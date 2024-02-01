using JuMP
using Gurobi
using Random
import XLSX
import JSON

gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol"=>1e-6)

# Design of Experiment
demand_status = "D2" # "D1" => "D_low" or "D2" => "D_med" or "D3" => "D_high"
supply_status = "S2" # "S1" => "S_low" or "S2" => "S_med" or "S3" => "S_high"
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
T_neg = [t for t in -3:tmax]

Δ = [1,2,3,4,5]
# Δ = [1,2,3,4,5,6,7,8,9,10]

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
for t in T_neg
    if t >= 1
        g[t] = 1e8
    else
        g[t] = 0.0
    end
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

F_time_set_neg = []
for t in T
    for tau in T
        if tau >= t
            if (tau-t+1) in Δ
                push!(F_time_set_neg,(t,tau))
            end
        end
    end
end
push!(F_time_set_neg,(-3, 1))
push!(F_time_set_neg,(-1, 3))

println(F_time_set)
println(F_time_set_neg)

X_tilde_lower = Dict()
X_tilde_upper = Dict()
for v in V
    for p in P_v[v]
        for t in T_neg
            for tau in T_neg
                if (t,tau) in F_time_set
                    X_tilde_lower[v,p,(t,tau)] = 0
                    X_tilde_upper[v,p,(t,tau)] = sum(s_real[p,l] for l in t:tau)
                elseif (t,tau) in F_time_set_neg
                    nonneg = 1
                    X_tilde_lower[v,p,(t,tau)] = 0
                    X_tilde_upper[v,p,(t,tau)] = sum(s_real[p,l] for l in nonneg:tau)
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

@variable(model, F[a in A, (t,tau) in F_time_set_neg], Bin)
@variable(model, Q[v in V, p in P_v[v], (t,tau) in F_time_set_neg] >= 0)
@variable(model, X[v in V, p in P_v[v], t in T] >= 0)
@variable(model, X_tilde[v in V, p in P_v[v], (t,tau) in F_time_set_neg] >= 0)
@variable(model, K[v in V, p in P_v[v], (t,tau) in F_time_set_neg] >= 0)
@variable(model, Y[p in P, t in T], Bin)
@variable(model, I[v in V, t in T_initial] >= 0)
@variable(model, Vc[v in V, t in T] >= 0)
@variable(model, S[a in A, t in T_initial] >=0)
@variable(model, W[p in P, (t,tau) in F_time_set_neg], Bin)
@variable(model, L[p in P, t in T], Bin)

################################################### OBJECTIVE FUNCTION AND CONSTRAINTS ####################################################

@objective(model, Min, sum(g[t]*F[a,(t,tau)] for (t,tau) in F_time_set_neg, a in A)
                            + sum(r[v,p,t]*X[v,p,t] for v in V, p in P_v[v], t in T)
                                + sum(pi*S[a,t] for a in A, t in T)
                                    + sum(h[v]*r_avg[v,t]*I[v,t] for v in V, t in T)
                                        + sum(Γ[p]*L[p,t] for p in P, t in T)
                                                                                    )

# Constraint (2)
for a in A
    for t in T_neg
        for tau in T_neg
            if (t,tau) in F_time_set
                @constraint(model, (tau-t+1)*F[a,(t,tau)] <= sum(Y[p,l] for l in t:tau, p in P_a[a]))
            elseif (t,tau) in F_time_set_neg
                nonneg = 1
                @constraint(model, (tau-nonneg+1)*F[a,(t,tau)] <= sum(Y[p,l] for l in nonneg:tau, p in P_a[a]))
            end
        end
    end
end

# Constraint (3)
for a in A
    for t in T_neg
        for tau in T_neg
            if tau >= t
                for t_prime in T_neg
                    for tau_prime in T_neg
                        if tau_prime >= t_prime
                            overlap_decision = (t == t_prime)
                            if overlap_decision == true
                                if ((t,tau) in F_time_set_neg) && ((t_prime,tau_prime) in F_time_set_neg) && ((t,tau) != (t_prime,tau_prime))
                                    @constraint(model, F[a,(t,tau)] + F[a,(t_prime,tau_prime)] <= 1)
                                end
                            end
                            if ((t,tau) in F_time_set_neg) && ((t_prime,tau_prime) in F_time_set_neg) && ((t,tau) != (t_prime,tau_prime)) && (t <= 0 && t_prime <= 0)
                                @constraint(model, F[a,(t,tau)] + F[a,(t_prime,tau_prime)] <= 1)
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
        lhs = 0.0
        for (l,k) in F_time_set_neg
            if t >= l && t <= k
                lhs += F[a,(l,k)]
            end
        end
        @constraint(model, lhs >= 1)
    end
end

# Constraint (5)
for p in P
    for t in T_neg
        for tau in T_neg
            if (t,tau) in F_time_set_neg
                @constraint(model, sum(F[a,(t,tau)] for a in A_p[p]) >= W[p,(t,tau)])
            end
        end
    end
end

# Constraint (6)
for p in P
    for t in T_neg
        for tau in T_neg
            if (t,tau) in F_time_set_neg
                @constraint(model, sum(F[a,(t,tau)] for a in A_p[p]) <= length(A_p) * W[p,(t,tau)])
            end
        end
    end
end

# Constraint (7)
for p in P
    for t in T_neg
        for tau in T_neg
            if (t,tau) in F_time_set
                @constraint(model, sum(Q[v,p,(t,tau)] for v in V_p[p]) <= W[p,(t,tau)]*sum((s_real[p,l] + sum(s_real[p,k]*κ*L[p,k] for k in 1:l)) for l in t:tau))
            elseif (t,tau) in F_time_set_neg
                nonneg = 1
                @constraint(model, sum(Q[v,p,(t,tau)] for v in V_p[p]) <= W[p,(t,tau)]*sum((s_real[p,l] + sum(s_real[p,k]*κ*L[p,k] for k in 1:l)) for l in nonneg:tau))
            end
        end
    end
end

# Constraint (8) - McCormick_1
for v in V
    for p in P_v[v]
        for t in T_neg
            for tau in T_neg
                if (t,tau) in F_time_set
                    @constraint(model, X_tilde[v,p,(t,tau)] == sum(X[v,p,l] for l in t:tau))
                elseif (t,tau) in F_time_set_neg
                    nonneg = 1
                    @constraint(model, X_tilde[v,p,(t,tau)] == sum(X[v,p,l] for l in nonneg:tau))
                end
            end
        end
    end
end

# Constraint (8) - McCormick_2
for v in V
    for p in P_v[v]
        for t in T_neg
            for tau in T_neg
                if (t,tau) in F_time_set_neg
                    @constraint(model, Q[v,p,(t,tau)] >= K[v,p,(t,tau)])
                end
            end
        end
    end
end

# Constraint (8) - McCormick_3
for v in V
    for p in P_v[v]
        for t in T_neg
            for tau in T_neg
                if (t,tau) in F_time_set_neg
                    @constraint(model, K[v,p,(t,tau)] >= X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)] + X_tilde[v,p,(t,tau)] - X_tilde_upper[v,p,(t,tau)])
                    @constraint(model, K[v,p,(t,tau)] <= X_tilde[v,p,(t,tau)])
                    @constraint(model, K[v,p,(t,tau)] <= X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)])
                end
            end
        end
    end
end

# Constraint (9)
for p in P
    for t in T
        @constraint(model, sum(X[v,p,t] for v in V_p[p]) <= Y[p,t]*(s_real[p,t]+sum(s_real[p,l]*κ*L[p,l] for l in 1:t)))
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

# Constraint (13) - Inventory 
#pre defined inventory start
#inventory at start
@constraint(model, I["Penta", 0] ==  12542)
@constraint(model, I["OPV", 0] ==  7598)
@constraint(model, I["IPV", 0] ==  14598)
@constraint(model, I["PCV", 0] ==  5145)

defined_values = ["Penta", "OPV", "IPV", "PCV"]
# defined_values = []
for v in V
    if v ∉ defined_values
        @constraint(model, I[v,0] == 0)
    end
end

###----------------------------------------------------------###
# # Tender starting point form historic contract data
# #ensure tender is assigned, by antigen, by time period

@constraint(model, F["Measles", (-1, 3)] == 1)
@constraint(model, F["Mumps", (-1, 3)] == 1)
@constraint(model, F["Rubella", (-1, 3)] == 1)
@constraint(model, F["Diphtheria", (-3, 1)] == 1)
@constraint(model, F["Tetanus", (-3, 1)] == 1)
@constraint(model, F["Pertussis", (-3, 1)] == 1)
@constraint(model, F["Hib", (-3, 1)] == 1)
@constraint(model, F["Hepatitis_B", (-3, 1)] == 1)
@constraint(model, F["Polio", (-3, 1)] == 1)
@constraint(model, F["HPV", (1, 5)] == 1)
@constraint(model, F["Rotavirus", (-3, 1)] == 1)
@constraint(model, F["PCV", (-1, 3)] == 1)


# # #ensure commitment (Q) is assigned
#measles
@constraint(model, Q["M", "PT_Bio", (-1, 3)] == 13299464)
# @constraint(model, Q["M", "Serum_Institute", (-1, 3)] == 0)

#MMR
@constraint(model, Q["MMR", "GSK", (-3, 1)] == 12505034)
@constraint(model, Q["MMR", "Serum_Institute", (-1, 3)] == 13547121)
@constraint(model, Q["MMR", "Merck_Sharp", (-1, 3)] == 6547121)

#MR
@constraint(model, Q["MR", "Biological_E", (-1, 3)] == 90279149)
# @constraint(model, Q["MR", "Serum_Institute", (-1, 3)] == 0)

# Tetanus Toxoid
# @constraint(model, Q["TT", "BB_NCIPD", (-3, 1)] == 0)
# @constraint(model, Q["TT", "Serum_Institute", (-3, 1)] == 0)
# @constraint(model, Q["TT", "PT_Bio", (-3, 1)] == 0)

# Tetanus-Diphtheria (Td)
@constraint(model, Q["Td", "Serum_Institute", (-3, 1)] == 180177056)
@constraint(model, Q["Td", "BB_NCIPD", (-3, 1)] == 13305452)
# @constraint(model, Q["Td", "PT_Bio", (-3, 1)] == 0)

# Diphtheria-Tetanus (DT)
# @constraint(model, Q["DT", "Serum_Institute", (-3, 1)] == 0)
# @constraint(model, Q["DT", "BB_NCIPD", (-3, 1)] == 0)
# @constraint(model, Q["DT", "PT_Bio", (-3, 1)] == 0)

# DTwP
# @constraint(model, Q["DTwP", "Serum_Institute", (-3, 1)] == 0)
# @constraint(model, Q["DTwP", "Biological_E", (-3, 1)] == 0)

# DTwP-Hib
# @constraint(model, Q["DTwP-Hib", "Serum_Institute", (-3, 1)] == 0)

# Penta
@constraint(model, Q["Penta", "Panacea_Biotec", (-3, 1)] == 8948035)
@constraint(model, Q["Penta", "Serum_Institute", (-3, 1)] == 140931564)
@constraint(model, Q["Penta", "LG_Chem", (-3, 1)] == 17896071)
@constraint(model, Q["Penta", "PT_Bio", (-3, 1)] == 31318125)
@constraint(model, Q["Penta", "Biological_E", (-3, 1)] == 53688215)

# Hexa
# @constraint(model, Q["Hexa", "Sanofi_Pasteur", (-3, 1)] == 0)

# Polio Vaccine - Inactivated (IPV)
@constraint(model, Q["IPV", "Sanofi_Pasteur", (-3, 1)] == 43365104)
@constraint(model, Q["IPV", "LG_Chem", (-3, 1)] == 40213942)
# @constraint(model, Q["IPV", "Bilthoven", (-3, 1)] == 0)
# @constraint(model, Q["IPV", "AJ_Vaccines", (-3, 1)] == 0)

# Polio Vaccine - Oral (OPV) 
@constraint(model, Q["OPV", "GSK", (-3, 1)] == 219201481)
@constraint(model, Q["OPV", "Sanofi_Pasteur", (-3, 1)] == 61220888)
@constraint(model, Q["OPV", "PT_Bio", (-3, 1)] == 84680592)
# @constraint(model, Q["OPV", "Bharat_Biotech", (-3, 1)] == 0)
# @constraint(model, Q["OPV", "Beijing_Institute", (-3, 1)] == 0)
# @constraint(model, Q["OPV", "Haffkine_Bio", (-3, 1)] == 0)
# @constraint(model, Q["OPV", "Panacea_Biotec", (-3, 1)] == 0)
# @constraint(model, Q["OPV", "Serum_Institute", (-3, 1)] == 0)

# Human Papillomavirus (HPV)
@constraint(model, Q["HPV", "Merck_Sharp", (1, 5)] == 3625021)
@constraint(model, Q["HPV", "GSK", (1, 5)] == 13464366)
@constraint(model, Q["HPV", "Xiamen_Innovax", (1, 5)] == 5390769)

# Hepatitis B
# @constraint(model, Q["HepB", "LG_Chem", (-3, 1)] == 0)
# @constraint(model, Q["HepB", "Serum_Institute", (-3, 1)] == 0)

# Haemophilus influenzae type b (Hib)
# @constraint(model, Q["Hib", "Sanofi_Pasteur", (-3, 1)] == 0)
# @constraint(model, Q["Hib", "Serum_Institute", (-3, 1)] == 0)
# @constraint(model, Q["Hib", "Centro_de", (-3, 1)] == 0)

# Rotavirus
@constraint(model, Q["Rotavirus", "GSK", (-3, 1)] == 56510400)
@constraint(model, Q["Rotavirus", "Serum_Institute", (-3, 1)] == 0) #56510400)
@constraint(model, Q["Rotavirus", "Bharat_Biotech", (-3, 1)] == 0) #29479003)

# Pneumococcal Conjugate vaccine
@constraint(model, Q["PCV", "GSK", (-1, 3)] ==  185663042)
@constraint(model, Q["PCV", "Pfizer", (-1, 3)] ==  20000000)
@constraint(model, Q["PCV", "Serum_Institute", (-1, 3)] ==  148533333)

# unvaccinated children (Sat) starting point based on general coverage
# good supply = 99% coverage, moderate = 90% coverage 
@constraint(model, S["Measles", 0] ==  37210000)
@constraint(model, S["Mumps", 0] ==  2610000)
@constraint(model, S["Rubella", 0] == 35730000)
@constraint(model, S["Diphtheria", 0] == 5706000)
@constraint(model, S["Tetanus", 0] ==  5777000)
@constraint(model, S["Pertussis", 0] ==  3207000)
@constraint(model, S["Hib", 10] ==  2595000)
@constraint(model, S["Hepatitis_B", 0] == 3123000)
@constraint(model, S["Polio", 0] == 5222000)
@constraint(model, S["HPV", 0] == 1900000)
@constraint(model, S["Rotavirus", 0] == 14250000)
@constraint(model, S["PCV", 0] == 1608000)

###---------------------------------------------------------------------------###

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

    open("Deterministic_results_no_length_restrictions.json", "w") do f
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

# COMMENT/UN-COMMENT WHATEVER RESULT YOU ARE LOOKING FOR #
# Save the results into a JSON document



