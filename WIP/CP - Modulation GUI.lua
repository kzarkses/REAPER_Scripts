-- @description Modulation GUI with Link FROM/TO parameters
-- @version 1.0
-- @author Claude

local ctx = reaper.ImGui_CreateContext('Modulation Box - GUI')
local WINDOW_FLAGS = reaper.ImGui_WindowFlags_AlwaysAutoResize()

-- Styles and colors
local style = {
    spacing = 8,
    param_width = 200,
    slider_width = 150,
    text_color = reaper.ImGui_ColorConvertDouble4ToU32(0.9, 0.9, 0.9, 1.0),
    header_color = reaper.ImGui_ColorConvertDouble4ToU32(0.7, 0.7, 1.0, 1.0),
    link_color = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.8, 0.2, 1.0),
    warning_color = reaper.ImGui_ColorConvertDouble4ToU32(1.0, 0.3, 0.3, 1.0)
}

-- State management
local state = {
    last_touched = {
        track = nil,
        fx_index = nil,
        param_index = nil,
        timestamp = 0,
        fx_name = "",
        param_name = ""
    },
    links_from = {},
    links_to = {},
    selected_link = nil
}

-- Helper function to get track from GetLastTouchedFX() result
local function getTrackFromResult(track_number)
    if track_number == 0 then
        return reaper.GetMasterTrack(0)
    else
        return reaper.GetTrack(0, track_number - 1)
    end
end

-- Get the last touched FX parameter information
local function getLastTouchedFX()
    local retval, trackidx, itemidx, takeidx, fx_number, param_number = reaper.GetTouchedOrFocusedFX(0)
    if not retval then return nil end
    
    local track = reaper.CSurf_TrackFromID(trackidx + 1, false)
    if not track then return nil end
    
    local _, fx_name = reaper.TrackFX_GetFXName(track, fx_number, "")
    local _, param_name = reaper.TrackFX_GetParamName(track, fx_number, param_number, "")
    local value = reaper.TrackFX_GetParam(track, fx_number, param_number)
    
    -- Check if parameter has active links
    local _, plink_active = reaper.TrackFX_GetNamedConfigParm(track, fx_number, "param." .. param_number .. ".plink.active")
    
    return {
        track = track,
        fx_index = fx_number,
        param_index = param_number,
        fx_name = fx_name or "Unknown FX",
        param_name = param_name or "Unknown Parameter",
        value = string.format("%.3f", value or 0),
        has_link = plink_active == "1",
        timestamp = reaper.time_precise()
    }
end

local function draw_envelope(env_data)
    -- Code pour dessiner une enveloppe
    local title = env_data.name or "Untitled"
    reaper.ImGui_Text(ctx, title)
end

-- Helper function to get parameter links
local function getParameterLinks(track, fx_index, param_index)
    local links_from = {}
    local links_to = {}
    
    if not track or not fx_index or not param_index then
        return links_from, links_to
    end
    
    -- Check links FROM other parameters
    local rv, plink_active = reaper.TrackFX_GetNamedConfigParm(track, fx_index, 
        "param." .. param_index .. ".plink.active")
    
    if plink_active == "1" then
        local _, effect = reaper.TrackFX_GetNamedConfigParm(track, fx_index, 
            "param." .. param_index .. ".plink.effect")
        local _, param = reaper.TrackFX_GetNamedConfigParm(track, fx_index,
            "param." .. param_index .. ".plink.param")
            
        if effect and param then
            local src_fx_idx = tonumber(effect)
            local src_param_idx = tonumber(param)
            
            local _, src_fx_name = reaper.TrackFX_GetFXName(track, src_fx_idx)
            local _, src_param_name = reaper.TrackFX_GetParamName(track, src_fx_idx, src_param_idx)
            
            table.insert(links_from, {
                track = src_track,
                fx_index = tonumber(src_fx_idx),
                param_index = tonumber(src_param_idx),
                fx_name = src_fx_name,
                param_name = src_param_name,
                offset = tonumber(reaper.TrackFX_GetNamedConfigParm(track, fx_index, 
                    "param." .. param_index .. ".plink.offset") or "0"),
                scale = tonumber(reaper.TrackFX_GetNamedConfigParm(track, fx_index,
                    "param." .. param_index .. ".plink.scale") or "1")
            })
        end
    end
    
    -- Check links TO other parameters
    local master_track = reaper.GetMasterTrack(0)
    local track_count = reaper.CountTracks(0)
    local all_tracks = {master_track}
    for i = 0, track_count - 1 do
        table.insert(all_tracks, reaper.GetTrack(0, i))
    end
    
    for _, check_track in ipairs(all_tracks) do
        local fx_count = reaper.TrackFX_GetCount(check_track)
        
        for j = 0, fx_count - 1 do
            local param_count = reaper.TrackFX_GetNumParams(check_track, j)
            
            for k = 0, param_count - 1 do
                local rv, plink_active = reaper.TrackFX_GetNamedConfigParm(check_track, j,
                    "param." .. k .. ".plink.active")
                
                if plink_active == "1" then
                    local _, effect = reaper.TrackFX_GetNamedConfigParm(check_track, j,
                        "param." .. k .. ".plink.effect")
                    local _, param = reaper.TrackFX_GetNamedConfigParm(check_track, j,
                        "param." .. k .. ".plink.param")
                    
                    if effect and param and
                       tonumber(effect) == fx_index and
                       tonumber(param) == param_index then
                        
                        local _, fx_name = reaper.TrackFX_GetFXName(check_track, j)
                        local _, param_name = reaper.TrackFX_GetParamName(check_track, j, k)
                        
                        table.insert(links_to, {
                            track = check_track,
                            fx_index = j,
                            param_index = k,
                            fx_name = fx_name,
                            param_name = param_name,
                            offset = tonumber(reaper.TrackFX_GetNamedConfigParm(check_track, j,
                                "param." .. k .. ".plink.offset") or "0"),
                            scale = tonumber(reaper.TrackFX_GetNamedConfigParm(check_track, j,
                                "param." .. k .. ".plink.scale") or "1")
                        })
                    end
                end
            end
        end
    end
    
    return links_from, links_to
end

-- Function to update link parameters
local function updateLinkParameters(track, fx_index, param_index, offset, scale)
    if not track or not fx_index or not param_index then return end
    
    reaper.TrackFX_SetNamedConfigParm(track, fx_index,
        "param." .. param_index .. ".plink.offset", tostring(offset))
    reaper.TrackFX_SetNamedConfigParm(track, fx_index,
        "param." .. param_index .. ".plink.scale", tostring(scale))
end

-- Main loop function
local function Loop()
    local visible, open = reaper.ImGui_Begin(ctx, 'Modulation Box', true, WINDOW_FLAGS)
    
    if visible then
        local current = getLastTouchedFX()
        
        if current then
            -- Update state if new parameter is touched
            if current.timestamp > state.last_touched.timestamp or
               current.track ~= state.last_touched.track or
               current.fx_index ~= state.last_touched.fx_index or
               current.param_index ~= state.last_touched.param_index then
                
                state.last_touched = current
                state.links_from, state.links_to = getParameterLinks(
                    current.track, 
                    current.fx_index, 
                    current.param_index
                )
                state.selected_link = nil
            end
            
            -- Display current parameter info
            reaper.ImGui_TextColored(ctx, style.header_color, "Current Parameter:")
            reaper.ImGui_Text(ctx, string.format("FX: %s", current.fx_name))
            reaper.ImGui_Text(ctx, string.format("Parameter: %s", current.param_name))
            reaper.ImGui_Text(ctx, string.format("Value: %s", current.value))
            reaper.ImGui_Spacing(ctx)
            
            -- Display links FROM section
            if #state.links_from > 0 then
                reaper.ImGui_TextColored(ctx, style.link_color, "Links FROM:")
                for i, link in ipairs(state.links_from) do
                    if reaper.ImGui_TreeNode(ctx, string.format("%s - %s##from%d", link.fx_name, link.param_name, i)) then
                        local changed = false
                        changed, link.offset = reaper.ImGui_DragDouble(ctx, "Offset##from" .. i, link.offset, 0.01, -1, 1, "%.3f")
                        changed, link.scale = reaper.ImGui_DragDouble(ctx, "Scale##from" .. i, link.scale, 0.01, -1, 1, "%.3f")
                        
                        if changed then
                            updateLinkParameters(current.track, current.fx_index,
                                current.param_index, link.offset, link.scale)
                        end
                        
                        reaper.ImGui_TreePop(ctx)
                    end
                end
                reaper.ImGui_Spacing(ctx)
            end
            
            -- Display links TO section
            if #state.links_to > 0 then
                reaper.ImGui_TextColored(ctx, style.link_color, "Links TO:")
                for i, link in ipairs(state.links_to) do
                    if reaper.ImGui_TreeNode(ctx, string.format("%s - %s##to%d", link.fx_name, link.param_name, i)) then
                        local changed = false
                        changed, link.offset = reaper.ImGui_SliderFloat(ctx,
                            "Offset##to" .. i, link.offset, -1, 1, "%.3f")
                        changed, link.scale = reaper.ImGui_SliderFloat(ctx,
                            "Scale##to" .. i, link.scale, -1, 1, "%.3f")
                        
                        if changed then
                            updateLinkParameters(link.track, link.fx_index,
                                link.param_index, link.offset, link.scale)
                        end
                        
                        reaper.ImGui_TreePop(ctx)
                    end
                end
            end
            
            if #state.links_from == 0 and #state.links_to == 0 then
                reaper.ImGui_TextColored(ctx, style.warning_color, "No parameter links found")
            end
        else
            reaper.ImGui_Text(ctx, "Touch a parameter to see its links")
        end
        
        reaper.ImGui_End(ctx)
    end
    
    if open then
        reaper.defer(Loop)
    end
end

-- Initialize and start the script
function Init()
    reaper.atexit(function()
        reaper.ImGui_DestroyContext(ctx)
    end)
end

Init()
reaper.defer(Loop)