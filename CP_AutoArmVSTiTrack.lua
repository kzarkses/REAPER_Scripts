-- @description Auto arm for selected instrument plugin tracks
-- @author mrtnz (modifié par l'assistant)
-- @version 1.0
-- @about
--   Automatically arms/disarms VSTi tracks based on selection
local retval, filename, section_id, command_id = reaper.get_action_context()

-- Configuration
local force_refresh = false -- Si false, vérifie uniquement lors des changements

-- Variables pour tracker les changements
local last_track_count = 0
local last_track_selection_state = {}
local last_track_vsti_state = {}

function ToolbarButton(enable)
  reaper.SetToggleCommandState(section_id, command_id, enable)
  reaper.RefreshToolbar2(section_id, command_id)
end

function HasStateChanged()
  local current_track_count = reaper.CountTracks(0)
  
  -- Vérifier si le nombre de pistes a changé
  if current_track_count ~= last_track_count then
    last_track_count = current_track_count
    return true
  end
  
  -- Vérifier les changements de sélection et de VSTi pour chaque piste
  local changes = false
  for i = 1, current_track_count do
    local tr = reaper.GetTrack(0, i-1)
    if tr then
      local track_guid = reaper.GetTrackGUID(tr)
      local is_selected = reaper.IsTrackSelected(tr)
      local has_vsti = reaper.TrackFX_GetInstrument(tr) ~= -1
      
      -- Vérifier si l'état a changé pour cette piste
      if last_track_selection_state[track_guid] ~= is_selected or
         last_track_vsti_state[track_guid] ~= has_vsti then
        changes = true
      end
      
      -- Mettre à jour les états
      last_track_selection_state[track_guid] = is_selected
      last_track_vsti_state[track_guid] = has_vsti
    end
  end
  
  return changes
end

function CheckInstrumentTracks()
  if not force_refresh and not HasStateChanged() then
    reaper.defer(CheckInstrumentTracks)
    return
  end
  
  local c_tracks = reaper.CountTracks(0)
  local changes = false
  
  if c_tracks ~= nil then
    for i = 1, c_tracks do
      local tr = reaper.GetTrack(0, i-1)
      if tr ~= nil then
        local id = reaper.TrackFX_GetInstrument(tr)
        if id ~= -1 then
          -- Gérer l'armement automatique basé sur la sélection
          local is_selected = reaper.IsTrackSelected(tr)
          local is_armed = reaper.GetMediaTrackInfo_Value(tr, 'I_RECARM')
          
          if is_selected and is_armed == 0 then
            -- Armer la piste si elle est sélectionnée et non armée
            reaper.SetMediaTrackInfo_Value(tr, 'I_RECARM', 1)
            changes = true
          elseif not is_selected and is_armed == 1 then
            -- Désarmer la piste si elle n'est pas sélectionnée mais armée
            reaper.SetMediaTrackInfo_Value(tr, 'I_RECARM', 0)
            changes = true
          end
        end
      end
    end
  end
  
  if changes then
    reaper.UpdateArrange()
  end
  
  reaper.defer(CheckInstrumentTracks)
end

function Exit()
  ToolbarButton(0)
end

function Init()
  -- Initialiser l'état des pistes
  last_track_count = reaper.CountTracks(0)
  for i = 1, last_track_count do
    local tr = reaper.GetTrack(0, i-1)
    if tr then
      local track_guid = reaper.GetTrackGUID(tr)
      last_track_selection_state[track_guid] = reaper.IsTrackSelected(tr)
      last_track_vsti_state[track_guid] = reaper.TrackFX_GetInstrument(tr) ~= -1
    end
  end
end

if reaper.GetToggleCommandStateEx(section_id, command_id) == 0 then
  reaper.atexit(Exit)
  ToolbarButton(1)
  Init()
  CheckInstrumentTracks()
else
  ToolbarButton(0)
end
