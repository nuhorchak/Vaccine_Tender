import JSON
using JuMP
using Gurobi

# Get the absolute path of the current file's directory
current_directory = @__DIR__

# Specify the JSON file name
# file_name = "starting_point_JSON.json"

# Specify the path to your JSON file
json_file_path = joinpath(pwd(), "starting_point_JSON.json")
# println(json_file_path)


# Read the JSON file
json_content = read(json_file_path, String)

# Parse JSON with the reviver function
json_content = JSON.parse(json_content)

print(json_content)

gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol"=>1e-6)

# Create a model
model = Model(optimizer_with_attributes(Gurobi.Optimizer,))

# Iterate over the outer dictionary
for (variable, inner_dict) in json_content
    # Iterate over the inner dictionary and add constraints to the model
    for (constraint_name, constraint_value) in inner_dict
        # Extract variable name and indices from constraint_name using a more robust approach
        match_result = match(r"^([\w\d_]+)\[([^\]]+)\]$", constraint_name)
        
        if match_result === nothing
            error("Invalid constraint name format: $constraint_name")
        end
        
        variable_name, indices = match_result.captures
        indices = parse.(Int, split(indices, ","))
        
        # Create variable in the model (if not already created)
        @variable(model, variable_name[1], indices[1]:indices[2])
        
        # Add constraint to the model
        @constraint(model, variable_name[1][indices...] == constraint_value)
    end
end

# Now you have a model with the specified constraints
