# This function, `generate_cuts_from_dual`, generates cutting planes (constraints) for a master problem 
# based on the dual solutions from a subproblem in a stochastic programming context. 
# It constructs these cuts for each scenario ω in the set of partially observed scenarios Ω_test_partial_2 
# and appends them to the master problem to ensure convergence of the optimization.

# Parameters:
# - `dual_subproblem`: A data structure containing dual variables for the subproblem associated with each scenario.

# Key Steps:
# 1. Check if the dual solutions are provided (`length(dual_subproblem) > 0`).
# 2. Iterate through the partially observed scenario set `Ω_test_partial_2`.
#    - For each scenario ω, initialize empty lists for the RHS values of constraints (8) to (14).
# 3. Populate the RHS values for each constraint:
#    - **Constraint (8):** Involves indexing over time `t`, `tau`, vehicle `v`, and product `p`, ensuring 
#      constraints for flow conservation are satisfied based on given parameters `Q`, `X_tilde_upper`, and `W`.
#    - **Constraint (9):** Relates to production limits, depending on `Y`, `s_real_tilde`, and constants `K_ddot`.
#    - **Constraint (10):** A simple constraint enforcing conditions for vehicle movement with `tmin` as a time threshold.
#    - **Constraint (11):** Handles demands for arcs in the network, affected by `d_real_tilde`.
#    - **Constraint (12):** Includes profit calculations for products `p` based on vehicle `v` and parameters `l` and `f_profit`.
#    - **Constraint (13):** Adds initial amounts of resources based on `starting_points_vect_I`.
#    - **Constraint (14):** Handles starting points for another set of resources from `starting_points_vect_S`.
# 4. Store all constraint RHS values (`b_By_omega`) in a dictionary for scenario ω.
# 5. Generate optimality cuts:
#    - Compute the right-hand side (RHS) of the θ constraint as the dot product of the duals and the constraint RHS values.
#    - Add the constraint `θ[ω] >= θ_rhs` to the master problem.

# Returns:
# - The updated master problem (`Masterproblem`) with the new constraints (cuts) added.



function generate_cuts_from_dual(dual_subproblem)
        
    if length(dual_subproblem) > 0

        cons_omega_dict = Dict()

        for ω in Ω_test_partial_2
            cons8_1_b_By_omega = []
            cons8_2_b_By_omega = []
            cons8_3_b_By_omega = []
            cons8_4_b_By_omega = []
            cons8_5_b_By_omega = []
            cons9_b_By_omega = []
            cons10_b_By_omega = []
            cons11_b_By_omega = []
            cons12_b_By_omega = []
            cons13_b_By_omega = []
            cons14_b_By_omega = []

            # Constraint (8)
            for v in V
                for p in P_v[v]
                    for t in T
                        for tau in T
                            if (t, tau) in F_time_set
                                push!(cons8_1_b_By_omega, 0.0)
                                push!(cons8_2_b_By_omega, -Q[v,p,(t,tau)])
                                push!(cons8_3_b_By_omega, X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)] - X_tilde_upper[v,p,(t,tau)])
                                push!(cons8_4_b_By_omega, 0.0)
                                push!(cons8_5_b_By_omega, X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)])
                            end
                        end
                    end
                end
            end

            # Constraint (9)
            for p in P
                for t in T
                    c = Y[p,t]*s_real_tilde[p, t, ω] + K_ddot[p,t]
                    push!(cons9_b_By_omega, c)
                end
            end

            # Constraint (10)
            for v in V
                for t in T
                    if t >= tmin
                        c = 0.0
                        push!(cons10_b_By_omega, c)
                    end
                end
            end

            # Constraint (11)
            for a in A
                for t in T
                    if t >= tmin
                        c = -d_real_tilde[a, t, ω]
                        push!(cons11_b_By_omega, c)
                    end
                end
            end

            # Constraint (12)
            for p in P
                for t in T
                    c = Y[p, t] * sum((1 + l[v, p]) * f_profit[v, p, t] for v in V_p[p])
                    push!(cons12_b_By_omega, c)
                end
            end

            # Constraint (13)
            for i in 1:length(starting_points_vect_I)
                amount = starting_points_vect_I[i][2]
                push!(cons13_b_By_omega, amount)
            end
    
            # Constraint (14)
            for i in 1:length(starting_points_vect_S)
                amount = starting_points_vect_S[i][2]
                push!(cons14_b_By_omega, amount)
            end

            b_By_omega = [cons8_1_b_By_omega, cons8_2_b_By_omega, cons8_3_b_By_omega, cons8_4_b_By_omega, cons8_5_b_By_omega, cons9_b_By_omega, cons10_b_By_omega, cons11_b_By_omega, cons12_b_By_omega, cons13_b_By_omega, cons14_b_By_omega]
            cons_omega_dict[ω] = b_By_omega
            # optimality cut 
            theta_rhs = 0.0
            for i in 1:length(cons_omega_dict[ω])
                theta_rhs += (transpose(cons_omega_dict[ω][i]) * dual_subproblem[ω][i])
            end
            @constraint(Masterproblem, theta[ω] >= theta_rhs)
        end
    end

    return Masterproblem
end