function dual_sub_problem_main(Q_bar, Y_bar, L_bar, W_bar, K_ddot_bar, I_hat_bar, S_hat_bar, Z_S_omega, F_time_set, h, delta, Δ, starting_points_vect_I, starting_points_vect_S,
    s_tilde, d_tilde, s_bar, ω, beta, κ, V, P, P_v, V_p, T, A, A_v, r_bar, m_segments, gurobi_solver_no_presolve, model_type)

    println("Building dual sub-problem")

    dualsubproblem_main = JuMP.Model()
    JuMP.set_optimizer(dualsubproblem_main, gurobi_solver_no_presolve)

    # === DUAL VARIABLES (Renamed) ===
    @variable(dualsubproblem_main, ψ[v in V, p in P_v[v], (t, tau) in F_time_set] <= 0)  # replaces λ
    @variable(dualsubproblem_main, μ[p in P, t in T] <= 0)
    @variable(dualsubproblem_main, π[a in A, t in T] <= 0)
    @variable(dualsubproblem_main, η[v in V, t in T]) 
    @variable(dualsubproblem_main, χ[v in V]) 
    @variable(dualsubproblem_main, σ[a in A]) 

    @objective(dualsubproblem_main, Max,
    sum(χ[v] * I_hat_bar[v] for v in V) +
    sum(σ[a] * S_hat_bar[a] for a in A) +
    sum(ψ[v,p,(t,tau)] * sum(Q_bar[(v,p,(t,tau),m)] for m in keys(m_segments)) for v in V, p in P_v[v], (t,tau) in F_time_set) +
    sum(μ[p,t] * Y_bar[p,t] * (s_tilde[(p,t,ω)] + sum(κ * s_bar[p] * L_bar[p, l] for l in 1:t)) for p in P, t in T) +
    sum(π[a,t] * - d_tilde[a, t, ω] for a in A, t in T)
    )

    # # === CONSTRAINTS ===
    for v in V
        for p in P_v[v]
            for t in T
                # Calculate the upper limit for the inner sum
                t_plus_Delta = t + maximum(Δ)
                upper_limit_l = min(t_plus_Delta, maximum(T)) 
                # println("Outer Index: ($v, $p, $t)")
                c = @constraint(dualsubproblem_main,
                sum(
                    W_bar[p, (k, l)] * ψ[v, p, (k, l)]
                    for k in 1:t, l in t:upper_limit_l if (k, l) in F_time_set
                ) + μ[p, t] + η[v, t] <= 0 
                )
                # println(c)
            end
        end
    end

    # Dual constraint from V
    for v in V, t in T
        c = @constraint(dualsubproblem_main, -η[v,t] - sum(π[a, t] for a in A_v[v]) <= 0)
        set_name(c, "dual_c_V[$((v,t))]")
    end
      
    for v in V, t in T
        if t < maximum(T)
            c = @constraint(dualsubproblem_main,
                -η[v, t] + η[v, t+1] <= h[v] * r_bar[(v,t)] / delta[t]  #sum(h[v] for v in V)
            )
        else
            c = @constraint(dualsubproblem_main,
                -η[v, t] <= h[v] * r_bar[(v,t)] / delta[t]
            )
        end
        set_name(c, "dual_c_I[$((v,t))]")
    end

    for a in A, t in T
        if t < maximum(T)
            c = @constraint(dualsubproblem_main,
                -π[a, t] + π[a, t+1] <= beta / delta[t]  #sum(beta for a in A)
            )
        else
            c = @constraint(dualsubproblem_main,
                -π[a, t] <= beta / delta[t]
            )
        end
        set_name(c, "dual_c_S[$((a,t))]")
    end
    
    for v in V
        c = @constraint(dualsubproblem_main,
            χ[v] + η[v, 1] == 0
        )
        set_name(c, "dual_c_I0_link[$v]")
    end

    for a in A
        c = @constraint(dualsubproblem_main,
            σ[a] + π[a, 1] == 0
        )
        set_name(c, "dual_c_S0_link[$a]")
    end
    
    return dualsubproblem_main
end