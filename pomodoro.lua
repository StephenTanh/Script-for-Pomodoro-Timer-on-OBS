-- Pomodoro 25/5 Timer cho OBS Studio
local obs = obslua

-- Biến lưu trữ tên Nguồn (Source) được chọn từ Menu
local label_source_name = ""
local timer_source_name = ""
local alarm_source_name = ""

-- Trạng thái Timer
local work_minutes = 25
local break_minutes = 5
local mode = "work"          -- "work" | "break"
local remaining = 25 * 60   -- số giây
local running = false
local last_tick = 0
local next_scene = ""
local cycle_count = 0
local auto_switch = false

-- Phát âm thanh thông báo
local function play_alert()
  if alarm_source_name == "" or alarm_source_name == nil then return end
  local source = obs.obs_get_source_by_name(alarm_source_name)
  if source ~= nil then
    obs.obs_source_media_restart(source)
    obs.obs_source_release(source)
  end
end

-- Định dạng thời gian M:SS
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

-- Cập nhật chữ lên Text Source đã chọn
local function update_display()
  if label_source_name ~= "" then
    local source = obs.obs_get_source_by_name(label_source_name)
    if source ~= nil then
      local settings = obs.obs_data_create()
      obs.obs_data_set_string(settings, "text", label_text())
      obs.obs_source_update(source, settings)
      obs.obs_data_release(settings)
      obs.obs_source_release(source)
    end
  end

  if timer_source_name ~= "" then
    local source = obs.obs_get_source_by_name(timer_source_name)
    if source ~= nil then
      local settings = obs.obs_data_create()
      obs.obs_data_set_string(settings, "text", timer_text())
      obs.obs_source_update(source, settings)
      obs.obs_data_release(settings)
      obs.obs_source_release(source)
    end
  end
end

-- Chuyển Scene nếu được bật
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

-- Reset về chế độ hiện tại
local function reset_mode()
  if mode == "work" then
    remaining = work_minutes * 60
  else
    remaining = break_minutes * 60
  end
  update_display()
end

-- Đổi chế độ Focus / Break
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

-- Vòng lặp đếm ngược mỗi giây
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

-- Điều khiển bằng nút bấm
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

-- Giao diện thiết lập Bảng Script (Script Properties)
function script_properties()
  local props = obs.obs_properties_create()

  -- Menu chọn Text Source cho Nhãn (Focus/Break)
  local p_label = obs.obs_properties_add_list(props, "label_source_name", "Label Text Source", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
  obs.obs_property_list_add_string(p_label, "[ None ]", "")

  -- Menu chọn Text Source cho Đồng hồ đếm ngược
  local p_timer = obs.obs_properties_add_list(props, "timer_source_name", "Timer Text Source", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
  obs.obs_property_list_add_string(p_timer, "[ None ]", "")

  -- Menu chọn Media Source cho Âm thanh thông báo
  local p_alarm = obs.obs_properties_add_list(props, "alarm_source_name", "Media Source (Sound Alarm)", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
  obs.obs_property_list_add_string(p_alarm, "[ None ]", "")

  -- Nạp danh sách các Nguồn hiện có vào Menu
  local sources = obs.obs_enum_sources()
  if sources ~= nil then
    for _, source in ipairs(sources) do
      local id = obs.obs_source_get_unversioned_id(source)
      local name = obs.obs_source_get_name(source)
      if id == "text_gdiplus" or id == "text_ft2_source" then
        obs.obs_property_list_add_string(p_label, name, name)
        obs.obs_property_list_add_string(p_timer, name, name)
      elseif id == "ffmpeg_source" then
        obs.obs_property_list_add_string(p_alarm, name, name)
      end
    end
  end
  obs.source_list_release(sources)

  obs.obs_properties_add_int(props, "work_minutes", "Work duration (min)", 1, 180, 1)
  obs.obs_properties_add_int(props, "break_minutes", "Break duration (min)", 1, 60, 1)
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
  label_source_name = obs.obs_data_get_string(settings, "label_source_name")
  timer_source_name = obs.obs_data_get_string(settings, "timer_source_name")
  alarm_source_name = obs.obs_data_get_string(settings, "alarm_source_name")
  work_minutes = obs.obs_data_get_int(settings, "work_minutes")
  break_minutes = obs.obs_data_get_int(settings, "break_minutes")
  auto_switch = obs.obs_data_get_bool(settings, "auto_switch")
  next_scene = obs.obs_data_get_string(settings, "next_scene")

  if not running then
    reset_mode()
  end
end

function script_description()
  return "Pomodoro 25/5 Timer cho OBS Studio.\n\n" ..
         "Hướng dẫn sử dụng:\n" ..
         "1. Tạo 2 nguồn Text (GDI+) trên OBS (ví dụ: 'PomodoroLabel' và 'PomodoroTimer').\n" ..
         "2. Chọn 2 nguồn đó ở menu thả xuống phía dưới.\n" ..
         "3. (Tùy chọn) Thêm 1 Media Source chứa file nhạc để báo hết giờ."
end

function script_defaults(settings)
  obs.obs_data_set_default_int(settings, "work_minutes", 25)
  obs.obs_data_set_default_int(settings, "break_minutes", 5)
  obs.obs_data_set_default_bool(settings, "auto_switch", false)
end
