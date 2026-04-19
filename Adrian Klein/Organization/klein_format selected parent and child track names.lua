-- @description Format Selected Parent and Child Track Names
-- @version 1.0
-- @author Adrian Klein
-- @about
--   Capitalizes selected parent track names and converts selected child track names to lowercase.

--[[
 * Description:
 *   Capitalizes selected parent track names.
 *   Converts selected child track names to lowercase.
]]

function main()

  reaper.Undo_BeginBlock()

  local sel_count = reaper.CountSelectedTracks(0)
  if sel_count == 0 then return end

  for i = 0, sel_count - 1 do

    local track = reaper.GetSelectedTrack(0, i)
    local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

    if name ~= "" then
      if depth == 1 then
        -- Parent track: Capitalize first letter
        name = name:lower()
        name = name:gsub("^%l", string.upper)
      else
        -- Child track: lowercase
        name = name:lower()
      end

      reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
    end

  end

  reaper.Undo_EndBlock(
    "Parent tracks capitalized, child tracks lowercase (selected tracks)",
    -1
  )

end

-- RUN
reaper.PreventUIRefresh(1)
main()
reaper.TrackList_AdjustWindows(false)
reaper.PreventUIRefresh(-1)