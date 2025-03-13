using JuMP
using Gurobi
using Random
using Dualization
using Plots
using DataFrames
using CSV
import XLSX
import JSON
import MathOptInterface

current_directory = @__DIR__
functions_directory = joinpath(current_directory, "functions")
data_dir = joinpath(current_directory, "data")
results_dir = joinpath(current_directory, "results")

# Include all the function files
include(joinpath(functions_directory, "create_check_params.jl"))
include(joinpath(functions_directory, "deterministic_equivalent.jl"))
include(joinpath(functions_directory, "generate_cuts_from_dual.jl"))
include(joinpath(functions_directory, "load_model_starting_points.jl"))
include(joinpath(functions_directory, "initialize_parameters.jl"))
include(joinpath(functions_directory, "process_scenario_data.jl"))
include(joinpath(functions_directory, "process_scenario_data_n_selected.jl"))
include(joinpath(functions_directory, "save_L_shaped_results.jl"))
include(joinpath(functions_directory, "select_random_scenarios.jl"))
include(joinpath(functions_directory, "create_vaccine_data.jl"))
include(joinpath(functions_directory, "sub_problem.jl"))
include(joinpath(functions_directory, "master_problem.jl"))
include(joinpath(functions_directory, "create_vaccine_data_MMR_only.jl"))

gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-2, "OutputFlag" => 0, "Presolve" => 0, "NumericFocus" => 1, "MIPGap" => 1e-1, "Threads" => 8) 
gurobi_solver_DE = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-2, "OutputFlag" => 1, "Presolve" => 1, "NumericFocus" => 1, "MIPGap" => 1e-1, "Threads" => 8) 
gurobi_solver_no_presolve = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-2, "OutputFlag" => 0, "Presolve" => 0, "NumericFocus" => 1, "MIPGap" => 1e-1, "Threads" => 8) 

function tender_stochastic_sensitivity(
    max_horizon_length::Int,
    max_tender_length::Int,
    number_of_demand_scenarios::Int,
    total_capacity_scenarios::Int,
    number_of_trials::Int,
    initial_inventory_rate::Int,
    scaled_capacity::Int,
    allowable_capacity_increase_number::Int,
    overlap_decision::Bool = true,
    capacity_extension_decision::Bool = true,
    UNICEF_MODEL::Bool = true,
    SOCIAL_BENEFIT_MODEL::Bool = false,
    MAX_PROFIT_MODEL::Bool = false
)

model = []

if UNICEF_MODEL
    model = "UNICEF_GAVI"
elseif SOCIAL_BENEFIT_MODEL
    model = "SOCIAL_BENEFIT"
else
    model = "MAX_PROFIT"
end

    # value to scale coefficients for faster computation
    unit = 1000
    global total_time = 0

    for trial in 1:number_of_trials
        println("trial: $trial")
        source = string(results_dir, "/", model, "_log_DE_L_T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",number_of_demand_scenarios*total_capacity_scenarios,"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
            overlap_decision = true
    
        ################################################### INITIALIZE NECESSARY PARAMS ###################################################
        #load vaccine dict data
        A, V, A_v, P, P_v, V_a, V_p, P_a, A_p, capacity_category, vaccine_category, antigen_category = create_vaccine_data() #there is something wrong with this data
        T, T_initial, Δ, s_real, r, r_avg, r_producer_avg, g, h, l, f_profit, Γ, F_time_set, κ, L_lower_number, L_upper_number, delta, beta, zeta_vm, phi_vm_lower, phi_vm_upper, m_segments = initialize_parameters(data_dir, unit, scaled_capacity, max_horizon_length, max_tender_length, P, V, P_v, V_p, allowable_capacity_increase_number)
        Scenarios_used, p_ω_test, p_ω_test_partial_2, Ω_test_partial_1, Ω_test_partial_2, partial_scenario, s_real_tilde, d_real_tilde, random_scenarios = process_scenario_data_n_selected(current_directory, data_dir, total_capacity_scenarios, number_of_demand_scenarios, A, T, P, scaled_capacity, max_horizon_length, max_tender_length, trial, initial_inventory_rate, allowable_capacity_increase_number, 1)
        X_tilde_lower, X_tilde_upper, L_ddot_lower, L_ddot_upper, L_hat_lower, L_hat_upper, L_check_lower, L_check_upper = create_check_params(V, P, P_v, T, F_time_set, s_real, κ, L_upper_number)
        
        starting_points_vect_F, starting_points_vect_I, starting_points_vect_S = load_model_starting_points(data_dir, initial_inventory_rate, unit, A, V)
        # cuts_dict = Dict()

        start_time = time()
    
        ################################################### INITIALIZE MASTER PROBLEM ###################################################
        Masterproblem = JuMP.Model()
        JuMP.set_optimizer(Masterproblem, gurobi_solver)
        source1 = string(results_dir, "/", model, "_log_Phase1_L_T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
        source2 = string(results_dir, "/", model, "_log_Phase2_L_T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")

        Masterproblem = master_problem(Masterproblem, A, F_time_set, V, P_v, P, T, L_lower_number, L_upper_number, 
                                        Ω_test_partial_2, Ω_test_partial_1, T_initial, starting_points_vect_I, 
                                        starting_points_vect_S, starting_points_vect_F, UNICEF_MODEL, 
                                        capacity_extension_decision, Γ, g, beta, delta, p_ω_test, r, h, r_avg, 
                                        partial_scenario, P_a, gurobi_solver, κ, s_real, L_hat_upper, L_check_upper, V_p, 
                                        X_tilde_upper, A_p, s_real_tilde, d_real_tilde, 1, f_profit, V_a, L_ddot_upper, l, overlap_decision, m_segments, zeta_vm, phi_vm_lower, phi_vm_upper, SOCIAL_BENEFIT_MODEL, MAX_PROFIT_MODEL)

        # write_to_file(Masterproblem, "pre_start_model.lp")

        # Relax constraints for integer and binary variables
        # for a in A, (t, tau) in F_time_set
        #     unset_binary(Masterproblem[:F][a, (t, tau)])
        # end
    
        # for p in P, t in T
        #     unset_binary(Masterproblem[:Y][p, t])
        # end
    
        for p in P, (t, tau) in F_time_set
            unset_binary(Masterproblem[:W][p, (t, tau)])  # Ensure proper indexing
        end
    
        # for v in V, p in P_v[v], t in T, m in keys(m_segments)
        #     unset_binary(Masterproblem[:Z][v, p, t, m])
        # end
    
        # for p in P, t in T
        #     unset_integer(Masterproblem[:L][p, t])
        # end
    
        LB = 0
        UB = 1e30 #high number to start large gap for L-shaped method (which uses infinity)
    
        relaxation_tol1 = 2e-1
        relaxation_tol2 = 1e-1
        global iter1 = 1
        global iter2 = 1
        iter_max = 5000
    
        Z_M = 0.0
        Z_M_prev = 0.0
        dual_subproblem = []
        lb_vector = []
        ub_vector = []
        lb_and_ub_vectors = Dict()
        opt_cut_list = Vector{Any}()
        
        # L-shaped method starts - Phase 1
        while iter1 <= iter_max
            println("Phase 1 iteration: $iter1")
            Masterproblem = generate_cuts_from_dual(Masterproblem, dual_subproblem, Ω_test_partial_2, V, P_v, T, F_time_set, 
            X_tilde_upper, P, s_real_tilde, 1, A, d_real_tilde, l, f_profit, V_p, 
            starting_points_vect_I, starting_points_vect_S, m_segments)
            set_optimizer_attribute(Masterproblem, "LogFile", source1)
            println("Solving MP after cuts!")
            JuMP.optimize!(Masterproblem)
            println("Masterproblem Model status: ", termination_status(Masterproblem))           

    
            if length(opt_cut_list) > 2
                popfirst!(opt_cut_list)
                if opt_cut_list[1] == opt_cut_list[2]
                    break
                end
            end
    
            if primal_status(Masterproblem) == MOI.NO_SOLUTION
                compute_conflict!(Masterproblem)
                iis_model, _ = copy_conflict(Masterproblem)
                println("MASTER_INFEASIBLE")
                print(iis_model)
            end
    
            X_bar = JuMP.value.(Masterproblem[:X])
            S_bar = JuMP.value.(Masterproblem[:S])
            I_bar = JuMP.value.(Masterproblem[:I])
            # X_inf_bar = JuMP.value.(Masterproblem[:X_inf])
    
            # additional_cost_MP = 0.0

            # if UNICEF_MODEL

            #     for a in A
            #         for t in T
            #             for ω in Ω_test_partial_1
            #                 additional_cost_MP += beta * S_bar[a,t,ω] / delta[t]
            #             end
            #         end
            #     end

            #     for v in V
            #         for t in T
            #             for ω in Ω_test_partial_1
            #                 additional_cost_MP += h[v] * r_avg[v,t] * I_bar[v,t,ω] / delta[t]
            #             end
            #         end
            #     end

            # elseif SOCIAL_BENEFIT_MODEL

            #     for a in A
            #         for t in T
            #             for ω in Ω_test_partial_1
            #                 additional_cost_MP += beta * S_bar[a,t,ω] / delta[t]
            #             end
            #         end
            #     end

            # else MAX_PROFIT_MODEL

            #     for a in A
            #         for v in V
            #             for t  = last(T)
            #                 for ω in Ω_test_partial_1
            #                     additional_cost_MP += r_avg[v,t] * S_bar[a,t,ω] / delta[t]
            #                 end
            #             end
            #         end
            #     end

            # end #end if statements

            
            Z_M = JuMP.objective_value(Masterproblem)
            println("Z_M")
            println(Z_M)
            
            # println("Theta: $(JuMP.value.(Masterproblem[:theta]))")
            global F_bar = JuMP.value.(Masterproblem[:F])
            global W_bar = JuMP.value.(Masterproblem[:W])

            #rounding heuristic for W - rounds first W
            # found = false
            # for p in P, (t, tau) in F_time_set
            #     if !found && W_bar[p, (t, tau)] > 0.5 && W_bar[p, (t, tau)] != round(W_bar[p, (t, tau)])
            #         W_bar[p, (t, tau)] = 1
            #         found = true
            #     end
            # end     
            

            global Y_bar = JuMP.value.(Masterproblem[:Y])
            global Q_bar = JuMP.value.(Masterproblem[:Q])
            global L_bar = JuMP.value.(Masterproblem[:L])
            global Z_bar = JuMP.value.(Masterproblem[:Z])
            global L_ddot_bar = JuMP.value.(Masterproblem[:L_ddot])
            global K_ddot_bar = JuMP.value.(Masterproblem[:K_ddot])
            global theta_bar = JuMP.value.(Masterproblem[:theta])

            X_sub = Dict()
            I_sub = Dict()
            S_sub = Dict()
            Vc_sub = Dict()
            for ω in Ω_test_partial_1
                X_temp = Dict()
                for v in V
                    for p in P_v[v]
                        for t in T
                            X_temp[v,p,t] = JuMP.value.(Masterproblem[:X][v,p,t,ω])
                        end
                    end
                end
                I_temp = Dict()
                for v in V
                    for t in T_initial
                        I_temp[v,t] = JuMP.value.(Masterproblem[:I][v,t,ω])
                    end
                end
                S_temp = Dict()
                for a in A
                    for t in T_initial
                        S_temp[a,t] = JuMP.value.(Masterproblem[:S][a,t,ω])
                    end
                end
                Vc_temp = Dict()
                for v in V
                    for t in T
                        Vc_temp[v,t] = JuMP.value.(Masterproblem[:Vc][v,t,ω])
                    end
                end
                X_sub[ω] = X_temp
                I_sub[ω] = I_temp
                S_sub[ω] = S_temp
                Vc_sub[ω] = Vc_temp
            end
    
            if iter1 == 1
                global obj_lb = @constraint(Masterproblem, objective_function(Masterproblem) >= Z_M)
                Z_M_prev = Z_M
            else
                if Z_M >= Z_M_prev
                    set_normalized_rhs(obj_lb, Z_M)
                    # println(obj_lb)
                    Z_M_prev = Z_M
                else
                    set_normalized_rhs(obj_lb, Z_M_prev)
                end
            end
    
            Z_S_omega = Dict()
            dual_subproblem = Dict()
            for ω in Ω_test_partial_2
                # println("scenario: $ω")
                Subproblem, cons_14_1, cons_14_2, cons_14_3, cons_14_4, cons_14_5, 
                cons_15, cons_16, cons_17, cons_18, cons_19 = sub_problem(F_bar, W_bar, Y_bar, Q_bar, L_bar, L_ddot_bar, K_ddot_bar, ω, beta, f_profit, delta, r_avg, gurobi_solver_no_presolve,
                V, P_v, T, T_initial, A, P, F_time_set, 1, V_p, X_tilde_upper, s_real_tilde, d_real_tilde, V_a, starting_points_vect_I, 
                starting_points_vect_S, r, h, l, zeta_vm, m_segments, UNICEF_MODEL, SOCIAL_BENEFIT_MODEL, MAX_PROFIT_MODEL)

                                                                        
                optimize!(Subproblem)
                println("Subproblem Model status: ", termination_status(Subproblem))
    
                X_sub[ω] = JuMP.value.(Subproblem[:X])
                I_sub[ω] = JuMP.value.(Subproblem[:I])
                S_sub[ω] = JuMP.value.(Subproblem[:S])
                Vc_sub[ω] = JuMP.value.(Subproblem[:Vc])
    
                constr14_1 = JuMP.dual.(cons_14_1)
                constr14_2 = JuMP.dual.(cons_14_2)
                constr14_3 = JuMP.dual.(cons_14_3)
                constr14_4 = JuMP.dual.(cons_14_4)
                constr14_5 = JuMP.dual.(cons_14_5)
                constr15 = JuMP.dual.(cons_15)
                constr16 = JuMP.dual.(cons_16)
                constr17 = JuMP.dual.(cons_17)
                constr18 = JuMP.dual.(cons_18)
                constr19 = JuMP.dual.(cons_19)
    
                dual_vector_omega = [constr14_1, constr14_2, constr14_3, constr14_4, constr14_5, constr15, constr16, constr17, constr18, constr19]
                dual_subproblem[ω] = dual_vector_omega
                Z_S_omega[ω] = JuMP.objective_value(Subproblem)
            end #end dual solving
    
            # update UB
            Z_S_expected = sum(p_ω_test_partial_2[ω] * Z_S_omega[ω] for ω in Ω_test_partial_2)
    
            theta_total = 0.0
            for ω in Ω_test_partial_2
                theta_total += p_ω_test_partial_2[ω] * theta_bar[ω]
            end
    
            if Z_M - theta_total + Z_S_expected < UB
                UB = Z_M - theta_total + Z_S_expected
            end
            push!(lb_vector, Z_M)
            push!(ub_vector, UB)
    
            time_elapsed = time() - start_time
            lb_and_ub_vectors["lb"] = lb_vector
            lb_and_ub_vectors["ub"] = ub_vector
            lb_and_ub_vectors["run_time"] = time_elapsed
            # current_directory = @__DIR__

            source = string(results_dir, "/", model, "_Phase1_T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
            f = open(source, "w")
            JSON.print(f, lb_and_ub_vectors)
            close(f)
    
            LB = Z_M
            global LB_phase1 = LB
    
            println("LB: $LB")
            println("UB: $UB")
    
            if (UB - LB) / abs(UB) < relaxation_tol1

                # global LB_phase1 = LB
                # write_to_file(Masterproblem, "phase1_model.lp")


                model_type = "L-shaped-phase1"
                save_L_shaped_results(F_bar,Y_bar,W_bar,L_bar,Q_bar,X_sub,I_sub,Vc_sub,S_sub,Z_bar, model_type, A, T, T_initial, 
                P, P_v, V, V_p, random_scenarios, F_time_set, random_scenarios, capacity_category, antigen_category, 
                vaccine_category, max_horizon_length, max_tender_length, trial, initial_inventory_rate, scaled_capacity, 
                allowable_capacity_increase_number, number_of_demand_scenarios, total_capacity_scenarios, 
                p_ω_test, κ, s_real, s_real_tilde, results_dir, m_segments)


                println("Phase 1 L-shaped method converged in $time_elapsed seconds after $iter1 iterations")
                total_time += time_elapsed

                # global X_sub_warm_start = X_sub
                # global I_sub_warm_start = I_sub
                # global Vc_sub_warm_start = Vc_sub
                # global S_sub_warm_start =S_sub

                break
            end # tolerance level reached, breaking iter1
            iter1 += 1
        end # end iter1

        # Phase 2
        println("################################ Solving phase 2, integer problem... ###############################")

        UB = 1e30
        LB = LB_phase1
        # write_to_file(Masterproblem, "phase2_start_model.lp")

        set_optimizer_attribute(Masterproblem, "Heuristics", 0.5)
        set_optimizer_attribute(Masterproblem, "PumpPasses", 10)
        # set_optimizer_attribute(Masterproblem, "GomoryPasses" => 2)

        # Restore binary/integer constraints
        # for a in A, (t, tau) in F_time_set
        #     set_binary(Masterproblem[:F][a, (t, tau)])
        # end
    
        # for p in P, t in T
        #     set_binary(Masterproblem[:Y][p, t])
        # end
    
        for p in P, (t, tau) in F_time_set
            set_binary(Masterproblem[:W][p, (t, tau)])  # Ensure proper indexing
        end
    
        # for v in V, p in P_v[v], t in T, m in keys(m_segments)
        #     set_binary(Masterproblem[:Z][v, p, t, m])
        # end
    
        # for p in P, t in T
        #     set_integer(Masterproblem[:L][p, t])
        # end

        # init warm start values for IP from relaxtion
        for a in A, (t, tau) in F_time_set
            set_start_value(Masterproblem[:F][a, (t, tau)], F_bar[a, (t, tau)])
        end

        for p in P, t in T
            set_start_value(Masterproblem[:Y][p, t], Y_bar[p, t])
            set_start_value(Masterproblem[:L][p, t], L_bar[p, t])
            set_start_value(Masterproblem[:L_ddot][p, t], L_bar[p, t])
        end   

        for p in P, (t, tau) in F_time_set
            if W_bar[p, (t, tau)] in (0, 1)
                set_start_value(Masterproblem[:W][p, (t, tau)], W_bar[p, (t, tau)])
            end
        end
        
        for v in V, p in P_v[v], (t, tau) in F_time_set, m in keys(m_segments)
            set_start_value(Masterproblem[:Q][v, p, (t, tau), m], Q_bar[v, p, (t, tau), m])
        end
        
        for v in V, p in P_v[v], t in T, m in keys(m_segments)
            set_start_value(Masterproblem[:Z][v, p, t, m], Z_bar[v, p, t, m])
        end

        # write_to_file(Masterproblem, "phase2_deleted_cons.lp")
                
        while iter2 <= iter_max
            println("Phase 2 iteration: $iter2")

            Masterproblem = generate_cuts_from_dual(Masterproblem, dual_subproblem, Ω_test_partial_2, V, P_v, T, F_time_set, 
            X_tilde_upper, P, s_real_tilde, 1, A, d_real_tilde, l, f_profit, V_p, 
            starting_points_vect_I, starting_points_vect_S, m_segments)
            set_optimizer_attribute(Masterproblem, "LogFile", source2)
            println("Optimizing Master Problem")
            JuMP.optimize!(Masterproblem)
            println("Masterproblem Model status: ", termination_status(Masterproblem))
    
            if length(opt_cut_list) > 2
                popfirst!(opt_cut_list)
                if opt_cut_list[1] == opt_cut_list[2]
                    break
                end
            end
    
            if primal_status(Masterproblem) == MOI.NO_SOLUTION
                compute_conflict!(Masterproblem)
                iis_model, _ = copy_conflict(Masterproblem)
                println("MASTER_INFEASIBLE")
                print(iis_model)
            end
    
            X_bar = JuMP.value.(Masterproblem[:X])
            S_bar = JuMP.value.(Masterproblem[:S])
            I_bar = JuMP.value.(Masterproblem[:I])
            # X_inf_bar = JuMP.value.(Masterproblem[:X_inf])
    
            # additional_cost_MP = 0.0

            # if UNICEF_MODEL

            #     for a in A
            #         for t in T
            #             for ω in Ω_test_partial_1
            #                 additional_cost_MP += beta * S_bar[a,t,ω] / delta[t]
            #             end
            #         end
            #     end

            #     for v in V
            #         for t in T
            #             for ω in Ω_test_partial_1
            #                 additional_cost_MP += h[v] * r_avg[v,t] * I_bar[v,t,ω] / delta[t]
            #             end
            #         end
            #     end

            # elseif SOCIAL_BENEFIT_MODEL

            #     for a in A
            #         for t in T
            #             for ω in Ω_test_partial_1
            #                 additional_cost_MP += beta * S_bar[a,t,ω] / delta[t]
            #             end
            #         end
            #     end

            # else MAX_PROFIT_MODEL

            #     for a in A
            #         for v in V
            #             for t  = last(T)
            #                 for ω in Ω_test_partial_1
            #                     additional_cost_MP += r_avg[v,t] * S_bar[a,t,ω] / delta[t]
            #                 end
            #             end
            #         end
            #     end

            # end #end if statements

            
            Z_M = JuMP.objective_value(Masterproblem)
            println("Z_M")
            println(Z_M)
            
            # println("Theta: $(JuMP.value.(Masterproblem[:theta]))")
            global F_bar = JuMP.value.(Masterproblem[:F])
            global W_bar = JuMP.value.(Masterproblem[:W])
            global Y_bar = JuMP.value.(Masterproblem[:Y])
            global Q_bar = JuMP.value.(Masterproblem[:Q])
            global L_bar = JuMP.value.(Masterproblem[:L])
            global Z_bar = JuMP.value.(Masterproblem[:Z])
            global L_ddot_bar = JuMP.value.(Masterproblem[:L_ddot])
            global K_ddot_bar = JuMP.value.(Masterproblem[:K_ddot])
            global theta_bar = JuMP.value.(Masterproblem[:theta])

            X_sub = Dict()
            I_sub = Dict()
            S_sub = Dict()
            Vc_sub = Dict()
            for ω in Ω_test_partial_1
                X_temp = Dict()
                for v in V
                    for p in P_v[v]
                        for t in T
                            X_temp[v,p,t] = JuMP.value.(Masterproblem[:X][v,p,t,ω])
                        end
                    end
                end
                I_temp = Dict()
                for v in V
                    for t in T_initial
                        I_temp[v,t] = JuMP.value.(Masterproblem[:I][v,t,ω])
                    end
                end
                S_temp = Dict()
                for a in A
                    for t in T_initial
                        S_temp[a,t] = JuMP.value.(Masterproblem[:S][a,t,ω])
                    end
                end
                Vc_temp = Dict()
                for v in V
                    for t in T
                        Vc_temp[v,t] = JuMP.value.(Masterproblem[:Vc][v,t,ω])
                    end
                end
                X_sub[ω] = X_temp
                I_sub[ω] = I_temp
                S_sub[ω] = S_temp
                Vc_sub[ω] = Vc_temp
            end
    
            if iter1 == 1
                global obj_lb = @constraint(Masterproblem, objective_function(Masterproblem) >= Z_M)
                Z_M_prev = Z_M
            else
                if Z_M >= Z_M_prev
                    set_normalized_rhs(obj_lb, Z_M)
                    # println(obj_lb)
                    Z_M_prev = Z_M
                else
                    set_normalized_rhs(obj_lb, Z_M_prev)
                end
            end
    
            Z_S_omega = Dict()
            dual_subproblem = Dict()
            for ω in Ω_test_partial_2
                # println("scenario: $ω")
                Subproblem, cons_14_1, cons_14_2, cons_14_3, cons_14_4, cons_14_5, 
                cons_15, cons_16, cons_17, cons_18, cons_19 = sub_problem(F_bar, W_bar, Y_bar, Q_bar, L_bar, L_ddot_bar, K_ddot_bar, ω, beta, f_profit, delta, r_avg, gurobi_solver_no_presolve,
                V, P_v, T, T_initial, A, P, F_time_set, 1, V_p, X_tilde_upper, s_real_tilde, d_real_tilde, V_a, starting_points_vect_I, 
                starting_points_vect_S, r, h, l, zeta_vm, m_segments, UNICEF_MODEL, SOCIAL_BENEFIT_MODEL, MAX_PROFIT_MODEL)

                                                                        
                optimize!(Subproblem)
                println("Subproblem Model status: ", termination_status(Subproblem))
    
                X_sub[ω] = JuMP.value.(Subproblem[:X])
                I_sub[ω] = JuMP.value.(Subproblem[:I])
                S_sub[ω] = JuMP.value.(Subproblem[:S])
                Vc_sub[ω] = JuMP.value.(Subproblem[:Vc])
    
                constr14_1 = JuMP.dual.(cons_14_1)
                constr14_2 = JuMP.dual.(cons_14_2)
                constr14_3 = JuMP.dual.(cons_14_3)
                constr14_4 = JuMP.dual.(cons_14_4)
                constr14_5 = JuMP.dual.(cons_14_5)
                constr15 = JuMP.dual.(cons_15)
                constr16 = JuMP.dual.(cons_16)
                constr17 = JuMP.dual.(cons_17)
                constr18 = JuMP.dual.(cons_18)
                constr19 = JuMP.dual.(cons_19)
    
                dual_vector_omega = [constr14_1, constr14_2, constr14_3, constr14_4, constr14_5, constr15, constr16, constr17, constr18, constr19]
                dual_subproblem[ω] = dual_vector_omega
                Z_S_omega[ω] = JuMP.objective_value(Subproblem)
            end #end dual solving
    
            # update UB
            Z_S_expected = sum(p_ω_test_partial_2[ω] * Z_S_omega[ω] for ω in Ω_test_partial_2)
    
            theta_total = 0.0
            for ω in Ω_test_partial_2
                theta_total += p_ω_test_partial_2[ω] * theta_bar[ω]
            end
    
            if Z_M - theta_total + Z_S_expected < UB
                UB = Z_M - theta_total + Z_S_expected
            end
            push!(lb_vector, Z_M)
            push!(ub_vector, UB)
    
            time_elapsed = time() - start_time
            lb_and_ub_vectors["lb"] = lb_vector
            lb_and_ub_vectors["ub"] = ub_vector
            lb_and_ub_vectors["run_time"] = time_elapsed
            # current_directory = @__DIR__

            source = string(results_dir, "/", model, "_Phase2_T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
            f = open(source, "w")
            JSON.print(f, lb_and_ub_vectors)
            close(f)
    
            LB = Z_M
    
            println("LB: $LB")
            println("UB: $UB")

            #cut generation complete conditions
            if (UB - LB) / abs(UB) < relaxation_tol2
                println("Phase 2 L-shaped method converged in $time_elapsed seconds after $iter2 iterations")
                total_time += time_elapsed
                model_type = "L-shaped-phase2"
                save_L_shaped_results(F_bar,Y_bar,W_bar,L_bar,Q_bar,X_sub,I_sub,Vc_sub,S_sub,Z_bar, model_type, A, T, T_initial, 
                P, P_v, V, V_p, random_scenarios, F_time_set, random_scenarios, capacity_category, antigen_category, 
                vaccine_category, max_horizon_length, max_tender_length, trial, initial_inventory_rate, scaled_capacity, 
                allowable_capacity_increase_number, number_of_demand_scenarios, total_capacity_scenarios, 
                p_ω_test, κ, s_real, s_real_tilde, results_dir, m_segments)


                # println("Final Sub Problem status: ", termination_status(Subproblem))
                # phase2_objective = JuMP.objective_value(Masterproblem)
                # phase2_run_time = JuMP.solve_time(Masterproblem)
                println("Phase 2 Objective Value")
                println(UB)
                println("Phase 2 run time")
                println(time_elapsed)
                println("Total run time: $total_time")

                # current_directory = @__DIR__
                # scenarios = length(random_scenarios)
                source = string(results_dir, "/", model, "_log_Phase2_L_T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
                break #break iter 2
            end #end phase 2, tolerance reached
            iter2 += 1
        end # end iter2
    end #end trials
end # end function

tender_stochastic_sensitivity(10,5,2,2,1,1,1,1, true, true, true, false, false)