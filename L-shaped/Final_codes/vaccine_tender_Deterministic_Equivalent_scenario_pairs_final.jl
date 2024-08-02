using JuMP
using Gurobi
using Random
using Dualization
using Plots
using DataFrames
using CSV
import XLSX
import JSON

gurobi_solver_DE = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "FeasibilityTol" => 1e-4, "OutputFlag" => 1, "Presolve" => 1, "NumericFocus" => 1, "MIPGap" => 1e-3, "Threads" => 8) 

# max_horizon_length => represents T => Integer number 
# max_tender_length => Δ ∈ {3,5,7}
# number_of_demand_scenarios => Number of demand scenarios. Integer number. We pair each demand scenario (N) with capacity scenarios (M). We obtain NxM scenarios in total.
# total_capacity_scenarios => Number of capacity scenarios. Integer number. We pair each demand scenario (N) with capacity scenarios (M). We obtain NxM scenarios in total.
# number_of_trials => to run the experiment multiple times. Integer number
# initial_inventory_rate => base value is 1, which represents half year demand (inventory level) for each vaccine. If selected as 2, it gives around one full year demand (inventory level) for each vaccine
# scaled_capacity => base value is 1. For the scaled_capacity effect, 1.5 should be input.
# allowable_capacity_increase_number => Default value is 5 meaning that a producer can increase its capacity by 50% (5x10%) in a year. It can be selected as allowable_capacity_increase_number ∈ {1,2,3,4,5}

# tender_stochastic_sensitivity(10,5,2,2,1,1,1,5)
function tender_stochastic_sensitivity(max_horizon_length,max_tender_length,number_of_demand_scenarios,total_capacity_scenarios,number_of_trials,initial_inventory_rate,scaled_capacity,allowable_capacity_increase_number)

    DE_output = Dict()
    Scenarios_used = Dict()

    for trial in 1:number_of_trials
        println("trial: $trial")

        overlap_decision = true
        capacity_extension_decision = true

        ################################################### INDICES ####################################################
        A = ["Measles", "Mumps", "Rubella", "Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio", "HPV", "Rotavirus", "PCV"]
        V = ["M", "MR", "MMR", "TT", "HepB", "Hib", "IPV", "OPV", "DT", "Td", "DTwP", "DTwP-Hib", "Penta", "Hexa", "HPV", "Rotavirus", "PCV"]
        A_v = Dict("M" => ["Measles"], "MR" => ["Measles", "Rubella"], "MMR" => ["Measles", "Mumps", "Rubella"], "TT" => ["Tetanus"], "HepB" => ["Hepatitis_B"], "Hib" => ["Hib"], "IPV" => ["Polio"],
            "OPV" => ["Polio"], "DT" => ["Diphtheria", "Tetanus"], "Td" => ["Diphtheria", "Tetanus"], "DTwP" => ["Diphtheria", "Tetanus", "Pertussis"],
            "DTwP-Hib" => ["Diphtheria", "Tetanus", "Pertussis", "Hib"], "Penta" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib"],
            "Hexa" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio"], "HPV" => ["HPV"], "Rotavirus" => ["Rotavirus"], "PCV" => ["PCV"])
        P = ["AJ_Vaccines", "BB_NCIPD", "China_National", "Bharat_Biotech", "Bilthoven", "Biological_E", "GSK", "Haffkine_Bio",
            "LG_Chem", "Merck_Sharp", "Panacea_Biotec", "PT_Bio", "Sanofi", "Serum_Institute", "Pfizer"]

        P_v = Dict("M" => ["Serum_Institute", "PT_Bio"], "MR" => ["Serum_Institute", "Biological_E"], "MMR" => ["Serum_Institute", "GSK"],
            "TT" => ["Serum_Institute", "PT_Bio", "BB_NCIPD", "Biological_E"], "HepB" => ["Serum_Institute", "LG_Chem"], "Hib" => ["Serum_Institute"],
            "IPV" => ["LG_Chem", "AJ_Vaccines", "Bilthoven", "Sanofi"],
            "OPV" => ["Serum_Institute", "PT_Bio", "GSK", "Sanofi", "Panacea_Biotec", "China_National", "Bharat_Biotech", "Haffkine_Bio"],
            "DT" => ["PT_Bio", "BB_NCIPD"], "Td" => ["Serum_Institute", "PT_Bio", "BB_NCIPD", "Biological_E"], "DTwP" => ["Serum_Institute", "Biological_E"], "DTwP-Hib" => ["Serum_Institute"],
            "Penta" => ["Serum_Institute", "PT_Bio", "Biological_E", "LG_Chem", "Panacea_Biotec"], "Hexa" => ["Sanofi"],
            "HPV" => ["GSK", "Merck_Sharp", "China_National"], "Rotavirus" => ["Serum_Institute", "GSK", "Bharat_Biotech"], "PCV" => ["Serum_Institute", "GSK", "Pfizer"])

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

        capacity_category = Dict("Small" => ["AJ_Vaccines","Panacea_Biotec","Bilthoven","China_National"],
                                 "Medium" => ["Sanofi","Pfizer","Haffkine_Bio","Bharat_Biotech","Merck_Sharp","PT_Bio","LG_Chem","BB_NCIPD"],
                                 "Large" => ["Serum_Institute","GSK","Biological_E"])
                                
        vaccine_category = Dict("MMR-based" => ["M","MR","MMR"],
                                 "Td-based" => ["TT","HepB","Hib","IPV","OPV","DT","Td","DTwP","DTwP-Hib","Penta","Hexa"],
                                 "Single" => ["HPV","Rotavirus","PCV"])

        antigen_category = Dict("MMR-based" => ["Measles","Mumps","Rubella"],
                                 "Td-based" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio"],
                                 "Single" => ["HPV","Rotavirus","PCV"])

        tmin = 1
        tmax = max_horizon_length
        T = [t for t in tmin:tmax]
        T_initial = [t for t in tmin-1:tmax]
        Δ = [i for i in 1:max_tender_length]

        current_directory = @__DIR__
        source = string(current_directory, "/results/log_DE_L_T_", max_horizon_length, "_delta_", max_tender_length, "_scen_", number_of_demand_scenarios * total_capacity_scenarios, "_trial_", trial, "_inv_", initial_inventory_rate, "_cap._", scaled_capacity, "_cap.inc._", allowable_capacity_increase_number, "_base.json")

        current_directory = @__DIR__
        filename = "data/scenario_pair_probabilities_new_demand_base_capacity_pandemic.json"
        relative_path = joinpath(current_directory, filename)
        scenario_pair_probs = JSON.parsefile(relative_path)

        total_scenarios = length(scenario_pair_probs)

        if !isfile(source)
            function select_random_scenarios(a::Int, b::Int, n::Int)
                numbers = collect(a:b)
                shuffled_numbers = shuffle(numbers)
                selected_numbers = shuffled_numbers[1:n]
                # Make pairs with all the capacity scenarios
                randomly_selected_scenarios = Vector{Int}()
                for i in selected_numbers
                    for j in 1:total_capacity_scenarios
                        push!(randomly_selected_scenarios, (i - 1) * total_capacity_scenarios + j)
                    end
                end
                return randomly_selected_scenarios
            end
            a = 1
            b = ceil(Int, total_scenarios / total_capacity_scenarios)
            n = number_of_demand_scenarios
            random_scenarios = select_random_scenarios(a, b, n)
            println("Selected random scenarios: ", random_scenarios)

            Ω_test = random_scenarios

        else
            println("Use scenarios generated by L-shaped method!")
            current_directory = @__DIR__
            source_2 = string(current_directory, "/results/scenarios_", tmax, "_delta_", max_tender_length, "_scen_", number_of_demand_scenarios * total_capacity_scenarios, "_trial_", trial, "_inv_", initial_inventory_rate, "_cap._", scaled_capacity, "_cap.inc._", allowable_capacity_increase_number, "_base.json")

            Ω_dict = JSON.parsefile(source_2)
            Ω_test = Ω_dict["All"]
        end

        total_probs = 0.0
        for ω in Ω_test
            total_probs += scenario_pair_probs["$ω"]
        end
        p_ω_test = Dict(ω => scenario_pair_probs["$ω"] / total_probs for ω in Ω_test)

        println(p_ω_test)

        unit = 1000

        current_directory = @__DIR__
        filename = "data/scenario_pairs_new_demand_base_capacity_pandemic.json"
        # Construct the relative path using joinpath
        relative_path = joinpath(current_directory, filename)

        scenario_pairs = JSON.parsefile(relative_path)

        # println(scenario_pairs)

        d_real_tilde = Dict()
        s_real_tilde = Dict()

        for ω in Ω_test
            for a in A
                for t in T
                    d_real_tilde[a, t, ω] = round(scenario_pairs["$ω"]["demand"]["$t"]["$a"] / unit, digits=0)
                end
            end
        end

        # println(d_real_tilde)

        for ω in Ω_test
            for p in P
                for t in T
                    s_real_tilde[p, t, ω] = round(scenario_pairs["$ω"]["capacity"]["$t"]["$p"] * scaled_capacity / unit, digits=0)
                end
            end
        end

        # println(s_real_tilde)

        filename2 = "data/production_capacity_scenarios.xlsx"

        # Construct the relative path using joinpath
        relative_path2 = joinpath(current_directory, filename2)

        capacity_file = XLSX.readxlsx(relative_path2)

        s_real_raw = capacity_file["base_capacity"]

        total_supply_row = length(P) + 1
        total_supply_col = 2

        s_real = Dict()

        for row in 2:total_supply_row
            producer = s_real_raw[row, 1]
            for col in 2:total_supply_col
                year = s_real_raw[1, col]
                s_real[producer] = round(s_real_raw[row, col] * scaled_capacity / unit, digits=0)
            end
        end
        # println(s_real)

        current_directory = @__DIR__

        filename = "data/Vaccine_price_data.xlsx"
        relative_path = joinpath(current_directory, filename)
        vaccine_price_file = XLSX.readxlsx(relative_path)

        r = Dict()
        for v in V
            vaccine_price_raw = vaccine_price_file[string(v, " Pricing")]
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
                    f_profit[v, p, t] = s_real[p] / length(V_p[p]) * r_producer_avg[p] / 2
                end
            end
        end

        κ = 0.10
        L_lower_number = 0
        L_upper_number = allowable_capacity_increase_number
        delta = [(1 + 0.03)^t for t in 1:tmax]

        # Γ is the cost of expanding capacity by 20% for producer p
        Γ = Dict()
        for p in P
            Γ[p] = 1e8 / unit
        end

        inf_penalty = 100

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

        current_directory = @__DIR__
        filename = "data/Starting_point.xlsx"
        relative_path = joinpath(current_directory, filename)
        starting_points_file = XLSX.readxlsx(relative_path)

        starting_points_F_raw = starting_points_file["F_start"]
        total_row_F = length(starting_points_F_raw[:, 1])
        starting_points_vect_F = []
        for row in 2:total_row_F
            antigen = starting_points_F_raw[row, 1]
            starting_year = starting_points_F_raw[row, 2]
            ending_year = starting_points_F_raw[row, 3]
            push!(starting_points_vect_F, (antigen, starting_year, ending_year))
        end

        starting_points_I_raw = starting_points_file["I_start"]
        total_row_I = length(starting_points_I_raw[:, 1])
        starting_points_vect_I = []
        for row in 2:total_row_I
            vaccine = starting_points_I_raw[row, 1]
            amount = round(starting_points_I_raw[row, 2] * initial_inventory_rate / unit, digits=0)
            push!(starting_points_vect_I, (vaccine, amount))
        end

        starting_points_S_raw = starting_points_file["S_start"]
        total_row_S = length(starting_points_S_raw[:, 1])
        starting_points_vect_S = []
        for row in 2:total_row_S
            antigen = starting_points_S_raw[row, 1]
            amount = round(starting_points_S_raw[row, 2] / unit, digits=0)
            push!(starting_points_vect_S, (antigen, amount))
        end

        function save_L_shaped_results(F_bar, Y_bar, W_bar, L_bar, Q_bar, X_de, I_de, Vc_de, S_de)
            F_results = Dict()
            for a in A
                temp_1 = Dict()
                for t in T
                    temp_2 = Dict()
                    for tau in T
                        if (t, tau) in F_time_set
                            temp_2[tau] = F_bar[a, (t, tau)]
                        end
                    end
                    temp_1[t] = temp_2
                end
                F_results[a] = temp_1
            end

            Y_results = Dict()
            for p in P
                temp_1 = Dict()
                for t in T
                    temp_1[t] = Y_bar[p, t]
                end
                Y_results[p] = temp_1
            end

            W_results = Dict()
            for p in P
                temp_1 = Dict()
                for t in T
                    temp_2 = Dict()
                    for tau in T
                        if (t, tau) in F_time_set
                            temp_2[tau] = W_bar[p, (t, tau)]
                        end
                    end
                    temp_1[t] = temp_2
                end
                W_results[p] = temp_1
            end

            L_results = Dict()
            for p in P
                temp_1 = Dict()
                for t in T
                    temp_1[t] = L_bar[p, t]
                end
                L_results[p] = temp_1
            end

            Q_results = Dict()
            for v in V
                temp_1 = Dict()
                for p in P_v[v]
                    temp_2 = Dict()
                    for t in T
                        temp_3 = Dict()
                        for tau in T
                            if (t, tau) in F_time_set
                                temp_3[tau] = Q_bar[v, p, (t, tau)]
                            end
                        end
                        temp_2[t] = temp_3
                    end
                    temp_1[p] = temp_2
                end
                Q_results[v] = temp_1
            end

            X_results = Dict()
            for v in V
                temp_1 = Dict()
                for p in P_v[v]
                    temp_2 = Dict()
                    for t in T
                        temp_3 = Dict()
                        for ω in Ω_test
                            temp_3[ω] = X_de[v, p, t, ω]
                        end
                        temp_2[t] = temp_3
                    end
                    temp_1[p] = temp_2
                end
                X_results[v] = temp_1
            end

            I_results = Dict()
            for v in V
                temp_1 = Dict()
                for t in T_initial
                    temp_2 = Dict()
                    for ω in Ω_test
                        temp_2[ω] = I_de[v, t, ω]
                    end
                    temp_1[t] = temp_2
                end
                I_results[v] = temp_1
            end

            Vc_results = Dict()
            for v in V
                temp_1 = Dict()
                for t in T
                    temp_2 = Dict()
                    for ω in Ω_test
                        temp_2[ω] = Vc_de[v, t, ω]
                    end
                    temp_1[t] = temp_2
                end
                Vc_results[v] = temp_1
            end

            S_results = Dict()
            for a in A
                temp_1 = Dict()
                for t in T_initial
                    temp_2 = Dict()
                    for ω in Ω_test
                        temp_2[ω] = S_de[a, t, ω]
                    end
                    temp_1[t] = temp_2
                end
                S_results[a] = temp_1
            end


            DE_output["F"] = F_results
            DE_output["Y"] = Y_results
            DE_output["W"] = W_results
            DE_output["L"] = L_results
            DE_output["Q"] = Q_results
            DE_output["X"] = X_results
            DE_output["I"] = I_results
            DE_output["Vc"] = Vc_results
            DE_output["S"] = S_results

            current_directory = @__DIR__
            source = string(current_directory, "/results/DE_results_T_", tmax, "_delta_", max_tender_length, "_scen_", number_of_demand_scenarios * total_capacity_scenarios, "_trial_", trial, "_inv_", initial_inventory_rate, "_cap._", scaled_capacity, "_cap.inc._", allowable_capacity_increase_number, "_base.json")
            f = open(source, "w")
            JSON.print(f, DE_output)
            close(f)

        end


        function deterministic_equivalent(p_ω, Ω)

            model = Model(gurobi_solver_DE)

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
            @variable(model, L_lower_number <= L[p in P, t in T] <= L_upper_number, Int)
            @variable(model, L_ddot[p in P, t in T] >= 0)
            @variable(model, L_hat[p in P, (t, tau) in F_time_set] >= 0)
            @variable(model, L_check[p in P, (t, tau) in F_time_set] >= 0)
            @variable(model, K_ddot[p in P, t in T] >= 0)
            @variable(model, K_hat[p in P, (t, tau) in F_time_set] >= 0)
            @variable(model, K_check[p in P, (t, tau) in F_time_set] >= 0)
            @variable(model, X_inf[p in P, t in T, ω in Ω] >= 0)

            ################################################### OBJECTIVE FUNCTION AND CONSTRAINTS ####################################################
            if capacity_extension_decision
                @objective(model, Min, sum(g[t] * F[a, (t, tau)] / delta[t] for (t, tau) in F_time_set, a in A if (a, t, tau) ∉ starting_points_vect_F)
                                       + sum(p_ω[ω] * r[v, p, t] * X[v, p, t, ω] / delta[t] for v in V, p in P_v[v], t in T, ω in Ω)
                                       + sum(p_ω[ω] * pi * S[a, t, ω] / delta[t] for a in A, t in T, ω in Ω)
                                       + sum(p_ω[ω] * h[v] * r_avg[v, t] * I[v, t, ω] / delta[t] for v in V, t in T, ω in Ω)
                                       + sum(Γ[p] * L[p, t] / delta[t] for p in P, t in T)
                                       + sum(inf_penalty * X_inf[p, t, ω] / delta[t] for p in P, t in T, ω in Ω)
                )
            else
                @objective(model, Min, sum(g[t] * F[a, (t, tau)] / delta[t] for (t, tau) in F_time_set, a in A if (a, t, tau) ∉ starting_points_vect_F)
                                       + sum(p_ω[ω] * r[v, p, t] * X[v, p, t, ω] / delta[t] for v in V, p in P_v[v], t in T, ω in Ω)
                                       + sum(p_ω[ω] * pi * S[a, t, ω] / delta[t] for a in A, t in T, ω in Ω)
                                       + sum(p_ω[ω] * h[v] * r_avg[v, t] * I[v, t, ω] / delta[t] for v in V, t in T, ω in Ω)
                                       + sum(inf_penalty * X_inf[p, t, ω] / delta[t] for p in P, t in T, ω in Ω)
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
                # for p in P
                #     for t in T
                #         for tau in T
                #             if (t, tau) in F_time_set
                #                 @constraint(model, sum(Q[v, p, (t, tau)] for v in V_p[p]) <= W[p, (t, tau)] * sum((s_real[p] + sum(κ*s_real[p] * L[p, k] for k in 1:l)) for l in t:tau))
                #             end
                #         end
                #     end
                # end
                for p in P
                    for t in T
                        for tau in T
                            if (t, tau) in F_time_set
                                @constraint(model, sum(Q[v, p, (t, tau)] for v in V_p[p]) <= W[p, (t, tau)] * sum(s_real[p] for l in t:tau) + K_hat[p, (t, tau)] + K_check[p, (t, tau)])
                                @constraint(model, L_hat[p, (t, tau)] == sum((tau - l + 1) * κ * s_real[p] * L[p, l] for l in t+1:tau))
                                @constraint(model, K_hat[p, (t, tau)] >= L_hat[p, (t, tau)] + W[p, (t, tau)] * L_hat_upper[p, (t, tau)] - L_hat_upper[p, (t, tau)])
                                @constraint(model, K_hat[p, (t, tau)] <= W[p, (t, tau)] * L_hat_upper[p, (t, tau)])
                                @constraint(model, K_hat[p, (t, tau)] <= L_hat[p, (t, tau)])

                                @constraint(model, L_check[p, (t, tau)] == sum((tau - t + 1) * κ * s_real[p] * L[p, l] for l in 1:t))
                                @constraint(model, K_check[p, (t, tau)] >= L_check[p, (t, tau)] + W[p, (t, tau)] * L_check_upper[p, (t, tau)] - L_check_upper[p, (t, tau)])
                                @constraint(model, K_check[p, (t, tau)] <= W[p, (t, tau)] * L_check_upper[p, (t, tau)])
                                @constraint(model, K_check[p, (t, tau)] <= L_check[p, (t, tau)])
                            end
                        end
                    end
                end
                # Constraint (9)
                # for ω in Ω
                #     for p in P
                #         for t in T
                #             @constraint(model, sum(X[v, p, t, ω] for v in V_p[p]) <= Y[p, t] * (s_real_tilde[p, t, ω] + sum(κ*s_real[p] * L[p, l] for l in 1:t)))
                #         end
                #     end
                # end
                for p in P
                    for t in T
                        @constraint(model, L_ddot[p, t] == sum(κ * s_real[p] * L[p, l] for l in 1:t))
                        @constraint(model, K_ddot[p, t] >= L_ddot[p, t] + Y[p, t] * L_ddot_upper[p, t] - L_ddot_upper[p, t])
                        @constraint(model, K_ddot[p, t] <= Y[p, t] * L_ddot_upper[p, t])
                        @constraint(model, K_ddot[p, t] <= L_ddot[p, t])
                    end
                end

                for ω in Ω
                    for p in P
                        for t in T
                            @constraint(model, sum(X[v, p, t, ω] for v in V_p[p]) <= Y[p, t] * s_real_tilde[p, t, ω] + K_ddot[p, t])
                        end
                    end
                end
            else
                # Constraint (7)
                for p in P
                    for t in T
                        for tau in T
                            if (t, tau) in F_time_set
                                @constraint(model, sum(Q[v, p, (t, tau)] for v in V_p[p]) <= W[p, (t, tau)] * sum(s_real[p] for l in t:tau))
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
                                    @constraint(model, Q[v, p, (t, tau)] >= K[v, p, (t, tau), ω])
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
                            @constraint(model, d_real_tilde[a, t, ω] - sum(Vc[v, t, ω] for v in V_a[a]) + S[a, t-1, ω] <= S[a, t, ω])
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

            for i in 1:length(starting_points_vect_F)
                a = starting_points_vect_F[i][1]
                t = starting_points_vect_F[i][2]
                tau = starting_points_vect_F[i][3]
                @constraint(model, F[a, (t, tau)] == 1)
            end

            for ω in Ω
                for i in 1:length(starting_points_vect_I)
                    v = starting_points_vect_I[i][1]
                    amount = starting_points_vect_I[i][2]
                    @constraint(model, I[v, 0, ω] == amount)
                end
            end

            for ω in Ω
                for i in 1:length(starting_points_vect_S)
                    a = starting_points_vect_S[i][1]
                    amount = starting_points_vect_S[i][2]
                    @constraint(model, S[a, 0, ω] == amount)
                end
            end

            return model
        end

        current_directory = @__DIR__
        source = string(current_directory, "/results/log_DE_T_", tmax, "_delta_", max_tender_length, "_scen_", number_of_demand_scenarios * total_capacity_scenarios, "_trial_", trial, "_inv_", initial_inventory_rate, "_cap._", scaled_capacity, "_cap.inc._", allowable_capacity_increase_number, "_base.json")

        deterministic_equivalent_model = deterministic_equivalent(p_ω_test, Ω_test)
        set_optimizer_attribute(deterministic_equivalent_model, "LogFile", source)
        optimize!(deterministic_equivalent_model)

        deterministic_equivalent_obj = JuMP.objective_value(deterministic_equivalent_model)
        deterministic_equivalent_run_time = JuMP.solve_time(deterministic_equivalent_model)
        println("deterministic_equivalent_obj")
        println(deterministic_equivalent_obj)
        println("deterministic_equivalent_run_time")
        println(deterministic_equivalent_run_time)

        F_de = Dict()
        Y_de = Dict()
        W_de = Dict()
        L_de = Dict()
        Q_de = Dict()
        X_de = Dict()
        I_de = Dict()
        S_de = Dict()
        Vc_de = Dict()

        F_de = JuMP.value.(deterministic_equivalent_model[:F])
        Y_de = JuMP.value.(deterministic_equivalent_model[:Y])
        W_de = JuMP.value.(deterministic_equivalent_model[:W])
        L_de = JuMP.value.(deterministic_equivalent_model[:L])
        Q_de = JuMP.value.(deterministic_equivalent_model[:Q])
        X_de = JuMP.value.(deterministic_equivalent_model[:X])
        I_de = JuMP.value.(deterministic_equivalent_model[:I])
        Vc_de = JuMP.value.(deterministic_equivalent_model[:Vc])
        S_de = JuMP.value.(deterministic_equivalent_model[:S])

        println(F_de)
        println(W_de)
        println(Y_de)
        println(L_de)
        println(S_de)

        save_L_shaped_results(F_de, Y_de, W_de, L_de, Q_de, X_de, I_de, Vc_de, S_de)
    end
end
