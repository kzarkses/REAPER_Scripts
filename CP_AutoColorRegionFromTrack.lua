-- Configuration
local CONFIG = {
    BACKGROUND_MODE = true,   
    REFRESH_INTERVAL = 1.0,    
    FORCE_REFRESH = false      
}

-- Variables globales pour le tracking des changements
local last_refresh_time = 0
local last_track_count = 0
local lastTrackColors = {}
local lastTrackParents = {}
local lastRegionStates = {}
local lastRegionNames = {}

-- Fonction pour obtenir toutes les régions dans l'ordre
function getAllRegions()
    local regions = {}
    local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
    
    for i = 0, num_markers + num_regions - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = reaper.EnumProjectMarkers3(0, i)
        if retval and isrgn and name then
            table.insert(regions, {
                name = name,
                start = pos,
                ending = rgnend,
                index = markrgnindexnumber,
                color = color,
                originalName = name -- Conserver le nom original
            })
        end
    end
    
    -- Trier les régions par position de début
    table.sort(regions, function(a, b) 
        if a.start == b.start then
            return (a.ending - a.start) > (b.ending - b.start)
        end
        return a.start < b.start
    end)
    
    return regions
end

-- Fonction pour vérifier si une région en contient une autre
function containsRegion(parent, child)
    -- Une région en contient une autre si elle commence avant (ou en même temps)
    -- et finit après
    return parent.start <= child.start and parent.ending >= child.ending
end

-- Fonction pour construire l'arborescence des régions
function buildRegionHierarchy(regions)
    local hierarchy = {}
    
    -- Pour chaque région, trouver son parent le plus immédiat
    for i, region in ipairs(regions) do
        local path = {region.name}
        local currentRegion = region
        
        -- Rechercher en arrière pour trouver les parents
        for j = i - 1, 1, -1 do
            local potentialParent = regions[j]
            if containsRegion(potentialParent, currentRegion) then
                table.insert(path, 1, potentialParent.name)
                currentRegion = potentialParent
            end
        end
        
        hierarchy[region.index] = {
            path = path,
            region = region
        }
    end
    
    return hierarchy
end

-- Fonction pour obtenir le chemin complet d'une piste
function getTrackFullPath(track)
    if not track then return {} end
    
    local path = {}
    local current = track
    while current do
        local _, name = reaper.GetTrackName(current)
        if name then
            table.insert(path, 1, {track = current, name = name})
        end
        current = reaper.GetParentTrack(current)
    end
    return path
end

-- Fonction pour trouver la piste correspondante à une région
function findMatchingTrack(regionPath)
    if not regionPath or #regionPath == 0 then return nil end
    
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local trackPath = getTrackFullPath(track)
            
            -- Vérifier si les chemins correspondent
            local match = true
            if #regionPath <= #trackPath then
                for j = 1, #regionPath do
                    if regionPath[j] ~= trackPath[j].name then
                        match = false
                        break
                    end
                end
                
                if match then
                    return trackPath[#regionPath].track
                end
            end
        end
    end
    
    return nil
end

-- Fonction pour mettre à jour les noms et couleurs des régions
function updateRegions()
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    
    local regions = getAllRegions()
    local hierarchy = buildRegionHierarchy(regions)
    
    for index, hierData in pairs(hierarchy) do
        local region = hierData.region
        local baseName = string.match(region.name, "([^/]+)$") or region.name
        
        local matching_track = findMatchingTrack(hierData.path)
        if matching_track then
            local track_color = reaper.GetTrackColor(matching_track)
            
            -- Force region marker to update by first deleting then recreating
            reaper.DeleteProjectMarker(0, index, true)
            reaper.AddProjectMarker2(0, true, region.start, region.ending, baseName, index, track_color)
        end
    end
    
    reaper.Undo_EndBlock("Update Region Names and Colors", -1)
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

-- Initialize lastRegionStates au démarrage
if not lastRegionStates then
    lastRegionStates = {}
end

-- Fonction pour détecter les changements
function detectChanges()
    local changes_detected = false
    
    -- Détecter immédiatement les changements de structure de pistes et de couleurs
    local current_track_count = reaper.CountTracks(0)
    if current_track_count ~= last_track_count then
        last_track_count = current_track_count
        changes_detected = true
    end
    
    -- Vérifier les changements de pistes et leurs couleurs - toujours immédiat
    for i = 0, current_track_count - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local guid = reaper.GetTrackGUID(track)
            local currentColor = reaper.GetTrackColor(track)
            
            if lastTrackColors[guid] ~= currentColor then
                changes_detected = true
                lastTrackColors[guid] = currentColor
            end
            
            -- Vérifier les changements de parenting
            local parent = reaper.GetParentTrack(track)
            local parent_guid = parent and reaper.GetTrackGUID(parent) or "none"
            if lastTrackParents[guid] ~= parent_guid then
                changes_detected = true
                lastTrackParents[guid] = parent_guid
            end
        end
    end

    -- Pour les régions, vérifier seulement si la souris n'est pas enfoncée
    local mouse_state = reaper.JS_Mouse_GetState(1)
    local is_mouse_down = (mouse_state & 1) == 1
    
    if not is_mouse_down then
        local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
        local total = num_markers + num_regions
        
        if not lastRegionStates then
            lastRegionStates = {}
            changes_detected = true
        end
        
        for i = 0, total - 1 do
            local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = reaper.EnumProjectMarkers3(0, i)
            if retval and isrgn then
                if not lastRegionStates[markrgnindexnumber] then
                    lastRegionStates[markrgnindexnumber] = {
                        pos = pos,
                        rgnend = rgnend,
                        name = name,
                        color = color
                    }
                    changes_detected = true
                else
                    local state = lastRegionStates[markrgnindexnumber]
                    if state.pos ~= pos or 
                       state.rgnend ~= rgnend or 
                       state.name ~= name or 
                       state.color ~= color then
                        
                        state.pos = pos
                        state.rgnend = rgnend
                        state.name = name
                        state.color = color
                        changes_detected = true
                    end
                end
            end
        end
        
        -- Nettoyer les régions supprimées
        local currentRegions = {}
        for i = 0, total - 1 do
            local _, isrgn, _, _, _, markrgnindexnumber = reaper.EnumProjectMarkers3(0, i)
            if isrgn then
                currentRegions[markrgnindexnumber] = true
            end
        end
        
        for index in pairs(lastRegionStates) do
            if not currentRegions[index] then
                lastRegionStates[index] = nil
                changes_detected = true
            end
        end
    end
    
    return changes_detected
end

-- Fonction principale de vérification
function checkAndUpdateRegions()
    local current_time = reaper.time_precise()
    local should_update = false
    
    if CONFIG.FORCE_REFRESH then
        -- Mode refresh forcé par intervalle
        if current_time - last_refresh_time >= CONFIG.REFRESH_INTERVAL then
            should_update = true
            last_refresh_time = current_time
        end
    else
        -- Mode détection des changements
        should_update = detectChanges()
    end
    
    if should_update then
        updateRegions()
    end
    
    if CONFIG.BACKGROUND_MODE then
        reaper.defer(checkAndUpdateRegions)
    end
end

-- Fonction pour réinitialiser tous les états
function resetAllStates()
    lastTrackColors = {}
    lastTrackParents = {}
    lastRegionStates = {}
    lastRegionNames = {}
    last_track_count = 0
    last_refresh_time = 0
end

-- Fonction d'initialisation
function InitializeTracking()
    last_track_count = reaper.CountTracks(0)
    lastTrackColors = {}
    lastTrackParents = {}
    lastRegionStates = {}
    lastRegionNames = {}
    
    -- Initialiser le suivi des pistes
    for i = 0, last_track_count - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local guid = reaper.GetTrackGUID(track)
            local parent = reaper.GetParentTrack(track)
            lastTrackParents[guid] = parent and reaper.GetTrackGUID(parent) or "none"
            lastTrackColors[guid] = reaper.GetTrackColor(track)
        end
    end
    
    -- Initialiser le suivi des régions
    local regions = getAllRegions()
    for _, region in ipairs(regions) do
        lastRegionStates[region.index] = {
            pos = region.start,
            ending = region.ending,
            name = region.name,
            color = region.color
        }
        lastRegionNames[region.index] = region.name
    end
end

-- Point d'entrée du script
function main()
    InitializeTracking()
    if CONFIG.BACKGROUND_MODE then
        last_refresh_time = reaper.time_precise()
        checkAndUpdateRegions()
    else
        updateRegions()
    end
end

function ToggleScript()
    local _, _, sectionID, cmdID = reaper.get_action_context()
    local state = reaper.GetToggleCommandState(cmdID)
    
    if state == -1 or state == 0 then
        reaper.SetToggleCommandState(sectionID, cmdID, 1)
        reaper.RefreshToolbar2(sectionID, cmdID)
        main()
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
