-- @description Append Incremented Numbers to Selected Tracks
-- @version 1.0
-- @author Adrian Klein
-- @about
--   Appends sequential numbers to the end of selected track names.

--[[
 * ReaScript Name: Append Incremented Numbers to Selected Tracks
 * Author: Adrian Klein
 * Version: 1.0
 * Description:
 *   Adds sequential numbers to the end of selected track names.
]]

function main()

  local sel_count = reaper.CountSelectedTracks(0)
  if sel_count == 0 then return end

  reaper.Undo_BeginBlock()

  for i = 0, sel_count - 1 do

    local track = reaper.GetSelectedTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

    if name ~= "" then
      -- Remove trailing numbers (e.g. "kick 12")
      name = name:gsub("%s*%d+$", "")
      -- Append new number
      name = name .. " " .. (i + 1)

      reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
    end

  end

  reaper.Undo_EndBlock("Append incremented numbers to selected tracks", -1)

end

-- RUN
reaper.PreventUIRefresh(1)
main()
reaper.TrackList_AdjustWindows(false)
reaper.PreventUIRefresh(-1)