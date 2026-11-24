#=
Diagnostics capture: collects every warning and error from one run into a single text file.

Sources collected:
  * Julia log records at level Warn or above (@warn, @error, depwarns when Julia is started with
    --depwarn=yes, and package warnings from JuMP / MOI / BilevelJuMP). Each occurrence is written,
    even when the console stops showing it because of `maxlog`.
  * Uncaught exceptions, with stack trace.
  * The Gurobi log: `quiet!` replaces `set_silent`, so while capture is on Gurobi writes its full
    log to a file instead of being silenced. Lines containing "warning" or "error" are copied over.
  * MibS: full stderr, the exit code, and stdout lines that look like warnings or errors.
=#
using Logging

const DIAG_GUROBI_LOG = Ref{Union{Nothing,String}}(nothing)   # set while capture is on

"""
    quiet!(model)

`set_silent` normally. While diagnostics capture is on, Gurobi output goes to the log file instead
(not the console), so its warnings are kept.
"""
function quiet!(model)
    path = DIAG_GUROBI_LOG[]
    if path === nothing
        set_silent(model)
    else
        set_optimizer_attribute(model, "OutputFlag", 1)
        set_optimizer_attribute(model, "LogToConsole", 0)
        set_optimizer_attribute(model, "LogFile", path)
    end
    return model
end

"""
Logger that appends every Warn/Error record to `io` (flushed immediately, so a crash keeps it)
and forwards everything to the console logger.
"""
struct DiagnosticLogger <: AbstractLogger
    io::IO
    console::AbstractLogger
    counts::Dict{LogLevel,Int}
end

Logging.min_enabled_level(l::DiagnosticLogger) = min(Logging.Warn, Logging.min_enabled_level(l.console))
Logging.shouldlog(::DiagnosticLogger, args...) = true
Logging.catch_exceptions(::DiagnosticLogger) = true

function Logging.handle_message(l::DiagnosticLogger, level, message, _module, group, id, file, line; kwargs...)
    if level >= Logging.Warn
        l.counts[level] = get(l.counts, level, 0) + 1
        println(l.io, "[", uppercase(string(level)), "] ", _module, "  ", something(file, "?"), ":", something(line, "?"))
        for s in split(string(message), '\n')
            println(l.io, "    ", s)
        end
        for (k, v) in kwargs
            k == :maxlog && continue
            println(l.io, "    ", k, " = ", v)
        end
        println(l.io)
        flush(l.io)
    end
    console = l.console
    if level >= Logging.min_enabled_level(console) &&
       Logging.shouldlog(console, level, _module, group, id)
        Logging.handle_message(console, level, message, _module, group, id, file, line; kwargs...)
    end
    return nothing
end

const DIAG_PATTERN = r"warn|error|fail|abort|numeric|unbounded|segmentation|exception|unexpected|termcode|recover"i

"""
    append_matching_lines(io, title, path; pattern = DIAG_PATTERN, full = false)

Copy lines of `path` that match `pattern` (or the whole file if `full`) into the report with line numbers.
"""
function append_matching_lines(io, title, path; pattern = DIAG_PATTERN, full = false)
    println(io, "="^100)
    println(io, title, "   (", path, ")")
    println(io, "="^100)
    if !isfile(path)
        println(io, "  (file not found)\n")
        return 0
    end
    n = 0
    for (i, line) in enumerate(eachline(path))
        if full || occursin(pattern, line)
            println(io, lpad(i, 7), ": ", line)
            n += 1
        end
    end
    n == 0 && println(io, "  (nothing)")
    println(io)
    return n
end

"""
    with_diagnostics(f, report_path; gurobi_log, mibs_dir = nothing)

Runs `f()` with every warning/error captured in `report_path`. The Gurobi log goes to `gurobi_log`;
if `mibs_dir` is given, the MibS stderr/stdout files written there are scanned at the end.
"""
function with_diagnostics(f, report_path::String; gurobi_log::String, mibs_dir = nothing)
    mkpath(dirname(report_path))
    mkpath(dirname(gurobi_log))
    isfile(gurobi_log) && rm(gurobi_log)            # one run per log
    io = open(report_path, "w")
    println(io, "Diagnostics for run started ", Libc.strftime("%Y-%m-%d %H:%M:%S", time()))
    println(io, "Julia ", VERSION, "   depwarn = ", Base.JLOptions().depwarn == 0 ? "off (start Julia with --depwarn=yes to include deprecations)" : "on")
    println(io, "Gurobi log: ", gurobi_log)
    println(io)
    println(io, "="^100)
    println(io, "Julia warnings and errors (in order)")
    println(io, "="^100)
    flush(io)

    logger = DiagnosticLogger(io, current_logger(), Dict{LogLevel,Int}())
    DIAG_GUROBI_LOG[] = gurobi_log
    result = nothing
    failure = nothing
    try
        result = with_logger(f, logger)
    catch err
        failure = (err, catch_backtrace())
    finally
        DIAG_GUROBI_LOG[] = nothing
    end

    if failure !== nothing
        println(io, "[UNCAUGHT EXCEPTION]")
        showerror(io, failure[1], failure[2])
        println(io, "\n")
    end
    isempty(logger.counts) && failure === nothing && println(io, "  (none)\n")

    n_grb = append_matching_lines(io, "Gurobi log lines with warning/error", gurobi_log; pattern = r"warning|error"i)
    n_err = n_out = 0
    if mibs_dir !== nothing
        n_err = append_matching_lines(io, "MibS stderr (full)", joinpath(mibs_dir, "mibs_errors.txt"); full = true)
        n_out = append_matching_lines(io, "MibS stdout lines matching $(DIAG_PATTERN.pattern)", joinpath(mibs_dir, "mibs_output.txt"))
    end

    println(io, "="^100)
    println(io, "Summary")
    println(io, "="^100)
    println(io, "Julia warnings:      ", get(logger.counts, Logging.Warn, 0))
    println(io, "Julia errors:        ", get(logger.counts, Logging.Error, 0))
    println(io, "Uncaught exception:  ", failure === nothing ? "no" : "yes")
    println(io, "Gurobi log lines:    ", n_grb)
    mibs_dir === nothing || println(io, "MibS stderr lines:   ", n_err, "\nMibS stdout matches: ", n_out)
    close(io)
    println("Diagnostics written to: ", report_path)

    failure === nothing || throw(failure[1])
    return result
end
