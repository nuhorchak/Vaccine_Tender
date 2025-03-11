using JuMP, Gurobi
include("OBJ_builder.jl")


model, x, y, z = build_model()

# Relax z from integer to continuous
unset_integer(z)
println("Solving relaxed problem...")
optimize!(model)

# Store results from relaxed model
relaxed_solution_x = value(x)
relaxed_solution_y = value(y)
relaxed_solution_z = value(z)
println("Relaxed solution: x=$(relaxed_solution_x), y=$(relaxed_solution_y), z=$(relaxed_solution_z)")

# Modify the objective by removing the `3z` term
@objective(model, Min, 4x + 6y)  # Keeping only 4x + 2y

# Reintroduce the integer constraint on z
set_integer(z)

println("Solving modified problem...")
optimize!(model)

# Final solution
println("Final solution: x=$(value(x)), y=$(value(y)), z=$(value(z))")

