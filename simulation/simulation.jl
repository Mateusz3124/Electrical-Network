@enum PlantType solar_wind hydro other
using SymbolicIndexingInterface

function short_circuit(line)
    ge = line.metadata[:graphelement]
    println([ge.src, ge.dst])

    _enable_short = ComponentAffect([], [:piline₊R_fault,:piline₊X_fault,:piline₊shortcircuit]) do u, p, ctx
        @info "Short circuit activated on line $(ctx.src)→$(ctx.dst) at t = $(ctx.t)s"
        p[:piline₊shortcircuit] = 1
    end

    shortcircuit_cb = PresetTimeComponentCallback(0.1, _enable_short)

    _disable_line = ComponentAffect([], [:piline₊active]) do u, p, ctx
        @info "Line $(ctx.src)→$(ctx.dst) disconnected at t = $(ctx.t)s"
        p[:piline₊active] = 0
    end

    deactivate_cb = PresetTimeComponentCallback(0.19, _disable_line)

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

    return PresetTimeCallback(0.0, affect)
end

function get_global_callbacks(nodes, sol)
    plant_vidxs = []
    load_vidxs = []
    
    for (i, node) in enumerate(nodes)
        parts = split(string(node.name), "_")
        if length(parts) == 2
            if parts[2] == "load"
                push!(load_vidxs, VIndex(i))
            end
        end
    end

    load_affect! = let load_vidxs = load_vidxs
        function (integrator)
            @info "Increased loads at t = $(integrator.t)s"
            p_net = NWParameter(integrator)
            for vidx in load_vidxs
                p_net.v[vidx, :load₊S_p_re] += 0.001 * 1000
                p_net.v[vidx, :load₊S_p_im] += 0.001 * 0.005 * 1000
            end
            SciMLBase.auto_dt_reset!(integrator)
            save_parameters!(integrator)
        end
    end

    # cb_plant = PresetTimeCallback([0.0], plant_affect!)
    cb_load  = PresetTimeCallback(collect(1.0:40.0:321.0), load_affect!)

    return CallbackSet(cb_load)
end

using NetworkDynamics, SciMLBase

const K, ALPHA = 0.14, 0.02    
const TMS      = 0.1
const PICKUP   = 1.15               
const KR       = 9.7 

t_iec(M)   = TMS * K / (M^ALPHA - 1)
t_reset(M) = TMS * KR / (1 - min(M, 0.99)^2)

function trip_wire(nw, s0, plant_types; eidxs = 1:ne(nw))
    get_i = getu(nw, [EIndex(i, :src₊i_mag) for i in eidxs])

    Is      = max.(PICKUP .* abs.(get_i(s0)), 0.3)
    S       = zeros(length(eidxs))
    alive   = trues(length(eidxs))
    tlast   = Ref(0.0)

    adj       = Dict{Symbol,Vector{Int}}()
    graphelem = Dict{Int,Tuple{Symbol,Symbol}}()
    for i in eidxs
        ge = get_graphelement(nw, EIndex(i))
        push!(get!(() -> Int[], adj, ge.src), i)
        push!(get!(() -> Int[], adj, ge.dst), i)
        graphelem[i] = (ge.src, ge.dst)
    end

    is_plant(name) = haskey(plant_types, name)
    is_load(name)  = endswith(string(name), "_load")

    function explore(start, excl, p)
        visited = Set{Symbol}((start,))
        queue = [start]
        has_ref = is_plant(start)
        while !isempty(queue)
            cur = popfirst!(queue)
            for k in adj[cur]
                k == excl && continue
                p.e[k, :piline₊active] == 1 || continue
                (s, d) = graphelem[k]
                nxt = s == cur ? d : s
                nxt in visited && continue
                push!(visited, nxt)
                is_plant(nxt) && (has_ref = true)
                push!(queue, nxt)
            end
        end
        return visited, has_ref
    end

    function attempt_trip(i, t, p)
        (src, dst) = graphelem[i]
        block_trip = false
        changed = false
        seen = Set{Symbol}()

        for name in (src, dst)
            name in seen && continue
            comp, has_ref = explore(name, i, p)
            union!(seen, comp)
            has_ref && continue

            for member in comp
                if is_plant(member)
                    type = get(plant_types, member, :other)
                    if type == :solar_wind
                        p.v[member, :solar_wind₊status] = 0.0
                        @info "Elektrownia $member (solar/wind) wyłączona wewnętrznie przed izolacją wyspy, linia $i, t = $(round(t, digits=4)) s"
                        changed = true
                    elseif type == :hydro
                        p.v[member, :gensal₊status] = 0.0
                        @info "Elektrownia $member (hydro) wyłączona wewnętrznie przed izolacją wyspy, linia $i, t = $(round(t, digits=4)) s"
                        changed = true
                    # else
                    #     @info "Elektrownia $member (other) - brak bezpiecznego wyłącznika, linia $i pozostaje zamknięta, t = $(round(t, digits=4)) s"
                    #     block_trip = true
                    end
                # elseif is_load(member)
                #     p.v[member, :load₊S_p_re] = 0.0
                #     p.v[member, :load₊S_p_im] = 0.0
                #     @info "Odbiór $member odciążony (Pset=Qset=0) przed izolacją wyspy, linia $i, t = $(round(t, digits=4)) s"
                #     changed = true
                end
            end
        end

        return block_trip, changed
    end

    affect! = function (integrator)
        dt = integrator.t - tlast[]
        tlast[] = integrator.t
        dt <= 0 && return

        I = abs.(get_i(integrator))
        p = NWParameter(integrator)
        tripped = false

        applied_now = 0

        for (j, i) in enumerate(eidxs)
            alive[j] || continue
            M = I[j] / Is[j]

            if M > 1.0
                S[j] += dt / t_iec(M)
            elseif S[j] > 0.0
                S[j] = max(S[j] - dt / t_reset(M), 0.0)
            end
            if S[j] >= 1.0
                attempt_trip(i, integrator.t, p)

                (src, dst) = graphelem[i]
                @info "Linia $i ($src→$dst) wyłączona w t = $(round(integrator.t, digits=4)) s (M = $(round(M, digits=2)))"
                if i == 187
                    p.e[i, :piline₊active] = 0
                end
                p.e[i, :piline₊active] = 1e-5
                changed = true

                alive[j] = false
                tripped |= changed
            end
        end

        if tripped
            SciMLBase.auto_dt_reset!(integrator)
            save_parameters!(integrator)
        end
    end

    DiscreteCallback((u, t, integ) -> true, affect!; save_positions = (false, false))
end

function simulate(nw, s0, nodes, lines, plant_types)
    # shut_down_inits(nodes)
    # short_circuit(lines[417])
    short_circuit(lines[142])
    # short_circuit(lines[1])

    # cb = trip_wire(nw, s0, plant_types)

    # plant_Max(nodes, s0)
    # cb = get_global_callbacks(nodes,s0)
    # change_load_all(nodes)
        
    # prob = ODEProblem(nw, s0, (0.0, 400);add_nw_cb=cb)
    
    # prob = ODEProblem(nw, s0, (0.0, 15))
    # prob = ODEProblem(nw, s0, (0.0, 2.0);add_nw_cb=cb)
    # prob = ODEProblem(nw, s0, (0.0, 2);add_nw_cb=cb)
    prob = ODEProblem(nw, s0, (0.0, 2);)

    print_cb = FunctionCallingCallback((u, t, integrator) -> println("t = $t, dt = $(integrator.dt)");
                                    func_everystep = true, func_start = true)

    sol = solve(prob, Rodas5P(); abstol=1e-5, reltol=1e-7, saveat = 0.01, callback = print_cb)
    # sol = solve(prob, Rodas5P(); saveat = 0.01, callback = print_cb)

    # sol = solve(prob, Rodas5P(linsolve = KLUFactorization()), dtmin = 1e-10, force_dtmin = false)
    # sol = solve(prob, Rodas5P(); callback = print_cb)
    # sol = solve(prob, FBDF(); verbose = true)
    println(sol.t[end])
    # sol = solve(prob, FBDF(); callback = print_cb, dtmin = 1e-7,, saveat = 0.01 force_dtmin = true, verbose=true)

    # sol = solve(prob, FBDF(); abstol=1e-7, reltol=1e-7, callback = print_cb)
    # sol = solve(prob, FBDF(); abstol=1e-7, reltol=1e-7, callback = print_cb)

    # sol = solve(prob, FBDF(linsolve = KLUFactorization()); abstol=1e-6, reltol=1e-8, saveat = 0.01, callback = print_cb)
    # sol = solve(prob, FBDF(); abstol=1e-8, reltol=1e-6) , saveat = 0.01
    # sol = solve(prob, Rodas5P(linsolve = KLUFactorization()), dtmin = 1e-10, force_dtmin = false)
    return sol
end
