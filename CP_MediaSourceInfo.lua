-- @description Media Source Information Dock
-- @version 1.6
-- @author Claude
-- @about
--   Displays detailed information about media sources with customization

-- Configuration Variables
local CONFIG = {
    -- Display Options (true to show, false to hide)
    SHOW_FILENAME = true,
    SHOW_LENGTH = false,
    SHOW_SAMPLERATE = false,
    SHOW_CHANNELS = false,
    SHOW_TYPE = false,
    
    -- Styling
    BACKGROUND_COLOR = 0x333333FF,  -- Dark gray background
    TEXT_COLOR = 0xCFCFD0FF,        -- White text
    FONT_SIZE = 16,                 -- Font size in points
    FONT_NAME = "Verdana",            -- Font name
    
    -- Additional Display Options
    SHOW_DISPLAY_TOGGLES = false,    -- Show checkboxes to toggle display
    SHOW_STYLING_OPTIONS = false,    -- Show color and font pickers
    
    -- Labels and Formatting
    LABELS = {
        FILENAME_PREFIX = "",
        LENGTH_PREFIX = "Length: ",
        SAMPLERATE_PREFIX = "Sample Rate: ",
        CHANNELS_PREFIX = "Channels: ",
        TYPE_PREFIX = "Type: ",
        NO_ITEM_TEXT = "Select a media item to view its details"
    }
}

local r = reaper

-- Create context at script start
local ctx = r.ImGui_CreateContext('Media Source Information')
local font = nil  -- Declare font globally

local WINDOW_FLAGS = r.ImGui_WindowFlags_NoTitleBar()

-- Persistent settings
local settings = {
    dock_id = 0,
    is_docked = false
}

function LoadSettings()
    settings.dock_id = tonumber(r.GetExtState("MediaSourceInfoDock", "dock_id")) or 0
    settings.is_docked = r.GetExtState("MediaSourceInfoDock", "is_docked") == "1"
    
    -- Load last used font size
    local saved_font_size = tonumber(r.GetExtState("MediaSourceInfoDock", "font_size"))
    if saved_font_size then
        CONFIG.FONT_SIZE = saved_font_size
    end
end

function SaveSettings()
    r.SetExtState("MediaSourceInfoDock", "dock_id", tostring(settings.dock_id), true)
    r.SetExtState("MediaSourceInfoDock", "is_docked", settings.is_docked and "1" or "0", true)
    r.SetExtState("MediaSourceInfoDock", "font_size", tostring(CONFIG.FONT_SIZE), true)
end

function GetFilenameFromPath(filepath)
    return filepath:match("[^/\\]+$") or filepath
end

function GetSelectedMediaSourceInfo()
    local item = r.GetSelectedMediaItem(0, 0)
    if not item then return nil end
    
    local take = r.GetActiveTake(item)
    if not take then return nil end
    
    local source = r.GetMediaItemTake_Source(take)
    if not source then return nil end
    
    local filepath = r.GetMediaSourceFileName(source)
    local filename = filepath and GetFilenameFromPath(filepath) or "N/A"
    local length, lengthIsQN = r.GetMediaSourceLength(source)
    local samplerate = r.GetMediaSourceSampleRate(source)
    local numchannels = r.GetMediaSourceNumChannels(source)
    
    local type = r.GetMediaSourceType(source, "")
    
    return {
        Filename = filename,
        Length = lengthIsQN and string.format("%.2f QN (tempo-dependent)", length) or string.format("%.2f seconds", length),
        SampleRate = samplerate and string.format("%d Hz", samplerate) or "N/A",
        Channels = numchannels and tostring(numchannels) or "N/A",
        Type = type or "N/A"
    }
end

-- Create font outside of MainLoop to avoid frame-related issues
font = r.ImGui_CreateFont(CONFIG.FONT_NAME, CONFIG.FONT_SIZE)
r.ImGui_Attach(ctx, font)

function MainLoop()
    r.ImGui_PushFont(ctx, font)
    
    -- Attempt to set dock state with error handling
    local dock_success, dock_error = pcall(function()
        if settings.is_docked and settings.dock_id ~= 0 then
            r.ImGui_SetNextWindowDock(ctx, settings.dock_id)
        end
    end)

    if not dock_success then
        r.ShowConsoleMsg("Dock error: " .. tostring(dock_error) .. "\n")
    end
    
    -- Set background and text colors
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), CONFIG.BACKGROUND_COLOR)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), CONFIG.TEXT_COLOR)
    
    local visible, open = r.ImGui_Begin(ctx, 'Media Source Information', true, WINDOW_FLAGS)
    
    if visible then
        -- Optional display toggles
        if CONFIG.SHOW_DISPLAY_TOGGLES then
            r.ImGui_Text(ctx, "Display Options:")
            CONFIG.SHOW_FILENAME = r.ImGui_Checkbox(ctx, "Filename", CONFIG.SHOW_FILENAME)
            r.ImGui_SameLine(ctx)
            CONFIG.SHOW_LENGTH = r.ImGui_Checkbox(ctx, "Length", CONFIG.SHOW_LENGTH)
            r.ImGui_SameLine(ctx)
            CONFIG.SHOW_SAMPLERATE = r.ImGui_Checkbox(ctx, "Sample Rate", CONFIG.SHOW_SAMPLERATE)
            
            CONFIG.SHOW_CHANNELS = r.ImGui_Checkbox(ctx, "Channels", CONFIG.SHOW_CHANNELS)
            r.ImGui_SameLine(ctx)
            CONFIG.SHOW_TYPE = r.ImGui_Checkbox(ctx, "Type", CONFIG.SHOW_TYPE)
            
            r.ImGui_Spacing(ctx)
            r.ImGui_Separator(ctx)
        end
        
        -- Optional styling options
        if CONFIG.SHOW_STYLING_OPTIONS then
            r.ImGui_Text(ctx, "Styling:")
            local font_changed
            font_changed, CONFIG.FONT_SIZE = r.ImGui_SliderInt(ctx, "Font Size", CONFIG.FONT_SIZE, 8, 24)
            
            local bg_changed
            bg_changed, CONFIG.BACKGROUND_COLOR = r.ImGui_ColorEdit4(ctx, "Background Color", CONFIG.BACKGROUND_COLOR, r.ImGui_ColorEditFlags_NoInputs())
            r.ImGui_SameLine(ctx)
            local text_changed
            text_changed, CONFIG.TEXT_COLOR = r.ImGui_ColorEdit4(ctx, "Text Color", CONFIG.TEXT_COLOR, r.ImGui_ColorEditFlags_NoInputs())
            
            r.ImGui_Spacing(ctx)
            r.ImGui_Separator(ctx)
        end
        
        -- Get and display media source information
        local source_info = GetSelectedMediaSourceInfo()
        
        if source_info then
            if CONFIG.SHOW_FILENAME then
                r.ImGui_Text(ctx, CONFIG.LABELS.FILENAME_PREFIX .. source_info.Filename)
            end
            if CONFIG.SHOW_LENGTH then
                r.ImGui_Text(ctx, CONFIG.LABELS.LENGTH_PREFIX .. source_info.Length)
            end
            if CONFIG.SHOW_SAMPLERATE then
                r.ImGui_Text(ctx, CONFIG.LABELS.SAMPLERATE_PREFIX .. source_info.SampleRate)
            end
            if CONFIG.SHOW_CHANNELS then
                r.ImGui_Text(ctx, CONFIG.LABELS.CHANNELS_PREFIX .. source_info.Channels)
            end
            if CONFIG.SHOW_TYPE then
                r.ImGui_Text(ctx, CONFIG.LABELS.TYPE_PREFIX .. source_info.Type)
            end
        else
            r.ImGui_Text(ctx, CONFIG.LABELS.NO_ITEM_TEXT)
        end
        
        r.ImGui_End(ctx)
    end
    
    -- Pop style modifications
    r.ImGui_PopStyleColor(ctx, 2)
    r.ImGui_PopFont(ctx)  -- Pop the font
    
    if open then
        r.defer(MainLoop)
    end
end

function Start()
    LoadSettings()
    MainLoop()
end

function ToggleScript()
    local _, _, sectionID, cmdID = r.get_action_context()
    local state = r.GetToggleCommandState(cmdID)
    
    if state == -1 or state == 0 then
        r.SetToggleCommandState(sectionID, cmdID, 1)
        r.RefreshToolbar2(sectionID, cmdID)
        Start()
    else
        r.SetToggleCommandState(sectionID, cmdID, 0)
        r.RefreshToolbar2(sectionID, cmdID)
    end
end

function Exit()
    local _, _, sectionID, cmdID = r.get_action_context()
    r.SetToggleCommandState(sectionID, cmdID, 0)
    r.RefreshToolbar2(sectionID, cmdID)
    SaveSettings()
end

r.atexit(Exit)
ToggleScript()
