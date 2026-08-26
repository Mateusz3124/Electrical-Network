using Oxygen
using HTTP
using JSON3
using PowerDynamics
using OrdinaryDiffEqRosenbrock
using OrdinaryDiffEqBDF: FBDF, ODEProblem, solve
using Serialization

sol = deserialize("example2.jld2")
data = JSON3.read(read("names.json", String))
time_data = sol.t

@get "/data" function(req::HTTP.Request)
    target_v_idxs = [VIndex(Symbol(node), :busbar₊P) for node in data.nodes]
    target_e_src_idxs = [EIndex(Symbol(line[1],line[2]), :src₊i_mag) for line in data.lines]
    target_e_dst_idxs = [EIndex(Symbol(line[1],line[2]), :dst₊i_mag) for line in data.lines]

    sol_v = sol(sol.t; idxs=target_v_idxs)
    sol_e = sol(sol.t; idxs=target_e_src_idxs)
    sol_e_dst = sol(sol.t; idxs=target_e_dst_idxs)

    v_dict = Dict(
        data.nodes[i] => [sol_v.u[t_idx][i] for t_idx in eachindex(sol.t)]
        for i in 1:989
    )
    e_dict = Dict(
        (Symbol(data.lines[i][1],data.lines[i][2])) => [sol_e.u[t_idx][i] for t_idx in eachindex(sol.t)]
        for i in 1:1174
    )
    e_dict_dst = Dict(
        (Symbol(data.lines[i][1],data.lines[i][2])) => [sol_e_dst.u[t_idx][i] for t_idx in eachindex(sol.t)]
        for i in 1:1174
    )
    json_dict = Dict(
        "v" => v_dict,
        "e" => e_dict,
        "eDst" => e_dict_dst,
        "t" => sol.t
    )
    return JSON3.write(json_dict)
end

serve(host="0.0.0.0", port=8000)