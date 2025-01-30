# HCVM - Hypothetically Coordinated Vaccine Market

HCVM optimization model:

L-Shaped/Final_codes: Main model file vaccine_tender_L_shaped_scenario_pairs_all_objectives_functionalized.jl

L-Shaped/Final_codes/functions: Functions used in main model
- create_check_params.jl: helper function, creates params used in McCormack relaxation

- deterministic_equivalent.jl: deterministic equivalent model

- generate_dual_cuts.jl: helper function, used to generate cuts for L-Shaped model

- load_model_starting_points.jl: helper function to load initial conditions

- load_params.jl: helper function to load model parameters

- load_scenarios.jl: helper function to load model scenarios

- master_problem.jl: master problem for two stage stochastic model

- save_L_Shape_results.jl: helper function to save results into corresponding files

- select_random_scenarios.jl: helper function to randomly select scenarios, if not all scenarios are specified in main function call

- setup_vax_info.jl: helper function to load vaccine lists and dicts

- sub_problem.jl: sub problem for two stage stochastic model