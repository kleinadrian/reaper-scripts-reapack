-- @description Toggle Selected Track Envelopes in Lanes
-- @version 1.6
-- @author Adrian Klein
-- @about
--   Toggles visibility of envelopes in lanes for selected tracks.
--   Preserves and restores automation mode when hiding or showing envelopes.

--[[
 * Description:
 *   Toggles visibility of envelopes in lanes for selected tracks.
 *   When hiding envelopes, saves automation mode and sets tracks to Read.
 *   When showing envelopes, restores automation mode if still in Read.

 * Notes:
 *   Falls back to action 40292 if no envelopes are present.
]]

local ACTION_HIDE_ALL_ENVS_SELECTED_TRACKS = 40889
local ACTION_VIEW_ENVS_LAST_TOUCHED_TRACK  = 40292

local READ_MODE = 1
local EXTSTATE_SECTION = "Klein_ToggleEnvLanes_AutoModeMemory"

local function get_track_guid(track)
  if not track then return nil end
  local guid = reaper.GetTrackGUID(track)
  if guid and guid ~= "" then return guid end
  return nil
end

local function save_track_automode(track)
  local guid = get_track_guid(track)
  if not guid then return end

  local mode = reaper.GetMediaTrackInfo_Value(track, "I_AUTOMODE")
  mode = math.floor((mode or READ_MODE) + 0.5)

  reaper.SetExtState(EXTSTATE_SECTION, guid, tostring(mode), false)
end

local function restore_track_automode_if_saved(track)
  local guid = get_track_guid(track)
  if not guid then return false end

  local value = reaper.GetExtState(EXTSTATE_SECTION, guid)
  if not value or value == "" then return false end

  local saved_mode = tonumber(value)
  if not saved_mode then
    reaper.DeleteExtState(EXTSTATE_SECTION, guid, false)
    return false
  end

  local current_mode = reaper.GetMediaTrackInfo_Value(track, "I_AUTOMODE")
  current_mode = math.floor((current_mode or READ_MODE) + 0.5)

  -- SAFETY: only restore if still in READ
  if current_mode == READ_MODE then
    reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", saved_mode)
  end

  reaper.DeleteExtState(EXTSTATE_SECTION, guid, false)
  return true
end

local function get_env_vis(env)
  if not env then return nil end

  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if not ok or not chunk then return nil end

  local visible = chunk:match("\nVIS%s+(%d+)")
  return tonumber(visible)
end

local function set_env_visibility(env, visible, in_lane)
  if not env then return false end

  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if not ok or not chunk then return false end

  local old_line = chunk:match("\nVIS [^\n]+")
  if not old_line then return false end

  local old_visible, old_in_lane, old_h = old_line:match("VIS%s+(%d+)%s+(%d+)%s+(%d+)")
  if not old_visible then return false end

  local lane_h = tonumber(old_h) or 0
  if visible == 1 and lane_h < 1 then lane_h = 1 end

  local new_line = string.format("\nVIS %d %d %d", visible, in_lane, lane_h)
  local new_chunk, count = chunk:gsub("\nVIS [^\n]+", new_line, 1)
  if count == 0 then return false end

  return reaper.SetEnvelopeStateChunk(env, new_chunk, false)
end

local function selected_tracks_have_visible_envelopes()
  local sel_count = reaper.CountSelectedTracks(0)

  for i = 0, sel_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
      local env_count = reaper.CountTrackEnvelopes(track)
      for j = 0, env_count - 1 do
        local env = reaper.GetTrackEnvelope(track, j)
        if env then
          local visible = get_env_vis(env)
          if visible == 1 then
            return true
          end
        end
      end
    end
  end

  return false
end

local function selected_tracks_have_any_envelopes()
  local sel_count = reaper.CountSelectedTracks(0)

  for i = 0, sel_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track and reaper.CountTrackEnvelopes(track) > 0 then
      return true
    end
  end

  return false
end

local function show_all_existing_envelopes_in_lanes_on_selected_tracks()
  local sel_count = reaper.CountSelectedTracks(0)

  for i = 0, sel_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
      local env_count = reaper.CountTrackEnvelopes(track)
      for j = 0, env_count - 1 do
        local env = reaper.GetTrackEnvelope(track, j)
        if env then
          set_env_visibility(env, 1, 1)
        end
      end
    end
  end
end

local function save_selected_tracks_automode_and_set_read()
  local sel_count = reaper.CountSelectedTracks(0)

  for i = 0, sel_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
      save_track_automode(track)
      reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", READ_MODE)
    end
  end
end

local function restore_saved_automode_for_selected_tracks()
  local sel_count = reaper.CountSelectedTracks(0)

  for i = 0, sel_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
      restore_track_automode_if_saved(track)
    end
  end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local sel_count = reaper.CountSelectedTracks(0)

if sel_count > 0 then
  if selected_tracks_have_visible_envelopes() then
    save_selected_tracks_automode_and_set_read()
    reaper.Main_OnCommand(ACTION_HIDE_ALL_ENVS_SELECTED_TRACKS, 0)
  else
    if selected_tracks_have_any_envelopes() then
      show_all_existing_envelopes_in_lanes_on_selected_tracks()
      restore_saved_automode_for_selected_tracks()
    else
      reaper.Main_OnCommand(ACTION_VIEW_ENVS_LAST_TOUCHED_TRACK, 0)
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Toggle envelopes with safe automode restore", -1)