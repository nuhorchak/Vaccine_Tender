#=
Deterministic bilevel tender game — steps 1 and 2 of the build order in
"Bilevel tender game model formulation.pdf":

  1. High-point relaxation (HPR) in Gurobi  -> lower bound v^HPR and a candidate (F, Π, Ω)
  2. Best-response check of that candidate -> bilevel-feasible cost (upper bound on v^BL)
  +  UG baseline (single-level, with ROI (8)) and its schedule evaluated against best responses

Data and helper code are copies of Deterministic/Model Files/Segment Test (unchanged except the
keyword arguments added to initialize_parameters.jl). Steps 3 (MibS) and 4 (value-function
decomposition) are not built yet.
=#
using JuMP
using Gurobi
using Random
using DataFrames, XLSX
import JSON
import MathOptInterface
const MOI = MathOptInterface

const BILEVEL_DIR = @__DIR__
const functions_directory = joinpath(BILEVEL_DIR, "functions")
const data_dir = joinpath(BILEVEL_DIR, "data")
const results_dir = joinpath(BILEVEL_DIR, "results")

# re-used from the deterministic model
include(joinpath(functions_directory, "create_vaccine_data.jl"))
include(joinpath(functions_directory, "create_vaccine_data_MMR_only.jl"))
include(joinpath(functions_directory, "initialize_parameters.jl"))
include(joinpath(functions_directory, "create_check_params.jl"))
include(joinpath(functions_directory, "load_model_starting_points.jl"))
include(joinpath(functions_directory, "deterministic_equivalent.jl"))           # (12) fixed: tender-indexed deliveries
include(joinpath(functions_directory, "deterministic_equivalent_original.jl"))  # unchanged copy, for comparison
# bilevel
include(joinpath(functions_directory, "bilevel_data.jl"))
include(joinpath(functions_directory, "bilevel_model.jl"))
include(joinpath(functions_directory, "bilevel_evaluate.jl"))

const GRB_ENV = Gurobi.Env()
gurobi_optimizer() = Gurobi.Optimizer(GRB_ENV)

term_values(terms) = Dict(string(k) => value(getfield(terms, k)) for k in (:tender, :procurement, :missed, :holding, :total))

function producer_summary(d, model, producers)
    Q, W = model[:Q], model[:W]
    Dict(p => Dict(
        "profit" => value(producers[p].profit),
        "revenue" => value(producers[p].revenue),
        "doses_committed" => sum((value(Q[(v, p), tt, m]) for v in d.V_p[p] for tt in d.F_time_set for m in d.M); init = 0.0),
        "tenders_joined" => [string(tt) for tt in d.F_time_set if value(W[p, tt]) > 0.5],
    ) for p in d.P)
end

function decision_summary(d, Fx, Πx, Ωx)
    Dict(
        "tenders" => [string(a, " ", tt) for a in d.A for tt in d.F_time_set if Fx[a, tt] > 0.5],
        "prices" => [string(v, " t=", t, " λ=", d.λ[k]) for v in d.V for t in d.T for k in d.Kset if Πx[v, t, k] > 0.5],
        "shares" => [string(v, "/", p, " ", tt, " u=", d.u[j]) for (v, p) in d.VP for tt in d.F_time_set
                     for j in d.Jset if Ωx[(v, p), tt, j] > 0.5],
    )
end

function run_bilevel(; horizon = 5, max_tender_length = 3, seed = 1, run_ug_baseline = true,
                     time_limit = 3600.0, tag = "", kwargs...)
    d = load_bilevel_data(data_dir; horizon, max_tender_length, seed, kwargs...)
    println("Instance: |A|=$(length(d.A)) |V|=$(length(d.V)) |P|=$(length(d.P)) |VP|=$(length(d.VP)) windows=$(length(d.F_time_set))")
    println("θ draws: ", d.θ)
    results = Dict{String,Any}("horizon" => horizon, "max_tender_length" => max_tender_length, "seed" => seed,
                               "theta" => d.θ, "lambda" => d.λ, "u" => d.u)

    # ---------- step 1: high-point relaxation ----------
    hpr, hpr_prod, hpr_terms = build_hpr(d, gurobi_optimizer)
    set_optimizer_attribute(hpr, "MIPGap", 1e-4)
    set_time_limit_sec(hpr, time_limit)
    optimize!(hpr)
    println("HPR status: ", termination_status(hpr), "  time: ", round(solve_time(hpr), digits = 1), " s")
    primal_status(hpr) == MOI.FEASIBLE_POINT || error("HPR has no feasible solution: $(termination_status(hpr))")
    v_hpr = objective_value(hpr)
    results["HPR_status"] = string(termination_status(hpr))
    v_hpr_bound = objective_bound(hpr)          # valid lower bound on v^BL even with a MIP gap
    Fx, Πx, Ωx = leader_decision_values(hpr)
    results["HPR"] = Dict("objective" => v_hpr, "bound" => v_hpr_bound, "terms" => term_values(hpr_terms),
                          "decision" => decision_summary(d, Fx, Πx, Ωx),
                          "producers" => producer_summary(d, hpr, hpr_prod))

    # ---------- step 2: best responses to the HPR candidate ----------
    ev = evaluate_leader_decision(d, Fx, Πx, Ωx, gurobi_optimizer; time_limit)
    results["HPR_candidate_bilevel"] = Dict("cost" => ev.cost, "phi" => ev.φ, "terms" => term_values(ev.terms),
                                            "producers" => producer_summary(d, ev.model, ev.producers))

    # ---------- UG baseline (single level, with (8)) and its schedule under best responses ----------
    if run_ug_baseline
        for (key, builder) in (("UG", deterministic_equivalent), ("UG_original12", deterministic_equivalent_original))
            ug = solve_ug_baseline(d, gurobi_optimizer; time_limit, builder)
            println("$key status: ", termination_status(ug), "  time: ", round(solve_time(ug), digits = 1), " s")
            if primal_status(ug) == MOI.FEASIBLE_POINT
                Fu, Πu, Ωu = leader_decision_from_ug(d, ug[:F], ug[:W])
                ev_ug = evaluate_leader_decision(d, Fu, Πu, Ωu, gurobi_optimizer; time_limit)
                results[key] = Dict("objective" => objective_value(ug), "bound" => objective_bound(ug),
                                    "status" => string(termination_status(ug)), "terms" => ug_terms(d, ug),
                                    "decision" => decision_summary(d, Fu, Πu, Ωu),
                                    "bilevel_cost_of_UG_schedule" => ev_ug.cost, "phi" => ev_ug.φ,
                                    "terms_under_best_response" => term_values(ev_ug.terms))
            else
                results[key] = Dict("status" => string(termination_status(ug)))
            end
        end
    end

    # ---------- report ----------
    ub = ev.cost
    println("\n================ Bilevel tender game (deterministic) ================")
    println("HPR objective (v^HPR):            ", round(v_hpr, digits = 2), "   bound: ", round(v_hpr_bound, digits = 2))
    println("Bilevel cost of HPR candidate:    ", round(ub, digits = 2))
    println("Gap (UB − LB)/LB:                 ", round(100 * (ub - v_hpr_bound) / abs(v_hpr_bound), digits = 2), " %")
    for key in ("UG", "UG_original12")
        if haskey(results, key) && haskey(results[key], "objective")
            println(rpad("$key objective (single level):", 34), round(results[key]["objective"], digits = 2))
            println(rpad("$key schedule, best responses:", 34), round(results[key]["bilevel_cost_of_UG_schedule"], digits = 2))
        end
    end
    println("Best-response profits φ_p:        ", Dict(p => round(v, digits = 2) for (p, v) in ev.φ))
    println("HPR leader decision:              ", JSON.json(results["HPR"]["decision"], 2))

    out = joinpath(results_dir, "bilevel_$(tag)T$(horizon)_D$(max_tender_length)_seed$(seed).json")
    open(out, "w") do f
        JSON.print(f, results, 2)
    end
    println("Saved: ", out)
    return results, d
end

# Instance presets -------------------------------------------------------------
# MMR test instance from the formulation note (measles data, T = 5, Δ = 3)
run_mmr(; kwargs...) = run_bilevel(; horizon = 5, max_tender_length = 3, tag = "MMR_", kwargs...)

# EXCURSION: MMR instance with capacity ≈ demand (files built by make_excursion_data.py)
const EXCURSION_MMR = (capacity_file = "EXCURSION_production_capacity_scenarios_MMR_balanced.xlsx",
                       scenario_file = "EXCURSION_scenario_pairs_1_scenario_MMR_balanced.json")
run_mmr_excursion(; kwargs...) = run_mmr(; tag = "EXCURSION_MMR_", EXCURSION_MMR..., kwargs...)

# Original deterministic-model data (Segment Test vaccine_tender_DE_only.jl):
# 13 vaccines incl. Penta/Hexa, 15 producers, NO_MMR 15YR capacity/demand files, T = 10, Δ = 5,
# discounts on HPV/Rotavirus/PCV only, initial inventory rate 1. Vaccine-level d̂ (award ceilings) from the
# 10-year Demand_Scenarios_Base.xlsx, the only file with vaccine-level demand.
run_original(; kwargs...) = run_bilevel(; horizon = 10, max_tender_length = 5, tag = "ORIG_",
    vaccine_data_fn = create_vaccine_data,
    capacity_file = "production_capacity_scenarios_NEW_15YR_NO_MMR.xlsx",
    scenario_file = "scenario_pairs_new_1_scenario_15YR_NO_MMR.json",
    discount_vaccines = ["HPV", "Rotavirus", "PCV"],
    initial_inventory_rate = 1,
    antigen_demand_source = :scenario,
    kwargs...)

# EXCURSION: full data with capacity ≈ demand (files built by `python make_excursion_data.py full`)
const EXCURSION_FULL = (capacity_file = "EXCURSION_production_capacity_scenarios_FULL_balanced.xlsx",
                        scenario_file = "EXCURSION_scenario_pairs_1_scenario_FULL_balanced.json")
run_original_excursion(; kwargs...) = run_original(; tag = "EXCURSION_ORIG_", EXCURSION_FULL..., kwargs...)

if abspath(PROGRAM_FILE) == @__FILE__
    # julia vaccine_tender_bilevel.jl          -> original data
    # julia vaccine_tender_bilevel.jl mmr      -> MMR test instance
    (!isempty(ARGS) && lowercase(ARGS[1]) == "mmr") ? run_mmr() : run_original()
end
