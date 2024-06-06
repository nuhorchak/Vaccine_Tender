using JuMP
using Gurobi
using Random
using Dualization
using Plots
import XLSX
import JSON

gurobi_solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-4, "OutputFlag" => 0, "Presolve" => 0, "NumericFocus" => 1, "MIPGap" => 1e-3) 
gurobi_solver_no_presolve = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-4, "OutputFlag" => 0, "Presolve" => 0, "NumericFocus" => 1, "MIPGap" => 1e-3) 

# max_tender_length => integer number 
# antigen_list_input => "MMR" => if we need to use MMR-related information only, "ALL" => If we include all the antigens
function tender_stochastic(max_tender_length, antigen_list_input)
    supply_status = "S2" # "S1" => "S_low" or "S2" => "S_med" or "S3" => "S_high"
    overlap_decision = true
    capacity_extension_decision = false
    relaxation_decision = true

    ################################################### INDICES ####################################################
    if antigen_list_input == "ALL"
        A = ["Measles", "Mumps", "Rubella", "Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio", "HPV", "Rotavirus", "PCV"]
        V = ["M", "MR", "MMR", "TT", "HepB", "Hib", "IPV", "OPV", "DT", "Td", "DTwP", "DTwP-Hib", "Penta", "Hexa", "HPV", "Rotavirus", "PCV"]
        A_v = Dict("M" => ["Measles"], "MR" => ["Measles", "Rubella"], "MMR" => ["Measles", "Mumps", "Rubella"], "TT" => ["Tetanus"], "HepB" => ["Hepatitis_B"], "Hib" => ["Hib"], "IPV" => ["Polio"],
            "OPV" => ["Polio"], "DT" => ["Diphtheria", "Tetanus"], "Td" => ["Diphtheria", "Tetanus"], "DTwP" => ["Diphtheria", "Tetanus", "Pertussis"],
            "DTwP-Hib" => ["Diphtheria", "Tetanus", "Pertussis", "Hib"], "Penta" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib"],
            "Hexa" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio"], "HPV" => ["HPV"], "Rotavirus" => ["Rotavirus"], "PCV" => ["PCV"])
        P = ["AJ_Vaccines", "BB_NCIPD", "Beijing_Institute", "Bharat_Biotech", "Bilthoven", "Biological_E", "Centro_de", "GSK", "Haffkine_Bio",
            "LG_Chem", "Merck_Sharp", "Panacea_Biotec", "PT_Bio", "Sanofi_Pasteur", "Serum_Institute", "Xiamen_Innovax", "Pfizer"]

        P_v = Dict("M" => ["Serum_Institute", "PT_Bio"], "MR" => ["Serum_Institute", "Biological_E"], "MMR" => ["Serum_Institute", "GSK", "Merck_Sharp"],
            "TT" => ["Serum_Institute", "PT_Bio", "BB_NCIPD"], "HepB" => ["Serum_Institute", "LG_Chem"], "Hib" => ["Serum_Institute", "Sanofi_Pasteur", "Centro_de"],
            "IPV" => ["LG_Chem", "AJ_Vaccines", "Bilthoven", "Sanofi_Pasteur"],
            "OPV" => ["Serum_Institute", "PT_Bio", "GSK", "Sanofi_Pasteur", "Panacea_Biotec", "Beijing_Institute", "Bharat_Biotech", "Haffkine_Bio"],
            "DT" => ["Serum_Institute", "PT_Bio", "BB_NCIPD"], "Td" => ["Serum_Institute", "PT_Bio", "BB_NCIPD"], "DTwP" => ["Serum_Institute", "Biological_E"], "DTwP-Hib" => ["Serum_Institute"],
            "Penta" => ["Serum_Institute", "PT_Bio", "Biological_E", "LG_Chem", "Panacea_Biotec"], "Hexa" => ["Sanofi_Pasteur"],
            "HPV" => ["GSK", "Merck_Sharp", "Xiamen_Innovax"], "Rotavirus" => ["Serum_Institute", "GSK", "Bharat_Biotech"], "PCV" => ["Serum_Institute", "GSK", "Pfizer"])
    elseif antigen_list_input == "MMR"
        A = ["Measles", "Mumps", "Rubella"]
        V = ["M", "MR", "MMR"]
        A_v = Dict("M" => ["Measles"], "MR" => ["Measles", "Rubella"], "MMR" => ["Measles", "Mumps", "Rubella"])
        P = ["Biological_E", "GSK", "Merck_Sharp", "PT_Bio", "Serum_Institute"]
        P_v = Dict("M" => ["Serum_Institute", "PT_Bio"], "MR" => ["Serum_Institute", "Biological_E"], "MMR" => ["Serum_Institute", "GSK", "Merck_Sharp"])
    end

    antigen_list_check = ""
    if length(A) == 3
        antigen_list_check = "_MMR_antigens"
    else
        length(A) > 3
        antigen_list_check = "_All_antigens"
    end

    V_a = Dict()
    for a in A
        vector_a = []
        for v in keys(A_v)
            if a in A_v[v]
                push!(vector_a, v)
            end
        end
        V_a[a] = vector_a
    end

    V_p = Dict()
    for p in P
        vector_p = []
        for v in keys(P_v)
            if p in P_v[v]
                push!(vector_p, v)
            end
        end
        V_p[p] = vector_p
    end

    P_a = Dict()
    for a in A
        vector_a = []
        vaccines = V_a[a]
        for v in vaccines
            producers = P_v[v]
            for p in producers
                if p ∉ vector_a
                    push!(vector_a, p)
                end
            end
        end
        P_a[a] = vector_a
    end

    A_p = Dict()
    for p in P
        vector_p = []
        for a in keys(P_a)
            if p in P_a[a]
                push!(vector_p, a)
            end
        end
        A_p[p] = vector_p
    end

    tmin = 1
    tmax = max_tender_length
    T = [t for t in tmin:tmax]
    T_initial = [t for t in tmin-1:tmax]

    Δ = [1,2,3,4,5]

    test_scenario_number = 5
    train_scenario_number = 25
    total_scenarios = test_scenario_number + train_scenario_number

    function generate_omega_list(start_number,end_number)
        return collect(start_number:end_number)
    end

    Ω_test_partial_1 = generate_omega_list(1,1)

    Ω_test = generate_omega_list(1,test_scenario_number)
    Ω_train = generate_omega_list(test_scenario_number+1,total_scenarios)

    println(Ω_test_partial_1)
    println(Ω_train)

    p_ω_test = Dict(ω => 1/length(Ω_test) for ω in Ω_test)

    println(p_ω_test)

    unit = 1000

    ################################################### PARAMETERS ####################################################

    # Get the absolute path of the current file's directory
    current_directory = @__DIR__

    # filename = "random_normal_forecast_data_30_scenarios.xlsx"
    filename = "generated_random_demand_scenarios_100_scenarios.xlsx"

    # Construct the relative path using joinpath
    relative_path = joinpath(current_directory, filename)
    
    # Print the resulting path
    # println("Relative Path: ", relative_path)
    
    random_demand_file = XLSX.readxlsx(relative_path)
    
    total_demand_row = 12+1
    total_demand_col = 10+1
    
    d_real = Dict()
    sheet_names = XLSX.sheetnames(random_demand_file)
    # println(sheet_names)
    for name in first(sheet_names, total_scenarios) #change the number based on scenario numbers
        data = random_demand_file[name]
        ω = findfirst((x -> x==name), sheet_names)
        for row in 2:total_demand_row
            antigen = data[row,1]
            for col in 2:total_demand_col
                year = data[1,col]
                d_real[antigen,parse(Int64, year),ω] = round(data[row,col] / unit, digits=0)
            end
        end
    end

    # Define the file name
    filename2 = "production_capacity_updated.xlsx"

    # Construct the relative path using joinpath
    relative_path2 = joinpath(current_directory, filename2)

    capacity_file = XLSX.readxlsx(relative_path2)

    s_real_raw = capacity_file["Medium_Capacity"]

    total_supply_row = length(P) + 1
    total_supply_col = length(T) + 1
    s_real = Dict()
    for row in 2:total_supply_row
        producer = s_real_raw[row, 1]
        for col in 2:total_supply_col
            year = s_real_raw[1, col]
            if antigen_list_input == "MMR"
                unit_temp = unit * 3
            elseif antigen_list_input == "ALL"
                unit_temp = unit
            end
            if supply_status == "S1"
                s_real[producer, year] = round(0.8 * s_real_raw[row, col] / unit_temp, digits=0)
            elseif supply_status == "S2"
                s_real[producer, year] = round(s_real_raw[row, col] / unit_temp, digits=0)
            elseif supply_status == "S3"
                s_real[producer, year] = round(1.2 * s_real_raw[row, col] / unit_temp, digits=0)
            end
        end
    end
    # println(s_real)

    filename = "Demand_Scenarios_updated.xlsx"

    # Construct the relative path using joinpath
    relative_path = joinpath(current_directory, filename)
    
    # Print the resulting path
    println("Relative Path: ", relative_path)
    
    demand_file = XLSX.readxlsx(relative_path)

    r = Dict()
    for v in V
        vaccine_price_raw = demand_file[string(v, " Pricing")]
        for row in 2:length(P_v[v])+1
            producer = vaccine_price_raw[row, 1]
            for col in 2:length(T)+1
                year = vaccine_price_raw[1, col]
                r[v, producer, year] = vaccine_price_raw[row, col]
            end
        end
    end

    r_avg = Dict()
    for v in V
        for t in T
            total = 0.0
            for p in P_v[v]
                total += r[v, p, t]
            end
            average = total / length(P_v[v])
            r_avg[v, t] = average
        end
    end

    r_producer_avg = Dict()
    for p in P
        total = 0.0
        for v in V_p[p]
            for t in T
                total += r[v, p, t]
            end
        end
        average = total / (length(V_p[p]) * length(T))
        r_producer_avg[p] = average
    end

    # Unvaccinated children penalty
    pi = 10

    # Tender cost
    g = Dict()
    for t in T
        g[t] = 1e8 / unit
    end

    # Inventory holding cost
    h = Dict()
    for v in V
        h[v] = 0.01
    end

    # ROI
    l = Dict()
    for v in V
        for p in P
            l[v, p] = 0.1
        end
    end

    f_profit = Dict()
    for p in P
        for v in V_p[p]
            for t in T
                f_profit[v, p, t] = s_real[p, t] / length(V_p[p]) * r_producer_avg[p] / 2
            end
        end
    end

    beta = 0.1
    γ = 0.1

    F_time_set = []
    for t in T
        for tau in T
            if tau >= t
                if (tau - t + 1) in Δ
                    push!(F_time_set, (t, tau))
                end
            end
        end
    end

    X_tilde_lower = Dict()
    X_tilde_upper = Dict()
    for v in V
        for p in P_v[v]
            for t in T
                for tau in T
                    if (t, tau) in F_time_set
                        X_tilde_lower[v, p, (t, tau)] = 0
                        X_tilde_upper[v, p, (t, tau)] = sum(s_real[p, l] for l in t:tau)
                    end
                end
            end
        end
    end

    # Γ is the cost of expanding capacity by 20% for producer p
    Γ = Dict()
    for p in P
        Γ[p] = 1e8 / unit
    end

    # κ is the allowable capacity increase in a period
    κ = 0.1

    inf_penalty = 100
    
    function deterministic_equivalent(p_ω,Ω)

        model = Model(gurobi_solver)

        @variable(model, F[a in A, (t, tau) in F_time_set], Bin)
        @variable(model, Q[v in V, p in P_v[v], (t, tau) in F_time_set] >= 0)
        @variable(model, X[v in V, p in P_v[v], t in T, ω in Ω] >= 0)
        @variable(model, X_tilde[v in V, p in P_v[v], (t, tau) in F_time_set, ω in Ω] >= 0)
        @variable(model, K[v in V, p in P_v[v], (t, tau) in F_time_set, ω in Ω] >= 0)
        @variable(model, Y[p in P, t in T], Bin)
        @variable(model, I[v in V, t in T_initial, ω in Ω] >= 0)
        @variable(model, Vc[v in V, t in T, ω in Ω] >= 0)
        @variable(model, S[a in A, t in T_initial, ω in Ω] >= 0)
        @variable(model, W[p in P, (t, tau) in F_time_set], Bin)
        @variable(model, L[p in P, t in T], Bin)
        @variable(model, X_inf[p in P, t in T, ω in Ω] >= 0)

        ################################################### OBJECTIVE FUNCTION AND CONSTRAINTS ####################################################
        if capacity_extension_decision
            @objective(model, Min, sum(g[t] * F[a, (t, tau)] for (t, tau) in F_time_set, a in A)
                                   + sum(p_ω[ω] * r[v, p, t] * X[v, p, t, ω] for v in V, p in P_v[v], t in T, ω in Ω)
                                   + sum(p_ω[ω] * pi * S[a, t, ω] for a in A, t in T, ω in Ω)
                                   + sum(p_ω[ω] * h[v] * r_avg[v, t] * I[v, t, ω] for v in V, t in T, ω in Ω)
                                   + sum(Γ[p] * L[p, t] for p in P, t in T)
                                   + sum(inf_penalty * X_inf[p, t, ω] for p in P, t in T, ω in Ω)
            )
        else
            @objective(model, Min, sum(g[t] * F[a, (t, tau)] for (t, tau) in F_time_set, a in A)
                                   + sum(p_ω[ω] * r[v, p, t] * X[v, p, t, ω] for v in V, p in P_v[v], t in T, ω in Ω)
                                   + sum(p_ω[ω] * pi * S[a, t, ω] for a in A, t in T, ω in Ω)
                                   + sum(p_ω[ω] * h[v] * r_avg[v, t] * I[v, t, ω] for v in V, t in T, ω in Ω)
                                   + sum(inf_penalty * X_inf[p, t, ω] for p in P, t in T, ω in Ω)
            )
        end


        # Constraint (2)
        for a in A
            for t in T
                for tau in T
                    if (t, tau) in F_time_set
                        @constraint(model, (tau - t + 1) * F[a, (t, tau)] <= sum(Y[p, l] for l in t:tau, p in P_a[a]))
                    end
                end
            end
        end

        if overlap_decision
            # Constraint (3)
            for a in A
                for t in T
                    for tau in T
                        if tau >= t
                            for t_prime in T
                                for tau_prime in T
                                    if tau_prime >= t_prime
                                        overlap_decision = (t == t_prime)
                                        if overlap_decision == true
                                            if ((t, tau) in F_time_set) && ((t_prime, tau_prime) in F_time_set) && ((t, tau) != (t_prime, tau_prime))
                                                @constraint(model, F[a, (t, tau)] + F[a, (t_prime, tau_prime)] <= 1)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            # Constraint (4) - updated
            for a in A
                for t in T
                    @constraint(model, sum(F[a, (l, k)] for (l, k) in F_time_set if t >= l && t <= k) >= 1)
                end
            end
        else
            # Constraint (3)
            for a in A
                for t in T
                    for tau in T
                        if tau >= t
                            for t_prime in T
                                for tau_prime in T
                                    if tau_prime >= t_prime
                                        overlap_decision = ((t_prime < t) && (tau_prime < t)) || ((t_prime > tau) && (tau_prime > tau)) || ((t == t_prime) && (tau == tau_prime))
                                        if overlap_decision == false
                                            if ((t, tau) in F_time_set) && ((t_prime, tau_prime) in F_time_set)
                                                @constraint(model, F[a, (t, tau)] + F[a, (t_prime, tau_prime)] <= 1)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            # Constraint (4)
            for a in A
                @constraint(model, sum((k - l + 1) * F[a, (l, k)] for (l, k) in F_time_set) >= tmax)
            end
        end

        # Constraint (5)
        for p in P
            for t in T
                for tau in T
                    if (t, tau) in F_time_set
                        @constraint(model, sum(F[a, (t, tau)] for a in A_p[p]) >= W[p, (t, tau)])
                    end
                end
            end
        end

        # Constraint (6)
        for p in P
            for t in T
                for tau in T
                    if (t, tau) in F_time_set
                        @constraint(model, sum(F[a, (t, tau)] for a in A_p[p]) <= length(A_p) * W[p, (t, tau)])
                    end
                end
            end
        end

        if capacity_extension_decision
            # Constraint (7)
            for p in P
                for t in T
                    for tau in T
                        if (t, tau) in F_time_set
                            @constraint(model, sum(Q[v, p, (t, tau)] for v in V_p[p]) <= W[p, (t, tau)] * sum((s_real[p, l] + sum(s_real[p, k] * κ * L[p, k] for k in 1:l)) for l in t:tau))
                        end
                    end
                end
            end
            # Constraint (9)
            for ω in Ω
                for p in P
                    for t in T
                        @constraint(model, sum(X[v, p, t, ω] for v in V_p[p]) <= Y[p, t] * (s_real[p, t] + sum(s_real[p, l] * κ * L[p, l] for l in 1:t)))
                    end
                end
            end
        else
            # Constraint (7)
            for p in P
                for t in T
                    for tau in T
                        if (t, tau) in F_time_set
                            @constraint(model, sum(Q[v, p, (t, tau)] for v in V_p[p]) <= W[p, (t, tau)] * sum(s_real[p, l] for l in t:tau))
                        end
                    end
                end
            end
            # Constraint (9)
            for ω in Ω
                for p in P
                    for t in T
                        @constraint(model, sum(X[v, p, t, ω] for v in V_p[p]) <= s_real[p, t] * Y[p, t])
                    end
                end
            end
        end

        # Constraint (8) - McCormick_1
        for ω in Ω
            for v in V
                for p in P_v[v]
                    for t in T
                        for tau in T
                            if (t, tau) in F_time_set
                                @constraint(model, X_tilde[v, p, (t, tau), ω] == sum(X[v, p, l, ω] for l in t:tau))
                            end
                        end
                    end
                end
            end
        end

        # Constraint (8) - McCormick_2
        for ω in Ω
            for v in V
                for p in P_v[v]
                    for t in T
                        for tau in T
                            if (t, tau) in F_time_set
                                @constraint(model, Q[v, p, (t, tau)] >= K[v, p, (t, tau), ω])
                            end
                        end
                    end
                end
            end
        end

        # Constraint (8) - McCormick_3
        for ω in Ω
            for v in V
                for p in P_v[v]
                    for t in T
                        for tau in T
                            if (t, tau) in F_time_set
                                @constraint(model, K[v, p, (t, tau), ω] >= X_tilde_upper[v, p, (t, tau)] * W[p, (t, tau)] + X_tilde[v, p, (t, tau), ω] - X_tilde_upper[v, p, (t, tau)])
                                @constraint(model, K[v, p, (t, tau), ω] <= X_tilde[v, p, (t, tau), ω])
                                @constraint(model, K[v, p, (t, tau), ω] <= X_tilde_upper[v, p, (t, tau)] * W[p, (t, tau)])
                            end
                        end
                    end
                end
            end
        end

        # Constraint (10)
        for ω in Ω
            for v in V
                for t in T
                    if t >= tmin
                        @constraint(model, I[v, t-1, ω] + sum(X[v, p, t, ω] for p in P_v[v]) == Vc[v, t, ω] + I[v, t, ω])
                    end
                end
            end
        end

        # Constraint (11)
        for ω in Ω
            for a in A
                for t in T
                    if t >= tmin
                        @constraint(model, d_real[a, t, ω] - sum(Vc[v, t, ω] for v in V_a[a]) + S[a, t-1, ω] <= S[a, t, ω])
                    end
                end
            end
        end

        # Constraint (12)
        for ω in Ω
            for p in P
                for t in T
                    @constraint(model, sum(r[v, p, t] * X[v, p, t, ω] for v in V_p[p]) + X_inf[p, t, ω] >= Y[p, t] * sum((1 + l[v, p]) * f_profit[v, p, t] for v in V_p[p]))
                end
            end
        end

        # Constraint (13)
        for ω in Ω
            for v in V
                @constraint(model, I[v, 0, ω] == 0)
            end
        end

        optimize!(model)

        return model
    end
    
    # println(p_ω_test)
    # println(Ω_test)
    # deterministic_equivalent_model = deterministic_equivalent(p_ω_test,Ω_test)
    # optimize!(deterministic_equivalent_model)

    # deterministic_equivalent_obj = JuMP.objective_value(deterministic_equivalent_model)
    # deterministic_equivalent_run_time = JuMP.solve_time(deterministic_equivalent_model)
    # println("deterministic_equivalent_obj")
    # println(deterministic_equivalent_obj)
    # println("deterministic_equivalent_run_time")
    # println(deterministic_equivalent_run_time)

    F_warm = Dict()
    Y_warm = Dict()
    W_warm = Dict()
    Q_warm = Dict()

    for ω in Ω_train
        p_ω_temp = Dict()
        p_ω_temp[ω] = 1.0
        Ω_temp = [ω]
        # println(Ω_temp)
        deterministic_equivalent_model_temp = deterministic_equivalent(p_ω_temp,Ω_temp)
        optimize!(deterministic_equivalent_model_temp)

        F_warm_temp = JuMP.value.(deterministic_equivalent_model_temp[:F])
        Y_warm_temp = JuMP.value.(deterministic_equivalent_model_temp[:Y])
        W_warm_temp = JuMP.value.(deterministic_equivalent_model_temp[:W])
        Q_warm_temp = JuMP.value.(deterministic_equivalent_model_temp[:Q])

        deterministic_equivalent_obj_temp = JuMP.objective_value(deterministic_equivalent_model_temp)
        println("ω: $ω")
        println("deterministic_equivalent_obj_temp: $deterministic_equivalent_obj_temp")

        # prevents rounding issues for F
        for a in A
            for t in T
                for tau in T
                    if (t, tau) in F_time_set
                        F_warm_temp[a,(t,tau)] = round(F_warm_temp[a,(t,tau)], digits = 0)
                    end
                end
            end
        end

        F_warm[ω] = F_warm_temp
        Y_warm[ω] = Y_warm_temp
        W_warm[ω] = W_warm_temp
        Q_warm[ω] = Q_warm_temp
    end
    
    cuts_dict = Dict()
    function master_problem(dual_subproblem, initial_cuts_status, ω_train)

        if length(dual_subproblem) > 0

            cons_omega_dict = Dict()

            for ω in Ω_test
                cons8_b_By_omega = []
                cons9_b_By_omega = []
                cons10_b_By_omega = []
                cons11_b_By_omega = []
                cons12_b_By_omega = []

                # Constraint (8)
                for v in V
                    for p in P_v[v]
                        for t in T
                            for tau in T
                                if (t, tau) in F_time_set
                                    push!(cons8_b_By_omega, -Q[v, p, (t, tau)])
                                end
                            end
                        end
                    end
                end

                # Constraint (9)
                for p in P
                    for t in T
                        c = Y[p, t] * s_real[p, t]
                        # c = Y[p, t] * (s_real[p, t] + sum(s_real[p, l] * κ * L[p, l] for l in 1:t))
                        push!(cons9_b_By_omega, c)
                    end
                end

                # Constraint (10)
                for v in V
                    for t in T
                        if t >= tmin
                            c = 0.0
                            push!(cons10_b_By_omega, c)
                        end
                    end
                end

                # Constraint (11)
                for a in A
                    for t in T
                        if t >= tmin
                            c = -d_real[a, t, ω]
                            push!(cons11_b_By_omega, c)
                        end
                    end
                end

                # Constraint (12)
                for p in P
                    for t in T
                        c = Y[p, t] * sum((1 + l[v, p]) * f_profit[v, p, t] for v in V_p[p])
                        push!(cons12_b_By_omega, c)
                    end
                end

                b_By_omega = [cons8_b_By_omega, cons9_b_By_omega, cons10_b_By_omega, cons11_b_By_omega, cons12_b_By_omega]
                cons_omega_dict[ω] = b_By_omega
                # optimality cut 
                theta_rhs = 0.0
                for i in 1:length(cons_omega_dict[ω])
                    theta_rhs += (transpose(cons_omega_dict[ω][i]) * dual_subproblem[ω][i])
                end

                # println("optimality_cut")
                if initial_cuts_status
                    cuts_dict[Symbol("cut_$(ω_train)_$(ω)")] = @constraint(Masterproblem, theta[ω] >= theta_rhs)
                    # println(cuts_dict[Symbol("cut_$(ω_train)_$(ω)")])
                else
                    @constraint(Masterproblem, theta[ω] >= theta_rhs)
                end
            end
        end

        return Masterproblem
    end

    function sub_problem(F_bar, W_bar, Y_bar, Q_bar, ω)

        Subproblem = JuMP.Model()
        JuMP.set_optimizer(Subproblem, gurobi_solver_no_presolve)

        @variable(Subproblem, X[v in V, p in P_v[v], t in T] >= 0)
        @variable(Subproblem, I[v in V, t in T_initial] >= 0)
        @variable(Subproblem, Vc[v in V, t in T] >= 0)
        @variable(Subproblem, S[a in A, t in T_initial] >= 0)
        @variable(Subproblem, X_inf[p in P, t in T] >= 0)

        inf_penalty = 100

        @objective(Subproblem, Min, sum(r[v, p, t] * X[v, p, t] for v in V, p in P_v[v], t in T)
                                    + sum(pi * S[a, t] for a in A, t in T)
                                    + sum(h[v] * r_avg[v, t] * I[v, t] for v in V, t in T)
                                    + sum(inf_penalty * X_inf[p, t] for p in P, t in T)
        )

        cons_8 = []
        cons_9 = []
        cons_10 = []
        cons_11 = []
        cons_12 = []

        # constraint 8 - before McCormick
        for v in V
            for p in P_v[v]
                for t in T
                    for tau in T
                        if (t, tau) in F_time_set
                            c = @constraint(Subproblem, Q_bar[v, p, (t, tau)] >= W_bar[p, (t, tau)] * sum(X[v, p, l] for l in t:tau))
                            set_name(c, "c_8[$((v,p,(t,tau)))]")
                            push!(cons_8, c)
                        end
                    end
                end
            end
        end

        # Constraint (9)
        for p in P
            for t in T
                if Y_bar[p, t] * s_real[p, t] < 0.1
                    c = @constraint(Subproblem, sum(X[v, p, t] for v in V_p[p]) <= round(Y_bar[p, t] * s_real[p, t], digits=0))
                else
                    c = @constraint(Subproblem, sum(X[v, p, t] for v in V_p[p]) <= Y_bar[p, t] * s_real[p, t])
                end
                set_name(c, "c_9[$((p,t))]")
                push!(cons_9, c)
            end
        end

        # Constraint (10)
        for v in V
            for t in T
                if t >= tmin
                    c = @constraint(Subproblem, I[v, t-1] + sum(X[v, p, t] for p in P_v[v]) == Vc[v, t] + I[v, t])
                    set_name(c, "c_10[$((v,t))]")
                    push!(cons_10, c)
                end
            end
        end

        # Constraint (11)
        for a in A
            for t in T
                if t >= tmin
                    c = @constraint(Subproblem, d_real[a, t, ω] - sum(Vc[v, t] for v in V_a[a]) + S[a, t-1] <= S[a, t])
                    set_name(c, "c_11[$((a,t))]")
                    push!(cons_11, c)
                end
            end
        end

        # Constraint (12)
        for p in P
            for t in T
                c = @constraint(Subproblem, sum(r[v, p, t] * X[v, p, t] for v in V_p[p]) + X_inf[p, t] >= Y_bar[p, t] * sum((1 + l[v, p]) * f_profit[v, p, t] for v in V_p[p]))
                set_name(c, "c_12[$((p,t))]")
                push!(cons_12, c)
            end
        end

        # Constraint (13)
        for v in V
            @constraint(Subproblem, I[v, 0] == 0)
        end

        return Subproblem, cons_8, cons_9, cons_10, cons_11, cons_12
    end

    start_time = time()

    ######### Initiate the Master problem #########
    Masterproblem = JuMP.Model()
    JuMP.set_optimizer(Masterproblem, gurobi_solver)

    @variable(Masterproblem, F[a in A, (t, tau) in F_time_set], Bin)
    @variable(Masterproblem, Q[v in V, p in P_v[v], (t, tau) in F_time_set] >= 0)
    @variable(Masterproblem, 0.0 <= Y[p in P, t in T] <= 1.0)
    @variable(Masterproblem, 0.0 <= W[p in P, (t, tau) in F_time_set] <= 1.0)
    # @variable(Masterproblem, Y[p in P, t in T], Bin)
    # @variable(Masterproblem, W[p in P, (t, tau) in F_time_set], Bin)
    # @variable(Masterproblem, L[p in P, t in T], Bin)
    @variable(Masterproblem, theta[ω in Ω_test] >= 0)
    # @variable(Masterproblem, W_mc[p in P, (t, tau) in F_time_set] >= 0)
    @variable(Masterproblem, X[v in V, p in P_v[v], t in T, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, X_tilde[v in V, p in P_v[v], (t,tau) in F_time_set, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, K[v in V, p in P_v[v], (t,tau) in F_time_set, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, I[v in V, t in T_initial, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, Vc[v in V, t in T, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, S[a in A, t in T_initial, ω in Ω_test_partial_1] >= 0)
    @variable(Masterproblem, X_inf[p in P, t in T, ω in Ω_test_partial_1] >= 0)

    ################################################### MASTER PROBLEM ####################################################

    @objective(Masterproblem, Min, sum(g[t] * F[a, (t, tau)] for (t, tau) in F_time_set, a in A)
                                   #    + sum(Γ[p] * L[p, t] for p in P, t in T)
                                   + sum(p_ω_test[ω]*theta[ω] for ω in Ω_test)
                                   + sum(r[v,p,t] * X[v,p,t,ω] for v in V, p in P_v[v], t in T, ω in Ω_test_partial_1)
                                   + sum(pi * S[a,t,ω] for a in A, t in T, ω in Ω_test_partial_1)
                                   + sum(h[v] * r_avg[v,t] * I[v,t,ω] for v in V, t in T, ω in Ω_test_partial_1)
                                   + sum(inf_penalty * X_inf[p,t,ω] for p in P, t in T, ω in Ω_test_partial_1)
    )
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

    # Constraint (3)
    for a in A
        for t in T
            for tau in T
                if tau >= t
                    for t_prime in T
                        for tau_prime in T
                            if tau_prime >= t_prime
                                overlap_decision = (t == t_prime)
                                if overlap_decision == true
                                    if ((t, tau) in F_time_set) && ((t_prime, tau_prime) in F_time_set) && ((t, tau) != (t_prime, tau_prime))
                                        @constraint(Masterproblem, F[a, (t, tau)] + F[a, (t_prime, tau_prime)] <= 1)
                                    end
                                end
                            end
                        end
                    end
                end
            end
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

    # Constraint (6)
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(Masterproblem, sum(F[a, (t, tau)] for a in A_p[p]) <= length(A_p) * W[p, (t, tau)])
                end
            end
        end
    end

    # Constraint (7)
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(Masterproblem, sum(Q[v, p, (t, tau)] for v in V_p[p]) <= W[p, (t, tau)] * sum(s_real[p, l] for l in t:tau))
                end
            end
        end
    end

    #Constraint (Valid Inequality 2)
    for p in P
        for t in T
            for tau in T
                if (t, tau) in F_time_set
                    @constraint(Masterproblem, sum(Q[v, p, (t, tau)] for v in V_p[p]) <= sum((Y[p,l] * s_real[p, l]) for l in t:tau))
                end
            end
        end
    end

    # Constraint (8) - McCormick_1
    for ω in Ω_test_partial_1
        for v in V
            for p in P_v[v]
                for t in T
                    for tau in T
                        if (t,tau) in F_time_set
                            @constraint(Masterproblem, X_tilde[v,p,(t,tau),ω] == sum(X[v,p,l,ω] for l in t:tau))
                        end
                    end
                end
            end
        end
    end
    
    # Constraint (8) - McCormick_2
    for ω in Ω_test_partial_1
        for v in V
            for p in P_v[v]
                for t in T
                    for tau in T
                        if (t,tau) in F_time_set
                            @constraint(Masterproblem, Q[v,p,(t,tau)] >= K[v,p,(t,tau),ω])
                        end
                    end
                end
            end
        end
    end
    
    # Constraint (8) - McCormick_3
    for ω in Ω_test_partial_1
        for v in V
            for p in P_v[v]
                for t in T
                    for tau in T
                        if (t,tau) in F_time_set
                            @constraint(Masterproblem, K[v,p,(t,tau),ω] >= X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)] + X_tilde[v,p,(t,tau),ω] - X_tilde_upper[v,p,(t,tau)])
                            @constraint(Masterproblem, K[v,p,(t,tau),ω] <= X_tilde[v,p,(t,tau),ω])
                            @constraint(Masterproblem, K[v,p,(t,tau),ω] <= X_tilde_upper[v,p,(t,tau)]*W[p,(t,tau)])
                        end
                    end
                end
            end
        end
    end

    # Constraint (9)
    for ω in Ω_test_partial_1
        for p in P
            for t in T
                @constraint(Masterproblem, sum(X[v,p,t,ω] for v in V_p[p]) <= s_real[p,t]*Y[p,t])
            end
        end
    end

    # Constraint (10)
    for ω in Ω_test_partial_1
        for v in V
            for t in T
                if t >= tmin
                    @constraint(Masterproblem, I[v,t-1,ω] + sum(X[v,p,t,ω] for p in P_v[v]) == Vc[v,t,ω] + I[v,t,ω])
                end
            end
        end
    end

    # Constraint (11)
    for ω in Ω_test_partial_1
        for a in A
            for t in T
                if t >= tmin
                    @constraint(Masterproblem, d_real[a,t,ω] - sum(Vc[v,t,ω] for v in V_a[a]) + S[a,t-1,ω] <= S[a,t,ω])
                end
            end
        end
    end

    # Constraint (12)
    for ω in Ω_test_partial_1
        for p in P
            for t in T
                @constraint(Masterproblem, sum(r[v,p,t]*X[v,p,t,ω] for v in V_p[p]) + X_inf[p,t,ω] >= Y[p,t] * sum((1+l[v,p])*f_profit[v,p,t] for v in V_p[p]))
            end
        end
    end

    # Constraint (13)
    for ω in Ω_test_partial_1
        for v in V
            @constraint(Masterproblem, I[v,0,ω] == 0)
        end
    end

    LB = 0
    UB = 1e30

    tol = 1e-2
    relaxation_tol = 5e-2
    global iter = 1
    iter_max = 5000
    rel_change_iter = 0

    theta_rhs = 0.0
    Z_M = 0.0
    Z_M_prev = 0.0
    dual_subproblem = []
    cut = nothing
    lb_vector = []
    ub_vector = []
    lb_and_ub_vectors = Dict()
    opt_cut_list = Vector{Any}()
    count = 1

    initial_cuts_status = true

    # add initial cuts before starting L-shaped method
    
    for ω_train in Ω_train
        dual_subproblem_temp = Dict()
        F_warm_temp = F_warm[ω_train]
        W_warm_temp = W_warm[ω_train]
        Y_warm_temp = Y_warm[ω_train]
        Q_warm_temp = Q_warm[ω_train]
        for ω in Ω_test
            Subproblem, cons_8, cons_9, cons_10, cons_11, cons_12 = sub_problem(F_warm_temp, W_warm_temp, Y_warm_temp, Q_warm_temp, ω)
            optimize!(Subproblem)
    
            constr8 = JuMP.dual.(cons_8)
            constr9 = JuMP.dual.(cons_9)
            constr10 = JuMP.dual.(cons_10)
            constr11 = JuMP.dual.(cons_11)
            constr12 = JuMP.dual.(cons_12)
    
            dual_vector_omega = [constr8, constr9, constr10, constr11, constr12]
            dual_subproblem_temp[ω] = dual_vector_omega
        end
        Masterproblem = master_problem(dual_subproblem_temp, initial_cuts_status, ω_train)
    end

    JuMP.optimize!(Masterproblem)

    cons_report = Dict()
    function constraint_report(c::ConstraintRef, cons_name)
        return (
            # name = name(c),
            # value = value(c),
            # rhs = normalized_rhs(c),
            # slack = normalized_rhs(c) - value(c),
            cons_report[cons_name] = normalized_rhs(c) - value(c)
        )
    end

    # constraints_to_delete = []

    # for ω_train in Ω_train
    #     for ω_test in Ω_test
    #         c_report = constraint_report(cuts_dict[Symbol("cut_$(ω_train)_$(ω_test)")], "cut_$(ω_train)_$(ω_test)")
    #         slack_temp = abs(round(cons_report["cut_$(ω_train)_$(ω_test)"], digits=0))
    #         if slack_temp == 0.0
    #             println("$ω_train,$ω_test")
    #             println(slack_temp)
    #         else
    #             # println("delete: cut_$(ω_train)_$(ω_test)")
    #             push!(constraints_to_delete, "cut_$(ω_train)_$(ω_test)")
    #         end
    #     end
    # end

    # for constraints in constraints_to_delete
    #     delete(Masterproblem, cuts_dict[Symbol(constraints)])
    # end
    
    # L-shaped method starts
    while iter <= iter_max
        initial_cuts_status = false
        println("iter: $iter")
        redundant_ω_train = 1
        Masterproblem = master_problem(dual_subproblem, initial_cuts_status, redundant_ω_train)
        # println(Masterproblem)
        JuMP.optimize!(Masterproblem)

        if length(opt_cut_list) > 2
            popfirst!(opt_cut_list)
            if opt_cut_list[1] == opt_cut_list[2]
                break
            end
        end

        if primal_status(Masterproblem) == MOI.NO_SOLUTION
            compute_conflict!(Masterproblem)
            iis_model, _ = copy_conflict(Masterproblem)
            println("MASTER_INFEASIBLE")
            print(iis_model)
        end

        X_bar = JuMP.value.(Masterproblem[:X])
        S_bar = JuMP.value.(Masterproblem[:S])
        I_bar = JuMP.value.(Masterproblem[:I])
        X_inf_bar = JuMP.value.(Masterproblem[:X_inf])

        additional_cost_MP = 0.0
        for v in V
            for p in P_v[v]
                for t in T
                    for ω in Ω_test_partial_1
                        additional_cost_MP += r[v,p,t] * X_bar[v,p,t,ω]
                    end
                end
            end
        end

        for a in A
            for t in T
                for ω in Ω_test_partial_1
                    additional_cost_MP += pi * S_bar[a,t,ω]
                end
            end
        end

        for v in V
            for t in T
                for ω in Ω_test_partial_1
                    additional_cost_MP += h[v] * r_avg[v,t] * I_bar[v,t,ω]
                end
            end
        end

        for p in P
            for t in T
                for ω in Ω_test_partial_1
                    additional_cost_MP += inf_penalty * X_inf_bar[p,t,ω]
                end
            end
        end
        
        Z_M = JuMP.objective_value(Masterproblem) - additional_cost_MP

        println("additional_cost_MP")
        println(additional_cost_MP)
        println("Z_M")
        println(Z_M)
        
        # cons_report = Dict()
        # for ω_train in Ω_train
        #     for ω_test in Ω_test
        #         c_report = constraint_report(cuts_dict[Symbol("cut_$(ω_train)_$(ω_test)")],"cut_$(ω_train)_$(ω_test)")
        #         slack_temp = abs(round(cons_report["cut_$(ω_train)_$(ω_test)"], digits= 0))
        #         if slack_temp == 0.0
        #             println("$ω_train,$ω_test")
        #             println(slack_temp)
        #         end
        #     end
        # end
        
        # println("Theta: $(JuMP.value.(Masterproblem[:theta]))")
        global F_bar = JuMP.value.(Masterproblem[:F])
        global W_bar = JuMP.value.(Masterproblem[:W])
        global Y_bar = JuMP.value.(Masterproblem[:Y])
        global Q_bar = JuMP.value.(Masterproblem[:Q])

        if iter == 1
            # @constraint(Masterproblem, obj_lb, Z_M <= objective_function(Masterproblem))
            global obj_lb = @constraint(Masterproblem, objective_function(Masterproblem) 
                                                        - sum(r[v,p,t] * Masterproblem[:X][v,p,t,ω] for v in V, p in P_v[v], t in T, ω in Ω_test_partial_1)
                                                        - sum(pi * Masterproblem[:S][a,t,ω] for a in A, t in T, ω in Ω_test_partial_1)
                                                        - sum(h[v] * r_avg[v,t] * Masterproblem[:I][v,t,ω] for v in V, t in T, ω in Ω_test_partial_1)
                                                        - sum(inf_penalty * Masterproblem[:X_inf][p,t,ω] for p in P, t in T, ω in Ω_test_partial_1)
                                                            >= Z_M)
            Z_M_prev = Z_M
        else
            if Z_M >= Z_M_prev
                set_normalized_rhs(obj_lb, Z_M)
                # println(obj_lb)
                Z_M_prev = Z_M
            else
                set_normalized_rhs(obj_lb, Z_M_prev)
            end
        end

        Z_S_omega = Dict()
        dual_subproblem = Dict()
        for ω in Ω_test
            # println("scenario: $ω")
            Subproblem, cons_8, cons_9, cons_10, cons_11, cons_12 = sub_problem(F_bar, W_bar, Y_bar, Q_bar, ω)
            optimize!(Subproblem)

            if primal_status(Subproblem) == MOI.NO_SOLUTION
                println(Q_bar)
                compute_conflict!(Subproblem)
                iis_model, _ = copy_conflict(Subproblem)
                println("SUBPROBLEM_INFEASIBLE")
                # print(iis_model)
                println(Subproblem)
            end

            constr8 = JuMP.dual.(cons_8)
            constr9 = JuMP.dual.(cons_9)
            constr10 = JuMP.dual.(cons_10)
            constr11 = JuMP.dual.(cons_11)
            constr12 = JuMP.dual.(cons_12)

            dual_vector_omega = [constr8, constr9, constr10, constr11, constr12]
            dual_subproblem[ω] = dual_vector_omega
            Z_S_omega[ω] = JuMP.objective_value(Subproblem)
        end

        # update UB
        Z_S_expected = sum(p_ω_test[ω] * Z_S_omega[ω] for ω in Ω_test)
        # println("Z_S_expected")
        # println(Z_S_expected)

        theta_total = 0.0
        for ω in Ω_test
            theta_total += p_ω_test[ω] * JuMP.value.(Masterproblem[:theta][ω])
        end

        # println("theta_total")
        # println(theta_total)

        if iter == rel_change_iter + 1
            UB = Z_M - theta_total + Z_S_expected
        end

        if Z_M - theta_total + Z_S_expected < UB
            UB = Z_M - theta_total + Z_S_expected
        end
        push!(lb_vector, Z_M)
        push!(ub_vector, UB)

        if iter % 10 == 0
            time_elapsed = time() - start_time
            lb_and_ub_vectors["lb"] = lb_vector
            lb_and_ub_vectors["ub"] = ub_vector
            lb_and_ub_vectors["run_time"] = time_elapsed
            current_directory = @__DIR__
            source_2 = string(current_directory, "/test_graph_T_", tmax, antigen_list_check, "_method_1_only_F_relaxed_stochastic_disaggregated.json")
            f = open(source_2, "w")
            JSON.print(f, lb_and_ub_vectors)
            close(f)
            # sleep(2)
        end

        LB = Z_M

        println("LB: $LB")
        println("UB: $UB")

        if (UB - LB) / UB < relaxation_tol
            ###### undo() converts the relaxation MP to original MP by keeping all the optimality cuts added.
            if relaxation_decision == true
                # undo()

                for p in P
                    for t in T
                        delete_lower_bound(Y[p, t])
                        delete_upper_bound(Y[p, t])
                        set_binary(Y[p, t])
                    end
                end

                for p in P
                    for t in T
                        for tau in T
                            if (t, tau) in F_time_set
                                delete_lower_bound(W[p, (t, tau)])
                                delete_upper_bound(W[p, (t, tau)])
                                set_binary(W[p, (t, tau)])
                            end
                        end
                    end
                end

                relaxation_decision = false
                println("RELAXATION CHANGE")
                rel_change_iter = iter

                break
            end
            if (UB - LB) / UB < tol
                time_elapsed = time() - start_time
                lb_and_ub_vectors["lb"] = lb_vector
                lb_and_ub_vectors["ub"] = ub_vector
                lb_and_ub_vectors["run_time"] = time_elapsed
                current_directory = @__DIR__
                source_2 = string(current_directory, "/test_graph_T_", tmax, antigen_list_check, "_method_1_only_F_relaxed_stochastic_disaggregated.json")
                f = open(source_2, "w")
                JSON.print(f, lb_and_ub_vectors)
                close(f)
                println("DONE")
                end_time = time()
                println("L-shaped run time: $(end_time-start_time)")

                # println("deterministic_equivalent_obj: $deterministic_equivalent_obj")
                # println("deterministic_equivalent_run_time: $deterministic_equivalent_run_time")
                break
            end
        end

        iter += 1
        if iter == iter_max
            end_time = time()
            println("L-shaped run time: $(end_time-start_time)")
        end
    end
    
end
