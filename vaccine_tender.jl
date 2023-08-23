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
A = ["a1","a2","a3","a4","a5"]
V = ["v1","v2","v3","v4","v5"]

A_v = Dict("v1" => ["a1"],"v2" => ["a2"], "v3" => ["a4","a5"], "v4" => ["a1", "a3"], "v5" => ["a1","a2","a3"])

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

P = ["p1","p2","p3"]
P_v = Dict("v1" => ["p1"],"v2" => ["p1","p2"], "v3" => ["p1","p3"], "v4" => ["p2", "p3"], "v5" => ["p1","p2","p3"])

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

tmax = 3
T = [t for t in 0:tmax]

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
d_rand = rand(10*(0:3),length(A),length(T))
d = Dict()
for a in 1:length(A)
    for t in 1:length(T)
        d[A[a],T[t]] = d_rand[a,t]
    end
end
#println(d_rand[4,3]) # -> returns the demand of antigen a4 at t=2 (since set T starts from 0) -> which corresponds to d["a4",2]

Random.seed!(1233) # -> always generate the same production capacity
s_rand = rand(10*(5:10),length(P),length(T))
s = Dict()
for p in 1:length(P)
    for t in 1:length(T)
        s[P[p],T[t]] = s_rand[p,t]
    end
end

Random.seed!(1233)
k_rand = rand(10*(5:10),length(V),length(T))
k = Dict()
for v in 1:length(V)
    for t in 1:length(T)
        k[V[v],T[t]] = k_rand[v,t]
    end
end

Random.seed!(1233)
r_rand = rand(10*(1:3),length(V),length(P),length(T))
r = Dict()
for v in 1:length(V)
    for p in 1:length(P)
        for t in 1:length(T)
            r[V[v],P[p],T[t]] = r_rand[v,p,t]
        end
    end
end

Random.seed!(1233)
r_avg_rand = rand(10*(1:3),length(V),length(T))
r_avg = Dict()
for v in 1:length(V)
    for t in 1:length(T)
        r_avg[V[v],T[t]] = r_avg_rand[v,t]
    end
end

Random.seed!(1233)
l_rand = rand(100*(2:4),length(V),length(P))
l = Dict()
for v in 1:length(V)
    for p in 1:length(P)
        l[V[v],P[p]] = l_rand[v,p]
    end
end

gamma = 0.1

Random.seed!(1233)
g_rand = rand(100*(1:3),length(T))
g = Dict()
for t in 1:length(T)
    g[T[t]] = g_rand[t]
end

Random.seed!(1233)
f_rand = rand(100*(1:2),length(V),length(P),length(T))
f = Dict()
for v in 1:length(V)
    for p in 1:length(P)
        for t in 1:length(T)
            f[V[v],P[p],T[t]] = f_rand[v,p,t]
        end
    end
end

Random.seed!(1233)
h_rand = rand((1:3)/10,length(V))
h = Dict()
for v in 1:length(V)
    h[V[v]] = h_rand[v]
end

pi = 1
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
@variable(model, Q[v in V, p in P, t in T] >= 0)
@variable(model, X[v in V, p in P, t in T] >= 0)
@variable(model, Y[v in V, p in P, t in T], Bin)
@variable(model, I[v in V, t in T] >= 0)
@variable(model, Vc[v in V, t in T] >= 0)
@variable(model, S[a in A, t in T] >=0)

################################################### OBJECTIVE FUNCTION AND CONSTRAINTS ####################################################

@objective(model, Min, sum(g[t]*F[a,t,tau] for t in T, tau in t:tmax, a in A)
                        + sum(r[v,p,t]*X[v,p,t] for v in V, p in P, t in T)
                            + sum(pi*r_avg[v,t]*S[a,t] for v in V, a in A, t in T)
                                + sum(h[v]*r_avg[v,t]*I[v,t] for v in V, t in T)
                                                                                    )

# Constraint (1)
for v in V
    for p in P_v[v]
        for t in T
            for tau in T
                if tau >= t
                    @constraint(model, sum((tau-t+1)*F[a,t,tau] for a in A_v[v]) <= sum(Y[v,p,l] for l in t:tau))
                end
            end
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

# Constraint (3)
for p in P
    for t in T
        @constraint(model, sum(Q[v,p,t] for v in V) <= sum(k[v,l]*Y[v,p,l] for l in t:tmax, v in V))
    end
end

# Constraint (4)
for v in V
    for p in P
        for t in T
            @constraint(model, Q[v,p,t] >= sum(X[v,p,l] for l in t:tmax))
        end
    end
end

# Constraint (5)
for v in V
    for p in P
        @constraint(model, sum(Q[v,p,t] for t in 1:tmax) >= sum(X[v,p,l] for l in 1:tmax))
    end
end

# Constraint (6)
for p in P
    for t in T
        @constraint(model, sum(X[v,p,t] for v in V) <= s[p,t]*sum(Y[v,p,t] for v in V))
    end
end

# Constraint (7)
for v in V
    for t in T
        if t >= 1
            @constraint(model, I[v,t-1] + sum(X[v,p,t] for p in P_v[v]) == Vc[v,t] + I[v,t])
        end
    end
end

# Constraint (8)
for a in A
    for t in T
        if t >= 1
            @constraint(model, d[a,t] - sum(Vc[v,t] for v in V_a[a]) + S[a,t-1] == S[a,t])
        end
    end
end

# Constraint (9)
for p in P
    for t in T
        @constraint(model, sum(r[v,p,t]*X[v,p,t] for v in V_p[p]) >= sum(l[v,p] for v in V_p[p]) - sum(f[v,p,t] for v in V_p[p]))
    end
end

optimize!(model)
println("!!!!!!!!!!!!!!!!!!!!!!!!!  F !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:F]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  Q !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:Q]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  X !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:X]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  Y !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:Y]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  I !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:I]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  Vc !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:Vc]))
println("!!!!!!!!!!!!!!!!!!!!!!!!!  S !!!!!!!!!!!!!!!!!!!!!!!!!!")
println(JuMP.value.(model[:S]))