using JuMP, LinearAlgebra
include(joinpath(functions_directory, "generate_cuts_from_dual.jl")) 

# ===================================================================
# Function: compute_euclidean_distance
# ===================================================================
function compute_euclidean_distance(θ_rhs, π_0, LB, πTb, π_0fT)
    num = θ_rhs + π_0*(LB)
    denom = sqrt((πTb - π_0fT)^2 + π_0^2)
    return num / denom
end

# ===================================================================
# Function: build order of c matrix from objtive function variables
# ===================================================================

function build_variable_order(containers...)
    variable_order = Dict{VariableRef, Int}()
    counter = 1
    for container in containers
        for var in values(container)
            if !haskey(variable_order, var)
                variable_order[var] = counter
                counter += 1
            end
        end
    end
    return variable_order
end       

# ===================================================================
# Function: get c vector from objective function
# ===================================================================
function get_c_vector(model, variable_order::Dict{VariableRef, Int})
    c = zeros(length(variable_order))
    obj_expr = JuMP.objective_function(model)
    for (var, idx) in variable_order
        coeff = JuMP.coefficient(obj_expr, var)
        c[idx] = coeff
    end
    return c
end

# ===================================================================
# Function: generate_cuts_from_dual
# ===================================================================
function generate_deepst_cut_from_dual(Masterproblem, dual_subproblem, Ω_test_partial_2, V, P_v, T, F_time_set, 
    X_tilde_upper, P, s_real_tilde, tmin, A, d_real_tilde, l, f_profit, V_p, 
    starting_points_vect_I, starting_points_vect_S, m_segments, κ, s_real, model, LB)

    if length(dual_subproblem) == 0
        return Masterproblem
    end

    println("Exaluating deepest cuts")

    F_ref = Masterproblem[:F]
    Q_ref = Masterproblem[:Q]
    theta_ref = Masterproblem[:theta]

    variable_order = build_variable_order(F_ref, Q_ref, theta_ref)
    c_vec = get_c_vector(Masterproblem, variable_order)

    candidate_cuts = []

    for ω in Ω_test_partial_2
        cons14_b_By_omega, cons15_b_By_omega = [], []
        cons16_b_By_omega, cons17_b_By_omega = [], []
        cons18_b_By_omega, cons19_b_By_omega = [], []

        for v in V, p in P_v[v], t in T, tau in T
            if (t, tau) in F_time_set
                push!(cons14_b_By_omega, -sum(Q_bar[v,p,(t, tau),m] for m in keys(m_segments)))
            end
        end

        for p in P, t in T
            push!(cons15_b_By_omega, Y_bar[p,t]*s_real_tilde[p, t, ω] + K_ddot_bar[p,t])
        end

        for v in V, t in T
            if t >= tmin
                push!(cons16_b_By_omega, 0.0)
            end
        end

        for a in A, t in T
            if t >= tmin
                push!(cons17_b_By_omega, -d_real_tilde[a, t, ω])
            end
        end

        for i in 1:length(starting_points_vect_I)
            push!(cons18_b_By_omega, starting_points_vect_I[i][2])
        end

        for i in 1:length(starting_points_vect_S)
            push!(cons19_b_By_omega, starting_points_vect_S[i][2])
        end

        b_By_omega = [cons14_b_By_omega, cons15_b_By_omega, cons16_b_By_omega,
                      cons17_b_By_omega, cons18_b_By_omega, cons19_b_By_omega]

        θ_rhs = sum(transpose(b_By_omega[i]) * dual_subproblem[ω][i] for i in 1:length(b_By_omega))
        π = vcat([dual_subproblem[ω][i] for i in 1:length(b_By_omega)]...)
        b = vcat([b_By_omega[i] for i in 1:length(b_By_omega)]...)
        πTb = dot(π, b)
        π_0 = 1.0
        π_0fT = dot(π_0, c_vec)

        dist = compute_euclidean_distance(θ_rhs, π_0, LB, πTb, π_0fT)
        println("Distance: $dist")
        push!(candidate_cuts, (ω=ω, dist=dist, rhs=θ_rhs))
    end

    println("Cut vector length: $(length(candidate_cuts))")

    @variable(max_cuts, 
    @objective(max_cuts, max, (θ_rhs + π_0 * LB) / sqrt((πTb - π_0fT)^2 + π_0^2) for 

    best_cut = argmax(cut -> cut.dist, candidate_cuts)
    println("*** Deepest cut selected for ω = $(best_cut) ***")

    Masterproblem = generate_cuts_from_dual(Masterproblem, dual_subproblem, best_cut.ω, V, P_v, T, F_time_set, 
                X_tilde_upper, P, s_real_tilde, 1, A, d_real_tilde, l, f_profit, V_p, 
                starting_points_vect_I, starting_points_vect_S, m_segments, κ, s_real, model)

    return Masterproblem
end
