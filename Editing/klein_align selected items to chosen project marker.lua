--[[
 * ReaScript Name: Align Selected Items to Chosen Project Marker
 * Author: Adrian Klein
 * Version: 1.0
 * Description:
 *   Aligns selected items to a chosen project marker
 *   Filters marker list (excludes negative timecode and markers starting with =, #, &, $)
 *   Remembers last selected marker per project (preselect only)
 *   Alignment priority: take marker, snap offset, item start
 *   Uses absolute alignment and de-stacks items only on collision
]]

--------------------------------------------------
-- ProjExtState (remember last marker per project)
--------------------------------------------------
local EXT_SECTION = "klein_align_items_to_marker"
local EXT_KEY_POS = "last_marker_pos"

local function proj_get_last_pos()
  local ok, s = reaper.GetProjExtState(0, EXT_SECTION, EXT_KEY_POS)
  if ok == 0 then return nil end
  return tonumber(s)
end

local function proj_set_last_pos(pos)
  if type(pos) ~= "number" then return end
  reaper.SetProjExtState(0, EXT_SECTION, EXT_KEY_POS, tostring(pos))
end

--------------------------------------------------
-- Utilities
--------------------------------------------------
local function msg(t)
  reaper.ShowMessageBox(t, "Align Items", 0)
end

local function get_first_take_marker_pos(take)
  if not take then return nil end
  local cnt = reaper.GetNumTakeMarkers(take)
  if not cnt or cnt <= 0 then return nil end

  -- API variants:
  -- A: retval, pos, name, color
  -- B: pos, name, color
  local a, b = reaper.GetTakeMarker(take, 0)
  if type(b) == "number" then return b end
  if type(a) == "number" then return a end
  return nil
end

local function starts_with_special(name)
  local c = name:sub(1,1)
  return (c == "=" or c == "#" or c == "&" or c == "$")
end

--------------------------------------------------
-- Capture selected items
--------------------------------------------------
local items = {}
local selCount = reaper.CountSelectedMediaItems(0)
if selCount == 0 then
  msg("No items selected.")
  return
end

for i = 0, selCount - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  table.insert(items, item)

  if reaper.GetMediaItemInfo_Value(item, "C_LOCK") == 1 then
    msg("Some items are locked. Unlock them and try again.")
    return
  end

  local tr = reaper.GetMediaItemTrack(item)
  if reaper.GetMediaTrackInfo_Value(tr, "C_LOCK") == 1 then
    msg("Some tracks are locked. Unlock them and try again.")
    return
  end
end

--------------------------------------------------
-- Collect CLEAN project markers
--------------------------------------------------
local numMarkers, numRegions = reaper.CountProjectMarkers(0)
if numMarkers == 0 then
  msg("No markers detected.")
  return
end

local markers = {}
local total = numMarkers + numRegions

for i = 0, total - 1 do
  local _, isrgn, pos, _, name = reaper.EnumProjectMarkers(i)
  if not isrgn then
    -- Filter by what REAPER DISPLAYS (matches your list)
    local tc = reaper.format_timestr_pos(pos, "", 0)
    if tc:sub(1,1) ~= "-" then
      local nm = (name and name ~= "") and name or "(unnamed)"
      if not starts_with_special(nm) then
        table.insert(markers, { pos = pos, name = nm })
      end
    end
  end
end

if #markers == 0 then
  msg("No usable markers found.")
  return
end

table.sort(markers, function(a,b) return a.pos < b.pos end)

--------------------------------------------------
-- Preselect last marker (closest by position) per project
--------------------------------------------------
local function find_closest_marker_index(lastPos)
  if type(lastPos) ~= "number" then return 1 end
  local bestIdx = 1
  local bestDist = math.huge
  for i = 1, #markers do
    local d = math.abs(markers[i].pos - lastPos)
    if d < bestDist then
      bestDist = d
      bestIdx = i
    end
  end
  return bestIdx
end

local lastPos = proj_get_last_pos()
local initialSelected = find_closest_marker_index(lastPos)

--------------------------------------------------
-- UI state
--------------------------------------------------
local UI = {
  W = 720, H = 460,
  rowH = 20, pad = 10, topH = 54,
  scroll = 0,
  selected = initialSelected,
  last_cap = 0, last_click = 0,
  dbl_ms = 350,
  done = false, cancel = false,
  target = nil
}

--------------------------------------------------
-- Apply alignment
--------------------------------------------------
local function insertTrackBelow(track)
  local idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
  reaper.InsertTrackAtIndex(idx, true)
  return reaper.GetTrack(0, idx)
end

local function apply_alignment(pos)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local used = {}

  for _, item in ipairs(items) do
    local take = reaper.GetActiveTake(item)
    local offset = get_first_take_marker_pos(take)

    if offset == nil then
      offset = reaper.GetMediaItemInfo_Value(item, "D_SNAPOFFSET") or 0
    end

    reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos - offset)

    local tr = reaper.GetMediaItemTrack(item)
    if used[tr] then
      local nt = insertTrackBelow(tr)
      reaper.MoveMediaItemToTrack(item, nt)
      used[nt] = true
    else
      used[tr] = true
    end
  end

  reaper.UpdateArrange()
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Align items to project marker", -1)
end

--------------------------------------------------
-- Draw UI
--------------------------------------------------
local function draw()
  gfx.set(0.12,0.12,0.12,1)
  gfx.rect(0,0,UI.W,UI.H,1)

  gfx.setfont(1,"Arial",16)
  gfx.set(1,1,1,1)
  gfx.x, gfx.y = UI.pad, UI.pad
  gfx.drawstr("Select a project marker")

  gfx.set(0.75,0.75,0.75,1)
  gfx.x, gfx.y = UI.pad, UI.pad + 24
  gfx.drawstr("Click • Wheel • Enter = OK • Esc = Cancel • Double-click = OK")

  local listH = UI.H - UI.topH - UI.pad
  local rows = math.floor(listH / UI.rowH)
  if rows < 1 then rows = 1 end

  local maxScroll = math.max(0, #markers - rows)
  UI.scroll = math.max(0, math.min(UI.scroll, maxScroll))

  if UI.selected < UI.scroll + 1 then UI.scroll = UI.selected - 1 end
  if UI.selected > UI.scroll + rows then UI.scroll = UI.selected - rows end

  for i = 1, rows do
    local idx = i + UI.scroll
    if idx > #markers then break end

    local y = UI.topH + (i-1)*UI.rowH
    if idx == UI.selected then
      gfx.set(0.25,0.45,0.85,0.35)
      gfx.rect(UI.pad,y,UI.W-UI.pad*2,UI.rowH,1)
    end

    local m = markers[idx]
    local tc = reaper.format_timestr_pos(m.pos,"",0)

    gfx.set(1,1,1,1)
    gfx.setfont(1,"Arial",14)
    gfx.x, gfx.y = UI.pad+6, y+3
    gfx.drawstr(string.format("%3d  %s  %s", idx, tc, m.name))
  end

  gfx.x, gfx.y = UI.pad, UI.H-UI.pad-18
  gfx.drawstr("Selected: "..UI.selected.."  "..markers[UI.selected].name)
end

--------------------------------------------------
-- UI loop (deferred)
--------------------------------------------------
local function loop()
  if UI.done then
    gfx.quit()
    if not UI.cancel and UI.target then
      -- Remember chosen marker PER PROJECT (preselect next time)
      proj_set_last_pos(UI.target)
      -- Move only after confirmation
      apply_alignment(UI.target)
    end
    return
  end

  local ch = gfx.getchar()
  if ch < 0 or ch == 27 then
    UI.done = true
    UI.cancel = true
    return reaper.defer(loop)
  end

  if ch == 13 then
    UI.target = markers[UI.selected].pos
    UI.done = true
    return reaper.defer(loop)
  end

  if ch == 30064 then UI.selected = math.max(1, UI.selected-1) end
  if ch == 30065 then UI.selected = math.min(#markers, UI.selected+1) end

  if gfx.mouse_wheel ~= 0 then
    UI.scroll = UI.scroll + (gfx.mouse_wheel > 0 and -3 or 3)
    gfx.mouse_wheel = 0
  end

  local cap = gfx.mouse_cap
  if (cap&1)==1 and (UI.last_cap&1)==0 then
    local row = math.floor((gfx.mouse_y-UI.topH)/UI.rowH)+1
    local idx = row + UI.scroll
    if idx>=1 and idx<=#markers then
      UI.selected = idx
      local now = reaper.time_precise()*1000
      if now-UI.last_click < UI.dbl_ms then
        UI.target = markers[idx].pos
        UI.done = true
      end
      UI.last_click = now
    end
  end
  UI.last_cap = cap

  draw()
  gfx.update()
  reaper.defer(loop)
end

gfx.init("Choose Project Marker (click + Enter)", UI.W, UI.H, 0)
loop()