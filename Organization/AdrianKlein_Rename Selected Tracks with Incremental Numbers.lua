-- @description Rename Selected Tracks with Incremental Numbers
-- @version 1.0
-- @author Adrian Klein
-- @about
--   Renames selected tracks sequentially using a user-defined base name.

--[[
 * ReaScript Name: Rename Selected Tracks with Incremental Numbers
 * Author: Adrian Klein
 * Version: 1.0
 * Description:
 *   Prompts for a base name and renames selected tracks sequentially.
]]

function main()

  local sel_count = reaper.CountSelectedTracks(0)
  if sel_count == 0 then return end

  -- Ask for base name
  local retval, base_name = reaper.GetUserInputs(
    "Rename selected tracks",
    1,
    "Base name:",
    ""
  )

  if not retval or base_name == "" then return end

  reaper.Undo_BeginBlock()

  for i = 0, sel_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local name = base_name .. " " .. (i + 1)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  end

  reaper.Undo_EndBlock(
    "Rename selected tracks with incremental numbers",
    -1
  )

end

-- RUN
reaper.PreventUIRefresh(1)
main()
reaper.TrackList_AdjustWindows(false)
reaper.PreventUIRefresh(-1)