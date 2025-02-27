local r = reaper

local ctx = r.ImGui_CreateContext('Session View')
local WINDOW_FLAGS = r.ImGui_WindowFlags_NoCollapse()

local cell_w = 120
local cell_h = 80
local grid_data = {}
local playing_clips = {}
local max_lanes = 0
local selected_scene = -1
local current_time = 0
local is_playing = false
local grid_scroll_y = 0

local config = {
    quantize = 1,
    auto_scene_launch = false,
    follow_playback = true,
    show_grid = true,
    scene_names = {},
    track_heights = {},
    show_meters = true,
    global_quantize = 4
}

function GetTimeSignature()
    local retval, measures, cml, fullbeats, cdenom = r.TimeMap_GetTimeSigAtTime(0, 0)
    return {
        num = fullbeats,
        denom = cdenom
    }
end

function QuantizePosition(pos)
    if config.global_quantize <= 0 then return pos end
    local ts = GetTimeSignature()
    local tempo = r.Master_GetTempo()
    local beats_per_second = tempo / 60
    local beat_length = 1 / beats_per_second
    local bar_length = beat_length * ts.num
    local quantum = bar_length / config.global_quantize
    
    return math.ceil(pos / quantum) * quantum
end

function GetAllTracks()
    local tracks = {}
    local count = r.CountTracks(0)
    for i = 0, count - 1 do
        local track = r.GetTrack(0, i)
        local _, name = r.GetTrackName(track)
        local color = r.GetTrackColor(track)
        local volume = r.GetMediaTrackInfo_Value(track, "D_VOL")
        local pan = r.GetMediaTrackInfo_Value(track, "D_PAN")
        local mute = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
        local solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0
        
        table.insert(tracks, {
            track = track,
            name = name,
            color = color,
            items = {},
            volume = volume,
            pan = pan,
            mute = mute,
            solo = solo,
            peak_l = 0,
            peak_r = 0
        })
    end
    return tracks
end

function GetTrackItems(track_info)
    local items = {}
    local track = track_info.track
    local item_count = r.CountTrackMediaItems(track)
    
    for i = 0, item_count - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take then
            local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            local lane = r.GetMediaItemInfo_Value(item, "I_LANE")
            local color = r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
            
            max_lanes = math.max(max_lanes, lane + 1)
            items[lane + 1] = items[lane + 1] or {}
            table.insert(items[lane + 1], {
                item = item,
                name = name ~= "" and name or "(unnamed)",
                pos = pos,
                length = length,
                playing = false,
                color = color,
                queued = false
            })
        end
    end
    return items
end

function GetPlaybackPosition()
    local play_state = r.GetPlayState()
    if play_state == 0 then return -1 end
    return r.GetPlayPosition()
end

function UpdateGridData()
    grid_data = GetAllTracks()
    for _, track in ipairs(grid_data) do
        track.items = GetTrackItems(track)
        
        local peaks = {0, 0}
        if config.show_meters then
            r.Track_GetPeaks(track.track, 2, peaks, 2)
            track.peak_l = peaks[1]
            track.peak_r = peaks[2]
        end
    end
    
    current_time = GetPlaybackPosition()
    is_playing = r.GetPlayState() > 0
end

function DrawClipContent(clip, playing, w, h)
    if not clip.waveform_points then
        local take = r.GetActiveTake(clip.item)
        if take then
            local source = r.GetMediaItemTake_Source(take)
            if source then
                local peaks = {}
                local samples_per_pixel = math.floor(r.GetMediaSourceLength(source) / w * r.GetMediaSourceSampleRate(source))
                local num_points = w
                r.GetMediaSourceSamplesPeak(source, samples_per_pixel, 0, num_points, peaks)
                
                clip.waveform_points = {}
                for i = 1, #peaks, 2 do
                    table.insert(clip.waveform_points, peaks[i])
                end
            end
        end
    end
    
    if clip.waveform_points then
        local prev_x, prev_y = 0, h/2
        for i, peak in ipairs(clip.waveform_points) do
            local x = (i-1) * w / #clip.waveform_points
            local y = h/2 - peak * h/2
            r.ImGui_DrawLine(ctx, prev_x, prev_y, x, y, 0x80FFFFFF)
            prev_x, prev_y = x, y
        end
    end
end

function DrawLevelMeter(peak_l, peak_r, w, h)
    local db_l = 20 * math.log(peak_l, 10)
    local db_r = 20 * math.log(peak_r, 10)
    local normalized_l = math.max(0, math.min(1, (db_l + 60) / 60))
    local normalized_r = math.max(0, math.min(1, (db_r + 60) / 60))
    
    local meter_h = h / 2 - 2
    local meter_w = 4
    
    r.ImGui_DrawRectFilled(ctx, 0, 0, meter_w, meter_h * (1-normalized_l), 0xFF333333)
    r.ImGui_DrawRectFilled(ctx, 0, meter_h * (1-normalized_l), meter_w, meter_h, 0xFF00FF00)
    
    r.ImGui_DrawRectFilled(ctx, 0, meter_h + 2, meter_w, meter_h + 2 + meter_h * (1-normalized_r), 0xFF333333)
    r.ImGui_DrawRectFilled(ctx, 0, meter_h + 2 + meter_h * (1-normalized_r), meter_w, h, 0xFF00FF00)
end

function DrawTrackControls(track)
    local ctrl_w = 80
    r.ImGui_PushItemWidth(ctx, ctrl_w)
    
    local vol_changed, new_vol = r.ImGui_SliderFloat(ctx, "##vol"..track.name, 20*math.log(track.volume, 10), -60, 12, "%.1f dB")
    if vol_changed then
        track.volume = math.pow(10, new_vol/20)
        r.SetMediaTrackInfo_Value(track.track, "D_VOL", track.volume)
    end
    
    local pan_changed, new_pan = r.ImGui_SliderFloat(ctx, "##pan"..track.name, track.pan*100, -100, 100, "%.0f%%")
    if pan_changed then
        track.pan = new_pan/100
        r.SetMediaTrackInfo_Value(track.track, "D_PAN", track.pan)
    end
    
    if r.ImGui_Button(ctx, track.mute and "M!" or "M", 20, 20) then
        track.mute = not track.mute
        r.SetMediaTrackInfo_Value(track.track, "B_MUTE", track.mute and 1 or 0)
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, track.solo and "S!" or "S", 20, 20) then
        track.solo = not track.solo
        r.SetMediaTrackInfo_Value(track.track, "I_SOLO", track.solo and 1 or 0)
    end
    
    if config.show_meters then
        r.ImGui_SameLine(ctx)
        local draw_list = r.ImGui_GetWindowDrawList(ctx)
        local screen_x, screen_y = r.ImGui_GetCursorScreenPos(ctx)
        DrawLevelMeter(track.peak_l, track.peak_r, 4, 60)
    end
    
    r.ImGui_PopItemWidth(ctx)
end

function DrawSceneControls()
    if selected_scene >= 0 and selected_scene <= max_lanes then
        if r.ImGui_Button(ctx, "Launch Scene " .. selected_scene, 120, 30) then
            LaunchScene(selected_scene)
        end
        r.ImGui_SameLine(ctx)
    end
    
    local quant_changed, new_quant = r.ImGui_SliderInt(ctx, "Quantize", config.global_quantize, 0, 16, config.global_quantize == 0 and "Off" or "%d")
    if quant_changed then 
        config.global_quantize = new_quant
    end
    
    r.ImGui_SameLine(ctx)
    local follow_changed
    follow_changed, config.follow_playback = r.ImGui_Checkbox(ctx, "Follow", config.follow_playback)
    
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Stop All", 80, 30) then
        StopAllClips()
    end
end

function DrawClip(clip, track_color)
    local r_val = ((track_color >> 16) & 0xFF) / 255
    local g_val = ((track_color >> 8) & 0xFF) / 255
    local b_val = (track_color & 0xFF) / 255
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), clip.playing and 0xFF00FF00 or r.ImGui_ColorConvertDouble4ToU32(r_val, g_val, b_val, 0.8))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), r.ImGui_ColorConvertDouble4ToU32(r_val * 1.2, g_val * 1.2, b_val * 1.2, 0.9))
    
    if r.ImGui_Button(ctx, "##" .. clip.name, cell_w - 4, cell_h - 20) then
        clip.playing = not clip.playing
        if clip.playing then
            local pos = config.global_quantize > 0 and QuantizePosition(current_time) or clip.pos
            r.SetMediaItemInfo_Value(clip.item, "D_POSITION", pos)
            r.SetMediaItemSelected(clip.item, true)
            r.SetEditCurPos(pos, false, false)
            if not is_playing then
                r.Main_OnCommand(1007, 0)
            end
            playing_clips[clip.item] = true
        else
            r.SetMediaItemSelected(clip.item, false)
            playing_clips[clip.item] = nil
            if next(playing_clips) == nil then
                r.Main_OnCommand(1016, 0)
            end
        end
    end
    
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_Text(ctx, clip.name)
        r.ImGui_Text(ctx, string.format("Length: %.2fs", clip.length))
        r.ImGui_EndTooltip(ctx)
    end
    
    DrawClipContent(clip, clip.playing, cell_w - 4, cell_h - 20)
    
    r.ImGui_Text(ctx, clip.name)
    r.ImGui_PopStyleColor(ctx, 2)
end

function LaunchScene(scene_index)
    for _, track in ipairs(grid_data) do
        local clips = track.items[scene_index] or {}
        for _, clip in ipairs(clips) do
                DrawClip(clip, track.color ~= 0 and track.color or 0x808080)
            end
            r.ImGui_EndGroup(ctx)
            r.ImGui_SameLine(ctx)
        end
        r.ImGui_NewLine(ctx)
        
        if not hovering_scene then
            if r.ImGui_IsMouseHoveringRect(ctx, r.ImGui_GetItemRectMin(ctx), r.ImGui_GetItemRectMax(ctx)) then
                selected_scene = lane + 1
            end
        end
    end
    
    r.ImGui_EndChild(ctx)
end

function SaveConfig()
    local state = {
        quantize = config.quantize,
        auto_scene_launch = config.auto_scene_launch,
        follow_playback = config.follow_playback,
        show_grid = config.show_grid,
        scene_names = config.scene_names,
        track_heights = config.track_heights,
        show_meters = config.show_meters,
        global_quantize = config.global_quantize
    }
    
    local json = r.format_json(state)
    r.SetExtState("SessionView", "Config", json, true)
end

function LoadConfig()
    local json = r.GetExtState("SessionView", "Config")
    if json ~= "" then
        local state = r.parse_json(json)
        if state then
            for k, v in pairs(state) do
                config[k] = v
            end
        end
    end
end

function DrawTransportInfo()
    local time_str = r.format_timestr_pos(current_time, "", 4)
    local tempo = r.Master_GetTempo()
    local ts = GetTimeSignature()
    
    r.ImGui_Text(ctx, string.format("Time: %s | Tempo: %.1f | Time Sig: %d/%d", 
        time_str, tempo, ts.num, ts.denom))
end

function DrawToolbar()
    if r.ImGui_BeginMenuBar(ctx) then
        if r.ImGui_BeginMenu(ctx, "View") then
            local show_changed
            show_changed, config.show_meters = r.ImGui_MenuItem(ctx, "Show Meters", nil, config.show_meters)
            show_changed, config.show_grid = r.ImGui_MenuItem(ctx, "Show Grid", nil, config.show_grid)
            
            if show_changed then
                SaveConfig()
            end
            r.ImGui_EndMenu(ctx)
        end
        r.ImGui_EndMenuBar(ctx)
    end
end

function Loop()
    UpdateGridData()
    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 8, 8)
    local visible, open = r.ImGui_Begin(ctx, 'Session View', true, 
        WINDOW_FLAGS | r.ImGui_WindowFlags_MenuBar())
        
    if visible then
        DrawToolbar()
        DrawSceneControls()
        r.ImGui_Separator(ctx)
        DrawTransportInfo()
        r.ImGui_Separator(ctx)
        
        if config.show_grid then
            DrawGrid()
        end
        
        r.ImGui_End(ctx)
    end
    
    r.ImGui_PopStyleVar(ctx)
    
    if config.follow_playback and is_playing then
        r.ImGui_SetScrollY(ctx, current_time * cell_h)
    end
    
    if open then
        r.defer(Loop)
    end
end

function Init()
    LoadConfig()
    UpdateGridData()
    Loop()
end

function Exit()
    SaveConfig()
    local _, _, sectionID, cmdID = r.get_action_context()
    r.SetToggleCommandState(sectionID, cmdID, 0)
    r.RefreshToolbar2(sectionID, cmdID)
end

function ToggleScript()
    local _, _, sectionID, cmdID = r.get_action_context()
    local state = r.GetToggleCommandState(cmdID)
    
    if state == -1 or state == 0 then
        r.SetToggleCommandState(sectionID, cmdID, 1)
        r.RefreshToolbar2(sectionID, cmdID)
        Init()
    else
        r.SetToggleCommandState(sectionID, cmdID, 0)
        r.RefreshToolbar2(sectionID, cmdID)
    end
end

r.atexit(Exit)
