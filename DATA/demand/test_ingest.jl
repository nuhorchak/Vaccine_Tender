using JuMP
using Gurobi
using Random
using Base.Iterators: flatten
import XLSX
import JSON

gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol"=>1e-6, "MIPGap" => 1e-4)

# Design of Experiment
# demand_status = "D2" # "D1" => "D_low" or "D2" => "D_med" or "D3" => "D_high"
supply_status = "S2" # "S1" => "S_low" or "S2" => "S_med" or "S3" => "S_high"
# price_status = "P1" # "P1" => "P_no_discount"
overlap_decision = true
capacity_extension_decision = true

################################################### INDICES ####################################################
#=
Index Definitions:
A: Set of antigens
V: Set of vaccines
A_v: Subset of antigens in vaccine v
V_a: Subset of vaccines in antigen a
P: Set of producers
P_v: Subset of producers of vaccine v
T: Set of time periods
=#
#println("antigens")
A = ["Measles","Mumps","Rubella","Diphtheria","Tetanus","Pertussis","Hepatitis_B","Hib","Polio","HPV","Rotavirus","PCV"]
#println("vaccines")
V = ["M","MR","MMR","TT","HepB","Hib","IPV","OPV","DT","Td","DTwP","DTwP-Hib","Penta","Hexa","HPV","Rotavirus","PCV"]
#println("vaccine,antigen dict")
A_v = Dict("M" => ["Measles"],"MR" => ["Measles","Rubella"],"MMR" => ["Measles","Mumps","Rubella"], "TT" => ["Tetanus"], "HepB" => ["Hepatitis_B"], "Hib" => ["Hib"], "IPV" => ["Polio"], 
            "OPV" => ["Polio"], "DT" => ["Diphtheria","Tetanus"], "Td" => ["Diphtheria","Tetanus"], "DTwP" => ["Diphtheria","Tetanus","Pertussis"],
            "DTwP-Hib" => ["Diphtheria","Tetanus","Pertussis","Hib"], "Penta" => ["Diphtheria","Tetanus","Pertussis","Hepatitis_B","Hib"], 
            "Hexa" => ["Diphtheria","Tetanus","Pertussis","Hepatitis_B","Hib","Polio"],"HPV" => ["HPV"], "Rotavirus" => ["Rotavirus"], "PCV" => ["PCV"])

V_a = Dict(a => [v for v in keys(A_v) if a in A_v[v]] for a in A)
# println(V_a)

P = ["AJ_Vaccines","BB_NCIPD","Beijing_Institute","Bharat_Biotech","Bilthoven","Biological_E","Centro_de","GSK","Haffkine_Bio",
        "LG_Chem","Merck_Sharp","Panacea_Biotec","PT_Bio","Sanofi_Pasteur","Serum_Institute","Xiamen_Innovax","Pfizer"]

P_v = Dict("M" => ["Serum_Institute", "PT_Bio"], "MR" => ["Serum_Institute", "Biological_E"], "MMR" => ["Serum_Institute","GSK","Merck_Sharp"],
    "TT"=> ["Serum_Institute","PT_Bio","BB_NCIPD"], "HepB" => ["Serum_Institute","LG_Chem"], "Hib" => ["Serum_Institute","Sanofi_Pasteur","Centro_de"], 
    "IPV" => ["LG_Chem","AJ_Vaccines","Bilthoven","Sanofi_Pasteur"], 
    "OPV" => ["Serum_Institute","PT_Bio","GSK","Sanofi_Pasteur","Panacea_Biotec","Beijing_Institute","Bharat_Biotech","Haffkine_Bio"],
    "DT" => ["Serum_Institute","PT_Bio","BB_NCIPD"], "Td" => ["Serum_Institute","PT_Bio","BB_NCIPD"], "DTwP" => ["Serum_Institute","Biological_E"], "DTwP-Hib" => ["Serum_Institute"],
    "Penta" => ["Serum_Institute","PT_Bio","Biological_E","LG_Chem","Panacea_Biotec"], "Hexa" => ["Sanofi_Pasteur"], 
    "HPV" => ["GSK","Merck_Sharp","Xiamen_Innovax"], "Rotavirus" => ["Serum_Institute","GSK","Bharat_Biotech"], "PCV" => ["Serum_Institute","GSK","Pfizer"])

V_p = Dict(p => [v for v in keys(P_v) if p in P_v[v]] for p in P)

P_a = Dict(a => unique(flatten([P_v[v] for v in V_a[a]])) for a in A)
A_p = Dict(p => [a for a in keys(P_a) if p in P_a[a]] for p in P)

tmin = 1
tmax = 10
T = [t for t in tmin:tmax]
T_initial = [t for t in tmin-1:tmax]

Δ = [1,2,3,4,5]

function generate_omega_list(omega::Int)
    return collect(1:omega)
end
Ω = generate_omega_list(1)
# println(Ω)

#all scenarios are random numbers for demand and equi-probable 
p_ω = Dict(ω => 1/length(Ω) for ω in Ω)
# println(p_ω)

################################################### PARAMETERS ####################################################
#=
Parameter Definitions:
d: demand for antigen a at time t
s: production capacity of producer p at time t
k: max annual production batch size of vaccine v at time t
r: reservation price of vaccine v produced by p at time t
r_avg: average price of vaccine v in period t
l: annualized return on investment that producer p requires for vaccine v
gamma: maximum discount per dose achieved at highest allowed procurement quantity
g: set up cost if having a tender in period t (for GAVI)
f: production set-up cost of producer p for vaccine v in period t
h: annual holding cost for vaccine v as a proportion of price
pi: penalty for shortage of amount committed
beta: risk parameter for demand
=#

# Get the absolute path of the current file's directory
current_directory = @__DIR__

# Define the relative path to the DATA folder and the file name
data_folder = joinpath(current_directory, "..", "DATA")  # Adjust ".." based on the location of the DATA folder relative to your script
filename = "mean_value.xlsx"
# filename = "MVP20_random_normal_forecast_data.xlsx"

# Construct the relative path using joinpath
relative_path = joinpath(data_folder, filename)

# Print the resulting path
println("Relative Path: ", relative_path)

random_demand_file = XLSX.readxlsx(relative_path)

total_demand_row = length(A)+1
total_demand_col = length(T)+1

d_real = Dict()
sheet_names = XLSX.sheetnames(random_demand_file)
println(sheet_names)
for name in first(sheet_names, 1) #change the number based on scenario numbers
    data = random_demand_file[name]
    ω = findfirst((x -> x==name), sheet_names)
    for row in 2:total_demand_row
        antigen = data[row,1]
        for col in 2:total_demand_col
            year = data[1,col]
            d_real[antigen,year,ω] = data[row,col]
        end
    end
end
println(d_real)