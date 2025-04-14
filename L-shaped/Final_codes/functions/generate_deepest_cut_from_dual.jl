using JuMP, LinearAlgebra

# # ===================================================================
# # Function: build_benders_x_vector
# # ===================================================================
# function build_benders_x_vector(Q, Y, K_ddot, V, P_v, P, F_time_set, T, m_segments)
#     Q_vec = [Q[v, p, (t, tau), m]
#              for v in V for p in P_v[v] for (t, tau) in F_time_set for m in keys(m_segments)]

#     Y_vec = [Y[p, t] for p in P for t in T]
#     Kddot_vec = [K_ddot[p, t] for p in P for t in T]

#     return vcat(Q_vec, Y_vec, Kddot_vec)
# end

# ===================================================================
# Function: compute_euclidean_distance
# ===================================================================
function compute_euclidean_distance(π, b, π_0, fTx, θ_val, πTb, θ_rhs)
    πTBx = πTb - θ_rhs
    num = abs(πTBx + π_0 * (fTx - θ_val))
    denom = sqrt(πTBx^2 + π_0^2)
    return num / denom
end

# ===================================================================
# Function: generate_cuts_from_dual
# ===================================================================
function generate_cuts_from_dual(Masterproblem, dual_subproblem, Ω_test_partial_2, V, P_v, T, F_time_set, 
    X_tilde_upper, P, s_real_tilde, tmin, A, d_real_tilde, l, f_profit, V_p, 
    starting_points_vect_I, starting_points_vect_S, m_segments, κ, s_real, model)

    Q = Masterproblem[:Q]
    Y = Masterproblem[:Y]
    K_ddot = Masterproblem[:K_ddot]
    theta = Masterproblem[:theta]

    if length(dual_subproblem) == 0
        return Masterproblem
    end

    println("Generating cuts from dual")

    # x_vector = build_benders_x_vector(Q, Y, K_ddot, V, P_v, P, F_time_set, T, m_segments)
    fTx = 0.0  # optionally compute this from objective coefficients
    # x_val = value.(x_vector)
    # θ_vals = Dict(ω => value(theta[ω]) for ω in Ω_test_partial_2)

    candidate_cuts = []

    for ω in Ω_test_partial_2
        cons14_b_By_omega, cons15_b_By_omega = [], []
        cons16_b_By_omega, cons17_b_By_omega = [], []
        cons18_b_By_omega, cons19_b_By_omega = [], []

        for v in V, p in P_v[v], t in T, tau in T
            if (t, tau) in F_time_set
                push!(cons14_b_By_omega, -sum(Q[v,p,(t, tau),m] for m in keys(m_segments)))
            end
        end

        for p in P, t in T
            push!(cons15_b_By_omega, Y[p,t]*s_real_tilde[p, t, ω] + K_ddot[p,t])
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
        # θ_val = θ_vals[ω]
        π_0 = -1.0

        dist = compute_euclidean_distance(π, b, π_0, fTx, value(theta[ω]), πTb, θ_rhs)
        push!(candidate_cuts, (ω=ω, dist=dist, rhs=θ_rhs))
    end

    best_cut = argmax(cut -> cut.dist, candidate_cuts)
    println("*** Deepest cut selected for ω = $(candidate_cuts[best_cut].ω) ***")
    @constraint(Masterproblem, theta[candidate_cuts[best_cut].ω] >= candidate_cuts[best_cut].rhs)

    return Masterproblem
end
