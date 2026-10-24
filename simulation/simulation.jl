 @enum PlantType solar_wind hydro other
using SymbolicIndexingInterface

function close_line(line)
    _disable_line = ComponentAffect([], [:piline₊active]) do u, p, ctx
        @info "Line $(ctx.src)→$(ctx.dst) disconnected at t = $(ctx.t)s"
        p[:piline₊active] = 1e-5
    end

    deactivate_cb = PresetTimeComponentCallback(0.4457, _disable_line)
    set_callback!(line, (deactivate_cb,))
end

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
                p_net.v[vidx, :load₊S_p_re] += 0.01 * 1000
                p_net.v[vidx, :load₊S_p_im] += 0.01 * 0.005 * 1000
            end
            SciMLBase.auto_dt_reset!(integrator)
            save_parameters!(integrator)
        end
    end

    # cb_plant = PresetTimeCallback([0.0], plant_affect!)
    # cb_load  = PresetTimeCallback([1.0], load_affect!)
    cb_load  = PresetTimeCallback(collect(1.0:50.0:561.0), load_affect!)

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
                (src, dst) = graphelem[i]
                @info "Linia $i ($src→$dst) wyłączona w t = $(round(integrator.t, digits=4)) s (M = $(round(M, digits=2)))"
                # if i == 187
                #     p.e[i, :piline₊active] = 0
                # end
                # if i == 358
                #     p.e[i, :piline₊active] = 0
                # end
                p.e[i, :piline₊active] = 1e-5
                changed = true

                alive[j] = false
                tripped |= changed
            end
        end

        if tripped
            SciMLBase.auto_dt_reset!(integrator)
            save_parameters!(integrator)
        else
            u_modified!(integrator, false)
        end
    end

    DiscreteCallback((u, t, integ) -> true, affect!; save_positions = (false, false))
end

function simulate(nw, s0, nodes, lines, plant_types)
    # shut_down_inits(nodes)
    # short_circuit(lines[417])
    # short_circuit(lines[330])
    short_circuit(lines[142])
    # short_circuit(lines[1])
    # close_line(lines[276])
    # close_line(lines[277])
    # close_line(lines[330])

    # cb = trip_wire(nw, s0, plant_types)

    # plant_Max(nodes, s0)
    # cb = get_global_callbacks(nodes,s0)
    # change_load_all(nodes)
        
    # prob = ODEProblem(nw, s0, (0.0, 270);add_nw_cb=cb)
    
    # prob = ODEProblem(nw, s0, (0.0, 0.14))
    # prob = ODEProblem(nw, s0, (0.0, 5.0);add_nw_cb=cb)
    prob = ODEProblem(nw, s0, (0.0, 15.0))
    # prob = ODEProblem(nw, s0, (0.0, 2);)

    print_cb = FunctionCallingCallback((u, t, integrator) -> println("t = $t, dt = $(integrator.dt)");
                                    func_everystep = true, func_start = true)

    # sol = solve(prob, Rodas5P(); abstol=1e-7, reltol=1e-12, callback = print_cb)
    # sol = solve(prob, Rodas5P(); saveat = 0.01, callback = print_cb)

    # sol = solve(prob, Rodas5P(linsolve = KLUFactorization()), dtmin = 1e-10, force_dtmin = false)
    # sol = solve(prob, Rodas5P(); callback = print_cb)
    # sol = solve(prob, FBDF(); verbose = true)
    sol = solve(prob, Rodas5P(linsolve = KLUFactorization()); abstol=1e-7, reltol=1e-8 , saveat = 0.01, callback = print_cb)
    # sol = solve(prob, Rodas5P(); abstol=1e-5, reltol=1e-7 , saveat = 0.01, maxiters = 10^7)
    # sol = solve(prob, Rodas5P(linsolve = KLUFactorization()); abstol=1e-5, reltol=1e-10, maxiters = 10^7)
    println(sol.t[end])
    # sol = solve(prob, FBDF(); callback = print_cb, dtmin = 1e-7,, saveat = 0.01 force_dtmin = true, verbose=true)

    # sol = solve(prob, FBDF(); abstol=1e-7, reltol=1e-7, callback = print_cb)
    # sol = solve(prob, FBDF(); abstol=1e-7, reltol=1e-7, callback = print_cb)

    # sol = solve(prob, FBDF(linsolve = KLUFactorization()); abstol=1e-6, reltol=1e-8, saveat = 0.01, callback = print_cb)
    # sol = solve(prob, FBDF(); abstol=1e-8, reltol=1e-6) , saveat = 0.01
    # sol = solve(prob, Rodas5P(linsolve = KLUFactorization()), dtmin = 1e-10, force_dtmin = false)
    return sol
end
