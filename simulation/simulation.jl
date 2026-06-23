@enum PlantType solar_wind hydro other

function short_circuit(line)
    _enable_short = ComponentAffect([], [:piline₊shortcircuit]) do u, p, ctx
        @info "Short circuit activated on line $(ctx.src)→$(ctx.dst) at t = $(ctx.t)s"
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
    plant_cond = ComponentCondition([:busbar₊P], []) do u, p, t
        #even when the plant is shut down, there can still be small values below 0.0
        u[:busbar₊P] < -0.1
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

function simulate(nw, s0, nodes, lines)
    shut_down_procedure(nodes[1], 5)
    shut_down_procedure(nodes[4], 8, solar_wind)
    shut_down_procedure(nodes[7], 11)
    shut_down_procedure(nodes[59], 94)
    shut_down_procedure(nodes[92], 146)
    shut_down_procedure(nodes[139], 209)
    shut_down_procedure(nodes[243], 364)
    shut_down_procedure(nodes[264], 396)
    shut_down_procedure(nodes[330], 483, hydro)
    shut_down_procedure(nodes[372], 534)
    shut_down_procedure(nodes[419], 595, hydro)
    shut_down_procedure(nodes[423], 600)
    shut_down_procedure(nodes[428], 605)
    shut_down_procedure(nodes[433], 610, hydro)
    shut_down_procedure(nodes[438], 615)
    shut_down_procedure(nodes[446], 622)
    shut_down_procedure(nodes[450], 626)
    shut_down_procedure(nodes[462], 637, solar_wind)
    shut_down_procedure(nodes[467], 643)
    shut_down_procedure(nodes[472], 649, solar_wind)
    shut_down_procedure(nodes[475], 652)
    shut_down_procedure(nodes[478], 654)
    shut_down_procedure(nodes[488], 663, solar_wind)
    
    short_circuit(lines[142])

    prob = ODEProblem(nw, s0, (0.0, 2.0))
    sol = solve(prob, FBDF())
    return sol
end