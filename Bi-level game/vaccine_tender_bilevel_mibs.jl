#=
Exact bilevel solve with MibS (step 3), via BilevelJuMP.

Run from the "Bi-level game" folder with the project environment (BilevelJuMP + MibS_jll live there):
    julia --project=. --depwarn=yes vaccine_tender_bilevel_mibs.jl          # MMR test instance (T = 5, Δ = 3)
    julia --project=. --depwarn=yes vaccine_tender_bilevel_mibs.jl original # original deterministic data (T = 10, Δ = 5)

Every warning/error of the run goes to results/mibs_<tag>T<h>_D<Δ>_seed<s>_diagnostics.txt (Gurobi log: <work dir>/gurobi.log).

Each run also solves the HPR (lower bound) and re-evaluates MibS's leader decision with the Gurobi
best-response code, as an independent check of the MibS objective.
=#
include(joinpath(@__DIR__, "vaccine_tender_bilevel.jl"))   # data, model blocks, HPR, evaluation (does not auto-run)
using BilevelJuMP
import MibS_jll
include(joinpath(functions_directory, "bilevel_mibs.jl"))

"""
    run_mibs(; horizon, max_tender_length, seed, tag, time_limit, diagnostics = true, kwargs...)

With `diagnostics = true`, every warning and error of the run (Julia, Gurobi log, MibS) is collected in
results/mibs_<tag>T<h>_D<Δ>_seed<s>_diagnostics.txt. Start Julia with --depwarn=yes to include deprecations.
"""
function run_mibs(; horizon, max_tender_length, seed = 1, tag = "", diagnostics = true, kwargs...)
    stem = "mibs_$(tag)T$(horizon)_D$(max_tender_length)_seed$(seed)"
    diagnostics || return _run_mibs(; horizon, max_tender_length, seed, tag, kwargs...)
    work_dir = joinpath(results_dir, stem)
    with_diagnostics(joinpath(results_dir, "$(stem)_diagnostics.txt");
                     gurobi_log = joinpath(work_dir, "gurobi.log"), mibs_dir = work_dir) do
        _run_mibs(; horizon, max_tender_length, seed, tag, kwargs...)
    end
end

function _run_mibs(; horizon, max_tender_length, seed = 1, tag = "", time_limit = 3600.0, dose_scale = 1000, kwargs...)
    # dose_scale = 1000: quantities in millions of doses (unit 1000 × 1000) so the big-M coefficients drop from
    # ~1e6 to ~1e3; per-dose prices scale up by the same factor, so every objective value is unchanged
    d = load_bilevel_data(data_dir; horizon, max_tender_length, seed, dose_scale, kwargs...)
    println("Instance: |A|=$(length(d.A)) |V|=$(length(d.V)) |P|=$(length(d.P)) |VP|=$(length(d.VP)) windows=$(length(d.F_time_set))")
    results = Dict{String,Any}("horizon" => horizon, "max_tender_length" => max_tender_length, "seed" => seed,
                               "theta" => d.θ, "lambda" => d.λ, "u" => d.u, "time_limit" => time_limit)

    # lower bound for reference
    hpr, _, _ = build_hpr(d, gurobi_optimizer)
    quiet!(hpr)
    optimize!(hpr)
    termination_status(hpr) == MOI.OPTIMAL || @warn "HPR stopped at $(termination_status(hpr))"
    results["HPR"] = Dict("objective" => objective_value(hpr), "bound" => objective_bound(hpr))

    # exact bilevel solve
    bm, _, _ = build_bilevel_jump(d)
    work_dir = joinpath(results_dir, "mibs_$(tag)T$(horizon)_D$(max_tender_length)_seed$(seed)")
    t0 = time()
    sol = solve_with_mibs(bm; time_limit, work_dir)
    wall = time() - t0
    println("MibS status: $(sol.status)  objective: $(sol.objective)  bound: $(sol.bound)  gap: $(round(100 * sol.gap, digits = 2)) %  wall time: $(round(wall, digits = 1)) s")
    sol.status == :optimal || @warn "MibS did not prove optimality: status $(sol.status), gap $(sol.gap)"
    println("  upper vars: $(sol.n_upper)  lower vars: $(sol.n_lower)  lower rows: $(sol.n_lower_rows)")
    results["MibS"] = Dict("status" => string(sol.status), "objective" => sol.objective, "bound" => sol.bound,
                           "gap" => sol.gap, "wall_time" => wall,
                           "n_upper_vars" => sol.n_upper, "n_lower_vars" => sol.n_lower,
                           "n_lower_rows" => sol.n_lower_rows, "files" => work_dir)

    if sol.status != :no_solution
        Fx, Πx, Ωx = leader_decision_from_mibs(bm, sol.values)
        results["MibS"]["decision"] = decision_summary(d, Fx, Πx, Ωx)
        # independent check with Gurobi: producers' best responses to MibS's leader decision
        ev = evaluate_leader_decision(d, Fx, Πx, Ωx, gurobi_optimizer; time_limit)
        results["MibS"]["gurobi_check"] = Dict("cost" => ev.cost, "phi" => ev.φ, "terms" => term_values(ev.terms),
                                               "producers" => producer_summary(d, ev.model, ev.producers))
        println("Gurobi re-evaluation of MibS decision: ", round(ev.cost, digits = 2))
        println("HPR lower bound:                        ", round(results["HPR"]["bound"], digits = 2))
        cpa = 100 * (sol.objective - results["HPR"]["bound"]) / results["HPR"]["bound"]
        if sol.status == :optimal
            println("Cost of producer autonomy (v^BL − v^HPR)/v^HPR: ", round(cpa, digits = 2), " %")
        else
            println("Cost of producer autonomy: at most ", round(cpa, digits = 2), " % (MibS not proven optimal)")
        end
    end

    out = joinpath(results_dir, "mibs_$(tag)T$(horizon)_D$(max_tender_length)_seed$(seed).json")
    open(out, "w") do f
        JSON.print(f, results, 2)
    end
    println("Saved: ", out)
    return results, d, sol
end

run_mibs_mmr(; kwargs...) = run_mibs(; horizon = 5, max_tender_length = 3, tag = "MMR_", kwargs...)
run_mibs_original(; kwargs...) = run_mibs(; horizon = 10, max_tender_length = 5, tag = "ORIG_",
    vaccine_data_fn = create_vaccine_data,
    capacity_file = "production_capacity_scenarios_NEW_15YR_NO_MMR.xlsx",
    scenario_file = "scenario_pairs_new_1_scenario_15YR_NO_MMR.json",
    discount_vaccines = ["HPV", "Rotavirus", "PCV"],
    initial_inventory_rate = 1,
    antigen_demand_source = :scenario,
    kwargs...)

if abspath(PROGRAM_FILE) == @__FILE__
    (!isempty(ARGS) && lowercase(ARGS[1]) == "original") ? run_mibs_original() : run_mibs_mmr()
end
