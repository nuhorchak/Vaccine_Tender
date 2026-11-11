"""
Master Problem (full Benders / single-cut L-shaped)

Builds the master problem with only the first-stage decisions and a single variable `theta` for the expected
second-stage (recourse) cost. No scenario is kept in the master: all second-stage variables (X, I, Vc, S) and
constraints are in the subproblems (sub_problem.jl), and enter the master only through the optimality cuts on
`theta` (generate_optimality_cut.jl).

First-stage variables: F, Q, Y, W, L, Z and the McCormick linearization variables (L_hat, K_hat, L_check,
K_check, L_ddot, K_ddot). K_ddot = Y * L_ddot links the capacity extensions to the second-stage capacity
constraint (15) in the subproblem.

Objective = first-stage cost (matches deterministic_equivalent.jl) + theta.

Returns:
- The JuMP model `Masterproblem` with variables, objective and first-stage constraints.
"""

function master_problem(Masterproblem, A, F_time_set, V, P_v, P, T, L_lower_number, L_upper_number,
    starting_points_vect_F, UNICEF_MODEL, Γ, g, delta, r_avg, P_a, κ, s_real, L_hat_upper, L_check_upper, V_p,
    A_p, f_profit, L_ddot_upper, l, m_segments, zeta_vm, phi_vm_lower, phi_vm_upper, social_benefit, max_profit)

    println("Building master problem")

    # -------------------------
    # Precompute
    # -------------------------
    M = collect(keys(m_segments))
    span = Dict((t,tau) => (tau - t + 1) for (t,tau) in F_time_set)
    T_start = unique(t for (t, tau) in F_time_set)  # tender start periods (outer index of constraints 9-10)
    # Valid finite big-M for constraint (10): constraint (7) caps producer p's total award over all windows at
    # Q_max[p]. Used instead of the open-ended last discount break (~1e35), which wrecks the solver numerics.
    Q_max = Dict(p => sum(span[(t,tau)] * s_real[p] + L_hat_upper[p,(t,tau)] + L_check_upper[p,(t,tau)] for (t,tau) in F_time_set) for p in P)

    @variable(Masterproblem, 0.0 <= F[a in A, (t, tau) in F_time_set] <= 1.0, Bin)
    @variable(Masterproblem, Q[v in V, p in P_v[v], (t, tau) in F_time_set, m in M] >= 0)
    @variable(Masterproblem, 0.0 <= Y[p in P, t in T] <= 1.0, Bin)
    @variable(Masterproblem, 0.0 <= W[p in P, (t, tau) in F_time_set] <= 1.0, Bin)
    @variable(Masterproblem, L_lower_number <= L[p in P, t in T] <= L_upper_number, Int)
    @variable(Masterproblem, L_hat[p in P, (t, tau) in F_time_set] >= 0)
    @variable(Masterproblem, K_hat[p in P, (t, tau) in F_time_set] >= 0)
    @variable(Masterproblem, L_check[p in P, (t, tau) in F_time_set] >= 0)
    @variable(Masterproblem, K_check[p in P, (t, tau) in F_time_set] >= 0)
    @variable(Masterproblem, L_ddot[p in P, t in T] >= 0)
    @variable(Masterproblem, K_ddot[p in P, t in T] >= 0)
    @variable(Masterproblem, theta >= 0)  # expected second-stage cost (recourse >= 0 for all model types)
    # @variable(Masterproblem, 0.0 <= Z[v in V, p in P_v[v], t in T, m in M] <= 1, Bin)
    @variable(Masterproblem, 0 <= Z[v in V, p in P_v[v], t in T, m in M] <= 1.0, Bin)

 

    ################################################### MASTER PROBLEM ####################################################

    #CONDITIONS: ALL use capacity extension

    # UNICEF model - base model used, calculated from the perspective of UNICEF-GAVI

    # social benefit - mods to OBJ funs (MP and SP), calcualted to minimize missed doses

    # max profit - mods to OBJ funs (MP and SP), calcualted from the perspective of producers (et. al)

    # Objective = first-stage terms of deterministic_equivalent.jl + theta (expected second-stage cost)
    if UNICEF_MODEL
        @objective(Masterproblem, Min, sum(g[t] * F[a, (t, tau)] / delta[t] for (t, tau) in F_time_set, a in A if (a,t,tau) ∉ starting_points_vect_F) +
        sum(r_avg[v,t] * (1 - zeta_vm[v,m]) * Q[v,p,(t, tau),m] / delta[t] for (t,tau) in F_time_set, v in V, p in P_v[v], m in M)
        + theta
        )

    elseif social_benefit
        # all social-benefit costs (missed doses) are second stage
        @objective(Masterproblem, Min, theta)

    elseif max_profit
        # DE max-profit objective has no second-stage cost terms, so the recourse (theta) is 0
        @objective(Masterproblem, Min, sum((-r_avg[v,t]*(1-zeta_vm[v,m])*Q[v,p,(t,tau),m]) / delta[t] for (t,tau) in F_time_set, v in V, p in P_v[v], m in M) +
        sum((Γ[p] * L[p, t]) / delta[t] for p in P, t in T) +
        sum(f_profit[v, p, (t,tau)] * W[p, (t,tau)] / delta[t] for (t, tau) in F_time_set, p in P, v in V_p[p]) +
        theta
        )

    end


    # Constraint (2)
    for a in A
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(Masterproblem, (tau - t + 1) * F[a, (t, tau)] <= sum(Y[p, l] for l in t:tau, p in P_a[a]))
                end
            end
        end
    end

    # Constraint (3) - at most one tender starting in each period
    for a in A
        for t in T
            @constraint(Masterproblem,
                sum(F[a,(t,tau)] for (t2,tau) in F_time_set if t2 == t) <= 1
            )
        end
    end

    # Constraint (4)
    for a in A
        for t in T
            @constraint(Masterproblem, sum(F[a, (l, k)] for (l, k) in F_time_set if t >= l && t <= k) >= 1)
        end
    end

    # Constraint (5)
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(Masterproblem, sum(F[a, (t, tau)] for a in A_p[p]) >= W[p, (t, tau)])
                end
            end
        end
    end

    # Constraint (6) - a tender can only be covered if some producer of that antigen commits
    for a in A, (t,tau) in F_time_set
        @constraint(Masterproblem, F[a,(t,tau)] <= sum(W[p,(t,tau)] for p in P_a[a]))
    end

    # Constraint (7) - McCormick
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(Masterproblem, sum(Q[v, p, (t, tau), m] for v in V_p[p], m in M) <= W[p,(t,tau)] * span[(t,tau)] * s_real[p] + K_hat[p,(t,tau)] + K_check[p,(t,tau)])
                    @constraint(Masterproblem, L_hat[p,(t,tau)] == sum((tau-l+1)*κ*s_real[p]*L[p,l] for l in t+1:tau))
                    @constraint(Masterproblem, K_hat[p,(t,tau)] >= L_hat[p,(t,tau)] + W[p,(t,tau)]*L_hat_upper[p,(t,tau)] - L_hat_upper[p,(t,tau)])
                    @constraint(Masterproblem, K_hat[p,(t,tau)] <= W[p,(t,tau)]*L_hat_upper[p,(t,tau)])
                    @constraint(Masterproblem, K_hat[p,(t,tau)] <= L_hat[p,(t,tau)])

                    @constraint(Masterproblem, L_check[p,(t,tau)] == sum((tau-t+1)*κ*s_real[p]*L[p,l] for l in 1:t))
                    @constraint(Masterproblem, K_check[p,(t,tau)] >= L_check[p,(t,tau)] + W[p,(t,tau)]*L_check_upper[p,(t,tau)] - L_check_upper[p,(t,tau)])
                    @constraint(Masterproblem, K_check[p,(t,tau)] <= W[p,(t,tau)]*L_check_upper[p,(t,tau)])
                    @constraint(Masterproblem, K_check[p,(t,tau)] <= L_check[p,(t,tau)])
                end
            end
        end
    end

    # Constraint (8) - revenue per tender window, all model types
    for p in P, (t, tau) in F_time_set
        lhs = @expression(Masterproblem, sum(r_avg[v,t] * (1 - zeta_vm[v,m]) * Q[v,p,(t,tau),m] for v in V_p[p], m in M))
        rhs = @expression(Masterproblem, sum((1 + l[v,p]) * f_profit[v,p,(t,tau)] * W[p,(t,tau)] for v in V_p[p]))
        c = @constraint(Masterproblem, lhs >= rhs)
        set_name(c, "revenue_constraint[$p,$t,$tau]")
    end

    # Constraints (9)-(10) - discount segment set on total volume over all tender windows
    # (matches deterministic equivalent; one constraint per start period, duplicates over tau dropped)
    for v in V
        for p in P_v[v]
            for t in T_start
                for m in M
                    Q_total = sum(Q[v,p,(t2,tau2),m] for (t2,tau2) in F_time_set)
                    @constraint(Masterproblem, phi_vm_lower[v,m] * Z[v,p,t,m] <= Q_total)
                    @constraint(Masterproblem, min(phi_vm_upper[v,m], Q_max[p]) * Z[v,p,t,m] >= Q_total)
                end
            end
        end
    end

    # Constraint (11)
    for v in V
        for p in P_v[v]
            for t in T
                @constraint(Masterproblem, sum(Z[v,p,t,m] for m in M) <= 1)
            end
        end
    end

    # Constraint (15) - McCormick for K_ddot = Y * L_ddot (first-stage; used in subproblem capacity constraint)
    for p in P
        for t in T
            @constraint(Masterproblem, L_ddot[p,t] == sum(κ * s_real[p] * L[p, l] for l in 1:t))
            @constraint(Masterproblem, K_ddot[p,t] >= L_ddot[p,t] + Y[p,t] * L_ddot_upper[p,t] - L_ddot_upper[p,t])
            @constraint(Masterproblem, K_ddot[p,t] <= Y[p,t] * L_ddot_upper[p,t])
            @constraint(Masterproblem, K_ddot[p,t] <= L_ddot[p,t])
        end
    end

    # Second-stage constraints (14), (16)-(20) are in sub_problem.jl and enter the master through the cuts on theta

    # Constraint (21) - Initial F Decision
    for (a, t, tau) in starting_points_vect_F
        c = @constraint(Masterproblem, F[a, (t, tau)] == 1)
        set_name(c, "master_c_21[$((a,t,tau))]")
    end

    return Masterproblem
end