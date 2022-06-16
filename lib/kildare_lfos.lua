-- adapted from @markeats

local musicutil = require 'musicutil'

local lfos = {}
lfos.count = 16
lfos.update_freq = 128
lfos.freqs = {}
lfos.progress = {}
lfos.values = {}
lfos.rand_values = {}

lfos.rates = {1/16,1/8,1/4,5/16,1/3,3/8,1/2,3/4,1,1.5,2,3,4,6,8,16,32,64,128,256,512,1024}
lfos.rates_as_strings = {"1/16","1/8","1/4","5/16","1/3","3/8","1/2","3/4","1","1.5","2","3","4","6","8","16","32","64","128","256","512","1024"}
local drums = {'bd','sd','tm','cp','rs','cb','hh','delay','reverb','main'}

local ivals = {}
for k,v in pairs(drums) do
  ivals[v] = {1 + (16*(k-1)), (16 * k)}
end

lfos.delay_params = {'time', 'level', 'feedback', 'spread', 'lpHz', 'hpHz', 'filterQ'}
lfos.reverb_params = {'decay', 'preDelay', 'earlyDiff', 'lpHz', 'modFreq', 'modDepth', 'level', 'thresh', 'slopeBelow', 'slopeAbove'}
lfos.main_params = {'lSHz', 'lSdb', 'lSQ', 'hSHz', 'hSdb', 'hSQ', 'eqHz', 'eqdb', 'eqQ'}

lfos.params_list = {}

lfos.min_specs = {}
lfos.max_specs = {}

lfos.last_param = {}
for i = 1,lfos.count do
  lfos.last_param[i] = "empty"
end

function lfos.add_params(poly)
  for k,v in pairs(ivals) do
    lfos.min_specs[k] = {}
    lfos.max_specs[k] = {}
    local i = 1
    local param_group = (k ~= "delay" and k ~= "reverb" and k ~= "main") and kildare_drum_params or kildare_fx_params
    for key,val in pairs(param_group[k]) do
      if param_group[k][key].type ~= "separator" then
        if (poly == nil and val.id ~= "poly") or (poly == true) then
          lfos.min_specs[k][i] = {
            min = param_group[k][key].min,
            max = param_group[k][key].max,
            warp = param_group[k][key].warp,
            step = 0.01,
            default = param_group[k][key].default,
            quantum = 0.01,
            formatter = param_group[k][key].formatter
          }
          lfos.max_specs[k][i] = {
            min = param_group[k][key].min,
            max = param_group[k][key].max,
            warp = param_group[k][key].warp,
            step = 0.01,
            default = param_group[k][key].max,
            quantum = 0.01,
            formatter = param_group[k][key].formatter
          }
          i = i+1 -- do not increment by the separators' gaps...
        end
      end
    end
  end

  lfos.build_params_static(poly)

  params:add_group("lfos",lfos.count * 12)
  for i = 1,lfos.count do
    if drums[util.wrap(i,1,#drums)] == "delay" then
      lfos.last_param[i] = "time"
    elseif drums[util.wrap(i,1,#drums)] == "reverb" then
      lfos.last_param[i] = "decay"
    elseif drums[util.wrap(i,1,#drums)] == "main" then
      lfos.last_param[i] = "lSHz"
    else
      if poly then
        lfos.last_param[i] = "poly"
      else
        lfos.last_param[i] = "amp"
      end
    end
    params:add_separator("lfo "..i)
    params:add_option("lfo_"..i,"state",{"off","on"},1)
    params:set_action("lfo_"..i,function(x)
      lfos.sync_lfos(i)
      if x == 1 then
        lfos.return_to_baseline(i,true,poly)
        params:hide("lfo_target_track_"..i)
        params:hide("lfo_target_param_"..i)
        params:hide("lfo_depth_"..i)
        params:hide("lfo_min_"..i)
        params:hide("lfo_max_"..i)
        params:hide("lfo_mode_"..i)
        params:hide("lfo_beats_"..i)
        params:hide("lfo_free_"..i)
        params:hide("lfo_shape_"..i)
        params:hide("lfo_reset_"..i)
        _menu.rebuild_params()
      elseif x == 2 then
        params:show("lfo_target_track_"..i)
        params:show("lfo_target_param_"..i)
        params:show("lfo_depth_"..i)
        params:show("lfo_min_"..i)
        params:show("lfo_max_"..i)
        params:show("lfo_mode_"..i)
        if params:get("lfo_mode_"..i) == 1 then
          params:show("lfo_beats_"..i)
        else
          params:show("lfo_free_"..i)
        end
        params:show("lfo_shape_"..i)
        params:show("lfo_reset_"..i)
        _menu.rebuild_params()
      end
    end)
    params:add_option("lfo_target_track_"..i, "track", drums, 1)
    params:set_action("lfo_target_track_"..i,
      function(x)
        local param_id = params.lookup["lfo_target_param_"..i]
        params.params[param_id].options = lfos.params_list[drums[x]].names
        params.params[param_id].count = tab.count(params.params[param_id].options)
        lfos.rebuild_param("min",i)
        lfos.rebuild_param("max",i)
        lfos.return_to_baseline(i,nil,poly)
      end
    )
    params:add_option("lfo_target_param_"..i, "param",lfos.params_list[drums[1]].names,1)
    params:set_action("lfo_target_param_"..i,
      function(x)
        lfos.rebuild_param("min",i)
        lfos.rebuild_param("max",i)
        lfos.return_to_baseline(i,nil,poly)
      end
    )
    params:add_number("lfo_depth_"..i,"depth",0,100,0,function(param) return (param:get().."%") end)
    params:set_action("lfo_depth_"..i, function(x) if x == 0 then lfos.return_to_baseline(i,true,poly) end end)

    local target_track = params:string("lfo_target_track_"..i)
    local target_param = params:get("lfo_target_param_"..i)
    params:add{
      type='control',
      id="lfo_min_"..i,
      name="lfo min",
      controlspec = controlspec.new(
        lfos.min_specs[target_track][target_param].min,
        lfos.min_specs[target_track][target_param].max,
        lfos.min_specs[target_track][target_param].warp,
        lfos.min_specs[target_track][target_param].step,
        lfos.min_specs[target_track][target_param].min,
        '',
        lfos.min_specs[target_track][target_param].quantum
      )
    }
    params:add{
      type='control',
      id="lfo_max_"..i,
      name="lfo max",
      controlspec = controlspec.new(
        lfos.min_specs[target_track][target_param].min,
        lfos.min_specs[target_track][target_param].max,
        lfos.min_specs[target_track][target_param].warp,
        lfos.min_specs[target_track][target_param].step,
        lfos.min_specs[target_track][target_param].default,
        '',
        lfos.min_specs[target_track][target_param].quantum
      )
    }
    params:add_option("lfo_mode_"..i, "update mode", {"clocked bars","free"},1)
    params:set_action("lfo_mode_"..i,
      function(x)
        if x == 1 and params:string("lfo_"..i) == "on" then
          params:hide("lfo_free_"..i)
          params:show("lfo_beats_"..i)
          lfos.freqs[i] = 1/(lfos.get_the_beats() * lfos.rates[params:get("lfo_beats_"..i)] * 4)
        elseif x == 2 then
          params:hide("lfo_beats_"..i)
          params:show("lfo_free_"..i)
          lfos.freqs[i] = params:get("lfo_free_"..i)
        end
        _menu.rebuild_params()
      end
      )
    params:add_option("lfo_beats_"..i, "rate", lfos.rates_as_strings, tab.key(lfos.rates_as_strings,"1"))
    params:set_action("lfo_beats_"..i,
      function(x)
        if params:string("lfo_mode_"..i) == "clocked bars" then
          lfos.freqs[i] = 1/(lfos.get_the_beats() * lfos.rates[x] * 4)
        end
      end
    )
    params:add{
      type='control',
      id="lfo_free_"..i,
      name="rate",
      controlspec=controlspec.new(0.001,24,'exp',0.001,0.05,'hz',0.001)
    }
    params:set_action("lfo_free_"..i,
      function(x)
        if params:string("lfo_mode_"..i) == "free" then
          lfos.freqs[i] = x
        end
      end
    )
    params:add_option("lfo_shape_"..i, "shape", {"sine","square","random"},1)

    params:add_trigger("lfo_reset_"..i, "reset lfo")
    params:set_action("lfo_reset_"..i, function(x) lfos.reset_phase(i) end)

    params:hide("lfo_free_"..i)
  end

  lfos.reset_phase()
  lfos.update_freqs()
  lfos.lfo_update()
  metro.init(lfos.lfo_update, 1 / lfos.update_freq):start()
  
  function clock.tempo_change_handler(bpm,source)
    print(bpm,source)
    if lfos.tempo_updater_clock then
      clock.cancel(tempo_updater_clock)
    end
    lfos.tempo_updater_clock = clock.run(function() clock.sleep(0.05) lfos.update_tempo() end)
  end

  -- params:bang()
end

function lfos.update_tempo()
  for i = 1,lfos.count do
    lfos.sync_lfos(i)
  end
end

function lfos.return_to_baseline(i,silent,poly)
  local drum_target = params:get("lfo_target_track_"..i)
  local parent = drums[drum_target]
  local param_name = parent.."_"..(lfos.params_list[parent].ids[(params:get("lfo_target_param_"..i))])
  -- print(parent,lfos.last_param[i],params:get(parent.."_"..lfos.last_param[i]))
  if parent ~= "delay" and parent ~= "reverb" and parent ~= "main" then
    if lfos.last_param[i] == "time" or lfos.last_param[i] == "decay" or lfos.last_param[i] == "lSHz" then
      if poly then
        lfos.last_param[i] = "poly"
      else
        lfos.last_param[i] = "amp"
      end
    end
    if lfos.last_param[i] ~= "carHz" and lfos.last_param[i] ~= "poly" and engine.name == "Kildare" then
      engine.set_param(parent,lfos.last_param[i],params:get(parent.."_"..lfos.last_param[i]))
    elseif lfos.last_param[i] == "carHz" and engine.name == "Kildare" then
      engine.set_param(parent,lfos.last_param[i],musicutil.note_num_to_freq(params:get(parent.."_"..lfos.last_param[i])))
    elseif lfos.last_param[i] == "poly" and engine.name == "Kildare" then
      engine.set_param(parent,lfos.last_param[i],params:get(parent.."_"..lfos.last_param[i]) == 1 and 0 or 1)
    end
  elseif (parent == "delay" or parent == "reverb" or parent == "main") and engine.name == "Kildare" then
    local sources = {delay = lfos.delay_params, reverb = lfos.reverb_params, main = lfos.main_params}
    if not tab.contains(sources[parent],lfos.last_param[i]) then
      lfos.last_param[i] = sources[parent][1]
    end
    if parent == "delay" and lfos.last_param[i] == "time" then
      engine["set_"..parent.."_param"](lfos.last_param[i],clock.get_beat_sec() * params:get(parent.."_"..lfos.last_param[i])/128)
    else
      engine["set_"..parent.."_param"](lfos.last_param[i],params:get(parent.."_"..lfos.last_param[i]))
    end
  end
  if not silent then
    lfos.last_param[i] = (lfos.params_list[parent].ids[(params:get("lfo_target_param_"..i))])
  end
end

function lfos.rebuild_param(param,i) -- TODO: needs to respect number
  local param_id = params.lookup["lfo_"..param.."_"..i]
  local target_track = params:string("lfo_target_track_"..i)
  local target_param = params:get("lfo_target_param_"..i)
  local default_value = param == "min"and lfos.min_specs[target_track][target_param].min
    or params:get(target_track.."_"..lfos.params_list[target_track].ids[(target_param)])
  if param == "max" then
    if lfos.min_specs[target_track][target_param].min == default_value then
      default_value = lfos.min_specs[target_track][target_param].max
    end
  end
  params.params[param_id].controlspec = controlspec.new(
    lfos.min_specs[target_track][target_param].min,
    lfos.min_specs[target_track][target_param].max,
    lfos.min_specs[target_track][target_param].warp,
    lfos.min_specs[target_track][target_param].step,
    default_value,
    '',
    lfos.min_specs[target_track][target_param].quantum
  )
  if param == "min" then
    if lfos.min_specs[target_track][target_param].formatter ~= nil then
      params.params[param_id].formatter = lfos.min_specs[target_track][target_param].formatter
    end
  elseif param == "max" then
    if params:string("lfo_target_param_"..i) == "pan" then
      default_value = 1
    end
    params.params[param_id]:set_raw(params.params[param_id].controlspec:unmap(default_value))
    if lfos.max_specs[target_track][target_param].formatter ~= nil then
      params.params[param_id].formatter = lfos.max_specs[target_track][target_param].formatter
    end
  end
end

function lfos.build_params_static(poly)
  for i = 1,#drums do
    local style = drums[i]
    lfos.params_list[style] = {ids = {}, names = {}}
    local parent = (style ~= "delay" and style ~= "reverb" and style ~= "main") and kildare_drum_params[style] or kildare_fx_params[style]
    for j = 1,#parent do
      if parent[j].type ~= "separator" then
        if (parent[j].id == "poly" and poly) or (parent[j].id ~= "poly") then
          table.insert(lfos.params_list[style].ids, parent[j].id)
          table.insert(lfos.params_list[style].names, parent[j].name)
        end
      end
    end

  end
end

function lfos.update_freqs()
  for i = 1, lfos.count do
    lfos.freqs[i] = 1 / util.linexp(1, lfos.count, 1, 1, i)
  end
end

function lfos.reset_phase(which)
  if which == nil then
    for i = 1, lfos.count do
      lfos.progress[i] = math.pi * 1.5
    end
  else
    lfos.progress[which] = math.pi * 1.5
  end
end

function lfos.get_the_beats()
  return 60 / params:get("clock_tempo")
end

function lfos.sync_lfos(i)
  if params:get("lfo_mode_"..i) == 1 then
    lfos.freqs[i] = 1/(lfos.get_the_beats() * lfos.rates[params:get("lfo_beats_"..i)] * 4)
  else
    lfos.freqs[i] = params:get("lfo_free_"..i)
  end
end

function lfos.set_delay_param(param_target,value)
  if param_target == "time" then
    engine.set_delay_param(param_target,clock.get_beat_sec() * value/128)
  else
    engine.set_delay_param(param_target,value)
  end
end

function lfos.send_param_value(target_track, target_id, value)
  if target_track ~= "delay" and target_track ~= "reverb" and target_track ~= "main" then
    engine.set_param(target_track,target_id,value)
  else
    if target_track == "delay" then
      lfos.set_delay_param(target_id,value)
    else
      engine["set_"..target_track.."_param"](target_id,value)
    end
  end
end

function lfos.lfo_update()
  local delta = (1 / lfos.update_freq) * 2 * math.pi
  for i = 1,lfos.count do
    lfos.progress[i] = lfos.progress[i] + delta * lfos.freqs[i]
    local min = params:get("lfo_min_"..i)
    local max = params:get("lfo_max_"..i)
    if min > max then
      local old_min = min
      local old_max = max
      min = old_max
      max = old_min
    end

    local mid = math.abs(min-max)/2
    local percentage = math.abs(max-min) * (params:get("lfo_depth_"..i)/100) -- new
    local target_track = params:string("lfo_target_track_"..i)
    local target_param = params:get("lfo_target_param_"..i)
    local param_name = lfos.params_list[target_track]
    local engine_target = params:get(target_track.."_"..param_name.ids[(target_param)])
    local value = util.linlin(-1,1,util.clamp(engine_target-percentage,min,max),util.clamp(engine_target+percentage,min,max),math.sin(lfos.progress[i])) -- new
    mid = util.linlin(min,max,util.clamp(engine_target-percentage,min,max),util.clamp(engine_target+percentage,min,max),mid) -- new
    
    if value ~= lfos.values[i] and (params:get("lfo_depth_"..i)/100 > 0) then
      lfos.values[i] = value
      if params:string("lfo_"..i) == "on" then
        if params:string("lfo_shape_"..i) == "sine" then
          if param_name.ids[(target_param)] == "poly" then
            value = util.linlin(-1,1,min,max,math.sin(lfos.progress[i])) < mid and 0 or 1
          end
          lfos.send_param_value(target_track, param_name.ids[(target_param)], value)
        elseif params:string("lfo_shape_"..i) == "square" then
          local square_value = value >= mid and max or min
          square_value = util.linlin(min,max,util.clamp(engine_target-percentage,min,max),util.clamp(engine_target+percentage,min,max),square_value) -- new
          lfos.send_param_value(target_track, param_name.ids[(target_param)], square_value)
        elseif params:string("lfo_shape_"..i) == "random" then
          local prev_value = lfos.rand_values[i]
          lfos.rand_values[i] = value >= mid and max or min
          local rand_value;
          if prev_value ~= lfos.rand_values[i] then
            rand_value = util.linlin(min,max,util.clamp(engine_target-percentage,min,max),util.clamp(engine_target+percentage,min,max),math.random(math.floor(min*100),math.floor(max*100))/100) -- new
            lfos.send_param_value(target_track, param_name.ids[(target_param)], rand_value)
          end
        end
      end
    end
  end
end

return lfos