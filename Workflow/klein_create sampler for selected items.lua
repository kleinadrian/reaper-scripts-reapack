-- @description Create Sampler for Selected Items
-- @version 1.0
-- @author Adrian Klein
-- @about
--   Creates a sampler track with ReaSamplOmatic5000 from selected items.
--   Sets up track, routing, and monitoring for immediate use.

--[[
 * Description:
 *   Creates a new track below the selected track or at the end if no track is selected.
 *   Names the track "efx sampler" and inserts ReaSamplOmatic5000.
 *   Selects the new track, enables record arm and monitoring, and sets MIDI input to all channels.
 *   Opens the ReaSamplOmatic5000 interface.

 * Notes:
 *   Requires manual use of "Import item from arrange" in the sampler to load the selected item.
]]

local function get_track_index(track)
  return math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1)
end

local function select_only_track(track)
  reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
  reaper.SetTrackSelected(track, true)
end

local function arm_for_midi(track)
  -- Arm + monitor
  reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
  reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 1)
  reaper.SetMediaTrackInfo_Value(track, "I_RECMODE", 0) -- record input

  -- Correct value for: Input: MIDI > All MIDI inputs > All channels
  -- 4096 = MIDI flag
  -- (63<<5) = physical input 63 = all MIDI inputs
  -- low 5 bits = channel (0 = all)
  local ALL_MIDI_ALL_CH = 4096 + (63 << 5) -- 6112

  -- Optional refresh toggle (mirrors your manual "none then all")
  reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", -1) -- none
  reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", ALL_MIDI_ALL_CH)
end

local function main()
  local src_track = reaper.GetSelectedTrack(0, 0)
  local insert_index

  if src_track then
    insert_index = get_track_index(src_track) + 1
  else
    insert_index = reaper.CountTracks(0) -- end of session
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Create new track
  reaper.InsertTrackAtIndex(insert_index, true)
  local new_track = reaper.GetTrack(0, insert_index)

  -- Name it
  reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", "efx sampler", true)

  -- Insert RS5k
  local fx = reaper.TrackFX_AddByName(new_track, "ReaSamplOmatic5000 (Cockos)", false, -1)

  -- Select + arm + monitor + MIDI input
  select_only_track(new_track)
  arm_for_midi(new_track)

  reaper.TrackList_AdjustWindows(false)

  -- Open RS5k UI (floating)
  if fx and fx >= 0 then
    reaper.TrackFX_Show(new_track, fx, 3) -- 3 = show floating window
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Create efx sampler track with RS5k (MIDI ready)", -1)
end

main()