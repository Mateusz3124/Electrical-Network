using PowerDynamics
using PowerDynamics: Library, initialize_from_pf, Network
using PowerDynamics.Library.ComposableInverter: SimpleGFLDC, LFilter, PLL_LPF, CC1
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as Dt
using ModelingToolkit: connect
using SciMLBase
using OrdinaryDiffEqBDF: FBDF, ODEProblem, solve
using DifferentialEquations: Rodas5P
using JSON3
using Serialization
using Graphs

include("models.jl")
include("network.jl")
include("simulation.jl")

function save_names()
    names = Dict()
    names_nodes = []
    names_lines = []

    for el in nodes
        push!(names_nodes, el.name)
    end

    for el in lines
        ge = el.metadata[:graphelement]
        push!(names_lines, [ge.src, ge.dst])
    end

    names[:nodes] = names_nodes
    names[:lines] = names_lines
    open("names.json", "w") do io
        JSON3.write(io, names)
    end
end

function main()
    data = JSON3.read(read("../data/calculated/belgium.json", String))
    p_base = 1000
    
    @time begin
    nw, nodes, lines = create_network(data, p_base)
    s0 = initialize_from_pf(nw; verbose=true, tol=1e-7, nwtol=1e-7, parallel=false) 
    end

    @time begin
    sol = simulate(nw, s0, nodes, lines)
    end
    serialize("sim/zdropSim.jld2", sol)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

