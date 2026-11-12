#=
Step 3 of the build order: exact solve of the bilevel tender game with MibS through BilevelJuMP.

The model re-uses the same blocks as the HPR / best-response code:
  Upper(bm): add_leader_design!, add_leader_state!, add_inventory_balance!, leader objective
  Lower(bm): add_followers! for every producer, objective = Σ_p profit_p
Because producers share no constraint, maximising the summed profit gives the same responses as
maximising each producer separately (single-follower equivalent, eq. (42) in the companion note).

MibS driver notes (BilevelJuMP v0.6.3 + MibS_jll 1.2.x on Windows):
  * BilevelJuMP.solve_with_MibS refuses any continuous variable; MibS itself accepts continuous variables
    as long as linking variables (F, Π, Ω) are integer, so we call the internal builders with the check off.
  * This MibS build prints `name = value`, which BilevelJuMP's parser does not read, so we rename every
    column/row to an MPS-safe name and parse the output ourselves.
=#

"""
    build_bilevel_jump(d) -> (bm, producers, terms)

BilevelJuMP model of the tender game.
"""
function build_bilevel_jump(d)
    bm = BilevelModel()
    U, L = Upper(bm), Lower(bm)
    add_leader_design!(U, d)
    add_leader_state!(U, d)
    producers = add_followers!(L, d, collect(d.P), bm[:F], bm[:Π], bm[:Ω])
    add_inventory_balance!(U, d)
    terms = leader_cost_terms(U, d, bm[:F], producers)
    @objective(U, Min, terms.total)
    @objective(L, Max, sum(producers[p].profit for p in d.P))
    return bm, producers, terms
end

"""
    solve_with_mibs(bm; time_limit, work_dir, mibs_options) -> NamedTuple

Writes the MPS + auxiliary file, runs MibS and parses the result.
Returns (status, objective, values::Dict{name=>value}, output, n_upper, n_lower, n_lower_rows).
`status` is :optimal, :feasible (time limit with an incumbent) or :no_solution.
"""
function solve_with_mibs(bm; time_limit::Real = 3600, work_dir::String = mktempdir(),
                         mibs_options::Vector{String} = String[])
    mkpath(work_dir)
    mps = joinpath(work_dir, "model.mps")
    aux = joinpath(work_dir, "model.aux")

    nm, lower_vars, lower_obj, lower_rows, lower_sense = BilevelJuMP._build_single_model(bm, false)

    # MPS-safe names: columns v1..vn (remember the JuMP name), rows r1..rm
    safe_to_name = Dict{String,String}()
    for (i, vi) in enumerate(MOI.get(nm, MOI.ListOfVariableIndices()))
        safe = "v$i"
        safe_to_name[safe] = MOI.get(nm, MOI.VariableName(), vi)
        MOI.set(nm, MOI.VariableName(), vi, safe)
    end
    r = 0
    for (F, S) in MOI.get(nm, MOI.ListOfConstraintTypesPresent())
        F == MOI.VariableIndex && continue
        for ci in MOI.get(nm, MOI.ListOfConstraintIndices{F,S}())
            r += 1
            MOI.set(nm, MOI.ConstraintName(), ci, "r$r")
        end
    end

    MOI.write_to_file(nm, mps)
    # BilevelJuMP's aux writer assumes rows are written ≥, ≤, =; the MOI MPS writer uses a different order,
    # so take row/column positions from the MPS file actually written.
    write_mibs_aux(nm, mps, aux, lower_vars, lower_obj, lower_rows, lower_sense)

    out_file = joinpath(work_dir, "mibs_output.txt")
    err_file = joinpath(work_dir, "mibs_errors.txt")
    # MibS cannot read paths containing spaces, so run inside work_dir with relative file names
    args = ["-Alps_instance", "model.mps", "-MibS_auxiliaryInfoFile", "model.aux",
            "-Alps_timeLimit", string(time_limit), mibs_options...]
    cd(work_dir) do
        MibS_jll.mibs() do exe
            run(pipeline(Cmd([exe; args]); stdout = out_file, stderr = err_file); wait = true)
        end
    end
    output = read(out_file, String)
    errors = read(err_file, String)
    isempty(strip(errors)) || @warn "MibS wrote to stderr:\n$errors"

    # parse: "Optimal solution:" (or another "...solution..." header) then "Cost = ..." and "name = value" lines
    status = occursin("Optimal solution", output) ? :optimal : :no_solution
    objective = NaN
    values = Dict{String,Float64}()
    in_solution = false
    for line in split(output, '\n')
        s = strip(line)
        if !in_solution
            if occursin(r"solution"i, s) && endswith(s, ":")
                in_solution = true
            end
            continue
        end
        if (m = match(r"^Cost\s*=\s*(\S+)", s)) !== nothing
            objective = parse(Float64, m[1])
        elseif (m = match(r"^(v\d+)\s*=\s*(\S+)$", s)) !== nothing
            values[safe_to_name[m[1]]] = parse(Float64, m[2])
        end
    end
    if status == :no_solution && !isnan(objective)
        status = :feasible
    end
    # MibS lower bound: last row of the progress table ("Nodes Done  Upper Bound  Lower Bound  Gap ...")
    bound = NaN
    for line in split(output, '\n')
        tok = split(strip(line))
        if length(tok) >= 5 && all(t -> tryparse(Float64, t) !== nothing, tok[[1, 2, 3]]) && endswith(tok[4], "%")
            bound = parse(Float64, tok[3])
        end
    end
    m = match(r"Relative optimality gap is ([0-9.]+)%", output)
    gap = m === nothing ? NaN : parse(Float64, m[1]) / 100
    status == :optimal && (bound = objective; gap = 0.0)
    return (status = status, objective = objective, bound = bound, gap = gap, values = values, output = output,
            n_upper = MOI.get(nm, MOI.NumberOfVariables()) - length(lower_vars),
            n_lower = length(lower_vars), n_lower_rows = length(lower_rows), work_dir = work_dir)
end

"""
    write_mibs_aux(nm, mps, aux, lower_vars, lower_obj, lower_rows, lower_sense)

MibS auxiliary file (N, M, LC, LR, LO, OS) with 0-based column/row positions read from the MPS file.
"""
function write_mibs_aux(nm, mps, aux, lower_vars, lower_obj, lower_rows, lower_sense)
    row_pos = Dict{String,Int}()
    col_pos = Dict{String,Int}()
    section = ""
    for line in eachline(mps)
        isempty(strip(line)) && continue
        if !startswith(line, " ")
            section = split(line)[1]
            continue
        end
        tok = split(line)
        if section == "ROWS"
            tok[1] == "N" && continue                      # objective row is not a constraint
            row_pos[tok[2]] = length(row_pos)
        elseif section == "COLUMNS"
            (length(tok) >= 2 && occursin("MARKER", tok[2])) && continue
            haskey(col_pos, tok[1]) || (col_pos[tok[1]] = length(col_pos))
        end
    end
    nvars = MOI.get(nm, MOI.NumberOfVariables())
    length(col_pos) == nvars || error("MPS has $(length(col_pos)) columns but the model has $nvars variables")

    coef = Dict{MOI.VariableIndex,Float64}(x => 0.0 for x in lower_vars)
    for term in lower_obj.terms
        haskey(coef, term.variable) && (coef[term.variable] += term.coefficient)
    end
    open(aux, "w") do io
        println(io, "N $(length(lower_vars))")
        println(io, "M $(length(lower_rows))")
        for x in lower_vars
            println(io, "LC $(col_pos[MOI.get(nm, MOI.VariableName(), x)])")
        end
        for ci in lower_rows
            println(io, "LR $(row_pos[MOI.get(nm, MOI.ConstraintName(), ci)])")
        end
        for x in lower_vars
            println(io, "LO $(coef[x])")
        end
        println(io, "OS ", lower_sense == MOI.MAX_SENSE ? -1 : 1)
    end
    return
end

"""
    leader_decision_from_mibs(bm, values) -> (Fx, Πx, Ωx)

Rounded leader decisions from MibS output (variables MibS does not print are zero).
"""
function leader_decision_from_mibs(bm, values)
    val(v) = round(get(values, name(v), 0.0))
    return val.(bm[:F]), val.(bm[:Π]), val.(bm[:Ω])
end
