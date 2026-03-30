-- @description Import Folder Content to Separate Tracks
-- @version 3.1
-- @author Adrian Klein
-- @about
--   Imports audio files from a folder to separate tracks at the "=START" marker.
--   Sets tempo, updates reference region, and prepares the project automatically.

--[[
 * ReaScript Name: Import Folder Content to Separate Tracks
 * Author: Adrian Klein
 * Version: 3.1
 * Description:
 *   Imports all audio files from a selected folder to separate tracks at marker "=START".
 *   Renames tracks from filenames and sets project tempo from MIDI map or folder name.
 *   Updates or creates region "reference print" to match imported content.
 *   Sets loop range, frames arrange view, limits project length, and selects imported tracks.
 *
 * Folder Format:
 *   - "Song Title 130bpm"
 *   - "Song Title 130bpm 4/4"
 *   - MIDI tempo map in folder overrides BPM/time signature.
 *
 * Behavior:
 *   1. Finds marker "=START" and imports all audio files at that position.
 *   2. Renames tracks based on filenames.
 *   3. Applies MIDI tempo map if present, otherwise uses folder BPM/time signature.
 *   4. Updates or creates region "reference print" to longest imported file.
 *   5. Sets loop points, frames arrange view, limits project length, selects tracks.
 *   6. Moves marker "=END" to project end if it exists.
]]

local REGION_NAME = "reference print"
local START_MARKER_NAME = "=START"
local END_MARKER_NAME = "=END"

local SUPPORTED_AUDIO_EXT = {
  wav=true, aif=true, aiff=true, flac=true, mp3=true, m4a=true,
  ogg=true, opus=true, w64=true, caf=true, bwf=true, rf64=true
}

local function show_msg(msg)
  reaper.ShowMessageBox(tostring(msg), "import folder content to separate tracks", 0)
end

local function trim_trailing_slash(path)
  return path:gsub("[/\\]+$", "")
end

local function get_extension(filename)
  return filename:match("%.([^.]+)$")
end

local function get_filename_without_extension(path)
  local name = path:match("([^/\\]+)$") or path
  return name:gsub("%.[^.]+$", "")
end

local function cleanup_track_name(name)
  if not name or name == "" then return name end

  local cleaned = name

  -- Remove leading spaces first
  cleaned = cleaned:gsub("^%s+", "")

  -- Remove leading numbers with optional separators like:
  -- 01. name
  -- 01 name
  -- 01_name
  -- 01-name
  -- 1.name
  -- 1_name
  -- 001-name
  cleaned = cleaned:gsub("^%d+[%s%._%-]+", "")

  -- Clean any leftover leading separators/spaces just in case
  cleaned = cleaned:gsub("^[%s%._%-]+", "")

  -- Trim trailing spaces
  cleaned = cleaned:gsub("%s+$", "")

  -- Safety fallback: if somehow everything got stripped, return original
  if cleaned == "" then
    return name
  end

  return cleaned
end

local function get_last_path_part(path)
  local trimmed = trim_trailing_slash(path)
  return trimmed:match("([^/\\]+)$") or trimmed
end

local function join_path(dir, file)
  local sep = package.config:sub(1,1)
  if dir:sub(-1) == "/" or dir:sub(-1) == "\\" then
    return dir .. file
  end
  return dir .. sep .. file
end

local function choose_folder()
  if reaper.APIExists("JS_Dialog_BrowseForFolder") then
    local ok, folder = reaper.JS_Dialog_BrowseForFolder("Select folder with audio files", "")
    if ok == 1 and folder and folder ~= "" then
      return trim_trailing_slash(folder)
    end
    return nil
  end

  local retval, input = reaper.GetUserInputs("Select folder", 1, "Folder path:", "")
  if retval and input and input ~= "" then
    return trim_trailing_slash(input)
  end

  return nil
end

local function collect_files_by_ext(folder, allowed_exts)
  local files = {}
  reaper.EnumerateFiles(folder, -1)

  local i = 0
  while true do
    local fn = reaper.EnumerateFiles(folder, i)
    if not fn then break end

    local ext = get_extension(fn)
    if ext and allowed_exts[ext:lower()] then
      files[#files + 1] = join_path(folder, fn)
    end

    i = i + 1
  end

  table.sort(files, function(a, b)
    return a:lower() < b:lower()
  end)

  return files
end

local function collect_audio_files(folder)
  return collect_files_by_ext(folder, SUPPORTED_AUDIO_EXT)
end

local function collect_midi_files(folder)
  return collect_files_by_ext(folder, { mid=true, midi=true })
end

local function deselect_all_tracks()
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local tr = reaper.GetTrack(0, i)
    reaper.SetTrackSelected(tr, false)
  end
end

local function find_marker_position_by_name(target_name)
  local i = 0
  while true do
    local retval, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers(i)
    if retval == 0 then break end

    if not isrgn and name == target_name then
      return pos, idx
    end

    i = i + 1
  end

  return nil, nil
end

local function move_marker_if_exists(target_name, new_pos)
  local i = 0
  while true do
    local retval, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers(i)
    if retval == 0 then break end

    if not isrgn and name == target_name then
      reaper.SetProjectMarker2(0, idx, false, new_pos, 0, target_name)
      return true
    end

    i = i + 1
  end

  return false
end

local function get_or_create_region(start_pos, end_pos)
  local i = 0
  while true do
    local retval, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers(i)
    if retval == 0 then break end

    if isrgn and name == REGION_NAME then
      reaper.SetProjectMarker2(0, idx, true, start_pos, end_pos, REGION_NAME)
      return idx, false
    end

    i = i + 1
  end

  local new_idx = reaper.AddProjectMarker2(0, true, start_pos, end_pos, REGION_NAME, -1)
  return new_idx, true
end

local function set_loop_points(start_pos, end_pos)
  reaper.GetSet_LoopTimeRange(true, true, start_pos, end_pos, false)
end

local function set_arrange_view(start_pos, end_pos)
  if end_pos <= start_pos then return end

  local length = end_pos - start_pos
  local end_pad = math.max(length * 0.01, 0.1)
  reaper.GetSet_ArrangeView2(0, true, 0, 0, start_pos, end_pos + end_pad)
end

local function apply_ruler_and_grid_for_tempo()
  reaper.Main_OnCommand(41916, 0) -- Time unit for ruler: Measures.Beats (minimal)
  reaper.Main_OnCommand(40923, 0) -- Grid: Set measure grid
end

local function set_project_length_limit(position)
  if not reaper.APIExists("SNM_SetDoubleConfigVar") then
    return false
  end

  reaper.SNM_SetDoubleConfigVar("projmaxlen", position)

  if reaper.SNM_GetIntConfigVar("projmaxlenuse", -1234) ~= 1 then
    reaper.SNM_SetIntConfigVar("projmaxlenuse", 1)
  end

  reaper.UpdateTimeline()
  return true
end

local function import_file_to_new_track(file_path, track_index, start_pos)
  reaper.InsertTrackAtIndex(track_index, true)
  local track = reaper.GetTrack(0, track_index)
  if not track then
    return nil, nil, "Could not create track for:\n" .. file_path
  end

  deselect_all_tracks()
  reaper.SetTrackSelected(track, true)
  reaper.SetOnlyTrackSelected(track)
  reaper.SetEditCurPos(start_pos, false, false)

  local item_count_before = reaper.CountTrackMediaItems(track)
  reaper.InsertMedia(file_path, 0)
  local item_count_after = reaper.CountTrackMediaItems(track)

  if item_count_after <= item_count_before then
    return nil, nil, "Could not import file:\n" .. file_path
  end

  local item = reaper.GetTrackMediaItem(track, item_count_after - 1)
  if not item then
    return nil, nil, "Imported file but could not retrieve item:\n" .. file_path
  end

  -- Disable loop source for this imported item
  reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)

  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  reaper.SetMediaItemPosition(item, start_pos, false)

  local item_end = start_pos + item_len
  local raw_name = get_filename_without_extension(file_path)
  local clean_name = cleanup_track_name(raw_name)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", clean_name, true)

  return track, item_end, nil
end

local function extract_folder_tempo_info(folder_path)
  local folder_name = get_last_path_part(folder_path)
  if not folder_name or folder_name == "" then return nil, nil, nil end

  local lower_name = folder_name:lower()

  local bpm = lower_name:match("(%d+)%s*bpm")
  bpm = bpm and tonumber(bpm) or nil
  if bpm and (bpm <= 0 or bpm > 999) then bpm = nil end

  local num, den = lower_name:match("(%d+)%s*/%s*(%d+)")
  num = num and tonumber(num) or nil
  den = den and tonumber(den) or nil

  local valid_denoms = { [1]=true, [2]=true, [4]=true, [8]=true, [16]=true, [32]=true, [64]=true }
  if not (num and den and num > 0 and valid_denoms[den]) then
    num, den = nil, nil
  end

  return bpm, num, den
end

local function score_tempo_map_filename(path)
  local name = get_filename_without_extension(path):lower()
  local score = 0

  if name == "tempo" then score = score + 200 end
  if name == "tempo map" then score = score + 200 end
  if name == "tempo-map" then score = score + 200 end

  if name:find("tempo", 1, true) then score = score + 80 end
  if name:find("map", 1, true) then score = score + 50 end
  if name:find("tempo%-map") then score = score + 60 end
  if name:find("tempo map") then score = score + 60 end

  return score
end

local function find_best_tempo_map_file(folder)
  local midi_files = collect_midi_files(folder)
  if #midi_files == 0 then return nil end
  if #midi_files == 1 then return midi_files[1] end

  local best_file = nil
  local best_score = -1

  for _, file in ipairs(midi_files) do
    local score = score_tempo_map_filename(file)
    if score > best_score then
      best_score = score
      best_file = file
    end
  end

  if best_score > 0 then
    return best_file
  end

  return nil
end

local function read_u16_be(s, i)
  local b1, b2 = s:byte(i, i + 1)
  if not b1 or not b2 then return nil end
  return b1 * 256 + b2
end

local function read_u32_be(s, i)
  local b1, b2, b3, b4 = s:byte(i, i + 3)
  if not b1 or not b2 or not b3 or not b4 then return nil end
  return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
end

local function read_vlq(s, i)
  local value = 0
  local byte = nil

  repeat
    byte = s:byte(i)
    if not byte then return nil, i end
    value = value * 128 + (byte % 128)
    i = i + 1
  until byte < 128

  return value, i
end

local function parse_midi_track_for_tempo_events(track_data, events)
  local i = 1
  local abs_tick = 0
  local running_status = nil

  while i <= #track_data do
    local delta
    delta, i = read_vlq(track_data, i)
    if not delta then return false, "Malformed MIDI delta-time." end
    abs_tick = abs_tick + delta

    local status = track_data:byte(i)
    if not status then break end

    local running = false
    if status < 0x80 then
      if not running_status then
        return false, "Malformed MIDI running status."
      end
      status = running_status
      running = true
    else
      i = i + 1
    end

    if status == 0xFF then
      local meta_type = track_data:byte(i)
      i = i + 1

      local meta_len
      meta_len, i = read_vlq(track_data, i)
      if not meta_len then return false, "Malformed MIDI meta-event length." end

      local data = track_data:sub(i, i + meta_len - 1)
      i = i + meta_len

      if meta_type == 0x51 and meta_len == 3 then
        local b1, b2, b3 = data:byte(1, 3)
        local tempo_us = b1 * 65536 + b2 * 256 + b3
        events[#events + 1] = { tick = abs_tick, tempo_us = tempo_us }
      elseif meta_type == 0x58 and meta_len >= 2 then
        local nn, dd = data:byte(1, 2)
        local denom = 2 ^ dd
        events[#events + 1] = { tick = abs_tick, num = nn, den = denom }
      end

      running_status = nil
    elseif status == 0xF0 or status == 0xF7 then
      local syx_len
      syx_len, i = read_vlq(track_data, i)
      if not syx_len then return false, "Malformed MIDI sysex length." end
      i = i + syx_len
      running_status = nil
    else
      local msg_type = math.floor(status / 16)
      local data_len = ((msg_type == 0xC) or (msg_type == 0xD)) and 1 or 2
      i = i + data_len
      running_status = status
    end
  end

  return true
end

local function parse_midi_tempo_map(file_path)
  local f = io.open(file_path, "rb")
  if not f then return nil, "Could not open MIDI tempo map file." end
  local data = f:read("*all")
  f:close()

  if not data or #data < 14 then
    return nil, "MIDI file is too short."
  end

  if data:sub(1, 4) ~= "MThd" then
    return nil, "Not a standard MIDI file."
  end

  local header_len = read_u32_be(data, 5)
  local format = read_u16_be(data, 9)
  local ntrks = read_u16_be(data, 11)
  local division = read_u16_be(data, 13)

  if not header_len or header_len < 6 or not format or not ntrks or not division then
    return nil, "Malformed MIDI header."
  end

  if division >= 0x8000 then
    return nil, "SMPTE-based MIDI tempo maps are not supported by this script."
  end

  local ppq = division
  local pos = 8 + header_len + 1
  local events = {}

  for tr = 1, ntrks do
    if data:sub(pos, pos + 3) ~= "MTrk" then
      return nil, "Malformed MIDI track chunk."
    end

    local tr_len = read_u32_be(data, pos + 4)
    if not tr_len then
      return nil, "Malformed MIDI track length."
    end

    local track_data = data:sub(pos + 8, pos + 7 + tr_len)
    local ok, err = parse_midi_track_for_tempo_events(track_data, events)
    if not ok then
      return nil, err
    end

    pos = pos + 8 + tr_len
  end

  if #events == 0 then
    return nil, "No tempo or time signature events found in MIDI file."
  end

  table.sort(events, function(a, b)
    if a.tick ~= b.tick then return a.tick < b.tick end
    if a.tempo_us and not b.tempo_us then return true end
    if b.tempo_us and not a.tempo_us then return false end
    return false
  end)

  local merged = {}
  for _, ev in ipairs(events) do
    local last = merged[#merged]
    if last and last.tick == ev.tick then
      if ev.tempo_us then last.tempo_us = ev.tempo_us end
      if ev.num then
        last.num = ev.num
        last.den = ev.den
      end
    else
      merged[#merged + 1] = {
        tick = ev.tick,
        tempo_us = ev.tempo_us,
        num = ev.num,
        den = ev.den
      }
    end
  end

  return {
    ppq = ppq,
    events = merged
  }
end

local function clear_tempo_markers_from(start_pos)
  local count = reaper.CountTempoTimeSigMarkers(0)
  for i = count - 1, 0, -1 do
    local ok, timepos = reaper.GetTempoTimeSigMarker(0, i)
    if ok and timepos >= (start_pos - 0.0000001) then
      reaper.DeleteTempoTimeSigMarker(0, i)
    end
  end
end

local function apply_folder_tempo_info(start_pos, bpm, ts_num, ts_den)
  if not bpm then return false end

  clear_tempo_markers_from(start_pos)

  local current_num, current_den, current_tempo = reaper.TimeMap_GetTimeSigAtTime(0, math.max(0, start_pos - 0.000001))
  local use_num = ts_num or current_num or 4
  local use_den = ts_den or current_den or 4

  reaper.SetTempoTimeSigMarker(0, -1, start_pos, -1, -1, bpm, use_num, use_den, false)
  apply_ruler_and_grid_for_tempo()
  return true
end

local function apply_midi_tempo_map(start_pos, tempo_map)
  if not tempo_map or not tempo_map.events or #tempo_map.events == 0 then
    return false
  end

  clear_tempo_markers_from(start_pos)

  local ppq = tempo_map.ppq
  local events = tempo_map.events

  local current_bpm = 120.0
  local current_num = 4
  local current_den = 4
  local first_idx = 1

  if events[1].tick == 0 then
    if events[1].tempo_us then
      current_bpm = 60000000.0 / events[1].tempo_us
    end
    if events[1].num then
      current_num = events[1].num
      current_den = events[1].den
    end
    first_idx = 2
  end

  reaper.SetTempoTimeSigMarker(0, -1, start_pos, -1, -1, current_bpm, current_num, current_den, false)

  local current_tick = 0
  local elapsed_sec = 0.0

  for i = first_idx, #events do
    local ev = events[i]
    local delta_qn = (ev.tick - current_tick) / ppq
    elapsed_sec = elapsed_sec + (delta_qn * 60.0 / current_bpm)

    local marker_time = start_pos + elapsed_sec
    local new_bpm = current_bpm
    local new_num = current_num
    local new_den = current_den

    if ev.tempo_us then
      new_bpm = 60000000.0 / ev.tempo_us
    end

    if ev.num then
      new_num = ev.num
      new_den = ev.den
    end

    reaper.SetTempoTimeSigMarker(0, -1, marker_time, -1, -1, new_bpm, new_num, new_den, false)

    current_tick = ev.tick
    current_bpm = new_bpm
    current_num = new_num
    current_den = new_den
  end

  apply_ruler_and_grid_for_tempo()
  return true
end

local function configure_tempo_from_folder_or_map(folder, start_pos)
  local tempo_map_file = find_best_tempo_map_file(folder)
  if tempo_map_file then
    local tempo_map = parse_midi_tempo_map(tempo_map_file)
    if tempo_map then
      local ok = apply_midi_tempo_map(start_pos, tempo_map)
      if ok then
        return "midi_map", tempo_map_file
      end
    end
  end

  local bpm, ts_num, ts_den = extract_folder_tempo_info(folder)
  if bpm then
    if apply_folder_tempo_info(start_pos, bpm, ts_num, ts_den) then
      return "folder_bpm", bpm
    end
  end

  return "none", nil
end

local function main()
  local folder = choose_folder()
  if not folder then return end

  local start_pos = find_marker_position_by_name(START_MARKER_NAME)
  if not start_pos then
    show_msg('Marker =START was not found. Please create that marker, then run the script again.')
    return
  end

  local files = collect_audio_files(folder)
  if #files == 0 then
    show_msg("No supported audio files found in that folder.")
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local original_cursor = reaper.GetCursorPosition()
  local imported_tracks = {}
  local start_track_index = reaper.CountTracks(0)
  local longest_end = start_pos

  configure_tempo_from_folder_or_map(folder, start_pos)

  deselect_all_tracks()

  for i = 1, #files do
    local track, item_end, err = import_file_to_new_track(files[i], start_track_index + (i - 1), start_pos)
    if err then
      reaper.SetEditCurPos(original_cursor, false, false)
      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock("import folder content to separate tracks", -1)
      show_msg(err)
      return
    end

    imported_tracks[#imported_tracks + 1] = track

    if item_end > longest_end then
      longest_end = item_end
    end
  end

  get_or_create_region(start_pos, longest_end)
  set_loop_points(start_pos, longest_end)
  set_arrange_view(start_pos, longest_end)
  set_project_length_limit(longest_end)
  move_marker_if_exists(END_MARKER_NAME, longest_end)

  deselect_all_tracks()
  for i = 1, #imported_tracks do
    reaper.SetTrackSelected(imported_tracks[i], true)
  end

  reaper.SetEditCurPos(original_cursor, false, false)
  reaper.UpdateArrange()
  reaper.TrackList_AdjustWindows(false)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("import folder content to separate tracks", -1)
end

main()