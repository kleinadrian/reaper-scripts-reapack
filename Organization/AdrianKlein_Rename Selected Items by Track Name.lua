-- @description Rename Selected Items by Track Name
-- @version 1.0
-- @author Adrian Klein
-- @about
--   Renames selected items based on their track name.
--   Supports take name appending and smart numbering.

--[[
 * ReaScript Name: Rename Selected Items by Track Name
 * Author: Adrian Klein
 * Version: 1.0
 * Description:
 *   Renames selected items based on their track name.
 *   Uses active take names (what REAPER displays on items).
 *   Supports optional take name appending and smart numbering.
]]

reaper.Undo_BeginBlock()

local tracks = {}
local sel_count = reaper.CountSelectedMediaItems(0)

-- collect selected items per track
for i = 0, sel_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
        local track = reaper.GetMediaItemTrack(item)
        if track then
            if not tracks[track] then
                tracks[track] = {}
            end
            tracks[track][#tracks[track] + 1] = item
        end
    end
end

for track, items in pairs(tracks) do
    -- sort by timeline position
    table.sort(items, function(a, b)
        local pa = reaper.GetMediaItemInfo_Value(a, "D_POSITION")
        local pb = reaper.GetMediaItemInfo_Value(b, "D_POSITION")
        if pa == pb then
            local la = reaper.GetMediaItemInfo_Value(a, "D_LENGTH")
            local lb = reaper.GetMediaItemInfo_Value(b, "D_LENGTH")
            return la < lb
        end
        return pa < pb
    end)

    -- get track name or fallback track number
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if track_name == "" then
        local num = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        track_name = string.format("Track %02d", num)
    end

    -- check if take names are unique and non-empty
    local seen = {}
    local need_numbering = false

    if #items > 1 then
        for _, item in ipairs(items) do
            local take = reaper.GetActiveTake(item)
            local take_name = ""

            if take then
                local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                take_name = tn or ""
            end

            if take_name == "" or seen[take_name] then
                need_numbering = true
                break
            end

            seen[take_name] = true
        end
    end

    -- rename active takes
    for idx, item in ipairs(items) do
        local take = reaper.GetActiveTake(item)
        if take then
            local _, old_take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)

            local new_name = track_name
            if old_take_name and old_take_name ~= "" then
                new_name = new_name .. " - " .. old_take_name
            end

            if need_numbering then
                new_name = new_name .. " " .. idx
            end

            reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
        end
    end
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Rename selected items by track name", -1)