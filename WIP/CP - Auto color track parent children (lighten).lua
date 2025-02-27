-- Configuration
local CONFIG = {
    LIGHTEN_AMOUNT = 0.85,    -- Pourcentage d'éclaircissement par niveau (0.08 = 8%)
    BACKGROUND_MODE = true,   -- true pour mode tâche de fond, false pour mode manuel
    REFRESH_INTERVAL = 1.0,    -- Intervalle de rafraîchissement en secondes pour FORCE_REFRESH
    FORCE_REFRESH = false      -- Si true, rafraîchit selon l'intervalle défini
}

-- Variables globales
local last_refresh_time = 0
local last_track_count = 0
local lastTrackColors = {}
local lastTrackParents = {}

-- Fonction pour convertir une couleur RGB en HSV
function rgbToHsv(r, g, b)
    r, g, b = r/255, g/255, b/255
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local h, s, v
    local d = max - min

    v = max
    
    if max == 0 then
        s = 0
    else
        s = d/max
    end
    
    if max == min then
        h = 0
    else
        if max == r then
            h = (g - b) / d
            if g < b then h = h + 6 end
        elseif max == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h/6
    end
    
    return h, s, v
end

-- Fonction pour convertir HSV en RGB
function hsvToRgb(h, s, v)
    local r, g, b
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    
    i = i % 6
    
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    elseif i == 5 then r, g, b = v, p, q
    end
    
    return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

-- Fonction pour éclaircir une couleur
function lightenColor(r, g, b, percent)
    local h, s, v = rgbToHsv(r, g, b)
    v = v + (1 - v) * percent
    v = math.min(v, 0.95)
    s = s * (1 - percent * 0.3)
    return hsvToRgb(h, s, v)
end

-- Fonctions de conversion de couleurs
function nativeToRGB(native)
    if native == 0 then return 0, 0, 0 end
    local r = (native & 0xFF0000) >> 16
    local g = (native & 0x00FF00) >> 8
    local b = native & 0x0000FF
    return r, g, b
end

function rgbToNative(r, g, b)
    return (r << 16) | (g << 8) | b
end

-- Fonction pour vérifier les changements de structure
function detectStructureChanges()
    local current_track_count = reaper.CountTracks(0)
    
    -- Vérifier si le nombre de pistes a changé
    if current_track_count ~= last_track_count then
        last_track_count = current_track_count
        return true
    end
    
    -- Vérifier les changements de hiérarchie
    for i = 0, current_track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local guid = reaper.GetTrackGUID(track)
        local parent = reaper.GetParentTrack(track)
        local parent_guid = parent and reaper.GetTrackGUID(parent) or "none"
        
        if lastTrackParents[guid] ~= parent_guid then
            lastTrackParents[guid] = parent_guid
            return true
        end
    end
    
    return false
end

-- Fonction pour vérifier les changements de couleur
function detectColorChanges()
    local changes_detected = false
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local guid = reaper.GetTrackGUID(track)
        local currentColor = reaper.GetTrackColor(track)
        
        if lastTrackColors[guid] ~= currentColor then
            changes_detected = true
            lastTrackColors[guid] = currentColor
        end
    end
    return changes_detected
end

-- Fonction pour mettre à jour toutes les couleurs
function updateAllColors()
    reaper.PreventUIRefresh(1)
    
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        if not reaper.GetParentTrack(track) then
            colorChildTracks(track, 1)
        end
    end
    
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

-- Fonction principale pour colorer les pistes enfants
function colorChildTracks(parentTrack, depth)
    local r, g, b = nativeToRGB(reaper.GetTrackColor(parentTrack))
    local lightenAmount = CONFIG.LIGHTEN_AMOUNT * depth
    
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local parent = reaper.GetParentTrack(track)
        
        if parent == parentTrack then
            local newR, newG, newB = lightenColor(r, g, b, lightenAmount)
            reaper.SetTrackColor(track, rgbToNative(newR, newG, newB))
            colorChildTracks(track, depth + 1)
        end
    end
end

-- Fonction principale de vérification
function checkAndUpdateColors()
    local current_time = reaper.time_precise()
    local should_update = false
    
    if CONFIG.FORCE_REFRESH then
        -- Mode force refresh : utiliser l'intervalle
        if current_time - last_refresh_time >= CONFIG.REFRESH_INTERVAL then
            should_update = true
            last_refresh_time = current_time
        end
    else
        -- Mode réactif : vérifier les changements
        should_update = detectStructureChanges() or detectColorChanges()
    end
    
    if should_update then
        updateAllColors()
    end
    
    if CONFIG.BACKGROUND_MODE then
        reaper.defer(checkAndUpdateColors)
    end
end

-- Fonction d'initialisation
function initializeTracking()
    last_track_count = reaper.CountTracks(0)
    
    -- Initialiser le suivi des parents et des couleurs
    for i = 0, last_track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local guid = reaper.GetTrackGUID(track)
        local parent = reaper.GetParentTrack(track)
        lastTrackParents[guid] = parent and reaper.GetTrackGUID(parent) or "none"
        lastTrackColors[guid] = reaper.GetTrackColor(track)
    end
end

-- Point d'entrée du script
function main()
    if CONFIG.BACKGROUND_MODE then
        last_refresh_time = reaper.time_precise()
        initializeTracking()
        checkAndUpdateColors()
    else
        reaper.Undo_BeginBlock()
        
        for i = 0, reaper.CountSelectedTracks(0) - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            if not reaper.GetParentTrack(track) then
                colorChildTracks(track, 1)
            end
        end
        
        reaper.Undo_EndBlock("Colorer hiérarchiquement les pistes", -1)
        reaper.UpdateArrange()
    end
end

function ToggleScript()
    local _, _, sectionID, cmdID = reaper.get_action_context()
    local state = reaper.GetToggleCommandState(cmdID)
    
    if state == -1 or state == 0 then
        reaper.SetToggleCommandState(sectionID, cmdID, 1)
        reaper.RefreshToolbar2(sectionID, cmdID)
        Start()
    else
        reaper.SetToggleCommandState(sectionID, cmdID, 0)
        reaper.RefreshToolbar2(sectionID, cmdID)
        Stop()
    end
end

function Start()
    if CONFIG.BACKGROUND_MODE then
        last_refresh_time = reaper.time_precise()
        initializeTracking()
        checkAndUpdateColors()
    end
end

function Stop()
    reaper.UpdateArrange()
end

function Exit()
    local _, _, sectionID, cmdID = reaper.get_action_context()
    reaper.SetToggleCommandState(sectionID, cmdID, 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
end

reaper.atexit(Exit)

ToggleScript()
