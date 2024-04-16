import XLSX
A = ["Measles","Mumps","Rubella","Diphtheria","Tetanus","Pertussis","Hepatitis_B","Hib","Polio","HPV","Rotavirus","PCV"]
tmin = 1
tmax = 10
T = [t for t in tmin:tmax]
T_initial = [t for t in tmin-1:tmax]

Δ = [1,3,5]

Ω = [1,2,3,4,5]

p_ω = Dict()

for ω in Ω
    p_ω[ω] = 1/length(Ω)
end 
println(p_ω)

total_demand_row = length(A)+1
total_demand_col = length(T)+1

# Get the absolute path of the current file's directory
current_directory = @__DIR__

# Define the file name
filename = "random_normal_forecast_data.xlsx"

# Construct the relative path using joinpath
relative_path = joinpath(current_directory, filename)

# Print the resulting path
println("Relative Path: ", relative_path)

demand_file = XLSX.readxlsx(relative_path)

sheet_names = XLSX.sheetnames(demand_file)
println(sheet_names)

d_real = Dict()


for name in sheet_names[1:5]
    data = demand_file[name]
    ω = findfirst((x -> x==name), sheet_names)
    for row in 2:total_demand_row
        antigen = data[row,1]
        for col in 2:total_demand_col
            year = data[1,col]
            d_real[antigen,year,ω] = data[row,col]
            # if (antigen == "Polio" && year == 1)
            #     println(antigen, year, ω)
            #     println(d_real[antigen,year,ω])
            # end
        end
    end
end
# println(d_real)
