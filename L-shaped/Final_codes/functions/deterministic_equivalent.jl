"""
deterministic_equivalent(p_ω, Ω, F_bar, W_bar, Y_bar, L_bar)

Defines the deterministic equivalent model for a stochastic optimization problem. The model includes decision variables, objective function, and constraints, with specific conditions for capacity extension and vaccination strategies.

# Arguments
- `p_ω`: A dictionary representing the probability of each scenario (omega in Omega).
- `Ω`: The set of scenarios. (use random_scenarios)
- `F_bar`: A dictionary of fixed binary variables (F_at_tau), representing tender coverage for antigen (a) over periods (t) to (tau).
- `W_bar`: A dictionary of fixed binary variables (W_pt_tau), indicating producer (p)'s commitment for periods (t) to (tau).
- `Y_bar`: A dictionary of fixed binary variables (Y_pt), specifying whether producer (p) produces in period (t).
- `L_bar`: A dictionary of fixed integer variables (L_pt), representing capacity extensions for producer (p) in period (t).

# Outputs
- `model`: A JuMP model for the deterministic equivalent problem.

# Key Components
1. **Variables**:
   - (F), (W), (Y): Decision variables related to tender, commitments, and production.
   - (Q), (X), (X_tilde), (K): Variables representing procurement, delivery, and intermediate calculations.
   - (I), (Vc), (S): Variables for inventory, vaccine administration, and missed doses.
   - (L), (L_hat), (L_check): Capacity extension variables.

2. **Objective Function**:
   - Varies based on conditions:
     - **Base model**: Minimizes costs from the UNICEF perspective.
     - **Capacity extension**: Includes additional terms for capacity costs.
     - **Min unvaccinated**: Minimizes missed doses and infeasibility penalties.

3. **Constraints**:
   - (2)-(12): Cover tender coverage, overlap avoidance, capacity limits, inventory balance, unmet demand, and production feasibility.
   - Initial constraints ensure consistency with the fixed variables (F_bar, W_bar, Y_bar, L_bar).

4. **Conditions**:
   - The model adapts based on whether capacity extension decisions are included and whether the objective focuses on social benefit or profit maximization.

# Notes
- Uses the Gurobi solver via JuMP.
"""


function deterministic_equivalent(p_ω, Ω, g, beta, Γ, gurobi_solver_DE,
    A, A_p, F_time_set, V, P_v, T, T_initial, P, P_a, starting_points_vect_F, starting_points_vect_I, 
    starting_points_vect_S, capacity_extension_decision, UNICEF_MODEL, L_lower_number, L_upper_number,
    κ, s_real, L_hat_upper, L_check_upper, d_real_tilde, X_tilde_upper, s_real_tilde, tmin, 
    r, r_avg, h, V_p, l, f_profit, V_a, delta, L_ddot_upper, overlap_decision, Ω_test_partial_1, Ω_test_partial_2, m_segments,zeta_vm, phi_vm_lower, phi_vm_upper, social_benefit, max_profit)

        
    model = Model(gurobi_solver_DE)

    @variable(model, F[a in A, (t, tau) in F_time_set], Bin)
    @variable(model, Q[v in V, p in P_v[v], (t, tau) in F_time_set, m in keys(m_segments)] >= 0)
    @variable(model, X[v in V, p in P_v[v], t in T, ω in Ω] >= 0)
    @variable(model, X_tilde[v in V, p in P_v[v], (t, tau) in F_time_set, ω in Ω] >= 0)
    @variable(model, K[v in V, p in P_v[v], (t, tau) in F_time_set, ω in Ω] >= 0)
    @variable(model, Y[p in P, t in T], Bin)
    @variable(model, I[v in V, t in T_initial, ω in Ω] >= 0)
    @variable(model, Vc[v in V, t in T, ω in Ω] >= 0)
    @variable(model, S[a in A, t in T_initial, ω in Ω] >= 0)
    @variable(model, W[p in P, (t, tau) in F_time_set], Bin)
    @variable(model, L_lower_number <= L[p in P, t in T] <= L_upper_number, Int)
    @variable(model, L_ddot[p in P, t in T] >= 0)
    @variable(model, L_hat[p in P, (t, tau) in F_time_set] >= 0)
    @variable(model, L_check[p in P, (t, tau) in F_time_set] >= 0)
    @variable(model, K_ddot[p in P, t in T] >= 0)
    @variable(model, K_hat[p in P, (t, tau) in F_time_set] >= 0)
    @variable(model, K_check[p in P, (t, tau) in F_time_set] >= 0)
    @variable(model, Z[v in V, p in P_v[v], t in T, m in keys(m_segments)] >= 0, Bin) 

    ################################################### OBJECTIVE FUNCTION AND CONSTRAINTS ####################################################

    #CONDITIONS: ALL use capacity extension

    # UNICEF model - base model used, calculated from the perspective of UNICEF-GAVI

    #social benefit - mods to OBJ funs (MP and SP), calcualted to minimize missed doses
    if UNICEF_MODEL && capacity_extension_decision 
        println("UNICEF-GAVI model with capacity extension/discounts")
        @objective(model, Min, sum(g[t] * F[a, (t, tau)] / delta[t] for (t, tau) in F_time_set, a in A if (a,t,tau) ∉ starting_points_vect_F) +
        sum(r_avg[v,t] * (1 - zeta_vm[v,m]) * Q[v,p,(t, tau),m] / delta[t] for (t,tau) in F_time_set, v in V, p in P_v[v], m in keys(m_segments)) +
        sum(p_ω[ω] * beta * S[a,t,ω] / delta[t] for a in A, t in T, ω in Ω) +
        sum(p_ω[ω] * h[v] * r_avg[v,t] * I[v,t,ω] / delta[t] for v in V, t in T, ω in Ω)
    )

    elseif social_benefit && capacity_extension_decision
        println("Social benefit model with capacity extension/discounts")
        @objective(model, Min, sum(p_ω[ω] *beta * S[a,t,ω] / delta[t] for a in A, t in T, ω in Ω))

    else max_profit && capacity_extension_decision
        println("Max Profit model with capacity extension/discounts")
        @objective(model, Min, sum((-r_avg[v,t] * (1 - zeta_vm[v,m]) * Q[v,p,(t, tau),m]) / delta[t] for (t,tau) in F_time_set, v in V, p in P_v[v], m in keys(m_segments)) +
        sum((Γ[p] * L[p, t]) / delta[t] for p in P, t in T) +  
        sum((f_profit[v,p,t] * Y[p,t]) / delta[t] for v in V, p in P_v[v], t in T) +
        sum(p_ω[ω] * ((r_avg[v,t]*S[a,t,ω]) / delta[t]) for a in A, v in V, t = last(T), ω in Ω)
    )
    end


    # Constraint (2)
    for a in A
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(model, (tau - t + 1) * F[a, (t, tau)] <= sum(Y[p, l] for l in t:tau, p in P_a[a]))
                end
            end
        end
    end

    #removed overlap condition bool
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
                                        @constraint(model, F[a, (t, tau)] + F[a, (t_prime, tau_prime)] <= 1)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    # Constraint (4) - updated
    for a in A
        for t in T
            @constraint(model, sum(F[a, (l, k)] for (l, k) in F_time_set if t >= l && t <= k) >= 1)
        end
    end


    # Constraint (5)
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(model, sum(F[a, (t, tau)] for a in A_p[p]) >= W[p, (t, tau)])
                end
            end
        end
    end

    # Constraint (6)
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(model, sum(F[a, (t, tau)] for a in A_p[p]) <= length(A_p) * W[p, (t, tau)])
                end
            end
        end
    end

    # Constraint (7) - McCormick
    # if capacity_extension_decision - removed, always considered
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(model, sum(Q[v, p, (t, tau), m] for v in V_p[p], m in keys(m_segments)) <= W[p,(t,tau)]*sum(s_real[p] for l in t:tau) + K_hat[p,(t,tau)] + K_check[p,(t,tau)])
                    @constraint(model, L_hat[p,(t,tau)] == sum((tau-l+1)*κ*s_real[p]*L[p,l] for l in t+1:tau))
                    @constraint(model, K_hat[p,(t,tau)] >= L_hat[p,(t,tau)] + W[p,(t,tau)]*L_hat_upper[p,(t,tau)] - L_hat_upper[p,(t,tau)])
                    @constraint(model, K_hat[p,(t,tau)] <= W[p,(t,tau)]*L_hat_upper[p,(t,tau)])
                    @constraint(model, K_hat[p,(t,tau)] <= L_hat[p,(t,tau)])

                    @constraint(model, L_check[p,(t,tau)] == sum((tau-t+1)*κ*s_real[p]*L[p,l] for l in 1:t))
                    @constraint(model, K_check[p,(t,tau)] >= L_check[p,(t,tau)] + W[p,(t,tau)]*L_check_upper[p,(t,tau)] - L_check_upper[p,(t,tau)])
                    @constraint(model, K_check[p,(t,tau)] <= W[p,(t,tau)]*L_check_upper[p,(t,tau)])
                    @constraint(model, K_check[p,(t,tau)] <= L_check[p,(t,tau)])
                end
            end
        end
    end

     # Constraint (8) 
     if max_profit #ROI with prodiction capacity consideration for max profit - need to fix this
        for p in P
            for t in T
                # @constraint(model, sum(r_avg[v,t] * (1 - zeta_vm[v,m]) for v in V_p[p], m in m_segments) * sum(Q[v, p, (t, tau), m] for (t, tau) in F_time_set )) >= sum((1 + l[v,p])*f[v,p,t]*Y[p,t] + Γ[p] * L[p, t] for v in V_p[p])
                # @constraint(model, sum(r_avg[v,t] * (1 - zeta_vm[v,m]) * Q[v1, p, (t, tau), m1] for v in V_p[p], m in m_segments, (t, tau) in F_time_set, v1 in V_p[p], m1 in eachindex(m_segments)) >= sum((1 + l[v,p])*f[v,p,t]*Y[p,t] + Γ[p] * L[p, t] for v in V_p[p]))
                sum_expr = @expression(model, sum(r_avg[v, t] * (1 - zeta_vm[v, m]) * Q[v, p, (t, tau), m] for v in V_p[p], m in keys(m_segments), (t,tau) in F_time_set))
                rhs_expr = @expression(model, sum((1 + l[v,p])*f_profit[v,p,t]*Y[p,t] + Γ[p] * L[p, t] for v in V_p[p]))
                @constraint(model, sum_expr >= rhs_expr)
            end
        end
    elseif UNICEF_MODEL #ROI without production capacity increases considered
        for p in P
            for t in T
                # @constraint(model,
                # sum(r_avg[v,t] * (1 - zeta_vm[v,m] for v in V_p[p], m in m_segments) * sum(Q[v, p, (t, tau), m] for (t, tau) in F_time_set)) >= sum((1 + l[v,p]) * f[v,p,t] * Y[p,t] for v in V_p[p]) for v in V_p[p])
                # sum(r_avg[v,t] * (1 - zeta_vm[v,m]) * Q[v1, p, (t, tau), m1] for v in V_p[p], m in m_segments, (t, tau) in F_time_set, v1 in V_p[p], m1 in eachindex(m_segments)) >= sum((1 + l[v,p]) * f[v,p,t] * Y[p,t] for v in V_p[p]) for v in V_p[p]))
                sum_expr = @expression(model, sum(r_avg[v, t] * (1 - zeta_vm[v, m]) * Q[v, p, (t, tau), m] for v in V_p[p], m in keys(m_segments), (t,tau) in F_time_set))
                rhs_expr = @expression(model, sum((1 + l[v, p]) * f_profit[v, p, t] * Y[p, t] for v in V_p[p]))
                @constraint(model, sum_expr >= rhs_expr)
            end
        end
    end

    # Constraint (9)
    for v in V
        for p in P_v[v]
            for t in T
                for m in keys(m_segments)
                    @constraint(model, phi_vm_lower[v,m] * Z[v,p,t,m] <= sum(Q[v,p,(t,tau),m] for (t, tau) in F_time_set))
                end
            end
        end
    end
    

    # Constraint (10)
    for v in V
        for p in P_v[v]
            for t in T
                for m in keys(m_segments)
                    @constraint(model, phi_vm_upper[v,m] * Z[v,p,t,m] >= sum(Q[v,p,(t,tau),m] for (t, tau) in F_time_set))
                end
            end
        end
    end

    # Constraint (11)
    for v in V
        for p in P_v[v]
            for t in T
                @constraint(model, sum(Z[v,p,t,m] for m in keys(m_segments)) <= 1)
            end
        end
    end

    #sub problem constraints
    
    # Constraint (14) - McCormick
    for ω in Ω
        for v in V
            for p in P_v[v]
                for t in T
                    for tau in T
                        if (t,tau) in F_time_set
                            @constraint(model, X_tilde[v,p,(t,tau),ω] == sum(X[v,p,l,ω] for l in t:tau))
                            @constraint(model, sum(Q[v,p,(t,tau), m] for m in keys(m_segments)) >= K[v,p,(t,tau),ω])
                            @constraint(model, K[v,p,(t,tau),ω] >= X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)] + X_tilde[v,p,(t,tau),ω] - X_tilde_upper[v,p,(t,tau)])
                            @constraint(model, K[v,p,(t,tau),ω] <= X_tilde[v,p,(t,tau),ω])
                            @constraint(model, K[v,p,(t,tau),ω] <= X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)])
                        end
                    end
                end
            end
        end
    end

    # Constraint (15) McCormack
    for p in P
        for t in T
            @constraint(model, L_ddot[p,t] == sum(κ*s_real[p] * L[p, l] for l in 1:t))
            @constraint(model, K_ddot[p,t] >= L_ddot[p,t] + Y[p,t]*L_ddot_upper[p,t] - L_ddot_upper[p,t])
            @constraint(model, K_ddot[p,t] <= Y[p,t]*L_ddot_upper[p,t])
            @constraint(model, K_ddot[p,t] <= L_ddot[p,t])
        end
    end

    for ω in Ω
        for p in P
            for t in T
                @constraint(model, sum(X[v,p,t,ω] for v in V_p[p]) <= Y[p,t]*s_real_tilde[p,t,ω] + K_ddot[p,t])
            end
        end
    end

    # Constraint (16)
    for ω in Ω
        for v in V
            for t in T
                if t >= tmin
                    @constraint(model, I[v, t-1, ω] + sum(X[v, p, t, ω] for p in P_v[v]) == Vc[v, t, ω] + I[v, t, ω])
                end
            end
        end
    end

    # Constraint (17)
    for ω in Ω
        for a in A
            for t in T
                if t >= tmin
                    @constraint(model, d_real_tilde[a, t, ω] - sum(Vc[v, t, ω] for v in V_a[a]) + S[a, t-1, ω] <= S[a, t, ω])
                end
            end
        end
    end

    # # Constraint (18)
    # for ω in Ω
    #     for p in P
    #         for t in T
    #             @constraint(model, sum(r[v, p, t] * X[v, p, t, ω] for v in V_p[p]) + X_inf[p, t, ω] >= Y[p, t] * sum((1 + l[v, p]) * f_profit[v, p, t] for v in V_p[p]))
    #         end
    #     end
    # end

    for i in 1:length(starting_points_vect_F)
        a = starting_points_vect_F[i][1]
        t = starting_points_vect_F[i][2]
        tau = starting_points_vect_F[i][3]
        @constraint(model, F[a, (t, tau)] == 1)
    end

    for ω in Ω
        for i in 1:length(starting_points_vect_I)
            v = starting_points_vect_I[i][1]
            amount = starting_points_vect_I[i][2]
            @constraint(model, I[v,0,ω] == amount)
        end
    end

    for ω in Ω
        for i in 1:length(starting_points_vect_S)
            a = starting_points_vect_S[i][1]
            amount = starting_points_vect_S[i][2]
            @constraint(model, S[a,0,ω] == amount)
        end
    end
    
    # for a in A
    #     for (t, tau) in F_time_set
    #         if F_bar[a,(t,tau)] == 0.0 || F_bar[a,(t,tau)] == 1.0
    #             # @constraint(model, F[a,(t,tau)] == F_bar[a,(t,tau)])
    #             set_start_value(F[a,(t,tau)], F_bar[a,(t,tau)])
    #         end
    #     end
    # end

    # for p in P
    #     for t in T
    #         if Y_bar[p,t] == 0.0 || Y_bar[p,t] == 1.0
    #             # @constraint(model, Y[p,t] == Y_bar[p,t])
    #             set_start_value(Y[p,t], Y_bar[p,t])
    #         end
    #     end
    # end

    # for p in P
    #     for (t, tau) in F_time_set
    #         if W_bar[p,(t,tau)] == 0.0 || W_bar[p,(t,tau)] == 1.0
    #             # @constraint(model, W[p,(t,tau)] == W_bar[p,(t,tau)])
    #             set_start_value(W[p,(t,tau)], W_bar[p,(t,tau)])
    #         end
    #     end
    # end

    # for p in P
    #     for t in T
    #         if L_bar[p,t] == 0.0 || L_bar[p,t] == 1.0 || L_bar[p,t] == 2.0 || L_bar[p,t] == 3.0 || L_bar[p,t] == 4.0 || L_bar[p,t] == 5.0
    #             # @constraint(model, L[p,t] == L_bar[p,t])
    #             set_start_value(L[p,t], L_bar[p,t])
    #         end
    #     end
    # end

    # for v in V
    #     for p in P_v[v]
    #         for t in T
    #             for m in keys(m_segments)
    #                 if Z_bar[v,p,t,m] == 0 || Z_bar[v,p,t,m] == 1.0
    #                     # @constraint(model,Z[v,p,t,m] == Z_bar[v,p,t,m])
    #                     set_start_value(Z[v,p,t,m], Z_bar[v,p,t,m])
    #                 end
    #             end
    #         end
    #     end
    # end

    return model
end