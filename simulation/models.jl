include("RenewableModel.jl")

function get_solar(solar_plant_template, name::Symbol, P, v)
    bus = compile_bus(solar_plant_template; name=name)
    set_pfmodel!(bus, pfPQ(P = P, Q = 0.0))
    return bus
end

function get_wind(wind_plant_template, name::Symbol, P, v)
    bus = compile_bus(wind_plant_template; name=name) 
    set_pfmodel!(bus, pfPQ(P = P, Q = 0.0))
    return bus
end

function get_hydro(hydro_plant_template, name::Symbol, P, v)
    bus = compile_bus(hydro_plant_template; name=name)
    set_default!(bus, Regex("gensal₊M_b\$"), P * 1000 / 0.9)
    set_pfmodel!(bus, P*1000 < 50 ? pfPQ(P=P, Q=0.0) : pfPV(P=P, V=1.0))
    return bus
end

function get_other(other_plant_template, name::Symbol, P, v)
    bus = compile_bus(other_plant_template; name=name)
    set_default!(bus, Regex("ctrld_gen₊other₊Sn\$"), P * 1000 / 0.9)

    set_default!(bus, Regex("ctrld_gen₊gov₊V_min\$"), 0.0)
    set_default!(bus, Regex("ctrld_gen₊gov₊V_max\$"), 1.00)
    set_pfmodel!(bus, pfPV(P=P, V=1.0))
    return bus
end

function get_load(bus_load_template, name::Symbol, P, Q) 
    bus_load = compile_bus(bus_load_template; name=name)
    
    set_pfmodel!(bus_load, pfPQ(P = -P, Q = -Q))
    return bus_load
end

function get_junction(junction_bus_template, name::Symbol)
    bus = compile_bus(junction_bus_template; name=name)
    set_pfmodel!(bus, pfPQ(P=0.0, Q=0.0))
    # set_pfmodel!(bus, pfShunt(B=1-e4))
    return bus
end

function get_slack(slack_plant_template, name::Symbol, V=1.0)
    bus = compile_bus(slack_plant_template; name=name)
    set_default!(bus, Regex("ctrld_gen₊gov₊V_min\$"), -5.0)
    set_default!(bus, Regex("ctrld_gen₊avr₊vr_min\$"), -5.0)
    set_default!(bus, Regex("ctrld_gen₊avr₊vr_max\$"), 5.0)
    set_pfmodel!(bus, pfSlack(V=V))
    return bus
end

smooth_max(a, b; δ=1e-4) = 0.5*(a + b + sqrt((a - b)^2 + δ^2))

@mtkmodel ZIPLoadSafe begin
    @parameters begin
        Pset, [guess=-1, description="Active Power at operation point [pu]"]
        Qset, [guess=0, description="Reactive Power at operation point [pu]"]
        Vset, [guess=1, description="Voltage at operation point [pu]"]
        KpZ, [description="Active power constant impedance fraction"]
        KqZ, [description="Reactive power constant impedance fraction"]
        KpI, [description="Active power constant current fraction"]
        KqI, [description="Reactive power constant current fraction"]
        KpC=1-KpZ-KpI, [description="Active power constant power fraction"]
        KqC=1-KqZ-KqI, [description="Reactive power constant power fraction"]
        Vfloor=0.15, [description="Voltage floor (pu) protecting against 1/|V|^2 singularity"]
    end
    @components begin
        terminal = Terminal()
    end
    @variables begin
        Vrel(t), [description="Relative voltage magnitude"]
        P(t), [description="Active Power"]
        Q(t), [description="Reactive Power"]
        denom(t), [description="var"]
    end
    @equations begin
        Vrel ~ sqrt(terminal.u_r^2 + terminal.u_i^2)/Vset
        P ~ Pset*(KpZ*Vrel^2 + KpI*Vrel + KpC)
        Q ~ Qset*(KqZ*Vrel^2 + KqI*Vrel + KqC)
        denom ~ smooth_max(terminal.u_r^2 + terminal.u_i^2, (Vfloor*Vset)^2)
        terminal.i_r ~  (P*terminal.u_r + Q*terminal.u_i) / denom
        terminal.i_i ~  (P*terminal.u_i - Q*terminal.u_r) / denom
    end
end

function initialize_templates()
    solar_wind_plant = CustomRenewable(name=:solar_wind, kp_v_dc=0.785, ki_v_dc=6.17, CC1_KI=339.3, C_dc=0.01)

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
        efd_input=true
    )

    @named scrx = PSSE_SCRX(;
        T_B = 10,
        K = 100,
        T_E = 0.05,
        E_MIN = -10,
        E_MAX = 10,
        r_cr_fd = 0,
        C_SWITCH = false,
        vothsg_input = false,
        vuel_input = false,
        voel_input = false
    )

    hygov = Library.PSSE_HYGOV(name=:swing_hydro_gov, G_MAX=1.0)
    con = [
        connect(scrx.EFD_out, gensal.EFD_in)
        connect(gensal.XADIFD_out, scrx.XADIFD_in)
        connect(gensal.ETERM_out, scrx.ECOMP_in)

        connect(hygov.PMECH_out, gensal.PMECH_in)
        connect(gensal.SPEED_out, hygov.SPEED_in)
    ]

    _machine = Library.SauerPaiMachine(;
        name=:other, 
        vf_input=true, 
        τ_m_input=true, 
        S_b=1000.0, 
        V_b=16.5, 
        ω_b=2*π*50,
        Vn=16.5, 
        R_s=0, 
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
        vr_min=-5.0, 
        vr_max=5.00, 
        E1=2.342286, 
        Se1=0.07, 
        E2=3.123048, 
        Se2=0.314,
        ceiling_function=:quadratic 
    )
    
    _gov = Library.TGOV1(; name=:gov, 
    R=0.05, 
    V_min=0.0, 
    V_max=5.0, 
    T1=0.5, 
    T2=2.1, 
    T3=7.2, 
    DT=0.0)

    other_farm = CompositeInjector([_machine, _gov, _avr], name=:ctrld_gen)

    # zipload = Library.PSSE_Load(
    #     name=:load, 
    #     S_b=1000,
    #     v_0=1
    # )
    zipload = ZIPLoadSafe(Pset=0.0, Qset=0.0, Vset=1.0, KpZ=0.0, KqZ=0.0, KpI=0.0, KqI=0.0, name=:load)
    
    piline_fault = Library.PiLine_fault(;R=0.001, X=0.002, G_src=0, B_src=0, G_dst=0, B_dst=0, name=:piline)
    breaker = Library.Breaker(; name=:breaker)
    shunt = Library.ConstantYLoad(; name=:shunt,
                                       allow_zero_conductance=true)
    return (
        solar_wind    = compile_bus(MTKBus(solar_wind_plant; name=:solar_plant_template); assume_io_coupling=true),
        hydro    = compile_bus(MTKBus([gensal, scrx, hygov], con; name=:hydro_plant_template); assume_io_coupling=true),
        other    = compile_bus(MTKBus(other_farm; name=:other_plant_template); assume_io_coupling=true),
        load     = compile_bus(MTKBus(zipload; name=:load_template); assume_io_coupling=true),
        # junction = compile_bus(MTKBus(Library.ZIPLoad(Pset=0.0, Qset=0.0, Vset=1.0, KpZ=0.0, KqZ=0.0, KpI=0.0, KqI=0.0, name=:junction_zip); name=:junction_bus_template)),
        junction = compile_bus(MTKBus(; name=:junction_bus_template)),
        slack = compile_bus(Library.SlackAlgebraic(; name=:slack_bus_template)),
        
        breaker  = compile_line(MTKLine(piline_fault); src=:start, dst=:end),
        line     = compile_line(MTKLine(piline_fault); src=:start, dst=:end)
    )
end
