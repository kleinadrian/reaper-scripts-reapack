-- @description Format Selected Tracks to Uppercase
-- @version 1.0
-- @author Adrian Klein
-- @about
--   Converts selected track names to uppercase.

--[[
 * Description:
 *   Converts selected track names to uppercase.
]]

function main()

  reaper.Undo_BeginBlock()

  local sel_count = reaper.CountSelectedTracks(0)
  if sel_count == 0 then return end

  for i = 0, sel_count - 1 do

    local track = reaper.GetSelectedTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

    if name ~= "" then
      name = name:upper()
      reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
    end

  end

  reaper.Undo_EndBlock("Selected tracks to uppercase", -1)

end

-- RUN
reaper.PreventUIRefresh(1)
main()
reaper.TrackList_AdjustWindows(false)
reaper.PreventUIRefresh(-1)