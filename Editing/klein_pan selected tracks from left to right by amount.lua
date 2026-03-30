--[[
 * ReaScript Name: Alternate Pan Left-Right for Selected Tracks by Amount
 * Author: Adrian Klein
 * Version: 1.1
 * Description:
 *   Prompts for a pan amount (0-100) and remembers the last value
 *   Alternates selected tracks left and right by the specified amount
]]

local EXT_SECTION = "AK_AlternatePan"
local EXT_KEY = "LastAmount"

function main()

  local sel_count = reaper.CountSelectedTracks(0)
  if sel_count == 0 then return end

  -- get last used value (default = 50)
  local last = reaper.GetExtState(EXT_SECTION, EXT_KEY)
  if last == "" then last = "50" end

  local ok, input = reaper.GetUserInputs(
    "Alternate Pan Amount",
    1,
    "Pan amount (0-100):",
    last
  )

  if not ok then return end

  local amt = tonumber(input)

  if not amt then
    reaper.ShowMessageBox("Please enter a number from 0 to 100.", "Error", 0)
    return
  end

  -- enforce limits
  if amt < 0 then amt = 0 end
  if amt > 100 then amt = 100 end

  -- remember value for next run
  reaper.SetExtState(EXT_SECTION, EXT_KEY, tostring(amt), true)

  local pan_abs = amt / 100.0

  reaper.Undo_BeginBlock()

  for i = 0, sel_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local pan = (i % 2 == 0) and -pan_abs or pan_abs
    reaper.SetMediaTrackInfo_Value(track, "D_PAN", pan)
  end

  reaper.Undo_EndBlock("Alternate pan left-right for selected tracks by amount", -1)

end

reaper.PreventUIRefresh(1)
main()
reaper.TrackList_AdjustWindows(false)
reaper.PreventUIRefresh(-1)