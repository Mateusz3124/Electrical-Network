to_int(x::Int)  = x
to_int(x::String) = parse(Int, x)
to_int(x::Symbol) = parse(Int, string(x))

function has_element(array, id)
  for el in array
    if to_int(el) == to_int(id)
      return true
    end
  end
  return false
end

function should_have_load(info)
  if length(info.start) == 1 && (string(info.highVoltage) != string(info.lowVoltage) || parse(Int64, info.highVoltage) <= 70000 || parse(Int64, info.lowVoltage) <= 70000 )
    return 1
  end
  return 0
end

function handle_plant!(id, info, network, nodes, lines, tpl, p_base)
  v = 1.0
  p = parse(Float64, string(info.power))

  if p == 0
    p = 100.0
  end

  p /= p_base

  if info.source == "wind" || info.source == "solar"
    push!(nodes, get_wind(tpl.solar_wind, Symbol(id, :_plant), p, info.voltage))
  elseif info.source == "hydro"
    push!(nodes, get_hydro(tpl.hydro, Symbol(id, :_plant), p, info.voltage))
  else
    push!(nodes, get_other(tpl.other, Symbol(id, :_plant), p, info.voltage))
  end
  
  push!(nodes, get_junction(tpl.junction, id))
  push!(lines, get_line(tpl.line, Symbol(id, :_plant), Symbol(id, :_temp)))
  push!(nodes, get_junction(tpl.junction, Symbol(id, :_temp)))
  push!(lines, get_line(tpl.breaker, Symbol(id, :_temp), id))
  
  return p
end

function handle_subsation!(id, info, network, nodes, lines, tpl, p, q)
  push!(nodes, get_junction(tpl.junction, id))

  if should_have_load(info) == 1
    push!(nodes, get_load(tpl.load, Symbol(id, :_load), p , q))
    push!(lines, get_line(tpl.line, id, Symbol(id, :_load)))
    return
  end

  if string(info.highVoltage) == string(info.lowVoltage)
    return
  end

  push!(nodes, get_junction(tpl.junction, Symbol(id, :_low)))
  push!(lines, get_line(tpl.line, id, Symbol(id, :_low)))
end

function handle_line!(id, info, network, nodes, lines, tpl)
  start = nothing
  finish = nothing 
  
  min_start = parse(Int, string(id))
  
  for el in info.start
    if to_int(el) < min_start
      min_start = to_int(el)
    end
    if network[el].type != "line"
      if network[el].type == "substation" && string(network[el].highVoltage) != string(network[el].lowVoltage) && string(info.voltage) == string(network[el].lowVoltage) && length(network[el].start) != 1
        start = Symbol(el, :_low) 
      else
        start = Symbol(el) 
      end
      break
    end
  end

  if start === nothing
    start = Symbol(min_start, :_junction_start)
    if Symbol(min_start) == id
      push!(nodes, get_junction(tpl.junction, start))
    elseif has_element(network[min_start].end, id)
      start = Symbol(min_start, :_junction_end)
    end
  end
  
  min_end = parse(Int, string(id))
  
  for el in info.end
    if to_int(el) < min_end
      min_end = to_int(el)
    end
    if network[el].type != "line"
      if network[el].type == "substation" && string(network[el].highVoltage) != string(network[el].lowVoltage) && string(info.voltage) == string(network[el].lowVoltage) && length(network[el].start) != 1
        finish = Symbol(el, :_low) 
      else
        finish = Symbol(el) 
      end
      break
    end
  end

  if finish === nothing
    finish = Symbol(min_end, :_junction_end)
    if Symbol(min_end) == id
      push!(nodes, get_junction(tpl.junction, finish))
    elseif has_element(network[min_end].start, id)
      finish = Symbol(min_end, :_junction_start)
    end
  end

  push!(lines, get_line(tpl.line, start, finish))
end


function create_network(data, p_base)
  power_sum = 0.0
  load_count = 0

  nodes = []
  lines = []

  tpl = initialize_templates()

  for (id, info) in data.network
    if info.type == "plant"
      power_sum += handle_plant!(id, info, data.network, nodes, lines, tpl, p_base)
    end
    if info.type == "substation"
      load_count += should_have_load(info)
    end
    if info.type == "line"
      handle_line!(id, info, data.network, nodes, lines, tpl)
    end
  end

  println(load_count)

  p = power_sum / load_count * 0.97
  q = p * 0.005

  println(p)
        
  for (id, info) in data.network
    if info.type == "substation"
      handle_subsation!(id, info, data.network, nodes, lines, tpl, p, q)
    end
  end

  # Clean up duplicate lines
  unique_lines = unique(lines) do l
    ge = l.metadata[:graphelement]
    min(ge.src, ge.dst), max(ge.src, ge.dst)
  end

  # Weird position
  filter!(l -> begin
    ge = l.metadata[:graphelement]
    !(ge.src == Symbol(932604234) || ge.dst == Symbol(932604234))
  end, unique_lines)

  filter!(node -> begin
    !(node.name == Symbol(932604234) || node.name == Symbol("932604234_load"))
  end, nodes)

  #symbolise networks from outside country can consume power or give
  push!(nodes, get_slack(tpl.other, :Germany, 1.0))
  push!(unique_lines, get_line(tpl.line, Symbol("Germany"), Symbol("214288187")))

  push!(nodes, get_slack(tpl.other, :France, 1.0))
  push!(unique_lines, get_line(tpl.line, Symbol("France"), Symbol("239441587")))

  push!(nodes, get_slack(tpl.other, :Netherlands, 1.0))
  push!(unique_lines, get_line(tpl.line, Symbol("Netherlands"), Symbol("825954426")))

  nw = Network(nodes, unique_lines)
  return (nw, nodes, unique_lines)
end