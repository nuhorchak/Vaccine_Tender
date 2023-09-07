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
A = ["a1","a2"]
V = ["v1","v2"]

A_v = Dict("v1" => ["a1"],"v2" => ["a2"])

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

P = ["p1","p2"]
P_v = Dict("v1" => ["p1"],"v2" => ["p2"])

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
d_rand = [10 10 20 20 30; 20 20 40 40 60]

d = Dict()
for a in 1:length(A)
    for t in 1:length(T)
        d[A[a],T[t]] = d_rand[a,t]
    end
end

Random.seed!(1233)
k_rand = [20 20 20 20 20; 30 30 30 40 40]
k = Dict()
for v in 1:length(V)
    for t in 1:length(T)
        k[V[v],T[t]] = k_rand[v,t]
    end
end

Random.seed!(1233)
r_rand = [5 2; 5 2;;; 5 2; 5 2;;; 10 4; 10 4;;; 10 4; 10 4;;; 20 8; 20 8]
r = Dict()
for v in 1:length(V)
    for p in 1:length(P)
        for t in 1:length(T)
            r[V[v],P[p],T[t]] = r_rand[v,p,t]
        end
    end
end

Random.seed!(1233)
r_avg_rand = [5 5 10 10 20; 2 2 4 4 8]
r_avg = Dict()
for v in 1:length(V)
    for t in 1:length(T)
        r_avg[V[v],T[t]] = r_avg_rand[v,t]
    end
end

Random.seed!(1233)
l_rand = [50 50; 20 20]
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
@variable(model, I[v in V, t in T_initial] >= 0)
@variable(model, Vc[v in V, t in T] >= 0)
@variable(model, S[a in A, t in T_initial] >=0)

################################################### OBJECTIVE FUNCTION AND CONSTRAINTS ####################################################

@objective(model, Min, sum(g[t]*F[a,t,tau] for t in T, tau in t:tmax, a in A)
                        + sum(gy[t]*Y[v, p, t] for v in V, p in P, t in T)
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
                    @constraint(model, sum((tau-t+1)*F[a,t,tau] for a in A_v[v]) <= length(A_v[v])*sum(Y[v,p,l] for l in t:tau, p in P_v[v]))
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
for a in A
    for t in T
        for tau in T
            if tau >= t
                @constraint(model, sum(F[a,t,l] for l in t:tau) <= 1)
            end
        end
    end
end

# Constraint (4)
for a in A
    @constraint(model, sum((k-l+1)*F[a,l,k] for l in 1:tmax, k in l:tmax) >= tmax)
end

# Constraint (5)
for a in A
    @constraint(model, sum(F[a,1,k] for k in 1:tmax) == 1)
end

# Constraint (6)
for p in P
    for t in T
        @constraint(model, sum(Q[v,p,t] for v in V) <= sum(k[v,l]*Y[v,p,l] for l in t:tmax, v in V))
    end
end

# Constraint (7)
for v in V
    for p in P
        for t in T
            @constraint(model, Q[v,p,t] >= sum(X[v,p,l] for l in t:tmax))
        end
    end
end

# Constraint (8)
for v in V
    for p in P
        @constraint(model, sum(Q[v,p,t] for t in tmin:tmax) >= sum(X[v,p,l] for l in 1:tmax))
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
        @constraint(model, sum(r[v,p,t]*X[v,p,t] for v in V_p[p]) >= sum(l[v,p] for v in V_p[p]) - sum(f[v,p,t] for v in V_p[p]))
    end
end
#=
# Constraint (12)
for v in V
    @constraint(model, I[v,0] == 0)
end
=#
optimize!(model)

println(model)
#=
println("!!!!!!!!!! demand !!!!!!!!!!!")
println(d_rand)
println("!!!!!!!!!! max annual production batch size !!!!!!!!!!!")
println(k_rand)
println("!!!!!!!!!! reservation price !!!!!!!!!!!")
println(r_rand)
println("!!!!!!!!!! f  !!!!!!!!!!!")
println(f_rand)
=#

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
