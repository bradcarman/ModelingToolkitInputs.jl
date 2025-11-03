# ModelingToolkitInputs.jl
Support for driving ModelingToolkit model inputs with data in determinate (data known upfront) and indeterminate form (data streamed at runtime). See the [documentation](https://bradcarman.github.io/ModelingToolkitInputs.jl/dev/). 

Without this package the best method to include data with a `ModelingToolkit` model is using using Interpolation (see [Building Models with Discrete Data, Interpolations, and Lookup Tables](https://docs.sciml.ai/ModelingToolkitStandardLibrary/stable/tutorials/input_component/#Building-Models-with-Discrete-Data,-Interpolations,-and-Lookup-Tables)).  

This package enables the following 4 key benefits and improvements:
1. The same `ModelingToolkit.System` can be used in both determinate and indeterminate forms without requiring any changes or modifications to the system.  This makes it very convenient to use and test the system against previously recorded data and be sure the exact same system will work in practice/deployment with streaming data.
2. Running several large datasets using `ModelingToolkitInputs` requires only 1 step: (1) call `solve` with each dataset.  When the data is included in the system using an interpolation object, this requires 2 steps: (1) `remake` the problem with new data, (2) then call solve.  
3. The 2 step process described above is significantly slower than the single step solve with `ModelingToolkitInputs`
4. Finally, this method enables the data size to change from dataset to dataset.
