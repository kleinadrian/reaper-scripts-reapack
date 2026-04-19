-- @description Create Sampler for Selected Items
-- @version 1.7
-- @author Adrian Klein
-- @about
--   Creates a sampler track with ReaSamplOmatic5000 from selected items.
--   Sets up track, routing, and monitoring for immediate use.

--[[
 * Description:
 *   Creates a new track below the selected track or at the end if no track is selected.
 *   Names the track using the format "efx <first word of the first sample>" and inserts ReaSamplOmatic5000.
 *   Selects the new track, enables record arm and monitoring, sets MIDI input to all channels,
 *   and disables MIDI input from other tracks in the session.
 *   Opens the ReaSamplOmatic5000 interface.

 * Notes:
 *   - Requires one or more selected items
 *   - If one item is selected, it is mapped across the full keyboard in Note mode
 *   - If multiple items are selected, each gets its own RS5k instance on the same track
 *   - Each instance is mapped starting from C2 on white keys, ascending across octaves
 *   - Samples are trimmed exactly as in the arrangement
]]

local function get_track_index(track)
  return math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1)
end

local function select_only_track(track)
  reaper.Main_OnCommand(40297, 0)
  reaper.SetTrackSelected(track, true)
end

local function disarm_all_tracks()
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 0)
    reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 0)
  end
end

local function arm_for_midi(track)
  reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
  reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 1)
  reaper.SetMediaTrackInfo_Value(track, "I_RECMODE", 0)
  local ALL_MIDI_ALL_CH = 4096 + (63 << 5)
  reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", -1)
  reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", ALL_MIDI_ALL_CH)
end

local function get_first_word(file_path)
  -- Get filename without path
  local filename = file_path:match("([^/\\]+)$") or file_path
  -- Remove extension
  filename = filename:match("(.+)%.[^%.]+$") or filename
  -- Split on space, underscore, dash, dot and return first word
  local first_word = filename:match("([^%s%_%-%.]+ )")
  if not first_word then
    first_word = filename:match("([^%s%_%-%.]+)")
  end
  return first_word or filename
end

local function get_white_keys(root, count)
  local white_offsets = {0, 2, 4, 5, 7, 9, 11}
  local keys = {}
  local root_octave = root - (root % 12)
  local root_in_octave = root % 12
  local start_idx = 1
  for i, v in ipairs(white_offsets) do
    if v == root_in_octave then
      start_idx = i
      break
    end
  end
  local idx = 0
  while #keys < count do
    local offset_pos = (start_idx - 1 + idx) % 7
    local extra_octaves = math.floor((start_idx - 1 + idx) / 7)
    local note = root_octave + extra_octaves * 12 + white_offsets[offset_pos + 1]
    table.insert(keys, note)
    idx = idx + 1
  end
  return keys
end

local function get_file_path(item)
  local take = reaper.GetActiveTake(item)
  if not take then return nil end
  local source = reaper.GetMediaItemTake_Source(take)
  source = reaper.GetMediaSourceParent(source) or source
  local path = reaper.GetMediaSourceFileName(source)
  if path and path ~= "" then return path end
  return nil
end

local function get_trim_offsets(item)
  local take = reaper.GetActiveTake(item)
  if not take then return 0, 1 end

  local source = reaper.GetMediaItemTake_Source(take)
  source = reaper.GetMediaSourceParent(source) or source

  local source_length = reaper.GetMediaSourceLength(source)
  if source_length <= 0 then return 0, 1 end

  local start_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  if playrate <= 0 then playrate = 1 end
  local actual_length = item_length * playrate

  local start_norm = math.max(0, math.min(1, start_offset / source_length))
  local end_norm = math.max(0, math.min(1, (start_offset + actual_length) / source_length))

  return start_norm, end_norm
end

local function import_single_item(new_track, fx, src_item)
  if not src_item then return end
  local file_path = get_file_path(src_item)
  if not file_path then return end

  reaper.TrackFX_SetNamedConfigParm(new_track, fx, "FILE0", file_path)
  reaper.TrackFX_SetNamedConfigParm(new_track, fx, "DONE", "")

  -- Mode: Note
  reaper.TrackFX_SetNamedConfigParm(new_track, fx, "MODE", "2")

  -- Note range start C2, end full range
  reaper.TrackFX_SetParam(new_track, fx, 3, 0.37795275449753)
  reaper.TrackFX_SetParam(new_track, fx, 4, 1.0)

  -- Pitch for start note C3 (-12)
  reaper.TrackFX_SetParam(new_track, fx, 5, 0.42500001192093)

  -- Obey note-offs
  reaper.TrackFX_SetParam(new_track, fx, 11, 1.0)

  -- Trim offsets
  local start_norm, end_norm = get_trim_offsets(src_item)
  reaper.TrackFX_SetParam(new_track, fx, 13, start_norm)
  reaper.TrackFX_SetParam(new_track, fx, 14, end_norm)
end

local function import_multiple_items(new_track, items)
  local C2 = 48
  local white_keys = get_white_keys(C2, #items)

  for i, item in ipairs(items) do
    local file_path = get_file_path(item)
    if file_path then
      local fx = reaper.TrackFX_AddByName(new_track, "ReaSamplOmatic5000 (Cockos)", false, -1)

      reaper.TrackFX_SetNamedConfigParm(new_track, fx, "FILE0", file_path)
      reaper.TrackFX_SetNamedConfigParm(new_track, fx, "DONE", "")

      -- Note range: single white key
      local note = white_keys[i]
      local normalized = note / 127
      reaper.TrackFX_SetParam(new_track, fx, 3, normalized)
      reaper.TrackFX_SetParam(new_track, fx, 4, normalized)

      -- Mode: Sample
      reaper.TrackFX_SetNamedConfigParm(new_track, fx, "MODE", "1")

      -- Obey note-offs
      reaper.TrackFX_SetParam(new_track, fx, 11, 1.0)

      -- Trim offsets
      local start_norm, end_norm = get_trim_offsets(item)
      reaper.TrackFX_SetParam(new_track, fx, 13, start_norm)
      reaper.TrackFX_SetParam(new_track, fx, 14, end_norm)
    end
  end
end

local function main()
  local item_count = reaper.CountSelectedMediaItems(0)
  if item_count == 0 then
    reaper.ShowMessageBox("No items selected.", "Create Sampler", 0)
    return
  end

  local items = {}
  for i = 0, item_count - 1 do
    table.insert(items, reaper.GetSelectedMediaItem(0, i))
  end

  local src_track = reaper.GetSelectedTrack(0, 0)
  local insert_index

  if src_track then
    insert_index = get_track_index(src_track) + 1
  else
    insert_index = reaper.CountTracks(0)
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  reaper.InsertTrackAtIndex(insert_index, true)
  local new_track = reaper.GetTrack(0, insert_index)

  -- Get track name from first item
  local first_file = get_file_path(items[1])
  local first_word = first_file and get_first_word(first_file) or "sampler"
  local track_name = "efx " .. first_word
  reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", track_name, true)

  select_only_track(new_track)
  disarm_all_tracks()
  arm_for_midi(new_track)

  if item_count == 1 then
    local fx = reaper.TrackFX_AddByName(new_track, "ReaSamplOmatic5000 (Cockos)", false, -1)
    import_single_item(new_track, fx, items[1])
  else
    import_multiple_items(new_track, items)
  end

  reaper.TrackList_AdjustWindows(false)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Create efx sampler track with RS5k (MIDI ready)", -1)

  reaper.defer(function()
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS7fb3d74a01cfeae229ad75b83192ca5086acbdbd"), 0)
  end)
end

main()