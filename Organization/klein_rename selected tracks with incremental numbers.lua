-- @description Rename Selected Tracks with Incremental Numbers
-- @version 2.2
-- @author Adrian Klein
-- @about
--   Renames selected tracks sequentially using a user-defined base name.
--   Skips numbering when only one track is selected.

--[[
 * Description:
 *   Renames selected tracks sequentially using a user-defined base name.
 *   Input field is ready to type immediately.

 * Notes:
 *   - If only one track is selected, no number is appended.
 *   - Numbering is applied only when two or more tracks are selected.
 *   - Press Enter or click Rename when done.
]]

-- ============================================================
-- RENAME ACTION
-- ============================================================

local function RenameSelectedTracks(base_name)
  local sel_count = reaper.CountSelectedTracks(0)
  if sel_count == 0 then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  for i = 0, sel_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", sel_count > 1 and base_name .. " " .. (i + 1) or base_name, true)
  end

  reaper.TrackList_AdjustWindows(false)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Rename selected tracks with incremental numbers", -1)
end

-- ============================================================
-- MAIN UI
-- ============================================================

local function Main()
  if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui is not installed.", "Track Renamer", 0)
    return
  end

  local ctx       = reaper.ImGui_CreateContext("AK_TrackRenamerIncremental")
  local base_name = ""
  local WIN_W     = 300
  local focus_set = false

  local function loop()
    -- ---- Style (identical to the AK script family) ----
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

    local visible, open = reaper.ImGui_Begin(ctx, "Rename Tracks — Incremental", true,
      reaper.ImGui_WindowFlags_NoCollapse()     |
      reaper.ImGui_WindowFlags_NoResize()       |
      reaper.ImGui_WindowFlags_NoScrollbar()    |
      reaper.ImGui_WindowFlags_AlwaysAutoResize())

    if visible then
      reaper.ImGui_Spacing(ctx)

      -- Grey section label
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x888888FF)
      reaper.ImGui_Text(ctx, "Base Name")
      reaper.ImGui_PopStyleColor(ctx)

      reaper.ImGui_Spacing(ctx)

      -- Full-width text input, auto-focused on first frame
      local avail_w = WIN_W - 18 * 2
      reaper.ImGui_SetNextItemWidth(ctx, avail_w)
      if not focus_set then
        reaper.ImGui_SetKeyboardFocusHere(ctx)
        focus_set = true
      end
      local enter_pressed, new_val = reaper.ImGui_InputText(ctx, "##basename", base_name,
        reaper.ImGui_InputTextFlags_EnterReturnsTrue())
      -- Always update base_name so preview stays live while typing
      if new_val ~= base_name then base_name = new_val end
      if enter_pressed then
        local t = base_name:match("^%s*(.-)%s*$")
        if t ~= "" then
          RenameSelectedTracks(t)
          open = false
        end
      end

      local sel_count = reaper.CountSelectedTracks(0)
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x555555FF)
      local preview
      if base_name ~= "" then
        if sel_count > 1 then
          preview = base_name .. " 1, " .. base_name .. " 2, ..."
        else
          preview = base_name
        end
      else
        preview = "e.g.  guitar 1, guitar 2, ..."
      end
      reaper.ImGui_Text(ctx, preview)
      reaper.ImGui_PopStyleColor(ctx)

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      -- Rename button, right-aligned, greyed when input is empty
      local trimmed   = base_name:match("^%s*(.-)%s*$")
      local btn_w     = 80
      reaper.ImGui_SetCursorPosX(ctx, 18 + avail_w - btn_w)
      if trimmed == "" then reaper.ImGui_BeginDisabled(ctx) end
      local do_rename = reaper.ImGui_Button(ctx, "Rename##rename", btn_w, 0)
      if trimmed == "" then reaper.ImGui_EndDisabled(ctx) end

      if do_rename then
        RenameSelectedTracks(trimmed)
        open = false
      end

      reaper.ImGui_Spacing(ctx)
    end

    reaper.ImGui_End(ctx)

    reaper.ImGui_PopStyleVar(ctx, 5)
    reaper.ImGui_PopStyleColor(ctx, 11)

    if open then
      reaper.defer(loop)
    end
  end

  reaper.defer(loop)
end

Main()