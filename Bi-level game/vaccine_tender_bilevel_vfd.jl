#=
Bilevel solve by value-function decomposition (step 4), all MILPs with Gurobi.

Run from the "Bi-level game" folder:
    julia --project=. vaccine_tender_bilevel_vfd.jl          # MMR test instance (T = 5, Δ = 3)
    julia --project=. vaccine_tender_bilevel_vfd.jl original # original deterministic data (T = 10, Δ = 5)
=#
include(joinpath(@__DIR__, "vaccine_tender_bilevel.jl"))   # data, model blocks, HPR, evaluation (does not auto-run)
include(joinpath(functions_directory, "bilevel_vfd.jl"))

function run_vfd(; horizon, max_tender_length, seed = 1, tag = "", time_limit = 3600.0, max_iter = 200,
                 gap_tol = 1e-4, kwargs...)
    d = load_bilevel_data(data_dir; horizon, max_tender_length, seed, kwargs...)
    println("Instance: |A|=$(length(d.A)) |V|=$(length(d.V)) |P|=$(length(d.P)) |VP|=$(length(d.VP)) windows=$(length(d.F_time_set))")

    res = solve_vfd(d, gurobi_optimizer; max_iter, time_limit, gap_tol)
    println("VFD status: $(res.status)  LB $(round(res.LB, digits = 2))  UB $(round(res.UB, digits = 2))  ",
            "gap $(round(100 * res.gap, digits = 3)) %  iterations $(length(res.log))  cuts $(res.n_cuts)  ",
            "time $(round(res.time, digits = 1)) s")

    results = Dict{String,Any}("horizon" => horizon, "max_tender_length" => max_tender_length, "seed" => seed,
                               "theta" => d.θ, "lambda" => d.λ, "u" => d.u, "time_limit" => time_limit,
                               "status" => string(res.status), "LB" => res.LB, "UB" => res.UB, "gap" => res.gap,
                               "n_cuts" => res.n_cuts, "time" => res.time, "phi0" => res.φ0, "log" => res.log)
    if res.best !== nothing
        b = res.best
        ev = evaluate_leader_decision(d, b.Fx, b.Πx, b.Ωx, gurobi_optimizer; φ = b.φ, time_limit)
        results["best"] = Dict("iteration" => b.iteration, "cost" => ev.cost, "phi" => b.φ,
                               "terms" => term_values(ev.terms), "decision" => decision_summary(d, b.Fx, b.Πx, b.Ωx),
                               "producers" => producer_summary(d, ev.model, ev.producers))
        println("Best decision found at iteration $(b.iteration), cost $(round(ev.cost, digits = 2))")
    end
    out = joinpath(results_dir, "vfd_$(tag)T$(horizon)_D$(max_tender_length)_seed$(seed).json")
    open(out, "w") do f
        JSON.print(f, results, 2)
    end
    println("Saved: ", out)
    return results, d, res
end

run_vfd_mmr(; kwargs...) = run_vfd(; horizon = 5, max_tender_length = 3, tag = "MMR_", kwargs...)
run_vfd_original(; kwargs...) = run_vfd(; horizon = 10, max_tender_length = 5, tag = "ORIG_",
    vaccine_data_fn = create_vaccine_data,
    capacity_file = "production_capacity_scenarios_NEW_15YR_NO_MMR.xlsx",
    scenario_file = "scenario_pairs_new_1_scenario_15YR_NO_MMR.json",
    discount_vaccines = ["HPV", "Rotavirus", "PCV"],
    initial_inventory_rate = 1,
    antigen_demand_source = :scenario,
    kwargs...)

if abspath(PROGRAM_FILE) == @__FILE__
    (!isempty(ARGS) && lowercase(ARGS[1]) == "original") ? run_vfd_original() : run_vfd_mmr()
end
