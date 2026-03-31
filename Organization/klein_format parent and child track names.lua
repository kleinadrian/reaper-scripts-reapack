-- @description Format Parent and Child Track Names
-- @version 1.0
-- @author Adrian Klein
-- @about
--   Capitalizes parent track names and converts child track names to lowercase.

--[[
 * Description:
 *   Capitalizes parent track names.
 *   Converts child track names to lowercase.
]]

function main()

  reaper.Undo_BeginBlock()

  local count_tracks = reaper.CountTracks(0)

  for i = 0, count_tracks - 1 do

    local track = reaper.GetTrack(0, i)
    local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

    if name ~= "" then
      if depth == 1 then
        -- Parent track: Capitalize first letter only
        name = name:lower()
        name = name:gsub("^%l", string.upper)
      else
        -- Child track: lowercase
        name = name:lower()
      end

      reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
    end

  end

  reaper.Undo_EndBlock("Parent tracks capitalized, child tracks lowercase", -1)

end

-- RUN
if reaper.CountTracks(0) > 0 then
  reaper.PreventUIRefresh(1)
  main()
  reaper.TrackList_AdjustWindows(false)
  reaper.PreventUIRefresh(-1)
end