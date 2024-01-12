using JuMP
using Gurobi
using Random
import XLSX
import JSON

gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol"=>1e-6)

# Design of Experiment
demand_status = "D3" # "D1" => "D_low" or "D2" => "D_med" or "D3" => "D_high"
supply_status = "S3" # "S1" => "S_low" or "S2" => "S_med" or "S3" => "S_high"
price_status = "P1" # "P1" => "P_no_discount"

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

V_a = Dict()
for a in A
    vector_a = []
    for v in keys(A_v)
        if a in A_v[v]
            push!(vector_a, v)
        end
    end
    V_a[a] = vector_a
end

P = ["AJ_Vaccines","BB_NCIPD","Beijing_Institute","Bharat_Biotech","Bilthoven","Biological_E","Centro_de","GSK","Haffkine_Bio",
        "LG_Chem","Merck_Sharp","Panacea_Biotec","PT_Bio","Sanofi_Pasteur","Serum_Institute","Xiamen_Innovax","Pfizer"]

P_v = Dict("M" => ["Serum_Institute", "PT_Bio"], "MR" => ["Serum_Institute", "Biological_E"], "MMR" => ["Serum_Institute","GSK","Merck_Sharp"],
    "TT"=> ["Serum_Institute","PT_Bio","BB_NCIPD"], "HepB" => ["Serum_Institute","LG_Chem"], "Hib" => ["Serum_Institute","Sanofi_Pasteur","Centro_de"], 
    "IPV" => ["LG_Chem","AJ_Vaccines","Bilthoven","Sanofi_Pasteur"], 
    "OPV" => ["Serum_Institute","PT_Bio","GSK","Sanofi_Pasteur","Panacea_Biotec","Beijing_Institute","Bharat_Biotech","Haffkine_Bio"],
    "DT" => ["Serum_Institute","PT_Bio","BB_NCIPD"], "Td" => ["Serum_Institute","PT_Bio","BB_NCIPD"], "DTwP" => ["Serum_Institute","Biological_E"], "DTwP-Hib" => ["Serum_Institute"],
    "Penta" => ["Serum_Institute","PT_Bio","Biological_E","LG_Chem","Panacea_Biotec"], "Hexa" => ["Sanofi_Pasteur"], 
    "HPV" => ["GSK","Merck_Sharp","Xiamen_Innovax"], "Rotavirus" => ["Serum_Institute","GSK","Bharat_Biotech"], "PCV" => ["Serum_Institute","GSK","Pfizer"])

V_p = Dict()
for p in P
    vector_p = []
    for v in keys(P_v)
        if p in P_v[v]
            push!(vector_p, v)
        end
    end
    V_p[p] = vector_p
end

P_a = Dict()
for a in A
    vector_a = []
    vaccines = V_a[a]
    for v in vaccines
        producers = P_v[v]
        for p in producers
            if p ∉ vector_a
                push!(vector_a, p)
            end
        end
    end
    P_a[a] = vector_a
end

A_p = Dict()
for p in P
    vector_p = []
    for a in keys(P_a)
        if p in P_a[a]
            push!(vector_p, a)
        end
    end
    A_p[p] = vector_p
end

tmin = 1
tmax = 10
T = [t for t in tmin:tmax]
T_initial = [t for t in tmin-1:tmax]

Δ = [1,3,5]

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

# source_1 = string("C:/Users/fthcn/Desktop/Vaccine_Tender_Scheduling_Problem/Demand_Scenarios_updated.xlsx")
# demand_file = XLSX.readxlsx(source_1)

# Get the absolute path of the current file's directory
current_directory = @__DIR__

# Define the file name
filename = "Demand_Scenarios_updated.xlsx"

# Construct the relative path using joinpath
relative_path = joinpath(current_directory, filename)

# Print the resulting path
println("Relative Path: ", relative_path)

demand_file = XLSX.readxlsx(relative_path)

d_real_raw = demand_file["Medium_Demand"]

total_demand_row = length(A)+1
total_demand_col = length(T)+1

d_real = Dict()
for row in 2:total_demand_row
    antigen = d_real_raw[row,1]
    for col in 2:total_demand_col
        year = d_real_raw[1,col]
        if demand_status == "D1"
            d_real[antigen,year] = 0.8*d_real_raw[row,col]
        elseif demand_status == "D2"
            d_real[antigen,year] = d_real_raw[row,col]
        elseif demand_status == "D3"
            d_real[antigen,year] = 1.2*d_real_raw[row,col]
        end
    end
end

# source_2 = string("C:/Users/fthcn/Desktop/Vaccine_Tender_Scheduling_Problem/production_capacity_updated.xlsx")
# capacity_file = XLSX.readxlsx(source_2)

# Define the file name
filename2 = "production_capacity_updated.xlsx"

# Construct the relative path using joinpath
relative_path2 = joinpath(current_directory, filename2)

capacity_file = XLSX.readxlsx(relative_path2)

s_real_raw = capacity_file["Medium_Capacity"]

total_supply_row = length(P)+1
total_supply_col = length(T)+1
s_real = Dict()
for row in 2:total_supply_row
    producer = s_real_raw[row,1]
    for col in 2:total_supply_col
        year = s_real_raw[1,col]
        if supply_status == "S1"
            s_real[producer,year] = 0.8*s_real_raw[row,col]
        elseif supply_status == "S2"
            s_real[producer,year] = s_real_raw[row,col]
        elseif supply_status == "S3"
            s_real[producer,year] = 1.2*s_real_raw[row,col]
        end
    end
end

r = Dict()
for v in V
    vaccine_price_raw = demand_file[string(v," Pricing")]
    for row in 2:length(P_v[v])+1
        producer = vaccine_price_raw[row,1]
        for col in 2:length(T)+1
            year = vaccine_price_raw[1,col]
            r[v,producer,year] = vaccine_price_raw[row,col]
        end
    end
end

r_avg = Dict()
for v in V
    for t in T
        total = 0.0
        for p in P_v[v]
            total += r[v,p,t]
        end
        average = total / length(P_v[v])
        r_avg[v,t] = average
    end
end

r_producer_avg = Dict()
for p in P
    total = 0.0
    for v in V_p[p]
        for t in T
            total += r[v,p,t]
        end
    end
    average = total / (length(V_p[p])*length(T))
    r_producer_avg[p] = average
end

# Unvaccinated children penalty
pi = 100

# Tender cost
g = Dict()
for t in T
    g[t] = 1e6
end

# Inventory holding cost
h = Dict()
for v in V
    h[v] = 0.01
end

# ROI
l = Dict()
for v in V
    for p in P
        l[v,p] = 0.1
    end
end

f = Dict()
for p in P
    for v in V_p[p]
        for t in T
            f[v,p,t] = s_real[p,t]/length(V_p[p])*r_producer_avg[p]/2
        end
    end
end

beta = 0.1
γ = 0.1

F_time_set = []
for t in T
    for tau in T
        if tau >= t
            if (tau-t+1) in Δ
                push!(F_time_set,(t,tau))
            end
        end
    end
end

X_tilda_lower = Dict()
X_tilda_upper = Dict()
for v in V
    for p in P_v[v]
        for t in T
            for tau in T
                if (t,tau) in F_time_set
                    X_tilda_lower[v,p,(t,tau)] = 0
                    X_tilda_upper[v,p,(t,tau)] = sum(s_real[p,l] for l in t:tau)
                end
            end
        end
    end
end

################################################### DECISION VARIABLES ####################################################
#=
Variable Definitions:
F: a binary variable takes the value 1 if a tender covers demand at time t to tau for antigen a
Q: procurement commitment of producer p for vaccine v at time t
X: number of doses of vaccines v delivered by p at time t
Y: a binary variable takes the value 1 if a tender is granted to producer p for vaccine v at time t
I: stock level for vaccine v at time t
Vc: number of children vaccinated with vaccine v at time t
S: number of children that were not vaccinated with antigen a due to vaccine shortage at time t
=#

model=Model(Gurobi.Optimizer)

@variable(model, F[a in A, (t,tau) in F_time_set], Bin)
@variable(model, Q[v in V, p in P_v[v], (t,tau) in F_time_set] >= 0)
@variable(model, X[v in V, p in P_v[v], t in T] >= 0)
@variable(model, X_tilda[v in V, p in P_v[v], (t,tau) in F_time_set] >= 0)
@variable(model, K[v in V, p in P_v[v], (t,tau) in F_time_set] >= 0)
@variable(model, Y[p in P, t in T], Bin)
@variable(model, I[v in V, t in T_initial] >= 0)
@variable(model, Vc[v in V, t in T] >= 0)
@variable(model, S[a in A, t in T_initial] >=0)
@variable(model, W[p in P, (t,tau) in F_time_set], Bin)

################################################### OBJECTIVE FUNCTION AND CONSTRAINTS ####################################################

@objective(model, Min, sum(g[t]*F[a,(t,tau)] for (t,tau) in F_time_set, a in A)
                            + sum(r[v,p,t]*X[v,p,t] for v in V, p in P_v[v], t in T)
                                + sum(pi*S[a,t] for a in A, t in T)
                                    + sum(h[v]*r_avg[v,t]*I[v,t] for v in V, t in T)
                                                                                    )

# Constraint (2)
for a in A
    for t in T
        for tau in T
            if (t,tau) in F_time_set
                @constraint(model, (tau-t+1)*F[a,(t,tau)] <= sum(Y[p,l] for l in t:tau, p in P_a[a]))
            end
        end
    end
end

# Constraint (3)
for a in A
    for t in T
        for tau in T
            if tau >= t
                for t_prime in T
                    for tau_prime in T
                        if tau_prime >= t_prime
                            overlap_decision = ((t_prime < t) && (tau_prime < t)) || ((t_prime > tau) && (tau_prime > tau)) || ((t == t_prime) && (tau == tau_prime))
                            if overlap_decision == false
                                if ((t,tau) in F_time_set) && ((t_prime,tau_prime) in F_time_set)
                                    @constraint(model, F[a,(t,tau)] + F[a,(t_prime,tau_prime)] <= 1)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

# Constraint (4)
for a in A
    @constraint(model, sum((k-l+1)*F[a,(l,k)] for (l,k) in F_time_set) >= tmax)
end

# Constraint (5)
for p in P
    for t in T
        for tau in T
            if (t,tau) in F_time_set
                @constraint(model, sum(F[a,(t,tau)] for a in A_p[p]) >= W[p,(t,tau)])
            end
        end
    end
end

# Constraint (6)
for p in P
    for t in T
        for tau in T
            if (t,tau) in F_time_set
                @constraint(model, sum(F[a,(t,tau)] for a in A_p[p]) <= length(A_p) * W[p,(t,tau)])
            end
        end
    end
end

# Constraint (7)
for p in P
    for t in T
        for tau in T
            if (t,tau) in F_time_set
                @constraint(model, sum(Q[v,p,(t,tau)] for v in V_p[p]) <= W[p,(t,tau)]*sum(s_real[p,l] for l in t:tau))
            end
        end
    end
end

# Constraint (8) - McCormick_1
for v in V
    for p in P_v[v]
        for t in T
            for tau in T
                if (t,tau) in F_time_set
                    @constraint(model, X_tilda[v,p,(t,tau)] == sum(X[v,p,l] for l in t:tau))
                end
            end
        end
    end
end

# Constraint (8) - McCormick_2
for v in V
    for p in P_v[v]
        for t in T
            for tau in T
                if (t,tau) in F_time_set
                    @constraint(model, Q[v,p,(t,tau)] >= K[v,p,(t,tau)])
                end
            end
        end
    end
end

# Constraint (8) - McCormick_3
for v in V
    for p in P_v[v]
        for t in T
            for tau in T
                if (t,tau) in F_time_set
                    @constraint(model, K[v,p,(t,tau)] >= X_tilda_upper[v,p,(t,tau)]*W[p,(t,tau)] + X_tilda[v,p,(t,tau)] - X_tilda_upper[v,p,(t,tau)])
                    @constraint(model, K[v,p,(t,tau)] <= X_tilda[v,p,(t,tau)])
                    @constraint(model, K[v,p,(t,tau)] <= X_tilda_upper[v,p,(t,tau)]*W[p,(t,tau)])
                end
            end
        end
    end
end

# Constraint (9)
for p in P
    for t in T
        @constraint(model, sum(X[v,p,t] for v in V_p[p]) <= s_real[p,t]*Y[p,t])
    end
end

# Constraint (10)
for v in V
    for t in T
        if t >= tmin
            @constraint(model, I[v,t-1] + sum(X[v,p,t] for p in P_v[v]) == Vc[v,t] + I[v,t])
        end
    end
end

# Constraint (11)
for a in A
    for t in T
        if t >= tmin
            @constraint(model, d_real[a,t] - sum(Vc[v,t] for v in V_a[a]) + S[a,t-1] <= S[a,t])
        end
    end
end

# Constraint (12)
for p in P
    for t in T
        @constraint(model, sum(r[v,p,t]*X[v,p,t] for v in V_p[p]) >= Y[p,t]*sum((1+l[v,p])*f[v,p,t] for v in V_p[p]))
    end
end

# Constraint (13)
for v in V
    @constraint(model, I[v,0] == 0)
end
###----------------------------------------------------------###
# Tender starting point form historic contract data
#ensure tender is assigned, by antigen, by time period
@constraint(model, F["Measles", (1,3)] == 1)
# print("F1")
@constraint(model, F["Mumps", (1,3)] == 1)
# print("F2")
@constraint(model, F["Rubella", (1,3)] == 1)
print("F3")
@constraint(model, F["Diphtheria", (1,1)] == 1)
@constraint(model, F["Diphtheria", (2,2)] == 1)
print("F4")
@constraint(model, F["Tetanus", (1,1)] == 1)
@constraint(model, F["Tetanus", (2,2)] == 1)
println("F5")
@constraint(model, F["Polio", (1,1)] == 1)
@constraint(model, F["Polio", (2,2)] == 1)
println("F6")
@constraint(model, F["HPV", (1,5)] == 1)
#print("F7")
#@constraint(model, F["Polio", (1,1)] == 1)
#@constraint(model, F["Polio", (2,2)] == 1)
println("F8")
@constraint(model, F["Pertussis", (1,1)] == 1)
@constraint(model, F["Pertussis", (2,2)] == 1)
println("F9")
@constraint(model, F["Hib", (1,1)] == 1)
@constraint(model, F["Hib", (2,2)] == 1)
println("F10")
# #ensure commitment is assigned
# #measles
@constraint(model, Q["M", "PT_Bio", (1, 1)]== 13299464.01)
# #MMR
@constraint(model, Q["MMR", "GSK", (1, 1)]== 12505034.87)
@constraint(model, Q["MMR", "GSK", (2, 2)]== 26626398.68)
@constraint(model, Q["MMR", "GSK", (3, 3)]== 25785425)
@constraint(model, Q["MMR", "Serum_Institute", (1, 1)]== 13547121.11)
# #MR - edited to not exceed production capacity.
@constraint(model, Q["MR", "Biological_E", (1, 1)]== 90279149)
# #HPV
@constraint(model, Q["HPV", "Merck_Sharp", (1, 1)]== 3625021.856)
# @constraint(model, Q["HPV", "Merck_Sharp", (2, 2)]== 3585241.201)
# @constraint(model, Q["HPV", "Merck_Sharp", (3, 3)]== 5242359.172)
# @constraint(model, Q["HPV", "GSK", (1, 1)]== 13464366.89)
# @constraint(model, Q["HPV", "GSK", (2, 2)]== 13316610.18)
# @constraint(model, Q["HPV", "GSK", (3, 3)]== 19471619.78)
# @constraint(model, Q["HPV", "GSK", (4, 4)]== 51656909.24)
# @constraint(model, Q["HPV", "GSK", (5, 5)]== 65711883.69)
# @constraint(model, Q["HPV", "Xiamen_Innovax", (4, 4)]== 13907629.41)
# @constraint(model, Q["HPV", "Xiamen_Innovax", (5, 5)]== 17691660.99)		
# #IPV			
@constraint(model, Q["IPV", "Sanofi_Pasteur", (1, 1)]== 43565104.36)
@constraint(model, Q["IPV", "LG_Chem", (1, 1)]== 40213942.49)
@constraint(model, Q["IPV", "LG_Chem", (2, 2)]== 111910967.2)
# #OPV
# @constraint(model, Q["OPV", "GSK", (1, 1)]== 219201481)
# @constraint(model, Q["OPV", "Sanofi_Pasteur", (1, 1)]== 131520888.6)
# @constraint(model, Q["OPV", "PT_Bio", (1, 1)]== 87680592.41)
# #Rota
# @constraint(model, Q["Rotavirus", "GSK", (1, 1)]== 142479003)
# #Td 
# @constraint(model, Q["Td", "Serum_Institute", (1, 1)]== 180177056.4) 
# @constraint(model, Q["Td", "BB_NCIPD", (1, 1)]== 63305452.23)
# #Penta
# @constraint(model, Q["Penta", "Panacea_Biotec", (1, 1)]== 8948035.869)
# @constraint(model, Q["Penta", "Panacea_Biotec", (1, 1)]== 9776403.551)
# @constraint(model, Q["Penta", "Serum_Institute", (1, 1)]== 140931564.9) 
# @constraint(model, Q["Penta", "Serum_Institute", (2, 2)]== 153978355.9) 
# @constraint(model, Q["Penta", "LG_Chem", (1, 1)]== 17896071.74)
# @constraint(model, Q["Penta", "LG_Chem", (2, 2)]== 19552807.1)
# @constraint(model, Q["Penta", "PT_Bio", (1, 1)]== 31318125.54)
# @constraint(model, Q["Penta", "PT_Bio", (1, 1)]== 34217412.43)
# @constraint(model, Q["Penta", "Biological_E", (1, 1)]== 53688215.21)
# @constraint(model, Q["Penta", "Biological_E", (1, 1)]== 58658421.31)
###---------------------------------------------------------------------------###

optimize!(model)

if primal_status(model) == MOI.NO_SOLUTION
    compute_conflict!(model)
    iis_model, _ = copy_conflict(model)
    print(iis_model)
end

println("!!!!!!!!!!!!!!!!!!!!!!!!!  F !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:F]))
# println("!!!!!!!!!!!!!!!!!!!!!!!!!  Y !!!!!!!!!!!!!!!!!!!!!!!!!!")
# println(JuMP.value.(model[:Y]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  Q !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:Q]))
# println("!!!!!!!!!!!!!!!!!!!!!!!!!  X !!!!!!!!!!!!!!!!!!!!!!!!!!")
# println(JuMP.value.(model[:X]))
# println("!!!!!!!!!!!!!!!!!!!!!!!!!  I !!!!!!!!!!!!!!!!!!!!!!!!!!")
# println(JuMP.value.(model[:I]))
# println("!!!!!!!!!!!!!!!!!!!!!!!!!  Vc !!!!!!!!!!!!!!!!!!!!!!!!!!")
# println(JuMP.value.(model[:Vc]))
# println("!!!!!!!!!!!!!!!!!!!!!!!!!  S !!!!!!!!!!!!!!!!!!!!!!!!!!")
# println(JuMP.value.(model[:S]))
# println("!!!!!!!!!!!!!!!!!!!!!!!!! W !!!!!!!!!!!!!!!!!!!!!!!!!!")
# println(JuMP.value.(model[:W]))
# println("!!!!!!!!!!!!!!!!!!!!!!!!! K !!!!!!!!!!!!!!!!!!!!!!!!!!")
# println(JuMP.value.(model[:K]))

println("Objective Value: $(JuMP.objective_value(model))")
println("Run Time: $(JuMP.solve_time(model))")
