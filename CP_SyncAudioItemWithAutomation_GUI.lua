-- Configuration
local WINDOW_FOLLOW_MOUSE = false

local time_selection_extension = 0.0
local sync_edit_cursor = false
local sync_automation = false
local sync_time_selection = true 
local auto_play = true
local playback_mode = "preview"
local last_selected_item_guid = nil
local mouse_down_time = 0
local last_mouse_state = 0
local CLICK_THRESHOLD = 0.15
local mouse_down_start = 0
local LONG_PRESS_THRESHOLD = 0.15  -- Seuil en secondes pour considérer un appui comme "long"
local is_dragging = false
local last_track_guid = nil

local WINDOW_X_OFFSET = 35  -- Horizontal offset from mouse position in pixels
local WINDOW_Y_OFFSET = 35  -- Vertical offset from mouse position in pixels
local WINDOW_WIDTH = 275   -- Initial window width in pixels
local WINDOW_HEIGHT = 275   -- Initial window height in pixels

-- Variables pour l'interface ImGui
local ctx = reaper.ImGui_CreateContext('Time Selection Extension Config')
local WINDOW_FLAGS = 0
local window_open = true
local window_position_set = false  -- Add this line

-- Variables globales pour le tracking des changements
local last_edit_cursor_pos = -1
local lastItemState = {
  position = nil,
  length = nil,
  rate = nil,
  sourceLength = nil,
  stretchMarkersHash = nil
}
local lastAutomationStates = {}
local lastEnvelopeCount = {}


-- Ajouter ces fonctions au début du script
function SaveSettings()
  reaper.SetExtState("TimeSelectionSync", "playback_mode", playback_mode, true)
  reaper.SetExtState("TimeSelectionSync", "sync_edit_cursor", sync_edit_cursor and "1" or "0", true)
  reaper.SetExtState("TimeSelectionSync", "sync_automation", sync_automation and "1" or "0", true)
  reaper.SetExtState("TimeSelectionSync", "sync_time_selection", sync_time_selection and "1" or "0", true) -- Nouvelle ligne
  reaper.SetExtState("TimeSelectionSync", "auto_play", auto_play and "1" or "0", true)
  reaper.SetExtState("TimeSelectionSync", "time_selection_extension", tostring(time_selection_extension), true)
end

-- Mettre à jour LoadSettings pour charger la nouvelle option
function LoadSettings()
  local cursor = reaper.GetExtState("TimeSelectionSync", "sync_edit_cursor")
  local automation = reaper.GetExtState("TimeSelectionSync", "sync_automation")
  local time_sel = reaper.GetExtState("TimeSelectionSync", "sync_time_selection") -- Nouvelle ligne
  local play = reaper.GetExtState("TimeSelectionSync", "auto_play")
  local ext = reaper.GetExtState("TimeSelectionSync", "time_selection_extension")
  local mode = reaper.GetExtState("TimeSelectionSync", "playback_mode")

  playback_mode = mode ~= "" and mode or "preview"
  sync_edit_cursor = cursor == "1"
  sync_automation = automation == "1"
  sync_time_selection = time_sel == "1" -- Correction du chargement
  auto_play = play == "1"
  time_selection_extension = ext ~= "" and tonumber(ext) or 0.0
end

-- Fonction pour comparer deux nombres avec une tolérance
local function approximately(a, b, tolerance)
  tolerance = tolerance or 0.000001
  return math.abs(a - b) < tolerance
end

-- Fonction pour calculer un hash des stretch markers
local function calculateStretchMarkersHash(take)
  if not take then return "" end
  
  local hash = ""
  local stretchMarkerCount = reaper.GetTakeNumStretchMarkers(take)
  
  for i = 0, stretchMarkerCount - 1 do
    local retval, pos, srcpos = reaper.GetTakeStretchMarker(take, i)
    if retval >= 0 then
      hash = hash .. string.format("%.6f:%.6f;", pos, srcpos)
    end
  end
  
  return hash
end

-- Fonction pour obtenir l'état actuel d'un item
local function getItemState(item)
  if not item then return nil end
  
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local take = reaper.GetActiveTake(item)
  local rate = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
  
  -- Obtenir la source length
  local sourceLength = 0
  if take then
    local source = reaper.GetMediaItemTake_Source(take)
    if source then
      local source_length, lengthIsQN = reaper.GetMediaSourceLength(source)
      if lengthIsQN then
        local tempo = reaper.Master_GetTempo()
        sourceLength = source_length * 60 / tempo
      else
        sourceLength = source_length
      end
    end
  end
  
  local stretchMarkersHash = take and calculateStretchMarkersHash(take) or ""
  
  return {
    position = pos,
    length = length,
    rate = rate,
    sourceLength = sourceLength,
    stretchMarkersHash = stretchMarkersHash
  }
end

-- Fonction pour obtenir l'état d'un automation item
local function getAutomationItemState(env, idx)
  local pos = reaper.GetSetAutomationItemInfo(env, idx, "D_POSITION", 0, false)
  local len = reaper.GetSetAutomationItemInfo(env, idx, "D_LENGTH", 0, false)
  local rate = reaper.GetSetAutomationItemInfo(env, idx, "D_PLAYRATE", 0, false)
  
  return {
    position = pos,
    length = len,
    rate = rate
  }
end

-- Fonction pour détecter les changements d'enveloppes
local function detectEnvelopeChanges(track)
  if not track then return false end
  
  local trackGUID = reaper.GetTrackGUID(track)
  local current_env_count = reaper.CountTrackEnvelopes(track)
  
  if lastEnvelopeCount[trackGUID] == nil then
    lastEnvelopeCount[trackGUID] = current_env_count
    return true
  end
  
  if current_env_count ~= lastEnvelopeCount[trackGUID] then
    lastEnvelopeCount[trackGUID] = current_env_count
    return true
  end
  
  return false
end

-- Fonction pour détecter les changements
local function detectChanges(selected_item)
  if not selected_item then return false end
  
  local track = reaper.GetMediaItem_Track(selected_item)
  local envelopeChanged = detectEnvelopeChanges(track)
  
  local currentState = getItemState(selected_item)
  
  local itemChanged = not lastItemState.length or
                     not approximately(currentState.length, lastItemState.length) or
                     not approximately(currentState.rate, lastItemState.rate) or
                     not approximately(currentState.sourceLength, lastItemState.sourceLength) or
                     currentState.stretchMarkersHash ~= lastItemState.stretchMarkersHash
  
  if envelopeChanged then
    return true
  end
  
  local track = reaper.GetMediaItem_Track(selected_item)
  local automationChanged = false
  local currentAutomationStates = {}
  
  local env_count = reaper.CountTrackEnvelopes(track)
  for k = 0, env_count - 1 do
    local env = reaper.GetTrackEnvelope(track, k)
    local ai_count = reaper.CountAutomationItems(env)
    
    currentAutomationStates[k] = {}
    
    for l = 0, ai_count - 1 do
      local currentAIState = getAutomationItemState(env, l)
      currentAutomationStates[k][l] = currentAIState
      
      if not lastAutomationStates[k] or
         not lastAutomationStates[k][l] or
         not approximately(currentAIState.position, lastAutomationStates[k][l].position) or
         not approximately(currentAIState.length, lastAutomationStates[k][l].length) or
         not approximately(currentAIState.rate, lastAutomationStates[k][l].rate) then
        automationChanged = true
      end
    end
    
    if not lastAutomationStates[k] or #currentAutomationStates[k] ~= #lastAutomationStates[k] then
      automationChanged = true
    end
  end
  
  if itemChanged or automationChanged then
    lastItemState = currentState
    lastAutomationStates = currentAutomationStates
    return true
  end
  
  return false
end

function isMouseOverMediaItem()
  local x, y = reaper.GetMousePosition()
  local item, take = reaper.GetItemFromPoint(x, y, false)
  return item
end

function isReaperWindowActive()
  local hwnd = reaper.GetMainHwnd()
  return reaper.JS_Window_GetForeground() == hwnd
end

function isLeftClick()
  local current_mouse_state = reaper.JS_Mouse_GetState(1)
  local current_time = reaper.time_precise()
  
  -- Début de l'appui
  if current_mouse_state == 1 and last_mouse_state == 0 then
    mouse_down_time = current_time
    mouse_down_start = current_time
    is_dragging = false
  end
  
  -- Pendant l'appui, vérifier si c'est un appui long
  if current_mouse_state == 1 and last_mouse_state == 1 then
    if (current_time - mouse_down_start) > LONG_PRESS_THRESHOLD then
      is_dragging = true
      -- Stop le transport si on commence à déplacer un item
      if is_dragging and reaper.GetPlayState() == 1 then
        reaper.Main_OnCommand(1016, 0) -- Transport: Stop
      end
    end
  end
  
  -- Relâchement du clic
  if current_mouse_state == 0 and last_mouse_state == 1 then
    local was_short_click = (current_time - mouse_down_start) < LONG_PRESS_THRESHOLD and not is_dragging
    last_mouse_state = current_mouse_state
    return was_short_click
  end
  
  last_mouse_state = current_mouse_state
  return false
end

function PlaySelectedItem()
  if not (auto_play and isReaperWindowActive()) then 
    return 
  end

  local selected_item_count = reaper.CountSelectedMediaItems(0)
  local is_playing = reaper.GetPlayState() & 1 == 1
  local is_previewing = reaper.GetPlayState() & 4 == 4
  
  -- Stop any current playback
  if selected_item_count == 0 and (is_playing or is_previewing) then
    if playback_mode == "preview" then
      reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_PREV_TAKE_CURSOR"), 0)
    else
      reaper.Main_OnCommand(1016, 0)  -- Stop
    end
    return
  end
  
  if selected_item_count == 0 then return end

  local clicked_item = isMouseOverMediaItem()
  if clicked_item and isLeftClick() then
    reaper.SetMediaItemSelected(clicked_item, true)
    -- Set edit cursor to item start
    local item_pos = reaper.GetMediaItemInfo_Value(clicked_item, "D_POSITION")
    reaper.SetEditCurPos(item_pos, false, false)
    -- Play based on selected mode
    if playback_mode == "preview" then
      reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_PREV_TAKE_CURSOR"), 0)
    else
      reaper.Main_OnCommand(1007, 0)  -- Play
    end
  end
end

-- Ajouter cette fonction dans la boucle MainLoop
function ProcessFades()
  if not is_fading or not fade_start_time then return end
  
  local master_track = reaper.GetMasterTrack(0)
  local current_time = reaper.time_precise()
  local elapsed = current_time - fade_start_time
  local fade_duration = fade_type == "in" and FADE_IN_LENGTH or FADE_OUT_LENGTH
  
  if elapsed >= fade_duration then
    -- Fin du fade
    if fade_type == "in" then
      reaper.SetMediaTrackInfo_Value(master_track, "D_VOL", 1)
    else
      reaper.Main_OnCommand(1016, 0) -- Transport: Stop
      reaper.SetMediaTrackInfo_Value(master_track, "D_VOL", 1)
    end
    is_fading = false
    fade_start_time = nil
    return
  end
  
  local progress = elapsed / fade_duration
  local vol = fade_type == "in" and progress or (1 - progress)
  reaper.SetMediaTrackInfo_Value(master_track, "D_VOL", vol)
end

function SyncAutomationItems()
  local selected_item = reaper.GetSelectedMediaItem(0, 0)
  if not selected_item then return end
  
  local item_pos = reaper.GetMediaItemInfo_Value(selected_item, "D_POSITION")
  local item_length = reaper.GetMediaItemInfo_Value(selected_item, "D_LENGTH")
  local take = reaper.GetActiveTake(selected_item)
  local item_rate = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
  local source_length = item_length * item_rate

  -- Synchronisation de la time selection seulement si activée
  if sync_time_selection then
    local start_time = item_pos
    local end_time = item_pos + item_length + time_selection_extension
    reaper.GetSet_LoopTimeRange(true, false, start_time, end_time, false)
  end
  
  if sync_edit_cursor then
    reaper.SetEditCurPos(item_pos, false, false)
    last_edit_cursor_pos = item_pos
  end
  
  if not sync_automation then return end
  
  local track = reaper.GetMediaItem_Track(selected_item)
  local track_guid = reaper.GetTrackGUID(track)
  
  -- Only update if we're still on the same track
  if last_track_guid and last_track_guid ~= track_guid then
      last_track_guid = track_guid
      return
  end
  
  last_track_guid = track_guid
  
  if not detectChanges(selected_item) then return end
  
  local env_count = reaper.CountTrackEnvelopes(track)
  for k = 0, env_count - 1 do
      local env = reaper.GetTrackEnvelope(track, k)
      
      -- Skip if envelope isn't visible
      local br_env = reaper.BR_EnvAlloc(env, false)
      local _, _, _, _, _, visible = reaper.BR_EnvGetProperties(br_env)
      reaper.BR_EnvFree(br_env, false)
      if not visible then goto continue end
      
      local ai_count = reaper.CountAutomationItems(env)
      local ai_found = false
      
      for l = 0, ai_count - 1 do
          local ai_pos = reaper.GetSetAutomationItemInfo(env, l, "D_POSITION", 0, false)
          
          if approximately(ai_pos, item_pos) then
              -- Force the loop length to match the item length
              reaper.GetSetAutomationItemInfo(env, l, "D_LENGTH", math.max(item_length, 0.1), true)
              reaper.GetSetAutomationItemInfo(env, l, "D_PLAYRATE", item_rate, true)
              reaper.GetSetAutomationItemInfo(env, l, "D_LOOPLEN", item_length, true)  -- Force loop length to match item length
              reaper.GetSetAutomationItemInfo(env, l, "D_POOL_LOOPLEN", item_length, true)  -- Also set pool loop length
              reaper.GetSetAutomationItemInfo(env, l, "D_LENGTH", item_length, true)
              
              ai_found = true
              break
          end
      end
      
      if not ai_found and sync_automation then
          local new_ai = reaper.InsertAutomationItem(env, -1, item_pos, math.max(item_length, 0.1))
          reaper.GetSetAutomationItemInfo(env, new_ai, "D_PLAYRATE", item_rate, true)
          reaper.GetSetAutomationItemInfo(env, new_ai, "D_LOOPLEN", item_length, true)  -- Set loop length for new items
          reaper.GetSetAutomationItemInfo(env, new_ai, "D_POOL_LOOPLEN", item_length, true)  -- Set pool loop length for new items
          reaper.GetSetAutomationItemInfo(env, new_ai, "D_LENGTH", item_length, true)
      end
      
      ::continue::
  end
end

function MainLoop()
  -- Définit la position de la fenêtre au premier lancement
  if not window_position_set then
    if WINDOW_FOLLOW_MOUSE then
      -- Position au curseur de souris
      local mouse_x, mouse_y = reaper.GetMousePosition()
      reaper.ImGui_SetNextWindowPos(ctx, mouse_x + WINDOW_X_OFFSET, mouse_y + WINDOW_Y_OFFSET)
    end
    reaper.ImGui_SetNextWindowSize(ctx, WINDOW_WIDTH, WINDOW_HEIGHT)
    window_position_set = true
  end

  local visible, open = reaper.ImGui_Begin(ctx, 'Time Selection Config', true, WINDOW_FLAGS)
  if visible then
    -- Options section
    reaper.ImGui_Text(ctx, "Options:")
    reaper.ImGui_Spacing(ctx)
    
    -- Time Selection option
    local time_sel_changed
    time_sel_changed, sync_time_selection = reaper.ImGui_Checkbox(ctx, "Sync Time Selection", sync_time_selection)
    reaper.ImGui_Spacing(ctx)
    
    local cursor_changed
    cursor_changed, sync_edit_cursor = reaper.ImGui_Checkbox(ctx, "Sync Edit Cursor", sync_edit_cursor)
    reaper.ImGui_Spacing(ctx)
    
    local automation_changed
    automation_changed, sync_automation = reaper.ImGui_Checkbox(ctx, "Sync Automation", sync_automation)
    reaper.ImGui_Spacing(ctx)
    
    local play_changed
    play_changed, auto_play = reaper.ImGui_Checkbox(ctx, "Auto-Play", auto_play)

    -- Extension settings (seulement visible si sync_time_selection est activé)
    if sync_time_selection then
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)
      
      reaper.ImGui_Text(ctx, string.format("Time Selection Extension: %.2f s", time_selection_extension))
      reaper.ImGui_Spacing(ctx)
      
      local changed
      changed, time_selection_extension = reaper.ImGui_SliderDouble(ctx, 's', 
                                                                time_selection_extension, 0.0, 5.0, '%.2f')
      reaper.ImGui_Spacing(ctx)
      
      -- Preset buttons
      reaper.ImGui_Text(ctx, "Presets:")
      if reaper.ImGui_Button(ctx, "0.0s") then
        time_selection_extension = 0.0
        changed = true
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "0.1s") then
        time_selection_extension = 0.1
        changed = true
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "0.3s") then
        time_selection_extension = 0.3
        changed = true
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "0.5s") then
        time_selection_extension = 0.5
        changed = true
      end
      
      if changed or cursor_changed or automation_changed or play_changed or time_sel_changed then
        SaveSettings()
      end
    end
    
    reaper.ImGui_End(ctx)
  end

  -- Process automation and features
  if auto_play then 
    PlaySelectedItem() 
  end
  
  SyncAutomationItems()
  
  if sync_edit_cursor then
    local selected_item = reaper.GetSelectedMediaItem(0, 0)
    if selected_item then
      local item_pos = reaper.GetMediaItemInfo_Value(selected_item, "D_POSITION")
      local current_edit_cursor_pos = reaper.GetCursorPosition()
      if not approximately(current_edit_cursor_pos, item_pos) then
        reaper.SetEditCurPos(item_pos, false, false)
      end
    end
  end
  
  reaper.PreventUIRefresh(-1)
  
  if open then
    reaper.defer(MainLoop)
  else
    SaveSettings()
  end
end

function ToggleScript()
  local _, _, sectionID, cmdID = reaper.get_action_context()
  local state = reaper.GetToggleCommandState(cmdID)
  
  if state == -1 or state == 0 then
    reaper.SetToggleCommandState(sectionID, cmdID, 1)
    reaper.RefreshToolbar2(sectionID, cmdID)
    reaper.Main_OnCommand(42213, 0)
    Start()
  else
    reaper.SetToggleCommandState(sectionID, cmdID, 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
    reaper.Main_OnCommand(42213, 0)
    Stop()
  end
end

function Start()
  LoadSettings()
  if reaper.GetToggleCommandState(40070) == 0 then
      reaper.Main_OnCommand(40070, 0)
  end
  MainLoop()
end

function Stop()
  local selected_item = reaper.GetSelectedMediaItem(0, 0)
  if selected_item then
    SyncAutomationItems()
  end
  window_open = false
  SaveSettings()
  reaper.UpdateArrange()
end

function Exit()
  local _, _, sectionID, cmdID = reaper.get_action_context()
  SaveSettings()
  
  reaper.SetToggleCommandState(sectionID, cmdID, 0)
  reaper.RefreshToolbar2(sectionID, cmdID)
  
  if reaper.GetToggleCommandState(42213) == 1 then
    reaper.Main_OnCommand(42213, 0)
  end
end

reaper.atexit(Exit)
ToggleScript()
