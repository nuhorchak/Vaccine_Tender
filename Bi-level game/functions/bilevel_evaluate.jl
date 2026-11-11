#=
Step 2 of the build order: best-response check and optimistic bilevel evaluation of a fixed
leader decision x = (F, Π, Ω).

  1. φ_p(x): solve each producer's MILP on its own (the producers share no constraint).
  2. Optimistic tie-break: one MILP over every producer with profit_p ≥ φ_p(x) − tol,
     minimising the leader's cost. Its value is the bilevel cost of x, an upper bound on v^BL.
=#

"""
    best_response(d, p, Fx, Πx, Ωx, optimizer) -> (φ, model, producer)

Producer p's optimal profit φ_p(x) for a fixed leader decision.
"""
function best_response(d, p, Fx, Πx, Ωx, optimizer)
    model = Model(optimizer)
    set_silent(model)
    set_optimizer_attribute(model, "MIPGap", 0.0)      # φ_p must be exact: it becomes a constraint below
    prod = add_followers!(model, d, [p], Fx, Πx, Ωx)
    @objective(model, Max, prod[p].profit)
    optimize!(model)
    termination_status(model) == MOI.OPTIMAL || error("Best response of $p not optimal: $(termination_status(model))")
    return objective_value(model), model, prod[p]
end

"""
    evaluate_leader_decision(d, Fx, Πx, Ωx, optimizer; rel_tol = 1e-6) -> NamedTuple

Bilevel-feasible cost of x under the optimistic convention, with every producer at a best response.
"""
function evaluate_leader_decision(d, Fx, Πx, Ωx, optimizer; rel_tol = 1e-6)
    φ = Dict{String,Float64}()
    for p in d.P
        φ[p], _, _ = best_response(d, p, Fx, Πx, Ωx, optimizer)
    end

    model = Model(optimizer)
    set_silent(model)
    add_leader_state!(model, d)
    producers = add_followers!(model, d, collect(d.P), Fx, Πx, Ωx)
    add_inventory_balance!(model, d)
    for p in d.P
        @constraint(model, producers[p].profit >= φ[p] - rel_tol * max(1.0, abs(φ[p])))
    end
    terms = leader_cost_terms(model, d, Fx, producers)
    @objective(model, Min, terms.total)
    optimize!(model)
    termination_status(model) == MOI.OPTIMAL || error("Optimistic evaluation not optimal: $(termination_status(model))")

    return (cost = objective_value(model), φ = φ, model = model, producers = producers, terms = terms)
end

"""
    leader_decision_values(model) -> (Fx, Πx, Ωx)

Rounded leader decisions from a solved model that contains F, Π, Ω.
"""
leader_decision_values(model) = (round.(value.(model[:F])), round.(value.(model[:Π])), round.(value.(model[:Ω])))

"""
    leader_decision_from_ug(d, F_ug, W_ug) -> (Fx, Πx, Ωx)

Turns a single-level UG schedule into a leader decision so it can be evaluated against the producers'
true best responses: the calendar is UG's F, every open tender is priced at the reference level (λ = 1),
and producers UG had participate (W = 1) get the full award share (largest u); everyone else gets none.
"""
function leader_decision_from_ug(d, F_ug, W_ug)
    FT = d.F_time_set
    k_ref = findfirst(==(1.0), d.λ)
    k_ref === nothing && error("Price ladder has no λ = 1.0 level; cannot price the UG schedule at r̄.")
    j_full = argmax(d.u)

    Fx = JuMP.Containers.DenseAxisArray(zeros(length(d.A), length(FT)), d.A, FT)
    for a in d.A, tt in FT
        Fx[a, tt] = round(value(F_ug[a, tt]))
    end
    Πx = JuMP.Containers.DenseAxisArray(zeros(length(d.V), length(d.T), length(d.Kset)), d.V, d.T, d.Kset)
    for v in d.V, t in d.T
        if any(Fx[a, tt] > 0.5 for a in d.A_v[v] for tt in FT if tt[1] == t)
            Πx[v, t, k_ref] = 1.0
        end
    end
    Ωx = JuMP.Containers.DenseAxisArray(zeros(length(d.VP), length(FT), length(d.Jset)), d.VP, FT, d.Jset)
    for (v, p) in d.VP, tt in FT
        if sum(Fx[a, tt] for a in d.A_v[v]) > 0.5 && round(value(W_ug[p, tt])) > 0.5
            Ωx[(v, p), tt, j_full] = 1.0
        end
    end
    return Fx, Πx, Ωx
end

"""
    solve_ug_baseline(d, optimizer) -> model

The manuscript's single-level UG model (with ROI constraint (8), and (2), (6)) on the same data, built with
the unchanged `deterministic_equivalent` copied from the Segment Test code (one scenario, ω = 1).
"""
function solve_ug_baseline(d, optimizer)
    d_real_tilde = Dict((a, t, 1) => d.d_at[(a, t)] for a in d.A, t in d.T)
    s_real_tilde = Dict((p, t, 1) => d.s_pt[(p, t)] for p in d.P, t in d.T)
    start_I = [(v, d.I0[v]) for v in d.V]
    start_S = [(a, d.S0[a]) for a in d.A]
    # same bracket menu as the bilevel model; the 1e35 sentinel is capped at the largest commitment allowed by (7)
    cap = maximum((tt[2] - tt[1] + 1) * d.s_real[p] + d.L_hat_upper[p, tt] + d.L_check_upper[p, tt]
                  for p in d.P for tt in d.F_time_set)
    phi_upper = Dict((v, m) => min(d.phi_vm_upper[v, m], cap) for v in d.V for m in d.M)

    model = deterministic_equivalent(Dict(1 => 1.0), [1], d.g, d.beta, d.Γ, optimizer,
        d.A, d.A_p, d.F_time_set, d.V, d.P_v, d.T, d.T_initial, d.P, d.P_a, d.starting_F, start_I, start_S,
        true, true, d.L_lower_number, d.L_upper_number,
        d.κ, d.s_real, d.L_hat_upper, d.L_check_upper, d_real_tilde, d.X_tilde_upper, s_real_tilde, 1,
        d.r, d.r_avg, d.h, d.V_p, d.l, d.f_profit, d.V_a, d.delta, d.L_ddot_upper, true, nothing, nothing,
        d.m_segments, d.zeta_vm, d.phi_vm_lower, phi_upper, false, false, true)
    set_silent(model)
    optimize!(model)
    return model
end
