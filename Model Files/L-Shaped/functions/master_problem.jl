"""
Master Problem Initialization Function

This function sets up and initializes the Master Problem for a mathematical optimization 
model using the JuMP package and Gurobi solver. It creates variables, objective functions, 
and constraints based on the given input parameters and conditions.

Parameters:
- `A`: Set of all antigens.
- `F_time_set`: Set of time intervals for F variables.
- `V`: Set of all vaccines.
- `P_v`: Dictionary mapping each vaccine to its associated producer.
- `P`: Set of all producers.
- `T`: Set of time periods.
- `L_lower_number`: Lower bound for the L variable.
- `L_upper_number`: Upper bound for the L variable.
- `Ω_test_partial_2`: Set of partial scenarios for θ variables.
- `Ω_test_partial_1`: Set of partial scenarios for θ variables.
- `T_initial`: Initial set of time periods.
- `starting_points_vect_I`: Starting values for I variables, as a vector of tuples.
- `starting_points_vect_S`: Starting values for S variables, as a vector of tuples.
- `starting_points_vect_F`: Starting values for F variables, as a vector of tuples.
- `UNICEF_MODEL`: Boolean indicating whether to use the UNICEF model.
- `capacity_extension_decision`: Boolean indicating whether capacity extension is considered.
- `gurobi_solver`: Gurobi optimizer to be used for the problem.

Returns:
- A JuMP model (`Masterproblem`) that contains all variables, constraints, and the objective 
  function based on the specified conditions.
"""

function master_problem(Masterproblem, A, F_time_set, V, P_v, P, T, L_lower_number, L_upper_number, 
    Ω_test_partial_2, Ω_test_partial_1, T_initial, starting_points_vect_I, 
    starting_points_vect_S, starting_points_vect_F, UNICEF_MODEL, 
    capacity_extension_decision, Γ, g, beta, delta, p_ω_test, r, h, r_avg, 
    partial_scenario, P_a, gurobi_solver, κ, s_real, L_hat_upper, L_check_upper, V_p, 
    X_tilde_upper, A_p, s_real_tilde, d_real_tilde, tmin, f_profit, V_a, L_ddot_upper, l, 
    overlap_decision, m_segments, zeta_vm, phi_vm_lower, phi_vm_upper, social_benefit, max_profit)

    println("Building master problem")

    @variable(Masterproblem, 0.0 <= F[a in A, (t, tau) in F_time_set] <= 1.0, Bin)
    @variable(Masterproblem, Q[v in V, p in P_v[v], (t, tau) in F_time_set, m in keys(m_segments)] >= 0)
    @variable(Masterproblem, 0.0 <= Y[p in P, t in T] <= 1.0, Bin)
    @variable(Masterproblem, 0.0 <= W[p in P, (t, tau) in F_time_set] <= 1.0, Bin)
    @variable(Masterproblem, L_lower_number <= L[p in P, t in T] <= L_upper_number, Int)
    @variable(Masterproblem, L_hat[p in P, (t, tau) in F_time_set] >= 0)
    @variable(Masterproblem, K_hat[p in P, (t, tau) in F_time_set] >= 0)
    @variable(Masterproblem, L_check[p in P, (t, tau) in F_time_set] >= 0)
    @variable(Masterproblem, K_check[p in P, (t, tau) in F_time_set] >= 0)
    @variable(Masterproblem, L_ddot[p in P, t in T] >= 0)
    @variable(Masterproblem, K_ddot[p in P, t in T] >= 0)
    @variable(Masterproblem, theta[ω in Ω_test_partial_2] >= 0)
    @variable(Masterproblem, X[v in V, p in P_v[v], t in T, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, X_tilde[v in V, p in P_v[v], (t,tau) in F_time_set, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, K[v in V, p in P_v[v], (t,tau) in F_time_set, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, I[v in V, t in T_initial, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, Vc[v in V, t in T, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, S[a in A, t in T_initial, ω in Ω_test_partial_1] >= 0)
    # @variable(Masterproblem, 0.0 <= Z[v in V, p in P_v[v], t in T, m in keys(m_segments)] <= 1, Bin)
    @variable(Masterproblem, 0 <= Z[v in V, p in P_v[v], t in T, m in keys(m_segments)] <= 1.0, Bin)

 

    ################################################### MASTER PROBLEM ####################################################

    #CONDITIONS: ALL use capacity extension

    # UNICEF model - base model used, calculated from the perspective of UNICEF-GAVI

    # social benefit - mods to OBJ funs (MP and SP), calcualted to minimize missed doses

    # max profit - mods to OBJ funs (MP and SP), calcualted from the perspective of producers (et. al)

    if UNICEF_MODEL && capacity_extension_decision #objective function is incorrect
        println("UNICEF-GAVI model with capacity extension/discounts")
        @objective(Masterproblem, Min, sum(g[t] * F[a, (t, tau)] / delta[t] for (t, tau) in F_time_set, a in A if (a,t,tau) ∉ starting_points_vect_F) +
        sum(r_avg[v,t] * (1 - zeta_vm[v,m]) * Q[v,p,(t, tau),m] / delta[t] for (t,tau) in F_time_set, v in V, p in P_v[v], m in keys(m_segments)) +
        + sum(p_ω_test[ω]*theta[ω] for ω in Ω_test_partial_2)
        
            + p_ω_test[partial_scenario] * (
                sum(beta * S[a,t,ω] / delta[t] for a in A, t in T, ω in Ω_test_partial_1)
                + sum(h[v] * r_avg[v,t] * I[v,t,ω] / delta[t] for v in V, t in T, ω in Ω_test_partial_1)
                )
        )

    elseif social_benefit && capacity_extension_decision
        println("Social benefit model with capacity extension/discounts")
        @objective(Masterproblem, Min, sum(p_ω_test[ω]*theta[ω] for ω in Ω_test_partial_2)
        
            + p_ω_test[partial_scenario] * (
                sum(beta * S[a,t,ω] / delta[t] for a in A, t in T, ω in Ω_test_partial_1)
                )
        )

    else max_profit && capacity_extension_decision
        println("Max profit model with capacity extension/discounts")
        @objective(Masterproblem, Min, sum((-r_avg[v,t]*(1-zeta_vm[v,m])*Q[v,p,(t,tau),m]) / delta[t] for (t,tau) in F_time_set, v in V, p in P_v[v], m in keys(m_segments)) +
        sum((Γ[p] * L[p, t]) / delta[t] for p in P, t in T) +
        sum((f_profit[v,p,t]* Y[p,t]) / delta[t] for v in V, p in P_v[v], t in T) +
        sum(p_ω_test[ω]*theta[ω] for ω in Ω_test_partial_2)
        
            + p_ω_test[partial_scenario] * (
                sum((r_avg[v,t]*S[a,t,ω]) / delta[t] for a in A, v in V, t = last(T), ω in Ω_test_partial_1)
                )
        )

    end


    # Constraint (2)
    for a in A
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(Masterproblem, (tau - t + 1) * F[a, (t, tau)] <= sum(Y[p, l] for l in t:tau, p in P_a[a]))
                end
            end
        end
    end

    # Constraint (3)
    for a in A
        for t in T
            for tau in T
                if tau >= t
                    for t_prime in T
                        for tau_prime in T
                            if tau_prime >= t_prime
                                overlap_decision = (t == t_prime)
                                if overlap_decision == true
                                    if ((t, tau) in F_time_set) && ((t_prime, tau_prime) in F_time_set) && ((t, tau) != (t_prime, tau_prime))
                                        @constraint(Masterproblem, F[a, (t, tau)] + F[a, (t_prime, tau_prime)] <= 1)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    # Constraint (4)
    for a in A
        for t in T
            @constraint(Masterproblem, sum(F[a, (l, k)] for (l, k) in F_time_set if t >= l && t <= k) >= 1)
        end
    end

    # Constraint (5)
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(Masterproblem, sum(F[a, (t, tau)] for a in A_p[p]) >= W[p, (t, tau)])
                end
            end
        end
    end

    # Constraint (6)
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(Masterproblem, sum(F[a, (t, tau)] for a in A_p[p]) <= length(A_p) * W[p, (t, tau)])
                end
            end
        end
    end

    # Constraint (7) - McCormick
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(Masterproblem, sum(Q[v, p, (t, tau), m] for v in V_p[p], m in keys(m_segments)) <= W[p,(t,tau)]*sum(s_real[p] for l in t:tau) + K_hat[p,(t,tau)] + K_check[p,(t,tau)])
                    # c7_1 = @constraint(Masterproblem, sum(Q[v, p, (t, tau), m] for v in V_p[p], m in keys(m_segments)) <= W[p,(t,tau)]*((tau-l+1)*s_real[p]) + K_hat[p,(t,tau)] + K_check[p,(t,tau)])
                    @constraint(Masterproblem, L_hat[p,(t,tau)] == sum((tau-l+1)*κ*s_real[p]*L[p,l] for l in t+1:tau))
                    @constraint(Masterproblem, K_hat[p,(t,tau)] >= L_hat[p,(t,tau)] + W[p,(t,tau)]*L_hat_upper[p,(t,tau)] - L_hat_upper[p,(t,tau)])
                    @constraint(Masterproblem, K_hat[p,(t,tau)] <= W[p,(t,tau)]*L_hat_upper[p,(t,tau)])
                    @constraint(Masterproblem, K_hat[p,(t,tau)] <= L_hat[p,(t,tau)])

                    @constraint(Masterproblem, L_check[p,(t,tau)] == sum((tau-t+1)*κ*s_real[p]*L[p,l] for l in 1:t))
                    @constraint(Masterproblem, K_check[p,(t,tau)] >= L_check[p,(t,tau)] + W[p,(t,tau)]*L_check_upper[p,(t,tau)] - L_check_upper[p,(t,tau)])
                    @constraint(Masterproblem, K_check[p,(t,tau)] <= W[p,(t,tau)]*L_check_upper[p,(t,tau)])
                    @constraint(Masterproblem, K_check[p,(t,tau)] <= L_check[p,(t,tau)])
                end
            end
        end
    end

    # Constraint (8) 
    if max_profit #ROI with prodiction capacity consideration for max profit
        for p in P
            for t in T
                # @constraint(Masterproblem, sum(r_avg[v,t] * (1 - zeta_vm[v,m]) for v in V_p[p], m in keys(m_segments)) * sum(Q[v, p, (t, tau), m] for (t, tau) in F_time_set )) >= sum((1 + l[v,p])*f[v,p,t]*Y[p,t] + Γ[p] * L[p, t] for v in V_p[p])
                # @constraint(Masterproblem, sum(r_avg[v,t] * (1 - zeta_vm[v,m]) * Q[v1, p, (t, tau), m1] for v in V_p[p], m in keys(m_segments), (t, tau) in F_time_set, v1 in V_p[p], m1 in eachindex(keys(m_segments))) >= sum((1 + l[v,p])*f[v,p,t]*Y[p,t] + Γ[p] * L[p, t] for v in V_p[p]))
                sum_expr = @expression(Masterproblem, sum(r_avg[v, t] * (1 - zeta_vm[v, m]) * Q[v, p, (t, tau), m] for v in V_p[p], m in keys(m_segments), (t,tau) in F_time_set))
                rhs_expr = @expression(Masterproblem, sum((1 + l[v,p])*f_profit[v,p,t]*Y[p,t] + Γ[p] * L[p, t] for v in V_p[p]))
                @constraint(Masterproblem, sum_expr >= rhs_expr)
            end
        end
    elseif UNICEF_MODEL #ROI without production capacity increases considered
        for p in P
            for t in T
                # @constraint(Masterproblem,
                # sum(r_avg[v,t] * (1 - zeta_vm[v,m] for v in V_p[p], m in keys(m_segments)) * sum(Q[v, p, (t, tau), m] for (t, tau) in F_time_set)) >= sum((1 + l[v,p]) * f[v,p,t] * Y[p,t] for v in V_p[p]) for v in V_p[p])
                # sum(r_avg[v,t] * (1 - zeta_vm[v,m]) * Q[v1, p, (t, tau), m1] for v in V_p[p], m in keys(m_segments), (t, tau) in F_time_set, v1 in V_p[p], m1 in eachindex(keys(m_segments))) >= sum((1 + l[v,p]) * f[v,p,t] * Y[p,t] for v in V_p[p]) for v in V_p[p]))
                sum_expr = @expression(Masterproblem, sum(r_avg[v, t] * (1 - zeta_vm[v, m]) * Q[v, p, (t, tau), m] for v in V_p[p], m in keys(m_segments), (t,tau) in F_time_set))
                rhs_expr = @expression(Masterproblem, sum((1 + l[v, p]) * f_profit[v, p, t] * Y[p, t] for v in V_p[p]))
                @constraint(Masterproblem, sum_expr >= rhs_expr)
            end
        end
    end

    # Constraint (9)
    for v in V
        for p in P_v[v]
            for t in T
                for m in keys(m_segments)
                    @constraint(Masterproblem, phi_vm_lower[v,m] * Z[v,p,t,m] <= sum(Q[v,p,(t,tau),m] for (t, tau) in F_time_set))
                end
            end
        end
    end
    

    # Constraint (10)
    for v in V
        for p in P_v[v]
            for t in T
                for m in keys(m_segments)
                    @constraint(Masterproblem, phi_vm_upper[v,m] * Z[v,p,t,m] >= sum(Q[v,p,(t,tau),m] for (t, tau) in F_time_set))
                end
            end
        end
    end

    # Constraint (11)
    for v in V
        for p in P_v[v]
            for t in T
                @constraint(Masterproblem, sum(Z[v,p,t,m] for m in keys(m_segments)) <= 1)
            end
        end
    end

    cons_14_1 = []
    cons_14_2 = []
    cons_14_3 = []
    cons_14_4 = []
    cons_14_5 = []
    cons_15_1 = []
    cons_15_2 = []
    cons_15_3 = []
    cons_15_4 = []
    cons_16 = []
    cons_17 = []
    cons_18 = []
    cons_19 = []
    cons_20 = []
    cons_21 = []
    
    #sub problem constraints
    # Constraint (14) - McCormick 
    for ω in Ω_test_partial_1
        for v in V
            for p in P_v[v]
                for t in T
                    for tau in T
                        if (t, tau) in F_time_set
                            c = @constraint(Masterproblem, X_tilde[v, p, (t, tau), ω] == sum(X[v, p, l, ω] for l in t:tau))
                            set_name(c, "master_c_14_1[$((v,p,(t,tau),ω))]")
                            push!(cons_14_1, c)

                            c = @constraint(Masterproblem, sum(Q[v, p, (t, tau), m]  for m in keys(m_segments)) >= K[v, p, (t, tau), ω])
                            set_name(c, "master_c_14_2[$((v,p,(t,tau),ω))]")
                            push!(cons_14_2, c)

                            c = @constraint(Masterproblem, K[v, p, (t, tau), ω] >= X_tilde_upper[v, p, (t, tau)] * W[p, (t, tau)] + X_tilde[v, p, (t, tau), ω] - X_tilde_upper[v, p, (t, tau)])
                            set_name(c, "master_c_14_3[$((v,p,(t,tau),ω))]")
                            push!(cons_14_3, c)

                            c = @constraint(Masterproblem, K[v, p, (t, tau), ω] <= X_tilde[v, p, (t, tau), ω])
                            set_name(c, "master_c_14_4[$((v,p,(t,tau),ω))]")
                            push!(cons_14_4, c)

                            c = @constraint(Masterproblem, K[v, p, (t, tau), ω] <= X_tilde_upper[v, p, (t, tau)] * W[p, (t, tau)])
                            set_name(c, "master_c_14_5[$((v,p,(t,tau),ω))]")
                            push!(cons_14_5, c)
                        end
                    end
                end
            end
        end
    end 

    # Constraint (15) - McCormick 
    for p in P
        for t in T
            c = @constraint(Masterproblem, L_ddot[p,t] == sum(κ * s_real[p] * L[p, l] for l in 1:t))
            set_name(c, "master_c_15_1[$((p,t))]")
            push!(cons_15_1, c)

            c = @constraint(Masterproblem, K_ddot[p,t] >= L_ddot[p,t] + Y[p,t] * L_ddot_upper[p,t] - L_ddot_upper[p,t])
            set_name(c, "master_c_15_2[$((p,t))]")
            push!(cons_15_2, c)

            c = @constraint(Masterproblem, K_ddot[p,t] <= Y[p,t] * L_ddot_upper[p,t])
            set_name(c, "master_c_15_3[$((p,t))]")
            push!(cons_15_3, c)

            c = @constraint(Masterproblem, K_ddot[p,t] <= L_ddot[p,t])
            set_name(c, "master_c_15_4[$((p,t))]")
            push!(cons_15_4, c)
        end
    end

    # Constraint (16)
    for ω in Ω_test_partial_1
        for p in P
            for t in T
                c = @constraint(Masterproblem, sum(X[v, p, t, ω] for v in V_p[p]) <= Y[p,t] * s_real_tilde[p,t,ω] + K_ddot[p,t])
                set_name(c, "master_c_16[$((p,t,ω))]")
                push!(cons_16, c)
            end
        end
    end

    # Constraint (17)
    for ω in Ω_test_partial_1
        for v in V
            for t in T
                if t >= tmin
                    c = @constraint(Masterproblem, I[v,t-1,ω] + sum(X[v, p, t, ω] for p in P_v[v]) == Vc[v,t,ω] + I[v,t,ω])
                    set_name(c, "master_c_17[$((v,t,ω))]")
                    push!(cons_17, c)
                end
            end
        end
    end

    # Constraint (18)
    for ω in Ω_test_partial_1
        for a in A
            for t in T
                if t >= tmin
                    c = @constraint(Masterproblem, d_real_tilde[a,t,ω] - sum(Vc[v,t,ω] for v in V_a[a]) + S[a,t-1,ω] <= S[a,t,ω])
                    set_name(c, "c_18[$((a,t,ω))]")
                    push!(cons_18, c)
                end
            end
        end
    end

    # Constraint (19) - Initial Inventory
    for ω in Ω_test_partial_1
        for (v, amount) in starting_points_vect_I
            c = @constraint(Masterproblem, I[v,0,ω] == amount)
            set_name(c, "master_c_19[$((v,ω))]")
            push!(cons_19, c)
        end
    end

    # Constraint (20) - Initial Shortage
    for ω in Ω_test_partial_1
        for (a, amount) in starting_points_vect_S
            c = @constraint(Masterproblem, S[a,0,ω] == amount)
            set_name(c, "master_c_20[$((a,ω))]")
            push!(cons_20, c)
        end
    end

    # Constraint (21) - Initial F Decision
    for (a, t, tau) in starting_points_vect_F
        c = @constraint(Masterproblem, F[a, (t, tau)] == 1)
        set_name(c, "master_c_21[$((a,t,tau))]")
        push!(cons_21, c)
    end


 
    return Masterproblem
end