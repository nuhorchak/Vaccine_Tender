using JuMP, Gurobi

function build_model()
    model = Model(Gurobi.Optimizer)

    # Define variables
    @variable(model, x >= 0, Int)  # Integer variable
    @variable(model, y >= 1)       # Continuous variable
    @variable(model, z >= 0, Int)  # Integer variable

    # Objective function (Minimization)
    @objective(model, Min, 4x + 6y + 7z)

    # Constraints
    @constraint(model, x + 2y + z >= 5)
    @constraint(model, 3x + y + 2z >= 8)

    return model, x, y, z
end

