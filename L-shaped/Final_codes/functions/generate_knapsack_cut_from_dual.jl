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

using LinearAlgebra

function generate_knapsack_cut_from_dual(Masterproblem, dual_subproblem, Ω_test_partial_2, p_ω_test_partial_2, V, P_v, T, F_time_set, 
    X_tilde_upper, P, s_real_tilde, tmin, A, d_real_tilde, l, f_profit, V_p, 
    starting_points_vect_I, starting_points_vect_S, m_segments, κ, s_real, model, UB)


    Q = Masterproblem[:Q]
    W = Masterproblem[:W]
    Y = Masterproblem[:Y]
    L = Masterproblem[:L]
    K_ddot = Masterproblem[:K_ddot]


        
    if length(dual_subproblem) > 0
        println("Generating knapsack cut from dual")

        cons_omega_rhs = Dict()
        cons_omega_lhs = Dict()
        theta_rhs_dict = Dict()
        theta_lhs_dict = Dict()

        for ω in Ω_test_partial_2
            cons14_b_By_omega = []
            cons15_b_By_omega = []
            cons16_b_By_omega = []
            cons17_b_By_omega = []
            cons18_b_By_omega = []
            cons19_b_By_omega = []

            for v in V
                for p in P_v[v]
                    for t in T
                        for tau in T
                            if (t, tau) in F_time_set
                                push!(cons14_b_By_omega, -sum(Q[v,p,(t, tau),m] for m in keys(m_segments)))
                                # push!(cons14_3_b_By_omega, X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)] - X_tilde_upper[v,p,(t,tau)])
                                # push!(cons14_4_b_By_omega, 0.0)
                                # push!(cons14_5_b_By_omega, X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)])
                            end
                        end
                    end
                end
            end

            # Constraint (15)
            for p in P
                for t in T
                    c = Y[p,t]*s_real_tilde[p, t, ω] + K_ddot[p,t]
                    push!(cons15_b_By_omega, c)
                end
            end

            # Constraint (16)
            for v in V
                for t in T
                    if t >= tmin
                        c = 0.0
                        push!(cons16_b_By_omega, c)
                    end
                end
            end

            # Constraint (17)
            for a in A
                for t in T
                    if t >= tmin
                        c = d_real_tilde[a, t, ω]
                        push!(cons17_b_By_omega, c)
                    end
                end
            end

            # Constraint (18)
            for i in 1:length(starting_points_vect_I)
                amount = starting_points_vect_I[i][2]
                push!(cons18_b_By_omega, -amount)
            end
    
            # Constraint (19)
            for i in 1:length(starting_points_vect_S)
                amount = starting_points_vect_S[i][2]
                push!(cons19_b_By_omega, -amount)
            end

            rhs_By_omega = [cons14_b_By_omega, 
            cons15_b_By_omega,]
            cons_omega_rhs[ω] = rhs_By_omega

            lhs_By_omega = [
            cons16_b_By_omega,
            cons17_b_By_omega,
            cons18_b_By_omega,
            cons19_b_By_omega]
            cons_omega_lhs[ω] = lhs_By_omega
            # optimality cut 
            theta_rhs = 0.0
            theta_lhs = 0.0

            for i in 1:2 #constraints 14 and 15 on the RHS
                theta_rhs += (transpose(cons_omega_rhs[ω][i]) * dual_subproblem[ω][i])
            end
            for i in 3:6 #constraints 16-19 on the LHS
                theta_lhs += (transpose(cons_omega_lhs[ω][i-2]) * dual_subproblem[ω][i])
            end
                       
            theta_rhs_dict[ω] = theta_rhs
            theta_lhs_dict[ω] = theta_lhs
            
        end

        theta_weighted_rhs = sum(p_ω_test_partial_2[ω] * theta_rhs_dict[ω] for ω in Ω_test_partial_2)
        theta_weighted_lhs = sum(p_ω_test_partial_2[ω] * theta_lhs_dict[ω] for ω in Ω_test_partial_2)
        @constraint(Masterproblem, UB - theta_weighted_lhs >= theta_weighted_rhs)
        println("*** Knapsack Cut generated! ***")
    end

    return Masterproblem
end