-- @description Rename Selected Tracks by Category
-- @version 1.0
-- @author Adrian Klein
-- @about
--   Renames selected tracks using a category name.
--   Supports optional sequential numbering.

--[[
 * ReaScript Name: Rename Selected Tracks by Category
 * Author: Adrian Klein
 * Version: 1.0
 * Description:
 *   Renames selected tracks using a category name.
 *   Supports optional sequential numbering.
]]

local labels = {
  "sfx",
  "foley",
  "dialog",
  "voice",
  "music"
}

-- Build menu string
local menu = table.concat(labels, "|")

-- Show popup menu
gfx.init("", 0, 0)
local choice = gfx.showmenu(menu)
gfx.quit()

if choice < 1 then return end
local baseName = labels[choice]

-- Count selected tracks
local selCount = reaper.CountSelectedTracks(0)
if selCount == 0 then return end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for i = 0, selCount - 1 do
  local track = reaper.GetSelectedTrack(0, i)
  local name = baseName

  if selCount > 1 then
    name = baseName .. " " .. (i + 1)
  end

  reaper.GetSetMediaTrackInfo_String(
    track,
    "P_NAME",
    name,
    true
  )
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Rename selected tracks: " .. baseName, -1)