-- Pomodoro 25/5 Timer for OBS Studio
-- Add as a script: Tools > Scripts > + > select this file
-- A text source named "PomodoroTimer" is created automatically and displayed on your scene.
-- An MP3 alert plays when the timer reaches 0 (Windows: via winmm.dll).

local obs = obslua
local label_source_name = "PomodoroLabel"
local timer_source_name = "PomodoroTimer"
local label_source = nil
local timer_source = nil
local alarm_source_name = "PomodoroAlarm"

-- State
local work_minutes = 25
local break_minutes = 5
local mode = "work"          -- "work" | "break"
local remaining = 25 * 60   -- seconds
local running = false
local last_tick = 0
local next_scene = ""
local cycle_count = 0
local auto_switch = false
local alert_path = ""        -- path to mp3 file

-- Play the alert sound
local function play_alert()
    local source = obs.obs_get_source_by_name(alarm_source_name)

    if source ~= nil then
        obs.obs_source_media_restart(source)
        obs.obs_source_release(source)
    end
end

-- Format seconds as M:SS
local function format_time(secs)
  local m = math.floor(secs / 60)
  local s = secs % 60
  return string.format("%d:%02d", m, s)
end

local function label_text()
  return mode == "work" and "FOCUS" or "BREAK"
end

local function timer_text()
  return format_time(remaining)
end

-- Create a single text source on the current scene
local function create_text_source(name, font_size)
  local s = obs.obs_get_source_by_name(name)
  if s ~= nil then return s end
  local settings = obs.obs_data_create()
  obs.obs_data_set_string(settings, "text", "")
  obs.obs_data_set_bool(settings, "outline", true)
  obs.obs_data_set_int(settings, "outline_size", 4)
  obs.obs_data_set_int(settings, "size", font_size)
  s = obs.obs_source_create("text_gdiplus", name, settings, nil)
  obs.obs_data_release(settings)
  -- add to current scene so it shows on screen
  local scene_source = obs.obs_frontend_get_current_scene()
  if scene_source then
    local scene = obs.obs_scene_from_source(scene_source)
    obs.obs_scene_add(scene, s)
    obs.obs_source_release(scene_source)
  end
  return s
end

-- Create / fetch both sources
local function ensure_source()
  if label_source == nil then
    label_source = create_text_source(label_source_name, 28)
  end
  if timer_source == nil then
    timer_source = create_text_source(timer_source_name, 96)
  end
end

-- Push updated text to both sources
local function update_display()
  ensure_source()
  if label_source ~= nil then
    local settings = obs.obs_source_get_settings(label_source)
    obs.obs_data_set_string(settings, "text", label_text())
    obs.obs_source_update(label_source, settings)
    obs.obs_data_release(settings)
  end
  if timer_source ~= nil then
    local settings = obs.obs_source_get_settings(timer_source)
    obs.obs_data_set_string(settings, "text", timer_text())
    obs.obs_source_update(timer_source, settings)
    obs.obs_data_release(settings)
  end
end

-- Switch scene if requested
local function maybe_switch_scene()
  if not auto_switch then return end
  if next_scene == nil or next_scene == "" then return end
  local scenes = obs.obs_frontend_get_scenes()
  for _, sc in ipairs(scenes) do
    if obs.obs_source_get_name(sc) == next_scene then
      obs.obs_frontend_set_current_scene(sc)
      break
    end
  end
  obs.source_list_release(scenes)
end

-- Reset to the appropriate mode
local function reset_mode()
  if mode == "work" then
    remaining = work_minutes * 60
  else
    remaining = break_minutes * 60
  end
  update_display()
end

-- Switch modes
local function toggle_mode()
  play_alert()
  if mode == "work" then
    mode = "break"
  else
    mode = "work"
  end
  reset_mode()
  maybe_switch_scene()
end

-- Tick callback (called every frame by OBS)
function script_tick(seconds)
  if not running then return end
  local now = os.time()
  if last_tick == 0 then last_tick = now end
  if now - last_tick >= 1 then
    remaining = remaining - 1
    last_tick = now
    if remaining <= 0 then
      cycle_count = cycle_count + 1
      toggle_mode()
    else
      update_display()
    end
  end
end

-- Controls
function start_pause(pressed)
  if not pressed then return end
  running = not running
  last_tick = 0
end

function reset_timer(pressed)
  if not pressed then return end
  running = false
  reset_mode()
end

function switch_mode_now(pressed)
  if not pressed then return end
  toggle_mode()
end

-- Properties
function script_properties()
  local props = obs.obs_properties_create()
  obs.obs_properties_add_int(props, "work_minutes", "Work duration (min)", 1, 180, 1)
  obs.obs_properties_add_int(props, "break_minutes", "Break duration (min)", 1, 60, 1)
  obs.obs_properties_add_path(props, "alert_path", "Alert sound (mp3/wav)", obs.OBS_PATH_FILE,
    "Audio files (*.mp3 *.wav);;All files (*.*)", nil)
  obs.obs_properties_add_bool(props, "auto_switch", "Auto switch scene on mode change")
  obs.obs_properties_add_text(props, "next_scene", "Scene to switch to", obs.OBS_TEXT_DEFAULT)
  local p = obs.obs_properties_create()
  obs.obs_properties_add_button(p, "start_pause_btn", "Start / Pause", start_pause)
  obs.obs_properties_add_button(p, "reset_btn", "Reset", reset_timer)
  obs.obs_properties_add_button(p, "switch_btn", "Switch Mode", switch_mode_now)
  obs.obs_properties_add_group(props, "controls", "Controls", obs.OBS_GROUP_NORMAL, p)
  return props
end

function script_update(settings)
  work_minutes = obs.obs_data_get_int(settings, "work_minutes")
  break_minutes = obs.obs_data_get_int(settings, "break_minutes")
  auto_switch = obs.obs_data_get_bool(settings, "auto_switch")
  next_scene = obs.obs_data_get_string(settings, "next_scene")
  alert_path = obs.obs_data_get_string(settings, "alert_path")
  if not running then
    reset_mode()
  end
end

function script_description()
  return "Pomodoro 25/5 Timer\n\nCreates a text source named \"" .. source_name ..
         "\" showing a countdown that alternates between a focus session and a break.\n\n" ..
         "Controls:\n• Start/Pause – toggles the countdown.\n" ..
         "• Reset – stops and resets the current mode.\n" ..
         "• Switch Mode – jump between work and break.\n\n" ..
         "An MP3/WAV alert plays when the timer reaches 0 (Windows only — uses winmm.dll)."
end

function script_defaults(settings)
  obs.obs_data_set_default_int(settings, "work_minutes", 25)
  obs.obs_data_set_default_int(settings, "break_minutes", 5)
  obs.obs_data_set_default_bool(settings, "auto_switch", false)
end

function script_load(settings)
  ensure_source()
  update_display()
end

function script_unload()
  running = false
  if label_source ~= nil then
    obs.obs_source_remove(label_source)
    obs.obs_source_release(label_source)
    label_source = nil
  end
  if timer_source ~= nil then
    obs.obs_source_remove(timer_source)
    obs.obs_source_release(timer_source)
    timer_source = nil
  end
end