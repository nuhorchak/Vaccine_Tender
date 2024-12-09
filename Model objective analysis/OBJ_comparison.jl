# THIS IS THE SOCIAL SURPLUS MODEL
@objective(model, Min, sum(g[t] * F[a, (t, tau)] / delta[t] for (t, tau) in F_time_set, a in A if (a,t,tau) ∉ starting_points_vect_F)
                        + sum(p_ω[ω] * r[v, p, t] * X[v, p, t, ω] / delta[t] for v in V, p in P_v[v], t in T, ω in Ω)
                        + sum(p_ω[ω] * pi * S[a, t, ω] / delta[t] for a in A, t in T, ω in Ω)
                        + sum(p_ω[ω] * h[v] * r_avg[v, t] * I[v, t, ω]  / delta[t] for v in V, t in T, ω in Ω)
                        + sum(Γ[p] * L[p, t] / delta[t] for p in P, t in T)
                        + sum(inf_penalty * X_inf[p, t, ω] / delta[t] for p in P, t in T, ω in Ω)
)

@objective(Subproblem, Min, sum(r[v, p, t] * X[v, p, t] / delta[t] for v in V, p in P_v[v], t in T)
    + sum(pi * S[a, t] / delta[t] for a in A, t in T)
    + sum(h[v] * r_avg[v, t] * I[v, t] / delta[t] for v in V, t in T)
    + sum(inf_penalty * X_inf[p, t] / delta[t] for p in P, t in T)
)

################################################### MASTER PROBLEM ####################################################

@objective(Masterproblem, Min, sum(g[t] * F[a, (t, tau)] / delta[t] for (t, tau) in F_time_set, a in A if (a,t,tau) ∉ starting_points_vect_F)
                                + sum(Γ[p] * L[p, t] / delta[t] for p in P, t in T)
                                + sum(p_ω_test[ω]*theta[ω] for ω in Ω_test_partial_2)

                                + p_ω_test[partial_scenario] * (
                                + sum(r[v,p,t] * X[v,p,t,ω] / delta[t] for v in V, p in P_v[v], t in T, ω in Ω_test_partial_1)
                                + sum(pi * S[a,t,ω] / delta[t] for a in A, t in T, ω in Ω_test_partial_1)
                                + sum(h[v] * r_avg[v,t] * I[v,t,ω] / delta[t] for v in V, t in T, ω in Ω_test_partial_1)
                                + sum(inf_penalty * X_inf[p,t,ω] / delta[t] for p in P, t in T, ω in Ω_test_partial_1)
                                )
)



# THIS IS THE MIN UNVAX MODEL


################################################### OBJECTIVE FUNCTION AND CONSTRAINTS ####################################################
if capacity_extension_decision
    @objective(model, Min, sum(p_ω[ω] * pi * S[a, t, ω] / delta[t] for a in A, t in T, ω in Ω) + sum(inf_penalty * X_inf[p, t, ω] / delta[t] for p in P, t in T, ω in Ω)
    )

@objective(Subproblem, Min, sum(pi * S[a, t] / delta[t] for a in A, t in T)
    + sum(inf_penalty * X_inf[p, t] / delta[t] for p in P, t in T)
)

################################################### MASTER PROBLEM ####################################################

@objective(Masterproblem, Min, sum(p_ω_test[ω]*theta[ω] for ω in Ω_test_partial_2)
                            + p_ω_test[partial_scenario] * (
                            + sum(pi * S[a,t,ω] /delta[t] for a in A, t in T, ω in Ω_test_partial_1)
                            + sum(inf_penalty * X_inf[p,t,ω] / delta[t] for p in P, t in T, ω in Ω_test_partial_1)
                            )