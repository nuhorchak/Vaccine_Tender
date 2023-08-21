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

tmax = 3
T = [t for t in 0:tmax]
println(T)

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
d = rand(10*(0:3),length(A),length(T))
#println(demand_random[4,3]) # -> returns the demand of antigen a4 at t=3

Random.seed!(1233) # -> always generate the same production capacity
s = rand(10*(1:10),length(P),length(T))
#println(s[1,:]) # -> returns the production capacity of producer p1 for all periods

Random.seed!(1233)
k = rand(10*(1:6),length(V),length(T))

Random.seed!(1233)
r = rand((1:3),length(V),length(P),length(T))
#println(r[1,2,3]) # -> returns the reservation price of vaccine v1 produced by p2 for period t=3
#println(r)
Random.seed!(1233)
r_avg = rand((1:3),length(V),length(T))
#println(r_avg)

Random.seed!(1233)
l = rand(100*(3:5),length(V),length(P))

gamma = 0.1

Random.seed!(1233)
g = rand(100*(1:3),length(T))

Random.seed!(1233)
f = rand(100*(1:2),length(V),length(P),length(T))

Random.seed!(1233)
h = rand((1:3)/10,length(V))

pi = 1
beta = 0.1

################################################### DECISION VARIABLES ####################################################
#=
Variable Definitions:
F: a binary variable if a tender covers demand in period t to tau for antigen a
Q:
X:
Y:
I:
Vc:
S:
=#


model=Model()

@variable(model, F[a in A, t in T, tau in t:tmax], Bin)
@variable(model, Q[v in V, p in P, t in T])
@variable(model, X[v in V, p in P, t in T])
@variable(model, Y[v in V, p in P, t in T], Bin)
@variable(model, I[v in V, t in T])
@variable(model, Vc[v in V, t in T])
@variable(model, S[a in A, t in T])