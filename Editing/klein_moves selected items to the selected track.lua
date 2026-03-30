--[[
 * ReaScript Name: Move Selected Items to Selected Track
 * Author: Adrian Klein
 * Version: 1.0
 * Description:
 *   Moves selected items from any track to the selected destination track
 *   Preserves exact item positions
]]

local function get_destination_track()
  local last = reaper.GetLastTouchedTrack()
  if last and reaper.IsTrackSelected(last) then
    return last
  end
  local first_sel = reaper.GetSelectedTrack(0, 0)
  return first_sel
end

local function main()
  local dest = get_destination_track()
  if not dest then
    reaper.ShowMessageBox("No destination track selected.\nSelect a track (and optionally touch it last), then run again.", "Move items", 0)
    return
  end

  local item_count = reaper.CountSelectedMediaItems(0)
  if item_count == 0 then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Collect items first (selection list changes as you move items)
  local items = {}
  for i = 0, item_count - 1 do
    items[#items + 1] = reaper.GetSelectedMediaItem(0, i)
  end

  for _, item in ipairs(items) do
    if item then
      reaper.MoveMediaItemToTrack(item, dest)
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Move selected items to selected track (keep position)", -1)
end

main()