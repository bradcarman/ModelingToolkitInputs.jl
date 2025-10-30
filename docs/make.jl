using Documenter
using ModelingToolkitInputs

makedocs(;
    # modules=[ModelingToolkitInputs],
    authors="Brad Carman <bradleygcarman@outlook.com>",
    sitename="ModelingToolkitInputs.jl",
    format=Documenter.HTML(;
        canonical="https://bradcarman.github.io/ModelingToolkitInputs.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

#=
using LiveServer
serve(dir="build")
=#

deploydocs(;
    repo="github.com/bradcarman/ModelingToolkitInputs.jl.git"
)

