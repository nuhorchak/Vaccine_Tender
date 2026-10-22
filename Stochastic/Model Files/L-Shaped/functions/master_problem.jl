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

    # -------------------------
    # Precompute
    # -------------------------
    M = collect(keys(m_segments))
    span = Dict((t,tau) => (tau - t + 1) for (t,tau) in F_time_set)

    @variable(Masterproblem, 0.0 <= F[a in A, (t, tau) in F_time_set] <= 1.0, Bin)
    @variable(Masterproblem, Q[v in V, p in P_v[v], (t, tau) in F_time_set, m in M] >= 0)
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
    @variable(Masterproblem, I[v in V, t in T_initial, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, Vc[v in V, t in T, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, S[a in A, t in T_initial, ω in Ω_test_partial_1] >= 0)
    # @variable(Masterproblem, 0.0 <= Z[v in V, p in P_v[v], t in T, m in M] <= 1, Bin)
    @variable(Masterproblem, 0 <= Z[v in V, p in P_v[v], t in T, m in M] <= 1.0, Bin)

 

    ################################################### MASTER PROBLEM ####################################################

    #CONDITIONS: ALL use capacity extension

    # UNICEF model - base model used, calculated from the perspective of UNICEF-GAVI

    # social benefit - mods to OBJ funs (MP and SP), calcualted to minimize missed doses

    # max profit - mods to OBJ funs (MP and SP), calcualted from the perspective of producers (et. al)

    if UNICEF_MODEL && capacity_extension_decision #objective function is incorrect
        println("UNICEF-GAVI model with capacity extension/discounts")
        @objective(Masterproblem, Min, sum(g[t] * F[a, (t, tau)] / delta[t] for (t, tau) in F_time_set, a in A if (a,t,tau) ∉ starting_points_vect_F) +
        sum(r_avg[v,t] * (1 - zeta_vm[v,m]) * Q[v,p,(t, tau),m] / delta[t] for (t,tau) in F_time_set, v in V, p in P_v[v], m in M)
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
                sum(S[a,t,ω] / delta[t] for a in A, t in T, ω in Ω_test_partial_1)
                )
        )

    else max_profit && capacity_extension_decision
        println("Max profit model with capacity extension/discounts")
        @objective(Masterproblem, Min, sum((-r_avg[v,t]*(1-zeta_vm[v,m])*Q[v,p,(t,tau),m]) / delta[t] for (t,tau) in F_time_set, v in V, p in P_v[v], m in M) +
        sum((Γ[p] * L[p, t]) / delta[t] for p in P, t in T) +
        sum(f_profit[v, p, (t,tau)] * W[p, (t,tau)] / delta[t] for (t, tau) in F_time_set, p in P, v in V_p[p]) +
        sum(p_ω_test[ω]*theta[ω] for ω in Ω_test_partial_2)

            + p_ω_test[partial_scenario] * (
                sum((r_avg[v,t]*S[a,t,ω]) / delta[t] for a in A, v in V, t = last(T), ω in Ω_test_partial_1)
                + sum(h[v] * r_avg[v,t] * I[v,t,ω] / delta[t] for v in V, t in T, ω in Ω_test_partial_1)
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

    # Constraint (3) - at most one tender starting in each period
    for a in A
        for t in T
            @constraint(Masterproblem,
                sum(F[a,(t,tau)] for (t2,tau) in F_time_set if t2 == t) <= 1
            )
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
                    @constraint(Masterproblem, sum(Q[v, p, (t, tau), m] for v in V_p[p], m in M) <= W[p,(t,tau)] * span[(t,tau)] * s_real[p] + K_hat[p,(t,tau)] + K_check[p,(t,tau)])
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

    # Constraint (8) - revenue per tender window, all model types
    for p in P, (t, tau) in F_time_set
        lhs = @expression(Masterproblem, sum(r_avg[v,t] * (1 - zeta_vm[v,m]) * Q[v,p,(t,tau),m] for v in V_p[p], m in M))
        rhs = @expression(Masterproblem, sum((1 + l[v,p]) * f_profit[v,p,(t,tau)] * W[p,(t,tau)] for v in V_p[p]))
        c = @constraint(Masterproblem, lhs >= rhs)
        set_name(c, "revenue_constraint[$p,$t,$tau]")
    end

    # Constraint (9)
    for v in V
        for p in P_v[v]
            for (t, tau) in F_time_set
                for m in M
                    @constraint(Masterproblem, phi_vm_lower[v,m] * Z[v,p,t,m] <= Q[v,p,(t,tau),m])
                end
            end
        end
    end


    # Constraint (10)
    for v in V
        for p in P_v[v]
            for (t, tau) in F_time_set
                for m in M
                    @constraint(Masterproblem, phi_vm_upper[v,m] * Z[v,p,t,m] >= Q[v,p,(t,tau),m])
                end
            end
        end
    end

    # Constraint (11)
    for v in V
        for p in P_v[v]
            for t in T
                @constraint(Masterproblem, sum(Z[v,p,t,m] for m in M) <= 1)
            end
        end
    end

    cons_14 = []
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
    # Constraint (14) - linear, W removed (matches deterministic equivalent)
    for ω in Ω_test_partial_1
        for v in V
            for p in P_v[v]
                for (t, tau) in F_time_set
                    c = @constraint(Masterproblem, sum(Q[v, p, (t, tau), m] for m in M) >= sum(X[v, p, l, ω] for l in t:tau))
                    set_name(c, "master_c_14[$((v,p,(t,tau),ω))]")
                    push!(cons_14, c)
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