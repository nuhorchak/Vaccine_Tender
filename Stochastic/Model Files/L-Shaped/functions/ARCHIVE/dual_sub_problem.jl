function dual_sub_problem(Q_core, Y_core, L_core,
    Q_bar, Y_bar, L_bar, I_hat_bar, S_hat_bar, θ_expected, F_time_set,
    s_tilde, ω, beta, κ, V, P, P_v, T, A, A_v, r_bar, m_segments, gurobi_solver_no_presolve, model_type)

    println("Building Pareto-optimal dual sub-problem with support constraint")

    dualsubproblem = JuMP.Model()
    JuMP.set_optimizer(dualsubproblem, gurobi_solver_no_presolve)

    @variable(dualsubproblem, π_2[v in V, p in P_v[v], (t, tau) in F_time_set] <= 0)
    @variable(dualsubproblem, π_3[p in P, t in T] <= 0)
    @variable(dualsubproblem, π_4[v in V, t in T])  # free
    @variable(dualsubproblem, π_5[a in A, t in T] <= 0)
    @variable(dualsubproblem, π_6[v in V])          # free
    @variable(dualsubproblem, π_7[a in A])          # free

    # need to check I and S for correct definition - PROBABLY NEED (t,tau) in F_time_set
    @objective(dualsubproblem, Max,
        sum(π_6[v] * I_hat_bar[v] for v in V) +
        sum(π_7[a] * S_hat_bar[a] for a in A) +
        sum(π_2[v,p,(t,tau)] * sum(Q_core[v,p,(t,tau),m] for m in keys(m_segments)) for v in V, p in P_v[v], (t, tau) in F_time_set) +
        sum(π_3[p,t] * (s_tilde[p,t,ω] * Y_core[p,t] + sum(κ * L_core[p,l] for l in 1:t)) for p in P, t in T)
    )

    # Cut support constraint
    c = @constraint(dualsubproblem,
        sum(π_6[v] * I_hat_bar[v] for v in V) +
        sum(π_7[a] * S_hat_bar[a] for a in A) +
        sum(π_2[v,p,(t,tau)] * sum(Q_bar[v,p,(t,tau),m] for m in keys(m_segments)) for v in V, p in P_v[v], (t, tau) in F_time_set) +
        sum(π_3[p,t] * (s_tilde[p,t,ω] * Y_bar[p,t] + sum(κ * L_bar[p,l] for l in 1:t)) for p in P, t in T)
        == θ_expected
    )
    set_name(c, "support_cut")

    # π_2 + π_3 + π_4 ≤ 0
    for v in V, p in P_v[v], t in T
        c = @constraint(dualsubproblem,
            sum(π_2[v, p, (t, tau)] for (tt, tau) in F_time_set if tt == t) + π_3[p, t] + π_4[v, t] <= 0
        )
        set_name(c, "c_flow[$((v,p,t))]")
    end

    # π_4 inventory coupling
    for v in V, t in T
        if t < maximum(T)
            c = @constraint(dualsubproblem, π_4[v,t] - π_4[v,t+1] <= 0)
            set_name(c, "c_inventory_flow[$((v,t))]")
        else
            c = @constraint(dualsubproblem, π_4[v,t] <= 0)
            set_name(c, "c_inventory_terminal[$((v,t))]")
        end
    end

    # π_5 recurrence
    if model_type == "UNICEF-GAVI" || model_type == "SOCIAL_BENEFIT"
        for a in A, t in T
            if t < maximum(T)
                c = @constraint(dualsubproblem, -beta + π_5[a,t] - π_5[a,t+1] <= 0)
                set_name(c, "c_unvac_rec[$((a,t))]")
            else
                c = @constraint(dualsubproblem, -beta + π_5[a,t] <= 0)
                set_name(c, "c_unvac_terminal[$((a,t))]")
            end
        end
    elseif model_type == "MAX_PROFIT"
        for a in A, t in T
            if t < maximum(T)
                c = @constraint(dualsubproblem, π_5[a,t] - π_5[a,t+1] <= 0)
                set_name(c, "c_unvac_rec_profit[$((a,t))]")
            else
                for v in V
                    c = @constraint(dualsubproblem, π_5[a,t] <= r_bar[v,t])
                    set_name(c, "c_unvac_terminal_profit[$((a,t,v))]")
                end
            end
        end
    end

    # Supply/demand balance: π_4 - π_5 coupling
    for v in V, t in T
        c = @constraint(dualsubproblem, -π_4[v,t] + sum(π_5[a,t] for a in A_v[v]) <= 0)
        set_name(c, "c_supply_demand[$((v,t))]")
    end


    return dualsubproblem
end
