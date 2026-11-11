#=
Model blocks for the deterministic bilevel tender game
("Bilevel tender game: model formulation", Oct 26 2026).

Equation tags in comments use the manuscript numbering, e.g. (7), (9)-(11), (13)-(16),
plus the bilevel labels from the companion note: (26)-(29) leader, (34)-(40) follower.

The producer block is written once and used three ways:
  * high-point relaxation (HPR): F, Π, Ω are leader variables in the same model
  * best response of producer p:  F, Π, Ω are fixed numbers, only producer p is built
  * optimistic evaluation:        F, Π, Ω fixed, every producer built, leader picks among optimal responses
Fx, Πx, Ωx may therefore be JuMP variable containers or containers of numbers with the same indexing:
  Fx[a, (t,τ)],  Πx[v, t, k],  Ωx[(v,p), (t,τ), j]
=#

"""
    add_leader_design!(model, d)

Leader decision variables F, Π, Ω and constraints (3), (4), (26)-(29).
Constraints (2) and (6) of the manuscript are intentionally NOT included.
"""
function add_leader_design!(model, d)
    FT = d.F_time_set
    @variable(model, F[a in d.A, tt in FT], Bin)
    @variable(model, Π[v in d.V, t in d.T, k in d.Kset], Bin)
    @variable(model, Ω[vp in d.VP, tt in FT, j in d.Jset], Bin)

    # (3) at most one tender start per antigen and period
    @constraint(model, c3[a in d.A, t in d.T], sum(F[a, tt] for tt in FT if tt[1] == t) <= 1)
    # (4) every period covered by a tender
    @constraint(model, c4[a in d.A, t in d.T], sum(F[a, tt] for tt in FT if tt[1] <= t <= tt[2]) >= 1)

    # (26) a price level only when a tender for one of v's antigens opens at t;  (27) one level
    for v in d.V, t in d.T
        @constraint(model, sum(Π[v, t, k] for k in d.Kset) <=
                           sum(F[a, tt] for a in d.A_v[v] for tt in FT if tt[1] == t))
        @constraint(model, sum(Π[v, t, k] for k in d.Kset) <= 1)
    end

    # (28) award share only in an open tender;  (29) one share level
    for (v, p) in d.VP, tt in FT
        @constraint(model, sum(Ω[(v, p), tt, j] for j in d.Jset) <= sum(F[a, tt] for a in d.A_v[v]))
        @constraint(model, sum(Ω[(v, p), tt, j] for j in d.Jset) <= 1)
    end

    # tenders already running at the start of the horizon (Starting_point.xlsx, F_start)
    for (a, t, τ) in d.starting_F
        @constraint(model, F[a, (t, τ)] == 1)
    end
    return model
end

"""
    add_leader_state!(model, d)

Leader state variables I, Vc, S with (15) missed doses and (16) initial stocks.
The inventory balance (14)/(30) needs follower deliveries and is added by `add_inventory_balance!`.
"""
function add_leader_state!(model, d)
    @variable(model, I[v in d.V, t in d.T_initial] >= 0)
    @variable(model, Vc[v in d.V, t in d.T] >= 0)
    @variable(model, S[a in d.A, t in d.T_initial] >= 0)

    # (15) cumulative missed doses
    @constraint(model, c15[a in d.A, t in d.T],
        d.d_at[(a, t)] - sum(Vc[v, t] for v in d.V_a[a]) + S[a, t-1] <= S[a, t])
    # (16) initial inventory and backlog
    @constraint(model, c16I[v in d.V], I[v, 0] == d.I0[v])
    @constraint(model, c16S[a in d.A], S[a, 0] == d.S0[a])
    return model
end

"""
    add_inventory_balance!(model, d)

(14)/(30): inventory balance driven by tender-indexed follower deliveries X[(v,p),(t',τ),t].
Requires every producer of every vaccine to be in the model.
"""
function add_inventory_balance!(model, d)
    I, Vc, X = model[:I], model[:Vc], model[:X]
    @constraint(model, c14[v in d.V, t in d.T],
        I[v, t-1] + sum(X[(v, p), tt, t] for p in d.P_v[v] for tt in d.F_time_set if tt[1] <= t <= tt[2])
        == Vc[v, t] + I[v, t])
    return model
end

"""
    add_followers!(model, d, Pset, Fx, Πx, Ωx) -> Dict(p => (revenue, cost, profit))

Producer variables and constraints for every p in `Pset`:
(34) commit only to open tenders, (35) award ceiling, (36) commit only if joined,
(37)-(38) exact price split of Q (Qk = Γ in the note), (39) deliveries equal commitments,
(7) commitment capacity and (13)/(40) per-period capacity with the McCormick terms of the
deterministic model, (9)-(11) discount brackets summed over windows starting at t.
"""
function add_followers!(model, d, Pset::Vector, Fx, Πx, Ωx)
    FT = d.F_time_set
    VPp = [(v, p) for (v, p) in d.VP if p in Pset]

    @variable(model, W[p in Pset, tt in FT], Bin)
    @variable(model, Y[p in Pset, t in d.T], Bin)
    @variable(model, d.L_lower_number <= L[p in Pset, t in d.T] <= d.L_upper_number, Int)
    @variable(model, L_ddot[p in Pset, t in d.T] >= 0)
    @variable(model, K_ddot[p in Pset, t in d.T] >= 0)
    @variable(model, L_hat[p in Pset, tt in FT] >= 0)
    @variable(model, K_hat[p in Pset, tt in FT] >= 0)
    @variable(model, L_check[p in Pset, tt in FT] >= 0)
    @variable(model, K_check[p in Pset, tt in FT] >= 0)
    @variable(model, Z[vp in VPp, t in d.T, m in d.M], Bin)
    @variable(model, Q[vp in VPp, tt in FT, m in d.M] >= 0)
    @variable(model, Qk[vp in VPp, tt in FT, m in d.M, k in d.Kset] >= 0)       # Γ_vptτmk in the note
    @variable(model, X[vp in VPp, tt in FT, l in tt[1]:tt[2]] >= 0)            # X_vptτl

    for p in Pset, tt in FT
        # (34) participate only in tenders opened for one of p's antigens
        @constraint(model, W[p, tt] <= sum(Fx[a, tt] for a in d.A_p[p]))

        # (7) commitment capacity, McCormick linearisation as in the deterministic model
        t, τ = tt
        @constraint(model, sum(Q[(v, p), tt, m] for v in d.V_p[p] for m in d.M) <=
                           W[p, tt] * (τ - t + 1) * d.s_real[p] + K_hat[p, tt] + K_check[p, tt])
        @constraint(model, L_hat[p, tt] == sum(((τ - l + 1) * d.κ * d.s_real[p]) * L[p, l] for l in t+1:τ))
        @constraint(model, K_hat[p, tt] >= L_hat[p, tt] + d.L_hat_upper[p, tt] * W[p, tt] - d.L_hat_upper[p, tt])
        @constraint(model, K_hat[p, tt] <= d.L_hat_upper[p, tt] * W[p, tt])
        @constraint(model, K_hat[p, tt] <= L_hat[p, tt])
        @constraint(model, L_check[p, tt] == sum(((τ - t + 1) * d.κ * d.s_real[p]) * L[p, l] for l in 1:t))
        @constraint(model, K_check[p, tt] >= L_check[p, tt] + d.L_check_upper[p, tt] * W[p, tt] - d.L_check_upper[p, tt])
        @constraint(model, K_check[p, tt] <= d.L_check_upper[p, tt] * W[p, tt])
        @constraint(model, K_check[p, tt] <= L_check[p, tt])
    end

    for (v, p) in VPp, tt in FT
        Dvt = d.D_hat[(v, tt)]
        Qsum = @expression(model, sum(Q[(v, p), tt, m] for m in d.M))
        # (35) award ceiling set by the leader's share
        @constraint(model, Qsum <= Dvt * sum(d.u[j] * Ωx[(v, p), tt, j] for j in d.Jset))
        # (36) commit only if joined
        @constraint(model, Qsum <= Dvt * W[p, tt])
        # (39) (12) as equality on tender-indexed deliveries
        @constraint(model, sum(X[(v, p), tt, l] for l in tt[1]:tt[2]) == Qsum)
        for m in d.M
            # (37) exact split of Q across price levels;  (38) only the chosen level is open
            @constraint(model, sum(Qk[(v, p), tt, m, k] for k in d.Kset) == Q[(v, p), tt, m])
            for k in d.Kset
                @constraint(model, Qk[(v, p), tt, m, k] <= Dvt * Πx[v, tt[1], k])
            end
        end
    end

    # (9)-(11) discount brackets: producers self-select from the announced menu
    for (v, p) in VPp, t in d.T
        for m in d.M
            Qtm = @expression(model, sum(Q[(v, p), tt, m] for tt in FT if tt[1] == t))
            @constraint(model, d.phi_vm_lower[v, m] * Z[(v, p), t, m] <= Qtm)               # (9)
            @constraint(model, d.phi_upper_cap[(v, t, m)] * Z[(v, p), t, m] >= Qtm)         # (10)
        end
        @constraint(model, sum(Z[(v, p), t, m] for m in d.M) == 1)                          # (11)
    end

    # (13)/(40) per-period capacity, deliveries summed over active windows
    for p in Pset, t in d.T
        @constraint(model, L_ddot[p, t] == sum((d.κ * d.s_real[p]) * L[p, l] for l in 1:t))
        @constraint(model, K_ddot[p, t] >= L_ddot[p, t] + d.L_ddot_upper[p, t] * Y[p, t] - d.L_ddot_upper[p, t])
        @constraint(model, K_ddot[p, t] <= d.L_ddot_upper[p, t] * Y[p, t])
        @constraint(model, K_ddot[p, t] <= L_ddot[p, t])
        @constraint(model,
            sum(X[(v, p), tt, t] for v in d.V_p[p] for tt in FT if tt[1] <= t <= tt[2]) <=
            d.s_pt[(p, t)] * Y[p, t] + K_ddot[p, t])
    end

    # producer objective pieces (MP objective (20) per producer + production cost), discounted like the DE model
    out = Dict{String,NamedTuple}()
    for p in Pset
        revenue = @expression(model,
            sum(d.ρ[(v, tt[1], k)] * (1 - d.zeta_vm[v, m]) / d.delta[tt[1]] * Qk[(v, p), tt, m, k]
                for v in d.V_p[p] for tt in FT for m in d.M for k in d.Kset))
        cost = @expression(model,
            sum(d.Γ[p] / d.delta[t] * L[p, t] for t in d.T) +
            sum(get(d.f_profit, (v, p, tt), 0.0) / d.delta[tt[1]] * W[p, tt] for v in d.V_p[p] for tt in FT) +
            sum(d.c[(v, p)] / d.delta[l] * X[(v, p), tt, l] for v in d.V_p[p] for tt in FT for l in tt[1]:tt[2]))
        out[p] = (revenue = revenue, cost = cost, profit = @expression(model, revenue - cost))
    end
    return out
end

"""
    leader_cost_terms(model, d, Fx, producers) -> NamedTuple of expressions

UG objective (1) with procurement priced at the chosen ladder level (= Σ_p producer revenue).
"""
function leader_cost_terms(model, d, Fx, producers)
    I, S = model[:I], model[:S]
    tender = @expression(model,
        sum(d.g[t] / d.delta[t] * Fx[a, (t, τ)] for a in d.A for (t, τ) in d.F_time_set if (a, t, τ) ∉ d.starting_F))
    procurement = @expression(model, sum(producers[p].revenue for p in keys(producers)))
    missed = @expression(model, sum(d.beta / d.delta[t] * S[a, t] for a in d.A for t in d.T))
    holding = @expression(model, sum(d.h[v] * d.r_avg[v, t] / d.delta[t] * I[v, t] for v in d.V for t in d.T))
    total = @expression(model, tender + procurement + missed + holding)
    return (; tender, procurement, missed, holding, total)
end

"""
    build_hpr(d, optimizer) -> (model, producers, leader_terms)

High-point relaxation (step 1): leader objective, leader constraints and every producer's
constraints in one MILP, producer optimality dropped. Its optimum is a lower bound on the bilevel cost.
"""
function build_hpr(d, optimizer)
    model = Model(optimizer)
    add_leader_design!(model, d)
    add_leader_state!(model, d)
    producers = add_followers!(model, d, collect(d.P), model[:F], model[:Π], model[:Ω])
    add_inventory_balance!(model, d)
    terms = leader_cost_terms(model, d, model[:F], producers)
    @objective(model, Min, terms.total)
    return model, producers, terms
end
