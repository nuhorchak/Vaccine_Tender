function update_core_points(iter::Int, λ::Float64,
    Q_bar, Y_bar, L_bar, W_bar, K_ddot_bar, s_real, κ,
    V, P_v, P, T, F_time_set, m_segments, L_lower_number)

    Q_bar_dict = Dict(Q_bar.data)
    # Y_bar_dict = Dict(k.key => v for (k, v) in pairs(Y_bar))
    # W_bar_dict = Dict(W_bar.data)
    # L_bar_dict = Dict(k.key => v for (k, v) in pairs(L_bar))

    if iter == 1
        for v in V, p in P_v[v], (t, tau) in F_time_set, m in keys(m_segments)
            Q_core[v,p,(t,tau),m] = 0.0
        end
        
        for p in P, (t,tau) in F_time_set
            W_core[p,(t,tau)] = 0.0
        end

        for p in P, t in T
            Y_core[p,t] = 0.0
            L_core[p,t] = L_lower_number
            K_ddot_core[p,t] = 0.0
        end

        println("Core points generated for iter $iter")

    else
        for v in V, p in P_v[v], (t, tau) in F_time_set, m in keys(m_segments)
            Q_core[v,p,(t,tau),m] = (1 - λ) * Q_core[v,p,(t,tau),m] + λ * Q_bar_dict[v,p,(t,tau),m]
        end

        for p in P, (t,tau) in F_time_set
            W_core[p,(t,tau)] = (1 - λ) * W_core[p,(t,tau)] + λ * W_bar[p,(t,tau)]
        end

        for p in P, t in T
            Y_core[p,t] = (1 - λ) * Y_core[p,t] + λ * Y_bar[p,t]
            L_core[p,t] = (1 - λ) * L_core[p,t] + λ * L_bar[p,t]
            K_ddot_core[p,t] = (1 - λ) * K_ddot_core[p,t] + λ * K_ddot_bar[p,t]
        end

        println("Core points updated for iter $iter")
        # println(Y_core)
    end

    return Q_core, Y_core, L_core, W_core, K_ddot_core
end
