function process_scenario_data_n_selected(
    current_directory::String,
    data_dir::String, 
    total_capacity_scenarios::Int, 
    number_of_demand_scenarios::Int, 
    A::Vector, 
    T::Vector, 
    P::Vector, 
    scaled_capacity::Int, 
    tmax::Int, 
    max_tender_length::Int, 
    trial::Int, 
    initial_inventory_rate::Int, 
    allowable_capacity_increase_number::Int,
    num_MP_scenarios::Int  # New input parameter
)
    # Load scenario pair probabilities
    scenario_pair_probs_path = joinpath(data_dir, "scenario_pair_probabilities_new.json")
    scenario_pair_probs = JSON.parsefile(scenario_pair_probs_path)

    total_scenarios = length(scenario_pair_probs)
    random_scenarios = select_random_scenarios(1, ceil(Int, total_scenarios / total_capacity_scenarios), number_of_demand_scenarios, total_capacity_scenarios)

    # Load scenario pairs
    scenario_pairs_path = joinpath(data_dir, "scenario_pairs_new.json")
    scenario_pairs = JSON.parsefile(scenario_pairs_path)

    unit = 1000
    Ω_test = random_scenarios

    d_real_tilde = Dict()
    s_real_tilde = Dict()
    demand_dict = Dict()
    capacity_dict = Dict()

    for ω in Ω_test
        total_demand = 0.0
        for a in A
            for t in T
                d_real_tilde[a, t, ω] = round(scenario_pairs["$ω"]["demand"]["$t"]["$a"] / unit, digits=0)
                total_demand += d_real_tilde[a, t, ω]
            end
        end
        demand_dict[ω] = total_demand
    end

    for ω in Ω_test
        total_capacity = 0.0
        for p in P
            for t in T
                s_real_tilde[p, t, ω] = round(scenario_pairs["$ω"]["capacity"]["$t"]["$p"] * scaled_capacity / unit, digits=0)
                total_capacity += s_real_tilde[p, t, ω]
            end
        end
        capacity_dict[ω] = total_capacity
    end

    # Random selection of num_MP_scenarios scenarios for Ω_test_partial_1
    num_MP_scenarios = min(num_MP_scenarios, length(Ω_test))  # Ensure we don't select more than available
    shuffled_indices = randperm(length(Ω_test))  # Generate a random permutation of indices
    Ω_test_partial_1 = [Ω_test[i] for i in shuffled_indices[1:num_MP_scenarios]]  # Select random scenarios

    # Remove selected scenarios from the full set to create Ω_test_partial_2
    Ω_test_partial_2 = [ω for ω in Ω_test if ω ∉ Ω_test_partial_1]

    # Select one scenario randomly as the partial_scenario
    partial_scenario = Ω_test_partial_1[rand(1:length(Ω_test_partial_1))]

    total_probs = sum(scenario_pair_probs["$ω"] for ω in Ω_test)
    p_ω_test = Dict(ω => scenario_pair_probs["$ω"] / total_probs for ω in Ω_test)

    total_probs_partial_2 = sum(scenario_pair_probs["$ω"] for ω in Ω_test_partial_2)
    p_ω_test_partial_2 = Dict(ω => scenario_pair_probs["$ω"] / total_probs_partial_2 for ω in Ω_test_partial_2)

    Scenarios_used = Dict(
        "All" => Ω_test,
        "Partial_1" => Ω_test_partial_1,
        "Partial_2" => Ω_test_partial_2
    )

    result_file = string(current_directory, "/results/scenarios_", tmax, "_delta_", max_tender_length, "_scen_", 
                         length(random_scenarios), "_trial_", trial, "_inv_", initial_inventory_rate, 
                         "_cap._", scaled_capacity, "_cap.inc._", allowable_capacity_increase_number, ".json")
    open(result_file, "w") do f
        JSON.print(f, Scenarios_used)
    end

    return Scenarios_used, p_ω_test, p_ω_test_partial_2, Ω_test_partial_1, Ω_test_partial_2, partial_scenario, s_real_tilde, d_real_tilde, random_scenarios
end
