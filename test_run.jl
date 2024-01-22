import JSON
using JuMP
using Gurobi

gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol"=>1e-6)

# Create a model
model = Model(optimizer_with_attributes(Gurobi.Optimizer))


##add code here for constraints building
# Step 1: Read the JSON document
F_start = JSON.parsefile("starting_point_F.json")

input_str = "F[Measles, (1,3)]: 1"

# Find the position of "[" and ","
start_index = findfirst(x -> x in "[,", input_str)

# Extract the substring between "[" and ","
substring = input_str[start_index[1]+1: start_index[2]-1]

# Add quotations to the substring
quoted_substring = "\"$substring\""

# Replace the original substring with the quoted one in the input string
modified_str = replace(input_str, substring => quoted_substring)

println(modified_str)
