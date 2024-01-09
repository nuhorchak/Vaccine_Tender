using JuMP
using Gurobi
using Random
import XLSX
import JSON

gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-6, "OutputFlag" => 0)

# Design of Experiment
# demand_status = "D3" # "D1" => "D_low" or "D2" => "D_med" or "D3" => "D_high"
supply_status = "S1" # "S1" => "S_low" or "S2" => "S_med" or "S3" => "S_high"
# price_status = "P1" # "P1" => "P_no_discount"

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
A = ["Measles", "Mumps", "Rubella", "Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "IPV", "HPV", "Rotavirus", "PCV"]
V = ["M", "MR", "MMR", "TT", "HepB", "Hib", "IPV", "OPV", "DT", "Td", "DTwP", "DTwP-Hib", "Penta", "Hexa", "HPV", "Rotavirus", "PCV"]

A_v = Dict("M" => ["Measles"], "MR" => ["Measles", "Rubella"], "MMR" => ["Measles", "Mumps", "Rubella"], "TT" => ["Tetanus"], "HepB" => ["Hepatitis_B"], "Hib" => ["Hib"], "IPV" => ["IPV"],
    "OPV" => ["IPV"], "DT" => ["Diphtheria", "Tetanus"], "Td" => ["Diphtheria", "Tetanus"], "DTwP" => ["Diphtheria", "Tetanus", "Pertussis"],
    "DTwP-Hib" => ["Diphtheria", "Tetanus", "Pertussis", "Hib"], "Penta" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib"],
    "Hexa" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "IPV"], "HPV" => ["HPV"], "Rotavirus" => ["Rotavirus"], "PCV" => ["PCV"])

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

P = ["AJ_Vaccines", "BB_NCIPD", "Beijing_Institute", "Bharat_Biotech", "Bilthoven", "Biological_E", "Centro_de", "GSK", "Haffkine_Bio",
    "LG_Chem", "Merck_Sharp", "Panacea_Biotec", "PT_Bio", "Sanofi_Pasteur", "Serum_Institute", "Xiamen_Innovax", "Pfizer"]

P_v = Dict("M" => ["Serum_Institute", "PT_Bio"], "MR" => ["Serum_Institute", "Biological_E"], "MMR" => ["Serum_Institute", "GSK", "Merck_Sharp"],
    "TT" => ["Serum_Institute", "PT_Bio", "BB_NCIPD"], "HepB" => ["Serum_Institute", "LG_Chem"], "Hib" => ["Serum_Institute", "Sanofi_Pasteur", "Centro_de"],
    "IPV" => ["LG_Chem", "AJ_Vaccines", "Bilthoven", "Sanofi_Pasteur"],
    "OPV" => ["Serum_Institute", "PT_Bio", "GSK", "Sanofi_Pasteur", "Panacea_Biotec", "Beijing_Institute", "Bharat_Biotech", "Haffkine_Bio"],
    "DT" => ["Serum_Institute", "PT_Bio", "BB_NCIPD"], "Td" => ["Serum_Institute", "PT_Bio", "BB_NCIPD"], "DTwP" => ["Serum_Institute", "Biological_E"], "DTwP-Hib" => ["Serum_Institute"],
    "Penta" => ["Serum_Institute", "PT_Bio", "Biological_E", "LG_Chem", "Panacea_Biotec"], "Hexa" => ["Sanofi_Pasteur"],
    "HPV" => ["GSK", "Merck_Sharp", "Xiamen_Innovax"], "Rotavirus" => ["Serum_Institute", "GSK", "Bharat_Biotech"], "PCV" => ["Serum_Institute", "GSK", "Pfizer"])

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

Δ = [1, 3, 5]

Ω = [1, 2, 3, 4, 5]

# The following lines gives the probability of the scenarios (0.3 for the first three scenarios, and 0.05 for the remaining two scenarios)

p_ω = Dict()
for ω in Ω
    if ω <= 3
        p_ω[ω] = 0.3
    else
        p_ω[ω] = 0.05
    end
end
println(p_ω)

# p_ω = Dict()
# for ω in Ω
#     if ω == 1
#         p_ω[ω] = 0.4
#     elseif ω == 2
#         p_ω[ω] = 0.2
#     elseif ω == 3
#         p_ω[ω] = 0.2
#     elseif ω == 4
#         p_ω[ω] = 0.10
#     elseif ω == 5
#         p_ω[ω] = 0.10
#     end
# end
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
d_pandemic_raw = demand_file["Pandemic_Effect"]
d_vaccine_replacement_raw = demand_file["Vaccine_Replacement_Effect"]

total_demand_row = length(A) + 1
total_demand_col = length(T) + 1

# source_2 = string("C:/Users/fthcn/Desktop/Vaccine_Tender_Scheduling_Problem/production_capacity_updated.xlsx")
# capacity_file = XLSX.readxlsx(source_2)

# Define the file name
filename2 = "production_capacity_updated.xlsx"

# Construct the relative path using joinpath
relative_path2 = joinpath(current_directory, filename2)

capacity_file = XLSX.readxlsx(relative_path2)

s_real_raw = capacity_file["Medium_Capacity"]

total_supply_row = length(P) + 1
total_supply_col = length(T) + 1

r = Dict()
for v in V
    vaccine_price_raw = demand_file[string(v, " Pricing")]
    for row in 2:length(P_v[v])+1
        producer = vaccine_price_raw[row, 1]
        for col in 2:length(T)+1
            year = vaccine_price_raw[1, col]
            r[v, producer, year] = vaccine_price_raw[row, col]
        end
    end
end

r_avg = Dict()
for v in V
    for t in T
        total = 0.0
        for p in P_v[v]
            total += r[v, p, t]
        end
        average = total / length(P_v[v])
        r_avg[v, t] = average
    end
end

r_producer_avg = Dict()
for p in P
    total = 0.0
    for v in V_p[p]
        for t in T
            total += r[v, p, t]
        end
    end
    average = total / (length(V_p[p]) * length(T))
    r_producer_avg[p] = average
end

beta = 0.1
γ = 0.1

F_time_set = []
for t in T
    for tau in T
        if tau >= t
            if (tau - t + 1) in Δ
                push!(F_time_set, (t, tau))
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

# first_stage function solves the deterministic model with the expected demand (weighted average of the 5 scenarios)
function first_stage(pi, g, h, l, d_real, s_real)

    f = Dict()
    for p in P
        for v in V_p[p]
            for t in T
                f[v, p, t] = s_real[p, t] / length(V_p[p]) * r_producer_avg[p] / 2
            end
        end
    end

    X_tilda_lower = Dict()
    X_tilda_upper = Dict()
    
    for v in V
        for p in P_v[v]
            for t in T
                for tau in T
                    if (t, tau) in F_time_set
                        X_tilda_lower[v, p, (t, tau)] = 0
                        X_tilda_upper[v, p, (t, tau)] = sum(s_real[p, l] for l in t:tau)
                    end
                end
            end
        end
    end

    model = Model(Gurobi.Optimizer)

    @variable(model, F[a in A, (t, tau) in F_time_set], Bin)
    @variable(model, Q[v in V, p in P_v[v], (t, tau) in F_time_set] >= 0)
    @variable(model, X[v in V, p in P_v[v], t in T] >= 0)
    @variable(model, X_tilda[v in V, p in P_v[v], (t, tau) in F_time_set] >= 0)
    @variable(model, K[v in V, p in P_v[v], (t, tau) in F_time_set] >= 0)
    @variable(model, Y[p in P, t in T], Bin)
    @variable(model, I[v in V, t in T_initial] >= 0)
    @variable(model, Vc[v in V, t in T] >= 0)
    @variable(model, S[a in A, t in T_initial] >= 0)
    @variable(model, W[p in P, (t, tau) in F_time_set], Bin)

    ################################################### OBJECTIVE FUNCTION AND CONSTRAINTS ####################################################

    @objective(model, Min, sum(g[t] * F[a, (t, tau)] for (t, tau) in F_time_set, a in A)
                           + sum(r[v, p, t] * X[v, p, t] for v in V, p in P_v[v], t in T)
                           + sum(pi*S[a,t] for a in A, t in T)
                           + sum(h[v] * r_avg[v, t] * I[v, t] for v in V, t in T)
    )

    # Constraint (2)
    for a in A
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(model, (tau - t + 1) * F[a, (t, tau)] <= sum(Y[p, l] for l in t:tau, p in P_a[a]))
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
                                    if ((t, tau) in F_time_set) && ((t_prime, tau_prime) in F_time_set)
                                        @constraint(model, F[a, (t, tau)] + F[a, (t_prime, tau_prime)] <= 1)
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
        @constraint(model, sum((k - l + 1) * F[a, (l, k)] for (l, k) in F_time_set) >= tmax)
    end

    # Constraint (5)
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(model, sum(F[a, (t, tau)] for a in A_p[p]) >= W[p, (t, tau)])
                end
            end
        end
    end

    # Constraint (6)
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(model, sum(F[a, (t, tau)] for a in A_p[p]) <= length(A_p) * W[p, (t, tau)])
                end
            end
        end
    end

    # Constraint (7)
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(model, sum(Q[v, p, (t, tau)] for v in V_p[p]) <= W[p, (t, tau)] * sum(s_real[p, l] for l in t:tau))
                end
            end
        end
    end

    # Constraint (8) - McCormick_1
    for v in V
        for p in P_v[v]
            for t in T
                for tau in T
                    if (t, tau) in F_time_set
                        @constraint(model, X_tilda[v, p, (t, tau)] == sum(X[v, p, l] for l in t:tau))
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
                    if (t, tau) in F_time_set
                        @constraint(model, Q[v, p, (t, tau)] >= K[v, p, (t, tau)])
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
                    if (t, tau) in F_time_set
                        @constraint(model, K[v, p, (t, tau)] >= X_tilda_upper[v, p, (t, tau)] * W[p, (t, tau)] + X_tilda[v, p, (t, tau)] - X_tilda_upper[v, p, (t, tau)])
                        @constraint(model, K[v, p, (t, tau)] <= X_tilda[v, p, (t, tau)])
                        @constraint(model, K[v, p, (t, tau)] <= X_tilda_upper[v, p, (t, tau)] * W[p, (t, tau)])
                    end
                end
            end
        end
    end

    # Constraint (9)
    for p in P
        for t in T
            @constraint(model, sum(X[v, p, t] for v in V_p[p]) <= s_real[p, t] * Y[p, t])
        end
    end

    # Constraint (10)
    for v in V
        for t in T
            if t >= tmin
                @constraint(model, I[v, t-1] + sum(X[v, p, t] for p in P_v[v]) == Vc[v, t] + I[v, t])
            end
        end
    end

    # Constraint (11)
    for a in A
        for t in T
            if t >= tmin
                @constraint(model, d_real[a, t] - sum(Vc[v, t] for v in V_a[a]) + S[a, t-1] <= S[a, t])
            end
        end
    end

    # Constraint (12)
    for p in P
        for t in T
            @constraint(model, sum(r[v, p, t] * X[v, p, t] for v in V_p[p]) >= Y[p, t] * sum((1 + l[v, p]) * f[v, p, t] for v in V_p[p]))
        end
    end

    # Constraint (13)
    for v in V
        @constraint(model, I[v, 0] == 0)
    end

    return model
end

# second_stage function solves each scenario using the fixed first stage decisions (F_results, Q_results, Y_results, W_results, which are obtained from first_stage function, are input to this model)
function second_stage(pi, g, h, l, F_results, Q_results, Y_results, W_results, d_real, s_real)

    f = Dict()
    for p in P
        for v in V_p[p]
            for t in T
                f[v, p, t] = s_real[p, t] / length(V_p[p]) * r_producer_avg[p] / 2
            end
        end
    end

    X_tilda_lower = Dict()
    X_tilda_upper = Dict()
    
    for v in V
        for p in P_v[v]
            for t in T
                for tau in T
                    if (t, tau) in F_time_set
                        X_tilda_lower[v, p, (t, tau)] = 0
                        X_tilda_upper[v, p, (t, tau)] = sum(s_real[p, l] for l in t:tau)
                    end
                end
            end
        end
    end

    model = Model(with_optimizer(gurobi_solver))

    F = Dict()
    for a in A
        for t in T
            for tau in T
                if (t,tau) in F_time_set
                    F[a,(t,tau)] = F_results[a][t][tau]
                end
            end
        end
    end
    # println(F)
    
    Q = Dict()
    for v in V
        for p in P_v[v]
            for t in T
                for tau in T
                    if (t,tau) in F_time_set
                        Q[v,p,(t,tau)] = Q_results[v][p][t][tau]
                    end
                end
            end
        end
    end
    
    Y = Dict()
    for p in P
        for t in T
            Y[p,t] = Y_results[p][t]
        end
    end
    
    W = Dict()
    for p in P
        for t in T
            for tau in T
                if (t,tau) in F_time_set
                    W[p,(t,tau)] = W_results[p][t][tau]
                end
            end
        end
    end
    
    # For this model, F, Q, Y, and W are not decision variables. We use fixed values obtained from first_stage function.

    # @variable(model, F[a in A, (t,tau) in F_time_set], Bin)
    # @variable(model, Q[v in V, p in P_v[v], (t,tau) in F_time_set] >= 0)
    @variable(model, X[v in V, p in P_v[v], t in T] >= 0)
    @variable(model, X_tilda[v in V, p in P_v[v], (t,tau) in F_time_set] >= 0)
    @variable(model, K[v in V, p in P_v[v], (t,tau) in F_time_set] >= 0)
    # @variable(model, Y[p in P, t in T], Bin)
    @variable(model, I[v in V, t in T_initial] >= 0)
    @variable(model, Vc[v in V, t in T] >= 0)
    @variable(model, S[a in A, t in T_initial] >=0)
    # @variable(model, W[p in P, (t,tau) in F_time_set], Bin)
    
    
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
    
    d_balance = Dict()
    # Constraint (11)
    for a in A
        for t in T
            if t >= tmin
                c = @constraint(model, d_real[a,t] - sum(Vc[v,t] for v in V_a[a]) + S[a,t-1] <= S[a,t])
                d_balance[a,t] = c
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

    return model
end

# To run the full sensitivity analysis, add all the values we want to observe to the list (i.e., pi_list = [30,1] means that the sensitivity analysis will be conducted for unvaccinated children cost as $30 or $1)
# pi_list = [100]
# g_list = [1e6]
# h_list = [0.01]
# l_list = [0.1]
pi_list = [100, 1]
g_list = [1e6, 1e4]
h_list = [0.01, 0.1]
l_list = [0.1, 0.5]

# We are not doing full Design of Experiments here. For the original values, we keep unvaccinated children cost (pi) = 100, tender cost (g) = 1e6, holding cost (h) = 0.01, ROI (l) = 0.1. The first value should be the values we would like to run ultimately.
sensitivity_list = []
for pi in 1:length(pi_list)
    for g in 1:length(g_list)
        for h in 1:length(h_list)
            for l in 1:length(l_list)
                if pi + g + h + l <= 5
                    push!(sensitivity_list, (pi_list[pi],g_list[g],h_list[h],l_list[l]))
                end
            end
        end
    end
end

# In the sensitivity analysis, we work on low / high supply ("S1" / "S3").
# supply_list = ["S3"]
supply_list = ["S1", "S3"]

result = Dict()
for supply_status in supply_list
    for sensitivity in sensitivity_list
        temp = (supply_status,sensitivity)
        println(temp)
        pi, g_val, h_val, l_val = sensitivity
        temp_result = []

        s_real = Dict()
        for row in 2:total_supply_row
            producer = s_real_raw[row, 1]
            for col in 2:total_supply_col
                year = s_real_raw[1, col]
                if supply_status == "S1"
                    s_real[producer, year] = 0.8 * s_real_raw[row, col]
                elseif supply_status == "S2"
                    s_real[producer, year] = s_real_raw[row, col]
                elseif supply_status == "S3"
                    s_real[producer, year] = 1.2 * s_real_raw[row, col]
                end
            end
        end

        d_real = Dict()
        for row in 2:total_demand_row
            antigen = d_real_raw[row,1]
            for col in 2:total_demand_col
                year = d_real_raw[1,col]
                d_real[antigen,year] = 0.0
                for ω in Ω
                    if ω == 1
                        d_real[antigen,year] = round(d_real[antigen,year] + p_ω[ω]*0.8*d_real_raw[row,col], digits = 0)
                    elseif ω == 2
                        d_real[antigen,year] = round(d_real[antigen,year] + p_ω[ω]*1.0*d_real_raw[row,col], digits = 0)
                    elseif ω == 3
                        d_real[antigen,year] = round(d_real[antigen,year] + p_ω[ω]*1.2*d_real_raw[row,col], digits = 0)
                    elseif ω == 4
                        d_real[antigen,year] = round(d_real[antigen,year] + p_ω[ω]*d_pandemic_raw[row,col], digits = 0)
                    elseif ω == 5
                        d_real[antigen,year] = round(d_real[antigen,year] + p_ω[ω]*d_vaccine_replacement_raw[row,col], digits = 0)
                    end
                end
            end
        end

        g = Dict()
        for t in T
            g[t] = g_val
        end

        h = Dict()
        for v in V
            h[v] = h_val
        end

        l = Dict()
        for v in V
            for p in P
                l[v, p] = l_val
            end
        end

        first_model = first_stage(pi, g, h, l, d_real, s_real)
        
        optimize!(first_model)

        total_tender_number = 0
        avg_tender_length = 0.0
        
        count_length_1 = 0
        count_length_3 = 0
        count_length_5 = 0
        for a in A
            for t in T
                for tau in T
                    if (t,tau) in F_time_set
                        if JuMP.value.(first_model[:F][a,(t,tau)]) >= 1.0
                            total_tender_number += 1
                            if tau-t+1 == 1
                                count_length_1 += 1
                            elseif tau-t+1 == 3
                                count_length_3 += 1
                            elseif tau-t+1 == 5
                                count_length_5 += 1
                            end
                            avg_tender_length += (tau-t+1)
                        end
                    end
                end
            end
        end
        avg_tender_length = avg_tender_length/total_tender_number

        F_results = Dict()
        for a in A
            temp_1 = Dict()
            for t in T
                temp_2 = Dict()
                for tau in T
                    if (t, tau) in F_time_set
                        temp_2[tau] = JuMP.value.(first_model[:F][a, (t, tau)])
                    end
                end
                temp_1[t] = temp_2
            end
            F_results[a] = temp_1
        end

        Q_results = Dict()
        for v in V
            temp_1 = Dict()
            for p in P_v[v]
                temp_2 = Dict()
                for t in T
                    temp_3 = Dict()
                    for tau in T
                        if (t, tau) in F_time_set
                            temp_3[tau] = JuMP.value.(first_model[:Q][v, p, (t, tau)])
                        end
                    end
                    temp_2[t] = temp_3
                end
                temp_1[p] = temp_2
            end
            Q_results[v] = temp_1
        end

        Y_results = Dict()
        for p in P
            temp_1 = Dict()
            for t in T
                temp_1[t] = JuMP.value.(first_model[:Y][p, t])
            end
            Y_results[p] = temp_1
        end
        
        W_results = Dict()
        for p in P
            temp_1 = Dict()
            for t in T
                temp_2 = Dict()
                for tau in T
                    if (t, tau) in F_time_set
                        temp_2[tau] = JuMP.value.(first_model[:W][p, (t, tau)])
                    end
                end
                temp_1[t] = temp_2
            end
            W_results[p] = temp_1
        end

        average_obj = 0.0
        average_run_time = 0.0
        average_producer_participated_in_tender_number = 0.0
        average_total_inventory = 0.0
        average_total_unvaccinated_children = 0.0
        # Ω = [1,2,3,4,5]
        for ω in Ω
            d_real = Dict()
            for row in 2:total_demand_row
                antigen = d_real_raw[row,1]
                for col in 2:total_demand_col
                    year = d_real_raw[1,col]
                    if ω == 1
                        d_real[antigen,year] = round(0.8*d_real_raw[row,col], digits = 0)
                    elseif ω == 2
                        d_real[antigen,year] = round(1.0*d_real_raw[row,col], digits = 0)
                    elseif ω == 3
                        d_real[antigen,year] = round(1.2*d_real_raw[row,col], digits = 0)
                    elseif ω == 4
                        d_real[antigen,year] = round(d_pandemic_raw[row,col], digits = 0)
                    elseif ω == 5
                        d_real[antigen,year] = round(d_vaccine_replacement_raw[row,col], digits = 0)
                    end
                end
            end

            model = second_stage(pi, g, h, l, F_results, Q_results, Y_results, W_results, d_real, s_real)

            println(ω)
            # println(d_balance["Measles",1])

            optimize!(model)
            println(JuMP.objective_value(model))

            average_obj += p_ω[ω]*JuMP.objective_value(model)
            average_run_time += p_ω[ω]*JuMP.solve_time(model)

            Producer_production_check = Dict()
            producer_participated_in_tender_number = 0
            for p in P
                temp_amount = 0.0
                for t in T
                    for v in V_p[p]
                        if JuMP.value.(model[:X][v,p,t]) >= 1.0
                            temp_amount = temp_amount + JuMP.value.(model[:X][v,p,t])
                        end
                    end
                end
                Producer_production_check[p] = temp_amount
                if temp_amount > 0.0
                    producer_participated_in_tender_number += 1
                end
            end
            average_producer_participated_in_tender_number += p_ω[ω]*producer_participated_in_tender_number

            total_inventory = 0.0
            for v in V
                for t in T
                    total_inventory += JuMP.value.(model[:I][v,t])
                end
            end
            average_total_inventory += p_ω[ω]*total_inventory

            total_unvaccinated_children = 0.0
            for a in A
                for t in T
                    total_unvaccinated_children += JuMP.value.(model[:S][a,t])
                end
            end
            average_total_unvaccinated_children += p_ω[ω]*total_unvaccinated_children
        end
        push!(temp_result, average_obj)
        push!(temp_result, average_run_time)
        push!(temp_result, total_tender_number)
        push!(temp_result, avg_tender_length)
        push!(temp_result, average_producer_participated_in_tender_number)
        push!(temp_result, average_total_inventory)
        push!(temp_result, average_total_unvaccinated_children)
        # println(average_obj)
        # println(average_run_time)
        # println(avg_tender_length)
        # println(total_tender_number)
        # println(average_producer_participated_in_tender_number)
        # println(average_total_inventory)
        # println(average_total_unvaccinated_children)
        println(temp_result)
        result[supply_status,sensitivity] = temp_result
    end
end
println(result)