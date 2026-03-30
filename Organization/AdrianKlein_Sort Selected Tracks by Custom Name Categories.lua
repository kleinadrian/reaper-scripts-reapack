-- @description Sort Selected Tracks by Custom Name Categories
-- @version 1.0
-- @author Adrian Klein
-- @about
--   Sorts selected tracks using custom name categories with priority-based matching.
--   Applies consistent naming and orders tracks with minimal changes.

--[[
 * ReaScript Name: Sort Selected Tracks by Custom Name Categories
 * Author: Adrian Klein
 * Version: 1.0
 * Description:
 *   Sorts selected tracks using custom name categories.
 *   Priority-based category matching with internal sub-ordering.
 *   No popup, no folder creation.
 *   Safe cleanup with lowercase renaming.
 *   Applies Title Case to parent folders if selected.
 *   Adds numbering only for true duplicates.
]]

----------------------------------------
-- Toggles
----------------------------------------

local RENAME_TRACKS = true
local RENUMBER_DUPLICATES = true
local CLEAN_IMPORTED_SUFFIXES = true

----------------------------------------
-- Helpers
----------------------------------------

local function msg(text)
  reaper.ShowMessageBox(text, "Sort selected tracks by custom name categories", 0)
end

local function trim(s)
  s = tostring(s or "")
  s = s:gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end

local function collapse_spaces(s)
  s = tostring(s or "")
  s = s:gsub("%s+", " ")
  return trim(s)
end

local function normalize(s)
  s = tostring(s or "")
  s = s:lower()
  s = s:gsub("[_%-%./\\]", " ")
  s = s:gsub("[%(%)%[%]{}:,;!%?%+%*&\"'#@|]", " ")
  s = s:gsub("%s+", " ")
  return trim(s)
end

local function tokenize(s)
  local t = {}
  s = normalize(s)
  for w in s:gmatch("%S+") do
    t[#t + 1] = w
  end
  return t
end

local NO_SINGULARIZE = {
  ["bass"] = true,
  ["basses"] = true,
  ["brass"] = true,
  ["glass"] = true,
}

local function singularize(word)
  if not word or word == "" then return word end
  if NO_SINGULARIZE[word] then return word end

  if word:match("ies$") and #word > 3 then
    return word:gsub("ies$", "y")
  end
  if word:match("oes$") and #word > 3 then
    return word:gsub("es$", "")
  end
  if word:match("ses$") and #word > 3 then
    return word:gsub("es$", "")
  end
  if word:match("shes$") and #word > 4 then
    return word:gsub("es$", "")
  end
  if word:match("ches$") and #word > 4 then
    return word:gsub("es$", "")
  end
  if word:match("xes$") and #word > 3 then
    return word:gsub("es$", "")
  end
  if word:match("s$") and #word > 2 then
    return word:sub(1, -2)
  end

  return word
end

local function words_map(tokens)
  local map = {}
  for _, w in ipairs(tokens) do
    map[w] = true
    local singular = singularize(w)
    if singular and singular ~= w then
      map[singular] = true
    end
  end
  return map
end

local function has_word(wmap, word)
  return wmap[word] == true
end

local function has_any_word(wmap, words)
  for _, w in ipairs(words) do
    if has_word(wmap, w) then return true end
  end
  return false
end

local function has_all_words(wmap, words)
  for _, w in ipairs(words) do
    if not has_word(wmap, w) then return false end
  end
  return true
end

local function has_phrase(norm, phrase)
  local n = " " .. norm .. " "
  local p = " " .. normalize(phrase) .. " "
  return n:find(p, 1, true) ~= nil
end

local function get_track_guid(track)
  return reaper.GetTrackGUID(track)
end

local function get_track_by_guid(guid)
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetTrackGUID(tr) == guid then
      return tr
    end
  end
  return nil
end

local function get_track_name(track)
  local _, name = reaper.GetTrackName(track, "")
  return name or ""
end

local function set_track_name(track, name)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
end

local function set_only_track_selected(track)
  reaper.Main_OnCommand(40297, 0)
  reaper.SetTrackSelected(track, true)
end

local function is_folder_parent(track)
  return reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
end

local function track_index0(track)
  return reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
end

----------------------------------------
-- Folder title case
----------------------------------------

local FOLDER_TITLE_CASE = {
  ["voiceover"] = "Voiceover",
  ["voice"] = "Voice",
  ["foley"] = "Foley",
  ["effects"] = "Effects",
  ["transitions"] = "Transitions",
  ["impacts"] = "Impacts",
  ["ambi"] = "Ambi",
  ["drones"] = "Drones",
  ["percussion"] = "Percussion",
  ["bass"] = "Bass",
  ["keys"] = "Keys",
  ["synths"] = "Synths",
  ["pads"] = "Pads",
  ["guitars"] = "Guitars",
  ["strings"] = "Strings",
  ["swarm"] = "Swarm",
  ["violins"] = "Violins",
  ["brass"] = "Brass",
  ["woodwinds"] = "Woodwinds",
  ["choir"] = "Choir",
  ["vocals"] = "Vocals",
  ["backing"] = "Backing",
  ["other tracks"] = "Other tracks",
}

local function folder_case_name(name)
  local n = normalize(name)
  return FOLDER_TITLE_CASE[n] or name
end

----------------------------------------
-- Cleanup / renaming
----------------------------------------

local function remove_extension(name)
  return name:gsub("%.(wav|aif|aiff|flac|mp3)$", "")
end

local function safe_cleanup_name(name)
  local s = tostring(name or "")
  s = s:gsub("_", " ")
  s = s:gsub("%-", " ")
  s = remove_extension(s)
  s = s:gsub("%s+[Cc][Oo][Pp][Yy]$", "")
  s = s:gsub("%s*%((%d+)%s*%)$", " %1")
  s = collapse_spaces(s)
  return s
end

local function lowercase_track_name(name)
  return collapse_spaces(tostring(name or ""):lower())
end

local PROTECTED_DUP_BASES = {
  ["violins"] = true,
  ["violin"] = true,
  ["violas"] = true,
  ["viola"] = true,
  ["celli"] = true,
  ["cello"] = true,
  ["basses"] = true,
  ["violin 1"] = true,
  ["violins 1"] = true,
  ["violin 2"] = true,
  ["violins 2"] = true,
  ["violin 1 ld"] = true,
  ["violin 2 ld"] = true,
  ["viola ld"] = true,
  ["celli ld"] = true,
  ["basses ld"] = true,
}

local PROTECTED_SUFFIX_WORDS = {
  ["ld"] = true,
  ["leader"] = true,
  ["close"] = true,
  ["far"] = true,
  ["room"] = true,
  ["l"] = true,
  ["r"] = true,
  ["mid"] = true,
  ["side"] = true,
  ["atmos"] = true,
  ["surround"] = true,
  ["spiccato"] = true,
  ["pizzicato"] = true,
  ["trill"] = true,
  ["staccato"] = true,
  ["tremolo"] = true,
  ["flautando"] = true,
  ["cs"] = true,
}

local function parse_duplicate_suffix(name)
  local n = normalize(name)

  local base_num, num = n:match("^(.-)%s+(%d+)$")
  if base_num and num then
    local last = base_num:match("(%S+)$")
    if PROTECTED_DUP_BASES[base_num] or (last and PROTECTED_SUFFIX_WORDS[last]) then
      return n, nil, false
    end
    return base_num, tonumber(num), true
  end

  local base_letter, letter = n:match("^(.-)%s+([a-z])$")
  if base_letter and letter then
    local last = base_letter:match("(%S+)$")
    if PROTECTED_DUP_BASES[base_letter] or (last and PROTECTED_SUFFIX_WORDS[last]) then
      return n, nil, false
    end
    return base_letter, string.byte(letter) - string.byte("a") + 1, true
  end

  return n, nil, true
end

----------------------------------------
-- Display order
----------------------------------------

local DISPLAY_ORDER = {
  "Voiceover",
  "Voice",
  "Foley",
  "Effects",
  "Transitions",
  "Impacts",
  "Ambi",
  "Drones",
  "Percussion",
  "Bass",
  "Keys",
  "Synths",
  "Pads",
  "Guitars",
  "Strings",
  "Swarm",
  "Violins",
  "Brass",
  "Woodwinds",
  "Choir",
  "Vocals",
  "Backing",
  "Other tracks"
}

local DISPLAY_INDEX = {}
for i, cat in ipairs(DISPLAY_ORDER) do
  DISPLAY_INDEX[cat] = i
end

----------------------------------------
-- Internal sub-order
----------------------------------------

local SUB = {
  Voiceover = {"voiceover", "dubb"},
  Voice = {"dialog", "dialogue", "voice"},
  Foley = {
    "foley", "footstep", "foot", "step", "walk", "walking", "run", "running",
    "hop", "hopping", "jump", "fall", "falling", "boot", "gravel", "dirt",
    "snow", "bare", "asphalt", "rock", "sneaker", "cloth", "leather", "armor",
    "body", "movement", "handling", "grab", "release", "prop", "door",
    "furniture", "glass", "bottle", "ceramic", "backpack", "gear", "zipper",
    "velcro", "coin", "chain", "rope", "sword", "gun", "metal keys",
    "key ring", "keys fx", "keys efx", "key fx", "key efx", "stair",
    "staircase", "stamp", "stomp", "debris", "granule"
  },
  Effects = {"effect", "fx", "efx", "sfx", "sound effect", "glitch", "stutter"},
  Transitions = {"transition", "trans", "whoosh", "swoosh", "swish", "riser", "downer", "sweep", "noise", "reverse", "airy"},
  Impacts = {"impact", "hit", "slam", "stinger", "boom", "braam", "sub drop", "sub boom", "low boom", "transition hit", "time warp"},
  Ambi = {"ambi", "ambiance", "atmos", "atmosphere", "background"},
  Drones = {"drone", "texture", "pedal"},
  Percussion = {
    "percussion", "perc", "drum", "drm", "kick", "bd", "snare", "sn",
    "hi hat", "hihat", "cymbal", "crash", "splash", "tom", "rototom",
    "frame drum", "darbuka", "tombek", "dhol", "dholak", "taiko", "surdo",
    "bombo", "boobam", "bucket", "scrap", "epic", "hammer", "hi perc",
    "mid perc", "low perc", "celeste", "gangsa", "kanjira", "khol",
    "mridangam", "pakhawaj", "tabla", "marimba", "vibraphone", "xylo",
    "xylophone", "glockenspiel", "crotales", "bell", "tubular bell",
    "mallet", "tam tam", "tamtam", "gong"
  },
  Bass = {
    "bass", "sub", "808", "sub bass", "subbass", "lowbass", "low bass",
    "bass guitar", "ac bass", "acoustic bass", "electric bass",
    "synth bass", "bass synth", "pulse bass", "bass pulse", "808 bass"
  },
  Keys = {"keys", "piano", "el piano", "pianet", "mark", "mark i", "mark ii", "clavinet", "mellotron", "hapsi", "harpsichord", "accordion", "harmonica", "organ"},
  Synths = {"synth", "synthesizer", "sine", "modular", "pulse", "low pulse", "seq", "sequence", "arp", "arpeggiator"},
  Pads = {"pad", "padding", "noisescape", "soundscape"},
  Guitars = {"guitar", "gtr", "gt", "ac guitar", "el guitar"},
  Strings = {"string", "harp", "cimbalom", "ukulele", "erhu", "guqin", "guzheng", "pipa", "yangqin", "tanbur", "kemence", "kanun", "saz"},
  Swarm = {"swarm", "cluster", "aleatoric", "alea", "trill"},
  Violins = {"violin 1 ld", "violins 1", "violin 2 ld", "violins 2", "viola ld", "viola", "violas", "celli ld", "cello", "celli", "basses ld", "basses", "contrabass", "double bass", "violin", "violins"},
  Brass = {"saxophone", "trumpet", "horn", "tenor trombone", "bass trombone", "contrabass trombone", "cimbasso", "tuba", "contrabass tuba", "trombone"},
  Woodwinds = {"piccolo", "flute", "bass flute", "oboe", "cor anglais", "coranglais", "clarinet", "bass clarinet", "bassclarinet", "contrabass clarinet", "bassoon", "contrabassoon", "ney", "reed", "bagpipe", "pipe", "shawm", "zurna"},
  Choir = {"soprano", "alto", "tenor", "choir bass", "bass choir", "tutti", "choir fx"},
  Vocals = {"vocal lead", "vocal ld", "lead vocal", "lead vox", "ld vocal", "ld vox", "int vocal", "int vox", "vocal", "vox", "adlib", "double"},
  Backing = {"backing vocal", "backing vox", "back vocal", "back vox", "bg vocal", "bg vox", "bk vocal", "bk vox", "backing", "bk", "bvox", "bgv"}
}

local function entry_matches(norm, wmap, entry)
  local e = normalize(entry)
  if e:find(" ", 1, true) then
    return has_phrase(norm, e)
  end
  return has_word(wmap, e)
end

local function subindex_from_entries(norm, wmap, entries)
  for i, entry in ipairs(entries) do
    if entry_matches(norm, wmap, entry) then
      return i
    end
  end
  return 999
end

----------------------------------------
-- Category detection
----------------------------------------

local function prep(name)
  local norm = normalize(name)
  local wmap = words_map(tokenize(name))
  return norm, wmap
end

local function is_voiceover(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Voiceover) < 999
end

local function is_voice(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Voice) < 999
end

local function is_foley(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Foley) < 999
end

local function is_effects(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Effects) < 999
end

local function is_transitions(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Transitions) < 999
end

local function is_impacts(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Impacts) < 999
end

local function is_ambi(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Ambi) < 999
end

local function is_drones(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Drones) < 999
end

local function is_percussion(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Percussion) < 999
end

local function is_bass(norm, wmap)
  if has_all_words(wmap, {"bass", "clarinet"}) then return false end
  if has_all_words(wmap, {"bass", "flute"}) then return false end
  if has_all_words(wmap, {"bass", "trombone"}) then return false end
  if has_all_words(wmap, {"contrabass", "trombone"}) then return false end
  if has_all_words(wmap, {"contrabass", "tuba"}) then return false end
  if has_all_words(wmap, {"choir", "bass"}) then return false end
  if has_all_words(wmap, {"bass", "choir"}) then return false end
  if has_all_words(wmap, {"double", "bass"}) then return false end
  if has_all_words(wmap, {"basses", "ld"}) then return false end
  if has_word(wmap, "basses") then return false end
  return subindex_from_entries(norm, wmap, SUB.Bass) < 999
end

local function is_keys(norm, wmap)
  if has_phrase(norm, "keys fx") or has_phrase(norm, "keys efx") or has_phrase(norm, "key fx") or has_phrase(norm, "key efx") or has_phrase(norm, "metal keys") or has_phrase(norm, "key ring") then
    return false
  end
  return subindex_from_entries(norm, wmap, SUB.Keys) < 999
end

local function is_synths(norm, wmap)
  if has_all_words(wmap, {"bass", "synth"}) then return false end
  if has_all_words(wmap, {"bass", "pulse"}) then return false end
  if has_all_words(wmap, {"808", "bass"}) then return false end
  if has_all_words(wmap, {"sub", "bass"}) then return false end
  return subindex_from_entries(norm, wmap, SUB.Synths) < 999
end

local function is_pads(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Pads) < 999
end

local function is_guitars(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Guitars) < 999
end

local function is_strings(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Strings) < 999
end

local function is_swarm(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Swarm) < 999
end

local function is_violins(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Violins) < 999
end

local function is_brass(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Brass) < 999
end

local function is_woodwinds(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Woodwinds) < 999
end

local function is_choir(norm, wmap)
  if has_word(wmap, "bass") and not has_phrase(norm, "choir bass") and not has_phrase(norm, "bass choir") then
    -- plain bass should not trigger Choir
  end
  return subindex_from_entries(norm, wmap, SUB.Choir) < 999
end

local function is_vocals(norm, wmap)
  return subindex_from_entries(norm, wmap, SUB.Vocals) < 999
end

local function is_backing(norm, wmap)
  if has_all_words(wmap, {"background", "vocal"}) or has_all_words(wmap, {"background", "vox"}) then
    return true
  end
  return subindex_from_entries(norm, wmap, SUB.Backing) < 999
end

local function detect_category(track_name)
  local norm, wmap = prep(track_name)

  if is_voiceover(norm, wmap) then return "Voiceover", subindex_from_entries(norm, wmap, SUB.Voiceover) end
  if is_voice(norm, wmap) then return "Voice", subindex_from_entries(norm, wmap, SUB.Voice) end

  if is_foley(norm, wmap) then return "Foley", subindex_from_entries(norm, wmap, SUB.Foley) end
  if is_choir(norm, wmap) then return "Choir", subindex_from_entries(norm, wmap, SUB.Choir) end
  if is_backing(norm, wmap) then return "Backing", subindex_from_entries(norm, wmap, SUB.Backing) end
  if is_vocals(norm, wmap) then return "Vocals", subindex_from_entries(norm, wmap, SUB.Vocals) end
  if is_woodwinds(norm, wmap) then return "Woodwinds", subindex_from_entries(norm, wmap, SUB.Woodwinds) end
  if is_brass(norm, wmap) then return "Brass", subindex_from_entries(norm, wmap, SUB.Brass) end
  if is_violins(norm, wmap) then return "Violins", subindex_from_entries(norm, wmap, SUB.Violins) end
  if is_swarm(norm, wmap) then return "Swarm", subindex_from_entries(norm, wmap, SUB.Swarm) end
  if is_strings(norm, wmap) then return "Strings", subindex_from_entries(norm, wmap, SUB.Strings) end
  if is_percussion(norm, wmap) then return "Percussion", subindex_from_entries(norm, wmap, SUB.Percussion) end
  if is_bass(norm, wmap) then return "Bass", subindex_from_entries(norm, wmap, SUB.Bass) end
  if is_keys(norm, wmap) then return "Keys", subindex_from_entries(norm, wmap, SUB.Keys) end
  if is_synths(norm, wmap) then return "Synths", subindex_from_entries(norm, wmap, SUB.Synths) end
  if is_pads(norm, wmap) then return "Pads", subindex_from_entries(norm, wmap, SUB.Pads) end
  if is_guitars(norm, wmap) then return "Guitars", subindex_from_entries(norm, wmap, SUB.Guitars) end

  if is_drones(norm, wmap) then return "Drones", subindex_from_entries(norm, wmap, SUB.Drones) end

  if is_transitions(norm, wmap) then return "Transitions", subindex_from_entries(norm, wmap, SUB.Transitions) end
  if is_impacts(norm, wmap) then return "Impacts", subindex_from_entries(norm, wmap, SUB.Impacts) end
  if is_effects(norm, wmap) then return "Effects", subindex_from_entries(norm, wmap, SUB.Effects) end

  if is_ambi(norm, wmap) then return "Ambi", subindex_from_entries(norm, wmap, SUB.Ambi) end

  return "Other tracks", 999
end

----------------------------------------
-- Main
----------------------------------------

local sel_count = reaper.CountSelectedTracks(0)
if sel_count == 0 then
  msg("Select the tracks you want to sort first.")
  return
end

local selected = {}
local min_index = math.huge

for i = 0, sel_count - 1 do
  local tr = reaper.GetSelectedTrack(0, i)
  local idx = track_index0(tr)
  local name = get_track_name(tr)
  local guid = get_track_guid(tr)
  local category, subindex = detect_category(name)

  if idx < min_index then
    min_index = idx
  end

  selected[#selected + 1] = {
    guid = guid,
    name = name,
    orig_index = idx,
    category = category,
    subindex = subindex or 999,
    display_index = DISPLAY_INDEX[category] or 999
  }
end

table.sort(selected, function(a, b)
  if a.display_index ~= b.display_index then
    return a.display_index < b.display_index
  end
  if a.subindex ~= b.subindex then
    return a.subindex < b.subindex
  end
  return a.orig_index < b.orig_index
end)

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for i, item in ipairs(selected) do
  local tr = get_track_by_guid(item.guid)
  if tr then
    set_only_track_selected(tr)
    reaper.ReorderSelectedTracks(min_index + (i - 1), 0)
  end
end

reaper.Main_OnCommand(40297, 0)
for _, item in ipairs(selected) do
  local tr = get_track_by_guid(item.guid)
  if tr then
    reaper.SetTrackSelected(tr, true)
  end
end

if RENAME_TRACKS then
  local original_tracks = {}

  for _, item in ipairs(selected) do
    local tr = get_track_by_guid(item.guid)
    if tr then
      local new_name = get_track_name(tr)

      if CLEAN_IMPORTED_SUFFIXES then
        new_name = safe_cleanup_name(new_name)
      end

      if is_folder_parent(tr) then
        new_name = folder_case_name(new_name)
      else
        new_name = lowercase_track_name(new_name)
      end

      original_tracks[#original_tracks + 1] = { track = tr, new_name = new_name }
    end
  end

  for _, item in ipairs(original_tracks) do
    set_track_name(item.track, item.new_name)
  end

  if RENUMBER_DUPLICATES then
    local groups_by_base = {}

    for _, item in ipairs(original_tracks) do
      local tr = item.track
      if not is_folder_parent(tr) then
        local current_name = get_track_name(tr)
        local base, _, safe = parse_duplicate_suffix(current_name)
        if safe then
          groups_by_base[base] = groups_by_base[base] or {}
          groups_by_base[base][#groups_by_base[base] + 1] = tr
        end
      end
    end

    for base, tracks in pairs(groups_by_base) do
      if #tracks > 1 then
        table.sort(tracks, function(a, b)
          return track_index0(a) < track_index0(b)
        end)

        for i, tr in ipairs(tracks) do
          set_track_name(tr, base .. " " .. tostring(i))
        end
      end
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Sort selected tracks by custom name categories", -1)