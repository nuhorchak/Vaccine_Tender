
function sub_problem(F_bar, W_bar, Y_bar, Q_bar, L_bar, L_ddot_bar, K_ddot_bar, ω, beta, f_profit, delta, r_avg, gurobi_solver_no_presolve,
    V, P_v, T, T_initial, A, P, F_time_set, tmin, V_p, X_tilde_upper, s_real, s_real_tilde, d_real_tilde, V_a, starting_points_vect_I, 
    starting_points_vect_S, r, h, l, zeta_vm, m_segments, κ, UNICEF_MODEL, social_benefit, max_profit)

    println("Building sub problem")


    Subproblem = JuMP.Model()
    JuMP.set_optimizer(Subproblem, gurobi_solver_no_presolve)

    @variable(Subproblem, X[v in V, p in P_v[v], t in T] >= 0)
    @variable(Subproblem, I[v in V, t in T_initial] >= 0)
    @variable(Subproblem, Vc[v in V, t in T] >= 0)
    @variable(Subproblem, S[a in A, t in T_initial] >= 0)
    # @variable(Subproblem, X_inf[p in P, t in T] >= 0)
    @variable(Subproblem, X_tilde[v in V, p in P_v[v], (t,tau) in F_time_set] >= 0)
    @variable(Subproblem, K[v in V, p in P_v[v], (t,tau) in F_time_set] >= 0)

    # CONDITIONS: ALL use capacity extension

    # UNICEF model - base model used, calculated from the perspective of UNICEF-GAVI

    # social benefit - mods to OBJ funs (MP and SP), calcualted to minimize missed doses

    # max profit - mods to OBJ funs (MP and SP), calcualted from the perspective of producers (et. al)
    
    if UNICEF_MODEL  #base model
        println("Condition: Base model")
        @objective(Subproblem, Min, sum(beta * S[a, t] / delta[t] for a in A, t in T)
        + sum(h[v] * r_avg[v, t] * I[v, t] / delta[t] for v in V, t in T)
        )
    elseif social_benefit #min unvax model
        println("Condition: Min Unvax Model")
        @objective(Subproblem, Min, sum(beta * S[a, t] / delta[t] for a in A, t in T)
        )
    else max_profit #max profit
        println("Condition: Max Profit model")
        @objective(Subproblem, Min, sum(r_avg[v,t]* S[a, t]/ delta[t] for a in A, t = last(T), v in V))
    end

    cons_14 = []
    cons_15 = []
    cons_16 = []
    cons_17 = []
    cons_18 = []
    cons_19 = []

    # constraint 14 - non McCormack
    for v in V
        for p in P_v[v]
            for t in T
                for tau in T
                    if (t,tau) in F_time_set
                        c = @constraint(Subproblem, sum(Q_bar[v,p,(t, tau),m] for m in keys(m_segments)) >= W_bar[p,(t,tau)] * sum(X[v,p,l] for l in t:tau))
                        set_name(c, "c_14[$((v,p,(t,tau)))]")
                        push!(cons_14, c)
                    end
                end
            end
        end
    end

    # Constraint (15) - non McCormick
    for p in P
        for t in T
            c = @constraint(Subproblem, sum(X[v,p,t] for v in V_p[p]) <= Y_bar[p,t] * (s_real_tilde[p, t, ω] + (sum(κ * s_real[p] * L_bar[p, l] for l in 1:t))))
            set_name(c, "c_15[$((p,t))]")
            push!(cons_15, c)
        end
    end

    # Constraint (16)
    for v in V
        for t in T
            # if t >= tmin
                c = @constraint(Subproblem, I[v, t-1] + sum(X[v, p, t] for p in P_v[v]) == Vc[v, t] + I[v, t])
                set_name(c, "c_16[$((v,t))]")
                push!(cons_16, c)
                # print(c)
            # end
        end
    end

    # Constraint (17)
    for a in A
        for t in T
            # if t >= tmin
                c = @constraint(Subproblem, d_real_tilde[a, t, ω] - sum(Vc[v, t] for v in V_a[a]) + S[a, t-1] <= S[a, t])
                set_name(c, "c_17[$((a,t))]")
                push!(cons_17, c)
            # end
        end
    end

    # Constraint (18)
    for i in 1:length(starting_points_vect_I)
        v = starting_points_vect_I[i][1]
        amount = starting_points_vect_I[i][2]
        # println("V: $v, amount: $amount")
        c = @constraint(Subproblem, I[v,0] == amount)
        set_name(c, "c_18[$v]")
        push!(cons_18, c)
    end

    # Constraint (19)
    for i in 1:length(starting_points_vect_S)
        a = starting_points_vect_S[i][1]
        amount = starting_points_vect_S[i][2]
        # println("S_hat value: $amount")
        c = @constraint(Subproblem, S[a,0] == amount)
        set_name(c, "c_19[$a]")
        push!(cons_19, c)
    end

    return Subproblem, cons_14, cons_15, cons_16, cons_17, cons_18, cons_19
end