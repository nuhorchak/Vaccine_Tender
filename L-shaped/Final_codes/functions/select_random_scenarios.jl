import Random

function select_random_scenarios(a::Int, b::Int, n::Int)
    numbers = collect(a:b)
    shuffled_numbers = shuffle(numbers)
    selected_numbers = shuffled_numbers[1:n]
    # Make pairs with all the capacity scenarios
    randomly_selected_scenarios = Vector{Int}()
    for i in selected_numbers
        for j in 1:total_capacity_scenarios
            push!(randomly_selected_scenarios, (i-1)*total_capacity_scenarios+j)
        end
    end
    return randomly_selected_scenarios
end