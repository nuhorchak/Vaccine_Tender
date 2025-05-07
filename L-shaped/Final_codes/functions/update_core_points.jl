function update_core_points(iter::Int, λ::Float64,
    Q_bar, Y_bar, L_bar, s_real, κ,
    V, P_v, P, T, F_time_set, m_segments, L_lower_number)

    # Initialize or update core point dictionaries
    Q_core = Dict{Tuple{Any,Any,Tuple{Any,Any},Any},Float64}()
    Y_core = Dict{Tuple{Any,Any},Float64}()
    L_core = Dict{Tuple{Any,Any},Float64}()
    L_ddot_core = Dict{Tuple{Any,Any},Float64}()

    if iter == 1
        for v in V, p in P_v[v], (t, tau) in F_time_set, m in keys(m_segments)
            Q_core[v,p,(t,tau),m] = 0.0
        end

        for p in P, t in T
            Y_core[p,t] = 0.0
            L_core[p,t] = L_lower_number
            # L_ddot_core[p,t] = sum(κ * s_real[p] * L_lower_number for t in 1:t)
        end

    else
        for v in V, p in P_v[v], (t, tau) in F_time_set, m in keys(m_segments)
            Q_core[v,p,(t,tau),m] = (1 - λ) * Q_core[v,p,(t,tau),m] + λ * Q_bar[v,p,(t,tau),m]
        end

        for p in P, t in T
            Y_core[p,t] = (1 - λ) * Y_core[p,t] + λ * Y_bar[p,t]
            L_core[p,t] = (1 - λ) * L_core[p,t] + λ * L_bar[p,t]
            # L_ddot_core[p,l] = sum(κ * s_real[p] * L_core[(p,l)] for l in 1:t)
        end
    end

    return Q_core, Y_core, L_core
end
