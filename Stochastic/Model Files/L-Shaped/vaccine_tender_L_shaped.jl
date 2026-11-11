using JuMP
using Gurobi
using Random
using DataFrames
using CSV
import XLSX
import JSON
import MathOptInterface
const MOI = MathOptInterface

# Plain single-cut L-shaped method (Benders decomposition) for the stochastic tender model.
# Master: first-stage decisions + one theta for the expected recourse. Subproblems: one LP per scenario.
# One aggregated optimality cut per iteration (complete recourse -> no feasibility cuts).
# Uses the same scenarios/probabilities as vaccine_tender_DE_only.jl so the objective can be compared to the DE.

current_directory = @__DIR__
functions_directory = joinpath(current_directory, "functions")
data_dir = joinpath(current_directory, "data")
results_dir = joinpath(current_directory, "results")

# Include all the function files
include(joinpath(functions_directory, "create_check_params.jl"))
include(joinpath(functions_directory, "load_model_starting_points.jl"))
include(joinpath(functions_directory, "initialize_parameters.jl"))
include(joinpath(functions_directory, "process_scenario_data_n_selected_with_MVP2_demand_scaling.jl"))
include(joinpath(functions_directory, "save_L_shaped_results.jl"))
include(joinpath(functions_directory, "create_vaccine_data.jl"))
include(joinpath(functions_directory, "master_problem.jl"))
include(joinpath(functions_directory, "sub_problem.jl"))
include(joinpath(functions_directory, "generate_optimality_cut.jl"))

# one shared, silent Gurobi environment: no license banner or "Set parameter" lines for every model built
const GRB_ENV = Gurobi.Env(; output_flag = 0)
gurobi_solver = JuMP.optimizer_with_attributes(() -> Gurobi.Optimizer(GRB_ENV), "OutputFlag" => 0, "FeasibilityTol" => 1e-6, "NumericFocus" => 1, "MIPGap" => 1e-4)
gurobi_solver_no_presolve = JuMP.optimizer_with_attributes(() -> Gurobi.Optimizer(GRB_ENV), "OutputFlag" => 0, "FeasibilityTol" => 1e-6, "Presolve" => 0, "NumericFocus" => 1)

function tender_stochastic_L_shaped(
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

    if UNICEF_MODEL
        model = "UNICEF_GAVI"
    elseif SOCIAL_BENEFIT_MODEL
        model = "SOCIAL_BENEFIT"
    else
        model = "MAX_PROFIT"
    end

    unit = 1
    seed = 9            # same as vaccine_tender_DE_only.jl
    iter_max = 500
    gap_tol = 1e-4      # relative (UB - LB) / |UB|
    cut_tol = 1e-6      # relative violation needed to add a cut

    for trial in 1:number_of_trials
        println("trial: $trial")
        demand_growth = 0.01 * (trial - 1)   # same as vaccine_tender_DE_only.jl

        ################################################### INITIALIZE NECESSARY PARAMS ###################################################
        A, V, A_v, P, P_v, V_a, V_p, P_a, A_p, capacity_category, vaccine_category, antigen_category = create_vaccine_data()
        T, T_initial, Δ, s_real, r, r_avg, r_producer_avg, g, h, l, f_profit, Γ, F_time_set, κ, L_lower_number, L_upper_number, delta, beta, zeta_vm, phi_vm_lower, phi_vm_upper, m_segments = initialize_parameters(data_dir, unit, scaled_capacity, max_horizon_length, max_tender_length, P, V, P_v, V_p, allowable_capacity_increase_number)
        Scenarios_used, p_ω_test, p_ω_test_partial_2, Ω_test_partial_1, Ω_test_partial_2, partial_scenario, s_real_tilde, d_real_tilde, random_scenarios, p_ω_MVP, Ω_MVP = process_scenario_data_n_selected_with_MVP2_demand_scaling(current_directory, data_dir, total_capacity_scenarios, number_of_demand_scenarios, A, T, P, scaled_capacity, max_horizon_length, max_tender_length, trial, initial_inventory_rate, allowable_capacity_increase_number, 1, false, unit, demand_growth, seed)
        X_tilde_lower, X_tilde_upper, L_ddot_lower, L_ddot_upper, L_hat_lower, L_hat_upper, L_check_lower, L_check_upper = create_check_params(V, P, P_v, T, F_time_set, s_real, κ, L_upper_number)
        starting_points_vect_F, starting_points_vect_I, starting_points_vect_S = load_model_starting_points(data_dir, initial_inventory_rate, unit, A, V)

        # Full decomposition: every scenario is a subproblem; the master only sees theta
        Ω = random_scenarios

        file_tag = string("_T_", max_horizon_length, "_delta_", max_tender_length, "_scen_", length(Ω), "_trial_", trial, "_demand_growth_", demand_growth, "_inv_", initial_inventory_rate, "_cap._", scaled_capacity, "_cap.inc._", allowable_capacity_increase_number)

        start_time = time()

        ################################################### INITIALIZE MASTER PROBLEM ###################################################
        Masterproblem = JuMP.Model()
        JuMP.set_optimizer(Masterproblem, gurobi_solver)
        # Gurobi log of every master solve -> file only (not the console); Gurobi appends, so start a fresh file
        master_log_file = string(results_dir, "/", model, "_master_log_L_shaped", file_tag, ".log")
        isfile(master_log_file) && rm(master_log_file)
        set_optimizer_attribute(Masterproblem, "LogToConsole", 0)
        set_optimizer_attribute(Masterproblem, "LogFile", master_log_file)
        set_optimizer_attribute(Masterproblem, "OutputFlag", 1)

        Masterproblem = master_problem(Masterproblem, A, F_time_set, V, P_v, P, T, L_lower_number, L_upper_number,
                                        starting_points_vect_F, UNICEF_MODEL, Γ, g, delta, r_avg, P_a, κ, s_real,
                                        L_hat_upper, L_check_upper, V_p, A_p, f_profit, L_ddot_upper, l,
                                        m_segments, zeta_vm, phi_vm_lower, phi_vm_upper, SOCIAL_BENEFIT_MODEL, MAX_PROFIT_MODEL)

        LB = -Inf
        UB = Inf
        lb_vector = Float64[]
        ub_vector = Float64[]
        incumbent = nothing
        iter = 0

        ################################################### L-SHAPED METHOD ###################################################
        while iter < iter_max
            iter += 1

            JuMP.optimize!(Masterproblem)
            println("Solved master problem in $(round(solve_time(Masterproblem), digits = 2)) s")
            if termination_status(Masterproblem) != MOI.OPTIMAL
                println("Master problem status: ", termination_status(Masterproblem))
                if primal_status(Masterproblem) == MOI.NO_SOLUTION
                    compute_conflict!(Masterproblem)
                    iis_model, _ = copy_conflict(Masterproblem)
                    println("MASTER_INFEASIBLE")
                    print(iis_model)
                end
                break
            end

            # master objective bound is a valid lower bound on the stochastic program
            LB = max(LB, JuMP.objective_bound(Masterproblem))
            Z_M = JuMP.objective_value(Masterproblem)

            F_bar = JuMP.value.(Masterproblem[:F])
            W_bar = JuMP.value.(Masterproblem[:W])
            Y_bar = JuMP.value.(Masterproblem[:Y])
            Q_bar = JuMP.value.(Masterproblem[:Q])
            L_bar = JuMP.value.(Masterproblem[:L])
            Z_bar = JuMP.value.(Masterproblem[:Z])
            L_ddot_bar = JuMP.value.(Masterproblem[:L_ddot])
            K_ddot_bar = JuMP.value.(Masterproblem[:K_ddot])
            theta_bar = JuMP.value.(Masterproblem[:theta])

            first_stage_cost = Z_M - theta_bar

            # solve the subproblems and collect each scenario's cut; one aggregated cut is added below
            Z_S = Dict()
            X_sub = Dict()
            I_sub = Dict()
            S_sub = Dict()
            Vc_sub = Dict()
            cut_exprs = Dict()

            for ω in Ω
                Subproblem, cons_14, cons_15, cons_16, cons_17, cons_18, cons_19 = sub_problem(F_bar, W_bar, Y_bar, Q_bar, L_bar, L_ddot_bar, K_ddot_bar, ω, beta, f_profit, delta, r_avg, gurobi_solver_no_presolve,
                    V, P_v, T, T_initial, A, P, F_time_set, 1, V_p, X_tilde_upper, s_real, s_real_tilde, d_real_tilde, V_a, starting_points_vect_I,
                    starting_points_vect_S, r, h, l, zeta_vm, m_segments, κ, UNICEF_MODEL, SOCIAL_BENEFIT_MODEL, MAX_PROFIT_MODEL)

                optimize!(Subproblem)
                println("Solved sub problem $ω in $(round(solve_time(Subproblem), digits = 2)) s")
                if termination_status(Subproblem) != MOI.OPTIMAL || !has_duals(Subproblem)
                    error("Subproblem for scenario $ω not solved to optimality: $(termination_status(Subproblem))")
                end

                Z_S[ω] = JuMP.objective_value(Subproblem)
                X_sub[ω] = JuMP.value.(Subproblem[:X])
                I_sub[ω] = JuMP.value.(Subproblem[:I])
                S_sub[ω] = JuMP.value.(Subproblem[:S])
                Vc_sub[ω] = JuMP.value.(Subproblem[:Vc])

                cut_exprs[ω] = scenario_cut_expression(Masterproblem, ω, Z_S[ω], cons_14, cons_15, cons_16, cons_17, cons_18, cons_19,
                    V, P_v, P, T, F_time_set, m_segments, s_real_tilde)
            end

            # expected recourse at the current first-stage solution
            Z_S_expected = sum(p_ω_test[ω] * Z_S[ω] for ω in Ω)

            # add the aggregated cut only if theta underestimates the expected recourse
            num_cuts = 0
            if theta_bar < Z_S_expected - cut_tol * max(1.0, abs(Z_S_expected))
                generate_optimality_cut(Masterproblem, cut_exprs, p_ω_test)
                num_cuts = 1
            end

            # current first-stage solution + its exact recourse is a feasible solution -> upper bound
            UB_candidate = first_stage_cost + Z_S_expected
            if UB_candidate < UB
                UB = UB_candidate
                incumbent = (F_bar, Y_bar, W_bar, L_bar, Q_bar, X_sub, I_sub, Vc_sub, S_sub, Z_bar)
            end

            push!(lb_vector, LB)
            push!(ub_vector, UB)
            gap = (UB - LB) / max(abs(UB), 1e-10)
            println("Iteration $iter  LB: $LB  UB: $UB  gap: $gap  cuts added: $num_cuts")

            f = open(string(results_dir, "/", model, "_L_shaped_bounds", file_tag, ".json"), "w")
            JSON.print(f, Dict("lb" => lb_vector, "ub" => ub_vector, "run_time" => time() - start_time))
            close(f)

            if gap < -gap_tol
                # with valid cuts LB <= UB always holds; stop instead of reporting a false convergence
                println("WARNING: LB > UB (gap $gap) - check the cuts")
                break
            elseif gap <= gap_tol || num_cuts == 0
                println(num_cuts == 0 ? "No violated cuts - optimal" : "Gap tolerance reached")
                break
            end
        end

        time_elapsed = time() - start_time
        println("L-shaped method finished in $time_elapsed seconds after $iter iterations")
        println("Objective (best UB): $UB")

        if incumbent !== nothing
            F_bar, Y_bar, W_bar, L_bar, Q_bar, X_sub, I_sub, Vc_sub, S_sub, Z_bar = incumbent
            save_L_shaped_results(F_bar, Y_bar, W_bar, L_bar, Q_bar, X_sub, I_sub, Vc_sub, S_sub, Z_bar, "L-shaped-phase1", A, T, T_initial,
                P, P_v, V, V_p, Ω, F_time_set, Ω, capacity_category, antigen_category,
                vaccine_category, max_horizon_length, max_tender_length, trial, initial_inventory_rate, scaled_capacity,
                allowable_capacity_increase_number, number_of_demand_scenarios, total_capacity_scenarios,
                p_ω_test, κ, s_real, s_real_tilde, results_dir, m_segments)
        end
    end
end

# (horizon, max tender length, demand scenarios, capacity scenarios, ...) -> 5 x 7 = 35 scenario pairs
tender_stochastic_L_shaped(10,5,5,7,1,1,1,2, true, true, true, false, false)
