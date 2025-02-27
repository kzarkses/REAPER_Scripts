-- Configuration
local ZOOM_LEVEL = 150 -- MIDI Editor vertical zoom level (1-1000)
local MIN_VISIBLE_NOTES = 12 -- Minimum number of notes visible vertically

-- State tracking
local last_selected_item_guid = nil

function IsItemMIDI(item)
    if not item then return false end
    local take = reaper.GetActiveTake(item)
    return take and reaper.TakeIsMIDI(take)
end

function GetMIDIEditor()
    return reaper.MIDIEditor_GetActive()
end

function GetSelectedItemGUID()
    local item = reaper.GetSelectedMediaItem(0, 0)
    if not item then return nil end
    return reaper.BR_GetMediaItemGUID(item)
end

function ZoomToMIDIContent()
    local current_guid = GetSelectedItemGUID()
    if not current_guid or current_guid == last_selected_item_guid then return end
    last_selected_item_guid = current_guid
    
    local item = reaper.GetSelectedMediaItem(0, 0)
    if not IsItemMIDI(item) then return end
    
    local take = reaper.GetActiveTake(item)
    local editor = GetMIDIEditor()
    if not editor then return end
    
    -- Get MIDI content bounds
    local _, notes = reaper.MIDI_CountEvts(take)
    local min_pitch, max_pitch = 127, 0
    
    for i = 0, notes - 1 do
        local _, _, _, _, _, _, pitch = reaper.MIDI_GetNote(take, i)
        min_pitch = math.min(min_pitch, pitch)
        max_pitch = math.max(max_pitch, pitch)
    end
    
    -- If no notes found, stop here
    if min_pitch == 127 or max_pitch == 0 then return end
    
    -- Ensure minimum visible range
    local pitch_range = max_pitch - min_pitch + 1
    if pitch_range < MIN_VISIBLE_NOTES then
        local extra = (MIN_VISIBLE_NOTES - pitch_range) / 2
        min_pitch = math.max(0, min_pitch - extra)
        max_pitch = math.min(127, max_pitch + extra)
    end
    
    -- First, zoom vertically to fixed level
    reaper.MIDIEditor_SetSetting_int(editor, "vertZoom", ZOOM_LEVEL)
    
    -- Then, set view to center on content
    local center_pitch = (min_pitch + max_pitch) / 2
    reaper.MIDIEditor_SetSetting_int(editor, "active_note_row", math.floor(center_pitch))
    
    -- Finally, ensure time is zoomed appropriately
    reaper.MIDIEditor_OnCommand(editor, 40466) -- Zoom horizontally to content
end

function Main()
    ZoomToMIDIContent()
    reaper.defer(Main)
end

function Exit()
    local _, _, sectionID, cmdID = reaper.get_action_context()
    reaper.SetToggleCommandState(sectionID, cmdID, 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
end

function Init()
    if not reaper.APIExists('JS_Window_GetClientSize') then
        reaper.ShowMessageBox('This script requires js_ReaScriptAPI extension', 'Error', 0)
        return false
    end
    return true
end

function ToggleScript()
    local _, _, sectionID, cmdID = reaper.get_action_context()
    local state = reaper.GetToggleCommandState(cmdID)
    
    if state == -1 or state == 0 then
        reaper.SetToggleCommandState(sectionID, cmdID, 1)
        reaper.RefreshToolbar2(sectionID, cmdID)
        Main()
    else
        reaper.SetToggleCommandState(sectionID, cmdID, 0)
        reaper.RefreshToolbar2(sectionID, cmdID)
    end
end

reaper.atexit(Exit)
ToggleScript()
