# ModelingToolkitInputs.jl

ModelingToolkitInputs.jl provides support for driving `ModelingToolkit` model inputs with data in determinate (data known upfront) and indeterminate form (data streamed at runtime).

## Installation

```julia
using Pkg
Pkg.add("ModelingToolkitInputs")
```

## Real-time Input Handling During Simulation

ModelingToolkit supports setting input values during simulation for variables marked with the `[input=true]` metadata. This is useful for real-time simulations, hardware-in-the-loop testing, interactive simulations, or any scenario where input values need to be determined during integration rather than specified beforehand.

To use this functionality, variables must be marked as inputs using the `[input=true]` metadata and specified in the `inputs` keyword argument of `@mtkcompile` and then followed by a call to `build_input_functions`.

There are two approaches to handling inputs during simulation:

### Determinate Form: Using `Input` Objects

When all input values are known beforehand, you can use the [`Input`] type to specify input values at specific time points. The solver will automatically apply these values using discrete callbacks.

```@example inputs
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using ModelingToolkitInputs
using OrdinaryDiffEq
using Plots

# Define system with an input variable
@variables x(t) [input=true]
@variables y(t) = 0

eqs = [D(y) ~ x]

# Compile with inputs specified
@mtkcompile sys=InputSystem(eqs, t, [x, y], []) inputs=[x]

prob = ODEProblem(sys, [], (0, 4))

# Create an Input object with predetermined values
input = Input(sys.x, [1, 2, 3, 4], [0, 1, 2, 3])

# Solve with the input - solver handles callbacks automatically
sol = solve(prob, [input], Tsit5())

plot(sol; idxs = [x, y])
```

Multiple `Input` objects can be passed in a vector to handle multiple input variables simultaneously.

### Indeterminate Form: Manual Input Setting with `set_input!`

When input values need to be computed on-the-fly or depend on external data sources, you can manually set inputs during integration using [`set_input!`]. This approach requires explicit control of the integration loop.

```@example inputs
# Initialize the integrator
integrator = init(prob, Tsit5())

# Manually set inputs and step through time
set_input!(integrator, sys.x, 1.0)
step!(integrator, 1.0, true)

set_input!(integrator, sys.x, 2.0)
step!(integrator, 1.0, true)

set_input!(integrator, sys.x, 3.0)
step!(integrator, 1.0, true)

set_input!(integrator, sys.x, 4.0)
step!(integrator, 1.0, true)

# IMPORTANT: Must call finalize! to save all input callbacks
finalize!(integrator)

plot(sol; idxs = [x, y])
```

!!! warning "Always call `finalize!`"
    
    When using `set_input!`, you must call [`finalize!`] after integration is complete. This ensures that all discrete callbacks associated with input variables are properly saved in the solution. Without this call, input values may not be correctly recorded when querying the solution.

## Benefits of ModelingToolkitInputs vs. DataInterpolations
There are several reasons why one would want to input data into their model using `ModelingToolkitInputs`:
1. The same `System` (or `InputSystem`) can be used in both determinate and indeterminate forms without requiring any changes or modifications to the system.  This makes it very convenient to use and test the system against previously recorded data and be sure the exact same system will work in practice with streaming data, as one example use case.
2. Run several large datasets using `ModelingToolkitInputs` requires only 1 step: call `solve` with each dataset.  When the data is included in the system using an interpolation object requires 2 steps: `remake` the problem with new data, then solve.  
3. The 2 step process described above is significantly slower than the signal step solve with `ModelingToolkitInputs`
4. Finally using Interpolation requires that the data length be a constant.

```@example comparison
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using ModelingToolkitInputs
using ModelingToolkitStandardLibrary.Blocks
using DataInterpolations
using OrdinaryDiffEq
using Plots

function MassSpringDamper(; name)
    
    vars = @variables begin
        f(t), [input = true] 
        x(t)=0 
        dx(t)=0
        ddx(t)
    end
    pars = @parameters m=10 k=1000 d=1

    eqs = [ddx * 10 ~ k * x + d * dx + f
           D(x) ~ dx
           D(dx) ~ ddx
           ]

    System(eqs, t, vars, pars; name)
end

function MassSpringDamperSystem(data, time; name)
    @named src = ParametrizedInterpolation(ConstantInterpolation, data, time)
    @named clk = ContinuousClock()
    @named model = MassSpringDamper()

    eqs = [model.f ~ src.output.u
           connect(clk.output, src.input)]

    System(eqs, t; name, systems = [src, clk, model])
end

dt = 4e-4
time = collect(0:dt:0.1)
data = sin.(2 * pi * time * 100)

@mtkcompile sys = MassSpringDamperSystem(data, time)
prob = ODEProblem(sys, [], (0, time[end]))
@time sol = solve(prob);
plot(sol; idxs=sys.model.dx)
```

Now let's record how much time it takes to replace the data.

```@example comparison
using BenchmarkTools
data2 = ones(length(data))
@btime begin 
    prob2 = remake(prob, p = [sys.src.data => data2])
    sol2 = solve(prob2)
end;
```

As can be seen, this takes over 300ms to run a new dataset.  In comparison using `ModelingToolkitInputs` only takes just over 1ms for each dataset run.  Additionally note, we can run the `MassSpringDamper` component directly without needing to wrap it in another component, making it very simple to run in determiniate or indeterminate forms.  

```@example comparison
@named sys = MassSpringDamper()
sys = mtkcompile(InputSystem(sys); inputs=ModelingToolkit.inputs(sys))
prob = ODEProblem(sys, [], (0, time[end]))

in1 = Input(sys.f, data, time)
in2 = Input(sys.f, data2, time)

@btime sol1 = solve(prob, [in1]);
@btime sol2 = solve(prob, [in2]);
```
