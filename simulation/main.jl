using PowerDynamics
using PowerDynamics: Library, initialize_from_pf, Network, PSSE_SCRX
using PowerDynamics.Library: PSSE_SCRX
using PowerDynamics.Library.ComposableInverter: SimpleGFLDC, LFilter, PLL_LPF, CC1
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as Dt
using ModelingToolkit: connect
using SciMLBase
using DiffEqCallbacks
using OrdinaryDiffEqBDF: FBDF, ODEProblem, solve
using DifferentialEquations: Rodas5P
using JSON3
using Serialization
using Graphs
using DifferentialEquations
using NonlinearSolve

include("models.jl")
include("network.jl")
include("simulation.jl")

function save_names(nodes, lines, data)
    names = Dict()
    names_lines = []

    for (i, node) in enumerate(nodes)
        if(node.name == :Netherlands)
            idx = Symbol("656866098")
            names[node.name] = Dict(
                :name => node.name,
                :position => [data.network[idx].position[2][1] + 0.001, data.network[idx].position[2][2] + 0.001],
                :type => "slack",
                :voltage => nothing
            )
            continue
        end
        if(node.name == :Germany)
            idx = Symbol("214288187")
            names[node.name] = Dict(
                :name => node.name,
                :position => [data.network[idx].lat + 0.001, data.network[idx].lon + 0.001],
                :type => "slack",
                :voltage => nothing
            )
            continue
        end
        if(node.name == :France)
            idx = Symbol("87528529")
            names[node.name] = Dict(
                :name => node.name,
                :position => [data.network[idx].position[1][1] + 0.001, data.network[idx].position[1][2] + 0.001],
                :type => "slack",
                :voltage => nothing
            )
            continue
        end
        parts = split(string(node.name), "_")
        v = get(data.network[parts[1]], :voltage, nothing)

        if length(parts) == 2
            if parts[2] == "low"
                names[node.name] = Dict(
                    :name => node.name,
                    :position => [data.network[parts[1]].lat + 0.001, data.network[parts[1]].lon + 0.001],
                    :type => data.network[parts[1]].type,
                    :voltage => v
                )
                continue
            end
            if parts[2] == "load"
                names[node.name] = Dict(
                    :name => node.name,
                    :position => [data.network[parts[1]].lat + 0.001, data.network[parts[1]].lon + 0.001],
                    :type => "load",
                    :voltage => v
                )
                continue
            end
            if parts[2] == "plant"
                names[node.name] = Dict(
                    :name => node.name,
                    :position => [data.network[parts[1]].lat + 0.001, data.network[parts[1]].lon + 0.001],
                    :type => "plant",
                    :voltage => v
                )
                continue
            end
        end
        
        if length(parts) == 3
            if parts[3] == "start"
                names[node.name] = Dict(
                    :name => node.name,
                    :position => [data.network[parts[1]].position[1][1], data.network[parts[1]].position[1][2]],
                    :type => data.network[parts[1]].type,
                    :voltage => v
                )
            else
                names[node.name] = Dict(
                    :name => node.name,
                    :position => [data.network[parts[1]].position[2][1], data.network[parts[1]].position[2][2]],
                    :type => data.network[parts[1]].type,
                    :voltage => v
                )
            end
            continue
        end
        names[node.name] = Dict(
            :name => node.name,
            :position => [data.network[parts[1]].lat, data.network[parts[1]].lon],
            :type => data.network[parts[1]].type,
            :voltage => v
        )
    end

    for el in lines
        ge = el.metadata[:graphelement]
        push!(names_lines, [ge.src, ge.dst])
    end

    namesr = Dict()

    namesr[:nodes] = names
    namesr[:lines] = names_lines
    open("names.json", "w") do io
        JSON3.write(io, namesr)
    end
end

industry = Set([
    Symbol("33756607_load"),
    Symbol("228369813_load"),
    Symbol("225982020_load"),
    Symbol("225991900_load"),
    Symbol("239444041_load"),
    Symbol("205830382_load"),
    Symbol("239276278_load"),
    Symbol("825954426_load"),
    Symbol("666662687_load"),
    Symbol("667172748_load"),
    Symbol("103325119_load"),
    Symbol("766062193_load"),
    Symbol("1351038456_load"),
    Symbol("715026288_load"),
    Symbol("138113463_load"),
    Symbol("105919468_load"),
    Symbol("87792346_load"),
    Symbol("168872812_load"),
    Symbol("161234130_load"),
])

function update_load(bus_load, s, k, KpZ, KpI, KqZ, KqI)
    V_pf = s[VIndex(k, :busbar₊u_mag)] 
    p_pf = s[VIndex(k, :busbar₊P)]
    q_pf = s[VIndex(k, :busbar₊Q)]

    Sbase = 1000

    set_default!(bus_load, Regex("load₊v_0\$"),    V_pf)
    set_default!(bus_load, Regex("load₊S_p_re\$"), -p_pf * Sbase)  # see sign note below
    set_default!(bus_load, Regex("load₊S_p_im\$"), -q_pf * Sbase)

    set_default!(bus_load, Regex("load₊a_re\$"),   KpI)
    set_default!(bus_load, Regex("load₊a_im\$"),   KqI)
    set_default!(bus_load, Regex("load₊b_re\$"),   KpZ)
    set_default!(bus_load, Regex("load₊b_im\$"),   KqZ)
    set_default!(bus_load, Regex("load₊S_b\$"),  Sbase)
    
    set_default!(bus_load, Regex("load₊characteristic\$"), 2)   # see note below — important for your case
    set_default!(bus_load, Regex("load₊PQBRAK\$"), 0.7)

    # algebraic-state guesses, avoid cold-start init failures
    set_default!(bus_load, Regex("load₊v\$"),  V_pf)
    set_default!(bus_load, Regex("load₊P\$"), -p_pf)
    set_default!(bus_load, Regex("load₊Q\$"), -q_pf)
    set_default!(bus_load, Regex("load₊kP\$"), 1.0)
    set_default!(bus_load, Regex("load₊kI\$"), 1.0)
end

function main()
    data = JSON3.read(read("../data/calculated/belgium.json", String))
    p_base = 1000
    @time begin

    nw, nodes, lines = create_network(data, p_base)

    nw = set_jac_prototype!(nw)

    pfnw = powerflow_model(nw)
    pfs0 = NWState(pfnw)
    s = solve_powerflow(nw; pfnw, pfs0, verbose=false, sparse=true)
    i = 1
    for (k, node) in enumerate(nodes)
        parts = split(string(node.name), "_")
        if length(parts) == 2
            if parts[2] == "load"
                if node.name in industry
                    update_load(node, s, k, 1.21, -1.61, 4.35, -7.08)
                elseif i % 2 == 0
                    update_load(node, s, k, 1.31, -1.94, 9.20, -15.27)
                else
                    update_load(node, s, k, 0.76, -0.52, 6.92, -11.75)
                end
                i += 1
            end
        end
    end
    s0 = initialize_from_pf(nw; pfs=s, verbose=false, tol=1e-6, nwtol=1e-6, parallel=false) 
    end

    @time begin
    sol = simulate(nw, s0, nodes, lines)
    end
    serialize("sim/aashort8.jld2", sol)
    # save_names(nodes, lines, data)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

