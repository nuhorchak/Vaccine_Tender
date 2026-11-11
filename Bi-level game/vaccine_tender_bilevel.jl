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
include(joinpath(functions_directory, "deterministic_equivalent.jl"))
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

function run_bilevel(; horizon = 5, max_tender_length = 3, seed = 1, run_ug_baseline = true, kwargs...)
    d = load_bilevel_data(data_dir; horizon, max_tender_length, seed, kwargs...)
    println("θ draws: ", d.θ)
    results = Dict{String,Any}("horizon" => horizon, "max_tender_length" => max_tender_length, "seed" => seed,
                               "theta" => d.θ, "lambda" => d.λ, "u" => d.u)

    # ---------- step 1: high-point relaxation ----------
    hpr, hpr_prod, hpr_terms = build_hpr(d, gurobi_optimizer)
    set_optimizer_attribute(hpr, "MIPGap", 1e-4)
    optimize!(hpr)
    println("HPR status: ", termination_status(hpr))
    termination_status(hpr) == MOI.OPTIMAL || error("HPR not solved to optimality")
    v_hpr = objective_value(hpr)
    v_hpr_bound = objective_bound(hpr)          # valid lower bound on v^BL even with a MIP gap
    Fx, Πx, Ωx = leader_decision_values(hpr)
    results["HPR"] = Dict("objective" => v_hpr, "bound" => v_hpr_bound, "terms" => term_values(hpr_terms),
                          "decision" => decision_summary(d, Fx, Πx, Ωx),
                          "producers" => producer_summary(d, hpr, hpr_prod))

    # ---------- step 2: best responses to the HPR candidate ----------
    ev = evaluate_leader_decision(d, Fx, Πx, Ωx, gurobi_optimizer)
    results["HPR_candidate_bilevel"] = Dict("cost" => ev.cost, "phi" => ev.φ, "terms" => term_values(ev.terms),
                                            "producers" => producer_summary(d, ev.model, ev.producers))

    # ---------- UG baseline (single level, with (8)) and its schedule under best responses ----------
    if run_ug_baseline
        ug = solve_ug_baseline(d, gurobi_optimizer)
        println("UG status: ", termination_status(ug))
        if primal_status(ug) == MOI.FEASIBLE_POINT
            Fu, Πu, Ωu = leader_decision_from_ug(d, ug[:F], ug[:W])
            ev_ug = evaluate_leader_decision(d, Fu, Πu, Ωu, gurobi_optimizer)
            results["UG"] = Dict("objective" => objective_value(ug), "decision" => decision_summary(d, Fu, Πu, Ωu),
                                 "bilevel_cost_of_UG_schedule" => ev_ug.cost, "phi" => ev_ug.φ,
                                 "terms_under_best_response" => term_values(ev_ug.terms))
        else
            results["UG"] = Dict("status" => string(termination_status(ug)))
        end
    end

    # ---------- report ----------
    ub = ev.cost
    println("\n================ Bilevel tender game (deterministic) ================")
    println("HPR objective (v^HPR):            ", round(v_hpr, digits = 2), "   bound: ", round(v_hpr_bound, digits = 2))
    println("Bilevel cost of HPR candidate:    ", round(ub, digits = 2))
    println("Gap (UB − LB)/LB:                 ", round(100 * (ub - v_hpr_bound) / abs(v_hpr_bound), digits = 2), " %")
    if haskey(results, "UG") && haskey(results["UG"], "objective")
        println("UG objective (single level, (8)): ", round(results["UG"]["objective"], digits = 2))
        println("UG schedule under best responses: ", round(results["UG"]["bilevel_cost_of_UG_schedule"], digits = 2))
    end
    println("Best-response profits φ_p:        ", Dict(p => round(v, digits = 2) for (p, v) in ev.φ))
    println("HPR leader decision:              ", JSON.json(results["HPR"]["decision"], 2))

    out = joinpath(results_dir, "bilevel_T$(horizon)_D$(max_tender_length)_seed$(seed).json")
    open(out, "w") do f
        JSON.print(f, results, 2)
    end
    println("Saved: ", out)
    return results, d
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_bilevel(horizon = 5, max_tender_length = 3, seed = 1)
end
