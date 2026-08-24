function _ri_to_dq(_r, _i, δ)
    _d =  cos(δ)*_r + sin(δ)*_i
    _q = -sin(δ)*_r + cos(δ)*_i
    return _d, _q
end

function _dq_to_ri(_d, _q, δ)
    _r =  cos(δ)*_d - sin(δ)*_q
    _i =  sin(δ)*_d + cos(δ)*_q
    return _r, _i
end

@component function CustomRenewable(; name, defaults...)
    @parameters begin
        status = 1.0, [description="Component status: 1.0 = On, 0.0 = Off"]
        Rf  = 0.01
        Lf = 0.03, [description="Filter reactance [pu] (frequency-normalized inductance)"]
        ω0  = 2π*50
        # PLL
        PLL_Kp = 2π*5
        PLL_Ki = (2π*5)^2/4
        PLL_τ_lpf = 1/(2π*300)
        # CC1
        CC1_KP = 0.36
        CC1_KI = 135.0
        CC1_F  = 0
        CC1_Fcoupl = 0
        # DC link
        C_dc = 1.25
        V_dc = 2.5, [description="DC voltage reference"]
        kp_v_dc, [description="DC voltage PI proportional gain"]
        ki_v_dc, [description="DC voltage PI integral gain"]
        # Reactive current setpoint (constant, from PF)
        iset_q, [guess=0, description="dq-frame reactive current setpoint"]
        # External DC power (solved at initialization)
        P_dc, [guess=0, description="External DC power draw"]
    end

    @variables begin
        v_dc_state(t), [guess=2.5, description="DC capacitor voltage"]
        v_dc_i(t), [guess=0, description="DC voltage PI integrator"]
        v_dc_safe(t), [guess=0, description="DC voltage PI integrator safe"]
    end

    @named filter = LFilter(; ω0, Rf, Lf)
    @named pll = PLL_LPF(; Kp=PLL_Kp, Ki=PLL_Ki, τ_lpf=PLL_τ_lpf)
    @named cc1 = CC1(; Lf=Lf, F=CC1_F, Fcoupl=CC1_Fcoupl, KP=CC1_KP, KI=CC1_KI)

    systems = @named begin
        terminal = Terminal()
    end
    push!(systems, filter)
    push!(systems, pll)
    push!(systems, cc1)

    # DC PI output → active current reference (d-axis in d-aligned convention)
    iset_d_dc = (V_dc - v_dc_state)*kp_v_dc + v_dc_i

    # P_ac: power from converter to AC filter (V_I · i_f in dq frame)
    P_ac = cc1.V_I_d * cc1.i_f_d + cc1.V_I_q * cc1.i_f_q

    eqs = [
        # Terminal connection
        connect(terminal, filter.terminal)
        # PLL measures terminal voltage
        pll.u_r ~ terminal.u_r
        pll.u_i ~ terminal.u_i
        # CC1 measurements in dq frame (using PLL angle)
        [cc1.i_f_d, cc1.i_f_q] .~ _ri_to_dq(filter.i_f_r, filter.i_f_i, pll.θ)
        [cc1.V_C_d, cc1.V_C_q] .~ _ri_to_dq(terminal.u_r, terminal.u_i, pll.θ)
        # CC1 output → filter voltage input
        [filter.V_I_r, filter.V_I_i] .~ _dq_to_ri(cc1.V_I_d, cc1.V_I_q, pll.θ)
        cc1.i_f_ref_d ~ status * iset_d_dc
        cc1.i_f_ref_q ~ status * iset_q

        v_dc_safe ~ max(v_dc_state, 0.1*V_dc)

        # DC link dynamics: Frozen when status is 0.0 to prevent windup and extreme discharge
        C_dc * Dt(v_dc_state) ~ status * (P_ac - P_dc) / v_dc_safe
        Dt(v_dc_i) ~ status * (V_dc - v_dc_state) * ki_v_dc
    ]
    sys = System(eqs, t; name, systems)
    set_mtk_defaults!(sys, defaults)
    return sys
end