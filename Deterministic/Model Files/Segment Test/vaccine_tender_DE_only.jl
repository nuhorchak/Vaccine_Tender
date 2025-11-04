using JuMP
using Gurobi
using Random
using Dualization
using Plots
using DataFrames, XLSX
using CSV 
import XLSX
import JSON
import MathOptInterface

current_directory = @__DIR__
println(current_directory)
functions_directory = joinpath(current_directory, "functions")
data_dir = joinpath(current_directory, "data")
# functions_directory = joinpath(current_directory, "..", "functions")
# data_dir = joinpath(current_directory, "..", "data")
results_dir = joinpath(current_directory, "results")

# Include all the function files
include(joinpath(functions_directory, "create_check_params.jl"))
include(joinpath(functions_directory, "deterministic_equivalent.jl"))
include(joinpath(functions_directory, "generate_cuts_from_dual.jl"))
include(joinpath(functions_directory, "load_model_starting_points.jl"))
include(joinpath(functions_directory, "initialize_parameters.jl"))
include(joinpath(functions_directory, "process_scenario_data.jl"))
include(joinpath(functions_directory, "process_scenario_data_n_selected_with_MVP2_demand_scaling.jl"))
include(joinpath(functions_directory, "save_L_shaped_results.jl"))
include(joinpath(functions_directory, "select_random_scenarios.jl"))
include(joinpath(functions_directory, "create_vaccine_data.jl"))
include(joinpath(functions_directory, "sub_problem.jl"))
include(joinpath(functions_directory, "master_problem.jl"))

gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-4, "OutputFlag" => 0, "Presolve" => 0, "NumericFocus" => 1, "MIPGap" => 1e-4)#, "Threads" => 32) 
gurobi_solver_DE = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-4, "OutputFlag" => 1, "Presolve" => 1, "NumericFocus" => 1, "MIPGap" => 1.5e-2)#8.5e-2)#, "Threads" => 32) 
gurobi_solver_no_presolve = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-2, "OutputFlag" => 0, "Presolve" => 0, "NumericFocus" => 1, "MIPGap" => 1e-2)#, "Threads" => 32) 

# Base offset for the seed (S₀)
const BASE_OFFSET = 10 

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
    global current_seed = 1
    global demand_growth = 0.0

    # --- Initialization ---

    # Initial increase for Trial 1 (k)
    current_increase = 10 
    # The seed starts at BASE_OFFSET + initial increase
    current_seed = BASE_OFFSET + current_increase

    for trial in 1:number_of_trials
        # seed = rand(1:99999)
        demand_growth = 0.0
        println("trial: $trial")
        source = string(results_dir, "/model_", model, "log_DE_L_T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",number_of_demand_scenarios*total_capacity_scenarios,"_trial_",trial,"_demand_growth_",demand_growth,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
            overlap_decision = true

        # # demand_growth = 0.01 * (trial - 1)
        # demand_growth = (0.4rand() - 0.1)
        # println("Demand Growth for trial $trial is: $demand_growth")

    
        ################################################### INITIALIZE NECESSARY PARAMS ###################################################
        #load vaccine dict data
        A, V, A_v, P, P_v, V_a, V_p, P_a, A_p, capacity_category, vaccine_category, antigen_category = create_vaccine_data()
        T, T_initial, Δ, s_real, r, r_avg, r_producer_avg, g, h, l, f_profit, Γ, F_time_set, κ, L_lower_number, L_upper_number, delta, beta, zeta_vm, phi_vm_lower, phi_vm_upper, m_segments = initialize_parameters(data_dir, unit, scaled_capacity, max_horizon_length, max_tender_length, P, V, P_v, V_p, allowable_capacity_increase_number)
        # Scenarios_used, p_ω_test, p_ω_test_partial_2, Ω_test_partial_1, Ω_test_partial_2, partial_scenario, s_real_tilde, d_real_tilde, random_scenarios = process_scenario_data_n_selected(current_directory, data_dir, total_capacity_scenarios, number_of_demand_scenarios, A, T, P, scaled_capacity, max_horizon_length, max_tender_length, trial, initial_inventory_rate, allowable_capacity_increase_number, 1)
        # Scenarios_used, p_ω_test, p_ω_test_partial_2, Ω_test_partial_1, Ω_test_partial_2, partial_scenario, s_real_tilde, d_real_tilde, random_scenarios = process_scenario_data_n_selected_with_MVP2(current_directory, data_dir, total_capacity_scenarios, number_of_demand_scenarios, A, T, P, scaled_capacity, max_horizon_length, max_tender_length, trial, initial_inventory_rate, allowable_capacity_increase_number, 1, true, unit,current_seed)
        random_scenarios, s_real_tilde, d_real_tilde = process_scenario_data_n_selected_with_MVP2_demand_scaling(current_directory, data_dir, total_capacity_scenarios, number_of_demand_scenarios, A, T, P, scaled_capacity, max_horizon_length, max_tender_length, trial, initial_inventory_rate, allowable_capacity_increase_number, 1, true, unit, demand_growth, current_seed)
        X_tilde_lower, X_tilde_upper, L_ddot_lower, L_ddot_upper, L_hat_lower, L_hat_upper, L_check_lower, L_check_upper = create_check_params(V, P, P_v, T, F_time_set, s_real, κ, L_upper_number)
        
        starting_points_vect_F, starting_points_vect_I, starting_points_vect_S = load_model_starting_points(data_dir, initial_inventory_rate, unit, A, V)
        # cuts_dict = Dict()

        println(d_real_tilde)

        start_time = time()
    
        ################################################### INITIALIZE DE ###################################################
        Deterministic_Equivalent = JuMP.Model()
        JuMP.set_optimizer(Deterministic_Equivalent, gurobi_solver_DE)
        # set_optimizer_attribute(Deterministic_Equivalent, "TimeLimit", 500)
        # source1 = string(results_dir, "/", model, "_log_Phase1_L_T_", max_horizon_length, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_demand_growth_",demand_growth,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
        source1 = normpath(joinpath(results_dir,
        string(model, "_log_Phase1_L_T_", max_horizon_length,
           "_delta_", max_tender_length,
           "_scen_", length(random_scenarios),
           "_trial_", trial,
           "_demand_growth_", demand_growth,
           "_inv_", initial_inventory_rate,
           "_cap_", scaled_capacity,
           "_cap_inc_", allowable_capacity_increase_number,
           ".json")))

        # Deterministic_Equivalent = deterministic_equivalent(p_ω_test, random_scenarios, g, beta, Γ, gurobi_solver_DE,
        # A, A_p, F_time_set, V, P_v, T, T_initial, P, P_a, starting_points_vect_F, starting_points_vect_I, 
        # starting_points_vect_S, capacity_extension_decision, UNICEF_MODEL, L_lower_number, L_upper_number,
        # κ, s_real, L_hat_upper, L_check_upper, d_real_tilde, X_tilde_upper, s_real_tilde, 1, 
        # r, r_avg, h, V_p, l, f_profit, V_a, delta, L_ddot_upper, overlap_decision, Ω_test_partial_1, Ω_test_partial_2, m_segments,zeta_vm, phi_vm_lower, phi_vm_upper, SOCIAL_BENEFIT_MODEL, MAX_PROFIT_MODEL)

        #SOLVING 1 SCENARIO MVP
        # Deterministic_Equivalent = deterministic_equivalent(1, 1, g, beta, Γ, gurobi_solver_DE,
        # A, A_p, F_time_set, V, P_v, T, T_initial, P, P_a, starting_points_vect_F, starting_points_vect_I, 
        # starting_points_vect_S, capacity_extension_decision, UNICEF_MODEL, L_lower_number, L_upper_number,
        # κ, s_real, L_hat_upper, L_check_upper, d_real_tilde, X_tilde_upper, s_real_tilde, 1, 
        # r, r_avg, h, V_p, l, f_profit, V_a, delta, L_ddot_upper, overlap_decision, Ω_test_partial_1, Ω_test_partial_2, 
        # m_segments,zeta_vm, phi_vm_lower, phi_vm_upper, SOCIAL_BENEFIT_MODEL, MAX_PROFIT_MODEL, true)

        #SOLVING 1 suppyl and demand explicit
        Deterministic_Equivalent = deterministic_equivalent(1, 1, g, beta, Γ, gurobi_solver_DE,
        A, A_p, F_time_set, V, P_v, T, T_initial, P, P_a, starting_points_vect_F, starting_points_vect_I, 
        starting_points_vect_S, capacity_extension_decision, UNICEF_MODEL, L_lower_number, L_upper_number,
        κ, s_real, L_hat_upper, L_check_upper, d_real_tilde, X_tilde_upper, s_real_tilde, 1, 
        r, r_avg, h, V_p, l, f_profit, V_a, delta, L_ddot_upper, overlap_decision, Nothing, Nothing, 
        m_segments,zeta_vm, phi_vm_lower, phi_vm_upper, SOCIAL_BENEFIT_MODEL, MAX_PROFIT_MODEL, true)

        set_optimizer_attribute(Deterministic_Equivalent, "LogFile", source1)
        # set_optimizer_attribute(Deterministic_Equivalent, "TimeLimit", 5000)
        JuMP.optimize!(Deterministic_Equivalent)

    
        if primal_status(Deterministic_Equivalent) == MOI.NO_SOLUTION
            compute_conflict!(Deterministic_Equivalent)
            iis_model, _ = copy_conflict(Deterministic_Equivalent)
            println("MASTER_INFEASIBLE")
            print(iis_model)
        end

        println("DE Model status: ", termination_status(Deterministic_Equivalent))
        OBJ_value = JuMP.objective_value(Deterministic_Equivalent)
        println("Objective Value: $OBJ_value")
    
        global F_bar = JuMP.value.(Deterministic_Equivalent[:F])
        global W_bar = JuMP.value.(Deterministic_Equivalent[:W])
        global Y_bar = JuMP.value.(Deterministic_Equivalent[:Y])
        global Q_bar = JuMP.value.(Deterministic_Equivalent[:Q])
        global L_bar = JuMP.value.(Deterministic_Equivalent[:L])
        global Z_bar = JuMP.value.(Deterministic_Equivalent[:Z])
        global X_bar = JuMP.value.(Deterministic_Equivalent[:X])
        global I_bar = JuMP.value.(Deterministic_Equivalent[:I])
        global Vc_bar = JuMP.value.(Deterministic_Equivalent[:Vc])
        global S_bar = JuMP.value.(Deterministic_Equivalent[:S])

        # println("F_bar: ", F_bar)
        # println("W_bar: ", W_bar)
        # println("Y_bar: ", Y_bar)
        # println("Q_bar: ", Q_bar)
        # println("L_bar: ", L_bar)
        # println("Z_bar: ", Z_bar)
        # println("X_bar: ", X_bar)
        # println("I_bar: ", I_bar)
        # println("Vc_bar: ", Vc_bar)
        # println("S_bar: ", S_bar)



        model_type = "MVP"
        if number_of_demand_scenarios + total_capacity_scenarios > 2
            save_L_shaped_results(F_bar,Y_bar,W_bar,L_bar,Q_bar,X_bar,I_bar,Vc_bar,S_bar,Z_bar, model_type, A, T, T_initial, 
            P, P_v, V, V_p, random_scenarios, F_time_set, random_scenarios, capacity_category, antigen_category, 
            vaccine_category, max_horizon_length, max_tender_length, trial, initial_inventory_rate, scaled_capacity, 
            allowable_capacity_increase_number, number_of_demand_scenarios, total_capacity_scenarios, 
            p_ω_test, κ, s_real, s_real_tilde, results_dir, m_segments)
        else
            save_L_shaped_results(F_bar,Y_bar,W_bar,L_bar,Q_bar,X_bar,I_bar,Vc_bar,S_bar,Z_bar, model_type, A, T, T_initial, 
            P, P_v, V, V_p, random_scenarios, F_time_set, random_scenarios, capacity_category, antigen_category, 
            vaccine_category, max_horizon_length, max_tender_length, trial, initial_inventory_rate, scaled_capacity, 
            allowable_capacity_increase_number, number_of_demand_scenarios, total_capacity_scenarios, 
            Nothing, κ, s_real, s_real_tilde, results_dir, m_segments)
        end

        println("Manual calculation of the objective value function:")

        F_OBJ = 0.0
        Q_OBJ = 0.0
        I_OBJ = 0.0
        S_OBJ = 0.0
        L_OBJ = 0.0
        Y_OBJ = 0.0
        obj_manual = 0.0
        LHS_value=Float64[]
        RHS_value=Float64[]

        # Term 1: Tender duration cost
        for (t, tau) in F_time_set, a in A
            if (a, t, tau) ∉ starting_points_vect_F
                F_OBJ += g[t] * value(Deterministic_Equivalent[:F][a, (t, tau)]) / delta[t]
            end
        end
        
        if UNICEF_MODEL
            # Term 2: Procurement cost (apply filtering on Q > 0)
            for (t, tau) in F_time_set, v in V, p in P_v[v], m in keys(m_segments)
                q_val = value(Deterministic_Equivalent[:Q][v, p, (t, tau), m])
                if q_val > 0
                    Q_OBJ += r_avg[v, t] * (1 - zeta_vm[v, m]) * q_val / delta[t]
                end
            end
        elseif SOCIAL_BENEFIT_MODEL
            # Term 2: Procurement cost (apply filtering on Q > 0)
            for (t, tau) in F_time_set, v in V, p in P_v[v], m in keys(m_segments)
                q_val = value(Deterministic_Equivalent[:Q][v, p, (t, tau), m])
                if q_val > 0
                    Q_OBJ += r_avg[v, t] * (1 - zeta_vm[v, m]) * q_val / delta[t]
                end
            end
        else
            # Term 2: Procurement cost (apply filtering on Q > 0)
            for (t, tau) in F_time_set, v in V, p in P_v[v], m in keys(m_segments)
                q_val = value(Deterministic_Equivalent[:Q][v, p, (t, tau), m])
                if q_val > 0
                    Q_OBJ += -r_avg[v, t] * (1 - zeta_vm[v, m]) * q_val / delta[t]
                end
            end
        end

        if UNICEF_MODEL
            # Term 3: Missed dose penalty
            for a in A, t in T
                S_OBJ += 1 * beta * value(Deterministic_Equivalent[:S][a, t, 1]) / delta[t]
            end
        elseif SOCIAL_BENEFIT_MODEL
            # Term 3: Missed dose penalty
            for a in A, t in T
                S_OBJ += 1 * beta * value(Deterministic_Equivalent[:S][a, t, 1]) / delta[t]
            end
        else
            # Term 3: Final period weighted revenue
            for a in A, v in V
                S_OBJ += 1 * (r_avg[v, last(T)] * value(Deterministic_Equivalent[:S][a, last(T), 1])) / delta[last(T)]
            end
        end

        # Term 4: Inventory holding cost
        for v in V, t in T
            I_OBJ += 1 * h[v] * r_avg[v, t] * value(Deterministic_Equivalent[:I][v, t, 1]) / delta[t]
        end

        # Term 5: Production capacity increase
        for p in P, t in T
            L_OBJ += Γ[p] * value(Deterministic_Equivalent[:L][p,t]) / delta[t]
        end

        # Term 6: Producer producing in period
        for v in V, p in P_v[v], (t,tau) in F_time_set
            Y_OBJ += f_profit[v,p,(t,tau)] * value(Deterministic_Equivalent[:Y][p,t]) / delta[t]
        end

        results = DataFrame(
            p = String[],
            t = Int[],
            tau = Int[],
            Q = Float64[],
            W = Float64[],
            ravg = Float64[],
            zetavm = Float64[],
            used_segments = Vector{Int}[],   # store vectors directly
            vaccines = Vector{String}[],
            lhs = Float64[],
            rhs = Float64[],
            rhs_adjusted = Float64[]
        )

        used_segments = []
        vaccines = []


        if UNICEF_MODEL
            obj_manual = F_OBJ + Q_OBJ + S_OBJ + I_OBJ
            println("F Objective value: ", F_OBJ)
            println("Q Objective value: ", Q_OBJ)
            println("S Objective value: ", S_OBJ)
            println("I Objective value: ", I_OBJ)
            println("L Objective value: ", L_OBJ)
            println("Y Objective value: ", Y_OBJ)
            println("Total Objective value: ", obj_manual)

            # producer_profits = Dict{String, Float64}()

            # for p in P
            #     total_profit_p = 0.0
            #     for v in V_p[p]
            #         for (t,tau) in F_time_set
            #             for m in keys(m_segments)
            #                 total_profit_p += r_avg[v, t] * (1 - zeta_vm[v, m]) * Deterministic_Equivalent[:Q][v, p, (t, tau), m]
            #             end
            #         end
            #     end
            #     producer_profits[p] = value(total_profit_p)
            # end

            # # Define the filename for the Excel file
            # num_m_segments = length(keys(m_segments))
            # filename = "producer_profits_$(num_m_segments)_segments.xlsx"

            # # Write the data to the Excel file
            # XLSX.openxlsx(filename, mode="w") do xf
            #     sheet = xf[1]
                
            #     # Write the column headers
            #     sheet["A1"] = "Producer"
            #     sheet["B1"] = "Total Profit"
                
            #     # Use a counter to track the row number
            #     row = 2
                
            #     # Loop through the dictionary and write each key-value pair to a new row
            #     for (p, profit) in producer_profits
            #         sheet["A$(row)"] = p
            #         sheet["B$(row)"] = profit
            #         row += 1
            #     end
            # end

            # println("Successfully saved producer_profits to $(filename)")
            # println("Profits: ", producer_profits)
            
        elseif SOCIAL_BENEFIT_MODEL
            obj_manual = S_OBJ
            println("F Objective value: ", F_OBJ)
            println("Q Objective value: ", Q_OBJ)
            println("S Objective value: ", S_OBJ)
            println("I Objective value: ", I_OBJ)
            println("L Objective value: ", L_OBJ)
            println("Y Objective value: ", Y_OBJ)
            println("Total Objective value: ", obj_manual)
        else
            obj_manual = Q_OBJ + S_OBJ + L_OBJ + Y_OBJ
            println("F Objective value: ", F_OBJ)
            println("Q Objective value: ", Q_OBJ)
            println("S Objective value: ", S_OBJ)
            println("I Objective value: ", I_OBJ)
            println("Y Objective value: ", L_OBJ)
            println("L Objective value: ", Y_OBJ)
            println("Total Objective value: ", obj_manual)
        end
        
        # 3. Update the seed and increase for the NEXT trial
        # The increase for the next trial doubles
        current_increase *= 2 
        # The seed for the next trial increases by the new, doubled amount
        current_seed += current_increase

    end #end trials
end # end function

tender_stochastic_sensitivity(10,5,1,1,5,1,1,1, true, true, false, false, true)