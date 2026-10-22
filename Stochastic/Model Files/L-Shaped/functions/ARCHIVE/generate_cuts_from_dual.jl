
# function generate_cuts_from_dual(Masterproblem, dual_subproblem, Ω_test_partial_2, V, P_v, T, F_time_set, 
#     X_tilde_upper, P, s_real_tilde, tmin, A, d_real_tilde, l, f_profit, V_p, I_hat_bar, S_hat_bar, 
#     starting_points_vect_I, starting_points_vect_S, m_segments, κ, s_real, model)


#     Q = Masterproblem[:Q]
#     W = Masterproblem[:W]
#     Y = Masterproblem[:Y]
#     L = Masterproblem[:L]
#     K_ddot = Masterproblem[:K_ddot]
#     theta = Masterproblem[:theta]

        
#     if length(dual_subproblem) > 0
#         println("Generating cuts from dual")

#         cons_omega_dict = Dict()

#         for ω in Ω_test_partial_2
#             cons14_b_By_omega = []
#             cons15_b_By_omega = []
#             cons16_b_By_omega = []
#             cons17_b_By_omega = []

#             cons18_b_By_omega = []
#             cons19_b_By_omega = []


#             for v in V
#                 for p in P_v[v]
#                     for t in T
#                         for tau in T
#                             if (t, tau) in F_time_set
#                                 push!(cons14_b_By_omega, -sum(Q[v,p,(t, tau),m] for m in keys(m_segments)))
#                                 # push!(cons14_3_b_By_omega, X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)] - X_tilde_upper[v,p,(t,tau)])
#                                 # push!(cons14_4_b_By_omega, 0.0)
#                                 # push!(cons14_5_b_By_omega, X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)])
#                             end
#                         end
#                     end
#                 end
#             end

#             # Constraint (15)
#             for p in P
#                 for t in T
#                     c = Y[p,t]*s_real_tilde[p, t, ω] + K_ddot[p,t]
#                     push!(cons15_b_By_omega, c)
#                 end
#             end


#             # Constraint (16)
#             for v in V
#                 for t in T
#                     c = 0.0
#                     push!(cons16_b_By_omega, c)
#                 end
#             end

#             # Constraint (17)
#             for a in A
#                 for t in T
#                     c = -d_real_tilde[a, t, ω]
#                     push!(cons17_b_By_omega, c)
#                 end
#             end

#             # # Constraint (18)
#             # for i in 1:length(starting_points_vect_I)
#             #     amount = starting_points_vect_I[i][2]
#             #     push!(cons18_b_By_omega, amount)
#             # end

#             for v in V
#                 amount = I_hat_bar[v]
#                 push!(cons18_b_By_omega, amount)
#             end

    
#             # # Constraint (19)
#             # for i in 1:length(starting_points_vect_S)
#             #     amount = starting_points_vect_S[i][2]
#             #     push!(cons19_b_By_omega, amount)
#             # end

#             for a in A
#                 amount = S_hat_bar[a]
#                 push!(cons19_b_By_omega, amount)
#             end

#             I_hat_bar, S_hat_bar

#             b_By_omega = [cons14_b_By_omega, 
#             cons15_b_By_omega,
#             cons16_b_By_omega,
#             cons17_b_By_omega,
#             cons18_b_By_omega,
#             cons19_b_By_omega]
#             cons_omega_dict[ω] = b_By_omega
            
#             # optimality cut 
#             theta_rhs = 0.0
#             for i in 1:length(cons_omega_dict[ω])
#                 theta_rhs += (transpose(cons_omega_dict[ω][i]) * dual_subproblem[ω][i])
#                 # println("Dual Subproblem omega, value $i: $(dual_subproblem[ω][i])")
#             end

#             @constraint(Masterproblem, theta[ω] >= theta_rhs)
            
#             println("*** Cut generated! ***")
#         end
#     end
    

#     return Masterproblem
# end

function generate_cuts_from_dual(Masterproblem, dual_subproblem_MMW, Ω_test_partial_2, V, P_v, T, F_time_set, 
    X_tilde_upper, P, s_real_tilde, tmin, A, d_real_tilde, l, f_profit, V_p, I_hat, S_hat, 
    starting_points_vect_I, starting_points_vect_S, m_segments, κ, s_real, model) # Renamed I_hat_bar, S_hat_bar to I_hat, S_hat

    Q = Masterproblem[:Q]
    W = Masterproblem[:W] # This is not used in the dual objective, but might be needed if your primal constraints were different
    Y = Masterproblem[:Y]
    L = Masterproblem[:L]
    K_ddot = Masterproblem[:K_ddot]
    theta = Masterproblem[:theta]

    println("Debug: Type of Masterproblem: ", typeof(Masterproblem))

    if length(dual_subproblem_MMW) > 0 
        println("Generating cuts from dual")

        for ω in Ω_test_partial_2
            ψ_vals = dual_subproblem_MMW[ω][1]
            μ_vals = dual_subproblem_MMW[ω][2]
            η_vals = dual_subproblem_MMW[ω][3]
            π_vals = dual_subproblem_MMW[ω][4]
            χ_vals = dual_subproblem_MMW[ω][5]
            σ_vals = dual_subproblem_MMW[ω][6]

            cut_rhs_expr = JuMP.AffExpr(0.0) 
            # println("Debug: Type of cut_rhs_expr after initialization for ω=$ω: ", typeof(cut_rhs_expr)) # Keep this for confirmation


            # Term for χ (related to I_hat)
            chi_idx = 1
            for v in V
                # Make sure the term being added is also a valid JuMP expression or number
                term_to_add = χ_vals[chi_idx] * I_hat[v] 
                JuMP.add_to_expression!(cut_rhs_expr, term_to_add)
                chi_idx += 1
            end

            # Term for σ (related to S_hat)
            sigma_idx = 1
            for a in A
                term_to_add = σ_vals[sigma_idx] * S_hat[a]
                JuMP.add_to_expression!(cut_rhs_expr, term_to_add)
                sigma_idx += 1
            end

            # Term for ψ (related to Q)
            psi_idx = 1
            for v in V, p in P_v[v], (t, tau) in F_time_set
                # sum(Q[v,p,(t,tau),m] for m in keys(m_segments)) is already a JuMP expression
                term_to_add = ψ_vals[psi_idx] * sum(Q[v,p,(t,tau),m] for m in keys(m_segments))
                JuMP.add_to_expression!(cut_rhs_expr, term_to_add)
                psi_idx += 1
            end

            # Term for μ (related to Y and L)
            mu_idx = 1
            for p in P, t in T
                # Y[p,t] and L[p,l] are JuMP variables
                term_to_add = μ_vals[mu_idx] * (Y[p,t] * s_real_tilde[p, t, ω] + sum(κ * s_real[p] * L[p, l] for l in 1:t))
                JuMP.add_to_expression!(cut_rhs_expr, term_to_add)
                mu_idx += 1
            end

            # Term for π (related to d_real_tilde)
            pi_idx = 1
            for a in A, t in T
                term_to_add = π_vals[pi_idx] * -d_real_tilde[a, t, ω]
                JuMP.add_to_expression!(cut_rhs_expr, term_to_add)
                pi_idx += 1
            end

            @constraint(Masterproblem, theta[ω] >= cut_rhs_expr)
            
            println("*** Cut generated for scenario $ω ***")
        end
    end
    
    return Masterproblem
end