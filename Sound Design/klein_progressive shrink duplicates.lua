-- @description Progressive Shrink Duplicates
-- @version 2.6
-- @author Adrian Klein
-- @about
--   Creates progressively shorter duplicates of selected items.
--   Supports directional control, spacing, and live preview.

--[[
 * Description:
 *   Creates progressively shorter copies of selected items by cropping from the right.
 *   Duplicates are placed sequentially with optional spacing and live preview.

 * Notes:
 *   - Requires one or more selected items
 *   - Direction:
 *     Left  = large to small
 *     Right = small to large
 *
 *   - Volume decay follows shrink amount
 *   - Single fade control applies to both fade in and fade out
 *   - Space forwards Play/Stop to REAPER
 *   - Enter to apply, Esc to cancel
]]

local EXT_SECTION = "AK_ProgressiveCropRepeater"

local DIR_LEFT  = "left"
local DIR_RIGHT = "right"

local DEFAULT_STATE = {
  copies = 3,
  spacing_ms = 20.0,
  shrink_percent = 82.0,
  direction = DIR_LEFT,
  volume_decay = false,
  fades = false,
  fade_percent = 1.0,
}

local MIN_LEN_SEC = 0.005
local MIN_FADE_MARGIN_SEC = 0.001

local function ms_to_sec(ms)
  return ms / 1000.0
end

local function safe_destroy_context(ctx)
  if reaper.ImGui_DestroyContext then
    reaper.ImGui_DestroyContext(ctx)
  end
end

local function commit_undo_state()
  if reaper.Undo_OnStateChange2 then
    reaper.Undo_OnStateChange2(0, "Progressive crop repeater", -1)
  else
    reaper.Undo_OnStateChange("Progressive crop repeater")
  end
end

local function is_valid_item(item)
  if reaper.ValidatePtr2 then
    return item ~= nil and reaper.ValidatePtr2(0, item, "MediaItem*")
  end
  return item ~= nil
end

-- ============================================================
-- EXTSTATE
-- ============================================================

local function save_state(state)
  reaper.SetExtState(EXT_SECTION, "copies", tostring(state.copies), true)
  reaper.SetExtState(EXT_SECTION, "spacing_ms", tostring(state.spacing_ms), true)
  reaper.SetExtState(EXT_SECTION, "shrink_percent", tostring(state.shrink_percent), true)
  reaper.SetExtState(EXT_SECTION, "direction", state.direction, true)
  reaper.SetExtState(EXT_SECTION, "volume_decay", state.volume_decay and "true" or "false", true)
  reaper.SetExtState(EXT_SECTION, "fades", state.fades and "true" or "false", true)
  reaper.SetExtState(EXT_SECTION, "fade_percent", tostring(state.fade_percent), true)
end

local function load_state()
  local state = {}

  state.copies = tonumber(reaper.GetExtState(EXT_SECTION, "copies")) or DEFAULT_STATE.copies
  state.spacing_ms = tonumber(reaper.GetExtState(EXT_SECTION, "spacing_ms")) or DEFAULT_STATE.spacing_ms
  state.shrink_percent = tonumber(reaper.GetExtState(EXT_SECTION, "shrink_percent")) or DEFAULT_STATE.shrink_percent

  state.direction = reaper.GetExtState(EXT_SECTION, "direction")
  if state.direction == "" then
    state.direction = DEFAULT_STATE.direction
  end

  state.volume_decay = (reaper.GetExtState(EXT_SECTION, "volume_decay") == "true")
  state.fades = (reaper.GetExtState(EXT_SECTION, "fades") == "true")
  state.fade_percent = tonumber(reaper.GetExtState(EXT_SECTION, "fade_percent")) or DEFAULT_STATE.fade_percent

  return state
end

local function reset_state_to_default(state)
  state.copies = DEFAULT_STATE.copies
  state.spacing_ms = DEFAULT_STATE.spacing_ms
  state.shrink_percent = DEFAULT_STATE.shrink_percent
  state.direction = DEFAULT_STATE.direction
  state.volume_decay = DEFAULT_STATE.volume_decay
  state.fades = DEFAULT_STATE.fades
  state.fade_percent = DEFAULT_STATE.fade_percent
end

-- ============================================================
-- SOURCE ITEM
-- ============================================================

local function get_selected_item()
  if reaper.CountSelectedMediaItems(0) ~= 1 then
    return nil
  end
  return reaper.GetSelectedMediaItem(0, 0)
end

local source_item = get_selected_item()
if not source_item then return end

local source_track = reaper.GetMediaItemTrack(source_item)
local source_pos = reaper.GetMediaItemInfo_Value(source_item, "D_POSITION")
local source_len = reaper.GetMediaItemInfo_Value(source_item, "D_LENGTH")

local ok_chunk, source_chunk = reaper.GetItemStateChunk(source_item, "", false)
if not ok_chunk or not source_chunk then return end

-- ============================================================
-- PREVIEW MANAGEMENT
-- ============================================================

local preview_items = {}

local function restore_source_item()
  if is_valid_item(source_item) then
    reaper.SetItemStateChunk(source_item, source_chunk, false)
  end
end

local function clear_preview_items()
  for i = #preview_items, 1, -1 do
    local item = preview_items[i]
    if item and is_valid_item(item) then
      local tr = reaper.GetMediaItemTrack(item)
      if tr then
        reaper.DeleteTrackMediaItem(tr, item)
      end
    end
  end
  preview_items = {}
end

local function clear_all_preview()
  clear_preview_items()
  restore_source_item()
  reaper.UpdateArrange()
end

local function create_item_from_source_chunk(track, chunk)
  local new_item = reaper.AddMediaItemToTrack(track)
  if not new_item then return nil end
  reaper.SetItemStateChunk(new_item, chunk, false)
  return new_item
end

local function build_lengths(state)
  local copies = math.max(0, math.floor(state.copies or 0))
  local shrink_percent = math.max(0.1, state.shrink_percent or 100)
  local ratio = shrink_percent / 100.0

  local total_items = copies + 1
  local lengths = {}

  for i = 0, total_items - 1 do
    local new_len = source_len * (ratio ^ i)
    if new_len < MIN_LEN_SEC then
      new_len = MIN_LEN_SEC
    end
    lengths[#lengths + 1] = new_len
  end

  if state.direction == DIR_RIGHT then
    local reversed = {}
    for i = 1, #lengths do
      reversed[i] = lengths[#lengths - i + 1]
    end
    lengths = reversed
  end

  return lengths
end

local function apply_item_extras(item, item_len, length_ratio, state)
  if state.volume_decay then
    reaper.SetMediaItemInfo_Value(item, "D_VOL", length_ratio)
  else
    reaper.SetMediaItemInfo_Value(item, "D_VOL", 1.0)
  end

  if state.fades then
    local fade_len = item_len * (math.max(0, state.fade_percent or 0) / 100.0)
    local max_allowed = math.max(0, (item_len - MIN_FADE_MARGIN_SEC) * 0.5)

    if fade_len > max_allowed then
      fade_len = max_allowed
    end

    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", fade_len)
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fade_len)
  else
    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
  end
end

local function build_preview(state)
  if not is_valid_item(source_item) then
    return false, "Source item no longer exists."
  end

  clear_all_preview()

  local spacing_sec = ms_to_sec(math.max(0, state.spacing_ms or 0))
  local lengths = build_lengths(state)
  if #lengths == 0 then return true, "" end

  reaper.SetMediaItemInfo_Value(source_item, "D_POSITION", source_pos)
  reaper.SetMediaItemInfo_Value(source_item, "D_LENGTH", lengths[1])
  apply_item_extras(source_item, lengths[1], lengths[1] / source_len, state)
  reaper.SetMediaItemSelected(source_item, true)

  local prev_end = source_pos + lengths[1]

  for i = 2, #lengths do
    local new_item = create_item_from_source_chunk(source_track, source_chunk)
    if not new_item then break end

    local new_len = lengths[i]
    local new_pos = prev_end + spacing_sec

    reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", new_pos)
    reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", new_len)
    apply_item_extras(new_item, new_len, new_len / source_len, state)
    reaper.SetMediaItemSelected(new_item, false)

    preview_items[#preview_items + 1] = new_item
    prev_end = new_pos + new_len
  end

  reaper.UpdateArrange()
  return true, ""
end

-- ============================================================
-- UI HELPERS
-- ============================================================

local function section_label(ctx, text)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x888888FF)
  reaper.ImGui_Text(ctx, text)
  reaper.ImGui_PopStyleColor(ctx)
end

local function text_input_active(ctx)
  if reaper.ImGui_IsAnyItemActive then
    return reaper.ImGui_IsAnyItemActive(ctx)
  end
  return false
end

-- ============================================================
-- MAIN UI
-- ============================================================

local function main()
  if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui is not installed.", "Progressive Crop Repeater", 0)
    return
  end

  local ctx = reaper.ImGui_CreateContext("AK_ProgressiveCropRepeater")
  local state = load_state()
  local WIN_W = 360
  local closing = false
  local cancel_on_close = false
  local last_signature = ""
  local status_msg = ""
  local COL2 = 120
  local EXTRA_COL2 = 205

  local function build_signature()
    return table.concat({
      tostring(math.floor(state.copies or 0)),
      string.format("%.6f", state.spacing_ms or 0),
      string.format("%.6f", state.shrink_percent or 0),
      state.direction or DIR_LEFT,
      state.volume_decay and "1" or "0",
      state.fades and "1" or "0",
      string.format("%.6f", state.fade_percent or 0)
    }, "|")
  end

  local function maybe_update_preview()
    local sig = build_signature()
    if sig ~= last_signature then
      local ok, msg = build_preview(state)
      status_msg = ok and "" or (msg or "Preview failed.")
      if ok then
        save_state(state)
        last_signature = sig
      end
    end
  end

  local function loop()
    if closing then
      if cancel_on_close then
        clear_all_preview()
      else
        commit_undo_state()
      end
      safe_destroy_context(ctx)
      return
    end

    if not is_valid_item(source_item) then
      closing = true
      cancel_on_close = false
      safe_destroy_context(ctx)
      return
    end

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

    local visible, open = reaper.ImGui_Begin(ctx, "Progressive Crop Repeater", true,
      reaper.ImGui_WindowFlags_NoCollapse()  |
      reaper.ImGui_WindowFlags_NoResize()    |
      reaper.ImGui_WindowFlags_NoScrollbar() |
      reaper.ImGui_WindowFlags_AlwaysAutoResize())

    if visible then
      reaper.ImGui_Spacing(ctx)

      local changed = false
      local avail_w = WIN_W - 18 * 2

      section_label(ctx, "Direction")
      reaper.ImGui_Spacing(ctx)

      if reaper.ImGui_RadioButton(ctx, "Left##dir", state.direction == DIR_LEFT) then
        state.direction = DIR_LEFT
        changed = true
      end
      reaper.ImGui_SameLine(ctx, COL2)
      if reaper.ImGui_RadioButton(ctx, "Right##dir", state.direction == DIR_RIGHT) then
        state.direction = DIR_RIGHT
        changed = true
      end

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      section_label(ctx, "Copies")
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, avail_w)
      local copies_changed, new_copies = reaper.ImGui_InputInt(ctx, "##copies", math.floor(state.copies))
      if copies_changed then
        if new_copies < 0 then new_copies = 0 end
        state.copies = new_copies
        changed = true
      end

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      section_label(ctx, "Spacing (ms)")
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, avail_w)
      local spacing_changed, new_spacing = reaper.ImGui_InputDouble(ctx, "##spacing", state.spacing_ms)
      if spacing_changed then
        if new_spacing < 0 then new_spacing = 0 end
        state.spacing_ms = new_spacing
        changed = true
      end

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      section_label(ctx, "Shrink (%)")
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, avail_w)
      local shrink_changed, new_shrink = reaper.ImGui_SliderDouble(ctx, "##shrink", state.shrink_percent, 10.0, 100.0, "%.3f")
      if shrink_changed then
        state.shrink_percent = new_shrink
        changed = true
      end

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      section_label(ctx, "Extras")
      reaper.ImGui_Spacing(ctx)

      local vol_changed, new_vol = reaper.ImGui_Checkbox(ctx, "Volume Decay##voldecay", state.volume_decay)
      if vol_changed then
        state.volume_decay = new_vol
        changed = true
      end

      reaper.ImGui_SameLine(ctx, EXTRA_COL2)

      local fades_changed, new_fades = reaper.ImGui_Checkbox(ctx, "Fades##fades", state.fades)
      if fades_changed then
        state.fades = new_fades
        changed = true
      end

      if state.fades then
        reaper.ImGui_Spacing(ctx)
        section_label(ctx, "Fade (%)")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, avail_w)
        local fade_changed, new_fade = reaper.ImGui_SliderDouble(ctx, "##fade", state.fade_percent, 0.0, 100.0, "%.1f")
        if fade_changed then
          state.fade_percent = new_fade
          changed = true
        end
      end

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x5A5A5AFF)
      reaper.ImGui_TextWrapped(ctx, "makesound.design")
      reaper.ImGui_PopStyleColor(ctx)

      reaper.ImGui_Spacing(ctx)

      local default_w = 60
      reaper.ImGui_SetCursorPosX(ctx, 18 + avail_w - default_w)
      if reaper.ImGui_Button(ctx, "Default", default_w, 0) then
        reset_state_to_default(state)
        changed = true
      end

      if changed then
        maybe_update_preview()
      end

      if status_msg ~= "" then
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xD08A8AFF)
        reaper.ImGui_TextWrapped(ctx, status_msg)
        reaper.ImGui_PopStyleColor(ctx)
      end

      reaper.ImGui_Spacing(ctx)

      if not text_input_active(ctx) and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
        reaper.Main_OnCommand(40044, 0) -- Transport: Play/Stop
      end

      if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
        closing = true
        cancel_on_close = false
      end

      if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
        closing = true
        cancel_on_close = true
      end
    end

    reaper.ImGui_End(ctx)
    reaper.ImGui_PopStyleVar(ctx, 5)
    reaper.ImGui_PopStyleColor(ctx, 11)

    if not open then
      closing = true
      cancel_on_close = true
    end

    if not closing then
      reaper.defer(loop)
    else
      if cancel_on_close then
        clear_all_preview()
      else
        commit_undo_state()
      end
      safe_destroy_context(ctx)
    end
  end

  maybe_update_preview()
  reaper.defer(loop)
end

main()