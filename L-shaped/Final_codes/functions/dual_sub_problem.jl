function dual_sub_problem(Q_core, Y_core, L_core,
    Q_bar, Y_bar, L_bar, I_hat_bar, S_hat_bar, θ_expected,
    s_tilde, beta, κ, V, P_v, T, A, A_v, r_bar, m_segments, gurobi_solver_no_presolve, model_type)

    println("Building Pareto-optimal dual sub-problem with support constraint")

    dualsubproblem = JuMP.Model()
    JuMP.set_optimizer(dualsubproblem, gurobi_solver_no_presolve)

    @variable(dualsubproblem, π_2[v in V, p in P_v[v], t in T, tau in T] <= 0)
    @variable(dualsubproblem, π_3[p in P_v[v], t in T] <= 0)
    @variable(dualsubproblem, π_4[v in V, t in T])  # free
    @variable(dualsubproblem, π_5[a in A, t in T] <= 0)
    @variable(dualsubproblem, π_6[v in V])          # free
    @variable(dualsubproblem, π_7[a in A])          # free

    # need to check I and S for correct definition - PROBABLY NEED (t,tau) in F_time_set
    @objective(dualsubproblem, Max,
        sum(π_6[v] * I_hat_bar[v,0] for v in V) +
        sum(π_7[a] * S_hat_bar[a,0] for a in A) +
        sum(π_2[v,p,(t,tau)] * sum(Q_core[v,p,(t,tau),m] for m in m_segments) for v in V, p in P_v[v], t in T, tau in T) +
        sum(π_3[p,t] * (s_tilde[p,t] * Y_core[p,t] + sum(κ * L_core[p,l] for l in 1:t)) for p in P_v[v], t in T)
    )

    # Constraint (37): cut must support the current MP solution y^n
    @constraint(dualsubproblem,
        sum(π_6[v] * I_hat_bar[v] for v in V) +
        sum(π_7[a] * S_hat_bar[a] for a in A) +
        sum(π_2[v,p,t,tau] * sum(Q_bar[v,p,(t,tau),m] for m in m_segments) for v in V, p in P_v[v], t in T, tau in T) +
        sum(π_3[p,t] * (s_tilde[p,t] * Y_bar[p,t] + sum(κ * L_bar[p,l] for l in 1:t)) for p in P_v[v], t in T)
        == θ_expected
    )

    for v in V, p in P_v[v], t in T
        @constraint(dualsubproblem, sum(π_2[v,p,t,tau] for tau in T) + π_3[p,t] + π_4[v,t] <= 0)
    end

    for v in V, t in T
        @constraint(dualsubproblem, π_4[v,t] - π_4[v,t+1] <= 0)
    end

    if model_type == "UNICEF-GAVI" || model_type == "SOCIAL_BENEFIT"
        for a in A, t in T
            @constraint(dualsubproblem, -beta + π_5[a,t] - π_5[a,t+1] <= 0)
        end
    elseif model_type == "MAX_PROFIT"
        for a in A, t in T
            if t == maximum(T)
                for v in V
                    @constraint(dualsubproblem, π_5[a,t] - π_5[a,t+1] <= r_bar[v,t])
                end
            else
                @constraint(dualsubproblem, π_5[a,t] - π_5[a,t+1] <= 0)
            end
        end
    end

    for v in V, t in T
        @constraint(dualsubproblem, -π_4[v,t] + sum(π_5[a,t] for a in A_v[v]) <= 0)
    end

    return dualsubproblem
end
