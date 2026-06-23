using PowerDynamics
using PowerDynamics: Library, initialize_from_pf, Network
using PowerDynamics.Library.ComposableInverter: SimpleGFLDC, LFilter, PLL_LPF, CC1
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as Dt
using ModelingToolkit: connect
using SciMLBase
using OrdinaryDiffEqBDF: FBDF, ODEProblem, solve
using JSON3
using Serialization
using Graphs

include("models.jl")
include("network.jl")
include("simulation.jl")

function main()
    data = JSON3.read(read("../data/calculated/belgium.json", String))
    p_base = 1000

    nw, nodes, lines = create_network(data, p_base)
    s0 = initialize_from_pf(nw; verbose=false, tol=1e-9, nwtol=1e-9, parallel=false) 

    sol = simulate(nw, s0, nodes, lines)

    serialize("sims/shutdown.jld2", sol)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

