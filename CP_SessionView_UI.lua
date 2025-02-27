UI = {}
local r = reaper

function UI.Init(ctx)
    UI.fonts = {
        normal = r.ImGui_CreateFont('sans-serif', 13),
        large = r.ImGui_CreateFont('sans-serif', 16),
        small = r.ImGui_CreateFont('sans-serif', 11)
    }
    
    for _, font in pairs(UI.fonts) do
        r.ImGui_Attach(ctx, font)
    end
end

function UI.DrawToolbar(ctx)
    if not State.settings.show_toolbar then return end
    
    local height = State.settings.toolbar_height
    
    r.ImGui_PushFont(ctx, UI.fonts.normal)
    if r.ImGui_Button(ctx, State.settings.quantize_enabled and "Quantize: On" or "Quantize: Off") then
        State.settings.quantize_enabled = not State.settings.quantize_enabled
    end
    
    r.ImGui_SameLine(ctx)
    if State.settings.quantize_enabled then
        local changed, value = r.ImGui_SliderInt(ctx, "##quantize", State.settings.quantize_value, 1, 16, "%d beats")
        if changed then State.settings.quantize_value = value end
    end
    
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Stop All") then
        Transport.StopAllClips()
    end
    
    r.ImGui_PopFont(ctx)
    r.ImGui_Separator(ctx)
end

function UI.DrawTrackHeader(ctx, track)
    r.ImGui_PushFont(ctx, UI.fonts.normal)
    local r_val = ((track.color >> 16) & 0xFF) / 255
    local g_val = ((track.color >> 8) & 0xFF) / 255
    local b_val = (track.color & 0xFF) / 255
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), r.ImGui_ColorConvertDouble4ToU32(r_val, g_val, b_val, 1))
    r.ImGui_Text(ctx, track.name)
    r.ImGui_PopStyleColor(ctx)
    
    r.ImGui_PushItemWidth(ctx, State.settings.cell_width - 10)
    local vol_changed, new_vol = r.ImGui_SliderDouble(ctx, "##vol"..track.name, track.volume, 0, 2, "Vol: %.2f")
    if vol_changed then
        r.SetMediaTrackInfo_Value(track.track, "D_VOL", new_vol)
    end
    
    local pan_changed, new_pan = r.ImGui_SliderDouble(ctx, "##pan"..track.name, track.pan, -1, 1, "Pan: %.2f")
    if pan_changed then
        r.SetMediaTrackInfo_Value(track.track, "D_PAN", new_pan)
    end
    r.ImGui_PopItemWidth(ctx)
    
    r.ImGui_PopFont(ctx)
end

function UI.DrawClip(ctx, clip, track_color)
    local r_val = ((track_color >> 16) & 0xFF) / 255
    local g_val = ((track_color >> 8) & 0xFF) / 255
    local b_val = (track_color & 0xFF) / 255
    local alpha = clip.is_playing and 1.0 or (clip.is_queued and 0.8 or 0.6)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), r.ImGui_ColorConvertDouble4ToU32(r_val, g_val, b_val, alpha))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), r.ImGui_ColorConvertDouble4ToU32(r_val * 1.2, g_val * 1.2, b_val * 1.2, alpha))
    
    local clip_id = "##" .. clip.guid
    if r.ImGui_Button(ctx, clip_id, State.settings.cell_width - 4, State.settings.cell_height - 4) then
        if clip.is_playing then
            Transport.StopClip(clip)
        else
            Transport.TriggerClip(clip)
        end
    end
    
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_Text(ctx, clip.name)
        r.ImGui_Text(ctx, string.format("Length: %.2fs", clip.length))
        r.ImGui_EndTooltip(ctx)
    end
    
    local text_size = r.ImGui_CalcTextSize(ctx, clip.name)
    local pos = r.ImGui_GetItemRectMin(ctx)
    local text_pos_x = pos[1] + (State.settings.cell_width - 4 - text_size) / 2
    local text_pos_y = pos[2] + (State.settings.cell_height - 4 - r.ImGui_GetTextLineHeight(ctx)) / 2
    
    r.ImGui_SetCursorPos(ctx, text_pos_x, text_pos_y)
    r.ImGui_Text(ctx, clip.name)
    
    r.ImGui_PopStyleColor(ctx, 2)
end

function UI.DrawSceneButton(ctx, scene_index)
    r.ImGui_PushFont(ctx, UI.fonts.small)
    
    local is_playing = false
    for _, clip in ipairs(Grid.GetScene(scene_index)) do
        if clip.is_playing then
            is_playing = true
            break
        end
    end
    
    local label = string.format("Scene %d%s", scene_index, is_playing and " ■" or "")
    if r.ImGui_Button(ctx, label, State.settings.cell_width - 4, 20) then
        if is_playing then
            Transport.StopScene(scene_index)
        else
            Transport.PlayScene(scene_index)
        end
    end
    
    r.ImGui_PopFont(ctx)
end

function UI.DrawGrid(ctx, grid_data)
    r.ImGui_BeginChild(ctx, "grid_view")
    
    for _, track in ipairs(grid_data.tracks) do
        r.ImGui_BeginGroup(ctx)
        UI.DrawTrackHeader(ctx, track)
        
        UI.DrawSceneButton(ctx, 1)
        for lane = 1, grid_data.max_lanes do
            local clips = track.items[lane] or {}
            for _, clip in ipairs(clips) do
                UI.DrawClip(ctx, clip, track.color)
            end
            r.ImGui_Dummy(ctx, 0, State.settings.grid_spacing)
        end
        
        r.ImGui_EndGroup(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_Dummy(ctx, State.settings.grid_spacing, 0)
        r.ImGui_SameLine(ctx)
    end
    
    r.ImGui_EndChild(ctx)
end

return UI