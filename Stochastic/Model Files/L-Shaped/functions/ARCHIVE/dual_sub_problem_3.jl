function dual_sub_problem(Q_core, Y_core, L_core, W_core, K_ddot_core,
    Q_bar, Y_bar, L_bar, W_bar, K_ddot_bar, I_hat_bar, S_hat_bar, θ_expected, F_time_set, h, delta, Δ,
    s_tilde, d_tilde, s_bar, ω, beta, κ, V, P, P_v, V_p, T, A, A_v, r_bar, m_segments, gurobi_solver_no_presolve, model_type)

    println("Building Pareto-optimal dual sub-problem with support constraint")

    dualsubproblem = JuMP.Model()
    JuMP.set_optimizer(dualsubproblem, gurobi_solver_no_presolve)

    # === DUAL VARIABLES ===
    @variable(dualsubproblem, ψ[v in V, p in P_v[v], (t, tau) in F_time_set] >= 0)
    @variable(dualsubproblem, μ[p in P, t in T] >= 0)
    @variable(dualsubproblem, π[a in A, t in T] >= 0)
    @variable(dualsubproblem, η[v in V, t in T])
    @variable(dualsubproblem, χ[v in V])
    @variable(dualsubproblem, σ[a in A])

    @objective(dualsubproblem, Max,
        sum(χ[v] * I_hat_bar[v] for v in V) +
        sum(σ[a] * S_hat_bar[a] for a in A) +
        sum(ψ[v, p, (t, tau)] * sum(Q_bar[(v, p, (t, tau), m)] for m in keys(m_segments)) for v in V, p in P_v[v], (t, tau) in F_time_set) +
        sum(μ[p, t] * (Y_bar[p, t] * s_tilde[(p, t, ω)] + (sum(κ * s_bar[p] * L_bar[p, l] for l in 1:t))) for p in P, t in T) + 
        sum(π[a, t] * d_tilde[a, t, ω] for a in A, t in T) 
    )

    # --- CONSTRAINTS ---
    for v in V, p in P_v[v], t in T
        psi_sum_term = sum(ψ[v, p, (t, tau)] * W_bar[p, (t, tau)] for tau in T if (t, tau) in F_time_set)
        c = @constraint(dualsubproblem, -psi_sum_term + μ[p, t] + η[v, t] <= 0)
        set_name(c, "dual_c_X[$((v, p, t))]")
    end


    for v in V, t in T
        c = @constraint(dualsubproblem, -η[v, t] - sum(π[a, t] for a in A_v[v]) <= 0)
        set_name(c, "dual_c_V[$((v,t))]")
    end

    for v in V, t in T
    if t == 1
        c = @constraint(dualsubproblem, 1/delta[t] * h[v] * r_bar[(v, t)] - η[v, t] + χ[v] <= 0)
    else
        c = @constraint(dualsubproblem, 1/delta[t] * h[v] * r_bar[(v, t)] - η[v, t] + η[v, t-1] <= 0)
    end
        set_name(c, "dual_c_I[$((v,t))]")
    end

    for a in A, t in T
        if t == 1
        c = @constraint(dualsubproblem,
        1/delta[t] * beta - π[a, t] + σ[a] <= 0
        )
        else
        c = @constraint(dualsubproblem,
        1/delta[t] * beta - π[a, t] + π[a, t-1] <= 0
        )
        end
        set_name(c, "dual_c_S[$((a,t))]")
    end

    for v in V
        c = @constraint(dualsubproblem, χ[v] <= 0)
        set_name(c, "dual_c_I0_link[$v]")
    end

    for a in A
        c = @constraint(dualsubproblem, σ[a] <= 0)
        set_name(c, "dual_c_S0_link[$a]")
    end


    return dualsubproblem
end