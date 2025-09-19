"""
process_scenario_data(data_dir, total_capacity_scenarios, number_of_demand_scenarios, A, T, P, scaled_capacity, tmax, max_tender_length, trial, initial_inventory_rate, allowable_capacity_increase_number)

Processes scenario data for demand and capacity based on input parameters, selecting random scenarios, calculating probabilities, and saving the results to a JSON file.

# Arguments:
-`current_directory::String`: Directory path of current directory
- `data_dir::String`: Directory path where the JSON files (`scenario_pair_probabilities_new.json` and `scenario_pairs_new.json`) are located.
- `total_capacity_scenarios::Int`: Total capacity scenarios used for random selection scaling.
- `number_of_demand_scenarios::Int`: Number of demand scenarios to select.
- `A::Vector`: Set of attributes (e.g., product types or locations).
- `T::Vector`: Set of time periods.
- `P::Vector`: Set of production units or plants.
- `scaled_capacity::Float64`: Scaling factor for capacity values.
- `tmax::Int`: Maximum time horizon.
- `max_tender_length::Int`: Maximum tender length.
- `trial::Int`: Trial identifier for the simulation.
- `initial_inventory_rate::Float64`: Initial inventory rate parameter.
- `allowable_capacity_increase_number::Int`: Number of allowable capacity increases.

# Returns:
- `Scenarios_used::Dict`: Dictionary containing the full (`"All"`) and partial (`"Partial_1"`, `"Partial_2"`) scenario sets used.
- `p_ω_test::Dict`: Dictionary of normalized probabilities for the selected test scenarios.
- `p_ω_test_partial_2::Dict`: Dictionary of normalized probabilities for the reduced test scenarios (excluding `"Partial_1"`).

# Notes:
- The function saves the `Scenarios_used` dictionary to a JSON file in the `results` subdirectory of `data_dir`.
"""

function process_scenario_data(
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
    allowable_capacity_increase_number::Int
)
    # Load scenario pair probabilities
    scenario_pair_probs_path = joinpath(data_dir, "scenario_pair_probabilities_new.json")
    # println("In process_scenario_data, scenario probs path: $scenario_pair_probs_path")
    scenario_pair_probs = JSON.parsefile(scenario_pair_probs_path)

    total_scenarios = length(scenario_pair_probs)
    random_scenarios = select_random_scenarios(1, ceil(Int, total_scenarios / total_capacity_scenarios), number_of_demand_scenarios, total_capacity_scenarios, 22)

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

    max_cap_value = maximum(values(capacity_dict))
    max_cap_keys = [k for k in keys(capacity_dict) if capacity_dict[k] == max_cap_value]
    filtered_demand_dict = filter(kv -> kv[1] in max_cap_keys, demand_dict)
    max_key_final = argmax(filtered_demand_dict)

    subset_probs_dict = Dict(ω => scenario_pair_probs["$ω"] for ω in random_scenarios if haskey(scenario_pair_probs, "$ω"))
    partial_scenario = max_key_final

    index_number = findfirst(x -> x == partial_scenario, random_scenarios)
    reduced_random_scenarios = copy(random_scenarios)
    deleteat!(reduced_random_scenarios, index_number)

    Ω_test_partial_1 = [partial_scenario]
    Ω_test_partial_2 = reduced_random_scenarios

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
