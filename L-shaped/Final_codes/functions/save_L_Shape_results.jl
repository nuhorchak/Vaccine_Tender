"""
save_L_shaped_results(F_bar, Y_bar, W_bar, L_bar, Q_bar, X_de, I_de, Vc_de, S_de, model_type)

Saves the results of the L-shaped optimization model to a structured output file.

# Arguments
- `F_bar`: A dictionary containing binary variables \(F_{at\tau}\), indicating whether a tender covers the demand for antigen \(a\) for periods \(t\) through \(\tau\).
- `Y_bar`: A dictionary containing binary variables \(Y_{pt}\), specifying whether manufacturer \(p\) produces in period \(t\).
- `W_bar`: A dictionary containing binary variables \(W_{pt\tau}\), indicating if producer \(p\) has made commitments for periods \(t\) through \(\tau\).
- `L_bar`: A dictionary containing integer variables \(L_{pt}\), representing capacity extension for producer \(p\) in period \(t\).
- `Q_bar`: A dictionary containing variables \(Q_{vpt\tau m}\), representing procurement commitments for vaccine \(v\) by producer \(p\) for periods \(t\) through \(\tau\), at discount segment \(m\).
- `X_de`: A dictionary containing \(X_{vpt\omega}\), the doses of vaccine \(v\) delivered by producer \(p\) in period \(t\) for scenario \(\omega\).
- `I_de`: A dictionary containing \(I_{vt\omega}\), the stock level for vaccine \(v\) at the beginning of period \(t\) (including period 0) for scenario \(\omega\).
- `Vc_de`: A dictionary containing \(V_{vt\omega}\), the number of doses administered with vaccine \(v\) in period \(t\) for scenario \(\omega\).
- `S_de`: A dictionary containing \(S_{at\omega}\), the number of missed doses for antigen \(a\) in period \(t\) (including period 0) for scenario \(\omega\).
- `model_type`: A string indicating the model type (`"L-shaped"` or `"DE_after_L-shaped"`).

# Outputs
- Writes results to JSON files in the `results/` directory. The structure and file names vary based on `model_type`.
- Captures sensitivity metrics, including average tender lengths, capacity increases, and demand fulfillment metrics.
"""

# add Z variable to this to check discount pricing
function save_L_shaped_results(F_bar,Y_bar,W_bar,L_bar,Q_bar,X_de,I_de,Vc_de,S_de,model_type)
    F_results = Dict()
    for a in A
        temp_1 = Dict()
        for t in T
            temp_2 = Dict()
            for tau in T
                if (t,tau) in F_time_set
                    temp_2[tau] = F_bar[a,(t,tau)]
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
            temp_1[t] = Y_bar[p,t]
        end
        Y_results[p] = temp_1
    end

    W_results = Dict()
    for p in P
        temp_1 = Dict()
        for t in T
            temp_2 = Dict()
            for tau in T
                if (t,tau) in F_time_set
                    temp_2[tau] = W_bar[p,(t,tau)]
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
            temp_1[t] = L_bar[p,t]
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
                    if (t,tau) in F_time_set
                        temp_3[tau] = Q_bar[v,p,(t,tau)]
                    end
                end
                temp_2[t] = temp_3
            end
            temp_1[p] = temp_2
        end
        Q_results[v] = temp_1
    end

    if model_type == "L-shaped"
        X_results = Dict()
        for v in V
            temp_1 = Dict()
            for p in P_v[v]
                temp_2 = Dict()
                for t in T
                    temp_3 = Dict()
                    for ω in Ω_test
                        temp_3[ω] = X_de[ω][v,p,t]
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
                    temp_2[ω] = I_de[ω][v,t]
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
                    temp_2[ω] = Vc_de[ω][v,t]
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
                    temp_2[ω] = S_de[ω][a,t]
                end
                temp_1[t] = temp_2
            end
            S_results[a] = temp_1
        end
    elseif model_type == "DE_after_L-shaped"
        X_results = Dict()
        for v in V
            temp_1 = Dict()
            for p in P_v[v]
                temp_2 = Dict()
                for t in T
                    temp_3 = Dict()
                    for ω in Ω_test
                        temp_3[ω] = X_de[v,p,t,ω]
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
                    temp_2[ω] = I_de[v,t,ω]
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
                    temp_2[ω] = Vc_de[v,t,ω]
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
                    temp_2[ω] = S_de[a,t,ω]
                end
                temp_1[t] = temp_2
            end
            S_results[a] = temp_1
        end
    end


    L_shaped_output["F"] = F_results
    L_shaped_output["Y"] = Y_results
    L_shaped_output["W"] = W_results
    L_shaped_output["L"] = L_results
    L_shaped_output["Q"] = Q_results
    L_shaped_output["X"] = X_results
    L_shaped_output["I"] = I_results
    L_shaped_output["Vc"] = Vc_results
    L_shaped_output["S"] = S_results

    if model_type == "L-shaped"
        current_directory = @__DIR__
        source = string(current_directory, "/results/L_results_T_", tmax, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
        f = open(source, "w")
        JSON.print(f, L_shaped_output)
        close(f)
    elseif model_type == "DE_after_L-shaped"
        current_directory = @__DIR__
        source = string(current_directory, "/results/DE_L_results_T_", tmax, "_delta_",max_tender_length,"_scen_",length(random_scenarios),"_trial_",trial,"_inv_",initial_inventory_rate,"_cap._",scaled_capacity,"_cap.inc._",allowable_capacity_increase_number,".json")
        f = open(source, "w")
        JSON.print(f, L_shaped_output)
        close(f)

        sensitivity_output = Dict()

        total_tender_length = 0.0
        count = 0
        for a in A
            for t in T
                for tau in T
                    if (t, tau) in F_time_set
                        if F_bar[a, (t, tau)] == 1
                            total_tender_length += (tau-t+1) * F_bar[a, (t, tau)]
                            count += 1
                        end
                    end
                end
            end
        end
        avg_tender_length = total_tender_length/count
        println("total_tender_length: $total_tender_length")
        println("total_number_of_tenders: $count")
        println("avg_tender_length: $avg_tender_length")

        total_overlapped = total_tender_length - (length(A)*tmax)

        println("total_overlapped: $total_overlapped")

        sensitivity_output["avg_tender_length"] = avg_tender_length
        sensitivity_output["total_overlapped"] = total_overlapped

        total_cap_increase = Dict()

        for p in P
            temp_cap_inc = 0.0
            for t in T
                temp_cap_inc += L_bar[p,t]
            end
            total_cap_increase[p] = temp_cap_inc*10
        end
        println("total_cap_increase (%)")
        println(total_cap_increase)

        sensitivity_output["total_cap_increase"] = total_cap_increase

        total_cap_increase_category = Dict()
        for category in keys(capacity_category)
            # println(category)
            count = 0
            total_temp = 0.0
            for p in P
                if p in capacity_category[category]
                    # println(p)
                    # println(total_cap_increase[p])
                    total_temp += total_cap_increase[p]
                    count += 1
                end
            end
            avg_temp = total_temp/count
            total_cap_increase_category[category] = avg_temp
        end
        println("total_cap_increase_category (%)")
        println(total_cap_increase_category)

        sensitivity_output["total_cap_increase_category"] = total_cap_increase_category

        cap_usage = Dict()
        cap_usage_producer_range = Dict()
        cap_usage_producer_expected = Dict()
        cap_usage_category = Dict()
        cap_usage_category_overall = Dict()
        for p in P
            temp_p_dict = Dict()
            temp_p_dict_2 = Dict()
            smallest_ratio = 1.0
            largest_ratio = 0.0
            ratio_expected = 0.0
            for ω in Ω_test
                temp_omega_dict = Dict()
                temp_total_X = 0.0
                for v in V_p[p]
                    for t in T
                        temp_total_X += X_de[v,p,t,ω]
                    end
                end
                temp_avg_X = temp_total_X / length(T)
                temp_period_cap = 0.0
                for t in T
                    temp_period_cap += s_real_tilde[p, t, ω] + sum(κ * s_real[p] * L_bar[p, l] for l in 1:t)
                end
                temp_avg_period_cap = temp_period_cap / length(T)
                temp_p_dict_2[ω] = temp_avg_X / temp_avg_period_cap
                # cap_usage[p,ω] = temp_avg_X / temp_avg_period_cap
                if temp_p_dict_2[ω] <= smallest_ratio
                    smallest_ratio = temp_p_dict_2[ω]
                end
                if temp_p_dict_2[ω] >= largest_ratio
                    largest_ratio = temp_p_dict_2[ω]
                end
                ratio_expected += temp_p_dict_2[ω] * p_ω_test[ω]

                category_cap_usage = Dict()
                for category in keys(vaccine_category)
                    temp_category_total_X = 0.0
                    for v in V_p[p]
                        if v in vaccine_category[category]
                            for t in T
                                temp_category_total_X += X_de[v,p,t,ω]
                            end
                        end
                    end
                    temp_rate = temp_category_total_X / temp_total_X 
                    temp_omega_dict[category] = temp_rate
                    # cap_usage_category[p,ω,category] = temp_rate
                end
                temp_p_dict[ω] = temp_omega_dict
            end
            cap_usage[p] = temp_p_dict_2
            cap_usage_category[p] = temp_p_dict

            category_ratio_expected_dict = Dict()
            for category in keys(vaccine_category)
                category_ratio_expected = 0.0
                for ω in Ω_test
                    category_ratio_expected += cap_usage_category[p][ω][category] * p_ω_test[ω]
                end
                category_ratio_expected_dict[category] = category_ratio_expected
            end

            cap_usage_producer_range[p] = [smallest_ratio,largest_ratio]
            cap_usage_producer_expected[p] = ratio_expected
            cap_usage_category_overall[p] = category_ratio_expected_dict
        end

        println("cap_usage")
        println(cap_usage)
        println("cap_usage_range")
        println(cap_usage_producer_range)
        println("cap_usage_expected")
        println(cap_usage_producer_expected)
        println("cap_usage_category")
        println(cap_usage_category)
        println("cap_usage_category_overall")
        println(cap_usage_category_overall)

        sensitivity_output["cap_usage"] = cap_usage
        sensitivity_output["cap_usage_producer_range"] = cap_usage_producer_range
        sensitivity_output["cap_usage_producer_expected"] = cap_usage_producer_expected
        sensitivity_output["cap_usage_category"] = cap_usage_category
        sensitivity_output["cap_usage_category_overall"] = cap_usage_category_overall

        unvac_children = Dict()
        unvac_children_range = Dict()
        unvac_children_expected = Dict()
        for a in A
            temp_a_dict = Dict()
            smallest_unvac = Inf
            largest_unvac = 0.0
            unvac_expected = 0.0
            for ω in Ω_test
                temp_total_S = 0.0
                for t in T
                    temp_total_S += S_de[a,t,ω]
                end
                temp_avg_S = temp_total_S / length(T)
                temp_a_dict[ω] = temp_avg_S
                # unvac_children[a,ω] = temp_avg_S
                if temp_avg_S <= smallest_unvac  
                    smallest_unvac = temp_avg_S
                end
                if temp_avg_S >= largest_unvac
                    largest_unvac = temp_avg_S
                end
                unvac_expected += temp_avg_S * p_ω_test[ω]
            end

            unvac_children_range[a] = [smallest_unvac,largest_unvac]
            unvac_children_expected[a] = unvac_expected

            unvac_children[a] = temp_a_dict
        end

        unvac_children_range_category = Dict()
        for category in keys(antigen_category)
            temp_dict = Dict()
            for ω in Ω_test
                temp_category_scenario = 0.0
                for a in A
                    if a in antigen_category[category]
                        temp_category_scenario += unvac_children[a][ω]
                    end
                end
                temp_dict[category,ω] =  temp_category_scenario
            end

            smallest_unvac_category = Inf
            largest_unvac_category = 0.0
            for ω in Ω_test
                if temp_dict[category,ω] <= smallest_unvac_category
                    smallest_unvac_category = temp_dict[category,ω]
                end
                if temp_dict[category,ω] >= largest_unvac_category
                    largest_unvac_category = temp_dict[category,ω]
                end
            end
            unvac_children_range_category[category] = [smallest_unvac_category,largest_unvac_category]
        end


        category_S_expected_dict = Dict()
        for category in keys(antigen_category)
            category_S_expected = 0.0
            for a in A
                if a in antigen_category[category]
                    for ω in Ω_test
                        category_S_expected += unvac_children[a][ω] * p_ω_test[ω]
                    end
                end
            end
            category_S_expected_dict[category] = category_S_expected
        end

        println("unvac_children")
        println(unvac_children)
        println("unvac_children_range")
        println(unvac_children_range)
        println("unvac_children_expected")
        println(unvac_children_expected)
        println("category_S_expected_dict")
        println(category_S_expected_dict)
        println("unvac_children_range_category")
        println(unvac_children_range_category)

        sensitivity_output["unvac_children"] = unvac_children
        sensitivity_output["unvac_children_range"] = unvac_children_range
        sensitivity_output["unvac_children_expected"] = unvac_children_expected
        sensitivity_output["category_S_expected_dict"] = category_S_expected_dict
        sensitivity_output["unvac_children_range_category"] = unvac_children_range_category


        inv_vaccine = Dict()
        inv_vaccine_range = Dict()
        inv_vaccine_expected = Dict()
        for v in V
            temp_v_dict = Dict()
            smallest_inv = Inf
            largest_inv = 0.0
            inv_expected = 0.0
            for ω in Ω_test
                temp_total_I = 0.0
                for t in T
                    temp_total_I += I_de[v,t,ω]
                end
                temp_avg_I = temp_total_I / length(T)
                temp_v_dict[ω] = temp_avg_I
                # inv_vaccine[v,ω] = temp_avg_I
                if temp_avg_I <= smallest_inv  
                    smallest_inv = temp_avg_I
                end
                if temp_avg_I >= largest_inv
                    largest_inv = temp_avg_I
                end
                inv_expected += temp_avg_I * p_ω_test[ω]
            end
            inv_vaccine_range[v] = [smallest_inv,largest_inv]
            inv_vaccine_expected[v] = inv_expected
            inv_vaccine[v] = temp_v_dict
        end

        inv_range_category = Dict()
        for category in keys(vaccine_category)
            temp_dict = Dict()
            for ω in Ω_test
                temp_category_scenario = 0.0
                for v in V
                    if v in vaccine_category[category]
                        temp_category_scenario += inv_vaccine[v][ω]
                    end
                end
                temp_dict[category,ω] =  temp_category_scenario
            end

            smallest_inv_category = Inf
            largest_inv_category = 0.0
            for ω in Ω_test
                if temp_dict[category,ω] <= smallest_inv_category
                    smallest_inv_category = temp_dict[category,ω]
                end
                if temp_dict[category,ω] >= largest_inv_category
                    largest_inv_category = temp_dict[category,ω]
                end
            end
            inv_range_category[category] = [smallest_inv_category,largest_inv_category]
        end


        category_I_expected_dict = Dict()
        for category in keys(vaccine_category)
            category_I_expected = 0.0
            for v in V
                if v in vaccine_category[category]
                    for ω in Ω_test
                        category_I_expected += inv_vaccine[v][ω] * p_ω_test[ω]
                    end
                end
            end
            category_I_expected_dict[category] = category_I_expected
        end

        println("inv_vaccine")
        println(inv_vaccine)
        println("inv_vaccine_range")
        println(inv_vaccine_range)
        println("inv_vaccine_expected")
        println(inv_vaccine_expected)
        println("category_I_expected_dict")
        println(category_I_expected_dict)
        # println("inv_range_category")
        # println(inv_range_category)

        sensitivity_output["inv_vaccine"] = inv_vaccine
        sensitivity_output["inv_vaccine_range"] = inv_vaccine_range
        sensitivity_output["inv_vaccine_expected"] = inv_vaccine_expected
        sensitivity_output["category_I_expected_dict"] = category_I_expected_dict
        sensitivity_output["inv_range_category"] = inv_range_category

        current_directory = @__DIR__
        source = string(current_directory, "/results/DE_L_results_T_", tmax, "_delta_", max_tender_length, "_scen_", number_of_demand_scenarios * total_capacity_scenarios, "_trial_", trial, "_inv_", initial_inventory_rate, "_cap._", scaled_capacity, "_cap.inc._", allowable_capacity_increase_number, "_sensitivity_original.json")
        f = open(source, "w")
        JSON.print(f, sensitivity_output)
        close(f)
    end
end