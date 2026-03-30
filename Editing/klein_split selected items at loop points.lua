-- @description Split selected items at loop points
-- @version 1.1
-- @author Adrian Klein
-- @about
--   Splits selected items at loop start and end points.
--   Selects only the resulting pieces inside the loop range.

--[[
 * ReaScript Name: Split Selected Items at Loop Points and Select Inside Pieces
 * Author: Adrian Klein
 * Version: 1.1
 * Description:
 *   Splits selected items at loop start and end points
 *   Selects only the resulting pieces inside the loop range
]]

local function is_item_locked(item)
  return reaper.GetMediaItemInfo_Value(item, "C_LOCK") ~= 0
end

local function is_track_locked(track)
  return track and reaper.GetMediaTrackInfo_Value(track, "C_LOCK") ~= 0
end

local function main()
  local sel_count = reaper.CountSelectedMediaItems(0)
  if sel_count == 0 then return end

  -- LOOP POINTS ONLY
  local loop_start, loop_end = reaper.GetSet_LoopTimeRange2(0, false, true, 0, 0, false)
  if loop_end <= loop_start then return end

  local items = {}
  for i = 0, sel_count - 1 do
    items[#items + 1] = reaper.GetSelectedMediaItem(0, i)
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  reaper.SelectAllMediaItems(0, false)

  for _, item in ipairs(items) do
    if item and reaper.ValidatePtr2(0, item, "MediaItem*") then
      local track = reaper.GetMediaItemTrack(item)

      if not is_item_locked(item) and not is_track_locked(track) then
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = pos + len

        local overlaps = (item_end > loop_start and pos < loop_end)

        if overlaps then
          local piece_to_select = nil

          local starts_before = pos < loop_start
          local ends_after = item_end > loop_end

          if starts_before and ends_after then
            reaper.SplitMediaItem(item, loop_end)
            piece_to_select = reaper.SplitMediaItem(item, loop_start)

          elseif starts_before and item_end > loop_start and item_end <= loop_end then
            piece_to_select = reaper.SplitMediaItem(item, loop_start)

          elseif pos >= loop_start and pos < loop_end and ends_after then
            reaper.SplitMediaItem(item, loop_end)
            piece_to_select = item

          elseif pos >= loop_start and item_end <= loop_end then
            piece_to_select = item
          end

          if piece_to_select and reaper.ValidatePtr2(0, piece_to_select, "MediaItem*") then
            reaper.SetMediaItemSelected(piece_to_select, true)
          end
        end
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Split selected items at loop points and select inside pieces", -1)
end

main()