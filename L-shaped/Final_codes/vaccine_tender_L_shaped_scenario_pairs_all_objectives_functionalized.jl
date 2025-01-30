using JuMP
using Gurobi
using Random
using Dualization
using Plots
using DataFrames
using CSV
import XLSX
import JSON

current_directory = @__DIR__
functions_directory = joinpath(current_directory, "functions")
data_dir = joinpath(current_directory, "data")
results_dir = joinpath(current_directory, "results")

# Include all the function files
include(joinpath(functions_directory, "create_check_params.jl"))
include(joinpath(functions_directory, "deterministic_equivalent.jl"))
include(joinpath(functions_directory, "generate_dual_cuts.jl"))
include(joinpath(functions_directory, "load_model_starting_points.jl"))
include(joinpath(functions_directory, "load_params.jl"))
include(joinpath(functions_directory, "load_scenarios.jl"))
include(joinpath(functions_directory, "save_L_Shape_results.jl"))
include(joinpath(functions_directory, "select_random_scenarios.jl"))
include(joinpath(functions_directory, "setup_vax_info.jl"))
include(joinpath(functions_directory, "sub_problem.jl"))
include(joinpath(functions_directory, "master_problem.jl"))

gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-4, "OutputFlag" => 0, "Presolve" => 0, "NumericFocus" => 1, "MIPGap" => 1e-3, "Threads" => 8) 
gurobi_solver_DE = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-4, "OutputFlag" => 1, "Presolve" => 1, "NumericFocus" => 1, "MIPGap" => 1e-3, "Threads" => 8) 
gurobi_solver_no_presolve = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-4, "OutputFlag" => 0, "Presolve" => 1, "NumericFocus" => 1, "MIPGap" => 1e-3, "Threads" => 8) 

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
    UNICEF_MODEL::Bool = true
    #, SOCIAL_BENEFIT_MODEL::Bool = false, MAX_PROFIT_MODEL::Bool = false
)
    # value to scale coefficients for faster computation
    unit = 1000

    for trial in 1:number_of_trials
        println("trial: $trial")
        source = string(current_directory, "/results/log_DE_L_T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",number_of_demand_scenarios*total_capacity_scenarios,"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
            # overlap_decision = true
    
        ################################################### INITIALIZE NECESSARY PARAMS ###################################################
        #load vaccine dict data
        A, V, A_v, P, P_v, V_a, V_p, P_a, A_p, capacity_category, vaccine_category, antigen_category = create_vaccine_data()
        T, T_initial, Δ, s_real, r, r_avg, r_producer_avg, g, h, l, f_profit, Γ, F_time_set, κ, L_lower_number, L_upper_number, delta, inf_penalty = process_production_and_cost_data(data_dir, unit, scaled_capacity, max_horizon_length, max_tender_length, P, V, P_v, V_p, allowable_capacity_increase_number)
        Scenarios_used, p_ω_test, p_ω_test_partial_2, Ω_test_partial_1, Ω_test_partial_2, partial_scenario, s_real_tilde, d_real_tilde, random_scenarios = process_scenario_data(current_directory, data_dir, total_capacity_scenarios, number_of_demand_scenarios, A, T, P, scaled_capacity, max_horizon_length, max_tender_length, trial, initial_inventory_rate, allowable_capacity_increase_number)
        X_tilde_lower, X_tilde_upper, L_ddot_lower, L_ddot_upper, L_hat_lower, L_hat_upper, L_check_lower, L_check_upper = create_bounds(V, P, P_v, T, F_time_set, s_real, κ, L_upper_number)
        
        starting_points_vect_F, starting_points_vect_I, starting_points_vect_S = load_starting_points(data_dir, initial_inventory_rate, unit)
        # cuts_dict = Dict()

        start_time = time()
    
        ################################################### INITIALIZE MASTER PROBLEM ###################################################
        Masterproblem = master_problem(A, F_time_set, V, P_v, P, T, L_lower_number, L_upper_number, 
                                        Ω_test_partial_2, Ω_test_partial_1, T_initial, starting_points_vect_I, 
                                        starting_points_vect_S, starting_points_vect_F, UNICEF_MODEL, 
                                        capacity_extension_decision, Γ, g, pi, delta, p_ω_test, r, h, r_avg, inf_penalty, 
                                        partial_scenario, P_a, gurobi_solver, κ, s_real, L_hat_upper, L_check_upper, V_p, 
                                        X_tilde_upper, A_p, s_real_tilde, d_real_tilde, 1, f_profit, V_a, L_ddot_upper, l, overlap_decision)
    
        LB = 0
        UB = 1e30 #high number to start large gap for L-shaped method (which uses infinity)
    
        relaxation_tol = 5e-2
        global iter = 1
        iter_max = 5000
    
        Z_M = 0.0
        Z_M_prev = 0.0
        dual_subproblem = []
        lb_vector = []
        ub_vector = []
        lb_and_ub_vectors = Dict()
        opt_cut_list = Vector{Any}()
        
        # L-shaped method starts
        while iter <= iter_max
            println("iter: $iter")
            Masterproblem = generate_cuts_from_dual(Masterproblem, dual_subproblem, Ω_test_partial_2, V, P_v, T, F_time_set, 
            X_tilde_upper, P, s_real_tilde, 1, A, d_real_tilde, l, f_profit, V_p, 
            starting_points_vect_I, starting_points_vect_S)
            JuMP.optimize!(Masterproblem)
    
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
            X_inf_bar = JuMP.value.(Masterproblem[:X_inf])
    
            additional_cost_MP = 0.0
            for v in V
                for p in P_v[v]
                    for t in T
                        for ω in Ω_test_partial_1
                            additional_cost_MP += r[v,p,t] * X_bar[v,p,t,ω] / delta[t]
                        end
                    end
                end
            end
    
            for a in A
                for t in T
                    for ω in Ω_test_partial_1
                        additional_cost_MP += pi * S_bar[a,t,ω] / delta[t]
                    end
                end
            end
    
            for v in V
                for t in T
                    for ω in Ω_test_partial_1
                        additional_cost_MP += h[v] * r_avg[v,t] * I_bar[v,t,ω] / delta[t]
                    end
                end
            end
    
            for p in P
                for t in T
                    for ω in Ω_test_partial_1
                        additional_cost_MP += inf_penalty * X_inf_bar[p,t,ω] / delta[t]
                    end
                end
            end
            
            Z_M = JuMP.objective_value(Masterproblem)
            println("Z_M")
            println(Z_M)
            
            println("Theta: $(JuMP.value.(Masterproblem[:theta]))")
            global F_bar = JuMP.value.(Masterproblem[:F])
            global W_bar = JuMP.value.(Masterproblem[:W])
            global Y_bar = JuMP.value.(Masterproblem[:Y])
            global Q_bar = JuMP.value.(Masterproblem[:Q])
            global L_bar = JuMP.value.(Masterproblem[:L])
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
    
            if iter == 1
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
                Subproblem, cons_8_1, cons_8_2, cons_8_3, cons_8_4, cons_8_5, 
                cons_9, cons_10, cons_11, cons_12, cons_13, cons_14 = sub_problem(F_bar, W_bar, Y_bar, Q_bar, L_bar, L_ddot_bar, K_ddot_bar, ω, pi, f_profit, delta, r_avg, gurobi_solver_no_presolve,
                                                                        V, P_v, T, T_initial, A, P, F_time_set, 1, V_p, X_tilde_upper, s_real_tilde, d_real_tilde, V_a, starting_points_vect_I, 
                                                                        starting_points_vect_S, r, h, l, inf_penalty, UNICEF_MODEL)
                optimize!(Subproblem)
    
                X_sub[ω] = JuMP.value.(Subproblem[:X])
                I_sub[ω] = JuMP.value.(Subproblem[:I])
                S_sub[ω] = JuMP.value.(Subproblem[:S])
                Vc_sub[ω] = JuMP.value.(Subproblem[:Vc])
    
                constr8_1 = JuMP.dual.(cons_8_1)
                constr8_2 = JuMP.dual.(cons_8_2)
                constr8_3 = JuMP.dual.(cons_8_3)
                constr8_4 = JuMP.dual.(cons_8_4)
                constr8_5 = JuMP.dual.(cons_8_5)
                constr9 = JuMP.dual.(cons_9)
                constr10 = JuMP.dual.(cons_10)
                constr11 = JuMP.dual.(cons_11)
                constr12 = JuMP.dual.(cons_12)
                constr13 = JuMP.dual.(cons_13)
                constr14 = JuMP.dual.(cons_14)
    
                dual_vector_omega = [constr8_1, constr8_2, constr8_3, constr8_4, constr8_5, constr9, constr10, constr11, constr12, constr13, constr14]
                dual_subproblem[ω] = dual_vector_omega
                Z_S_omega[ω] = JuMP.objective_value(Subproblem)
            end
    
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
            current_directory = @__DIR__

            source = string(current_directory, "/results/T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
            f = open(source, "w")
            JSON.print(f, lb_and_ub_vectors)
            close(f)
    
            LB = Z_M
    
            println("LB: $LB")
            println("UB: $UB")
    
            if (UB - LB) / UB < relaxation_tol
                model_type = "L-shaped"
                save_L_shaped_results(F_bar,Y_bar,W_bar,L_bar,Q_bar,X_sub,I_sub,Vc_sub,S_sub, model_type, A, T, T_initial, 
                P, P_v, V, V_p, random_scenarios, F_time_set, random_scenarios, capacity_category, antigen_category, 
                vaccine_category, max_horizon_length, max_tender_length, trial, initial_inventory_rate, scaled_capacity, 
                allowable_capacity_increase_number, number_of_demand_scenarios, total_capacity_scenarios, 
                p_ω_test, κ, s_real, s_real_tilde, results_dir)

                println("L_shaped method converged in $time_elapsed seconds after $iter iterations")

                current_directory = @__DIR__
                scenarios = length(random_scenarios)
                source = string(current_directory, "/results/log_DE_L_T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
                
                deterministic_equivalent_model = deterministic_equivalent(p_ω_test, random_scenarios, F_bar, W_bar, Y_bar, L_bar, g, pi, Γ, gurobi_solver_DE,
                A, A_p, F_time_set, V, P_v, T, T_initial, P, P_a, starting_points_vect_F, starting_points_vect_I, 
                starting_points_vect_S, capacity_extension_decision, UNICEF_MODEL, L_lower_number, L_upper_number,
                κ, s_real, L_hat_upper, L_check_upper, d_real_tilde, X_tilde_upper, s_real_tilde, 1, 
                r, r_avg, h, inf_penalty, V_p, l, f_profit, V_a, delta, L_ddot_upper, overlap_decision)

                set_optimizer_attribute(deterministic_equivalent_model, "LogFile", source)
                optimize!(deterministic_equivalent_model)
            
                deterministic_equivalent_obj = JuMP.objective_value(deterministic_equivalent_model)
                deterministic_equivalent_run_time = JuMP.solve_time(deterministic_equivalent_model)
                println("deterministic_equivalent_obj")
                println(deterministic_equivalent_obj)
                println("deterministic_equivalent_run_time")
                println(deterministic_equivalent_run_time) 

                F_de = Dict()
                Y_de = Dict()
                W_de = Dict()
                L_de = Dict()
                Q_de = Dict()
                X_de = Dict()
                I_de = Dict()
                S_de = Dict()
                Vc_de = Dict()

                F_de = JuMP.value.(deterministic_equivalent_model[:F])
                Y_de = JuMP.value.(deterministic_equivalent_model[:Y])
                W_de = JuMP.value.(deterministic_equivalent_model[:W])
                L_de = JuMP.value.(deterministic_equivalent_model[:L])
                Q_de = JuMP.value.(deterministic_equivalent_model[:Q])
                X_de = JuMP.value.(deterministic_equivalent_model[:X])
                I_de = JuMP.value.(deterministic_equivalent_model[:I])
                Vc_de = JuMP.value.(deterministic_equivalent_model[:Vc])
                S_de = JuMP.value.(deterministic_equivalent_model[:S])


                model_type = "DE_after_L-shaped"
                save_L_shaped_results(F_de,Y_de,W_de,L_de,Q_de,X_de,I_de,Vc_de,S_de, model_type, A, T, T_initial, 
                P, P_v, V, V_p, random_scenarios, F_time_set, random_scenarios, capacity_category, antigen_category, 
                vaccine_category, max_horizon_length, max_tender_length, trial, initial_inventory_rate, scaled_capacity, 
                allowable_capacity_increase_number, number_of_demand_scenarios, total_capacity_scenarios, 
                p_ω_test, κ, s_real, s_real_tilde, results_dir)

                break
            end
    
            iter += 1
        end
    end
end

tender_stochastic_sensitivity(10,5,5,7,1,1,1,1, true, true, true)#, false, false, false)