"""
    create_bounds(V::Vector, P::Vector, P_v::Dict, T::Vector, F_time_set::Vector, s_real::Dict, κ::Float64, L_upper_number::Int)

Generates bounds for variables used in optimization based on the provided inputs.

# Arguments:
- `V::Vector`: List of vaccines.
- `P::Vector`: List of producers.
- `P_v::Dict`: Mapping of vaccines to producers.
- `T::Vector`: List of time periods.
- `F_time_set::Vector`: Set of (t, tau) time intervals for tender.
- `s_real::Dict`: Real supply capacities for producers.
- `κ::Float64`: Scaling factor for capacity adjustments.
- `L_upper_number::Int`: Upper limit on allowable capacity increases.

# Returns:
- `X_tilde_lower::Dict`: Lower bounds for tender allocations.
- `X_tilde_upper::Dict`: Upper bounds for tender allocations.
- `L_ddot_lower::Dict`: Lower bounds for instantaneous capacity increases.
- `L_ddot_upper::Dict`: Upper bounds for instantaneous capacity increases.
- `L_hat_lower::Dict`: Lower bounds for cumulative capacity increases over (t, tau).
- `L_hat_upper::Dict`: Upper bounds for cumulative capacity increases over (t, tau).
- `L_check_lower::Dict`: Lower bounds for cumulative capacity increases over all past periods.
- `L_check_upper::Dict`: Upper bounds for cumulative capacity increases over all past periods.
"""
function create_bounds(V::Vector, P::Vector, P_v::Dict, T::Vector, F_time_set::Vector, s_real::Dict, κ::Float64, L_upper_number::Int)
    # Initialize dictionaries for bounds
    X_tilde_lower = Dict()
    X_tilde_upper = Dict()
    for v in V
        for p in P_v[v]
            for t in T
                for tau in T
                    if (t, tau) in F_time_set
                        X_tilde_lower[v, p, (t, tau)] = 0
                        X_tilde_upper[v, p, (t, tau)] = sum(s_real[p] for l in t:tau)
                    end
                end
            end
        end
    end

    L_ddot_lower = Dict()
    L_ddot_upper = Dict()
    for p in P
        for t in T
            L_ddot_lower[p, t] = 0
            L_ddot_upper[p, t] = sum(κ * s_real[p] * L_upper_number for l in 1:t)
        end
    end

    L_hat_lower = Dict()
    L_hat_upper = Dict()
    for p in P
        for (t, tau) in F_time_set
            L_hat_lower[p, (t, tau)] = 0
            temp = 0.0
            for l in (t+1):tau
                temp += (tau - l + 1) * κ * s_real[p] * L_upper_number
            end
            L_hat_upper[p, (t, tau)] = temp
        end
    end

    L_check_lower = Dict()
    L_check_upper = Dict()
    for p in P
        for (t, tau) in F_time_set
            L_check_lower[p, (t, tau)] = 0
            L_check_upper[p, (t, tau)] = sum((tau - t + 1) * κ * s_real[p] * L_upper_number for l in 1:t)
        end
    end

    # Return all bounds
    return X_tilde_lower, X_tilde_upper, L_ddot_lower, L_ddot_upper, L_hat_lower, L_hat_upper, L_check_lower, L_check_upper
end
