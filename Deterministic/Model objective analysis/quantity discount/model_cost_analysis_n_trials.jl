"""
Computes and aggregates cost components across n trial runs:

1. COORDINATING ENTITY COST:
       sum_{t in T} delta_t * (
           sum_{a in A} sum_{tau in T_t^l} g_t * F_{a,t,tau} / delta[t]
         + sum_{v in V} sum_{p in P} sum_{m in M}
               r_avg_{v,t} * (1 - zeta_{v,m}) * sum_{tau} Q_{v,p,t,tau,m}
       )

2. PRODUCTION COST:
       sum_{t in T} delta_t * (
           sum_{p in P} gamma_p * L_{p,t}
         + sum_{v in V_p} sum_{p in P} sum_{tau} (1 - f_profit_{v,p,t,tau}) * W_{p,t,tau}
       )

3. SYSTEM HOLDING COST:
       sum_{t in T} delta_t * (
           sum_{v in V} h_v * r_vt * I_{v,t}
       )

Loops over all JSON files matching the naming convention in RESULTS_DIR,
varying the trial number. Reports per-trial results and mean ± std across trials.

Sets from create_vaccine_data:          A, V, P, P_v, V_p
Parameters from initialize_parameters:  delta, g, r_avg, zeta_vm, Gamma (=gamma_p),
                                         f_profit, T, Delta, m_segments
Results from JSON:                       Q[v][p][t][tau][m]  -- procurement quantities
                                         F[a][t][tau]        -- tender schedule (binary)
                                         L[p][t]             -- capacity extension (integer)
                                         W[p][t][tau]        -- producer delivery commitment (binary)
                                         I[v][t][omega]      -- inventory stock level
"""

using JSON, Printf, Statistics
using DataFrames, XLSX
const FUNCTIONS_DIR = joinpath(@__DIR__, "..", "..", "Model Files", "Segment Test", "functions")
include(joinpath(FUNCTIONS_DIR, "create_vaccine_data.jl"))
include(joinpath(FUNCTIONS_DIR, "initialize_parameters.jl"))

# -----------------------------------------------------------------------------
# CONFIGURATION  -- edit these to match your run
# -----------------------------------------------------------------------------
const RESULTS_DIR       = joinpath(@__DIR__, "results", "buyer discounts", "2 segments", "UG")
const DATA_DIR          = joinpath(@__DIR__, "data")
const STARTING_PT_PATH  = joinpath(@__DIR__, "data", "Starting_point.xlsx")
const UNIT              = 1000
const TMAX              = 10
const DELTA_MAX         = 5
const SCALED_CAP        = 1
const ALLOW_CAP         = 1
const ITER              = 1
const N_ITERS           = 1

# Filename template -- trial number is the only varying field
# e.g. MVP_DE_results_T_10_delta_5_scen_1_trial_3_inv_1_cap._1_cap.inc._1.json
const FILE_PREFIX = "MVP_DE_results_T_10_delta_5_scen_1_trial_"
const FILE_SUFFIX = "_inv_1_cap._1_cap.inc._1.json"

# -----------------------------------------------------------------------------
# 0.  Sets and parameters (computed once, shared across all trials)
# -----------------------------------------------------------------------------
A, V, A_v, P, P_v, V_a, V_p, P_a, A_p,
    capacity_category, vaccine_category, antigen_category = create_vaccine_data()

T, T_initial, Delta, s_real, r, r_avg, r_producer_avg, g, h, l, f_profit, Gamma,
    F_time_set, kappa, L_lower_number, L_upper_number, delta, beta,
    zeta_vm, phi_vm_lower, phi_vm_upper, m_segments, lambda =
        initialize_parameters(
            DATA_DIR, UNIT, SCALED_CAP, TMAX, DELTA_MAX,
            P, V, P_v, V_p, ALLOW_CAP, ITER, N_ITERS
        )

M = collect(eachindex(m_segments))

# -----------------------------------------------------------------------------
# Load starting points (once)
# -----------------------------------------------------------------------------
let
    tbl = XLSX.readtable(STARTING_PT_PATH, "F_start")
    df  = DataFrame(tbl)
    global starting_points_vect_F = Set{Tuple{String,Int,Int}}()
    for row in eachrow(df)
        antigen = string(row[1])
        t_start = Int(row[2])
        t_end   = Int(row[3])
        push!(starting_points_vect_F, (antigen, t_start, t_end))
    end
end
println("Starting points loaded: ", length(starting_points_vect_F), " entries")

# -----------------------------------------------------------------------------
# 1.  Helper functions
# -----------------------------------------------------------------------------
function tau_set(t::Int, T::Vector{Int}, Delta::Vector{Int})
    return [tau for tau in T if tau >= t && (tau - t + 1) in Delta]
end

function get_Q(Q_data, v, p, t, tau, m)::Float64
    t_s, tau_s, m_s = string(t), string(tau), string(m)
    haskey(Q_data, v)                      || return 0.0
    haskey(Q_data[v], p)                   || return 0.0
    haskey(Q_data[v][p], t_s)             || return 0.0
    haskey(Q_data[v][p][t_s], tau_s)      || return 0.0
    haskey(Q_data[v][p][t_s][tau_s], m_s) || return 0.0
    return Float64(Q_data[v][p][t_s][tau_s][m_s])
end

function get_F(F_data, a, t, tau)::Float64
    t_s, tau_s = string(t), string(tau)
    haskey(F_data, a)              || return 0.0
    haskey(F_data[a], t_s)         || return 0.0
    haskey(F_data[a][t_s], tau_s)  || return 0.0
    return Float64(F_data[a][t_s][tau_s])
end

function get_L(L_data, p, t)::Float64
    t_s = string(t)
    haskey(L_data, p)      || return 0.0
    haskey(L_data[p], t_s) || return 0.0
    return Float64(L_data[p][t_s])
end

function get_W(W_data, p, t, tau)::Float64
    t_s, tau_s = string(t), string(tau)
    haskey(W_data, p)              || return 0.0
    haskey(W_data[p], t_s)         || return 0.0
    haskey(W_data[p][t_s], tau_s)  || return 0.0
    return Float64(W_data[p][t_s][tau_s])
end

function get_I(I_data, v, t, omega::String="1")::Float64
    t_s = string(t)
    haskey(I_data, v)             || return 0.0
    haskey(I_data[v], t_s)        || return 0.0
    haskey(I_data[v][t_s], omega) || return 0.0
    return Float64(I_data[v][t_s][omega])
end

# -----------------------------------------------------------------------------
# 2.  Core computation for a single JSON file
# -----------------------------------------------------------------------------
function compute_costs(json_path::String)
    results = JSON.parsefile(json_path)
    Q_data  = results["Q"]
    F_data  = results["F"]
    L_data  = results["L"]
    W_data  = results["W"]
    I_data  = results["I"]

    A_F = collect(keys(F_data))

    tender_cost_total      = 0.0
    procurement_cost_total = 0.0
    production_cost_total  = 0.0
    cap_extension_total    = 0.0
    prod_setup_total       = 0.0
    holding_cost_total     = 0.0

    for t in T
        tau_list = tau_set(t, T, Delta)

        # Tender cost
        tender_sum = 0.0
        for a in A_F, tau in tau_list
            (a, t, tau) in starting_points_vect_F && continue
            tender_sum += g[t] * get_F(F_data, a, t, tau) / delta[t]
        end

        # Procurement cost
        procurement_sum = 0.0
        for v in V
            haskey(Q_data, v) || continue
            for p in keys(Q_data[v])
                for m in M
                    zeta  = zeta_vm[v, m]
                    r_bar = r_avg[v, t]
                    Q_sum = sum(get_Q(Q_data, v, p, t, tau, m) for tau in tau_list)
                    procurement_sum += r_bar * (1.0 - zeta) * Q_sum
                end
            end
        end

        # Production cost
        gamma_L_sum = 0.0
        for p in P
            gamma_L_sum += Gamma[p] * get_L(L_data, p, t)
        end

        unrec_setup_sum = 0.0
        for p in P
            for tau in T
                W_val = get_W(W_data, p, t, tau)
                W_val == 0.0 && continue
                for v in V_p[p]
                    fp = get(f_profit, (v, p, (t, tau)), 0.0)
                    unrec_setup_sum += (1.0 - fp) * W_val
                end
            end
        end

        production_sum = gamma_L_sum + unrec_setup_sum

        # Holding cost
        holding_sum = 0.0
        for v in V
            holding_sum += h[v] * r_avg[v, t] * get_I(I_data, v, t)
        end

        tender_cost_total      += delta[t] * tender_sum
        procurement_cost_total += delta[t] * procurement_sum
        production_cost_total  += delta[t] * production_sum
        cap_extension_total    += delta[t] * gamma_L_sum
        prod_setup_total       += delta[t] * unrec_setup_sum
        holding_cost_total     += delta[t] * holding_sum
    end

    ce_cost_total    = tender_cost_total + procurement_cost_total
    grand_total_cost = ce_cost_total + production_cost_total + holding_cost_total

    return (
        grand_total           = grand_total_cost,
        ce_cost               = ce_cost_total,
        tender_component      = tender_cost_total,
        procurement_component = procurement_cost_total,
        production_cost       = production_cost_total,
        cap_extension_cost    = cap_extension_total,
        prod_setup_cost       = prod_setup_total,
        holding_cost          = holding_cost_total,
    )
end

# -----------------------------------------------------------------------------
# 3.  Discover and run all trial files
# -----------------------------------------------------------------------------
all_files = sort([
    f for f in readdir(RESULTS_DIR)
    if startswith(f, FILE_PREFIX) && endswith(f, FILE_SUFFIX)
])

if isempty(all_files)
    error("No matching JSON files found in: $RESULTS_DIR")
end

println("Found ", length(all_files), " trial files:")
for f in all_files; println("  ", f); end
println()

# Collect results across trials
trial_results = []
for fname in all_files
    trial_num = replace(replace(fname, FILE_PREFIX => ""), FILE_SUFFIX => "")
    fpath = joinpath(RESULTS_DIR, fname)
    print("  Computing trial $trial_num ... ")
    res = compute_costs(fpath)
    push!(trial_results, merge(res, (trial = trial_num,)))
    println("done  (grand total = $(round(res.grand_total, digits=2)))")
end

# -----------------------------------------------------------------------------
# 4.  Per-trial report
# -----------------------------------------------------------------------------
sep = "=" ^ 100
println()
println(sep)
println("PER-TRIAL COST BREAKDOWN")
println(sep)
@printf("%-8s  %-14s  %-14s  %-14s  %-14s  %-14s  %-14s\n",
        "Trial", "CE Cost", "Tender", "Procurement", "Production", "Holding", "Grand Total")
println("-" ^ 100)
for r in trial_results
    @printf("%-8s  %14.2f  %14.2f  %14.2f  %14.2f  %14.2f  %14.2f\n",
            r.trial,
            r.ce_cost,
            r.tender_component,
            r.procurement_component,
            r.production_cost,
            r.holding_cost,
            r.grand_total)
end
println(sep)

# -----------------------------------------------------------------------------
# 5.  Mean and std across trials
# -----------------------------------------------------------------------------
fields = [:grand_total, :ce_cost, :tender_component, :procurement_component,
          :production_cost, :cap_extension_cost, :prod_setup_cost, :holding_cost]
labels = ["Grand total", "CE cost (subtotal)", "  Tender component",
          "  Procurement component", "Production cost",
          "  Capacity extension (γL)", "  Production setup (1-f)W", "Holding cost"]

println()
println(sep)
println("SUMMARY ACROSS $(length(trial_results)) TRIALS")
println(sep)
@printf("%-30s  %20s  %20s\n", "Cost component", "Mean", "Std Dev")
println("-" ^ 74)
for (field, label) in zip(fields, labels)
    vals = [getfield(r, field) for r in trial_results]
    @printf("%-30s  %20.2f  %20.2f\n", label, mean(vals), std(vals))
end
println(sep)
