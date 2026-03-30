-- @description Alternate Pan Selected Tracks Left-Right
-- @version 1.1
-- @author Adrian Klein
-- @about
--   Alternates selected tracks between hard left and hard right pan positions.

--[[
 * ReaScript Name: Alternate Pan Selected Tracks Left-Right
 * Author: Adrian Klein
 * Version: 1.1
 * Description:
 *   Alternates selected tracks between hard left and hard right pan positions.
]]

function main()

  local sel_count = reaper.CountSelectedTracks(0)
  if sel_count == 0 then return end

  reaper.Undo_BeginBlock()

  for i = 0, sel_count - 1 do

    local track = reaper.GetSelectedTrack(0, i)

    -- i is zero-based: 0 = first track
    local pan = (i % 2 == 0) and -1.0 or 1.0

    reaper.SetMediaTrackInfo_Value(track, "D_PAN", pan)

  end

  reaper.Undo_EndBlock("Alternate pan left-right for selected tracks", -1)

end

-- RUN
reaper.PreventUIRefresh(1)
main()
reaper.TrackList_AdjustWindows(false)
reaper.PreventUIRefresh(-1)