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

When all input values are known beforehand, you can use the [`Input`](@ref) type to specify input values at specific time points. The solver will automatically apply these values using discrete callbacks.

```@example inputs
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using OrdinaryDiffEq
using Plots

# Define system with an input variable
@variables x(t) [input=true]
@variables y(t) = 0

eqs = [D(y) ~ x]

# Compile with inputs specified
@mtkcompile sys=System(eqs, t, [x, y], []) inputs=[x]

prob = ODEProblem(sys, [], (0, 4))

# Create an Input object with predetermined values
input = Input(sys.x, [1, 2, 3, 4], [0, 1, 2, 3])

# Solve with the input - solver handles callbacks automatically
sol = solve(prob, [input], Tsit5())

plot(sol; idxs = [x, y])
```

Multiple `Input` objects can be passed in a vector to handle multiple input variables simultaneously.

### Indeterminate Form: Manual Input Setting with `set_input!`

When input values need to be computed on-the-fly or depend on external data sources, you can manually set inputs during integration using [`set_input!`](@ref). This approach requires explicit control of the integration loop.

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
    
    When using `set_input!`, you must call [`finalize!`](@ref) after integration is complete. This ensures that all discrete callbacks associated with input variables are properly saved in the solution. Without this call, input values may not be correctly recorded when querying the solution.

## Docstrings

```@docs; canonical=false
ModelingToolkit.Input
ModelingToolkit.set_input!
ModelingToolkit.finalize!
```
