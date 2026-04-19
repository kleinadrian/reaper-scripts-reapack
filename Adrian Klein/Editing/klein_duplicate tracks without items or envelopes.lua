-- @description Duplicate Tracks Without Items or Envelopes
-- @version 1.4
-- @author Adrian Klein
-- @about
--   Duplicates selected tracks while preserving FX, routing, and settings.
--   Removes all items and automation envelopes and resets automation mode.

--[[
 * Description:
 *   Duplicates selected tracks while preserving FX, routing, and settings.
 *   Removes all media items from duplicates.
 *   Removes all automation envelopes via state chunk.

 * Notes:
 *   Resets automation mode to Trim/Read.
]]

local function delete_all_items_on_track(track)
  for i = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
    local it = reaper.GetTrackMediaItem(track, i)
    reaper.DeleteTrackMediaItem(track, it)
  end
end

local function delete_all_envelopes_via_chunk(track)
  local ok, chunk = reaper.GetTrackStateChunk(track, "", false)
  if not ok or not chunk then return end

  local lines = {}
  for line in chunk:gmatch("[^\n]+") do
    lines[#lines + 1] = line
  end

  local cleaned = {}
  local depth   = 0
  local in_env  = false

  for _, line in ipairs(lines) do
    local stripped = line:match("^%s*(.-)%s*$")
    if not in_env then
      if stripped:match("^<[%u_]*ENV") then
        in_env = true
        depth  = 1
      else
        cleaned[#cleaned + 1] = line
      end
    else
      if stripped:sub(1, 1) == "<" then
        depth = depth + 1
      elseif stripped == ">" then
        depth = depth - 1
        if depth == 0 then in_env = false end
      end
    end
  end

  local new_chunk = table.concat(cleaned, "\n") .. "\n"
  reaper.SetTrackStateChunk(track, new_chunk, false)
end

local function set_only_tracks_selected(tracks)
  reaper.Main_OnCommand(40297, 0)
  for _, tr in ipairs(tracks) do
    reaper.SetTrackSelected(tr, true)
  end
end

local function main()
  local sel_count = reaper.CountSelectedTracks(0)
  if sel_count == 0 then return end

  local src = {}
  for i = 0, sel_count - 1 do
    src[#src + 1] = reaper.GetSelectedTrack(0, i)
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  reaper.Main_OnCommand(40062, 0) -- Track: Duplicate tracks

  -- Find duplicates: inserted immediately after each source track
  local cleaned = {}
  for _, s in ipairs(src) do
    local s_idx     = math.floor(reaper.GetMediaTrackInfo_Value(s, "IP_TRACKNUMBER") - 1)
    local candidate = reaper.GetTrack(0, s_idx + 1)
    if candidate and candidate ~= s then
      cleaned[#cleaned + 1] = candidate
    end
  end

  -- Clean each duplicate
  for _, t in ipairs(cleaned) do
    delete_all_items_on_track(t)
    delete_all_envelopes_via_chunk(t)
    reaper.SetMediaTrackInfo_Value(t, "I_AUTOMODE", 0) -- Trim/Read
  end

  set_only_tracks_selected(cleaned)

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Duplicate tracks (no items, no envelopes)", -1)
end

main()