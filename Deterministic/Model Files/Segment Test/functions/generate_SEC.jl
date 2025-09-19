function generate_SEC(iter1::Int, Masterproblem::Model, F_bar, F_time_set, S_sub, A, T_initial, random_scenarios, p_ω_test, d_real_tilde; threshold::Float64 = 0.1)
    if iter1 > 1
        S_results = Dict(a => Dict(t => Dict(ω => S_sub[ω][a, t] for ω in random_scenarios) for t in T_initial) for a in A)

        total_weighted_missed = sum(p_ω_test[ω] * sum(S_results[a][t][ω] for a in A, t in T_initial) for ω in random_scenarios)
        println("Total Missed doses: $total_weighted_missed")

        total_weighted_demand = sum(p_ω_test[ω] * d_real_tilde[(a, t, ω)] for (a, t, ω) in keys(d_real_tilde))
        println("Total Demand: $total_weighted_demand")

        ratio = total_weighted_missed / total_weighted_demand
        println("Ratio of Missed doses to demand: $ratio")

        if ratio >= threshold
            println("Generating solution elimination constraint for F[a,(t,tau)]")
            mismatch_sum = sum(1 - Masterproblem[:F][a, (t, tau)] for a in A, (t, tau) in F_time_set if F_bar[a, (t, tau)] == 1) +
                           sum(Masterproblem[:F][a, (t, tau)] for a in A, (t, tau) in F_time_set if F_bar[a, (t, tau)] == 0)
            @constraint(Masterproblem, mismatch_sum >= 1)
        end
    end
end