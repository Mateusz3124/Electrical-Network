using NetworkDynamics: NWParameter, VIndex

# Initial guesses for every SauerPai machine (+ AVRTypeI, TGOV1), computed from
# the power flow solution. With the default guesses (δ = 0, V_q = 1, vr = 0) the
# component init does not converge for machines with a large load angle.
function sauerpai_guesses(nw, s)
    pars = NWParameter(nw)
    guesses = Dict{Any,Float64}()
    for k in 1:nv(nw)
        comp = nw[VIndex(k)]
        Symbol("ctrld_gen₊other₊Sn") in NetworkDynamics.psym(comp) || continue
        machine(a) = pars[VIndex(k, Symbol("ctrld_gen₊other₊", a))]
        avr(a) = pars[VIndex(k, Symbol("ctrld_gen₊avr₊", a))]
        gov(a) = pars[VIndex(k, Symbol("ctrld_gen₊gov₊", a))]

        Sn = machine("Sn"); Sb = machine("S_b"); Vn = machine("Vn"); Vb = machine("V_b")
        V = complex(s[VIndex(k, :busbar₊u_r)], s[VIndex(k, :busbar₊u_i)]) * Vb / Vn
        S = complex(s[VIndex(k, :busbar₊P)], s[VIndex(k, :busbar₊Q)]) * Sb / Sn
        I = conj(S / V)

        Rs = machine("R_s"); Xd = machine("X_d"); Xq = machine("X_q")
        Xdp = machine("X′_d"); Xqp = machine("X′_q"); Xls = machine("X_ls")
        E = V + complex(Rs, Xq) * I
        δ = angle(E)
        rot = cis(-(δ - π / 2))
        vd, vq = reim(V * rot)
        id, iq = reim(I * rot)

        eqp = vq + Rs * iq + Xdp * id
        edp = (Xq - Xqp) * iq
        ψppd = eqp - (Xdp - Xls) * id
        ψppq = -edp - (Xqp - Xls) * iq
        vf = vq + Rs * iq + Xd * id
        τm = real(S) + Rs * abs2(I)

        e1 = avr("E1"); e2 = avr("E2"); se1 = avr("Se1"); se2 = avr("Se2")
        sq = sqrt(e1 * se1 / (e2 * se2))
        A = (e1 - e2 * sq) / (1 - sq)
        B = e2 * se2 / (e2 - A)^2
        ceiling = abs(vf) > A ? B * (abs(vf) - A)^2 : 0.0
        vr = avr("Ke") * vf + ceiling
        U = abs(V)

        if !(avr("vr_min") <= vr <= avr("vr_max")) || !(gov("V_min") <= τm <= gov("V_max"))
            @warn "Power flow point of $(comp.name) is outside the AVR/governor limits" vr τm
        end

        vals = Dict(
            :ctrld_gen₊other₊δ => δ,
            :ctrld_gen₊other₊ω => 1.0,
            :ctrld_gen₊other₊V_d => vd,
            :ctrld_gen₊other₊V_q => vq,
            :ctrld_gen₊other₊E′_d => edp,
            :ctrld_gen₊other₊E′_q => eqp,
            :ctrld_gen₊other₊ψ″_d => ψppd,
            :ctrld_gen₊other₊ψ″_q => ψppq,
            :ctrld_gen₊avr₊vfout => vf,
            :ctrld_gen₊avr₊v_fb => 0.0,
            :ctrld_gen₊avr₊vr => vr,
            :ctrld_gen₊avr₊vm => U,
            :ctrld_gen₊avr₊vref => U + vr / avr("Ka"),
            :ctrld_gen₊gov₊τ_m₊u => τm,
            :ctrld_gen₊gov₊xg1 => τm,
            :ctrld_gen₊gov₊xg2 => τm,
            :ctrld_gen₊gov₊p_ref => gov("R") * τm,
        )
        available = Set(vcat(NetworkDynamics.sym(comp), NetworkDynamics.psym(comp)))
        for (sym, val) in vals
            sym in available && (guesses[VIndex(k, sym)] = val)
        end
    end
    return Dict(k => v for (k, v) in guesses)
end
