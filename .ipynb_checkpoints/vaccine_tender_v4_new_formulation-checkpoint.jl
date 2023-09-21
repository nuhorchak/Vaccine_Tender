using JuMP
using Gurobi
using Random

gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol"=>1e-6)

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
A = ["Measles","Mumps","Rubella"]
V = ["M","MR","MMR"]

A_v = Dict("M" => ["Measles"], "MR" => ["Measles","Rubella"], "MMR" => ["Measles","Mumps", "Rubella"])

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

P = ["Serum Institute of India","PT Bio Farma", "GlaxoSmithKline", "Merck Sharp & Dohme", "Biological E. Limited"]
P_v = Dict("M" => ["Serum Institute of India", "PT Bio Farma"],"MR" => ["Serum Institute of India", "Biological E. Limited"], "MMR" => ["Serum Institute of India","GlaxoSmithKline", "Merck Sharp & Dohme"])

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

tmin = 1
tmax = 5
T = [t for t in tmin:tmax]
T_initial = [t for t in tmin-1:tmax]

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

Random.seed!(1230) # -> always generate the same demand
#d_rand = [10 10 20 20 30; 20 20 40 40 60]

d_real = [11006234.91 5751303.32 829582.94 854456.60 882693.02; 1846729.12 1948070.23 2019683.90 2086697.63 2148068.09; 154337077.7 69304118.4 122627458.4 77770557.69 84871745.66]


d = Dict()
for a in 1:length(A)
    for t in 1:length(T)
        d[A[a],T[t]] = d_real[a,t]
    end
end

Random.seed!(1233)
k_rand = [2110062340  57513030 18467290 18467290 1543537077; 11006234 57513030 18467290 1543737077 1543370779; 11006234 57513030 18467290 1543370779 1594337077]
k = Dict()
for v in 1:length(V)
    for t in 1:length(T)
        k[V[v],T[t]] = k_rand[v,t]
    end
end

Random.seed!(1233)
r_rand = [0.53745 0.5776 0.53745 9999 9999; 0.5679 .82 0.53745 9999 9999; 0.59835 8 0.53745 0.024 9999;;; 0.5679 .52 0.53745 9999 9999; 0.6288 0.2864 0.53745 9999 9999; 0.2864 0.024 0.53745 9999 9999;;; 0.59835 .456 0.53745 9999 9999; 0.2864 .44 0.53745 .756 0.756; 0.32405 0.2864 0.53745 0.75 0.56;;; 0.6288 4 0.53745 0.56 9999; 10 4 0.53745 9999 9999; 15 15 0.53745 9999 9999;;; 0.32405 0.024 0.53745 9999 9999; 0.024 8 0.53745 9999 9999; 30 30 0.53745 9999 9999]
#r_rand = [5 2; 5 2; 6 6;;; 5 2; 5 2; 6 6;;; 10 4; 10 4; 12 12;;; 10 4; 10 4; 12 12;;; 20 8; 20 8; 24 24]
r = Dict()
for v in 1:length(V)
    for p in 1:length(P)
        for t in 1:length(T)
            println("Vaccine $v, Producer $p, Time $t")
            println(r_rand[v,p,t])
            r[V[v],P[p],T[t]] = r_rand[v,p,t]
        end
    end
end

Random.seed!(1233)
r_avg_rand = [0.411925 0.4316 0.451275 0.47095 0.174025; 0.760225 0.7799 0.799575 0.81925 0.522325; 0.763625 0.7833 0.802975 0.82265 0.525725]
r_avg = Dict()
for v in 1:length(V)
    for t in 1:length(T)
        r_avg[V[v],T[t]] = r_avg_rand[v,t]
    end
end

Random.seed!(1233)
l_rand = [0.1 0.1 0.1 0.1 0.1; 0.1 0.1 0.1 0.1 0.1; 0.1 0.1 0.1 0.1 0.1]
l = Dict()
for v in 1:length(V)
    for p in 1:length(P)
        l[V[v],P[p]] = l_rand[v,p]
    end
end

gamma = 0.1

Random.seed!(1233)
g_rand = [10 10 10 10 10]
g = Dict()
for t in 1:length(T)
    g[T[t]] = g_rand[t]
end

Random.seed!(1233)
gy_rand = [10 10 10 10 10]
gy = Dict()
for t in 1:length(T)
    gy[T[t]] = gy_rand[t]
end

Random.seed!(1233)
f_rand = rand(10*(1:1),length(V),length(P),length(T))
f = Dict()
for v in 1:length(V)
    for p in 1:length(P)
        for t in 1:length(T)
            f[V[v],P[p],T[t]] = f_rand[v,p,t]
        end
    end
end

Random.seed!(1233)
h_rand = rand((1:1),length(V))
h = Dict()
for v in 1:length(V)
    h[V[v]] = h_rand[v]
end

pi = 10
beta = 0.1

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

model=Model(with_optimizer(gurobi_solver))

@variable(model, F[a in A, t in T, tau in t:tmax], Bin)
@variable(model, Q[v in V, p in P_v[v], t in T, tau in t:tmax] >= 0)
@variable(model, X[v in V, p in P_v[v], t in T] >= 0, Int)
@variable(model, Y[v in V, p in P_v[v], t in T], Bin)
@variable(model, I[v in V, t in T_initial] >= 0, Int)
@variable(model, Vc[v in V, t in T] >= 0, Int)
@variable(model, S[a in A, t in T_initial] >=0, Int)
@variable(model, δ[v in V, p in P_v[v], t in T, tau in t:tmax], Bin)

################################################### OBJECTIVE FUNCTION AND CONSTRAINTS ####################################################

@objective(model, Min, sum(g[t]*F[a,t,tau] for t in T, tau in t:tmax, a in A)
                        + sum(gy[t]*Y[v, p, t] for v in V, p in P_v[v], t in T)
                            + sum(r[v,p,t]*X[v,p,t] for v in V, p in P_v[v], t in T)
                                + sum(pi*r_avg[v,t]*S[a,t] for v in V, a in A, t in T)
                                    + sum(h[v]*r_avg[v,t]*I[v,t] for v in V, t in T)
                                                                                    )

# Constraint (1)
for v in V
    for p in P_v[v]
        for t in T
            @constraint(model, sum(F[a,l,k] for a in A_v[v], l in 1:t, k in t:tmax) >= Y[v,p,t])
        end
    end
end

# Constraint (2)
for a in A
    for t in T
        for tau in T
            if tau >= t
                @constraint(model, sum(F[a,l,tau] for l in t:tau) <= 1)
            end
        end
    end
end

# Constraint (2-b)
for a in A
    for t in T
        for tau in T
            if tau >= t
                @constraint(model, sum(F[a,t,l] for l in t:tau) <= 1)
            end
        end
    end
end

# Constraint (2-c)
for a in A
    for t in T
        for tau in T
            if tau >= t
                for t_prime in T
                    for tau_prime in T
                        if tau_prime >= t_prime
                            if (t_prime < t) && (tau_prime >= t) && (tau_prime < tau)
                                @constraint(model, F[a,t,tau] + F[a,t_prime,tau_prime] <= 1)
                            end
                            if (t_prime > t) && (t_prime <= tau) && (tau_prime > tau)
                                @constraint(model, F[a,t,tau] + F[a,t_prime,tau_prime] <= 1)
                            end
                            if (t_prime > t) && (t_prime < tau) && (tau_prime > t) && (tau_prime < tau)
                                @constraint(model, F[a,t,tau] + F[a,t_prime,tau_prime] <= 1)
                            end
                            if (t_prime < t) && (tau_prime > tau)
                                @constraint(model, F[a,t,tau] + F[a,t_prime,tau_prime] <= 1)
                            end
                        end
                    end
                end
            end
        end
    end
end

#=
# Overlap test
for a in A
    @constraint(model, F[a,1,2] + F[a,3,3] == 2)
end
=#
#=
# Overlap test 2
for a in A
    @constraint(model, F[a,1,2] + F[a,3,4] == 2)
end
=#
#=
# Overlap test 2
for a in A
    @constraint(model, F[a,1,2] == 1)
end
=#

# Constraint (3)
for a in A
    @constraint(model, sum((k-l+1)*F[a,l,k] for l in 1:tmax, k in l:tmax) >= tmax)
end

# Constraint (4)
for v in V
    for p in P_v[v]
        for t in T
            for tau in T
                if tau >= t
                    @constraint(model, Q[v,p,t,tau] <= 1000 * sum(F[a,t,tau] for a in A_v[v]))
                end
            end
        end
    end
end

# Constraint (5)
for v in V
    for p in P_v[v]
        for t in T
            for tau in T
                if tau >= t
                    @constraint(model, Q[v,p,t,tau] <= sum(k[v,l]*Y[v,p,l] for l in t:tau))
                end
            end
        end
    end
end

# Constraint (6) - auxilary variable constraint a
for v in V
    for p in P_v[v]
        for t in T
            for tau in T
                if tau >= t
                    @constraint(model, sum(F[a,t,tau] for a in A_v[v]) >= δ[v,p,t,tau])
                end
            end
        end
    end
end

# Constraint (6) - auxilary variable constraint b
for v in V
    for p in P_v[v]
        for t in T
            for tau in T
                if tau >= t
                    @constraint(model, sum(F[a,t,tau] for a in A_v[v]) <= length(A_v) * δ[v,p,t,tau])
                end
            end
        end
    end
end

# Constraint (7)
for v in V
    for p in P_v[v]
        for t in T
            for tau in T
                if tau >= t
                    #@constraint(model, Q[v,p,t,tau] >= δ[v,p,t,tau] * sum(X[v,p,l] for l in t:tau))
                    @constraint(model, Q[v,p,t,tau] + 1000*(1-δ[v,p,t,tau]) >= sum(X[v,p,l] for l in t:tau))
                end
            end
        end
    end
end

# Constraint (8)
for v in V
    for p in P_v[v]
        for t in T
            @constraint(model, X[v,p,t] <= k[v,t])
        end
    end
end

# Constraint (9)
for v in V
    for t in T
        if t >= tmin
            @constraint(model, I[v,t-1] + sum(X[v,p,t] for p in P_v[v]) == Vc[v,t] + I[v,t])
        end
    end
end

# Constraint (10)
for a in A
    for t in T
        if t >= tmin
            @constraint(model, d[a,t] - sum(Vc[v,t] for v in V_a[a]) + S[a,t-1] == S[a,t])
        end
    end
end

# Constraint (11)
for p in P
    for t in T
        @constraint(model, sum(r[v,p,t]*X[v,p,t] for v in V_p[p]) >= sum((1+l[v,p])*f[v,p,t]*Y[v,p,t] for v in V_p[p]))
    end
end

# Constraint (12)
for v in V
    @constraint(model, I[v,0] == 0)
end

optimize!(model)
#print(model)

if primal_status(model) == MOI.NO_SOLUTION
    compute_conflict!(model)
    iis_model, _ = copy_conflict(model)
    print(iis_model)
end

println("!!!!!!!!!!!!!!!!!!!!!!!!!  F !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:F]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  Y !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:Y]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  Q !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:Q]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  X !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:X]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  I !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:I]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  Vc !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:Vc]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  S !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:S]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  Delta !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:δ]))