-- @description Align Items Sequentially to Project Markers
-- @version 1.1
-- @author Adrian Klein
-- @about
--   Aligns selected items sequentially to project markers starting from the edit cursor.
--   Uses snap offset or item start as alignment reference.

--[[
 * Description:
 *   Aligns selected items sequentially to project markers starting from the edit cursor.
 *   Uses only markers (regions are ignored).
 *   Uses snap offset as alignment point (falls back to item start if zero).
 *   Preserves item length and adjusts position only.

 * Notes:
 *   Stops when no more markers are available.
]]


local proj = 0
local EPS = 0.000001

-- ---------- Utility ----------

local function msg(text)
    reaper.ShowMessageBox(text, "Align items to markers", 0)
end

local function get_selected_items_sorted()
    local items = {}
    local count = reaper.CountSelectedMediaItems(proj)

    if count == 0 then return items end

    for i = 0, count - 1 do
        items[#items + 1] = reaper.GetSelectedMediaItem(proj, i)
    end

    table.sort(items, function(a, b)
        local pa = reaper.GetMediaItemInfo_Value(a, "D_POSITION")
        local pb = reaper.GetMediaItemInfo_Value(b, "D_POSITION")
        return pa < pb
    end)

    return items
end

local function get_markers_after_position(start_pos)
    local markers = {}
    local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
    local total = num_markers + num_regions

    for i = 0, total - 1 do
        local retval, isrgn, pos = reaper.EnumProjectMarkers(i)
        if retval and not isrgn and pos >= start_pos - EPS then
            markers[#markers + 1] = pos
        end
    end

    table.sort(markers)
    return markers
end

local function get_snap_offset_position(item)
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local snap = reaper.GetMediaItemInfo_Value(item, "D_SNAPOFFSET")
    return item_pos + snap
end

-- ---------- Main ----------

local items = get_selected_items_sorted()

if #items == 0 then
    msg("Select the items you want to align,\nand place the edit cursor near the starting marker.")
    return
end

local cursor_pos = reaper.GetCursorPosition()
local markers = get_markers_after_position(cursor_pos)

if #markers == 0 then
    msg("No normal markers found after the edit cursor.")
    return
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local marker_index = 1

for i = 1, #items do
    if not markers[marker_index] then break end

    local item = items[i]
    local target_marker_pos = markers[marker_index]

    local align_point = get_snap_offset_position(item)

    local delta = target_marker_pos - align_point
    local current_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", current_pos + delta)

    marker_index = marker_index + 1
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Align selected items sequentially to markers", -1)