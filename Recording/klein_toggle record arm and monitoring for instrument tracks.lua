-- @description Toggle Record Arm and Monitoring for Instrument Tracks
-- @version 1.1
-- @author Adrian Klein
-- @about
--   Toggles record arm on selected tracks.
--   Enables monitoring only for instrument-related tracks and skips utility tracks.

--[[
 * Description:
 *   Toggles record arm on selected tracks.
 *   Enables monitoring only for instrument-related tracks.

 * Notes:
 *   Ignores tracks with names containing notes, marker, print, bus, send, master, or video.
 *   Ignores folder parent tracks and tracks without record input.
]]

local IGNORE_WORDS = { "notes", "note", "marker", "markers", "print", "bus", "send", "master", "video" }

local function track_name(track)
  local _, name = reaper.GetTrackName(track, "")
  return name or ""
end

local function name_should_be_ignored(name)
  local n = string.lower(name or "")
  for _, w in ipairs(IGNORE_WORDS) do
    if string.find(n, w, 1, true) then return true end
  end
  return false
end

local function is_folder_parent(track)
  return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
end

local function has_no_record_input(track)
  -- I_RECINPUT < 0 means no input assigned
  return reaper.GetMediaTrackInfo_Value(track, "I_RECINPUT") < 0
end

local function should_ignore_track(track)
  if not track then return true end
  if is_folder_parent(track) then return true end
  if has_no_record_input(track) then return true end
  local name = track_name(track)
  if name_should_be_ignored(name) then return true end
  return false
end

local function has_instrument_fx(track)
  return track and reaper.TrackFX_GetInstrument(track) ~= -1
end

local function has_midi_items(track)
  local item_count = reaper.CountTrackMediaItems(track)
  for i = 0, item_count - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local take = reaper.GetActiveTake(item)
    if take and reaper.TakeIsMIDI(take) then
      return true
    end
  end
  return false
end

local function send_has_midi_enabled(src_track, send_idx)
  local mf = reaper.GetTrackSendInfo_Value(src_track, 0, send_idx, "I_MIDIFLAGS")
  local src_chan_bits = mf & 0x1F
  return src_chan_bits ~= 31
end

local function sends_midi_to_instrument_track(track)
  local send_count = reaper.GetTrackNumSends(track, 0)
  for i = 0, send_count - 1 do
    if send_has_midi_enabled(track, i) then
      local dest_tr = reaper.GetTrackSendInfo_Value(track, 0, i, "P_DESTTRACK")
      if dest_tr and has_instrument_fx(dest_tr) then
        return true
      end
    end
  end
  return false
end

local function is_instrument_related(track)
  if has_instrument_fx(track) then return true end
  if has_midi_items(track) and sends_midi_to_instrument_track(track) then return true end
  return false
end

local function is_armed(track)
  return reaper.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
end

local function is_monitoring_on(track)
  return reaper.GetMediaTrackInfo_Value(track, "I_RECMON") ~= 0
end

local function set_arm(track, on)
  reaper.SetMediaTrackInfo_Value(track, "I_RECARM", on and 1 or 0)
end

local function set_monitor(track, on)
  reaper.SetMediaTrackInfo_Value(track, "I_RECMON", on and 1 or 0)
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local sel_count = reaper.CountSelectedTracks(0)
if sel_count == 0 then
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Toggle arm/monitor for selected tracks (none selected)", -1)
  return
end

local tracks = {}
for i = 0, sel_count - 1 do
  local tr = reaper.GetSelectedTrack(0, i)
  if not should_ignore_track(tr) then
    tracks[#tracks + 1] = { tr = tr, inst = is_instrument_related(tr) }
  end
end

if #tracks == 0 then
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Toggle arm/monitor for selected tracks (all ignored)", -1)
  return
end

local all_on = true
for _, t in ipairs(tracks) do
  if t.inst then
    if not (is_armed(t.tr) and is_monitoring_on(t.tr)) then all_on = false break end
  else
    if not is_armed(t.tr) then all_on = false break end
  end
end

local target_on = not all_on

for _, t in ipairs(tracks) do
  set_arm(t.tr, target_on)
  if t.inst then
    set_monitor(t.tr, target_on)
  end
end

local _, _, sectionID, cmdID = reaper.get_action_context()
reaper.SetToggleCommandState(sectionID, cmdID, target_on and 1 or 0)
reaper.RefreshToolbar2(sectionID, cmdID)

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Toggle arm (+monitor for instrument-related) on selected tracks (safe mode)", -1)