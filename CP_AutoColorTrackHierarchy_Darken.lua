-- Configuration
local CONFIG = {
    FINAL_DARKEN = 0.4,
    FINAL_DESATURATE = 1.0,
    CURVE_POWER = 1.0,
    PROGRESSION_BIAS = 0.0,
    BACKGROUND_MODE = true
}

-- Variables globales
local lastTrackColors = {}
local lastTrackParents = {}
local last_track_count = 0

function isLeafTrack(track)
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        if reaper.GetParentTrack(reaper.GetTrack(0, i)) == track then
            return false
        end
    end
    return true
end

function getLeafDepth(track)
    if not track then return 0 end
    
    local maxDepth = 0
    local track_count = reaper.CountTracks(0)
    
    for i = 0, track_count - 1 do
        local current = reaper.GetTrack(0, i)
        if isLeafTrack(current) then
            local depth = 0
            local parent = current
            while parent do
                if parent == track then
                    maxDepth = math.max(maxDepth, depth)
                    break
                end
                parent = reaper.GetParentTrack(parent)
                depth = depth + 1
            end
        end
    end
    
    return maxDepth
end

function rgbToHsv(r, g, b)
    r, g, b = r/255, g/255, b/255
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local h, s, v
    local d = max - min
    
    v = max
    s = max == 0 and 0 or d/max
    
    if max == min then
        h = 0
    else
        if max == r then
            h = (g - b) / d + (g < b and 6 or 0)
        elseif max == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h/6
    end
    
    return h, s, v
end

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

function darkenColor(r, g, b, amount)
    if r == 0 and g == 0 and b == 0 then return 0, 0, 0 end
    
    if r == g and g == b then
        local value = math.floor(r * (1 - amount))
        return value, value, value
    end
    
    local h, s, v = rgbToHsv(r, g, b)
    v = v * (1 - amount)
    v = math.max(v, 0.05)
    s = s * (1 - amount * CONFIG.FINAL_DESATURATE)
    return hsvToRgb(h, s, v)
end

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

function calculateProgressiveDarken(level, totalLevels)
    if totalLevels <= 1 then return CONFIG.FINAL_DARKEN end
    
    local progress = level / totalLevels
    if CONFIG.PROGRESSION_BIAS ~= 0 then
        if CONFIG.PROGRESSION_BIAS > 0 then
            progress = progress * (1 + CONFIG.PROGRESSION_BIAS * (1 - progress))
        else
            progress = progress * (1 - CONFIG.PROGRESSION_BIAS * progress)
        end
    end
    
    if CONFIG.CURVE_POWER ~= 1 then
        if progress == 0 then return 0 end
        progress = progress^CONFIG.CURVE_POWER
    end
    
    return progress * CONFIG.FINAL_DARKEN
end

function processTrack(track, baseColor, currentLevel, targetLevel)
    if not track then return end
    local trackColor = reaper.GetTrackColor(track)
    
    -- Si le parent est par défaut, tous les enfants restent par défaut
    local parent = reaper.GetParentTrack(track)
    if parent and reaper.GetTrackColor(parent) == 0 then
        return
    end
    
    -- Traiter uniquement si track a une couleur ou si c'est une track racine
    if trackColor ~= 0 then
        local track_count = reaper.CountTracks(0)
        local hasChildren = false
        
        for i = 0, track_count - 1 do
            local child = reaper.GetTrack(0, i)
            if reaper.GetParentTrack(child) == track then
                hasChildren = true
                break
            end
        end
        
        if currentLevel > 0 then
            local amount = hasChildren and calculateProgressiveDarken(currentLevel, targetLevel) or CONFIG.FINAL_DARKEN
            local r, g, b = nativeToRGB(baseColor)
            local newR, newG, newB = darkenColor(r, g, b, amount)
            reaper.SetTrackColor(track, rgbToNative(newR, newG, newB))
        end
        
        -- Traiter les enfants
        for i = 0, track_count - 1 do
            local child = reaper.GetTrack(0, i)
            if reaper.GetParentTrack(child) == track then
                processTrack(child, baseColor, currentLevel + 1, targetLevel)
            end
        end
    end
 end

function updateColors()
    reaper.PreventUIRefresh(1)
    
    -- Pas de Undo_BeginBlock ici
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local color = reaper.GetTrackColor(track)
        
        if not reaper.GetParentTrack(track) and color ~= 0 then
            local leafDepth = getLeafDepth(track)
            if leafDepth > 0 then
                processTrack(track, color, 0, leafDepth)
            end
        end
    end
    
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

function detectChanges()
    local current_track_count = reaper.CountTracks(0)
    
    -- Détecter les nouvelles tracks ou changements de structure
    if current_track_count ~= last_track_count then
        last_track_count = current_track_count
        initializeTracking()
        return true
    end
    
    -- Vérifier les changements de couleur et de parenté
    for i = 0, current_track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local guid = reaper.GetTrackGUID(track)
        local currentColor = reaper.GetTrackColor(track)
        local parent = reaper.GetParentTrack(track)
        local parent_guid = parent and reaper.GetTrackGUID(parent) or "none"
        
        if not lastTrackColors[guid] or 
           lastTrackColors[guid] ~= currentColor or 
           lastTrackParents[guid] ~= parent_guid then
            lastTrackColors[guid] = currentColor
            lastTrackParents[guid] = parent_guid
            return true
        end
    end
    
    return false
 end

function checkAndUpdateColors()
    if detectChanges() then
        updateColors()
    end
    
    if CONFIG.BACKGROUND_MODE then
        reaper.defer(checkAndUpdateColors)
    end
end

function initializeTracking()
    last_track_count = reaper.CountTracks(0)
    
    for i = 0, last_track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local guid = reaper.GetTrackGUID(track)
        local parent = reaper.GetParentTrack(track)
        lastTrackParents[guid] = parent and reaper.GetTrackGUID(parent) or "none"
        lastTrackColors[guid] = reaper.GetTrackColor(track)
    end
end

function Start()
    if CONFIG.BACKGROUND_MODE then
        initializeTracking()
        updateColors()
        checkAndUpdateColors()
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
    end
end

function Exit()
    local _, _, sectionID, cmdID = reaper.get_action_context()
    reaper.SetToggleCommandState(sectionID, cmdID, 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
end

reaper.atexit(Exit)
ToggleScript()
