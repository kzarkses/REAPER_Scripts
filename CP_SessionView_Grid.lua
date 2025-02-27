Grid = {}
local r = reaper

Grid.data = {
    tracks = {},
    max_lanes = 0,
    scenes = {}
}

function Grid.Init()
    Grid.Update()
end

function Grid.GetTrackInfo(track)
    local retval, name = r.GetTrackName(track)
    local color = r.GetTrackColor(track)
    local items = Grid.GetTrackItems(track)
    local max_lane = 0
    
    for lane, _ in pairs(items) do
        max_lane = math.max(max_lane, lane)
    end
    
    return {
        track = track,
        name = name,
        color = color ~= 0 and color or 0x808080,
        items = items,
        max_lane = max_lane,
        mute = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1,
        solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0,
        volume = r.GetMediaTrackInfo_Value(track, "D_VOL"),
        pan = r.GetMediaTrackInfo_Value(track, "D_PAN")
    }
end

function Grid.GetTrackItems(track)
    local items = {}
    local item_count = r.CountTrackMediaItems(track)
    
    for i = 0, item_count - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take then
            local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            local lane = r.GetMediaItemInfo_Value(item, "I_LANE")
            
            items[lane + 1] = items[lane + 1] or {}
            table.insert(items[lane + 1], {
                item = item,
                take = take,
                guid = r.BR_GetMediaItemGUID(item),
                name = name ~= "" and name or "(unnamed)",
                pos = pos,
                length = length,
                is_playing = State.IsClipPlaying(item),
                is_queued = State.IsClipQueued(item),
                trigger_time = State.GetClipTriggerTime(item),
                color = r.GetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR")
            })
        end
    end
    return items
end

function Grid.Update()
    local tracks = {}
    local max_lanes = 0
    
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        local track_info = Grid.GetTrackInfo(track)
        max_lanes = math.max(max_lanes, track_info.max_lane)
        table.insert(tracks, track_info)
    end
    
    Grid.data.tracks = tracks
    Grid.data.max_lanes = max_lanes
    Grid.UpdateScenes()
end

function Grid.UpdateScenes()
    local scenes = {}
    
    for lane = 1, Grid.data.max_lanes do
        local scene = {}
        for _, track in ipairs(Grid.data.tracks) do
            if track.items[lane] then
                for _, clip in ipairs(track.items[lane]) do
                    table.insert(scene, clip)
                end
            end
        end
        if #scene > 0 then
            table.insert(scenes, scene)
        end
    end
    
    Grid.data.scenes = scenes
end

function Grid.GetData()
    return Grid.data
end

function Grid.GetScene(index)
    return Grid.data.scenes[index]
end

function Grid.GetTrackAtIndex(index)
    return Grid.data.tracks[index]
end

function Grid.GetClipByGUID(guid)
    for _, track in ipairs(Grid.data.tracks) do
        for _, clips in pairs(track.items) do
            for _, clip in ipairs(clips) do
                if clip.guid == guid then
                    return clip
                end
            end
        end
    end
    return nil
end

return Grid