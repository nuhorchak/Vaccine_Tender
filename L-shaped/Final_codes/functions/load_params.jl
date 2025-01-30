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
function process_production_and_cost_data(
    data_dir::String, unit::Int, scaled_capacity::Int, max_horizon_length::Int, max_tender_length::Int, 
    P::Vector, V::Vector, P_v::Dict, V_p::Dict, allowable_capacity_increase_number::Int
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

    inf_penalty = 100

    # Read production capacity data
    capacity_file_path = joinpath(data_dir, "production_capacity_scenarios.xlsx")
    capacity_file = XLSX.readxlsx(capacity_file_path)
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

    # Read vaccine price data
    vaccine_price_file_path = joinpath(data_dir, "Vaccine_price_data.xlsx")
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
            l[v, p] = 0.1
        end
    end

    # Profit function
    f_profit = Dict()
    for p in P
        for v in V_p[p]
            for t in T
                f_profit[v, p, t] = s_real[p] / length(V_p[p]) * r_producer_avg[p] / 2
            end
        end
    end

    # Cost of capacity expansion
    Γ = Dict()
    for p in P
        Γ[p] = 1e8 / unit
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

# Define the lambda values to cycle through
lambda_values_list = [0.05, 0.1, 0.2]

# Initialize a dictionary to store lambda values
lambda_m = Dict()

# Loop through v, p, t, and assign lambda for each m
for v in V
    for p in P
        for t in T
            for m in 1:length(lambda_values_list)
                lambda_m[v, p, t, m] = lambda_values_list[m]
            end
        end
    end
end


    return T, T_initial, Δ, s_real, r, r_avg, r_producer_avg, g, h, l, f_profit, Γ, F_time_set, κ, L_lower_number, L_upper_number, delta, inf_penalty, lambda_m
end