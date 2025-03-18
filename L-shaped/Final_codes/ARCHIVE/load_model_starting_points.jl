"""
    load_starting_points(file_path::String, initial_inventory_rate::Float64, unit::Int)

Reads starting points data from an Excel file and processes it into structured vectors.

# Arguments:
- `file_path::String`: Path to the Excel file containing the starting points data.
- `initial_inventory_rate::Float64`: Scaling factor for inventory amounts.
- `unit::Int`: Unit scaling factor for rounding values.

# Returns:
- `starting_points_vect_F::Vector`: Vector of tuples for `F_start` containing (antigen, starting_year, ending_year).
- `starting_points_vect_I::Vector`: Vector of tuples for `I_start` containing (vaccine, scaled amount).
- `starting_points_vect_S::Vector`: Vector of tuples for `S_start` containing (antigen, scaled amount).
"""
function load_model_starting_points(file_path::String, initial_inventory_rate::Int, unit::Int)
    # Read the Excel file
    filename = "Starting_point.xlsx"
    relative_path = joinpath(file_path, filename)
    starting_points_file = XLSX.readxlsx(relative_path)

    starting_points_F_raw = starting_points_file["F_start"]
    total_row_F = length(starting_points_F_raw[:, 1])
    starting_points_vect_F = []
    for row in 2:total_row_F
        antigen = starting_points_F_raw[row,1]
        starting_year = starting_points_F_raw[row,2]
        ending_year = starting_points_F_raw[row,3]
        push!(starting_points_vect_F, (antigen,starting_year,ending_year))
    end

    starting_points_I_raw = starting_points_file["I_start"]
    total_row_I = length(starting_points_I_raw[:, 1])
    starting_points_vect_I = []
    for row in 2:total_row_I
        vaccine = starting_points_I_raw[row,1]
        amount = round(starting_points_I_raw[row,2] * initial_inventory_rate / unit, digits=0)
        push!(starting_points_vect_I, (vaccine,amount))
    end

    starting_points_S_raw = starting_points_file["S_start"]
    total_row_S = length(starting_points_S_raw[:, 1])
    starting_points_vect_S = []
    for row in 2:total_row_S
        antigen = starting_points_S_raw[row,1]
        amount = round(starting_points_S_raw[row,2] / unit, digits=0)
        push!(starting_points_vect_S, (antigen,amount))
    end

    # Return the processed vectors
    return starting_points_vect_F, starting_points_vect_I, starting_points_vect_S
end
