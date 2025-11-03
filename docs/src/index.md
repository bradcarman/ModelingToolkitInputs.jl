# ModelingToolkitInputs.jl

ModelingToolkitInputs.jl provides support for driving `ModelingToolkit` model inputs with data in determinate (data known upfront) and indeterminate form (data streamed at runtime).

## Installation

```julia
using Pkg
Pkg.add("ModelingToolkitInputs")
```

## Getting Started
In `ModelingToolkit` it is possible to mark a variable as an input, as follows

```julia
@variables x(t) [input=true]
```

When compiling the model using [`mtkcompile`](https://docs.sciml.ai/ModelingToolkit/stable/API/model_building/#ModelingToolkit.mtkcompile), if the input variable is not connected to a source, then it must be specified with the `inputs` keyword.  When this is done, `ModelingToolkit` will convert the variable to a "discrete variable".  In `ModelingToolkit` a discrete variable is technically a parameter that has an independant variable.  So for example one can create a discrete variable as follows

```julia
@parameters x(t)
```

In `ModelingToolkitInputs` a new system type `InputSystem` is provided that adds the functions necessary (`input_functions`) to feed data into these discrete input variables. The `input_functions` are generated when calling `mtkcompile` on an `InputSystem`, as follows.

```@example inputs
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using ModelingToolkitInputs

# Define system with an input variable
@variables x(t) [input=true]
@variables y(t) = 0

eqs = [D(y) ~ x]

# Compile with inputs specified
@mtkcompile sys=InputSystem(eqs, t, [x, y], []) inputs=[x]
```
As can be seen this system has 2 variables and 1 equation. By telling `ModelingToolkit` that `x` is an input, the system is then balanced because a connection with `x` is now assumed.  The `input_functions` which are generated enable that assumed connection to a data source.  

Note: when the `System` is defined in a function, it can be converted to an `InputSystem` as follows.
```julia
function Demo(;name)
    @variables x(t) [input=true]
    @variables y(t) = 0

    eqs = [D(y) ~ x]

    return System(eqs, t, [x, y], []; name)
end

@named demo = Demo()
@mtkcompile sys=InputSystem(demo) inputs=ModelingToolkit.unbound_inputs(demo)
```


## Indeterminate Form: Using ModelingToolkit with Streaming Data
When input values need to be computed on-the-fly or depend on external data sources, you can manually set inputs while steping the integrator using `set_input!`.  

```@example inputs
using OrdinaryDiffEq
using Plots

prob = ODEProblem(sys, [], (0, 4))

# Initialize the integrator
integrator = init(prob, Tsit5())

# Manually set inputs and step through time
dt = 1.0
for i=1:4
    # input streaming data
    set_input!(integrator, sys.x, i)

    # step the model forward in time
    step!(integrator, dt, true)

    # (optional) compute something with outputs...
    println("y=$(integrator[y])")
end

finalize!(integrator)

plot(integrator.sol; idxs = [x, y])
```

Note: here we can see that `x` initializes at a value of 0.0, which is the assumed initial value if no default value is given in the model.  As can be seen, this is no concequence as the value changes immediately at time 0 to the set value of 1.0 before steping the integrator.

!!! warning "Always call `finalize!`"
    
    When using `set_input!`, you must call `finalize!` after integration is complete. This ensures that all discrete callbacks associated with input variables are properly saved in the solution. Without this call, input values may not be correctly recorded when querying the solution.


## Determinate Form: Connecting ModelingToolkit `inputs` to Data
When data is available, you can use the `Input` type to specify input values at specific time points. The solver will automatically apply these values using discrete callbacks.  Then supply a vector of `Input`'s using the `inputs` keyword to `solve`.

```@example inputs
# Create an Input object with predetermined values
input = Input(sys.x, [1, 2, 3, 4], [0, 1, 2, 3])

sol = solve(prob, Tsit5(); inputs=[input])

plot(sol; idxs = [x, y])
```

Multiple `Input` objects can be passed in a vector to handle multiple input variables simultaneously.


## Benefits of ModelingToolkitInputs vs. DataInterpolations
There are several reasons why one would want to input data into their model using `ModelingToolkitInputs`:
1. The same `System` (or `InputSystem`) can be used in both determinate and indeterminate forms without requiring any changes or modifications to the system.  This makes it very convenient to use and test the system against previously recorded data and be sure the exact same system will work in practice/deployment with streaming data.
2. Running several large datasets using `ModelingToolkitInputs` requires only 1 step: (1) call `solve` with each dataset.  When the data is included in the system using an interpolation object, this requires 2 steps: (1) `remake` the problem with new data, (2) then call solve.  
3. The 2 step process described above is significantly slower than the single step solve with `ModelingToolkitInputs`
4. Finally using Interpolation requires that the data length be a constant for all datasets.

The following example demonstrates this comparison.

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

    return System(eqs, t, vars, pars; name)
end

function MassSpringDamperSystem(data, time; name)
    @named src = ParametrizedInterpolation(ConstantInterpolation, data, time)
    @named clk = ContinuousClock()
    @named model = MassSpringDamper()

    eqs = [model.f ~ src.output.u
           connect(clk.output, src.input)]

    return System(eqs, t; name, systems = [src, clk, model])
end

dt = 4e-4
time = collect(0:dt:0.1)
data = 2 .* sin.(2 * pi * time * 100)

@mtkcompile sys = MassSpringDamperSystem(data, time)
prob = ODEProblem(sys, [], (0, time[end]))
sol1 = solve(prob)
plot(sol1; idxs=sys.model.dx)
```

Now let's record how much time it takes to replace the data.

```@example comparison
using BenchmarkTools
data2 = 100 .* one.(data)
sol2 = @btime begin 
    prob2 = remake(prob, p = [sys.src.data => data2])
    solve(prob2)
end
nothing # hide
```

As can be seen, this takes over 400ms to run a new dataset.  In comparison using `ModelingToolkitInputs` only takes just over 1ms for each dataset run.  Additionally note, we can run the `MassSpringDamper` component directly without needing to wrap it in another component, making it very simple to run in determiniate or indeterminate forms.  

```@example comparison
@named sysi = MassSpringDamper()
inputs=ModelingToolkit.unbound_inputs(sysi); #f
sysi = mtkcompile(InputSystem(sysi); inputs)
probi = ODEProblem(sysi, [], (0, time[end]))

sol1i = @btime begin 
    in1 = Input(sysi.f, data, time)
    solve(probi; inputs=[in1])
end
sol2i = @btime begin 
    in2 = Input(sysi.f, data2, time)
    solve(probi; inputs=[in2])
end
nothing # hide
```

## Discontinuities
One important detail to point out is that the input is discontinuous.  Note that the interpolation type set is `ConstantInterpolation` to provide the true form of the data input.  In order to properly numerically solve this, the solver needs to know when these discontinuites occur.  Currently this is not automatically provided by `ModelingToolkit` interpolation, and it hasn't been added manually in this comparison.  As a result the `DataInterpolations` solution is done in 122 steps.  The use of `ModelingToolkitInputs` however does provide the correct solving for discontinuities becuase the use of `DiscreteCallbacks` is used at each discrete data input time.  Therefore the solution is given in `n=2*length(time)` because a solve is done on each side of the discrete steps.  The difference in solution quality can be seen when comparing `sol1` and `sol1i` where the input force is a sine wave.  

```@example comparison
plot(sol1.t, sol1[sys.model.dx]; marker=:dot, label="MTK + Interpolation (n=$(length(sol1.t)))")
plot!(sol1i.t, sol1i[sysi.dx]; marker=:+, label="ModelingToolkitInputs (n=$(length(sol1i.t)))")
```

Therefore the end result is `ModelingToolkitInputs` offers a faster, more convenient way to provide data input with a higher accuracy solution provided automatically.  

# API
```@docs
Input 
InputSystem
set_input! 
finalize!
```

In addition, the keyword `inputs` is added to `solve`.  
