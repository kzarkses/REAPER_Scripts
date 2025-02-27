State = {}

local r = reaper

State.settings = {
    cell_width = 120,
    cell_height = 80,
    grid_spacing = 4,
    toolbar_height = 30,
    show_toolbar = true,
    show_inactive_clips = true,
    auto_scroll = true,
    quantize_enabled = false,
    quantize_value = 4,
    follow_transport = true,
    playing_clips = {},
    queued_clips = {},
    selected_scene = -1,
    global_lanes = 8,
    last_known_play_state = 0,
    last_known_position = 0
}

function State.Init()
    State.LoadSettings()
    State.InitializePlaybackStates()
end

function State.LoadSettings()
    for key, default in pairs(State.settings) do
        local saved = r.GetExtState("SessionView", key)
        if saved ~= "" then
            if type(default) == "boolean" then
                State.settings[key] = saved == "true"
            elseif type(default) == "number" then
                State.settings[key] = tonumber(saved)
            else
                State.settings[key] = saved
            end
        end
    end
end

function State.Save()
    for key, value in pairs(State.settings) do
        r.SetExtState("SessionView", key, tostring(value), true)
    end
end

function State.InitializePlaybackStates()
    State.settings.playing_clips = {}
    State.settings.queued_clips = {}
    State.settings.last_known_play_state = r.GetPlayState()
    State.settings.last_known_position = r.GetPlayPosition()
end

function State.AddPlayingClip(clip_id, trigger_time)
    State.settings.playing_clips[clip_id] = trigger_time
end

function State.RemovePlayingClip(clip_id)
    State.settings.playing_clips[clip_id] = nil
end

function State.QueueClip(clip_id, trigger_time)
    State.settings.queued_clips[clip_id] = trigger_time
end

function State.IsClipPlaying(clip_id)
    return State.settings.playing_clips[clip_id] ~= nil
end

function State.IsClipQueued(clip_id)
    return State.settings.queued_clips[clip_id] ~= nil
end

function State.GetClipTriggerTime(clip_id)
    return State.settings.playing_clips[clip_id] or State.settings.queued_clips[clip_id]
end

return State