using JuMP
using Gurobi
using Random
import XLSX
import JSON

gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol"=>1e-6)

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

Ω = [1,2,3,4,5,6,7,8,9,10]

p_ω = Dict()
# for ω in Ω
#     if ω <= 3
#         p_ω[ω] = 0.3
#     else
#         p_ω[ω] = 0.05
#     end
# end

#all scenarios are random numbers for demand and equi-probable 
for ω in Ω
    p_ω[ω] = 1/length(Ω)
end 
println(p_ω)

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

# Define the file name
filename = "random_normal_forecast_data.xlsx"

# Construct the relative path using joinpath
relative_path = joinpath(current_directory, filename)

# Print the resulting path
println("Relative Path: ", relative_path)

random_demand_file = XLSX.readxlsx(relative_path)

total_demand_row = length(A)+1
total_demand_col = length(T)+1

d_real = Dict()
sheet_names = XLSX.sheetnames(random_demand_file)
println(sheet_names)
for name in sheet_names
    data = random_demand_file[name]
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

# Define the file name
filename = "Demand_Scenarios_updated.xlsx"

# Construct the relative path using joinpath
relative_path = joinpath(current_directory, filename)

# Print the resulting path
println("Relative Path: ", relative_path)

demand_file = XLSX.readxlsx(relative_path)

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
    g[t] = 1e8
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

# inflation rate
delta = []
delta = [0.03 for t in 1:tmax]

# Get the absolute path of the current file's directory
current_directory = @__DIR__

# Define the file name
filename = "Starting_point.xlsx"

# Construct the relative path using joinpath
relative_path = joinpath(current_directory, filename)

starting_points_file = XLSX.readxlsx(relative_path)

starting_points_F_raw = starting_points_file["F_start"]
total_row_F = 13
starting_points_vect_F = []
for row in 2:total_row_F
    antigen = starting_points_F_raw[row,1]
    starting_year = starting_points_F_raw[row,2]
    ending_year = starting_points_F_raw[row,3]
    push!(starting_points_vect_F, (antigen,starting_year,ending_year))
end
println(starting_points_vect_F)

starting_points_Q_raw = starting_points_file["Q_start"]
total_row_Q = 27
starting_points_vect_Q = []
for row in 2:total_row_Q
    vaccine = starting_points_Q_raw[row,1]
    producer = starting_points_Q_raw[row,2]
    starting_year = starting_points_Q_raw[row,3]
    ending_year = starting_points_Q_raw[row,4]
    amount = starting_points_Q_raw[row,5]
    push!(starting_points_vect_Q, (vaccine,producer,starting_year,ending_year,amount))
end
println(starting_points_vect_Q)

starting_points_I_raw = starting_points_file["I_start"]
total_row_I = 5
starting_points_vect_I = []
for row in 2:total_row_I
    vaccine = starting_points_I_raw[row,1]
    amount = starting_points_I_raw[row,2]
    push!(starting_points_vect_I, (vaccine,amount))
end
println(starting_points_vect_I)

starting_points_S_raw = starting_points_file["S_start"]
total_row_S = 13
starting_points_vect_S = []
for row in 2:total_row_S
    antigen = starting_points_S_raw[row,1]
    amount = starting_points_S_raw[row,2]
    push!(starting_points_vect_S, (antigen,amount))
end
println(starting_points_vect_S)

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

X_tilde_lower = Dict()
X_tilde_upper = Dict()
for v in V
    for p in P_v[v]
        for t in T
            for tau in T
                if (t,tau) in F_time_set
                    X_tilde_lower[v,p,(t,tau)] = 0
                    X_tilde_upper[v,p,(t,tau)] = sum(s_real[p,l] for l in t:tau)
                end
            end
        end
    end
end

# Γ is the cost of expanding capacity by 20% for producer p
Γ = Dict()
for p in P
    Γ[p] = 1e8
end

# κ is the allowable capacity increase in a period
κ = 0.1

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
@variable(model, X[v in V, p in P_v[v], t in T, ω in Ω] >= 0)
@variable(model, X_tilde[v in V, p in P_v[v], (t,tau) in F_time_set, ω in Ω] >= 0)
@variable(model, K[v in V, p in P_v[v], (t,tau) in F_time_set, ω in Ω] >= 0)
@variable(model, Y[p in P, t in T], Bin)
@variable(model, I[v in V, t in T_initial, ω in Ω] >= 0)
@variable(model, Vc[v in V, t in T, ω in Ω] >= 0)
@variable(model, S[a in A, t in T_initial, ω in Ω] >= 0)
@variable(model, W[p in P, (t,tau) in F_time_set], Bin)
@variable(model, L[p in P, t in T], Bin)

################################################### OBJECTIVE FUNCTION AND CONSTRAINTS ####################################################
if capacity_extension_decision
    @objective(model, Min, sum(g[t]*F[a,(t,tau)]/(1+delta[t])^tmax for (t,tau) in F_time_set, a in A if (a,t,tau) ∉ starting_points_vect_F)
    + sum(p_ω[ω]*r[v,p,t]*X[v,p,t,ω]/(1+delta[t])^tmax for v in V, p in P_v[v], t in T, ω in Ω)
        + sum(p_ω[ω]*pi*S[a,t,ω]/(1+delta[t])^tmax for a in A, t in T, ω in Ω)
            + sum(p_ω[ω]*h[v]*r_avg[v,t]*I[v,t,ω]/(1+delta[t])^tmax for v in V, t in T, ω in Ω)
                + sum(Γ[p]*L[p,t]/(1+delta[t])^tmax for p in P, t in T)
                                                            )
else
    @objective(model, Min, sum(g[t]*F[a,(t,tau)]/(1+delta[t])^tmax for (t,tau) in F_time_set, a in A if (a,t,tau) ∉ starting_points_vect_F)
    + sum(p_ω[ω]*r[v,p,t]*X[v,p,t,ω]/(1+delta[t])^tmax for v in V, p in P_v[v], t in T, ω in Ω)
        + sum(p_ω[ω]*pi*S[a,t,ω]/(1+delta[t])^tmax for a in A, t in T, ω in Ω)
            + sum(p_ω[ω]*h[v]*r_avg[v,t]*I[v,t,ω]/(1+delta[t])^tmax for v in V, t in T, ω in Ω)
                                                            )
end


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

if overlap_decision
    # Constraint (3)
    for a in A
        for t in T
            for tau in T
                if tau >= t
                    for t_prime in T
                        for tau_prime in T
                            if tau_prime >= t_prime
                                overlap_decision = (t == t_prime)
                                if overlap_decision == true
                                    if ((t,tau) in F_time_set) && ((t_prime,tau_prime) in F_time_set) && ((t,tau) != (t_prime,tau_prime))
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
    # Constraint (4) - updated
    for a in A
        for t in T
            @constraint(model, sum(F[a,(l,k)] for (l,k) in F_time_set if t >= l && t <= k) >= 1)
        end
    end
else
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

if capacity_extension_decision
    # Constraint (7)
    for p in P
        for t in T
            for tau in T
                if (t,tau) in F_time_set
                    @constraint(model, sum(Q[v,p,(t,tau)] for v in V_p[p]) <= W[p,(t,tau)]*sum((s_real[p,l] + sum(s_real[p,k]*κ*L[p,k] for k in 1:l)) for l in t:tau))
                end
            end
        end
    end
    # Constraint (9)
    for ω in Ω
        for p in P
            for t in T
                @constraint(model, sum(X[v,p,t,ω] for v in V_p[p]) <= Y[p,t]*(s_real[p,t]+sum(s_real[p,l]*κ*L[p,l] for l in 1:t)))
            end
        end
    end
else
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
    # Constraint (9)
    for ω in Ω
        for p in P
            for t in T
                @constraint(model, sum(X[v,p,t,ω] for v in V_p[p]) <= s_real[p,t]*Y[p,t])
            end
        end
    end
end

# Constraint (8) - McCormick_1
for ω in Ω
    for v in V
        for p in P_v[v]
            for t in T
                for tau in T
                    if (t,tau) in F_time_set
                        @constraint(model, X_tilde[v,p,(t,tau),ω] == sum(X[v,p,l,ω] for l in t:tau))
                    end
                end
            end
        end
    end
end

# Constraint (8) - McCormick_2
for ω in Ω
    for v in V
        for p in P_v[v]
            for t in T
                for tau in T
                    if (t,tau) in F_time_set
                        @constraint(model, Q[v,p,(t,tau)] >= K[v,p,(t,tau),ω])
                    end
                end
            end
        end
    end
end

# Constraint (8) - McCormick_3
for ω in Ω
    for v in V
        for p in P_v[v]
            for t in T
                for tau in T
                    if (t,tau) in F_time_set
                        @constraint(model, K[v,p,(t,tau),ω] >= X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)] + X_tilde[v,p,(t,tau),ω] - X_tilde_upper[v,p,(t,tau)])
                        @constraint(model, K[v,p,(t,tau),ω] <= X_tilde[v,p,(t,tau),ω])
                        @constraint(model, K[v,p,(t,tau),ω] <= X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)])
                    end
                end
            end
        end
    end
end

# Constraint (10)
for ω in Ω
    for v in V
        for t in T
            if t >= tmin
                @constraint(model, I[v,t-1,ω] + sum(X[v,p,t,ω] for p in P_v[v]) == Vc[v,t,ω] + I[v,t,ω])
            end
        end
    end
end

# Constraint (11)
for ω in Ω
    for a in A
        for t in T
            if t >= tmin
                @constraint(model, d_real[a,t,ω] - sum(Vc[v,t,ω] for v in V_a[a]) + S[a,t-1,ω] <= S[a,t,ω])
            end
        end
    end
end

# Constraint (12)
for ω in Ω
    for p in P
        for t in T
            @constraint(model, sum(r[v,p,t]*X[v,p,t,ω] for v in V_p[p]) >= Y[p,t]*sum((1+l[v,p])*f[v,p,t] for v in V_p[p]))
        end
    end
end

for i in 1:length(starting_points_vect_F)
    a = starting_points_vect_F[i][1]
    t = starting_points_vect_F[i][2]
    tau = starting_points_vect_F[i][3]
    @constraint(model, F[a, (t, tau)] == 1)
end

for i in 1:length(starting_points_vect_Q)
    v = starting_points_vect_Q[i][1]
    p = starting_points_vect_Q[i][2]
    t = starting_points_vect_Q[i][3]
    tau = starting_points_vect_Q[i][4]
    amount = starting_points_vect_Q[i][5]
    @constraint(model, Q[v, p, (t, tau)] == amount)
end

for ω in Ω
    for i in 1:length(starting_points_vect_I)
        v = starting_points_vect_I[i][1]
        amount = starting_points_vect_I[i][2]
        @constraint(model, I[v,0,ω] == amount)
    end
    defined_values = ["Penta", "OPV", "IPV", "PCV"]
    # defined_values = []
    for v in V
        if v ∉ defined_values
            @constraint(model, I[v,0,ω] == 0)
        end
    end
end

for ω in Ω
    for i in 1:length(starting_points_vect_S)
        a = starting_points_vect_S[i][1]
        amount = starting_points_vect_S[i][2]
        @constraint(model, S[a,0,ω] == amount)
    end
end

optimize!(model)

# Check feasibility status
if termination_status(model) == MOI.OPTIMAL
    println("The model is feasible.")
    println("Objective Value: $(JuMP.objective_value(model))")
    println("Run Time: $(JuMP.solve_time(model))")
    # Collect variable names and values
    variable_names = JuMP.all_variables(model)
    variable_values = Dict()
    for variable in variable_names
        variable_values[variable] = value(variable)
    end
    # Convert to JSON
    json_results = JSON.json(variable_values)

    open("Deterministic_results_with_initial_conditions.json", "w") do f
        write(f, json_results)
    end
else
    println("The model is infeasible.")
    # println(termination_status(model))
    compute_conflict!(model)
    iis_model, _ = copy_conflict(model)
    print(iis_model)
    json_errors = iis_model
    open("errors.json", "w") do f
        write(f, json_errors)
    end
end

# println("!!!!!!!!!!!!!!!!!!!!!!!!!  F !!!!!!!!!!!!!!!!!!!!!!!!!!")
# println(JuMP.value.(model[:F]))
# println("!!!!!!!!!!!!!!!!!!!!!!!!!  Y !!!!!!!!!!!!!!!!!!!!!!!!!!")
# println(JuMP.value.(model[:Y]))
# println("!!!!!!!!!!!!!!!!!!!!!!!!!  Q !!!!!!!!!!!!!!!!!!!!!!!!!!")
# println(JuMP.value.(model[:Q]))
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
# println("!!!!!!!!!!!!!!!!!!!!!!!!! L !!!!!!!!!!!!!!!!!!!!!!!!!!")
# println(JuMP.value.(model[:L]))
