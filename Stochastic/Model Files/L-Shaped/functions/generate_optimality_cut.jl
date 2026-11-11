"""
Single-cut L-shaped (Benders) optimality cut.

The subproblem for scenario ω is an LP with complete recourse, so only optimality cuts are needed. Its
constraints (sub_problem.jl) with their duals π and right-hand sides b:
- (14) sum(X[v,p,l] for l in t:tau) <= sum(Q[v,p,(t,tau),m] for m)                  b depends on Q
- (15) sum(X[v,p,t] for v in V_p[p]) <= Y[p,t] * s_real_tilde[p,t,ω] + K_ddot[p,t]   b depends on Y, K_ddot
- (16) inventory balance                                                              b = 0
- (17) unmet demand / shortage                                                        b = -d_real_tilde[a,t,ω]
- (18) initial inventory                                                              b = I_hat[v]
- (19) initial shortage                                                               b = S_hat[a]

By LP duality, for any first-stage x the recourse cost is bounded below by the dual objective at the current
duals π_ω:

    cut_ω(x) = Σ_(14) π * Q-terms(x) + Σ_(15) π * (Y s_tilde + K_ddot)(x) + Σ_(16)-(19) π * b

which equals the subproblem objective Z_S[ω] at the current master solution (strong duality). The variable
lower bounds (X, I, Vc, S >= 0) have zero RHS and add nothing.

One aggregated cut is added per iteration:

    theta >= Σ_ω p_ω * cut_ω(x)
"""

"""
scenario_cut_expression(Masterproblem, ω, Z_S, cons_14, cons_15, cons_16, cons_17, cons_18, cons_19,
                        V, P_v, P, T, F_time_set, m_segments, s_real_tilde)

Returns cut_ω(x) as an expression in the master variables. Call right after solving scenario ω's subproblem
(its duals are read here). cons_14 and cons_15 must be in the order created by sub_problem.
Errors if the cut does not equal the subproblem objective Z_S at the current master solution.
"""
function scenario_cut_expression(Masterproblem, ω, Z_S, cons_14, cons_15, cons_16, cons_17, cons_18, cons_19,
    V, P_v, P, T, F_time_set, m_segments, s_real_tilde)

    Q = Masterproblem[:Q]
    Y = Masterproblem[:Y]
    K_ddot = Masterproblem[:K_ddot]

    cut_expr = AffExpr(0.0)
    cut_at_x_bar = 0.0   # cut evaluated at the current master solution (subproblem RHS)

    # Constraint (14) - RHS depends on Q; same loop order as sub_problem
    i = 1
    for v in V
        for p in P_v[v]
            for (t, tau) in F_time_set
                dual_i = dual(cons_14[i])
                add_to_expression!(cut_expr, dual_i, sum(Q[v,p,(t,tau),m] for m in keys(m_segments)))
                cut_at_x_bar += dual_i * normalized_rhs(cons_14[i])
                i += 1
            end
        end
    end

    # Constraint (15) - RHS depends on Y and K_ddot; same loop order as sub_problem
    i = 1
    for p in P
        for t in T
            dual_i = dual(cons_15[i])
            add_to_expression!(cut_expr, dual_i, Y[p,t] * s_real_tilde[p,t,ω] + K_ddot[p,t])
            cut_at_x_bar += dual_i * normalized_rhs(cons_15[i])
            i += 1
        end
    end

    # Constraints (16)-(19) - RHS does not depend on the first stage -> constant term of the cut
    for cons in (cons_16, cons_17, cons_18, cons_19)
        for c in cons
            term = dual(c) * normalized_rhs(c)
            add_to_expression!(cut_expr, term)
            cut_at_x_bar += term
        end
    end

    # strong duality check: the cut must be tight at the current master solution
    if abs(cut_at_x_bar - Z_S) > 1e-6 * max(1.0, abs(Z_S))
        error("Cut for scenario $ω is not tight: dual objective $cut_at_x_bar vs subproblem objective $Z_S")
    end

    return cut_expr
end

"""
generate_optimality_cut(Masterproblem, cut_exprs, p_ω)

Adds the single aggregated cut theta >= Σ_ω p_ω[ω] * cut_exprs[ω] to the master problem.
"""
function generate_optimality_cut(Masterproblem, cut_exprs, p_ω)

    theta = Masterproblem[:theta]

    cut_rhs = AffExpr(0.0)
    for (ω, cut_expr) in cut_exprs
        add_to_expression!(cut_rhs, p_ω[ω], cut_expr)
    end

    c = @constraint(Masterproblem, theta >= cut_rhs)
    return c
end
