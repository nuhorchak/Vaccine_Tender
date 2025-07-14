using JuMP
using Gurobi
using Random
using Dualization
using Plots
using DataFrames
using CSV
import XLSX
import JSON
import MathOptInterface as MOI


current_directory = @__DIR__
#functions_directory = joinpath(current_directory, "functions")
#data_dir = joinpath(current_directory, "data")
functions_directory = joinpath(current_directory, "..", "functions")
data_dir = joinpath(current_directory, "..", "data")
results_dir = joinpath(current_directory, "results")

# Include all the function files
include(joinpath(functions_directory, "create_check_params.jl"))
include(joinpath(functions_directory, "deterministic_equivalent.jl"))
include(joinpath(functions_directory, "generate_cuts_from_dual.jl")) 
# include(joinpath(functions_directory, "generate_deepest_cut_from_dual.jl"))
include(joinpath(functions_directory, "generate_knapsack_cut_from_dual.jl"))
include(joinpath(functions_directory, "load_model_starting_points.jl"))
include(joinpath(functions_directory, "initialize_parameters.jl"))
include(joinpath(functions_directory, "process_scenario_data.jl"))
include(joinpath(functions_directory, "process_scenario_data_n_selected_with_MVP.jl"))
include(joinpath(functions_directory, "save_L_shaped_results.jl"))
include(joinpath(functions_directory, "select_random_scenarios.jl"))
include(joinpath(functions_directory, "create_vaccine_data.jl"))
include(joinpath(functions_directory, "sub_problem.jl"))
include(joinpath(functions_directory, "master_problem.jl"))
# include(joinpath(functions_directory, "create_vaccine_data_MMR_only.jl"))

# gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-2, "OutputFlag" => 0, "Presolve" => 0, "NumericFocus" => 1, "MIPGap" => 9e-1, "Heuristics" => 0.5, "PumpPasses" => 10, "GomoryPasses"=>2)#, "Threads" => 8)
gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-3, "OutputFlag" => 0, "Presolve" => 0, "NumericFocus" => 1, "Heuristics" => 0.5, "PumpPasses" => 10, "GomoryPasses"=>2)#, "Threads" => 8) 
gurobi_solver_DE = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-3, "OutputFlag" => 1, "Presolve" => 1, "NumericFocus" => 1, "MIPGap" => 1e-1)#, "Threads" => 8) 
gurobi_solver_no_presolve = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-3, "OutputFlag" => 0, "Presolve" => 0, "NumericFocus" => 1, "MIPGap" => 1e-1)#, "Threads" => 8) 

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
    global LB_phase1 = 0
    global trust_delta_all = 0
    global delta_gap = 99999999999999999999
    global gap_counter = 0
    global feasible_solution = true

    global F_bars = []
    global num_flips_F = []


    if UNICEF_MODEL
        model = "UNICEF_GAVI"
    elseif SOCIAL_BENEFIT_MODEL
        model = "SOCIAL_BENEFIT"
    else
        model = "MAX_PROFIT"
    end

    # value to scale coefficients for faster computation
    # global seed = rand(1:9999999)
    global seed = 40
    unit = 1
    global total_time = 0
    global mip_gap_start = 2e-1  # 20% initial gap
    global min_gap = 1e-2  # 1% Minimum acceptable gap
    global epsilon = 1

    for trial in 1:number_of_trials
        println("trial: $trial")
        source = string(results_dir, "/", model, "_log_DE_L_T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",number_of_demand_scenarios*total_capacity_scenarios,"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
            overlap_decision = true
    
        ################################################### INITIALIZE NECESSARY PARAMS ###################################################
        #load vaccine dict data
        A, V, A_v, P, P_v, V_a, V_p, P_a, A_p, capacity_category, vaccine_category, antigen_category = create_vaccine_data()
        T, T_initial, Δ, s_real, r, r_avg, r_producer_avg, g, h, l, f_profit, Γ, F_time_set, κ, L_lower_number, L_upper_number, delta, beta, zeta_vm, phi_vm_lower, phi_vm_upper, m_segments = initialize_parameters(data_dir, unit, scaled_capacity, max_horizon_length, max_tender_length, P, V, P_v, V_p, allowable_capacity_increase_number)
        Scenarios_used, p_ω_test, p_ω_test_partial_2, Ω_test_partial_1, Ω_test_partial_2, partial_scenario, s_real_tilde, d_real_tilde, random_scenarios = process_scenario_data_n_selected_with_MVP(current_directory, data_dir, total_capacity_scenarios, number_of_demand_scenarios, A, T, P, scaled_capacity, max_horizon_length, max_tender_length, trial, initial_inventory_rate, allowable_capacity_increase_number, 1, false, seed,unit)
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
        LB = 0
        UB = 1e30 #high number to start large gap for L-shaped method (which uses infinity)


    
        relaxation_tol1 = 1e-3
        relaxation_tol2 = 1e-2 #1%
        global iter1 = 1
        global iter2 = 1
        iter_max = 500
    
        Z_M = 0.0
        Z_M_prev = 0.0
        dual_subproblem = []
        lb_vector = []
        ub_vector = []
        lb_and_ub_vectors = Dict()
        f_flip_vector = Dict()
        opt_cut_list = Vector{Any}()
        mip_gap = mip_gap_start
        
        # L-shaped method starts - Phase 1
        while iter1 <= iter_max
            println("Phase 1 iteration: $iter1")
            # write_to_file(Masterproblem, "model_iter_$(iter1).lp")

            # #generate benders cuts
            # if iter1 > 1
            #     Masterproblem = generate_deepst_cut_from_dual(Masterproblem, dual_subproblem, Ω_test_partial_2, V, P_v, T, F_time_set, 
            #     X_tilde_upper, P, s_real_tilde, 1, A, d_real_tilde, l, f_profit, V_p, 
            #     starting_points_vect_I, starting_points_vect_S, m_segments, κ, s_real, model, LB)
            # end

            # #generate benders cuts
            if iter1 > 1
                Masterproblem = generate_cuts_from_dual(Masterproblem, dual_subproblem, Ω_test_partial_2, V, P_v, T, F_time_set, 
                X_tilde_upper, P, s_real_tilde, 1, A, d_real_tilde, l, f_profit, V_p, 
                starting_points_vect_I, starting_points_vect_S, m_segments, κ, s_real, model)
            end

            #generate knapsack cut
            if iter1 > 1
                Masterproblem = generate_knapsack_cut_from_dual(Masterproblem, dual_subproblem, Ω_test_partial_2, p_ω_test_partial_2, V, P_v, T, F_time_set, 
                X_tilde_upper, P, s_real_tilde, 1, A, d_real_tilde, l, f_profit, V_p, 
                starting_points_vect_I, starting_points_vect_S, m_segments, κ, s_real, model, UB)
            end

            # generate solution eliminiation constraint for scenario where missed doses > threashold
            if iter1 > 1

                S_results = Dict()
                for a in A
                    temp_1 = Dict()
                    for t in T_initial
                        temp_2 = Dict()
                        for ω in random_scenarios
                            temp_2[ω] = S_sub[ω][a,t]
                        end
                        temp_1[t] = temp_2
                    end
                    S_results[a] = temp_1
                end

                total_weighted_missed = sum(p_ω_test[ω] * sum(S_results[a][t][ω] for a in A, t in T_initial) for ω in random_scenarios)
                println("Total Missed doses: $total_weighted_missed")

                total_weighted_demand = sum(p_ω_test[ω] * d_real_tilde[(a, t, ω)] for (a, t, ω) in keys(d_real_tilde))
                println("Total Demand: $total_weighted_demand")

                ratio = total_weighted_missed / total_weighted_demand

                println("Ratio of Missed doses to demand: $ratio")

                if ratio >= 0.1 #generate SEC if ratio of missed doses to demand is greater than 10%
                    println("Generating solution elimination constraint for F[a,(t,tau)]")        
                    mismatch_sum = sum(1 - Masterproblem[:F][a, (t, tau)] for a in A, (t, tau) in F_time_set if F_bar[a, (t, tau)] == 1) +
                    sum(Masterproblem[:F][a, (t, tau)] for a in A, (t, tau) in F_time_set if F_bar[a, (t, tau)] == 0)
        
                    @constraint(Masterproblem, mismatch_sum >= 1)
                end
            end

            # generate cut for UB using epsilon
            if iter1 > 1
                epsilon = max(1e-2 * abs(UB), 1)  # use 1e-3, not 10e-4
                println("Generating feasibility seeking cut, with epsilon: $epsilon") 
                if model == "UNICEF_GAVI"
                    rhs_expr = @expression(Masterproblem,
                    sum(g[t] * Masterproblem[:F][a, (t, tau)] / delta[t]
                        for (t, tau) in F_time_set, a in A if (a, t, tau) ∉ starting_points_vect_F) +
                    sum(r_avg[v,t] * (1 - zeta_vm[v,m]) * Masterproblem[:Q][v,p,(t, tau),m] / delta[t]
                        for v in V, p in P_v[v], (t, tau) in F_time_set, m in keys(m_segments)) +
                    sum(p_ω_test[ω] * Masterproblem[:theta][ω] for ω in Ω_test_partial_2)
                    )
                elseif model == "SOCIAL_BENEFIT"
                    rhs_expr = @expression(Masterproblem, 
                    sum(p_ω_test[ω] * Masterproblem[:theta][ω] for ω in Ω_test_partial_2)
                    )
                elseif model == "MAX_PROFIT"
                    rhs_expr = @expression(Masterproblem,
                    sum((-r_avg[v,t]*(1-zeta_vm[v,m])*Masterproblem[:Q][v,p,(t,tau),m]) / delta[t] for (t,tau) in F_time_set, v in V, p in P_v[v], m in keys(m_segments)) +
                    sum((Γ[p] * Masterproblem[:L][p, t]) / delta[t] for p in P, t in T) +
                    sum((f_profit[v,p,t]* Masterproblem[:Y][p,t]) / delta[t] for v in V, p in P_v[v], t in T) +
                    sum(p_ω_test[ω]*Masterproblem[:theta][ω] for ω in Ω_test_partial_2)
                    )
                end
                @constraint(Masterproblem, UB - epsilon >= rhs_expr)
            end 

            set_optimizer_attribute(Masterproblem, "LogFile", source1)
            set_optimizer_attribute(Masterproblem, "MIPGap", mip_gap)
            println("Solving MP after cuts!")
            JuMP.optimize!(Masterproblem)
            # println("Masterproblem Model status: ", termination_status(Masterproblem))
            # Check the solver status

            if termination_status(Masterproblem) == MOI.OPTIMAL
                println("Optimal solution found with MIPGap = ", mip_gap)

                if length(opt_cut_list) > 2
                    popfirst!(opt_cut_list)
                    if opt_cut_list[1] == opt_cut_list[2]
                        break
                    end
                end
                
                Z_M = JuMP.objective_value(Masterproblem)
                if model == "MAX_PROFIT"
                    println("Z_M")
                    println(-Z_M)
                else
                    println("Z_M")
                    println(Z_M)
                end
                
                # println("Theta: $(JuMP.value.(Masterproblem[:theta]))")
                global F_bar = JuMP.value.(Masterproblem[:F])
    
                if iter1 == 1
                    push!(F_bars, Dict((a, (t, tau)) => JuMP.value(Masterproblem[:F][a, (t, tau)]) for a in A, (t, tau) in F_time_set))
                else
                    # check variable flips:
                    push!(F_bars, Dict((a, (t, tau)) => JuMP.value(Masterproblem[:F][a, (t, tau)]) for a in A, (t, tau) in F_time_set))
    
                    function count_flips(F1::Dict, F2::Dict)
                        return count(k -> F1[k] != F2[k], keys(F1))
                    end
    
                    num_flips = count_flips(F_bars[iter1-1], F_bars[iter1])
                    println("---------------- F Flips in iteration $iter1: $num_flips ------------------")
                    push!(num_flips_F, num_flips)
                end
    
                f_flip_vector["num_flips"] = num_flips_F
                source = string(results_dir, "/", model, "_flips",".json")
                f = open(source, "w")
                JSON.print(f, f_flip_vector)
                close(f)
    
                global W_bar = JuMP.value.(Masterproblem[:W])
                global Y_bar = JuMP.value.(Masterproblem[:Y])
                global Q_bar = JuMP.value.(Masterproblem[:Q])
                global L_bar = JuMP.value.(Masterproblem[:L])
                global Z_bar = JuMP.value.(Masterproblem[:Z])
                global L_ddot_bar = JuMP.value.(Masterproblem[:L_ddot])
                global K_ddot_bar = JuMP.value.(Masterproblem[:K_ddot])
                global theta_bar = JuMP.value.(Masterproblem[:theta])
    
                global X_sub = Dict()
                global I_sub = Dict()
                global S_sub = Dict()
                global Vc_sub = Dict()
                
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
                    Subproblem, cons_14, cons_15, cons_16, cons_17, cons_18, cons_19 = sub_problem(F_bar, W_bar, Y_bar, Q_bar, L_bar, L_ddot_bar, K_ddot_bar, ω, beta, f_profit, delta, r_avg, gurobi_solver_no_presolve,
                    V, P_v, T, T_initial, A, P, F_time_set, 1, V_p, X_tilde_upper, s_real, s_real_tilde, d_real_tilde, V_a, starting_points_vect_I, 
                    starting_points_vect_S, r, h, l, zeta_vm, m_segments, κ, UNICEF_MODEL, SOCIAL_BENEFIT_MODEL, MAX_PROFIT_MODEL)
    
                    set_optimizer_attribute(Subproblem, "MIPGap", mip_gap)                                                        
                    optimize!(Subproblem)
                    println("Subproblem Model status: ", termination_status(Subproblem))
        
                    X_sub[ω] = JuMP.value.(Subproblem[:X])
                    I_sub[ω] = JuMP.value.(Subproblem[:I])
                    S_sub[ω] = JuMP.value.(Subproblem[:S])
                    Vc_sub[ω] = JuMP.value.(Subproblem[:Vc])
        
                    constr14 = JuMP.dual.(cons_14)
                    constr15 = JuMP.dual.(cons_15)
                    constr16 = JuMP.dual.(cons_16)
                    constr17 = JuMP.dual.(cons_17)
                    constr18 = JuMP.dual.(cons_18)
                    constr19 = JuMP.dual.(cons_19)
        
                    dual_vector_omega = [constr14, constr15, constr16, constr17, constr18, constr19]
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
                # LB_phase1 = LB
    
                # Reduce the MIP gap by 10%
                mip_gap /= 1.1
                mip_gap = max(mip_gap, min_gap)
                println("Reducing MIPGap to ", mip_gap)
        
                println("LB: $LB")
                println("UB: $UB")
    
                # println("LB Phase 1: $LB_phase1")
    
                if iter1 > 1
                    lb_prev = lb_vector[iter1 - 1]
                    ub_prev = ub_vector[iter1 - 1]
                
                    lb_curr = lb_vector[iter1]
                    ub_curr = ub_vector[iter1]
                
                    # For example, compute gap difference
                    gap_prev = (ub_prev - lb_prev) / abs(ub_prev)
                    gap_curr = (ub_curr - lb_curr) / abs(ub_curr)
                
                    delta_gap = abs(gap_curr - gap_prev)
                    println("GAP: $delta_gap")
                end
    
                large_gap = delta_gap > 0.00004
    
                if large_gap
                    println("The difference between successive solutions is greater than tolerance: $delta_gap")
                    gap_counter = 0
                else
                    println("The difference is small: $delta_gap")
                    gap_counter += 1
                    println("Successive difference Count: $gap_counter")
                end
        
                if (UB - LB) / abs(UB) < relaxation_tol1 || gap_counter > 10 || iter1 >= iter_max # || UB < LB
    
                    if (UB - LB) / abs(UB) < relaxation_tol1
                        println("Tolerance reached - Phase 1")
                    elseif gap_counter > 10
                        println("Solution stabilitized, tolerance not reached")
                    elseif iter1 > iter_max
                        println("Max iterations reached")
                    elseif UB < LB
                        println("Previous solution optimal - UB < LB")
                    end
    
                    model_type = "L-shaped-phase1"
                    save_L_shaped_results(F_bar,Y_bar,W_bar,L_bar,Q_bar,X_sub,I_sub,Vc_sub,S_sub,Z_bar, model_type, A, T, T_initial, 
                    P, P_v, V, V_p, random_scenarios, F_time_set, random_scenarios, capacity_category, antigen_category, 
                    vaccine_category, max_horizon_length, max_tender_length, trial, initial_inventory_rate, scaled_capacity, 
                    allowable_capacity_increase_number, number_of_demand_scenarios, total_capacity_scenarios, 
                    p_ω_test, κ, s_real, s_real_tilde, results_dir, m_segments)
    
    
                    println("Phase 1 L-shaped method completed in $time_elapsed seconds after $iter1 iterations")
                    total_time += time_elapsed
    
                    break
                end # tolerance level reached, breaking iter1

            elseif primal_status(Masterproblem) == MOI.NO_SOLUTION
                compute_conflict!(Masterproblem)
                iis_model, _ = copy_conflict(Masterproblem)
                println("MASTER_INFEASIBLE")
                print(iis_model)

                println("All solutions eliminated, previous solution optimal")

                model_type = "L-shaped-phase1"
                save_L_shaped_results(F_bar,Y_bar,W_bar,L_bar,Q_bar,X_sub,I_sub,Vc_sub,S_sub,Z_bar, model_type, A, T, T_initial, 
                P, P_v, V, V_p, random_scenarios, F_time_set, random_scenarios, capacity_category, antigen_category, 
                vaccine_category, max_horizon_length, max_tender_length, trial, initial_inventory_rate, scaled_capacity, 
                allowable_capacity_increase_number, number_of_demand_scenarios, total_capacity_scenarios, 
                p_ω_test, κ, s_real, s_real_tilde, results_dir, m_segments)


                println("Phase 1 L-shaped method completed in $time_elapsed seconds after $iter1 iterations")
                total_time += time_elapsed

                break
                
            end
    
            iter1 += 1
        end # end iter1
    end #end trials
end # end function

tender_stochastic_sensitivity(10,5,3,3,1,1,1,2, true, true, false, true, false)