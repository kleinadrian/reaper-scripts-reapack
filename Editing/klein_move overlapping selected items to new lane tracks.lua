--[[
 * ReaScript Name: Move Overlapping Selected Items to New Lane Tracks
 * Author: Adrian Klein
 * Version: 1.0
 * Description:
 *   Moves overlapping selected items to new lane tracks per source track
 *   Uses deterministic sorting with minimal lane creation
 *   Preserves original track names and colors
 *   Avoids breaking folder closing tracks when possible
]]

-- ====== SETTINGS ======
local EPS = 0.000001         -- overlap tolerance (seconds). Increase slightly if you want "touching" to count as overlap.
local NAME_FMT = "%s %d" -- Lane numbering starts at 2 (Lane 1 = original track)
local COPY_COLOR = true
-- ======================

local function msg(s) reaper.ShowConsoleMsg(tostring(s).."\n") end

local function get_track_index(track)
  -- 0-based
  return math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1)
end

local function get_track_name(track)
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return name ~= "" and name or "Track"
end

local function set_track_name(track, name)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
end

local function get_item_bounds(item)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  return pos, pos + len
end

local function sort_items_by_pos(a, b)
  local ap = reaper.GetMediaItemInfo_Value(a, "D_POSITION")
  local bp = reaper.GetMediaItemInfo_Value(b, "D_POSITION")
  if ap == bp then
    local al = reaper.GetMediaItemInfo_Value(a, "D_LENGTH")
    local bl = reaper.GetMediaItemInfo_Value(b, "D_LENGTH")
    return al < bl
  end
  return ap < bp
end

local function ensure_lane_track(base_track, base_index, lane_num, created_tracks, base_name, base_color)
  -- lane_num: 0 = base track, 1 = Lane 2 track, 2 = Lane 3 track, etc.
  if lane_num == 0 then return base_track end

  if created_tracks[lane_num] and reaper.ValidatePtr2(0, created_tracks[lane_num], "MediaTrack*") then
    return created_tracks[lane_num]
  end

  local insert_index = base_index + lane_num -- directly beneath base, stacked
  reaper.InsertTrackAtIndex(insert_index, true)
  local tr = reaper.GetTrack(0, insert_index)

  -- copy name + color
  set_track_name(tr, string.format(NAME_FMT, base_name, lane_num + 1))
  if COPY_COLOR and base_color ~= 0 then
    reaper.SetTrackColor(tr, base_color)
  end

  created_tracks[lane_num] = tr
  return tr
end

-- Collect selected items grouped by their source track
local sel_cnt = reaper.CountSelectedMediaItems(0)
if sel_cnt == 0 then return end

local items_by_track = {}
local track_order = {}

for i = 0, sel_cnt - 1 do
  local it = reaper.GetSelectedMediaItem(0, i)
  local tr = reaper.GetMediaItem_Track(it)
  if tr then
    local key = tostring(tr)
    if not items_by_track[key] then
      items_by_track[key] = { track = tr, items = {} }
      table.insert(track_order, tr)
    end
    table.insert(items_by_track[key].items, it)
  end
end

-- Process tracks bottom-to-top so inserting tracks doesn't mess indices for tracks we haven't processed yet
table.sort(track_order, function(a, b)
  return get_track_index(a) > get_track_index(b)
end)

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for _, base_track in ipairs(track_order) do
  local key = tostring(base_track)
  local group = items_by_track[key]
  local items = group.items
  table.sort(items, sort_items_by_pos)

  local base_index = get_track_index(base_track)
  local base_name = get_track_name(base_track)
  local base_color = reaper.GetTrackColor(base_track)

  local base_folderdepth = math.floor(reaper.GetMediaTrackInfo_Value(base_track, "I_FOLDERDEPTH"))
  local created_lane_tracks = {} -- lane_num -> track
  local lane_end = {}           -- lane_num -> end_time
  lane_end[0] = -math.huge

  local max_lane = 0

  for _, item in ipairs(items) do
    local s, e = get_item_bounds(item)

    -- Find first lane that doesn't overlap
    local lane = nil
    for l = 0, max_lane do
      if s >= (lane_end[l] - EPS) then
        lane = l
        break
      end
    end

    if lane == nil then
      max_lane = max_lane + 1
      lane = max_lane
      lane_end[lane] = -math.huge
    end

    local target_track = ensure_lane_track(base_track, base_index, lane, created_lane_tracks, base_name, base_color)

    if target_track and target_track ~= reaper.GetMediaItem_Track(item) then
      reaper.MoveMediaItemToTrack(item, target_track)
    end

    lane_end[lane] = math.max(lane_end[lane], e)
  end

  -- Folder safety: if the base track closes a folder (negative depth),
  -- move that closing depth to the last created lane track so lanes stay within the same folder.
  if base_folderdepth < 0 and max_lane > 0 then
    -- base no longer closes
    reaper.SetMediaTrackInfo_Value(base_track, "I_FOLDERDEPTH", 0)
    local last_lane_track = created_lane_tracks[max_lane]
    if last_lane_track then
      reaper.SetMediaTrackInfo_Value(last_lane_track, "I_FOLDERDEPTH", base_folderdepth)
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Move overlapping selected items to new lane tracks", -1)