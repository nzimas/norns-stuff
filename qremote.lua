local mod     = require 'core/mods'
local script  = require 'core/script'
local tabutil = require 'tabutil'
local midi    = require 'midi'

--------------------------------------------------
-- State
--------------------------------------------------
local state = {
  script_active = true
}

-- track last CC values for each of the 3 encoder CCs
-- keyed by CC number (e.g. last_cc_vals[58], etc.)
local last_cc_vals = {}

-- which MIDI device to send feedback to (change if needed)
local midi_out_id = 1
local midi_out

--------------------------------------------------
-- Parameter setup
--------------------------------------------------
local function init_params()
  params:add_group("MOD - QREMOTE", 8)

  params:add_option("qremote_active", "qremote active", {"on", "off"}, state.script_active and 1 or 2)
  params:set_action("qremote_active", function(v)
    state.script_active = (v == 1)
  end)

  params:add{type = "number", id = "qremote_mchan", name = "Midi Chan", min = 1, max = 16, default = 10}

  params:add{type = "number", id = "qremote_enc1", name = "Enc1 CC", min = 1, max = 127, default = 58}
  params:add{type = "number", id = "qremote_enc2", name = "Enc2 CC", min = 1, max = 127, default = 62}
  params:add{type = "number", id = "qremote_enc3", name = "Enc3 CC", min = 1, max = 127, default = 63}

  params:add{type = "number", id = "qremote_but1", name = "But1 CC", min = 1, max = 127, default = 85}
  params:add{type = "number", id = "qremote_but2", name = "But2 CC", min = 1, max = 127, default = 87}
  params:add{type = "number", id = "qremote_but3", name = "But3 CC", min = 1, max = 127, default = 88}
end

--------------------------------------------------
-- Minimal mod table
--------------------------------------------------
local m = {}
local nornskey = norns.none
local nornsmidi_event

--------------------------------------------------
-- MIDI event handler
--------------------------------------------------
local function midi_event(id, data)
  local consumed = false

  if state.script_active then
    -- CC status byte check (0xB0 = 176 decimal)
    if (data[1] & 0xF0) == 0xB0 then
      local ch = (data[1] - 0xB0) + 1 -- 1-based channel
      local mchan = params:get("qremote_mchan")

      if ch == mchan then
        local cc  = data[2]
        local val = data[3]

        -- read encoder CC assignments
        local cc_enc1 = params:get("qremote_enc1")
        local cc_enc2 = params:get("qremote_enc2")
        local cc_enc3 = params:get("qremote_enc3")

        -- is this one of the encoders?
        if cc == cc_enc1 or cc == cc_enc2 or cc == cc_enc3 then
          -- difference-based direction
          local old_val = last_cc_vals[cc] or 64
          local diff = val - old_val
          local delta = 0
          if diff > 0 then
            delta = 1
          elseif diff < 0 then
            delta = -1
          end

          if delta ~= 0 then
            -- figure out which Norns encoder index to pass
            local enc_index = (cc == cc_enc1) and 1
                           or (cc == cc_enc2) and 2
                           or (cc == cc_enc3) and 3
            _norns.enc(enc_index, delta)
            consumed = true
          end

          -- if we are near boundary, snap back to 64 so we don't get stuck
          if val <= 6 or val >= 121 then
            if midi_out then
              midi_out:cc(cc, 64, mchan)
            end
            last_cc_vals[cc] = 64
          else
            -- otherwise just remember this new value
            last_cc_vals[cc] = val
          end
        end

        -- read button CC assignments
        local but1 = params:get("qremote_but1")
        local but2 = params:get("qremote_but2")
        local but3 = params:get("qremote_but3")

        -- is this a button CC?
        if cc == but1 then
          _norns.key(1, (val > 0) and 1 or 0)
          consumed = true
        elseif cc == but2 then
          _norns.key(2, (val > 0) and 1 or 0)
          consumed = true
        elseif cc == but3 then
          _norns.key(3, (val > 0) and 1 or 0)
          consumed = true
        end
      end
    end
  end

  if not consumed then
    -- pass unhandled events to normal Norns MIDI
    nornsmidi_event(id, data)
  end
end

--------------------------------------------------
-- Hooks
--------------------------------------------------
mod.hook.register("system_post_startup", "qremote-sys-post-startup", function()
  state.system_post_startup = true

  -- connect for sending boundary snap-back
  midi_out = midi.connect(midi_out_id)

  local script_clear = script.clear
  script.clear = function()
    local is_restart = (tabutil.count(params.lookup) == 0)
    script_clear()
    init_params()
  end

  -- intercept normal Norns MIDI
  nornsmidi_event = _norns.midi.event
  _norns.midi.event = midi_event
end)

mod.hook.register("script_pre_init", "qremote-pre-init", function()
end)

--------------------------------------------------
-- Minimal mod menu
--------------------------------------------------
m.key = function(n, z)
  if n == 2 and z == 1 then
    mod.menu.exit()
  end
end

m.enc = function(n, d)
  mod.menu.redraw()
end

m.redraw = function()
  screen.clear()
  screen.move(64, 40)
  screen.text_center("QREMOTE")
  screen.update()
end

m.init = function() end
m.deinit = function() end

mod.menu.register(mod.this_name, m)

--------------------------------------------------
-- Optional library API
--------------------------------------------------
local api = {}
api.get_state = function()
  return state
end

return api
