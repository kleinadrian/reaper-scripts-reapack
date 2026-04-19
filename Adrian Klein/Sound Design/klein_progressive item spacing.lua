-- @description Progressive Item Spacing
-- @version 5.7
-- @author Adrian Klein
-- @about
--   Interactive tool for spacing items with progressive curves.
--   Supports linear, exponential, and logarithmic spacing.

--[[
 * Description:
 *   Interactive progressive spacing tool with live preview.
 *   Repositions selected items so the gap between them grows progressively.
 *   Keeps the first item fixed and adjusts spacing based on selected curve.

 * Notes:
 *   - Requires two or more selected items
 *   - Supports Linear, Exponential, and Logarithmic curves
 *   - Direction: Left, Center, Right
 *   - Amount slider controls spacing intensity
 *   - Options for locked items and overlap handling
 *   - Enter to apply, Esc to cancel
]]

local EXT_SECTION = "AK_ProgressiveItemSpacingInteractive"

local CURVE_LINEAR      = "linear"
local CURVE_EXPONENTIAL = "exponential"
local CURVE_LOGARITHMIC = "logarithmic"

local DIR_LEFT   = "left"
local DIR_CENTER = "center"
local DIR_RIGHT  = "right"

local DEFAULT_STATE = {
  curve = CURVE_EXPONENTIAL,
  direction = DIR_LEFT,
  amount = 0.0,
  locked_mode = true,
  overlap_mode = false,
}

local function safe_destroy_context(ctx)
  if reaper.ImGui_DestroyContext then
    reaper.ImGui_DestroyContext(ctx)
  end
end

local function commit_undo_state()
  if reaper.Undo_OnStateChange2 then
    reaper.Undo_OnStateChange2(0, "Progressive space selected items", -1)
  else
    reaper.Undo_OnStateChange("Progressive space selected items")
  end
end

-- ============================================================
-- EXTSTATE
-- ============================================================

local function save_state(state)
  reaper.SetExtState(EXT_SECTION, "curve", state.curve, true)
  reaper.SetExtState(EXT_SECTION, "direction", state.direction, true)
  reaper.SetExtState(EXT_SECTION, "amount", tostring(state.amount), true)
  reaper.SetExtState(EXT_SECTION, "locked_mode", state.locked_mode and "true" or "false", true)
  reaper.SetExtState(EXT_SECTION, "overlap_mode", state.overlap_mode and "true" or "false", true)
end

local function load_state()
  local state = {}

  state.curve = reaper.GetExtState(EXT_SECTION, "curve")
  if state.curve == "" then state.curve = DEFAULT_STATE.curve end

  state.direction = reaper.GetExtState(EXT_SECTION, "direction")
  if state.direction == "" then state.direction = DEFAULT_STATE.direction end

  local amount = tonumber(reaper.GetExtState(EXT_SECTION, "amount"))
  state.amount = amount or DEFAULT_STATE.amount

  local locked = reaper.GetExtState(EXT_SECTION, "locked_mode")
  if locked == "" then
    state.locked_mode = DEFAULT_STATE.locked_mode
  else
    state.locked_mode = (locked == "true")
  end

  local overlap = reaper.GetExtState(EXT_SECTION, "overlap_mode")
  if overlap == "" then
    state.overlap_mode = DEFAULT_STATE.overlap_mode
  else
    state.overlap_mode = (overlap == "true")
  end

  if state.direction == DIR_CENTER then
    state.locked_mode = false
  end

  return state
end

local function reset_state_to_default(state)
  state.curve = DEFAULT_STATE.curve
  state.direction = DEFAULT_STATE.direction
  state.amount = DEFAULT_STATE.amount
  state.locked_mode = DEFAULT_STATE.locked_mode
  state.overlap_mode = DEFAULT_STATE.overlap_mode
end

-- ============================================================
-- HELPERS
-- ============================================================

local function is_item_locked(item)
  if not item then return true end

  if reaper.GetMediaItemInfo_Value(item, "C_LOCK") ~= 0 then
    return true
  end

  local track = reaper.GetMediaItemTrack(item)
  if track and reaper.GetMediaTrackInfo_Value(track, "C_LOCK") ~= 0 then
    return true
  end

  return false
end

local function collect_selected_items()
  local items = {}
  local count = reaper.CountSelectedMediaItems(0)

  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
      items[#items + 1] = {
        item = item,
        pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
        len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
        locked = is_item_locked(item),
      }
    end
  end

  table.sort(items, function(a, b)
    if a.pos == b.pos then
      return a.len < b.len
    end
    return a.pos < b.pos
  end)

  return items
end

local original_items = collect_selected_items()
if #original_items < 2 then return end

local function clone_items_from_original()
  local items = {}
  for i = 1, #original_items do
    items[i] = {
      item = original_items[i].item,
      pos = original_items[i].pos,
      len = original_items[i].len,
      locked = original_items[i].locked,
    }
  end
  return items
end

local function restore_original_positions()
  for i = 1, #original_items do
    reaper.SetMediaItemInfo_Value(original_items[i].item, "D_POSITION", original_items[i].pos)
  end
  reaper.UpdateArrange()
end

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

local function original_average_gap(items, first_idx, last_idx)
  local gap_count = last_idx - first_idx
  if gap_count <= 0 then return 0 end

  local total_gap = 0
  for i = first_idx + 1, last_idx do
    local prev = items[i - 1]
    local cur = items[i]
    total_gap = total_gap + (cur.pos - (prev.pos + prev.len))
  end

  return total_gap / gap_count
end

-- ============================================================
-- CURVES
-- ============================================================

local function make_weights(count, curve, amount, direction)
  local weights = {}
  if count <= 0 then return weights end

  local effective_amount

  if curve == CURVE_LINEAR then
    effective_amount = amount * 12.0
  elseif curve == CURVE_EXPONENTIAL then
    effective_amount = amount * 4.0
  else
    effective_amount = amount * 18.0
  end

  for i = 1, count do
    local t = (count == 1) and 0 or ((i - 1) / (count - 1))
    local w = 1.0

    if curve == CURVE_LINEAR then
      w = 1 + effective_amount * t
    elseif curve == CURVE_EXPONENTIAL then
      w = (1 + effective_amount) ^ (i - 1)
    elseif curve == CURVE_LOGARITHMIC then
      w = 1 + effective_amount * (math.log(1 + 9 * t) / math.log(10))
    end

    weights[i] = w
  end

  if direction == DIR_RIGHT then
    local reversed = {}
    for i = 1, count do
      reversed[i] = weights[count - i + 1]
    end
    weights = reversed
  end

  return weights
end

local function apply_overlap_to_gap(gap, avg_gap, amount, overlap_mode)
  if not overlap_mode then
    return gap
  end

  local overlap_push = avg_gap * (amount * 2.5)
  return gap - overlap_push
end

-- ============================================================
-- CHAIN REDISTRIBUTION
-- ============================================================

local function chain_right(items, first_idx, last_idx, curve, amount, weight_direction, shared_avg_gap, overlap_mode)
  local gap_count = last_idx - first_idx
  if gap_count <= 0 then return true end

  local avg_gap = shared_avg_gap or original_average_gap(items, first_idx, last_idx)
  if avg_gap < 0 then return false end

  local weights = make_weights(gap_count, curve, amount, weight_direction)
  local current_pos = items[first_idx].pos + items[first_idx].len

  for i = 1, gap_count do
    local item_idx = first_idx + i
    local gap = avg_gap * weights[i]
    gap = apply_overlap_to_gap(gap, avg_gap, amount, overlap_mode)

    local new_pos = current_pos + gap
    reaper.SetMediaItemInfo_Value(items[item_idx].item, "D_POSITION", new_pos)
    items[item_idx].pos = new_pos
    current_pos = new_pos + items[item_idx].len
  end

  return true
end

local function chain_left(items, first_idx, last_idx, curve, amount, weight_direction, shared_avg_gap, overlap_mode)
  local gap_count = last_idx - first_idx
  if gap_count <= 0 then return true end

  local avg_gap = shared_avg_gap or original_average_gap(items, first_idx, last_idx)
  if avg_gap < 0 then return false end

  local weights = make_weights(gap_count, curve, amount, weight_direction)
  local current_pos = items[last_idx].pos

  for i = 1, gap_count do
    local item_idx = last_idx - i
    local gap = avg_gap * weights[i]
    gap = apply_overlap_to_gap(gap, avg_gap, amount, overlap_mode)

    local new_pos = current_pos - gap - items[item_idx].len
    reaper.SetMediaItemInfo_Value(items[item_idx].item, "D_POSITION", new_pos)
    items[item_idx].pos = new_pos
    current_pos = new_pos
  end

  return true
end

local function redistribute_single_anchor(items, first_idx, last_idx, curve, amount, direction, overlap_mode)
  if last_idx <= first_idx then return true end

  if direction == DIR_LEFT then
    return chain_right(items, first_idx, last_idx, curve, amount, DIR_LEFT, nil, overlap_mode)
  end

  if direction == DIR_RIGHT then
    return chain_left(items, first_idx, last_idx, curve, amount, DIR_RIGHT, nil, overlap_mode)
  end

  -- DIR_CENTER: symmetric outward expansion from middle pivot
  local mid_idx = math.floor((first_idx + last_idx) / 2)
  local shared_avg_gap = original_average_gap(items, first_idx, last_idx)
  if shared_avg_gap < 0 then return false end

  local right_ok = true
  if last_idx > mid_idx then
    right_ok = chain_right(items, mid_idx, last_idx, curve, amount, DIR_LEFT, shared_avg_gap, overlap_mode)
  end

  local left_ok = true
  if mid_idx > first_idx then
    left_ok = chain_left(items, first_idx, mid_idx, curve, amount, DIR_LEFT, shared_avg_gap, overlap_mode)
  end

  return right_ok and left_ok
end

-- ============================================================
-- LOCKED MODE
-- ============================================================

local function redistribute_between_fixed_anchors(items, anchor_a, anchor_b, curve, amount, direction, overlap_mode)
  if anchor_b - anchor_a < 2 then
    return true
  end

  local first = items[anchor_a]
  local last = items[anchor_b]

  local first_end = first.pos + first.len
  local last_start = last.pos

  local movable_indices = {}
  local total_inner_lengths = 0

  for i = anchor_a + 1, anchor_b - 1 do
    if not items[i].locked then
      movable_indices[#movable_indices + 1] = i
      total_inner_lengths = total_inner_lengths + items[i].len
    end
  end

  if #movable_indices == 0 then
    return true
  end

  local total_gap_space = last_start - first_end - total_inner_lengths
  if total_gap_space < 0 then
    return false
  end

  local gap_count = #movable_indices + 1
  local weights = make_weights(gap_count, curve, amount, direction)

  local weight_sum = 0
  for i = 1, #weights do
    weight_sum = weight_sum + weights[i]
  end
  if weight_sum <= 0 then return false end

  local gaps = {}
  for i = 1, gap_count do
    gaps[i] = total_gap_space * (weights[i] / weight_sum)
  end

  if overlap_mode then
    local avg_gap = total_gap_space / gap_count
    local overlap_push = avg_gap * (amount * 2.5)

    for i = 1, gap_count do
      gaps[i] = gaps[i] - overlap_push
    end
  end

  local pos = first_end + gaps[1]

  for n = 1, #movable_indices do
    local idx = movable_indices[n]
    reaper.SetMediaItemInfo_Value(items[idx].item, "D_POSITION", pos)
    items[idx].pos = pos
    pos = pos + items[idx].len + gaps[n + 1]
  end

  return true
end

local function apply_preview(state)
  restore_original_positions()

  local items = clone_items_from_original()
  if #items < 2 then
    return false, "Select at least 2 items."
  end

  if not state.locked_mode then
    local ok = redistribute_single_anchor(items, 1, #items, state.curve, state.amount, state.direction, state.overlap_mode)
    reaper.UpdateArrange()
    if not ok then
      return false, "Not enough room to redistribute selected items."
    end
    return true, ""
  end

  if #items < 3 then
    reaper.UpdateArrange()
    return false, "Locked mode needs at least 3 selected items."
  end

  local anchors = {1}
  for i = 2, #items - 1 do
    if items[i].locked then
      anchors[#anchors + 1] = i
    end
  end
  anchors[#anchors + 1] = #items

  local did_anything = false

  for a = 1, #anchors - 1 do
    local first_idx = anchors[a]
    local last_idx = anchors[a + 1]

    if last_idx - first_idx >= 2 then
      local ok = redistribute_between_fixed_anchors(items, first_idx, last_idx, state.curve, state.amount, state.direction, state.overlap_mode)
      if not ok then
        reaper.UpdateArrange()
        return false, "One anchor segment has no room to fit the movable items."
      end
      did_anything = true
    end
  end

  reaper.UpdateArrange()

  if not did_anything then
    return false, "No unlocked items found between anchors."
  end

  return true, ""
end

-- ============================================================
-- UI
-- ============================================================

local function main()
  if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui is not installed.", "Progressive Item Spacing", 0)
    return
  end

  local ctx = reaper.ImGui_CreateContext("AK_ProgressiveItemSpacingInteractive")
  local state = load_state()
  local status_msg = ""
  local last_preview_signature = ""
  local WIN_W = 360
  local closing = false
  local cancel_on_close = false

  local COL2 = 120
  local COL3 = 240

  local function build_signature()
    return table.concat({
      state.curve,
      state.direction,
      string.format("%.6f", state.amount),
      state.locked_mode and "1" or "0",
      state.overlap_mode and "1" or "0"
    }, "|")
  end

  local function maybe_update_preview()
    local sig = build_signature()
    if sig ~= last_preview_signature then
      local ok, msg = apply_preview(state)
      status_msg = ok and "" or msg
      last_preview_signature = sig
      save_state(state)
    end
  end

  local function loop()
    if closing then
      if cancel_on_close then
        restore_original_positions()
      else
        commit_undo_state()
      end
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

    local visible, open = reaper.ImGui_Begin(ctx, "Progressive Item Spacing", true,
      reaper.ImGui_WindowFlags_NoCollapse()  |
      reaper.ImGui_WindowFlags_NoResize()    |
      reaper.ImGui_WindowFlags_NoScrollbar() |
      reaper.ImGui_WindowFlags_AlwaysAutoResize())

    if visible then
      reaper.ImGui_Spacing(ctx)

      local changed = false
      local avail_w = WIN_W - 18 * 2

      section_label(ctx, "Curve")
      reaper.ImGui_Spacing(ctx)

      if reaper.ImGui_RadioButton(ctx, "Linear##curve", state.curve == CURVE_LINEAR) then
        state.curve = CURVE_LINEAR
        changed = true
      end
      reaper.ImGui_SameLine(ctx, COL2)
      if reaper.ImGui_RadioButton(ctx, "Exponential##curve", state.curve == CURVE_EXPONENTIAL) then
        state.curve = CURVE_EXPONENTIAL
        changed = true
      end
      reaper.ImGui_SameLine(ctx, COL3)
      if reaper.ImGui_RadioButton(ctx, "Logarithmic##curve", state.curve == CURVE_LOGARITHMIC) then
        state.curve = CURVE_LOGARITHMIC
        changed = true
      end

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      section_label(ctx, "Direction")
      reaper.ImGui_Spacing(ctx)

      if reaper.ImGui_RadioButton(ctx, "Left##dir", state.direction == DIR_LEFT) then
        state.direction = DIR_LEFT
        changed = true
      end
      reaper.ImGui_SameLine(ctx, COL2)
      if reaper.ImGui_RadioButton(ctx, "Center##dir", state.direction == DIR_CENTER) then
        state.direction = DIR_CENTER
        state.locked_mode = false
        changed = true
      end
      reaper.ImGui_SameLine(ctx, COL3)
      if reaper.ImGui_RadioButton(ctx, "Right##dir", state.direction == DIR_RIGHT) then
        state.direction = DIR_RIGHT
        changed = true
      end

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      section_label(ctx, "Amount")
      reaper.ImGui_Spacing(ctx)

      reaper.ImGui_SetNextItemWidth(ctx, avail_w)
      local amount_changed, new_amount = reaper.ImGui_SliderDouble(ctx, "##amount", state.amount, 0.0, 1.0, "%.3f")
      if amount_changed then
        state.amount = new_amount
        changed = true
      end

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      section_label(ctx, "Locked")
      reaper.ImGui_Spacing(ctx)

      if state.direction == DIR_CENTER then
        reaper.ImGui_BeginDisabled(ctx)
      end

      local lock_changed, new_locked = reaper.ImGui_Checkbox(ctx, "Use locked items as fixed anchors##locked", state.locked_mode)
      if lock_changed then
        state.locked_mode = new_locked
        changed = true
      end

      if state.direction == DIR_CENTER then
        reaper.ImGui_EndDisabled(ctx)
      end

      reaper.ImGui_Spacing(ctx)

      section_label(ctx, "Overlap")
      reaper.ImGui_Spacing(ctx)

      local overlap_changed, new_overlap = reaper.ImGui_Checkbox(ctx, "Allow overlaps between items##overlap", state.overlap_mode)
      if overlap_changed then
        state.overlap_mode = new_overlap
        changed = true
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
        restore_original_positions()
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