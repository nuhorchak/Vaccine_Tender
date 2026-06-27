"""
Multi-model cost analysis across n trial runs per model.

Computes for each model:
  1. COORDINATING ENTITY COST (tender + procurement)
  2. PRODUCTION COST (capacity extension + unrecouped setup)
  3. SYSTEM HOLDING COST

Then outputs:
  - Console: per-trial table + mean/std summary per model
  - Excel:   one sheet per model (per-trial breakdown) + summary comparison sheet
  - Plots:   one bar chart per cost component, models on x-axis with CI bars

Sets from create_vaccine_data:          A, V, P, P_v, V_p
Parameters from initialize_parameters:  delta, g, r_avg, zeta_vm, Gamma,
                                         f_profit, T, Delta, m_segments
Results from JSON:                       Q[v][p][t][tau][m], F[a][t][tau],
                                         L[p][t], W[p][t][tau], I[v][t][omega]
"""

using JSON, Printf, Statistics
using DataFrames, XLSX
using Plots, StatsPlots

const FUNCTIONS_DIR = joinpath(@__DIR__, "..", "..", "Model Files", "Segment Test", "functions")
include(joinpath(FUNCTIONS_DIR, "create_vaccine_data.jl"))
include(joinpath(FUNCTIONS_DIR, "initialize_parameters.jl"))

# =============================================================================
# CONFIGURATION
# =============================================================================

# Define models: each entry is (label, path_to_results_folder)
const MODELS = [
    ("UG-OLD", joinpath(@__DIR__, "results", "UG_test_no_W", "OLD")),
    ("UG-No_W", joinpath(@__DIR__, "results", "UG_test_no_W", "NEW"))
]

const DATA_DIR         = joinpath(@__DIR__, "data")
const STARTING_PT_PATH = joinpath(@__DIR__, "data", "Starting_point.xlsx")
const OUTPUT_EXCEL     = joinpath(@__DIR__, "results", "model comparison", "UG_With_and_Without_W", "model_cost_comparison.xlsx")
const OUTPUT_PLOTS_DIR = joinpath(@__DIR__, "results", "model comparison", "UG_With_and_Without_W")

const UNIT       = 1000
const TMAX       = 10
const DELTA_MAX  = 5
const SCALED_CAP = 1
const ALLOW_CAP  = 1
const ITER       = 1
const N_ITERS    = 1

# Filename convention -- only trial number varies between files
# e.g. MVP_DE_results_T_10_delta_5_scen_1_trial_3_inv_1_cap._1_cap.inc._1.json
const FILE_PREFIX = "MVP_DE_results_T_10_delta_5_scen_1_trial_"
const FILE_SUFFIX = "_inv_1_cap._1_cap.inc._1.json"

# =============================================================================
# 0.  Sets and parameters (computed once, shared across all models/trials)
# =============================================================================
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

# Load starting points (once)
let
    tbl = XLSX.readtable(STARTING_PT_PATH, "F_start")
    df  = DataFrame(tbl)
    global starting_points_vect_F = Set{Tuple{String,Int,Int}}()
    for row in eachrow(df)
        push!(starting_points_vect_F, (string(row[1]), Int(row[2]), Int(row[3])))
    end
end
println("Starting points loaded: ", length(starting_points_vect_F), " entries")

# =============================================================================
# 1.  Helper functions
# =============================================================================
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
    haskey(F_data, a)             || return 0.0
    haskey(F_data[a], t_s)        || return 0.0
    haskey(F_data[a][t_s], tau_s) || return 0.0
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
    haskey(W_data, p)             || return 0.0
    haskey(W_data[p], t_s)        || return 0.0
    haskey(W_data[p][t_s], tau_s) || return 0.0
    return Float64(W_data[p][t_s][tau_s])
end

function get_I(I_data, v, t, omega::String="1")::Float64
    t_s = string(t)
    haskey(I_data, v)             || return 0.0
    haskey(I_data[v], t_s)        || return 0.0
    haskey(I_data[v][t_s], omega) || return 0.0
    return Float64(I_data[v][t_s][omega])
end

function get_S(S_data, a, t, omega::String="1")::Float64
    t_s = string(t)
    haskey(S_data, a)             || return 0.0
    haskey(S_data[a], t_s)        || return 0.0
    haskey(S_data[a][t_s], omega) || return 0.0
    return Float64(S_data[a][t_s][omega])
end

# =============================================================================
# 2.  Core computation for a single JSON file
# =============================================================================
function compute_costs(json_path::String)
    results = JSON.parsefile(json_path)
    Q_data  = results["Q"]
    F_data  = results["F"]
    L_data  = results["L"]
    W_data  = results["W"]
    I_data  = results["I"]
    A_F     = collect(keys(F_data))
    S_data  = results["S"]   # S[antigen][t][omega]

    tender_cost_total      = 0.0
    procurement_cost_total = 0.0
    cap_extension_total    = 0.0
    prod_setup_total       = 0.0
    holding_cost_total     = 0.0

    for t in T
        tau_list = tau_set(t, T, Delta)

        tender_sum = 0.0
        for a in A_F, tau in tau_list
            (a, t, tau) in starting_points_vect_F && continue
            tender_sum += g[t] * get_F(F_data, a, t, tau) / delta[t]
        end

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

        holding_sum = 0.0
        for v in V
            holding_sum += h[v] * r_avg[v, t] * get_I(I_data, v, t)
        end

        tender_cost_total      += delta[t] * tender_sum
        procurement_cost_total += delta[t] * procurement_sum
        cap_extension_total    += delta[t] * gamma_L_sum
        prod_setup_total       += delta[t] * unrec_setup_sum
        holding_cost_total     += delta[t] * holding_sum
    end

    # Missed doses: raw sum_{a} S[a, t=TMAX, omega=1]
    # Only period TMAX (rolling sum -- final period captures cumulative shortfall)
    # Raw doses, no beta penalty or delta discounting applied.
    missed_doses = 0.0
    A_S = collect(keys(S_data))
    for a in A_S
        missed_doses += get_S(S_data, a, TMAX, "1")
    end

    ce_cost_total     = tender_cost_total + procurement_cost_total
    production_total  = cap_extension_total + prod_setup_total
    grand_total_cost  = ce_cost_total + production_total + holding_cost_total

    return (
        grand_total           = grand_total_cost,
        ce_cost               = ce_cost_total,
        tender_component      = tender_cost_total,
        procurement_component = procurement_cost_total,
        production_cost       = production_total,
        cap_extension_cost    = cap_extension_total,
        prod_setup_cost       = prod_setup_total,
        holding_cost          = holding_cost_total,
        missed_doses          = missed_doses,
    )
end

# =============================================================================
# 3.  Run all models
# =============================================================================

# cost fields and their display labels
const COST_FIELDS = [:ce_cost, :production_cost, :holding_cost, :missed_doses]
const COST_LABELS = ["Coordinating Entity Costs", "Production Costs", "Holding Costs", "Missed Doses"]

# model_stats[label] = (trials=Vector{NamedTuple}, means=Dict, stds=Dict)
model_stats = Dict{String, NamedTuple}()

for (model_label, results_dir) in MODELS
    println("\n", "=" ^ 70)
    println("MODEL: $model_label  →  $results_dir")
    println("=" ^ 70)

    all_files = sort([
        f for f in readdir(results_dir)
        if startswith(f, FILE_PREFIX) && endswith(f, FILE_SUFFIX)
    ])

    isempty(all_files) && error("No matching files found for model $model_label in $results_dir")
    println("Found $(length(all_files)) trial files")

    trial_results = NamedTuple[]
    for fname in all_files
        trial_num = replace(replace(fname, FILE_PREFIX => ""), FILE_SUFFIX => "")
        fpath     = joinpath(results_dir, fname)
        print("  Trial $trial_num ... ")
        res = compute_costs(fpath)
        push!(trial_results, merge(res, (trial = trial_num,)))
        println("grand total = $(round(res.grand_total, digits=2))")
    end

    # Compute mean and std for each cost field
    means = Dict(f => mean([getfield(r, f) for r in trial_results]) for f in COST_FIELDS)
    stds  = Dict(f => std( [getfield(r, f) for r in trial_results]) for f in COST_FIELDS)

    model_stats[model_label] = (trials = trial_results, means = means, stds = stds)

    # Per-model console summary
    sep = "-" ^ 50
    println()
    println(sep)
    @printf("  %-28s  %14s  %14s\n", "Cost Component", "Mean", "Std Dev")
    println(sep)
    for (field, label) in zip(COST_FIELDS, COST_LABELS)
        @printf("  %-28s  %14.2f  %14.2f\n", label, means[field], stds[field])
    end
    println(sep)
end

# =============================================================================
# 4.  Cross-model comparison (console)
# =============================================================================
model_labels = [m[1] for m in MODELS]
sep = "=" ^ (30 + 30 * length(MODELS))
println("\n", sep)
println("CROSS-MODEL COMPARISON  (Mean ± Std Dev)")
println(sep)
let
    header = @sprintf("%-28s", "Cost Component")
    for lbl in model_labels
        header = header * @sprintf("  %-28s", lbl)
    end
    println(header)
    println("-" ^ (30 + 30 * length(MODELS)))
    for (field, label) in zip(COST_FIELDS, COST_LABELS)
        row = @sprintf("%-28s", label)
        for lbl in model_labels
            m = model_stats[lbl].means[field]
            s = model_stats[lbl].stds[field]
            row = row * @sprintf("  %12.2f ± %-12.2f", m, s)
        end
        println(row)
    end
end
println(sep)

# =============================================================================
# 5.  Excel output
# =============================================================================
println("\nWriting Excel output to: $OUTPUT_EXCEL")

XLSX.openxlsx(OUTPUT_EXCEL, mode="w") do xf

    # -- One sheet per model: per-trial breakdown
    for (model_label, _) in MODELS
        stats  = model_stats[model_label]
        trials = stats.trials
        sheet  = XLSX.addsheet!(xf, model_label)

        # Header row
        headers = ["Trial", "Coordinating Entity Costs", "Production Costs", "Holding Costs", "Missed Doses"]
        for (col, h) in enumerate(headers)
            sheet[1, col] = h
        end

        # Data rows
        for (row_idx, r) in enumerate(trials)
            sheet[row_idx + 1, 1] = r.trial
            sheet[row_idx + 1, 2] = r.ce_cost
            sheet[row_idx + 1, 3] = r.production_cost
            sheet[row_idx + 1, 4] = r.holding_cost
            sheet[row_idx + 1, 5] = r.missed_doses
        end

        # Mean and std rows at the bottom
        n_trials = length(trials)
        sheet[n_trials + 2, 1] = "Mean"
        sheet[n_trials + 3, 1] = "Std Dev"
        for (col_idx, field) in enumerate(COST_FIELDS)
            sheet[n_trials + 2, col_idx + 1] = stats.means[field]
            sheet[n_trials + 3, col_idx + 1] = stats.stds[field]
        end
    end

    # -- Summary comparison sheet
    summary = XLSX.addsheet!(xf, "Summary Comparison")

    # Build header: Cost Component | Model1 Mean | Model1 Std | Model2 Mean | ...
    summary[1, 1] = "Cost Component"
    col = 2
    for lbl in model_labels
        summary[1, col]     = "$lbl Mean"
        summary[1, col + 1] = "$lbl Std Dev"
        col += 2
    end

    for (row_idx, (field, label)) in enumerate(zip(COST_FIELDS, COST_LABELS))
        summary[row_idx + 1, 1] = label
        col = 2
        for lbl in model_labels
            summary[row_idx + 1, col]     = model_stats[lbl].means[field]
            summary[row_idx + 1, col + 1] = model_stats[lbl].stds[field]
            col += 2
        end
    end
end
println("Excel file written.")

# =============================================================================
# 6.  Bar charts with confidence intervals (one per cost component)
# =============================================================================
mkpath(OUTPUT_PLOTS_DIR)
println("Generating plots in: $OUTPUT_PLOTS_DIR")

# 95% CI multiplier (1.96 * std / sqrt(n))
n_trials_per_model = [length(model_stats[lbl].trials) for lbl in model_labels]

for (field, label) in zip(COST_FIELDS, COST_LABELS)
    means_vec = [model_stats[lbl].means[field] for lbl in model_labels]
    stds_vec  = [model_stats[lbl].stds[field]  for lbl in model_labels]
    n_vec     = n_trials_per_model
    ci_vec    = [1.96 * s / sqrt(n) for (s, n) in zip(stds_vec, n_vec)]

    # Safe filename: replace spaces, parentheses, slashes
    safe_name = replace(replace(replace(label, " " => "_"), r"[()γ/]" => ""), "." => "")

    bar_plot = bar(
        model_labels,
        means_vec,
        xrotation=45,
        yerror       = ci_vec,
        legend       = false,
        title        = label,
        xlabel       = "Model",
        ylabel       = "Cost",
        bar_width    = 0.5,
        color        = [:steelblue, :coral, :seagreen, :mediumpurple, :slategray, :tomato, :teal, :hotpink, :darkorange, :goldenrod][1:length(model_labels)],
        # color_palette = :Dark2_8,
        linecolor    = :black,
        errorbar_linewidth = 2,
        size         = (600, 450),
        titlefontsize = 12,
        margin       = 8Plots.mm,
    )

    outpath = joinpath(OUTPUT_PLOTS_DIR, "$(safe_name).png")
    savefig(bar_plot, outpath)
    println("  Saved: $(safe_name).png")
end

println("\nDone. All outputs written.")
