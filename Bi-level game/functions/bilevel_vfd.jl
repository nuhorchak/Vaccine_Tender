#=
Step 4 of the build order: value-function decomposition (Zeng & An 2014; Yue, Gao, Zeng & You 2019).

Master = HPR (44) + for each producer p a variable η_p ≤ π_p(x, y_p) that under-approximates the value
function φ_p(x), built from best responses found so far.

Why the cuts are exact here. The leader decision x = (F, Π, Ω) enters producer p's problem only through
three right-hand sides, all non-decreasing in x:
    (34) W[p,tt]       ≤ Σ_{a∈A_p} F[a,tt]
    (35) Σ_m Q[v,p,tt,m] ≤ D_vtt Σ_j u_j Ω[(v,p),tt,j]
    (38) Qk[v,p,tt,m,k] ≤ D_vtt Π[v,t,k]
and the producer objective does not depend on x. So a response ŷ computed at x̂ stays feasible at every x
that keeps the specific entries ŷ uses:
    F[a*,tt] = 1 for each tender ŷ joins (a* an antigen of p tendered at x̂),
    Σ_{j : u_j D ≥ Q̂} Ω[(v,p),tt,j] = 1 for each (v,tt) where ŷ commits Q̂ > 0,
    Π[v,t,k] = 1 for each price level ŷ sells at.
When all hold, φ_p(x) ≥ π̂ = π_p(ŷ). Writing viol(x) for the number of violated conditions (each term is
0/1 by (27), (29) and binarity), the cut is
    η_p ≥ φ⁰_p + (π̂ − φ⁰_p)(1 − viol(x)),
with φ⁰_p = φ_p(x = 0) a global lower bound on φ_p (by the same monotonicity). It is tight at x̂, so the
master's candidate x̂ is cut off unless its producers are already at a best response. x is binary, so the
loop terminates finitely; the master value is a lower bound and every candidate's optimistic evaluation an
upper bound on v^BL.
=#

"""
    zero_leader_decision(d) -> (Fx, Πx, Ωx) with every entry 0
"""
function zero_leader_decision(d)
    FT = d.F_time_set
    Fx = JuMP.Containers.DenseAxisArray(zeros(length(d.A), length(FT)), d.A, FT)
    Πx = JuMP.Containers.DenseAxisArray(zeros(length(d.V), length(d.T), length(d.Kset)), d.V, d.T, d.Kset)
    Ωx = JuMP.Containers.DenseAxisArray(zeros(length(d.VP), length(FT), length(d.Jset)), d.VP, FT, d.Jset)
    return Fx, Πx, Ωx
end

"""
    response_conditions(d, p, Fx, brm; tol) -> (F_conds, Ω_conds, Π_conds)

Leader entries that keep producer p's best response (solved in model `brm` at x̂ = Fx, ...) feasible.
"""
function response_conditions(d, p, Fx, brm; tol = 1e-6)
    W, Q, Qk = brm[:W], brm[:Q], brm[:Qk]
    F_conds = Tuple{String,Tuple{Int,Int}}[]
    Ω_conds = Tuple{Tuple{String,String},Tuple{Int,Int},Vector{Int}}[]
    # price levels: the same quantities can be sold at whichever level is open at (v,t) (relabelling Qk),
    # so the condition is Σ_k Π[v,t,k] = 1 and the revenue at level k enters the cut. rev[(v,t)][k] = revenue
    # of ŷ's (v,t) quantities if priced at level k.
    Π_conds = Dict{Tuple{String,Int},Vector{Float64}}()
    for tt in d.F_time_set
        value(W[p, tt]) > 0.5 || continue
        i = findfirst(a -> Fx[a, tt] > 0.5, d.A_p[p])
        i === nothing && error("Producer $p joins $tt but no antigen of $p is tendered there")
        push!(F_conds, (d.A_p[p][i], tt))
    end
    for (v, q) in d.VP
        q == p || continue
        for tt in d.F_time_set
            Dvt = d.D_hat[(v, tt)]
            Qsum = sum(value(Q[(v, p), tt, m]) for m in d.M)
            if Qsum > tol
                J = [j for j in d.Jset if d.u[j] * Dvt >= Qsum - tol * max(1.0, Dvt)]
                isempty(J) && error("No award share covers $Qsum for ($v,$p,$tt)")
                push!(Ω_conds, ((v, p), tt, J))
            end
            t = tt[1]
            for m in d.M
                qm = sum(value(Qk[(v, p), tt, m, k]) for k in d.Kset)
                qm > tol || continue
                rev = get!(Π_conds, (v, t), zeros(length(d.Kset)))
                for k in d.Kset
                    rev[k] += d.ρ[(v, t, k)] * (1 - d.zeta_vm[v, m]) / d.delta[t] * qm
                end
            end
        end
    end
    return F_conds, Ω_conds, Π_conds
end

"""
    add_vf_cut!(master, d, p, π̂, Πx, φ0, conds) -> constraint

η_p ≥ π̂ + Σ_{(v,t),k} Δ_vtk Π[v,t,k] − M·viol(x), with Δ_vtk = revenue of ŷ's (v,t) quantities at level k
minus at the level used at x̂ (Πx). When viol = 0 the RHS is the profit of ŷ relabelled to the open price
levels, a feasible response; M = π̂ + Σ max_k Δ⁺ − φ⁰ makes the RHS ≤ φ⁰ when any condition fails.
"""
function add_vf_cut!(master, d, p, π̂, Πx, φ0, conds)
    F, Π, Ω, η = master[:F], master[:Π], master[:Ω], master[:η]
    F_conds, Ω_conds, Π_conds = conds
    Δ = Dict{Tuple{String,Int,Int},Float64}()
    for ((v, t), rev) in Π_conds
        k̂ = findfirst(k -> Πx[v, t, k] > 0.5, d.Kset)
        k̂ === nothing && error("Producer $p sells ($v,$t) but no price level is open at x̂")
        for k in d.Kset
            Δ[(v, t, k)] = rev[k] - rev[k̂]
        end
    end
    max_gain = sum(maximum(Δ[(v, t, k)] for k in d.Kset) for (v, t) in keys(Π_conds); init = 0.0)
    M = π̂ + max_gain - φ0
    viol = @expression(master,
        sum((1 - F[a, tt]) for (a, tt) in F_conds; init = 0.0) +
        sum((1 - sum(Ω[vp, tt, j] for j in J)) for (vp, tt, J) in Ω_conds; init = 0.0) +
        sum((1 - sum(Π[v, t, k] for k in d.Kset)) for (v, t) in keys(Π_conds); init = 0.0))
    relabel = @expression(master, sum(Δ[key] * Π[key...] for key in keys(Δ); init = 0.0))
    return @constraint(master, η[p] >= π̂ + relabel - M * viol)
end

"""
    solve_vfd(d, optimizer; max_iter, time_limit, gap_tol, master_gap, rel_tol, verbose) -> NamedTuple

Value-function decomposition. Returns the best leader decision, bounds and an iteration log.
"""
function solve_vfd(d, optimizer; max_iter::Int = 200, time_limit::Real = 3600.0, gap_tol::Real = 1e-4,
                   master_gap::Real = 1e-5, rel_tol::Real = 1e-6, verbose::Bool = true)
    t_start = time()
    elapsed() = time() - t_start

    # φ⁰_p: producer value at x = 0, a lower bound on φ_p(x) for every x
    Z0 = zero_leader_decision(d)
    φ0 = Dict(p => best_response(d, p, Z0..., optimizer)[1] for p in d.P)

    master, producers, terms = build_hpr(d, optimizer)
    set_silent(master)
    set_optimizer_attribute(master, "MIPGap", master_gap)
    @variable(master, η[p in d.P] >= φ0[p])
    @constraint(master, vf[p in d.P], producers[p].profit >= η[p])

    LB, UB = -Inf, Inf
    best = nothing
    log = Dict{String,Any}[]
    seen = Set{UInt}()
    n_cuts = 0
    status = :iteration_limit
    for it in 1:max_iter
        remaining = time_limit - elapsed()
        remaining <= 0 && (status = :time_limit; break)
        set_time_limit_sec(master, remaining)
        optimize!(master)
        primal_status(master) == MOI.FEASIBLE_POINT || (status = :time_limit; break)
        LB = max(LB, objective_bound(master))
        master_obj = objective_value(master)
        Fx, Πx, Ωx = leader_decision_values(master)

        key = hash((Array(Fx), Array(Πx), Array(Ωx)))
        repeat = key in seen
        push!(seen, key)

        # producers' best responses at the candidate (independent MILPs) and new cuts
        prof = Dict(p => value(producers[p].profit) for p in d.P)   # read before cuts modify the master
        φ = Dict{String,Float64}()
        n_new = 0
        for p in d.P
            φ[p], brm, _ = best_response(d, p, Fx, Πx, Ωx, optimizer)
            if prof[p] < φ[p] - rel_tol * max(1.0, abs(φ[p]))
                add_vf_cut!(master, d, p, φ[p], Πx, φ0[p], response_conditions(d, p, Fx, brm))
                n_new += 1
            end
        end
        n_cuts += n_new

        # upper bound: candidate's optimistic bilevel cost (producers at best responses)
        if n_new == 0
            cand = master_obj            # master's own responses are best responses: bilevel feasible
        else
            ev = evaluate_leader_decision(d, Fx, Πx, Ωx, optimizer; φ, time_limit = max(1.0, time_limit - elapsed()))
            cand = ev.cost
        end
        if cand < UB
            UB = cand
            best = (Fx = Fx, Πx = Πx, Ωx = Ωx, φ = φ, iteration = it)
        end
        gap = (UB - LB) / max(1.0, abs(UB))
        push!(log, Dict("iteration" => it, "master" => master_obj, "LB" => LB, "candidate" => cand, "UB" => UB,
                        "gap" => gap, "new_cuts" => n_new, "repeat" => repeat, "time" => elapsed()))
        verbose && println("it $(lpad(it, 3))  LB $(round(LB, digits = 1))  candidate $(round(cand, digits = 1))  ",
                           "UB $(round(UB, digits = 1))  gap $(round(100gap, digits = 3)) %  cuts +$n_new  ",
                           "$(round(elapsed(), digits = 1)) s")
        n_new == 0 && (status = :optimal; break)     # optimal up to the master's MIP gap
        repeat && @warn "Candidate repeated at iteration $it although cuts were added; check cut validity"
        gap <= gap_tol && (status = :optimal; break)
    end
    return (status = status, LB = LB, UB = UB, gap = (UB - LB) / max(1.0, abs(UB)), best = best,
            log = log, n_cuts = n_cuts, φ0 = φ0, time = elapsed(), master = master)
end
