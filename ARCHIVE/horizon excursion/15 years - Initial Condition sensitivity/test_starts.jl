import XLSX
import JSON
using DataFrames
using CSV

# Get the absolute path of the current file's directory
# current_directory = @__DIR__

# # Define the file name
# filename = "starts/Starting_point.xlsx"

# # Construct the relative path using joinpath
# relative_path = joinpath(current_directory, filename)

# starting_points_file = XLSX.readxlsx(relative_path)

# starting_points_Q_raw = starting_points_file["Q_start"]
# total_row_Q = length(starting_points_Q_raw[:, 1])
# println(total_row_Q)
# starting_points_vect_Q = []
# for row in 2:total_row_Q
#     vaccine = starting_points_Q_raw[row,1]
#     producer = starting_points_Q_raw[row,2]
#     starting_year = starting_points_Q_raw[row,3]
#     ending_year = starting_points_Q_raw[row,4]
#     amount = starting_points_Q_raw[row,5]
#     push!(starting_points_vect_Q, (vaccine,producer,starting_year,ending_year,amount))
# end
# println(starting_points_vect_Q) 

tmin = 1
tmax = 15
T = [t for t in tmin:tmax]
delta = []
delta = [0.03 for t in 1:tmax]
println(delta)