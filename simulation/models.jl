include("RenewableModel.jl")

function get_solar(solar_plant_template, name::Symbol, P, v)
    bus = compile_bus(solar_plant_template; name=name)
    set_pfmodel!(bus, pfPV(P = P, V = 1.0))
    return bus
end

function get_wind(wind_plant_template, name::Symbol, P, v)
    bus = compile_bus(wind_plant_template; name=name) 
    set_pfmodel!(bus, pfPV(P = P, V = 1.0))
    return bus
end

function get_hydro(hydro_plant_template, name::Symbol, P, v)
    bus = compile_bus(hydro_plant_template; name=name)
    set_default!(bus, Regex("gensal₊M_b\$"), P * 1000)
    set_pfmodel!(bus, pfPV(P = P, V = 1.0))
    return bus
end

function get_other(other_plant_template, name::Symbol, P, v)
    bus = compile_bus(other_plant_template; name=name)
    set_default!(bus, Regex("ctrld_gen₊other₊P_max\$"), 1.3)
    set_default!(bus, Regex("ctrld_gen₊other₊Sn\$"), P * 1000)

    # set_default!(bus, Regex("ctrld_gen₊gov₊V_min\$"), 0.0)
    # set_default!(bus, Regex("ctrld_gen₊gov₊V_max\$"), 1.0)
    
    # set_default!(bus, Regex("ctrld_gen₊other₊Vn\$"), parse.(Float64, v) / 1000)
    # set_default!(bus, Regex("ctrld_gen₊other₊V_b\$"), parse.(Float64, v) / 1000)
    
    set_pfmodel!(bus, pfPV(P = P, V = 1.0))
    return bus
end

function get_load(bus_load_template, name::Symbol, P, Q, KpZ, KpI, KqZ, KqI) 
    bus_load = compile_bus(bus_load_template; name=name)

    # set_default!(bus_load, Regex("load₊Pset\$"), -P / scale_p)
    # set_default!(bus_load, Regex("load₊Qset\$"), -Q / scale_q)

    # set_default!(bus_load, Regex("load₊Vset\$"), 1.0)

    set_default!(bus_load, Regex("load₊KpZ\$"), KpZ)
    set_default!(bus_load, Regex("load₊KpI\$"), KpI)
    set_default!(bus_load, Regex("load₊KqZ\$"), KqZ)
    set_default!(bus_load, Regex("load₊KqI\$"), KqI)
    
    set_pfmodel!(bus_load, pfPQ(P = -P, Q = -Q))
    return bus_load
end

function get_junction(junction_bus_template, name::Symbol)
    bus = compile_bus(junction_bus_template; name=name)
    set_pfmodel!(bus, pfPQ(P=0.0, Q=0.0))
    return bus
end

function get_slack(slack_plant_template, name::Symbol, V=1.0)
    bus = compile_bus(slack_plant_template; name=name)
    set_default!(bus, Regex("ctrld_gen₊gov₊V_min\$"), -1.0)
    set_default!(bus, Regex("ctrld_gen₊avr₊vr_min\$"), -5.0)
    set_default!(bus, Regex("ctrld_gen₊avr₊vr_max\$"), 5.0)
    set_pfmodel!(bus, pfSlack(V=V))
    return bus
end

function get_line(line_template, src, dst)
    line = compile_line(line_template; src=src, dst=dst)
    return line
end

function initialize_templates()
    solar_wind_plant = CustomRenewable(name=:solar_wind, kp_v_dc=2.0, ki_v_dc=50.0)

    gensal = Library.PSSE_GENSAL(;
        name=:gensal,
        S_b=1000, 
        M_b=1000, 
        H=4.41, 
        D=0.1, 
        Xd=1.22, 
        Xq=0.76, 
        Xpd=0.297,
        Xppd=0.2, 
        Xppq=0.2, 
        Xl=0.12, 
        Tpd0=5.7, 
        Tppd0=0.028, 
        Tppq0=0.0358,
        S10=0.186, 
        S12=0.802, 
        R_a=1e-5, 
        pmech_input=true, 
        efd_input=false
    )

    hygov = Library.PSSE_HYGOV(name=:swing_hydro_gov, G_MAX=1.0)
    con = [
        connect(hygov.PMECH_out, gensal.PMECH_in)
        connect(gensal.SPEED_out, hygov.SPEED_in)
    ]

    _machine = Library.SauerPaiMachine(;
        name=:other, 
        vf_input=true, 
        τ_m_input=true, 
        S_b=1000.0, 
        V_b=16.5, 
        ω_b=1.0,
        Vn=16.5, 
        R_s=0.0, 
        X_ls=0.125, 
        X_d=1.0, 
        X_q=0.69, 
        X′_d=0.31, 
        X′_q=0.5,
        T′_d0=10.2, 
        T′_q0=0.2, 
        X″_d=0.25, 
        X″_q=0.25, 
        T″_d0=0.05, 
        T″_q0=0.035, 
        H=4.3, 
        D=0.5
    )

    _avr = Library.AVRTypeI(;
        name=:avr, 
        Ka=20.0, 
        Ke=1.0, 
        Kf=0.08, 
        Ta=0.2, 
        Tf=1.0, 
        Te=0.8, 
        Tr=0.01,
        vr_min=-1.0, 
        vr_max=1.00, 
        E1=2.342286, 
        Se1=0.07, 
        E2=3.123048, 
        Se2=0.314,
        ceiling_function=:quadratic 
    )
    
    _gov = Library.TGOV1(; name=:gov, 
    R=0.05, 
    V_min=0.0, 
    V_max=1.0, 
    T1=0.5, 
    T2=2.1, 
    T3=7.2, 
    DT=0.0)

    other_farm = CompositeInjector([_machine, _gov, _avr], name=:ctrld_gen)

    zipload = Library.ZIPLoad(name=:load,  #region typu D według klasyfikacji Consolidated Edison Inc 
    Pset=0, 
    Qset=0, 
    KpZ=1.31, KqZ=9.2, 
    KpI=-1.94, KqI=-15.27)
    
    piline_fault = Library.PiLine_fault(;R=0.001, X=0.002, G_src=0, B_src=0, G_dst=0, B_dst=0, name=:piline)
    breaker = Library.Breaker(; name=:breaker)

    return (
        solar_wind    = compile_bus(MTKBus(solar_wind_plant; name=:solar_plant_template); assume_io_coupling=true),
        hydro    = compile_bus(MTKBus([gensal, hygov], con; name=:hydro_plant_template); assume_io_coupling=true),
        other    = compile_bus(MTKBus(other_farm; name=:other_plant_template); assume_io_coupling=true),
        load     = compile_bus(MTKBus(zipload; name=:load_template); assume_io_coupling=true),
        junction = compile_bus(MTKBus(; name=:junction_bus_template)),
        slack = compile_bus(Library.SlackAlgebraic(; name=:slack_bus_template)),
        
        breaker  = compile_line(MTKLine(piline_fault); src=:start, dst=:end),
        line     = compile_line(MTKLine(piline_fault); src=:start, dst=:end)
    )
end
