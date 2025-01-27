using JuMP
using Gurobi
using Random
using Dualization
using Plots
using DataFrames
using CSV
import XLSX
import JSON

#import functions to calculations
# Include the external file
current_directory = @__DIR__
functions_directory = joinpath(current_directory, "functions")

# Include a function file from the "functions" folder
include(joinpath(functions_directory, "setup_vax_info.jl"))
include(joinpath(functions_directory, "sub_problem.jl"))
include(joinpath(functions_directory, "save_L_Shape_results.jl"))
include(joinpath(functions_directory, "deterministic_equivalent.jl"))
include(joinpath(functions_directory, "select_random_scenarios.jl"))


gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-4, "OutputFlag" => 0, "Presolve" => 0, "NumericFocus" => 1, "MIPGap" => 1e-6, "Threads" => 8) 
gurobi_solver_DE = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-4, "OutputFlag" => 1, "Presolve" => 1, "NumericFocus" => 1, "MIPGap" => 1e-6, "Threads" => 8) 
gurobi_solver_no_presolve = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-4, "OutputFlag" => 0, "Presolve" => 1, "NumericFocus" => 1, "MIPGap" => 1e-6, "Threads" => 8) 

# max_horizon_length => represents T => Integer number 
# max_tender_length => Δ ∈ {3,5,7}
# number_of_demand_scenarios => Number of demand scenarios. Integer number. We pair each demand scenario (N) with capacity scenarios (M). We obtain NxM scenarios in total.
# total_capacity_scenarios => Number of capacity scenarios. Integer number. We pair each demand scenario (N) with capacity scenarios (M). We obtain NxM scenarios in total.
# number_of_trials => to run the experiment multiple times. Integer number
# initial_inventory_rate => base value is 1, which is OBE since we are running modified starts
# scaled_capacity => base value is 1. For the scaled_capacity effect, 1.5 should be input.
# allowable_capacity_increase_number => Default value is 5 meaning that a producer can increase its capacity by 50% (5x10%) in a year. It can be selected as allowable_capacity_increase_number ∈ {1,2,3,4,5}
# capacity_extension_decision => boolean, true if capacity increases are allowed
# UNICEF_MODEL => boolean, true is UNICEF_MODEL is used, false if min_unvax model is used

# tender_stochastic_sensitivity(10,5,5,7,1,1,1,1, false)
function tender_stochastic_sensitivity(max_horizon_length,max_tender_length,number_of_demand_scenarios,total_capacity_scenarios,number_of_trials,initial_inventory_rate,scaled_capacity,allowable_capacity_increase_number, 
    capacity_extension_decision = true, UNICEF_MODEL = true, SOCIAL_BENEFIT_MODEL = false, MAX_PROFIT_MODEL = false, testing = false)

    L_shaped_output = Dict()
    Scenarios_used = Dict()


    for trial in 1:number_of_trials
        println("trial: $trial")
        current_directory = @__DIR__
        source = string(current_directory, "/results/log_DE_L_T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",number_of_demand_scenarios*total_capacity_scenarios,"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
        if true
            overlap_decision = true
        
            ################################################### INITIALIZE NECESSARY PARAMS ###################################################
            vaccine_dict = create_vaccine_data()
        
            tmin = 1
            tmax = max_horizon_length
            T = [t for t in tmin:tmax]
            T_initial = [t for t in tmin-1:tmax]
            Δ = [i for i in 1:max_tender_length]

        
            current_directory = @__DIR__
            filename = "data/scenario_pair_probabilities_new.json"
            relative_path = joinpath(current_directory, filename)
            scenario_pair_probs = JSON.parsefile(relative_path)

            total_scenarios = length(scenario_pair_probs)
        


            random_scenarios = select_random_scenarios(1, ceil(Int, total_scenarios/total_capacity_scenarios), number_of_demand_scenarios)
            println("Selected random scenarios: ", random_scenarios)
        
            current_directory = @__DIR__
            filename = "data/scenario_pairs_new.json"
            # Construct the relative path using joinpath
            relative_path = joinpath(current_directory, filename)
        
            scenario_pairs = JSON.parsefile(relative_path)
            unit = 1000

            Ω_test = random_scenarios

            d_real_tilde = Dict()
            s_real_tilde = Dict()
        
            demand_dict = Dict()
            for ω in Ω_test
                total_demand = 0.0
                for a in A
                    for t in T
                        d_real_tilde[a,t,ω] = round(scenario_pairs["$ω"]["demand"]["$t"]["$a"] / unit, digits=0)
                        total_demand += d_real_tilde[a,t,ω]
                    end
                end
                demand_dict[ω] = total_demand
            end
            # println(d_real_tilde)
        
            capacity_dict = Dict()
            for ω in Ω_test
                total_capacity = 0.0
                for p in P
                    for t in T
                        s_real_tilde[p,t,ω] = round(scenario_pairs["$ω"]["capacity"]["$t"]["$p"] * scaled_capacity / unit, digits=0)
                        total_capacity += s_real_tilde[p,t,ω]
                    end
                end
                capacity_dict[ω] = total_capacity
            end
            # println(s_real_tilde)
            max_cap_value = maximum(values(capacity_dict))
            max_cap_keys = [k for k in keys(capacity_dict) if capacity_dict[k] == max_cap_value]

            filtered_demand_dict = filter(kv -> kv[1] in max_cap_keys, demand_dict)
            max_key_final = argmax(filtered_demand_dict)

            println(max_cap_value)
            println(max_cap_keys)
            println(max_key_final)
        
            subset_probs_dict = Dict(ω => scenario_pair_probs["$ω"] for ω in random_scenarios if haskey(scenario_pair_probs, "$ω"))
            # partial_scenario = argmax(subset_probs_dict)
            partial_scenario = max_key_final
            # partial_scenario = 3
        
            index_number = findfirst(x -> x == partial_scenario, random_scenarios)
            reduced_random_scenarios = copy(random_scenarios)
            deleteat!(reduced_random_scenarios, index_number)
        
            Ω_test_partial_1 = [partial_scenario]
            Ω_test_partial_2 = reduced_random_scenarios
    
            # Ω_train = generate_omega_list(test_scenario_number+1,total_scenarios)
        
            println(Ω_test_partial_1)
            println(Ω_test_partial_2)
            # println(Ω_train)
        
            total_probs = 0.0
            for ω in Ω_test
                total_probs += scenario_pair_probs["$ω"]
            end
            p_ω_test = Dict(ω => scenario_pair_probs["$ω"]/total_probs for ω in Ω_test)
        
            total_probs_partial_2 = 0.0
            for ω in Ω_test_partial_2
                total_probs_partial_2 += scenario_pair_probs["$ω"]
            end
            p_ω_test_partial_2 = Dict(ω => scenario_pair_probs["$ω"]/total_probs_partial_2 for ω in Ω_test_partial_2)
        
            println(p_ω_test)
            println(p_ω_test_partial_2)
    
            Scenarios_used["All"] = Ω_test
            Scenarios_used["Partial_1"] = Ω_test_partial_1
            Scenarios_used["Partial_2"] = Ω_test_partial_2
    
            source = string(current_directory, "/results/scenarios_", tmax, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
            f = open(source, "w")
            JSON.print(f, Scenarios_used)
            close(f)

            # println(scenario_pairs)
        
            filename2 = "data/production_capacity_scenarios.xlsx"
        
            # Construct the relative path using joinpath
            relative_path2 = joinpath(current_directory, filename2)
        
            capacity_file = XLSX.readxlsx(relative_path2)
        
            s_real_raw = capacity_file["base_capacity"]
        
            total_supply_row = length(P) + 1
            total_supply_col = 2
        
            s_real = Dict()
            
            for row in 2:total_supply_row
                producer = s_real_raw[row, 1]
                for col in 2:total_supply_col
                    year = s_real_raw[1, col]
                    s_real[producer] = round(s_real_raw[row, col] * scaled_capacity / unit, digits=0)
                end
            end
            # println(s_real)
        
            current_directory = @__DIR__
        
            filename = "data/Vaccine_price_data.xlsx"
            relative_path = joinpath(current_directory, filename)       
            vaccine_price_file = XLSX.readxlsx(relative_path)
        
            r = Dict()
            for v in V
                vaccine_price_raw = vaccine_price_file[string(v, " Pricing")]
                for row in 2:length(P_v[v])+1
                    producer = vaccine_price_raw[row, 1]
                    for col in 2:length(T)+1
                        year = vaccine_price_raw[1, col]
                        r[v, producer, year] = vaccine_price_raw[row, col]
                    end
                end
            end
        
            r_avg = Dict()
            for v in V
                for t in T
                    total = 0.0
                    for p in P_v[v]
                        total += r[v, p, t]
                    end
                    average = total / length(P_v[v])
                    r_avg[v, t] = average
                end
            end
        
            r_producer_avg = Dict()
            for p in P
                total = 0.0
                for v in V_p[p]
                    for t in T
                        total += r[v, p, t]
                    end
                end
                average = total / (length(V_p[p]) * length(T))
                r_producer_avg[p] = average
            end
        
            # Unvaccinated children penalty
            pi = 10
        
            # Tender cost
            g = Dict()
            for t in T
                g[t] = 1e8 / unit
            end
        
            # Inventory holding cost
            h = Dict()
            for v in V
                h[v] = 0.01
            end
        
            # ROI
            l = Dict()
            for v in V
                for p in P
                    l[v, p] = 0.1
                end
            end
        
            f_profit = Dict()
            for p in P
                for v in V_p[p]
                    for t in T
                        f_profit[v, p, t] = s_real[p] / length(V_p[p]) * r_producer_avg[p] / 2
                    end
                end
            end

            #define discount segments
        
            κ = 0.10
            L_lower_number = 0
            L_upper_number = allowable_capacity_increase_number
            delta = [(1+0.03)^t for t in 1:tmax]
        
            # Γ is the cost of expanding capacity for producer p
            Γ = Dict()
            for p in P
                Γ[p] = 1e8 / unit
            end
        
            inf_penalty = 100
        
            F_time_set = []
            for t in T
                for tau in T
                    if tau >= t
                        if (tau - t + 1) in Δ
                            push!(F_time_set, (t, tau))
                        end
                    end
                end
            end
        
            X_tilde_lower = Dict()
            X_tilde_upper = Dict()
            for v in V
                for p in P_v[v]
                    for t in T
                        for tau in T
                            if (t, tau) in F_time_set
                                X_tilde_lower[v, p, (t, tau)] = 0
                                X_tilde_upper[v, p, (t, tau)] = sum(s_real[p] for l in t:tau)
                            end
                        end
                    end
                end
            end
        
            L_ddot_lower = Dict()
            L_ddot_upper = Dict()
            for p in P
                for t in T
                    L_ddot_lower[p,t] = 0
                    L_ddot_upper[p,t] = sum(κ*s_real[p]*L_upper_number for l in 1:t)
                end
            end
        
            L_hat_lower = Dict()
            L_hat_upper = Dict()
            for p in P
                for (t, tau) in F_time_set
                    L_hat_lower[p,(t,tau)] = 0
                    temp = 0.0
                    for l in (t+1):tau
                        temp += (tau-l+1)*κ*s_real[p]*L_upper_number
                    end
                    L_hat_upper[p,(t,tau)] = temp
                end
            end
        
            L_check_lower = Dict()
            L_check_upper = Dict()
            for p in P
                for (t, tau) in F_time_set
                    L_check_lower[p,(t,tau)] = 0
                    L_check_upper[p,(t,tau)] = sum((tau-t+1)*κ*s_real[p]*L_upper_number for l in 1:t)
                end
            end
            
            current_directory = @__DIR__
            filename = "data/Starting_point.xlsx"
            relative_path = joinpath(current_directory, filename)
            starting_points_file = XLSX.readxlsx(relative_path)
            
            starting_points_F_raw = starting_points_file["F_start"]
            total_row_F = length(starting_points_F_raw[:, 1])
            starting_points_vect_F = []
            for row in 2:total_row_F
                antigen = starting_points_F_raw[row,1]
                starting_year = starting_points_F_raw[row,2]
                ending_year = starting_points_F_raw[row,3]
                push!(starting_points_vect_F, (antigen,starting_year,ending_year))
            end
        
            starting_points_I_raw = starting_points_file["I_start"]
            total_row_I = length(starting_points_I_raw[:, 1])
            starting_points_vect_I = []
            for row in 2:total_row_I
                vaccine = starting_points_I_raw[row,1]
                amount = round(starting_points_I_raw[row,2] * initial_inventory_rate / unit, digits=0)
                push!(starting_points_vect_I, (vaccine,amount))
            end
        
            starting_points_S_raw = starting_points_file["S_start"]
            total_row_S = length(starting_points_S_raw[:, 1])
            starting_points_vect_S = []
            for row in 2:total_row_S
                antigen = starting_points_S_raw[row,1]
                amount = round(starting_points_S_raw[row,2] / unit, digits=0)
                push!(starting_points_vect_S, (antigen,amount))
            end

                        
            
        
            
            cuts_dict = Dict()
            function master_problem(dual_subproblem)
        
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
        
            start_time = time()
        
            ######### Initiate the Master problem #########
            Masterproblem = JuMP.Model()
            JuMP.set_optimizer(Masterproblem, gurobi_solver)
        
            @variable(Masterproblem, 0.0 <= F[a in A, (t, tau) in F_time_set] <= 1.0)
            # @variable(Masterproblem, F[a in A, (t, tau) in F_time_set], Bin)
            @variable(Masterproblem, Q[v in V, p in P_v[v], (t, tau) in F_time_set] >= 0)
            @variable(Masterproblem, 0.0 <= Y[p in P, t in T] <= 1.0)
            @variable(Masterproblem, 0.0 <= W[p in P, (t, tau) in F_time_set] <= 1.0)
            @variable(Masterproblem, L_lower_number <= L[p in P, t in T] <= L_upper_number)
            # @variable(Masterproblem, Y[p in P, t in T], Bin)
            # @variable(Masterproblem, W[p in P, (t, tau) in F_time_set], Bin)
            #@variable(model, L_lower_number <= L[p in P, t in T] <= L_upper_number, Int)
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
            @variable(Masterproblem, X_inf[p in P, t in T, ω in Ω_test_partial_1] >= 0)
            #add Z, fix Q with m for segments
        
            ################################################### MASTER PROBLEM ####################################################

            #CONDITIONS: ALL use capacity extension

            # UNICEF model - base model used, calculated from the perspective of UNICEF-GAVI

            #social benefit - mods to OBJ funs (MP and SP), calcualted to minimize missed doses

            #max profit - mods to OBJ funs (MP and SP), calcualted from the perspective of producers (et. al)

            if UNICEF_MODEL && !capacity_extension_decision #base model, no capacity extension
                println("Condition: Base model and no capacity extension")
                @objective(Masterproblem, Min, sum(g[t] * F[a, (t, tau)] / delta[t] for (t, tau) in F_time_set, a in A if (a,t,tau) ∉ starting_points_vect_F)
                + sum(p_ω_test[ω]*theta[ω] for ω in Ω_test_partial_2)
                
                + p_ω_test[partial_scenario] * (
                + sum(r[v,p,t] * X[v,p,t,ω] / delta[t] for v in V, p in P_v[v], t in T, ω in Ω_test_partial_1)
                + sum(pi * S[a,t,ω] / delta[t] for a in A, t in T, ω in Ω_test_partial_1)
                + sum(h[v] * r_avg[v,t] * I[v,t,ω] / delta[t] for v in V, t in T, ω in Ω_test_partial_1)
                + sum(inf_penalty * X_inf[p,t,ω] / delta[t] for p in P, t in T, ω in Ω_test_partial_1)
                )
                )
            elseif UNICEF_MODEL && capacity_extension_decision #base model, capacity extension
                println("Condition: Base model with capacity extension")
                @objective(Masterproblem, Min, sum(g[t] * F[a, (t, tau)] / delta[t] for (t, tau) in F_time_set, a in A if (a,t,tau) ∉ starting_points_vect_F)
                + sum(Γ[p] * L[p, t] / delta[t] for p in P, t in T)
                + sum(p_ω_test[ω]*theta[ω] for ω in Ω_test_partial_2)
                
                + p_ω_test[partial_scenario] * (
                + sum(r[v,p,t] * X[v,p,t,ω] / delta[t] for v in V, p in P_v[v], t in T, ω in Ω_test_partial_1)
                + sum(pi * S[a,t,ω] / delta[t] for a in A, t in T, ω in Ω_test_partial_1)
                + sum(h[v] * r_avg[v,t] * I[v,t,ω] / delta[t] for v in V, t in T, ω in Ω_test_partial_1)
                + sum(inf_penalty * X_inf[p,t,ω] / delta[t] for p in P, t in T, ω in Ω_test_partial_1)
                )
                )
            elseif testing
                println("Condition: Testing")
                @objective(Masterproblem, Min, sum(p_ω_test[ω]*theta[ω] for ω in Ω_test_partial_2)
                + p_ω_test[partial_scenario] * (
                + sum(h[v] * r_avg[v,t] * I[v,t,ω] / delta[t] for v in V, t in T, ω in Ω_test_partial_1)
                + sum(inf_penalty * X_inf[p,t,ω] / delta[t] for p in P, t in T, ω in Ω_test_partial_1)
                )
                )
            elseif capacity_extension_decision && UNICEF_MODEL #min unvax model, capacity extension
                println("Condition: Min Unvax Model and Capacity extension")
                @objective(Masterproblem, Min, sum(p_ω_test[ω]*theta[ω] for ω in Ω_test_partial_2)
                + p_ω_test[partial_scenario] * (sum(pi * S[a,t,ω] / delta[t] for a in A, t in T, ω in Ω_test_partial_1)
                + sum(inf_penalty * X_inf[p,t,ω] / delta[t] for p in P, t in T, ω in Ω_test_partial_1)
                )
                )
            else #min unvax model, no capacity extension
                println("Condition: Min Unvax Model and no capacity extension")
                @objective(Masterproblem, Min, sum(p_ω_test[ω]*theta[ω] for ω in Ω_test_partial_2)
                + p_ω_test[partial_scenario] * (sum(pi * S[a,t,ω] / delta[t] for a in A, t in T, ω in Ω_test_partial_1)
                + sum(inf_penalty * X_inf[p,t,ω] / delta[t] for p in P, t in T, ω in Ω_test_partial_1)
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
                            @constraint(Masterproblem, sum(Q[v, p, (t, tau)] for v in V_p[p]) <= W[p,(t,tau)]*sum(s_real[p] for l in t:tau) + K_hat[p,(t,tau)] + K_check[p,(t,tau)])
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

        
            # Constraint (8) - McCormick_1
            for ω in Ω_test_partial_1
                for v in V
                    for p in P_v[v]
                        for t in T
                            for tau in T
                                if (t,tau) in F_time_set
                                    @constraint(Masterproblem, X_tilde[v,p,(t,tau),ω] == sum(X[v,p,l,ω] for l in t:tau))
                                    @constraint(Masterproblem, Q[v,p,(t,tau)] >= K[v,p,(t,tau),ω])
                                    @constraint(Masterproblem, K[v,p,(t,tau),ω] >= X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)] + X_tilde[v,p,(t,tau),ω] - X_tilde_upper[v,p,(t,tau)])
                                    @constraint(Masterproblem, K[v,p,(t,tau),ω] <= X_tilde[v,p,(t,tau),ω])
                                    @constraint(Masterproblem, K[v,p,(t,tau),ω] <= X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)])
                                end
                            end
                        end
                    end
                end
            end
        
            # Constraint (9) McCormick
            for p in P
                for t in T
                    @constraint(Masterproblem, L_ddot[p,t] == sum(κ*s_real[p] * L[p, l] for l in 1:t))
                    @constraint(Masterproblem, K_ddot[p,t] >= L_ddot[p,t] + Y[p,t]*L_ddot_upper[p,t] - L_ddot_upper[p,t])
                    @constraint(Masterproblem, K_ddot[p,t] <= Y[p,t]*L_ddot_upper[p,t])
                    @constraint(Masterproblem, K_ddot[p,t] <= L_ddot[p,t])
                end
            end
        
            for ω in Ω_test_partial_1
                for p in P
                    for t in T
                        @constraint(Masterproblem, sum(X[v,p,t,ω] for v in V_p[p]) <= Y[p,t]*s_real_tilde[p,t,ω] + K_ddot[p,t])
                    end
                end
            end
        
            # Constraint (10)
            for ω in Ω_test_partial_1
                for v in V
                    for t in T
                        if t >= tmin
                            @constraint(Masterproblem, I[v,t-1,ω] + sum(X[v,p,t,ω] for p in P_v[v]) == Vc[v,t,ω] + I[v,t,ω])
                        end
                    end
                end
            end
        
            # Constraint (11)
            for ω in Ω_test_partial_1
                for a in A
                    for t in T
                        if t >= tmin
                            @constraint(Masterproblem, d_real_tilde[a,t,ω] - sum(Vc[v,t,ω] for v in V_a[a]) + S[a,t-1,ω] <= S[a,t,ω])
                        end
                    end
                end
            end
        
            # Constraint (12)
            for ω in Ω_test_partial_1
                for p in P
                    for t in T
                        @constraint(Masterproblem, sum(r[v,p,t]*X[v,p,t,ω] for v in V_p[p]) + X_inf[p,t,ω] >= Y[p,t] * sum((1+l[v,p])*f_profit[v,p,t] for v in V_p[p]))
                    end
                end
            end
    
            # Constraint (13)
            for ω in Ω_test_partial_1
                for i in 1:length(starting_points_vect_I)
                    v = starting_points_vect_I[i][1]
                    amount = starting_points_vect_I[i][2]
                    @constraint(Masterproblem, I[v,0,ω] == amount)
                end
            end
    
            # Constraint (14)
            for ω in Ω_test_partial_1
                for i in 1:length(starting_points_vect_S)
                    a = starting_points_vect_S[i][1]
                    amount = starting_points_vect_S[i][2]
                    @constraint(Masterproblem, S[a,0,ω] == amount)
                end
            end
        
            for i in 1:length(starting_points_vect_F)
                a = starting_points_vect_F[i][1]
                t = starting_points_vect_F[i][2]
                tau = starting_points_vect_F[i][3]
                @constraint(Masterproblem, F[a, (t, tau)] == 1)
            end
        
            LB = 0
            UB = 1e30
        
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
                Masterproblem = master_problem(dual_subproblem)
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
                
                # println("Theta: $(JuMP.value.(Masterproblem[:theta]))")
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
                    Subproblem, cons_8_1, cons_8_2, cons_8_3, cons_8_4, cons_8_5, cons_9, cons_10, cons_11, cons_12, cons_13, cons_14 = sub_problem(F_bar, W_bar, Y_bar, Q_bar, L_bar, L_ddot_bar, K_ddot_bar, ω)
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
    
                source = string(current_directory, "/results/T_", tmax, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
                f = open(source, "w")
                JSON.print(f, lb_and_ub_vectors)
                close(f)
        
                LB = Z_M
        
                println("LB: $LB")
                println("UB: $UB")
        
                if (UB - LB) / UB < relaxation_tol
                    # println(F_bar)
                    # println(W_bar)
                    # println(Y_bar)
                    # println(L_bar)
                    # println(I_bar)
                    # println(S_bar)
                    # println(K_ddot_bar)
                    # println(L_ddot_bar)
                    # println(Q_bar)
                    model_type = "L-shaped"
                    save_L_shaped_results(F_bar,Y_bar,W_bar,L_bar,Q_bar,X_sub,I_sub,Vc_sub,S_sub,model_type)
                    println("L_shaped method converged in $time_elapsed seconds after $iter iterations")

                    current_directory = @__DIR__
                    scenarios = length(Ω_test)
                    source = string(current_directory, "/results/log_DE_L_T_", tmax, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
                    
                    deterministic_equivalent_model = deterministic_equivalent(p_ω_test,Ω_test,F_bar,W_bar,Y_bar,L_bar)
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
                    save_L_shaped_results(F_de,Y_de,W_de,L_de,Q_de,X_de,I_de,Vc_de,S_de,model_type)

                    

                    break
                end
        
                iter += 1
            end
        end
    end
end

tender_stochastic_sensitivity(10,5,5,7,1,1,1,1, true, true, false, false, false)