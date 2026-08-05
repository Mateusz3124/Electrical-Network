@enum PlantType solar_wind hydro other

function short_circuit(line)
    ge = line.metadata[:graphelement]
    println([ge.src, ge.dst])
    _enable_short = ComponentAffect([], [:piline₊R_fault,:piline₊X_fault,:piline₊shortcircuit]) do u, p, ctx
        @info "Short circuit activated on line $(ctx.src)→$(ctx.dst) at t = $(ctx.t)s"
        p[:piline₊R_fault] = 0.01
        p[:piline₊X_fault] = 0.02
        p[:piline₊shortcircuit] = 1
    end

    shortcircuit_cb = PresetTimeComponentCallback(0.1, _enable_short)

    _disable_line = ComponentAffect([], [:piline₊active]) do u, p, ctx
        @info "Line $(ctx.src)→$(ctx.dst) disconnected at t = $(ctx.t)s"
        p[:piline₊active] = 0
    end

    deactivate_cb = PresetTimeComponentCallback(0.2, _disable_line)

    set_callback!(line, (shortcircuit_cb, deactivate_cb))
end

function shut_down_procedure(plant, line_to_close, type = other)
    println(plant)
    plant_cond = ComponentCondition([:busbar₊P], []) do u, p, t
        #even when the plant is shut down, there can still be small values below 0.0
        return u[:busbar₊P] > 0.5
    end

    if type == other
        affect = let edge_idx = line_to_close
            ComponentAffect([], []) do u, p, ctx
                integrator = ctx.integrator
                println("Plant $(ctx.vidx) dropped below 0 kW at t=$(integrator.t). Tripping Line $edge_idx !")

                p_net = NWParameter(integrator)
                
                p_net.e[edge_idx, :breaker₊closed] = 0
                
                SciMLBase.auto_dt_reset!(integrator)
                save_parameters!(integrator)
                nothing
            end
        end

        plant_cb = DiscreteComponentCallback(
            plant_cond, 
            affect
        )

        set_callback!(plant, (plant_cb))
        return
    end

    if type == solar_wind
        affect = ComponentAffect([],[:solar_wind₊status]) do u, p, ctx
            p[:solar_wind₊status] = 0.0
            println("Plant $(ctx.vidx) dropped below 0 kW at t=$(ctx.integrator.t). Solar!")
        end

        plant_cb = DiscreteComponentCallback(
            plant_cond, 
            affect
        )

        set_callback!(plant, (plant_cb))
        return
    end

    if type == hydro
        affect = ComponentAffect([],[:gensal₊status]) do u, p, ctx
            p[:gensal₊status] = 0.0
            println("Plant $(ctx.vidx) dropped below 0 kW at t=$(ctx.integrator.t). Hydro!")
        end

        plant_cb = DiscreteComponentCallback(
            plant_cond, 
            affect
        )

        set_callback!(plant, (plant_cb))
        return
    end

end

function change_load(node)
    _change_load = ComponentAffect([], [:load₊Pset, :load₊Qset]) do u, p, ctx
        @info "increased load [$(ctx.vidx)] t = $(ctx.t)s"
        p[:load₊Pset] -= 0.01
        p[:load₊Qset] -= 0.01 * 0.005
    end

    t_steps = collect(1:10:61)
    set_callback!(node, PresetTimeComponentCallback(t_steps, _change_load))
end

function shut_down_inits(nodes)
    shut_down_procedure(nodes[1], 5)
    # shut_down_procedure(nodes[4], 8, solar_wind)
    # shut_down_procedure(nodes[7], 11)
    # shut_down_procedure(nodes[59], 94)
    # shut_down_procedure(nodes[92], 146)
    # shut_down_procedure(nodes[139], 209)
    # shut_down_procedure(nodes[243], 364)
    # shut_down_procedure(nodes[264], 396)
    # shut_down_procedure(nodes[330], 483, hydro)
    # shut_down_procedure(nodes[372], 534)
    # shut_down_procedure(nodes[419], 595, hydro)
    # shut_down_procedure(nodes[423], 600)
    # shut_down_procedure(nodes[428], 605)
    # shut_down_procedure(nodes[433], 610, hydro)
    # shut_down_procedure(nodes[438], 615)
    # shut_down_procedure(nodes[446], 622)
    # shut_down_procedure(nodes[450], 626)
    # shut_down_procedure(nodes[462], 637, solar_wind)
    # shut_down_procedure(nodes[467], 643)
    # shut_down_procedure(nodes[472], 649, solar_wind)
    # shut_down_procedure(nodes[475], 652)
    # shut_down_procedure(nodes[478], 654)
    # shut_down_procedure(nodes[488], 663, solar_wind)
end

function change_load_all(nodes)
    for node in nodes
        parts = split(string(node.name), "_")
        if length(parts) == 2
            if parts[2] == "load"
                change_load(node)
            end
        end
    end
end

function plant_Max(nodes, sol)
    _enable_max = ComponentAffect([], [:ctrld_gen₊gov₊V_max]) do u, p, ctx
        @info "Set to max $(ctx.id)"
        p[:ctrld_gen₊gov₊V_max] = 1.0
    end

    max_cb = PresetTimeComponentCallback(0.0, _enable_max)
    for node in nodes
        parts = split(string(node.name), "_")
        if length(parts) == 2
            if parts[2] == "plant"
                try 
                    println(sol.v[node.name][:ctrld_gen₊gov₊V_max])
                    set_callback!(node, max_cb)
                catch
                end
            
            end
        end
    end
end

function create_plant_max_callback(nodes)
    plant_vidxs=[]
    for (i, node) in enumerate(nodes)
        parts = split(string(node.name), "_")
        if length(parts) == 2
            if parts[2] == "plant"
                try 
                    push!(plant_vidxs,VIndex(i))
                catch
                end
            
            end
        end
    end

    affect = let plant_vidxs = plant_vidxs
        ComponentAffect([], []) do u, p, ctx
            integrator = ctx.integrator
            @info "Triggered plant_Max at t=$(integrator.t)"

            p_net = NWParameter(integrator)

            for vidx in plant_vidxs
                p_net.v[vidx, :ctrld_gen₊gov₊V_max] = 1.0
            end         
            
            SciMLBase.auto_dt_reset!(integrator)
            save_parameters!(integrator)
            nothing
        end
    end

    # 3. Exactly ONE callback created
    return PresetTimeCallback(0.0, affect)
end

function get_global_callbacks(nodes, sol)
    plant_vidxs = []
    load_vidxs = []
    
    # 1. Gather all indices ONCE
    for (i, node) in enumerate(nodes)
        parts = split(string(node.name), "_")
        if length(parts) == 2
            if parts[2] == "load"
                push!(load_vidxs, VIndex(i))
            end
        end
    end

    # 3. Define standard SciML affect for Loads
    load_affect! = let load_vidxs = load_vidxs
        function (integrator)
            @info "Increased loads at t = $(integrator.t)s"
            p_net = NWParameter(integrator)
            for vidx in load_vidxs
                p_net.v[vidx, :load₊Pset] -= 0.01
                p_net.v[vidx, :load₊Qset] -= 0.01 * 0.005
            end
            SciMLBase.auto_dt_reset!(integrator)
            save_parameters!(integrator)
        end
    end

    # cb_plant = PresetTimeCallback([0.0], plant_affect!)
    cb_load  = PresetTimeCallback(collect(1.0:10.0:71.0), load_affect!)

    return CallbackSet(cb_load)
end

# Usage when solving:
function simulate(nw, s0, nodes, lines)
    # shut_down_inits(nodes)
    short_circuit(lines[142])

    # plant_Max(nodes, s0)
    # cb = get_global_callbacks(nodes,s0)
    # change_load_all(nodes)
        
    # prob = ODEProblem(nw, s0, (0.0, 81);add_nw_cb=cb)
    prob = ODEProblem(nw, s0, (0.0, 10))
    print_cb = FunctionCallingCallback((u, t, integrator) -> println("t = $t, dt = $(integrator.dt)");
                                    func_everystep = true, func_start = true)

    sol = solve(prob, FBDF(); callback = print_cb)
    # sol = solve(prob, FBDF(); abstol=1e-8, reltol=1e-6) , saveat = 0.01
    # sol = solve(prob, Rodas5P(linsolve = KLUFactorization()), dtmin = 1e-10, force_dtmin = false)
    return sol
end
