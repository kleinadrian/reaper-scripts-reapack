-- @description Rename Selected Tracks by Category
-- @version 2.4
-- @author Adrian Klein
-- @about
--   Renames selected tracks using a category name.
--   Supports optional sequential numbering and persistent categories.

--[[
 * Description:
 *   Renames selected tracks using a category name.
 *   Supports optional sequential numbering.
 *   Categories are editable from the UI and persist across sessions.

 * Notes:
 *   Click a category button to rename. Window closes automatically if Autoclose is checked.
]]

-- ============================================================
-- DEFAULTS
-- ============================================================

local EXT_SECTION = "AK_TrackRenamer"

local DEFAULT_CATEGORIES = {"sfx", "foley", "dialog", "voice", "music"}

-- ============================================================
-- PERSISTENCE
-- ============================================================

local function SaveCategories(cats)
  reaper.SetExtState(EXT_SECTION, "categories", table.concat(cats, "|"), true)
end

local function LoadCategories()
  local raw = reaper.GetExtState(EXT_SECTION, "categories")
  if not raw or raw == "" then return {table.unpack(DEFAULT_CATEGORIES)} end
  local cats = {}
  for cat in raw:gmatch("[^|]+") do
    cats[#cats + 1] = cat
  end
  if #cats == 0 then return {table.unpack(DEFAULT_CATEGORIES)} end
  return cats
end

local function SaveNumbering(val)
  reaper.SetExtState(EXT_SECTION, "numbering", val and "true" or "false", true)
end

local function LoadNumbering()
  local v = reaper.GetExtState(EXT_SECTION, "numbering")
  if v == "" then return true end  -- default on
  return v == "true"
end

local function SaveAutoclose(val)
  reaper.SetExtState(EXT_SECTION, "autoclose", val and "true" or "false", true)
end

local function LoadAutoclose()
  local v = reaper.GetExtState(EXT_SECTION, "autoclose")
  if v == "" then return false end  -- default off
  return v == "true"
end



local function RenameSelectedTracks(base_name, use_numbering)
  local sel_count = reaper.CountSelectedTracks(0)
  if sel_count == 0 then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  for i = 0, sel_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local name  = base_name
    if use_numbering and sel_count > 1 then
      name = base_name .. " " .. (i + 1)
    end
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Rename selected tracks: " .. base_name, -1)
end

-- ============================================================
-- MAIN UI
-- ============================================================

local function Main()
  if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui is not installed.", "Track Renamer", 0)
    return
  end

  local ctx        = reaper.ImGui_CreateContext("AK_TrackRenamer")
  local categories = LoadCategories()
  local numbering  = LoadNumbering()
  local autoclose  = LoadAutoclose()
  local new_cat    = ""         -- text input buffer for new category
  local WIN_W      = 300
  local closing    = false

  local function loop()
    -- ---- Keyboard passthrough to Reaper ----
    -- Modifier values: 4096 = Cmd (Mac), 1 = Ctrl (Windows)
    local mods     = reaper.ImGui_GetKeyMods and reaper.ImGui_GetKeyMods(ctx) or 0
    local cmd_ctrl = (mods == 4096 or mods == 1)

    if mods == 0 and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
      reaper.Main_OnCommand(40044, 0)  -- transport: play/stop
    end
    if cmd_ctrl and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z()) then
      reaper.Main_OnCommand(40029, 0)  -- edit: undo
    end
    if cmd_ctrl and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_S()) then
      reaper.Main_OnCommand(40026, 0)  -- file: save project
    end
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
      closing = true
    end

    -- ---- Style (identical to BIP settings) ----
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(),       0x1E1E1EFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),        0x2A2A2AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x333333FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(),      0x4A9EFFFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         0x2A2A2AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  0x3A3A3AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(),         0x2A2A2AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(),  0x4A9EFF44)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),           0xE8E8E8FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),         0x383838FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(),      0x383838FF)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 6)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(),  4)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(),  18, 16)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(),   6, 4)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(),    8, 10)

    reaper.ImGui_SetNextWindowSize(ctx, WIN_W, 0, reaper.ImGui_Cond_Always())

    local visible, open = reaper.ImGui_Begin(ctx, "Track Renamer", true,
      reaper.ImGui_WindowFlags_NoCollapse()    |
      reaper.ImGui_WindowFlags_NoResize()      |
      reaper.ImGui_WindowFlags_NoScrollbar()   |
      reaper.ImGui_WindowFlags_AlwaysAutoResize())

    if visible then
      reaper.ImGui_Spacing(ctx)

      local function section_label(text)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x888888FF)
        reaper.ImGui_Text(ctx, text)
        reaper.ImGui_PopStyleColor(ctx)
      end

      -- ---- Numbering ----
      section_label("Numbering")
      reaper.ImGui_SameLine(ctx, 110)
      local ch_num, new_num = reaper.ImGui_Checkbox(ctx, "Sequential##numbering", numbering)
      if ch_num then
        numbering = new_num
        SaveNumbering(numbering)
      end

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      -- ---- Category buttons ----
      section_label("Category")
      reaper.ImGui_Spacing(ctx)

      local to_delete = nil
      for i, cat in ipairs(categories) do
        -- Category button — full width minus space for ✕
        local avail_w = WIN_W - 18 * 2  -- account for window padding both sides
        local del_w   = 24
        local btn_w   = avail_w - del_w - 8  -- 8 = item spacing

        if reaper.ImGui_Button(ctx, cat .. "##cat" .. i, btn_w, 0) then
          RenameSelectedTracks(cat, numbering)
          if autoclose then open = false end
        end

        reaper.ImGui_SameLine(ctx)

        -- ✕ delete button
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        0x3A2222FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  0x5A2222FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),           0xFF6666FF)
        if reaper.ImGui_Button(ctx, "x##del" .. i, del_w, 0) then
          to_delete = i
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
      end

      -- Apply deletion after loop
      if to_delete then
        table.remove(categories, to_delete)
        SaveCategories(categories)
      end

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      -- ---- Add new category ----
      section_label("Add Category")
      reaper.ImGui_Spacing(ctx)

      local avail_w2  = WIN_W - 18 * 2
      reaper.ImGui_SetNextItemWidth(ctx, avail_w2)
      local changed, new_val = reaper.ImGui_InputText(ctx, "##newcat", new_cat)
      if changed then new_cat = new_val end

      -- Add button + Autoclose checkbox on same row
      local trimmed   = new_cat:match("^%s*(.-)%s*$")
      local add_btn_w = 52

      -- Autoclose checkbox (left side)
      local ch_ac, new_ac = reaper.ImGui_Checkbox(ctx, "Autoclose##autoclose", autoclose)
      if ch_ac then
        autoclose = new_ac
        SaveAutoclose(autoclose)
      end

      -- Add button (right side, same row)
      reaper.ImGui_SameLine(ctx, 18 + avail_w2 - add_btn_w)
      if trimmed == "" then reaper.ImGui_BeginDisabled(ctx) end
      if reaper.ImGui_Button(ctx, "Add##addcat", add_btn_w, 0) then
        if trimmed ~= "" then
          categories[#categories + 1] = trimmed
          SaveCategories(categories)
          new_cat = ""
        end
      end
      if trimmed == "" then reaper.ImGui_EndDisabled(ctx) end

      reaper.ImGui_Spacing(ctx)
    end

    reaper.ImGui_End(ctx)

    reaper.ImGui_PopStyleVar(ctx, 5)
    reaper.ImGui_PopStyleColor(ctx, 11)

    if open and not closing then
      reaper.defer(loop)
    end
  end

  reaper.defer(loop)
end

Main()