Transport = {}
local r = reaper

function Transport.Init()
    Transport.stop_all_queued = false
    Transport.next_quantize_time = 0
end

function Transport.Update()
    local play_state = r.GetPlayState()
    local play_position = r.GetPlayPosition()
    
    Transport.UpdateQuantizeTime()
    Transport.CheckQueuedClips()
    Transport.MonitorPlayingClips()
    
    if Transport.stop_all_queued then
        Transport.StopAllClips()
        Transport.stop_all_queued = false
    end
end

function Transport.UpdateQuantizeTime()
    if not State.settings.quantize_enabled then
        Transport.next_quantize_time = 0
        return
    end
    
    local tempo = r.Master_GetTempo()
    local beats_per_second = tempo / 60
    local seconds_per_beat = 1 / beats_per_second
    local quantize_interval = seconds_per_beat * State.settings.quantize_value
    local current_time = r.GetPlayPosition()
    
    Transport.next_quantize_time = math.ceil(current_time / quantize_interval) * quantize_interval
end

function Transport.TriggerClip(clip)
    if State.settings.quantize_enabled then
        Transport.QueueClip(clip)
    else
        Transport.PlayClip(clip)
    end
end

function Transport.QueueClip(clip)
    local trigger_time = Transport.next_quantize_time
    State.QueueClip(clip.item, trigger_time)
end

function Transport.PlayClip(clip)
    local item = clip.item
    local take = clip.take
    local pos = clip.pos
    
    r.SetMediaItemSelected(item, true)
    r.SetEditCurPos(pos, false, false)
    
    if r.GetPlayState() == 0 then
        r.OnPlayButton()
    end
    
    State.AddPlayingClip(item, r.GetPlayPosition())
end

function Transport.StopClip(clip)
    local item = clip.item
    r.SetMediaItemSelected(item, false)
    State.RemovePlayingClip(item)
    
    if not next(State.settings.playing_clips) then
        r.OnStopButton()
    end
end

function Transport.CheckQueuedClips()
    local current_time = r.GetPlayPosition()
    
    for item, trigger_time in pairs(State.settings.queued_clips) do
        if current_time >= trigger_time then
            local clip = Grid.GetClipByGUID(r.GetItemGUID(item))
            if clip then
                Transport.PlayClip(clip)
            end
            State.settings.queued_clips[item] = nil
        end
    end
end

function Transport.MonitorPlayingClips()
    for item in pairs(State.settings.playing_clips) do
        local clip = Grid.GetClipByGUID(r.GetItemGUID(item))
        if clip then
            local current_time = r.GetPlayPosition()
            local end_time = clip.pos + clip.length
            
            if current_time >= end_time then
                Transport.StopClip(clip)
            end
        end
    end
end

function Transport.PlayScene(scene_index)
    local scene = Grid.GetScene(scene_index)
    if scene then
        for _, clip in ipairs(scene) do
            Transport.TriggerClip(clip)
        end
    end
end

function Transport.StopScene(scene_index)
    local scene = Grid.GetScene(scene_index)
    if scene then
        for _, clip in ipairs(scene) do
            Transport.StopClip(clip)
        end
    end
end

function Transport.StopAllClips()
    Transport.stop_all_queued = true
    for item in pairs(State.settings.playing_clips) do
        local clip = Grid.GetClipByGUID(r.GetItemGUID(item))
        if clip then
            Transport.StopClip(clip)
        end
    end
    State.settings.queued_clips = {}
end

return Transport