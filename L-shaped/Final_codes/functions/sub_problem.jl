"""
sub_problem(F_bar, W_bar, Y_bar, Q_bar, L_bar, L_ddot_bar, K_ddot_bar, ω)

Defines the sub-problem for the optimization model, including variables, constraints, and objective functions.

# Arguments
- `F_bar`: A dictionary containing binary variables (F_at_tau), indicating tender coverage for antigen (a) over periods (t) through (tau).
- `W_bar`: A dictionary with binary variables (W_pt_tau), representing producer (p)'s commitments for periods (t) through (tau).
- `Y_bar`: A dictionary with binary variables (Y_pt), indicating whether producer (p) produces in period (t).
- `Q_bar`: A dictionary containing variables (Q_vpt_tau_m), representing procurement commitments for vaccine (v) by producer (p) over periods (t) through (tau) in discount segment (m).
- `L_bar`: A dictionary representing integer variables (L_pt), which indicate capacity extension for producer (p) in period (t).
- `L_ddot_bar`: A dictionary capturing additional capacity-related constraints for (L).
- `K_ddot_bar`: A dictionary for capacity scaling related to (K).
- `ω`: A specific scenario index for scenario-dependent parameters.

# Outputs
- `Subproblem`: The JuMP optimization model representing the sub-problem.
- `cons_8_1` to `cons_14`: Arrays of constraints applied in the sub-problem.

# Key Components
1. **Variables**:
   - (X): Doses of vaccines delivered by producers.
   - (I): Inventory levels of vaccines.
   - (Vc): Vaccines administered.
   - (S): Missed doses of antigens.
   - (X_inf): Auxiliary variables for infeasibilities.
   - (X_tilde), (K): Intermediate variables for McCormick-related reformulations.

2. **Objective Function**:
   - Varies based on the model type:
     - **Base model (UNICEF)**: Minimizes total costs including social costs and penalties.
     - **Testing model**: Focuses on inventory and infeasibility penalties.
     - **Min Unvaccinated model**: Minimizes missed doses and infeasibility penalties.

3. **Constraints**:
   - Constraints (8)-(14): Represent system-specific constraints such as McCormick conditions, capacity limits, inventory dynamics, unmet demand, and initial conditions.

# Notes
- The sub-problem model uses JuMP with Gurobi as the solver.
- McCormick constraints are reformulated to avoid explicit McCormick envelopes.
- Ensure the required parameters and dictionaries are pre-defined before calling the function.
"""


function sub_problem(F_bar, W_bar, Y_bar, Q_bar, L_bar, L_ddot_bar, K_ddot_bar, ω, beta, f_profit, delta, r_avg, gurobi_solver_no_presolve,
    V, P_v, T, T_initial, A, P, F_time_set, tmin, V_p, X_tilde_upper, s_real_tilde, d_real_tilde, V_a, starting_points_vect_I, 
    starting_points_vect_S, r, h, l, zeta_vm, m_segments, UNICEF_MODEL, social_benefit, max_profit)

    println("Building sub problem")


    Subproblem = JuMP.Model()
    JuMP.set_optimizer(Subproblem, gurobi_solver_no_presolve)

    @variable(Subproblem, X[v in V, p in P_v[v], t in T] >= 0)
    @variable(Subproblem, I[v in V, t in T_initial] >= 0)
    @variable(Subproblem, Vc[v in V, t in T] >= 0)
    @variable(Subproblem, S[a in A, t in T_initial] >= 0)
    # @variable(Subproblem, X_inf[p in P, t in T] >= 0)
    @variable(Subproblem, X_tilde[v in V, p in P_v[v], (t,tau) in F_time_set] >= 0)
    @variable(Subproblem, K[v in V, p in P_v[v], (t,tau) in F_time_set] >= 0)

    # CONDITIONS: ALL use capacity extension

    # UNICEF model - base model used, calculated from the perspective of UNICEF-GAVI

    # social benefit - mods to OBJ funs (MP and SP), calcualted to minimize missed doses

    # max profit - mods to OBJ funs (MP and SP), calcualted from the perspective of producers (et. al)
    
    if UNICEF_MODEL  #base model
        println("Condition: Base model")
        @objective(Subproblem, Min, sum(r[v, p, t] * X[v, p, t] / delta[t] for v in V, p in P_v[v], t in T)
        + sum(beta * S[a, t] / delta[t] for a in A, t in T)
        + sum(h[v] * r_avg[v, t] * I[v, t] / delta[t] for v in V, t in T)
        )
    elseif social_benefit #min unvax model
        println("Condition: Min Unvax Model")
        @objective(Subproblem, Min, sum(beta * S[a, t] / delta[t] for a in A, t in T)
        )
    else max_profit #max profit
        println("Condition: Max Profit model")
        @objective(Subproblem, Min, sum(r_avg[v,t]* S[a, t]/ delta[t] for a in A, t = last(T), v in V))
    end

    cons_14_1 = []
    cons_14_2 = []
    cons_14_3 = []
    cons_14_4 = []
    cons_14_5 = []
    cons_15 = []
    cons_16 = []
    cons_17 = []
    # cons_12 = []
    cons_18 = []
    cons_19 = []

    # constraint 14 - McCormick - this uses McCormack relaxation...can we remove it?
    for v in V
        for p in P_v[v]
            for m in keys(m_segments)
                for t in T
                    for tau in T
                        if (t,tau) in F_time_set
                            c = @constraint(Subproblem, X_tilde[v,p,(t,tau)] == sum(X[v,p,l] for l in t:tau))
                            set_name(c, "c_14_1[$((v,p,(t,tau)))]")
                            push!(cons_14_1, c)
                            c = @constraint(Subproblem, Q_bar[v,p,(t,tau),m] >= K[v,p,(t,tau)])
                            set_name(c, "c_14_2[$((v,p,(t,tau)))]")
                            push!(cons_14_2, c)
                            c = @constraint(Subproblem, K[v,p,(t,tau)] >= X_tilde_upper[v,p,(t,tau)]*W_bar[p,(t,tau)] + X_tilde[v,p,(t,tau)] - X_tilde_upper[v,p,(t,tau)])
                            set_name(c, "c_14_3[$((v,p,(t,tau)))]")
                            push!(cons_14_3, c)
                            c = @constraint(Subproblem, K[v,p,(t,tau)] <= X_tilde[v,p,(t,tau)])
                            set_name(c, "c_14_4[$((v,p,(t,tau)))]")
                            push!(cons_14_4, c)
                            c = @constraint(Subproblem, K[v,p,(t,tau)] <= X_tilde_upper[v,p,(t,tau)]*W_bar[p,(t,tau)])
                            set_name(c, "c_14_5[$((v,p,(t,tau)))]")
                            push!(cons_14_5, c)
                        end
                    end
                end
            end
        end
    end

    # Constraint (15) McCormick
    for p in P
        for t in T
            if Y_bar[p,t]*s_real_tilde[p, t, ω] + K_ddot_bar[p,t] < 1e-1
                c = @constraint(Subproblem, sum(X[v,p,t] for v in V_p[p]) <= round(Y_bar[p,t]*s_real_tilde[p, t, ω] + K_ddot_bar[p,t], digits=0))
            else
                c = @constraint(Subproblem, sum(X[v,p,t] for v in V_p[p]) <= Y_bar[p,t]*s_real_tilde[p, t, ω] + K_ddot_bar[p,t])
            end

            set_name(c, "c_15[$((p,t))]")
            push!(cons_15, c)
        end
    end

    # Constraint (16)
    for v in V
        for t in T
            if t >= tmin
                c = @constraint(Subproblem, I[v, t-1] + sum(X[v, p, t] for p in P_v[v]) == Vc[v, t] + I[v, t])
                set_name(c, "c_16[$((v,t))]")
                push!(cons_16, c)
            end
        end
    end

    # Constraint (17)
    for a in A
        for t in T
            if t >= tmin
                c = @constraint(Subproblem, d_real_tilde[a, t, ω] - sum(Vc[v, t] for v in V_a[a]) + S[a, t-1] <= S[a, t])
                set_name(c, "c_17[$((a,t))]")
                push!(cons_17, c)
            end
        end
    end

    # # Constraint (12) - remove
    # for p in P
    #     for t in T
    #         c = @constraint(Subproblem, sum(r[v, p, t] * X[v, p, t] for v in V_p[p]) + X_inf[p, t] >= Y_bar[p, t] * sum((1 + l[v, p]) * f_profit[v, p, t] for v in V_p[p]))
    #         set_name(c, "c_12[$((p,t))]")
    #         push!(cons_12, c)
    #     end
    # end

    # Constraint (18)
    for i in 1:length(starting_points_vect_I)
        v = starting_points_vect_I[i][1]
        amount = starting_points_vect_I[i][2]
        c = @constraint(Subproblem, I[v,0] == amount)
        set_name(c, "c_18[$v]")
        push!(cons_18, c)
    end

    # Constraint (19)
    for i in 1:length(starting_points_vect_S)
        a = starting_points_vect_S[i][1]
        amount = starting_points_vect_S[i][2]
        c = @constraint(Subproblem, S[a,0] == amount)
        set_name(c, "c_19[$a]")
        push!(cons_19, c)
    end
    return Subproblem, cons_14_1, cons_14_2, cons_14_3, cons_14_4, cons_14_5, cons_15, cons_16, cons_17, cons_18, cons_19
end