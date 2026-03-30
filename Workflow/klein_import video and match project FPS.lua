-- @description Import Video and Match Project FPS
-- @version 2.5
-- @author Adrian Klein
-- @about
--   Imports video files with automatic frame rate detection and project FPS matching.
--   Places videos using markers or sequentially and manages video tracks automatically.

--[[
 * Description:
 *   Imports multiple video files with automatic frame rate detection and smart placement.
 *   Ensures consistent FPS, manages video tracks, and preserves project and UI state.

 * Notes:
 *   Video Handling:
 *   - Multi-select import via JS_Dialog_BrowseForOpenFiles.
 *   - Detects frame rate using ffprobe (no hardcoded paths).
 *   - Aborts or prompts if selected videos have mismatched frame rates.
 *   - Skips files already present in the project.

 *   Placement:
 *   - Uses "=START" marker, then numbered video markers in order.
 *   - Supports naming: "video", "video 3", "video3", "video 03".
 *   - Trims previous video if next marker overlaps.
 *   - Falls back to end-to-end chaining when markers run out.

 *   Track Management:
 *   - Uses selected video track if available (clears existing items).
 *   - Creates "video" track at top if none exist.
 *   - Reuses empty or non-overlapping video tracks when possible.
 *   - Creates additional tracks ("video 2", "video 3", etc.) as needed.
 *   - Tracks are TCP-only, hidden from MCP, pinned, colored, and utility-layout assigned.

 *   Behavior:
 *   - Sets project FPS using SWS config vars (projfrbase / projfrdrop).
 *   - Disables looping on imported items.
 *   - Locks item positions after processing.
 *   - Preserves video window state and opens it on first import.
 *   - Maintains full UI state (cursor, scroll, zoom, selection).
 *   - Deselects video tracks after import.
]]

-- ============================================================
-- FFPROBE
-- ============================================================

local function GetFFProbePath()
  local candidates = {
    "ffprobe",
    "/opt/homebrew/bin/ffprobe",
    "/usr/local/bin/ffprobe",
    "ffprobe.exe",
    "C:\\ffmpeg\\bin\\ffprobe.exe",
  }
  for _, path in ipairs(candidates) do
    local ret = reaper.ExecProcess(path .. " -version", 5000)
    if ret and ret:find("ffprobe") then return path end
  end
  return nil
end

local function ParseFPS(rational_str)
  if not rational_str or rational_str == "" or rational_str == "0/0" then return nil end
  local num, den = rational_str:match("(%d+)/(%d+)")
  if num and den then
    num, den = tonumber(num), tonumber(den)
    if den == 0 then return nil end
    local fps = num / den
    local known = {
      {23.976, 24000 / 1001},
      {24,     24},
      {25,     25},
      {29.97,  30000 / 1001},
      {30,     30},
      {50,     50},
      {59.94,  60000 / 1001},
      {60,     60},
    }
    for _, k in ipairs(known) do
      if math.abs(fps - k[2]) < 0.01 then return k[1] end
    end
    return fps
  end
  return tonumber(rational_str)
end

local function DetectFPS(ffprobe_path, file_path)
  if not ffprobe_path then return nil end
  local cmd = string.format(
    '%s -v error -select_streams v:0 -show_entries stream=r_frame_rate,avg_frame_rate -of default=noprint_wrappers=1 "%s"',
    ffprobe_path, file_path
  )
  local output = reaper.ExecProcess(cmd, 10000)
  if not output then return nil end
  local r_fps, avg_fps
  local r_str   = output:match("r_frame_rate=([%d/]+)")
  local avg_str = output:match("avg_frame_rate=([%d/]+)")
  if r_str   then r_fps   = ParseFPS(r_str)   end
  if avg_str then avg_fps = ParseFPS(avg_str)  end
  return r_fps or avg_fps
end

local function GetVideoResolution(ffprobe_path, file_path)
  if not ffprobe_path then return nil, nil end
  local cmd = string.format(
    '%s -v error -select_streams v:0 -show_entries stream=width,height -of default=noprint_wrappers=1 "%s"',
    ffprobe_path, file_path
  )
  local output = reaper.ExecProcess(cmd, 10000)
  if not output then return nil, nil end
  local w = tonumber(output:match("width=(%d+)"))
  local h = tonumber(output:match("height=(%d+)"))
  return w, h
end

-- ============================================================
-- FILE DIALOG (multi-select)
-- ============================================================

local VIDEO_EXTENSIONS = {
  mp4=true, mov=true, avi=true, mkv=true,
  mxf=true, wmv=true, webm=true, mpg=true, mpeg=true, m4v=true
}

local function IsVideoFile(filename)
  if not filename or filename == "" then return false end
  local ext = filename:match("%.([^%.]+)$")
  return ext and VIDEO_EXTENSIONS[ext:lower()] or false
end

local function SelectVideoFiles()
  local ext_list = "Video files\0*.mp4;*.mov;*.avi;*.mkv;*.mxf;*.wmv;*.webm;*.mpg;*.mpeg;*.m4v\0\0"
  local retval, file_names = reaper.JS_Dialog_BrowseForOpenFiles(
    "Select Video File(s)", "", "", ext_list, true
  )
  if retval ~= 1 or not file_names or file_names == "" then return nil end

  local parts = {}
  local s = file_names
  while true do
    local nul = s:find("\0")
    if not nul then
      if s ~= "" then parts[#parts + 1] = s end
      break
    end
    local part = s:sub(1, nul - 1)
    if part ~= "" then parts[#parts + 1] = part end
    s = s:sub(nul + 1)
  end

  if #parts == 0 then return nil end

  local files = {}
  local first = parts[1]
  local is_folder = not IsVideoFile(first)

  if is_folder then
    local folder = first:gsub("[/\\]+$", "")
    local sep = package.config:sub(1, 1)
    for i = 2, #parts do
      files[#files + 1] = folder .. sep .. parts[i]
    end
  else
    for _, p in ipairs(parts) do
      files[#files + 1] = p
    end
  end

  table.sort(files, function(a, b) return a:lower() < b:lower() end)

  return files
end

-- ============================================================
-- FPS HELPERS
-- ============================================================

local function FPSToString(fps)
  if not fps then return "unknown" end
  local labels = {
    [23.976] = "23.976", [24] = "24",  [25] = "25",
    [29.97]  = "29.97",  [30] = "30",  [50] = "50",
    [59.94]  = "59.94",  [60] = "60",
  }
  return labels[fps] or string.format("%.3f", fps)
end

local function GetProjectFPS()
  local fps, _ = reaper.TimeMap_curFrameRate(0)
  return fps
end

local FPS_CONFIG = {
  [23.976] = {base = 24, drop = 2},
  [24]     = {base = 24, drop = 0},
  [25]     = {base = 25, drop = 0},
  [29.97]  = {base = 30, drop = 2},
  [30]     = {base = 30, drop = 0},
  [50]     = {base = 50, drop = 0},
  [59.94]  = {base = 60, drop = 2},
  [60]     = {base = 60, drop = 0},
}

local function SetProjectFPS(fps)
  local cfg = FPS_CONFIG[fps]
  if not cfg then
    local best, best_diff = 30, math.huge
    for k, _ in pairs(FPS_CONFIG) do
      local diff = math.abs(k - fps)
      if diff < best_diff then best, best_diff = k, diff end
    end
    cfg = FPS_CONFIG[best]
  end
  local proj = reaper.EnumProjects(-1)
  reaper.SNM_SetIntConfigVarEx(proj, "projfrbase", cfg.base)
  reaper.SNM_SetIntConfigVarEx(proj, "projfrdrop", cfg.drop)
end

-- ============================================================
-- PROJECT VIDEO CHECK
-- ============================================================

local function ProjectHasVideo()
  for ti = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, ti)
    for ii = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, ii)
      local take = reaper.GetActiveTake(item)
      if take then
        local src      = reaper.GetMediaItemTake_Source(take)
        local filename = src and reaper.GetMediaSourceFileName(src, "") or ""
        if IsVideoFile(filename) then return true end
      end
    end
  end
  return false
end

local function FileAlreadyInProject(file_path)
  for ti = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, ti)
    for ii = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, ii)
      local take = reaper.GetActiveTake(item)
      if take then
        local src      = reaper.GetMediaItemTake_Source(take)
        local filename = src and reaper.GetMediaSourceFileName(src, "") or ""
        if filename == file_path then return true end
      end
    end
  end
  return false
end

-- ============================================================
-- MARKER HELPERS
-- ============================================================

local function GetMarkerPos(name)
  for i = 0, reaper.CountProjectMarkers(0) - 1 do
    local _, is_rgn, pos, _, mname, _ = reaper.EnumProjectMarkers(i)
    if not is_rgn and mname == name then return pos end
  end
  return nil
end

local function IsPositionTakenByVideo(pos)
  local threshold = 0.01
  for ti = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, ti)
    for ii = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, ii)
      local take = reaper.GetActiveTake(item)
      if take then
        local src      = reaper.GetMediaItemTake_Source(take)
        local filename = src and reaper.GetMediaSourceFileName(src, "") or ""
        if IsVideoFile(filename) then
          local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          if math.abs(item_pos - pos) < threshold then return true end
        end
      end
    end
  end
  return false
end

-- Parse a marker name and return its video slot number, or nil if not a video marker
-- Recognises: "video" (slot 0), "video3", "video 3", "video 03" (slot 3), etc.
local function ParseVideoMarkerSlot(name)
  if not name then return nil end
  local low = name:lower()
  -- Exact "video" with nothing after = slot 0
  if low == "video" then return 0 end
  -- "video" followed by optional space(s) then digits
  local n = low:match("^video%s*(%d+)$")
  if n then return tonumber(n) end
  return nil
end

local function GetVideoMarkersSorted()
  local markers = {}
  for i = 0, reaper.CountProjectMarkers(0) - 1 do
    local _, is_rgn, pos, _, name, _ = reaper.EnumProjectMarkers(i)
    if not is_rgn then
      local slot = ParseVideoMarkerSlot(name)
      if slot then
        markers[#markers + 1] = {slot = slot, pos = pos}
      end
    end
  end
  table.sort(markers, function(a, b) return a.slot < b.slot end)
  return markers
end

local function BuildMarkerQueue()
  local queue = {}

  local start_pos = GetMarkerPos("=START")
  if start_pos and not IsPositionTakenByVideo(start_pos) then
    queue[#queue + 1] = start_pos
  end

  local video_markers = GetVideoMarkersSorted()
  for _, m in ipairs(video_markers) do
    if not IsPositionTakenByVideo(m.pos) then
      queue[#queue + 1] = m.pos
    end
  end

  return queue
end

-- ============================================================
-- VIDEO WINDOW
-- ============================================================

local function IsVideoWindowOpen()
  return reaper.GetToggleCommandState(50125) == 1
end

local function OpenAndPositionVideoWindow(src_w, src_h)
  reaper.Main_OnCommand(50125, 0)

  if not reaper.JS_Window_Find then return end

  local win = reaper.JS_Window_Find("Video", true)
  if not win then win = reaper.JS_Window_Find("REAPER Video", true) end
  if not win then return end

  local screen_w, screen_h = 1920, 1080
  local screen_x, screen_y = 0, 0

  local target_w = src_w and math.floor(src_w * 0.5) or 640
  local target_h = src_h and math.floor(src_h * 0.5) or 360

  local max_w = math.floor(screen_w * 0.9)
  local max_h = math.floor(screen_h * 0.9)

  if target_w > max_w then
    local scale = max_w / target_w
    target_w = max_w
    target_h = math.floor(target_h * scale)
  end
  if target_h > max_h then
    local scale = max_h / target_h
    target_h = max_h
    target_w = math.floor(target_w * scale)
  end

  local win_x = screen_x + math.floor((screen_w - target_w) / 2)
  local win_y = screen_y + math.floor((screen_h - target_h) / 2)

  reaper.JS_Window_SetPosition(win, win_x, win_y, target_w, target_h)
end

-- ============================================================
-- TRACK MANAGEMENT
-- ============================================================

local VIDEO_COLOR = reaper.ColorToNative(0x1B, 0x1C, 0x21) | 0x1000000

local function IsVideoTrackName(name)
  if not name then return false end
  local low = name:lower()
  -- "video" or "video" followed by optional space(s) and digits
  return low == "video" or low:match("^video%s*%d+$") ~= nil
end

local function ApplyVideoTrackSettings(track)
  reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", VIDEO_COLOR)
  reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP",   1)
  reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
  reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND",    0)
  reaper.SetMediaTrackInfo_Value(track, "B_TCPPIN",      1)
  reaper.GetSetMediaTrackInfo_String(track, "P_TCP_LAYOUT", "Utility",       true)
  reaper.GetSetMediaTrackInfo_String(track, "P_MCP_LAYOUT", "Utility Video", true)
end

local function GetNextVideoTrackName()
  local names = {}
  for ti = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, ti)
    local _, name = reaper.GetTrackName(track)
    if IsVideoTrackName(name) then names[name:lower()] = true end
  end
  if not names["video"] then return "video" end
  local n = 2
  while true do
    local candidate = "video " .. n
    if not names[candidate] then return candidate end
    n = n + 1
  end
end

local function GetLastVideoTrackIndex()
  local last_idx = -1
  for ti = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, ti)
    local _, name = reaper.GetTrackName(track)
    if IsVideoTrackName(name) then last_idx = ti end
  end
  return last_idx
end

local function ItemsOverlap(track, new_pos, new_len)
  local new_end = new_pos + new_len
  for ii = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item  = reaper.GetTrackMediaItem(track, ii)
    local i_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local i_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if new_pos < (i_pos + i_len) and new_end > i_pos then return true end
  end
  return false
end

local function DeleteAllItemsOnTrack(track)
  local count = reaper.CountTrackMediaItems(track)
  for i = count - 1, 0, -1 do
    local item = reaper.GetTrackMediaItem(track, i)
    reaper.DeleteTrackMediaItem(track, item)
  end
end

local function CreateVideoTrack(name, at_index)
  reaper.InsertTrackAtIndex(at_index, false)
  local track = reaper.GetTrack(0, at_index)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  ApplyVideoTrackSettings(track)
  return track
end

local function GetOrCreateVideoTrack(place_pos, approx_len)
  if reaper.CountSelectedTracks(0) > 0 then
    local sel_track = reaper.GetSelectedTrack(0, 0)
    local _, sel_name = reaper.GetTrackName(sel_track)
    if IsVideoTrackName(sel_name) then
      DeleteAllItemsOnTrack(sel_track)
      ApplyVideoTrackSettings(sel_track)
      return sel_track
    end
  end

  local video_tracks = {}
  for ti = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, ti)
    local _, name = reaper.GetTrackName(track)
    if IsVideoTrackName(name) then
      table.insert(video_tracks, {track = track, idx = ti})
    end
  end

  if #video_tracks == 0 then
    return CreateVideoTrack("video", 0)
  end

  for _, entry in ipairs(video_tracks) do
    if reaper.CountTrackMediaItems(entry.track) == 0 then
      ApplyVideoTrackSettings(entry.track)
      return entry.track
    end
  end

  for _, entry in ipairs(video_tracks) do
    if not ItemsOverlap(entry.track, place_pos, approx_len) then
      ApplyVideoTrackSettings(entry.track)
      return entry.track
    end
  end

  local last_idx = GetLastVideoTrackIndex()
  local new_name = GetNextVideoTrackName()
  return CreateVideoTrack(new_name, last_idx + 1)
end

-- ============================================================
-- MAIN
-- ============================================================

local function Main()
  -- Save UI state
  local cursor_pos            = reaper.GetCursorPosition()
  local view_start, view_end  = reaper.BR_GetArrangeView(0)
  local sel_start, sel_end    = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local video_window_was_open = IsVideoWindowOpen()

  local selected_tracks = {}
  for ti = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, ti)
    if reaper.IsTrackSelected(track) then
      table.insert(selected_tracks, track)
    end
  end
  local selected_items = {}
  for ii = 0, reaper.CountSelectedMediaItems(0) - 1 do
    table.insert(selected_items, reaper.GetSelectedMediaItem(0, ii))
  end

  -- File selection (multi-select)
  local files = SelectVideoFiles()
  if not files or #files == 0 then return end

  -- Duplicate check
  local filtered = {}
  for _, f in ipairs(files) do
    if not FileAlreadyInProject(f) then
      filtered[#filtered + 1] = f
    end
  end
  if #filtered == 0 then return end
  files = filtered

  -- Detect FPS for all files
  local ffprobe = GetFFProbePath()
  local fps_list = {}
  local res_w, res_h

  for i, f in ipairs(files) do
    fps_list[i] = DetectFPS(ffprobe, f)
    if i == 1 then
      res_w, res_h = GetVideoResolution(ffprobe, f)
    end
  end

  -- Multi-file FPS consistency check
  if #files > 1 then
    local ref_fps = fps_list[1]
    for i = 2, #files do
      local f = fps_list[i]
      if ref_fps and f and math.abs(f - ref_fps) > 0.01 then
        reaper.ShowMessageBox(
          "Videos have different frame rates. Match FPS to avoid sync issues.",
          "Frame Rate Mismatch", 0
        )
        return
      end
    end
  end

  local video_fps = fps_list[1]

  -- FPS / project logic
  local project_has_video = ProjectHasVideo()
  local project_fps       = GetProjectFPS()

  if not project_has_video then
    if video_fps then SetProjectFPS(video_fps) end
  else
    if video_fps and math.abs(video_fps - project_fps) > 0.01 then
      local msg = string.format(
        "The movie frame rate doesn't match the project frame rate.\n\n" ..
        "The movie has a frame rate of %s fps.\n" ..
        "The project is currently set to %s fps.\n\n" ..
        "Yes: Change project FPS\n" ..
        "No: Keep current FPS",
        FPSToString(video_fps), FPSToString(project_fps)
      )
      local choice = reaper.ShowMessageBox(msg, "Frame Rate Mismatch", 3)
      if choice == 2 then return end
      if choice == 6 then SetProjectFPS(video_fps) end
    end
  end

  -- Build marker queue
  local marker_queue = BuildMarkerQueue()
  local marker_idx   = 1
  local chain_pos    = GetMarkerPos("=START") or 0.0

  -- Get or create video track
  local first_pos   = marker_queue[1] or chain_pos
  local video_track = GetOrCreateVideoTrack(first_pos, 7200)

  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

  local last_item      = nil
  local inserted_items = {}

  for _, file_path in ipairs(files) do
    local place_pos
    if marker_idx <= #marker_queue then
      place_pos = marker_queue[marker_idx]
      marker_idx = marker_idx + 1
    else
      place_pos = chain_pos
    end

    -- Trim previous item if it overlaps this position
    if last_item then
      local last_pos = reaper.GetMediaItemInfo_Value(last_item, "D_POSITION")
      local last_len = reaper.GetMediaItemInfo_Value(last_item, "D_LENGTH")
      local last_end = last_pos + last_len
      if last_end > place_pos then
        reaper.SetMediaItemInfo_Value(last_item, "D_LENGTH", place_pos - last_pos)
      end
    end

    reaper.SetOnlyTrackSelected(video_track)
    reaper.SetEditCurPos(place_pos, false, false)
    reaper.InsertMedia(file_path, 0)

    -- Get newly inserted item
    local num_items = reaper.CountTrackMediaItems(video_track)
    if num_items > 0 then
      last_item = reaper.GetTrackMediaItem(video_track, num_items - 1)
      if last_item then
        reaper.SetMediaItemInfo_Value(last_item, "B_LOOPSRC", 0)
        table.insert(inserted_items, last_item)
        local item_len = reaper.GetMediaItemInfo_Value(last_item, "D_LENGTH")
        chain_pos = place_pos + item_len
      end
    end
  end

  -- Lock all inserted items after all trimming is done
  for _, item in ipairs(inserted_items) do
    reaper.SetMediaItemInfo_Value(item, "C_LOCK", 1)
  end

  -- Deselect all tracks, restore only non-video original selection
  reaper.SelectAllMediaItems(0, false)
  for ti = 0, reaper.CountTracks(0) - 1 do
    reaper.SetTrackSelected(reaper.GetTrack(0, ti), false)
  end
  for _, track in ipairs(selected_tracks) do
    local _, name = reaper.GetTrackName(track)
    if not IsVideoTrackName(name) then
      reaper.SetTrackSelected(track, true)
    end
  end
  for _, item in ipairs(selected_items) do
    reaper.SetMediaItemSelected(item, true)
  end

  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()

  -- Restore UI state
  reaper.SetEditCurPos(cursor_pos, false, false)
  reaper.BR_SetArrangeView(0, view_start, view_end)
  reaper.GetSet_LoopTimeRange(true, false, sel_start, sel_end, false)

  reaper.Undo_EndBlock("klein_video_import", -1)

  -- Video window: preserve state
  if not video_window_was_open and not project_has_video then
    OpenAndPositionVideoWindow(res_w, res_h)
  elseif video_window_was_open and not IsVideoWindowOpen() then
    reaper.Main_OnCommand(50125, 0)
  end
end

Main()