to_int(x::Int)  = x
to_int(x::String) = parse(Int, x)
to_int(x::Symbol) = parse(Int, string(x))

R = 0.0
X = 0.0

function get_line(line_template, src, dst, distance=0.1)
    # println(distance)
    line = compile_line(line_template; src=src, dst=dst, name=Symbol(src,dst))
    global R
    global X  
    R += distance * 0.000205
    X += distance * 0.00041
    set_default!(line, Regex("piline₊R\$"), distance * 0.000205)
    set_default!(line, Regex("piline₊X\$"), distance * 0.00041)
    set_default!(line, Regex("piline₊B_src\$"), distance * 0.00006)
    set_default!(line, Regex("piline₊B_dst\$"), distance * 0.00006)
    return line
end

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

counter = 1


sum_solar = 0
sum_other = 0

function handle_plant!(id, info, network, nodes, lines, tpl, p_base, plant_types)
  v = 1.0
  p = parse(Float64, string(info.power))
  global sum_solar
  global sum_other
  if p == 0
    p = 100.0
  end

  p /= p_base

  # if info.source == "wind" || info.source == "solar"
  #   # push!(nodes, get_other(tpl.other, Symbol(id, :_plant), p, 1.0))
  #   push!(nodes, get_wind(tpl.solar_wind, Symbol(id, :_plant), p, 1.0))
  #   plant_types[Symbol(id, :_plant)] = :solar_wind
  #   # push!(nodes, get_other(tpl.other, Symbol(id, :_plant), p, 1.0))
  #   # plant_types[Symbol(id, :_plant)] = :other
  # elseif info.source == "hydro"
  #   push!(nodes, get_hydro(tpl.hydro, Symbol(id, :_plant), p, 1.0))
  #   plant_types[Symbol(id, :_plant)] = :hydro
  #   # push!(nodes, get_other(tpl.other, Symbol(id, :_plant), p, 1.0))
  #   # plant_types[Symbol(id, :_plant)] = :other
  # else
  #   push!(nodes, get_other(tpl.other, Symbol(id, :_plant), p, 1.0))
  #   plant_types[Symbol(id, :_plant)] = :other
  # end

  global counter

  # if counter % 4 < 3 && p > 1
  if counter % 4 > 0 && p > 0.05
    println("other ", id)
    sum_other += p
    push!(nodes, get_other(tpl.other, Symbol(id, :_plant), p, 1.0))
    plant_types[Symbol(id, :_plant)] = :other
  else
    println("solar ", id)
    sum_solar += p
    push!(nodes, get_wind(tpl.solar_wind, Symbol(id, :_plant), p, 1.0))
    plant_types[Symbol(id, :_plant)] = :solar_wind
  end

  counter += 1

  push!(nodes, get_junction(tpl.junction, id))
  push!(lines, get_line(tpl.line, Symbol(id, :_temp), Symbol(id, :_plant)))
  push!(nodes, get_junction(tpl.junction, Symbol(id, :_temp)))
  push!(lines, get_line(tpl.breaker, Symbol(id, :_temp), id))
  
  return p
end

industry = Set([
    Symbol("33756607_load"),
    Symbol("228369813_load"),
    Symbol("225982020_load"),
    Symbol("225991900_load"),
    Symbol("239444041_load"),
    Symbol("205830382_load"),
    Symbol("239276278_load"),
    Symbol("825954426_load"),
    Symbol("666662687_load"),
    Symbol("667172748_load"),
    Symbol("103325119_load"),
    Symbol("766062193_load"),
    Symbol("1351038456_load"),
    Symbol("715026288_load"),
    Symbol("138113463_load"),
    Symbol("105919468_load"),
    Symbol("87792346_load"),
    Symbol("168872812_load"),
    Symbol("161234130_load"),
])

i = 1

function handle_subsation!(id, info, network, nodes, lines, tpl, p, q)
  push!(nodes, get_junction(tpl.junction, id))
  global i
  if should_have_load(info) == 1
    if Symbol(id, :_load) in industry
	    push!(nodes, get_load(tpl.load, Symbol(id, :_load), q , q * 0.0005))
    elseif i % 2 == 0
      push!(nodes, get_load(tpl.load, Symbol(id, :_load), p , p * 0.0005))
    else
      push!(nodes, get_load(tpl.load, Symbol(id, :_load), p , p * 0.0005))
    end
    push!(lines, get_line(tpl.line, id, Symbol(id, :_load)))
    i += 1
    return
  end

  if string(info.highVoltage) == string(info.lowVoltage)
    return
  end

  push!(nodes, get_junction(tpl.junction, Symbol(id, :_low)))
  push!(lines, get_line(tpl.line, id, Symbol(id, :_low)))
end

function haversine_distance(coord1, coord2)
    R = 6371.0
    lat1, lon1 = deg2rad(coord1[1]), deg2rad(coord1[2])
    lat2, lon2 = deg2rad(coord2[1]), deg2rad(coord2[2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = sin(dlat / 2)^2 + cos(lat1) * cos(lat2) * sin(dlon / 2)^2
    c = 2 * atan(sqrt(a), sqrt(1 - a))
    return R * c
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

  lat1, lon1 = deg2rad(info.position[1][1]), deg2rad(info.position[1][2])
  lat2, lon2 = deg2rad(info.position[2][1]), deg2rad(info.position[2][1])

  push!(lines, get_line(tpl.line, start, finish, haversine_distance(info.position[1], info.position[2])))
end


function create_network(data, p_base)
  power_sum = 0.0
  load_count = 0

  nodes = []
  lines = []
  plant_types = Dict{Symbol,Symbol}()

  tpl = initialize_templates()

  for (id, info) in data.network
    if info.type == "plant"
      power_sum += handle_plant!(id, info, data.network, nodes, lines, tpl, p_base, plant_types)
    end
    if info.type == "substation"
      load_count += should_have_load(info)
    end
    if info.type == "line"
      handle_line!(id, info, data.network, nodes, lines, tpl)
    end
  end

  println(load_count)

  power_used = power_sum * 0.97
  p = power_used * 0.5 / (load_count - 19)
  q = power_used * 0.5 / 19.0

  # println(p)
  # println(power_sum * 0.97 / load_count)
  # println(q)
        
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

  push!(nodes, get_slack(tpl.other, :Germany, 1.0))
  push!(unique_lines, get_line(tpl.line, Symbol("Germany"), Symbol("214288187")))
  plant_types[:Germany] = :other

  push!(nodes, get_slack(tpl.other, :France, 1.0))
  push!(unique_lines, get_line(tpl.line, Symbol("France"), Symbol("239441587")))
  plant_types[:France] = :other

  push!(nodes, get_slack(tpl.other, :Netherlands, 1.0))
  push!(unique_lines, get_line(tpl.line, Symbol("Netherlands"), Symbol("825954426")))
  plant_types[:Netherlands] = :other

  global sum_solar
  global sum_other
  
  println(sum_solar)
  println(sum_other)

  nw = Network(nodes, unique_lines)
  return (nw, nodes, unique_lines, plant_types)
end
