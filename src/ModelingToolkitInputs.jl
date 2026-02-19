module ModelingToolkitInputs
using ModelingToolkit
using SymbolicIndexingInterface
using Setfield
using StaticArrays
using CommonSolve
using SciMLBase

export set_input!, finalize!, Input, InputSystem

struct InputFunctions
    events::Vector{ModelingToolkit.SymbolicDiscreteCallback}
    vars::Vector{SymbolicUtils.BasicSymbolic}
    setters::Vector{SymbolicIndexingInterface.ParameterHookWrapper}
end

"""
    InputSystem(sys::ModelingToolkit.System)
    InputSystem(eqs, args...; kwargs...)

Wraps a `ModelingToolkit.System` object to provide the functions to feed data to discrete variables.  Generate an `InputSystem` either directly in place of a `System` or by wrapping an already generate system.
"""
struct InputSystem
    system::ModelingToolkit.System
    input_functions::Union{InputFunctions,Nothing}
end
InputSystem(system::ModelingToolkit.System, input_functions=nothing) = InputSystem(system, input_functions)
InputSystem(eqs::Union{ModelingToolkit.Equation,Vector{ModelingToolkit.Equation}}, args...; kwargs...) = InputSystem(System(eqs, args...; kwargs...))

get_input_functions(x::InputSystem) = getfield(x, :input_functions)
get_system(x::InputSystem) = getfield(x, :system)
Base.getproperty(x::InputSystem, f::Symbol) = getproperty(get_system(x), f)
Base.propertynames(x::InputSystem) = propertynames(getfield(x, :system))

function Base.show(io::IO, mime::MIME"text/plain", sys::InputSystem)
    println(io, "InputSystem")
    show(io, mime, get_system(sys))
end

equations(sys::InputSystem) = getfield(get_system(sys), :equations)
parameters(sys::InputSystem) = getfield(get_system(sys), :parameters)
unknowns(sys::InputSystem) = getfield(get_system(sys), :unknowns)

for prop in ModelingToolkit.SYS_PROPS
    fname_get = Symbol(:get_, prop)
    fname_has = Symbol(:has_, prop)
    @eval begin
        export $fname_get, $fname_has
        $fname_get(sys::InputSystem) = getfield(get_system(sys), $(QuoteNode(prop)))
        $fname_has(sys::InputSystem) = isdefined(get_system(sys), $(QuoteNode(prop)))
    end
end

function ModelingToolkit.mtkcompile(sys::InputSystem; inputs=Any[], kwargs...)
    sys = mtkcompile(get_system(sys); inputs, kwargs...)
    input_functions = nothing
    if !isempty(inputs)
        sys, input_functions = build_input_functions(sys, inputs)
    end
    return InputSystem(sys, input_functions)
end

struct InputProblem
    prob::ModelingToolkit.ODEProblem
    input_functions::InputFunctions
end

get_prob(x::InputProblem) = getfield(x, :prob)
get_input_functions(x::InputProblem) = getfield(x, :input_functions)
Base.getproperty(x::InputProblem, f::Symbol) = getproperty(get_prob(x), f)

function Base.show(io::IO, mime::MIME"text/plain", sys::InputProblem)
    println(io, "InputProblem")
    show(io, mime, get_prob(sys))
end

function ModelingToolkit.ODEProblem(sys::InputSystem, args...; kwargs...)
    prob = ModelingToolkit.ODEProblem(get_system(sys), args...; kwargs...)
    input_functions = get_input_functions(sys)
    if !isnothing(input_functions)
        return InputProblem(prob, input_functions)
    else
        return prob
    end
end

"""
    Input(var, data, time)

Type used to provide data input for a `InputSystem`
"""
struct Input
    var::Union{Num, Symbolics.Arr{Num, 1}}
    data::SVector
    time::SVector
end

function Input(var, data::Vector, time::Vector)
    n = length(data)
    sdata = SVector{n}(data)
    stime = SVector{n}(time)
    return Input(var, sdata, stime)
end

struct InputIntegrator
    integrator::SciMLBase.DEIntegrator
    input_functions::InputFunctions
end

get_input_functions(x::InputIntegrator) = getfield(x, :input_functions)
get_integrator(x::InputIntegrator) = getfield(x, :integrator)
Base.getproperty(x::InputIntegrator, f::Symbol) = getproperty(get_integrator(x), f)
Base.getindex(x::InputIntegrator, f) = getindex(get_integrator(x), f)
SciMLBase.reinit!(x::InputIntegrator) = reinit!(get_integrator(x))

function Base.show(io::IO, mime::MIME"text/plain", sys::InputIntegrator)
    println(io, "InputIntegrator")
    show(io, mime, get_integrator(sys))
end

CommonSolve.init(input_prob::InputProblem, args...; kwargs...) = InputIntegrator(init(get_prob(input_prob), args...; kwargs...), get_input_functions(input_prob))
CommonSolve.solve!(input_integrator::InputIntegrator) = solve!(get_integrator(input_integrator))
CommonSolve.step!(input_integrator::InputIntegrator, args...; kwargs...) = step!(get_integrator(input_integrator), args...; kwargs...)

# get_input_functions(sys::ModelingToolkit.AbstractSystem) = ModelingToolkit.get_gui_metadata(sys).layout

function set_input!(input_funs::InputFunctions, integrator::SciMLBase.DEIntegrator, var, value::Union{Real, Vector{<:Real}})
    i = findfirst(isequal(var), input_funs.vars)
    setter = input_funs.setters[i]
    event = input_funs.events[i]

    setter(integrator, value)
    ModelingToolkit.save_callback_discretes!(integrator, event)
    u_modified!(integrator, true)
    return nothing
end

"""
    set_input!(input_integrator::InputIntegrator, var, value::Real)

Sets the value of a discrete variable of a `ModelingToolkit` input.  For example

```julia
set_input!(integrator, sys.x, 1.0)
step!(integrator, dt)
```
"""
function set_input!(input_integrator::InputIntegrator, var, value::Union{Real, Vector{<:Real}})
    set_input!(get_input_functions(input_integrator), get_integrator(input_integrator), var, value)
end

function finalize!(input_funs::InputFunctions, integrator)
    for i in eachindex(input_funs.vars)
        ModelingToolkit.save_callback_discretes!(integrator, input_funs.events[i])
    end

    return nothing
end

"""
    finalize!(input_integrator::InputIntegrator)

Saves the final state of all discrete variables.  Call after the final step of the integrator.
"""
finalize!(input_integrator::InputIntegrator) = finalize!(get_input_functions(input_integrator), get_integrator(input_integrator))

function (input_funs::InputFunctions)(integrator, var, value::Union{Real, Vector{<:Real}})
    set_input!(input_funs, integrator, var, value)
end
(input_funs::InputFunctions)(integrator) = finalize!(input_funs, integrator)

function build_input_functions(sys, inputs)

    # Here we ensure the inputs have metadata marking the discrete variables as parameters.  In some
    # cases the inputs can be fed to this function before they are converted to parameters by mtkcompile.
    vars = SymbolicUtils.BasicSymbolic[ModelingToolkit.isparameter(x) ? x : ModelingToolkit.toparam(x)
                                       for x in ModelingToolkit.unwrap.(inputs)]
    setters = []
    events = ModelingToolkit.SymbolicDiscreteCallback[]
    defaults = if pkgversion(ModelingToolkit) > v"11"
        ModelingToolkit.initial_conditions(sys)
    else
        ModelingToolkit.defaults(sys)
    end

    input_functions = nothing
    if !isempty(vars)
        for (j,x) in enumerate(vars)
            affect = ModelingToolkit.ImperativeAffect((m, o, c, i) -> m, modified=(; x))
            sdc = ModelingToolkit.SymbolicDiscreteCallback(Inf, affect)

            push!(events, sdc)

            # ensure that the ODEProblem does not complain about missing parameter map
            if !haskey(defaults, x)
                if inputs[j] isa Symbolics.Arr
                    defaults[x] = zeros(length(inputs[j]))
                else
                    defaults[x] = 0.0
                end                
            end
        end

        @set! sys.discrete_events = events
        @set! sys.index_cache = ModelingToolkit.IndexCache(sys)
        # @set! sys.initial_conditions = initial_conditions

        setters = [SymbolicIndexingInterface.setsym(sys, x) for x in vars]

        input_functions = InputFunctions(events, vars, setters)
    end

    return sys, input_functions
end

function CommonSolve.solve(input_prob::InputProblem, args...; inputs::Vector{Input}, kwargs...)
    tstops = Float64[]

    prob = get_prob(input_prob)
    input_functions = get_input_functions(input_prob)

    # Collect all time points
    for input::Input in inputs
        tstops = union(tstops, input.time)

        # DiscreteCallback doesn't hit on t==0, workaround...
        if input.time[1] == 0
            if pkgversion(ModelingToolkit) > v"11"
                prob.ps[Initial(input.var)] = input.data[1]
            else
                prob.ps[input.var] = input.data[1]
            end
        end
    end

    # Create a single callback that updates all inputs at once
    t_end = prob.tspan[2]
    push!(tstops, t_end)

    condition = (u, t, integrator) -> any(t .== tstops)
    affect! = function (integrator)
        # Update all inputs that have data at the current time
        for input::Input in inputs
            i = findfirst(==(integrator.t), input.time)
            if !isnothing(i)
                @inbounds set_input!(input_functions, integrator, input.var, input.data[i])
            end
        end

        # Finalize if at the end
        if integrator.t == t_end
            finalize!(input_functions, integrator)
        end
    end

    callback = DiscreteCallback(condition, affect!, save_positions = (false, false))

    return solve(prob, args...; tstops, callback, kwargs...)
end


end # module ModelingToolkitInputs
