using Statistics
using Random
using JSON

function process_scenario_data_n_selected_with_MVP2_demand_scaling(
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
    num_MP_scenarios::Int,
    MVP::Bool,
    unit::Int,
    demand_growth_rate::Float64,
    seed::Int,
)
    scenario_pair_probs_path = joinpath(data_dir, "scenario_pair_probabilities_new_15YR_NO_MMR.json")
    scenario_pair_probs = JSON.parsefile(scenario_pair_probs_path)

    # Convert keys to integers and sort them to maintain order
    all_scenario_keys_sorted = sort(parse.(Int, collect(keys(scenario_pair_probs))))

    # Determine the maximum number of scenarios allowed to be selected
    max_scenarios_to_select = total_capacity_scenarios * number_of_demand_scenarios

    # Ensure we don't try to select more scenarios than available
    if max_scenarios_to_select > length(all_scenario_keys_sorted)
        @warn "Requested maximum scenarios ($max_scenarios_to_select) exceeds available scenarios ($(length(all_scenario_keys_sorted))). Selecting all available scenarios."
        max_scenarios_to_select = length(all_scenario_keys_sorted)
    end

    # Set seed for reproducibility
    println("Demand current seed: $seed")
    Random.seed!(seed)

    # --- New Logic: Select a random central scenario and then its neighbors ---

    # 1. Select a random central scenario from all available scenarios
    central_scenario_index = rand(1:length(all_scenario_keys_sorted))
    central_scenario_value = all_scenario_keys_sorted[central_scenario_index]

    selected_keys_set = Set{Int}() # Use a Set for efficient checking for duplicates
    push!(selected_keys_set, central_scenario_value)

    # Initialize pointers for expanding outwards
    left_ptr = central_scenario_index - 1
    right_ptr = central_scenario_index + 1

    # Expand outwards until we have enough scenarios or hit bounds
    while length(selected_keys_set) < max_scenarios_to_select
        can_go_left = (left_ptr >= 1)
        can_go_right = (right_ptr <= length(all_scenario_keys_sorted))

        if !can_go_left && !can_go_right # No more scenarios to add
            break
        elseif can_go_left && can_go_right # Both directions are possible
            # Randomly choose to go left or right (biased towards more available side if one runs out sooner)
            # A more balanced approach: check remaining capacity and distribute roughly evenly
            remaining_to_add = max_scenarios_to_select - length(selected_keys_set)
            
            # If we need to add an odd number, one side will get one more.
            # Randomly decide which side gets the extra one if needed.
            
            if rand(Bool) # Randomly choose left or right to add next
                if can_go_left
                    push!(selected_keys_set, all_scenario_keys_sorted[left_ptr])
                    left_ptr -= 1
                elseif can_go_right # If left is exhausted, try right
                    push!(selected_keys_set, all_scenario_keys_sorted[right_ptr])
                    right_ptr += 1
                end
            else
                if can_go_right
                    push!(selected_keys_set, all_scenario_keys_sorted[right_ptr])
                    right_ptr += 1
                elseif can_go_left # If right is exhausted, try left
                    push!(selected_keys_set, all_scenario_keys_sorted[left_ptr])
                    left_ptr -= 1
                end
            end
        elseif can_go_left # Only left is possible
            push!(selected_keys_set, all_scenario_keys_sorted[left_ptr])
            left_ptr -= 1
        elseif can_go_right # Only right is possible
            push!(selected_keys_set, all_scenario_keys_sorted[right_ptr])
            right_ptr += 1
        end
    end

    # Convert the set back to a sorted array for consistent ordering
    selected_keys = sort(collect(selected_keys_set))
    random_scenarios = selected_keys

    # Create a new dictionary with the selected keys
    selected_scenario_probs = Dict(string(k) => scenario_pair_probs[string(k)] for k in selected_keys)

    # Load scenario pairs
    scenario_pairs_path = joinpath(data_dir, "scenario_pairs_new_1_scenario_15YR_NO_MMR.json")
    scenario_pairs = JSON.parsefile(scenario_pairs_path)
    selected_scenario_pairs = Dict(string(k) => scenario_pairs[string(k)] for k in selected_keys)

    Ω_test = random_scenarios

    d_real_tilde = Dict()
    s_real_tilde = Dict()
    demand_dict = Dict()
    capacity_dict = Dict()

    # for ω in Ω_test
    #     total_demand = 0.0
    #     for a in A
    #         for t in T
    #             d_real_tilde[a, t, ω] = round(scenario_pairs["$ω"]["demand"]["$t"]["$a"] / unit, digits=0)
    #             total_demand += d_real_tilde[a, t, ω]
    #         end
    #     end
    #     demand_dict[ω] = total_demand
    # end

    for ω in Ω_test
        total_demand = 0.0
        for a in A
            # new_rate = round((0.6 + 0.9 * rand()), digits=2) # demand_growth_rate)
            for t in T
                growth_multiplier = t == 1 ? 1.0 : round((0.7 + 0.8 * rand()), digits=2) # demand_growth_rate)
                d_real_tilde[a, t, ω] = round(
                    (scenario_pairs["$ω"]["demand"]["$t"]["$a"] * growth_multiplier) / unit,
                    digits=2,
                )
                total_demand += d_real_tilde[a, t, ω]
            end
        end
        demand_dict[ω] = total_demand
    end

    for ω in Ω_test
        total_capacity = 0.0
        for p in P
            # new_prod_rate = (0.6 + 0.8 * rand())
            for t in T
                # scaled_capacity_multiplier = t == 1 ? 1.0 : scaled_capacity # new_prod_rate
                s_real_tilde[p, t, ω] = round(scenario_pairs["$ω"]["capacity"]["$t"]["$p"] * (scaled_capacity) / unit, digits=2) #(1 + scaled_capacity_multiplier) / unit, digits=5)
                total_capacity += s_real_tilde[p, t, ω]
            end
        end
        capacity_dict[ω] = total_capacity
    end

    if total_capacity_scenarios + number_of_demand_scenarios > 2
        # Random selection of num_MP_scenarios scenarios for Ω_test_partial_1
        num_MP_scenarios = min(num_MP_scenarios, length(Ω_test))
        shuffled_indices = randperm(length(Ω_test))
        Ω_test_partial_1 = [Ω_test[i] for i in shuffled_indices[1:num_MP_scenarios]]

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

        println(Scenarios_used)
    end

    Ω_MVP = Set()
    p_ω_MVP = Dict()

    if MVP
        MVP_scenario = 1
        Ω_MVP = Set([MVP_scenario])

        # Compute average demand and capacity
        d_real_tilde_MVP = Dict()
        s_real_tilde_MVP = Dict()

        for a in A
            for t in T
                d_real_tilde_MVP[a, t, MVP_scenario] = round(Statistics.mean([d_real_tilde[a, t, ω] for ω in Ω_test]), digits=2)
            end
        end

        for p in P
            for t in T
                s_real_tilde_MVP[p, t, MVP_scenario] = round(Statistics.mean([s_real_tilde[p, t, ω] for ω in Ω_test]), digits=2)
            end
        end

        # Assign probability 1 to MVP scenario
        p_ω_MVP[MVP_scenario] = 1.0

        # Override outputs with MVP results
        s_real_tilde = s_real_tilde_MVP
        d_real_tilde = d_real_tilde_MVP
    end

    #use random_scenarios for full set, Ω_MVP for MVP
    if total_capacity_scenarios + number_of_demand_scenarios > 2
        if MVP
            result_file = string(current_directory, "/results/scenarios_", tmax, "_delta_", max_tender_length, "_scen_",
                                length(Ω_MVP), "_trial_", trial, "_inv_", initial_inventory_rate,
                                "_cap._", scaled_capacity, "_cap.inc._", allowable_capacity_increase_number, ".json")
            open(result_file, "w") do f
                JSON.print(f, Scenarios_used)
            end
        else
            result_file = string(current_directory, "/results/scenarios_", tmax, "_delta_", max_tender_length, "_scen_",
                                length(random_scenarios), "_trial_", trial, "_inv_", initial_inventory_rate,
                                "_cap._", scaled_capacity, "_cap.inc._", allowable_capacity_increase_number, ".json")
            open(result_file, "w") do f
                JSON.print(f, Scenarios_used)
            end
        end
    end

    if total_capacity_scenarios + number_of_demand_scenarios > 2
        return Scenarios_used, p_ω_test, p_ω_test_partial_2, Ω_test_partial_1, Ω_test_partial_2, partial_scenario, s_real_tilde, d_real_tilde, random_scenarios, p_ω_MVP, Ω_MVP
    else
        return random_scenarios, s_real_tilde, d_real_tilde
    end
end