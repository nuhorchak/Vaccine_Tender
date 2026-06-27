"""
    process_production_and_cost_data(data_dir::String, unit::Int, scaled_capacity::Float64, max_horizon_length::Int, max_tender_length::Int, P::Vector, V::Vector, P_v::Dict, V_p::Dict, allowable_capacity_increase_number::Int)

Processes production capacity, vaccine pricing, and cost-related data from Excel files and generates relevant parameters and dictionaries.

# Arguments:
- `data_dir::String`: Directory containing the data files (`production_capacity_scenarios.xlsx`, `Vaccine_price_data.xlsx`).
- `unit::Int`: Scaling factor for unit conversions.
- `scaled_capacity::Float64`: Scaling factor for production capacities.
- `max_horizon_length::Int`: Maximum time horizon length (tmax).
- `max_tender_length::Int`: Maximum tender length (Δ).
- `P::Vector`: Vector of producers.
- `V::Vector`: Vector of vaccines.
- `P_v::Dict`: Dictionary mapping vaccines to their producers.
- `V_p::Dict`: Dictionary mapping producers to their vaccines.
- `allowable_capacity_increase_number::Int`: Number of allowable capacity increases.

# Returns:
- Various dictionaries (`s_real`, `r`, `r_avg`, `r_producer_avg`, `g`, `h`, `l`, `f_profit`, `Γ`) and sets (`T`, `T_initial`, `Δ`, `F_time_set`) used for simulation and optimization.

"""
function initialize_parameters(
    data_dir::String, unit::Int, scaled_capacity::Int, max_horizon_length::Int, max_tender_length::Int, 
    P::Vector, V::Vector, P_v::Dict, V_p::Dict, allowable_capacity_increase_number::Int, iter::Int, n_iters::Int
)
    # Time-related sets
    tmin = 1
    tmax = max_horizon_length
    T = [t for t in tmin:tmax]
    T_initial = [t for t in tmin-1:tmax]
    Δ = [i for i in 1:max_tender_length]

    κ = 0.10
    L_lower_number = 0
    L_upper_number = allowable_capacity_increase_number
    delta = [(1+0.03)^t for t in 1:tmax]

    # inf_penalty = 100
    # Unvaccinated children penalty
    beta = 10

    # # Read production capacity data
    # capacity_file_path = joinpath(data_dir, "production_capacity_scenarios.xlsx")
    # capacity_file = XLSX.readxlsx(capacity_file_path)
    # s_real_raw = capacity_file["base_capacity"]

    # total_supply_row = length(P) + 1
    # total_supply_col = 2
    # s_real = Dict()

    # for row in 2:total_supply_row
    #     producer = s_real_raw[row, 1]
    #     for col in 2:total_supply_col
    #         year = s_real_raw[1, col]
    #         s_real[producer] = round(s_real_raw[row, col] * scaled_capacity / unit, digits=0)
    #     end
    # end

    # Define file path
    capacity_file_path = joinpath(data_dir, "production_capacity_scenarios_NEW_15YR_NO_MMR.xlsx")

    # Open the XLSX file and read the "base_capacity" sheet
    capacity_file = XLSX.readxlsx(capacity_file_path)
    s_real_raw = capacity_file["base_capacity"]  # Select the first sheet by name

    # Extract column names from the first row, ensuring they are all strings
    column_names = string.(vec(s_real_raw[1, :]))  # Convert to 1D vector of Strings
    @show column_names
    @show findall(==("missing"), column_names)

    # Extract actual data from row 2 onwards
    data = s_real_raw[2:end, :]

    # Convert to DataFrame using extracted column names
    s_real_raw_df = DataFrame(data, column_names)
    s_real_raw_df_filtered = filter(row -> row[1] in P, s_real_raw_df)
    # s_real_raw_df_filtered = s_real_raw_df_filtered[:, 1:2]


    # Initialize s_real dictionary
    s_real = Dict()

    # Iterate over rows of the filtered DataFrame
    for row in eachrow(s_real_raw_df_filtered)
        producer = row[1]  # Extract the manufacturer name from the first column

        # Iterate over column names starting from the second column (years)
        for col in names(s_real_raw_df_filtered)[2:2]  # Skip the first column (Manufacturer)
            year = string(col)  # Ensure the year is a string
            s_real[producer] = round(row[col] / unit, digits=5)  # Store value in dictionary
        end
    end

    # Read vaccine price data
    vaccine_price_file_path = joinpath(data_dir, "Vaccine_price_data_15YR.xlsx")
    vaccine_price_file = XLSX.readxlsx(vaccine_price_file_path)

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

    # Average vaccine prices per year
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

    # Average vaccine prices per producer
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

    # Return on investment
    l = Dict()
    for v in V
        for p in P
            l[v, p] = 0.02
        end
    end

        # Time set for tender
    F_time_set = []
    for t in T
        for tau in T
            if tau >= t && (tau - t + 1) in Δ
                push!(F_time_set, (t, tau))
            end
        end
    end

    prod_ratio_file_path = joinpath(data_dir, "producer_ratios.xlsx")
    sheet = "prop_by_manuf"
    sheet_data = DataFrame(XLSX.readtable(prod_ratio_file_path, sheet))
    df_selected = sheet_data[:, [1,3,2]]


    # Profit function 
    f_profit = Dict()
    for p in P
        for v in V_p[p]
            for (t,tau) in F_time_set
                selected_row = df_selected[(df_selected.Manufacturer .== p) .& (df_selected.Vaccine .== v), :]
                if !isempty(selected_row)
                    # The combination exists, so you can safely access the value
                    proportion_value = selected_row.Proportion[1]
                    # You can now use proportion_value in your calculations
                else
                    # The combination does not exist, so skip this iteration
                    continue # Use 'continue' to skip to the next iteration of the inner loop
                end
                f_profit[v, p, (t,tau)] = s_real[p] / length(V_p[p]) * r_producer_avg[p] /1e5 * proportion_value
            end
        end
    end

    # add * market share per vaccine

    # Cost of capacity expansion
    Γ = Dict()
    for p in P
        Γ[p] = 1e8 / unit
    end




    # Define the m values to cycle through for Q, Z, lambda_m

    ##############################################################################
    # # --- NEW: compute middle break based on iter / n_iters (linear spacing) ---
    # start_val = 1e2
    # end_val   = 1e8
    # if n_iters == 1
    #     middle_break = start_val
    # else
    #     # Logarithmic interpolation
    #     log_start = log10(start_val)  # 2
    #     log_end = log10(end_val)      # 8
    #     log_middle = log_start + (iter - 1) * (log_end - log_start) / (n_iters - 1)
    #     middle_break = 10^log_middle
    # end
    # middle_break = round(middle_break; digits=6)

    # # Update segment breaks using computed middle_break
    # m_segments = [0.00, -0.01]
    # lower_breaks_values = [0.0, middle_break]
    # upper_breaks_values = [middle_break + 1.0, 9.999999999999999e35]  # large sentinel

    # println("=" ^ 40)
    # println("        Break Values Summary")
    # println("=" ^ 40)
    # println("\nLower Breaks:")
    # println("  ", lower_breaks_values)
    # println("\nUpper Breaks:")
    # println("  ", upper_breaks_values)
    # println("\n" * "=" ^ 40)

    #*****************************************

    # # --- Compute logarithmically spaced breaks for 3 groups ---
    # start_val = 1e2
    # end_val   = 1e8

    # n_groups = 3
    # n_breaks = n_groups - 1

    # if n_breaks == 0
    #     break_values = Float64[]
    # else
    #     log_start = log10(start_val)
    #     log_end   = log10(end_val)

    #     break_values = [
    #         10^(log_start + i * (log_end - log_start) / n_groups)
    #         for i in 1:n_breaks
    #     ]
    # end

    # break_values = round.(break_values; digits=6)

    # # Segment definitions
    # m_segments = [0.00, -0.01, -0.02]

    # # Lower/upper bounds for each segment
    # lower_breaks_values = vcat(0.0, break_values)

    # upper_breaks_values = vcat(
    #     break_values .+ 1.0,
    #     9.999999999999999e35
    # )

    # println("=" ^ 40)
    # println("        Break Values Summary")
    # println("=" ^ 40)

    # println("\nBreak Values:")
    # println("  ", break_values)

    # println("\nLower Breaks:")
    # println("  ", lower_breaks_values)

    # println("\nUpper Breaks:")
    # println("  ", upper_breaks_values)

    # println("\n" * "=" ^ 40)
    ##############################################################################

    #%%%%%%%%%%%%%%%%%%%%%%%%%%%% DISCOUNT CODE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    m_segments = [0.00, 0.01]
    lower_breaks_values = [0, 6.0e4]
    upper_breaks_values = [6.01e4, 99999999999999999999999999999999999]

    #UG
    # m_segments = [0.00, 0.01, 0.02]
    # lower_breaks_values = [0, 6.0e4, 3.0e5]
    # upper_breaks_values = [6.01e4, 3.01e5, 99999999999999999999999999999999999]

    #SB
    # m_segments = [0.00, 0.01, 0.02]
    # lower_breaks_values = [0, 6.0e4, 3.0e8]
    # upper_breaks_values = [6.01e4, 3.01e8, 99999999999999999999999999999999999]

    # m_segments = [0.0, 0.01, 0.02, 0.04]
    # lower_breaks_values = [0.0, 1.041e4, 3.69e6, 5.47e8]
    # upper_breaks_values = [1.04e4, 3.68e6, 5.46e8, 999999999999999999999999999999]

    # m_segments = [0]
    # lower_breaks_values = [0]
    # upper_breaks_values = [99999999999999999999]

    zeta_vm = Dict()
    phi_vm_lower = Dict()
    phi_vm_upper = Dict()
 
    # Loop through v, and assign lambda for each m
    # for v in V
    #     for m in keys(m_segments)
    #         zeta_vm[v, m] = m_segments[m]
    #     end
    # end

    target_vaccines = ["Penta", "Hexa"]
    # target_vaccines = ["TT", "HepB",  "IPV", "OPV", "DT", "Td", "DTwP", "DTwP-Hib", "HPV", "Rotavirus", "PCV", "Penta", "Hexa"]
    # target_vaccines = ["TT", "HepB",  "IPV", "OPV", "DT", "Td", "DTwP", "DTwP-Hib", "HPV", "Rotavirus", "PCV"]

    for v in V, m in eachindex(m_segments)
        zeta_vm[v, m] = (v in target_vaccines) ? m_segments[m] : 0.0
    end
 
 
    for v in V
        for m in keys(lower_breaks_values)
            phi_vm_lower[v, m] = lower_breaks_values[m]
        end
    end
 
    for v in V
        for m in keys(upper_breaks_values)
            phi_vm_upper[v, m] = upper_breaks_values[m]
        end
    end

    # Single segment - fixed discounts only, no quantity breaks needed
    # m_segments = [0.0]
    # lower_breaks_values = [0.0]
    # upper_breaks_values = [99999999999999999999.0]

    # producer_discount = Dict(
    #     "Small"  => 0.10,
    #     "Medium" => 0.05,
    #     "Large"  => 0.00
    # )

    # # Invert capacity_category to a producer -> category lookup
    # capacity_category = Dict(
    #     "Small"  => ["Serum_Institute", "Haffkine_Bio", "Merck_Sharp", "Sanofi"],
    #     "Medium" => ["Bilthoven", "Pfizer", "Bharat_Biotech", "PT_Bio", "BB_NCIPD", "China_National"],
    #     "Large"  => ["GSK", "Biological_E", "AJ_Vaccines", "LG_Chem", "Panacea_Biotec"]
    # )

    # producer_to_category = Dict(
    #     p => cat for (cat, producers) in capacity_category for p in producers
    # )

    # zeta_vm    = Dict()
    # phi_vm_lower = Dict()
    # phi_vm_upper = Dict()

    # for v in V, m in eachindex(m_segments)
    #     cat = get(producer_to_category, v, "Large")  # default to no discount if unlisted
    #     zeta_vm[v, m] = producer_discount[cat]
    # end

    # for v in V, m in eachindex(m_segments)
    #     phi_vm_lower[v, m] = lower_breaks_values[m]
    #     phi_vm_upper[v, m] = upper_breaks_values[m]
    # end

    #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% DISCOUNT CODE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    λ = 0.8


    return T, T_initial, Δ, s_real, r, r_avg, r_producer_avg, g, h, l, f_profit, Γ, F_time_set, κ, L_lower_number, L_upper_number, delta, beta, zeta_vm, phi_vm_lower, phi_vm_upper, m_segments, λ
end