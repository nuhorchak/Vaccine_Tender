"""
    load_bilevel_data(data_dir; kwargs...)

Builds every set and parameter for the deterministic bilevel tender game
("Bilevel tender game: model formulation", Oct 26 2026).

Re-uses the Segment Test loaders (create_vaccine_data*, initialize_parameters,
create_check_params, load_model_starting_points) and adds the bilevel-only data:

- K, λ_k, ρ_vtk = λ_k r̄_vt       price ladder
- J, u_j                         award-share levels
- d̂_vt, D̂_vtτ                    vaccine-level demand forecast and tender volume
- c_vp = θ_p r̄_v                 synthetic per-dose production cost

All quantities are divided by `unit` (default 1000) exactly as in the deterministic model.
Returns a NamedTuple `d` used by every bilevel model builder.
"""
function load_bilevel_data(data_dir::String;
    vaccine_data_fn = create_vaccine_data_MMR_only,
    horizon::Int = 5,
    max_tender_length::Int = 3,
    unit::Int = 1000,
    scaled_capacity::Int = 1,
    allowable_capacity_increase_number::Int = 1,
    initial_inventory_rate::Int = 0,
    capacity_file::String = "production_capacity_scenarios_NEW_6OCT.xlsx",
    price_file::String = "Vaccine_price_data_15YR.xlsx",
    scenario_file::String = "scenario_pairs_new_1_scenario_6OCT.json",
    vaccine_demand_file::String = "Demand_Scenarios_Base.xlsx",
    vaccine_demand_sheet::String = "Medium_Demand_calc",
    antigen_demand_source::Symbol = :scenario,     # :scenario -> antigen demand from scenario_file (same as deterministic model) ; :vaccine -> d_at = Σ_{v∈V_a} d̂_vt
    fix_starting_tenders::Bool = true,             # keep the F_start tenders from Starting_point.xlsx (as in the DE model)
    discount_vaccines::Union{Nothing,Vector} = nothing,  # vaccines with bracket discounts; nothing -> all of V
    discount_structure::Symbol = :all_unit,        # :all_unit -> ζ_m on every dose once Q reaches bracket m;
                                                   # :incremental -> ζ_m only on the doses inside bracket m
    λ::Vector{Float64} = [0.98, 1.0, 1.02],        # price ladder: ±2% around the reference price r̄_vt
    u::Vector{Float64} = [0.0, 0.5, 1.0],
    θ_range::Dict{String,Tuple{Float64,Float64}} = Dict(
        "Large" => (0.20, 0.30), "Medium" => (0.25, 0.35), "Small" => (0.30, 0.40)),   # half the PDF placeholders
    seed::Int = 1,
    per_dose_cost::Bool = true,                    # false -> c_vp = 0: producer cost is only f (W) and Γ (L), as in the UG ROI
    dose_scale::Real = 1,                          # >1: rescale doses for conditioning (see rescale_doses); objective unchanged
)
    discount_structure in (:all_unit, :incremental) ||
        error("discount_structure must be :all_unit or :incremental, got :$discount_structure")

    # ---------------- sets (re-used) ----------------
    A, V, A_v, P, P_v, V_a, V_p, P_a, A_p, capacity_category, vaccine_category, antigen_category = vaccine_data_fn()

    target_vaccines = discount_vaccines === nothing ? collect(V) : discount_vaccines

    # ---------------- parameters (re-used) ----------------
    T, T_initial, Δ, s_real, r, r_avg, r_producer_avg, g, h, l, f_profit, Γ, F_time_set, κ,
    L_lower_number, L_upper_number, delta, beta, zeta_vm, phi_vm_lower, phi_vm_upper, m_segments =
        initialize_parameters(data_dir, unit, scaled_capacity, horizon, max_tender_length, P, V, P_v, V_p,
                              allowable_capacity_increase_number, 1, 1;
                              capacity_file = capacity_file, price_file = price_file,
                              target_vaccines = target_vaccines)
    F_time_set = Tuple{Int,Int}[(t, τ) for (t, τ) in F_time_set]
    M = collect(eachindex(m_segments))

    X_tilde_lower, X_tilde_upper, L_ddot_lower, L_ddot_upper, L_hat_lower, L_hat_upper, L_check_lower, L_check_upper =
        create_check_params(V, P, P_v, T, F_time_set, s_real, κ, L_upper_number)

    starting_F, starting_I, starting_S = load_model_starting_points(data_dir, initial_inventory_rate, unit, A, V)
    starting_F = fix_starting_tenders ?
        [(a, Int(t), Int(τ)) for (a, t, τ) in starting_F if (Int(t), Int(τ)) in F_time_set] : Tuple{String,Int,Int}[]

    # ---------------- per-period capacity s_pt (deterministic, from the 1-scenario file) ----------------
    scen = JSON.parsefile(joinpath(data_dir, scenario_file))
    scen = scen[first(sort(collect(keys(scen))))]
    s_pt = Dict((p, t) => round(scen["capacity"]["$t"][p] * scaled_capacity / unit, digits = 2) for p in P, t in T)

    # ---------------- vaccine-level demand d̂_vt ----------------
    sheet = XLSX.readxlsx(joinpath(data_dir, vaccine_demand_file))[vaccine_demand_sheet][:]
    d_hat = Dict{Tuple{String,Int},Float64}()
    for v in V
        row = findfirst(i -> !ismissing(sheet[i, 1]) && string(sheet[i, 1]) == v, 1:size(sheet, 1))
        row === nothing && error("Vaccine $v not found in $vaccine_demand_file/$vaccine_demand_sheet")
        for t in T
            col = findfirst(j -> !ismissing(sheet[1, j]) && string(sheet[1, j]) == string(t), 1:size(sheet, 2))
            col === nothing && error("Year $t not found in $vaccine_demand_file/$vaccine_demand_sheet")
            d_hat[(v, t)] = round(Float64(sheet[row, col]) / unit, digits = 2)
        end
    end
    D_hat = Dict((v, tt) => sum(d_hat[(v, l)] for l in tt[1]:tt[2]) for v in V, tt in F_time_set)

    # ---------------- antigen demand d_at ----------------
    d_at = Dict{Tuple{String,Int},Float64}()
    for a in A, t in T
        d_at[(a, t)] = antigen_demand_source == :vaccine ?
            sum(d_hat[(v, t)] for v in V_a[a]) :
            round(scen["demand"]["$t"][a] / unit, digits = 2)
    end

    # ---------------- price ladder, award shares ----------------
    Kset = collect(eachindex(λ))
    Jset = collect(eachindex(u))
    ρ = Dict((v, t, k) => λ[k] * r_avg[v, t] for v in V, t in T, k in Kset)

    # ---------------- synthetic production cost c_vp = θ_p r̄_v ----------------
    size_group = Dict(p => cat for (cat, ps) in capacity_category for p in ps)
    rng = Random.MersenneTwister(seed)
    θ = Dict{String,Float64}()
    for p in P
        lo, hi = θ_range[get(size_group, p, "Medium")]
        θ[p] = round(lo + (hi - lo) * rand(rng), digits = 4)
    end
    r_bar = Dict(v => sum(r_avg[v, t] for t in T) / length(T) for v in V)
    c = Dict((v, p) => (per_dose_cost ? θ[p] * r_bar[v] : 0.0) for v in V for p in P_v[v])

    # sanity check: someone must earn a positive margin at the top price after the deepest discount
    for v in V
        best = maximum(maximum(λ) * r_bar[v] * (1 - maximum(zeta_vm[v, m] for m in M)) - c[(v, p)] for p in P_v[v])
        best <= 0 && @warn "No producer of $v has a positive margin at the top ladder price after the deepest discount."
    end

    # bracket upper bounds: the data uses a 1e35 sentinel; cap it at the largest feasible commitment (big-M hygiene)
    phi_upper_cap = Dict((v, t, m) => min(phi_vm_upper[v, m],
                         sum(D_hat[(v, tt)] for tt in F_time_set if tt[1] == t; init = 0.0)) for v in V, t in T, m in M)

    VP = [(v, p) for v in V for p in P_v[v]]
    I0 = Dict(v => 0.0 for v in V); for (v, amt) in starting_I; I0[v] = amt; end
    S0 = Dict(a => 0.0 for a in A); for (a, amt) in starting_S; S0[a] = Float64(amt); end

    d = (; A, V, A_v, P, P_v, V_a, V_p, P_a, A_p, VP, capacity_category, size_group,
           T, T_initial, F_time_set, M, Kset, Jset, λ, u,
           s_real, s_pt, r, r_avg, r_bar, ρ, c, θ, g, h, l, f_profit, Γ, κ, L_lower_number, L_upper_number,
           delta, beta, zeta_vm, phi_vm_lower, phi_vm_upper, phi_upper_cap, m_segments,
           L_ddot_upper, L_hat_upper, L_check_upper, X_tilde_upper,
           d_hat, D_hat, d_at, I0, S0, starting_F, unit, seed, discount_structure, dose_scale = 1.0)
    return dose_scale == 1 ? d : rescale_doses(d, dose_scale)
end

"""
    rescale_doses(d, σ) -> d′

Change of units for numerical conditioning: every dose quantity is divided by σ and every per-dose
price/cost is multiplied by σ, so every model term (and the objective value) is unchanged in money.
Fixed costs (g, Γ, f) and dimensionless data (κ, ζ, λ, u, δ, h) are untouched.
Quantity variables (Q, X, I, Vc, S, ...) come out in units of `d.unit * σ` doses.
Only the bilevel blocks (HPR, best response, MibS, VFD) are covered; `l` and the UG baseline are not rescaled.
"""
function rescale_doses(d, σ::Real)
    σ = Float64(σ)
    q(D) = Dict(k => v / σ for (k, v) in D)          # quantity
    p(D) = Dict(k => v * σ for (k, v) in D)          # money per dose
    return merge(d, (;
        s_real = q(d.s_real), s_pt = q(d.s_pt), d_hat = q(d.d_hat), D_hat = q(d.D_hat), d_at = q(d.d_at),
        phi_vm_lower = q(d.phi_vm_lower), phi_vm_upper = q(d.phi_vm_upper), phi_upper_cap = q(d.phi_upper_cap),
        L_ddot_upper = q(d.L_ddot_upper), L_hat_upper = q(d.L_hat_upper), L_check_upper = q(d.L_check_upper),
        X_tilde_upper = q(d.X_tilde_upper), I0 = q(d.I0), S0 = q(d.S0),
        r = p(d.r), r_avg = p(d.r_avg), r_bar = p(d.r_bar), ρ = p(d.ρ), c = p(d.c), beta = d.beta * σ,
        unit = d.unit * σ, dose_scale = d.dose_scale * σ))
end

"""
    bracket_widths(d, v, t) -> Dict(m => w_m)

Incremental discounts: width of bracket m for vaccine v at period t, i.e. the doses priced at ζ_m.
Breakpoints are the bracket lower bounds φ_m (phi_vm_lower), so w_m = φ_{m+1} − φ_m, and the last bracket
runs up to the largest commitment possible at t (phi_upper_cap). Widths are clipped at that cap, so a
bracket that starts above it has width 0.
"""
function bracket_widths(d, v, t)
    Ms = sort(d.M)
    cap = d.phi_upper_cap[(v, t, last(Ms))]
    w = Dict{eltype(Ms),Float64}()
    for (i, m) in enumerate(Ms)
        hi = i < length(Ms) ? min(d.phi_vm_lower[v, Ms[i+1]], cap) : cap
        w[m] = max(0.0, hi - min(d.phi_vm_lower[v, m], cap))
    end
    return w
end
