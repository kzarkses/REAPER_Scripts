-- @description Media Properties Toolbar
-- @version 1.2
-- @author Claude
-- @about
--   Display and edit media item properties in a toolbar

local r = reaper

-- Configuration variables
local config = {
    -- Interface
    font_name = "Verdana",
    font_size = 16,
    entry_height = 20,
    entry_width = 60,
    name_width = 240,  -- Independent width for name
    source_width = 300, -- Independent width for source
    text_color = {0.70, 0.70, 0.70, 1},
    background_color = {0.2, 0.2, 0.2, 1},
    frame_color = {0.2, 0.2, 0.2, 1},
    frame_color_active = {0.21, 0.7, 0.63, 0.4},

    colors = {
        text_normal = {0.75, 0.75, 0.75, 1.0},
        text_modified = {0.0, 0.8, 0.6, 1.0},
        text_negative = {0.8, 0.4, 0.6, 1.0},
        text_bool_on = {0.0, 0.8, 0.0, 1.0},
        text_bool_off = {0.8, 0.0, 0.0, 1.0}
    },

    tooltip_bg = {0.2, 0.2, 0.2, 0.95},
    tooltip_text = {0.9, 0.9, 0.9, 1.0},

    mouse = {
        volume_sensitivity = 0.05,
        pitch_sensitivity = 0.1,
        pan_sensitivity = 0.01,
        rate_sensitivity = 0.01,
        time_sensitivity = 0.01
    },

    volume = {
        min_db = -120,
        max_db = 120,
        step_db = 1,
        drag_sensitivity = 0.05
    },

    pitch = {
        min = -96,
        max = 96,
        step = 1,
        drag_sensitivity = 0.1
    },

    pan = {
        min = -1,
        max = 1,
        step = 0.1,
        drag_sensitivity = 0.01
    },

    rate = {
        min = 0.1,
        max = 100,
        step = 0.1,
        drag_sensitivity = 0.01
    },

    time = {
        step = 1,
        drag_seconds = 0.01,
        drag_minutes = 0.6,
        drag_milliseconds = 0.001
    },

    db_to_linear = function(db)
        return 10^(db/20)
    end,
    
    linear_to_db = function(linear)
        if linear <= 0 then return -120 end
        return 20 * math.log(linear, 10)
    end,
   
    clamp = function(value, min, max)
        return math.max(min, math.min(max, value))
    end
}

local state = {
    last_item = nil,
    last_mouse_cap = 0,
    last_mouse_x = 0,
    last_mouse_y = 0,
    drag_active = false,
    active_control = nil,
    window_x = 0,
    window_y = 0,
    dock_id = 0,
    is_docked = false
}

-- Load saved dock state
function loadDockState()
    state.dock_id = tonumber(r.GetExtState("MediaPropertiesToolbar", "dock_id")) or 0
    state.is_docked = r.GetExtState("MediaPropertiesToolbar", "is_docked") == "1"
end

-- Save dock state
function saveDockState()
    r.SetExtState("MediaPropertiesToolbar", "dock_id", tostring(state.dock_id), true)
    r.SetExtState("MediaPropertiesToolbar", "is_docked", state.is_docked and "1" or "0", true)
end

function init()
    loadDockState()
    
    local title = 'Media Properties Toolbar'
    local docked = state.is_docked and state.dock_id or 0
    local x, y = 100, 100
    local w = 1200  -- Increased width to accommodate new parameters
    local h = config.entry_height * 2
    
    -- Initialize window without focus
    gfx.init(title, w, h, docked, x, y)
    gfx.setfont(1, config.font_name, config.font_size)
    
    -- Keep arrange window focused
    r.Main_OnCommand(r.NamedCommandLookup("_BR_FOCUS_ARRANGE_WND"), 0)
end

function truncateString(str, maxWidth)
    local str_w = gfx.measurestr(str)
    if str_w <= maxWidth then return str end
    
    local ellipsis = "..."
    local ellipsis_w = gfx.measurestr(ellipsis)
    local available_w = maxWidth - ellipsis_w
    
    while str_w > available_w and #str > 1 do
        str = str:sub(2)
        str_w = gfx.measurestr(str)
    end
    
    return ellipsis .. str
end

function drawTooltip(text, x, y)
    local padding = 4
    local text_w, text_h = gfx.measurestr(text)
    
    gfx.set(table.unpack(config.tooltip_bg))
    gfx.rect(x, y - text_h - padding*2, text_w + padding*2, text_h + padding*2, true)
    
    gfx.set(table.unpack(config.tooltip_text))
    gfx.x = x + padding
    gfx.y = y - text_h - padding
    gfx.drawstr(text)
end

function drawHeaderCell(text, x, y, w)
    gfx.set(table.unpack(config.frame_color))
    gfx.rect(x, y, w, config.entry_height)
    
    gfx.set(table.unpack(config.text_color))
    local str_w, str_h = gfx.measurestr(text)
    gfx.x = x + (w - str_w) / 2
    gfx.y = y + (config.entry_height - str_h) / 2
    gfx.drawstr(text)
end

function drawValueCell(value, x, y, w, is_active, param_type, param_name)
    if is_active then
        gfx.set(table.unpack(config.frame_color_active))
    else
        gfx.set(table.unpack(config.frame_color))
    end
    gfx.rect(x, y, w, config.entry_height)

        -- Check if value is modified from default
    local is_negative = false
    if param_type == "volume" or param_type == "takevol" then
        local db = 20 * math.log(value, 10)
        is_negative = db < 0
    elseif param_type == "pitch" or param_type == "pan" then
        is_negative = value < 0
    elseif param_type == "rate" then  
        is_negative = value < 1.0
    end
    
    -- Then check for any modifications
    local is_modified = false
    if param_type == "volume" or param_type == "takevol" then
        is_modified = math.abs(value - 1.0) > 0.001
    elseif param_type == "pitch" or param_type == "pan" then 
        is_modified = math.abs(value) > 0.001
    elseif param_type == "rate" then
        is_modified = math.abs(value - 1.0) > 0.001
    elseif param_type == "time" and (param_name == "snap" or param_name == "fadein" or param_name == "fadeout") then
        is_modified = value > 0.001 
    end

    -- Special handling for boolean values
    if param_type == "bool" then
        is_modified = value
        is_negative = not value
        value = value and "ON" or "OFF"
    end

    -- Set color based on state
    if is_negative then
        gfx.set(table.unpack(config.colors.text_negative))
    elseif is_modified then
        gfx.set(table.unpack(config.colors.text_modified))
    else
        gfx.set(table.unpack(config.colors.text_normal))
    end

    local metrics = nil
    local display_value

    if param_type == "time" or param_name == "position" or param_name == "length" then
        -- Convert to minutes:seconds.milliseconds format
        local minutes = math.floor(value / 60)
        local seconds = math.floor(value % 60)
        local ms = math.floor((value % 1) * 1000)
        display_value = string.format("%d:%02d.%03d", minutes, seconds, ms)
    elseif param_type == "volume" or param_type == "takevol" then
        local db = 20 * math.log(value, 10)
        if db == math.abs(0) then db = 0 end
        display_value = string.format("%+.1f dB", db)
    elseif param_type == "pitch" then
        if value == 0 then 
            display_value = "0 st"
        else 
            display_value = string.format("%+.1f st", value)
        end
    elseif param_type == "pan" then
        if value == 0 then 
            display_value = "C"
        elseif value < 0 then 
            display_value = string.format("%d L", math.floor(math.abs(value * 100)))
        else 
            display_value = string.format("%d R", math.floor(value * 100))
        end
    elseif param_type == "rate" then
        display_value = string.format("%.3f x", value)
    elseif param_type == "bool" then
        display_value = value
    else
        display_value = tostring(value)
    end
    
    if param_type == "name" then
        local margin = 4
        display_value = truncateString(display_value, w - margin)
    end

    if param_type == "time" then
        local str_w = gfx.measurestr(display_value)
        local text_x = x + (w - str_w) / 2
        gfx.x = text_x
        gfx.y = y + (config.entry_height - select(2, gfx.measurestr(display_value))) / 2
        gfx.drawstr(display_value)
        metrics = getTimeStringMetrics(display_value, text_x)
    else
        local str_w, str_h = gfx.measurestr(display_value)
        gfx.x = x + (w - str_w) / 2
        gfx.y = y + (config.entry_height - str_h) / 2
        gfx.drawstr(display_value)
    end
    
    return {
        x = x, 
        y = y, 
        w = w, 
        h = config.entry_height,
        text_metrics = metrics,
        param_type = param_type
    }
end

function formatTimeString(time)
    local minutes = math.floor(time / 60)
    local seconds = math.floor(time % 60)
    local ms = math.floor((time % 1) * 1000)
    return string.format("%d:%02d.%03d", minutes, seconds, ms)
end

function getTimeStringMetrics(str, x)
    local parts = {}
    local minutes = str:match("^(%d+):")
    local seconds = str:match(":(%d+)%.")
    local ms = str:match("%.(%d+)$")
    
    local min_width = gfx.measurestr(minutes)
    local colon_width = gfx.measurestr(":")
    local sec_width = gfx.measurestr(seconds)
    local dot_width = gfx.measurestr(".")
    
    parts.min_end = x + min_width
    parts.sec_start = parts.min_end + colon_width
    parts.sec_end = parts.sec_start + sec_width
    parts.ms_start = parts.sec_end + dot_width
    
    return parts
end

function updateItemRate(item, take, rate)
    local original_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local original_rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    
    local new_length = original_length * (original_rate / rate)
    
    r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
    r.SetMediaItemInfo_Value(item, "D_LENGTH", new_length)
    
    r.UpdateItemInProject(item)
end

function handleMouseInput(item_data, mx, my, controls)
    local mouse_cap = gfx.mouse_cap
    local mouse_wheel = gfx.mouse_wheel
    gfx.mouse_wheel = 0

    if mouse_cap == 0 then
        for id, ctrl in pairs(controls) do
            if mx >= ctrl.x and mx < ctrl.x + ctrl.w and
               my >= ctrl.y and my < ctrl.y + ctrl.h then
                if id == "source" then
                    drawTooltip(ctrl.full_source, mx + 10, my)
                end
            end
        end
    end

    -- Handle click/double-click
    if mouse_cap == 1 and state.last_mouse_cap == 0 then
        local current_time = r.time_precise()
        local last_click_time = state.last_click_time or 0
        local is_double_click = (current_time - last_click_time) < 0.3
        state.last_click_time = current_time
    
        if is_double_click then
            for id, ctrl in pairs(controls) do
                if mx >= ctrl.x and mx < ctrl.x + ctrl.w and
                   my >= ctrl.y and my < ctrl.y + ctrl.h then
                    if ctrl.param_type == "bool" then
                        updateItemValue(item_data, id, not ctrl.value)
                    else
                        local new_value = handleValueInput(id, ctrl.value)
                        if new_value then
                            updateItemValue(item_data, id, new_value)
                        end
                    end
                    break
                end
            end
        else
            for id, ctrl in pairs(controls) do
                if mx >= ctrl.x and mx < ctrl.x + ctrl.w and
                   my >= ctrl.y and my < ctrl.y + ctrl.h then
                    if ctrl.param_type ~= "bool" then
                        state.active_control = id
                        state.drag_active = true
                    else
                        updateItemValue(item_data, id, not ctrl.value)
                    end
                    break
                end
            end
        end
    end

    -- Handle wheel
    if mouse_wheel ~= 0 then
        for id, ctrl in pairs(controls) do
            if mx >= ctrl.x and mx < ctrl.x + ctrl.w and
               my >= ctrl.y and my < ctrl.y + ctrl.h then
                
                if id == "volume" or id == "takevol" then
                    local current_db = config.linear_to_db(ctrl.value)
                    local db_change = mouse_wheel > 0 and config.volume.step_db or -config.volume.step_db
                    local new_db = config.clamp(current_db + db_change, config.volume.min_db, config.volume.max_db)
                    updateItemValue(item_data, id, config.db_to_linear(new_db))
                
                elseif id == "pitch" then
                    local new_value = config.clamp(
                        ctrl.value + (mouse_wheel > 0 and config.pitch.step or -config.pitch.step),
                        config.pitch.min, 
                        config.pitch.max
                    )
                    updateItemValue(item_data, id, new_value)
 
                elseif id == "pan" then
                    local new_value = config.clamp(
                        ctrl.value + (mouse_wheel > 0 and config.pan.step or -config.pan.step),
                        config.pan.min, 
                        config.pan.max
                    )
                    updateItemValue(item_data, id, new_value)
 
                elseif id == "rate" then
                    local new_value = config.clamp(
                        ctrl.value + (mouse_wheel > 0 and config.rate.step or -config.rate.step),
                        config.rate.min, 
                        config.rate.max
                    )
                    updateItemValue(item_data, id, new_value)
 
                elseif ctrl.param_type == "time" then
                    if ctrl.text_metrics then
                        local increment
                        if mx <= ctrl.text_metrics.min_end then
                            increment = 60  -- Minutes
                        elseif mx <= ctrl.text_metrics.sec_end then
                            increment = 1   -- Seconds
                        else
                            increment = 0.001  -- Millisecondes
                        end
                        local delta = mouse_wheel > 0 and increment or -increment
                        updateItemValue(item_data, id, math.max(0, ctrl.value + delta))
                    end
                end
            end
        end
    end
    
    -- Handle drag
    if state.drag_active and state.active_control then
        local ctrl = controls[state.active_control]
        if ctrl then
            if state.active_control == "volume" or state.active_control == "takevol" then
                local db_change = (mx - state.last_mouse_x) * config.mouse.volume_sensitivity
                local current_db = config.linear_to_db(ctrl.value)
                local new_db = config.clamp(current_db + db_change, config.volume.min_db, config.volume.max_db)
                updateItemValue(item_data, state.active_control, config.db_to_linear(new_db))
    
            elseif state.active_control == "pitch" then
                local change = (mx - state.last_mouse_x) * config.mouse.pitch_sensitivity
                local new_value = config.clamp(ctrl.value + change, config.pitch.min, config.pitch.max)
                updateItemValue(item_data, "pitch", new_value)
    
            elseif state.active_control == "pan" then
                local change = (mx - state.last_mouse_x) * config.mouse.pan_sensitivity
                local new_value = config.clamp(ctrl.value + change, config.pan.min, config.pan.max)
                updateItemValue(item_data, "pan", new_value)
    
            elseif state.active_control == "rate" then
                local change = (mx - state.last_mouse_x) * config.mouse.rate_sensitivity
                local new_value = config.clamp(ctrl.value + change, config.rate.min, config.rate.max)
                updateItemValue(item_data, "rate", new_value)
                
            elseif ctrl.param_type == "time" then
                if ctrl.text_metrics then
                    local drag_sensitivity
                    if mx <= ctrl.text_metrics.min_end then
                        drag_sensitivity = config.time.drag_minutes
                    elseif mx <= ctrl.text_metrics.sec_end then
                        drag_sensitivity = config.time.drag_seconds
                    else
                        drag_sensitivity = config.time.drag_milliseconds
                    end
                    
                    local change = (mx - state.last_mouse_x) * drag_sensitivity
                    updateItemValue(item_data, state.active_control, math.max(0, ctrl.value + change))
                end
            end
        end
    end

    -- Handle right-click reset
    if mouse_cap == 2 and state.last_mouse_cap == 0 then
        for id, ctrl in pairs(controls) do
            if mx >= ctrl.x and mx < ctrl.x + ctrl.w and
               my >= ctrl.y and my < ctrl.y + ctrl.h then
                local reset_value = nil
                if id == "volume" then reset_value = 1.0
                elseif id == "takevol" then reset_value = 1.0
                elseif id == "pitch" then reset_value = 0
                elseif id == "pan" then reset_value = 0
                elseif id == "rate" then reset_value = 1.0
                elseif id == "fadein" then reset_value = 0
                elseif id == "fadeout" then reset_value = 0
                elseif id == "snap" then reset_value = 0
                elseif id == "preserve_pitch" then reset_value = false
                elseif id == "phase_invert" then reset_value = false
                elseif id == "mute" then reset_value = false
                end
                    
                if reset_value ~= nil then
                    updateItemValue(item_data, id, reset_value)
                end
                break
            end
        end
    end

    if mouse_cap == 0 then
        state.drag_active = false
        state.active_control = nil
    end
    
    state.last_mouse_cap = mouse_cap
    state.last_mouse_x = mx
    state.last_mouse_y = my
end

function handleValueInput(param_name, current_value)
    if param_name == "position" or param_name == "length" or 
       param_name == "fadein" or param_name == "fadeout" or
       param_name == "snap" then
       
        local min = math.floor(current_value / 60)
        local sec = math.floor(current_value % 60)
        local ms = math.floor((current_value % 1) * 1000)
        
        local retval, user_input = r.GetUserInputs(param_name, 3, 
            "Minutes,Seconds,Milliseconds", 
            string.format("%d,%d,%d", min, sec, ms))
            
        if not retval then return nil end
        
        local new_min, new_sec, new_ms = user_input:match("([^,]+),([^,]+),([^,]+)")
        if new_min and new_sec and new_ms then
            new_min = tonumber(new_min) or 0
            new_sec = tonumber(new_sec) or 0
            new_ms = tonumber(new_ms) or 0
            return new_min * 60 + new_sec + new_ms/1000
        end
        return current_value
        
    elseif param_name == "pan" then
        local pan_val = current_value * 100
        local retval, user_input = r.GetUserInputs(param_name, 1, 
            "Pan (-100=L, 0=C, 100=R):", string.format("%.0f", pan_val))
        if not retval then return current_value end
        local new_value = tonumber(user_input)
        if new_value then return new_value/100 end
        return current_value
        
    elseif param_name == "pitch" then
        local retval, user_input = r.GetUserInputs(param_name, 1, 
            "Pitch (semitones):", string.format("%.1f", current_value))
        if not retval then return current_value end
        return tonumber(user_input) or current_value
        
    elseif param_name == "rate" then
        local retval, user_input = r.GetUserInputs(param_name, 1, 
            "Playback rate:", string.format("%.3f", current_value))
        if not retval then return current_value end
        return tonumber(user_input) or current_value
        
    elseif param_name == "name" then
        local retval, user_input = r.GetUserInputs("Item Name", 1, 
            "New name:,extrawidth=200", current_value or "")
        if retval then return user_input end
        return current_value
    end
    
    return current_value
end

function updateItemValue(item_data, param_name, value)
    local selected_items = {}
    local item_count = r.CountSelectedMediaItems(0)
    
    for i = 0, item_count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        table.insert(selected_items, item)
    end
    
    if #selected_items == 0 then return end
    
    r.Undo_BeginBlock()
    
    for _, item in ipairs(selected_items) do
        local take = r.GetActiveTake(item)
        if take then
            if param_name == "name" then
                r.GetSetMediaItemTakeInfo_String(take, "P_NAME", value, true)
            
            elseif param_name == "volume" then
                r.SetMediaItemInfo_Value(item, "D_VOL", value)
                
            elseif param_name == "takevol" then
                r.SetMediaItemTakeInfo_Value(take, "D_VOL", value)
                
            elseif param_name == "pitch" then
                r.SetMediaItemTakeInfo_Value(take, "D_PITCH", value)
                
            elseif param_name == "pan" then
                r.SetMediaItemTakeInfo_Value(take, "D_PAN", value)
                
            elseif param_name == "rate" then
                updateItemRate(item, take, value)
                
            elseif param_name == "preserve_pitch" then
                r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", value and 1 or 0)
                
            elseif param_name == "phase_invert" then
                -- Toggle phase
                r.Main_OnCommand(40181, 0)
                
            elseif param_name == "mute" then
                r.SetMediaItemInfo_Value(item, "B_MUTE", value and 1 or 0)
                
            elseif param_name == "position" then
                r.SetMediaItemInfo_Value(item, "D_POSITION", value)
                
            elseif param_name == "length" then
                r.SetMediaItemInfo_Value(item, "D_LENGTH", value)
                
            elseif param_name == "snap" then
                r.SetMediaItemInfo_Value(item, "D_SNAPOFFSET", value)
                
            elseif param_name == "fadein" then
                r.SetMediaItemInfo_Value(item, "D_FADEINLEN", value)
                
            elseif param_name == "fadeout" then
                r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", value)
            end
            
            r.UpdateItemInProject(item)
        end
    end
    
    r.Undo_EndBlock("Update media items", -1)
    
    -- Keep arrange window focused
    r.Main_OnCommand(r.NamedCommandLookup("_BR_FOCUS_ARRANGE_WND"), 0)
end

function drawInterface()
    local total_width = gfx.w
    local remaining_width = total_width - config.name_width - config.source_width 
    local base_width = math.floor(remaining_width / 13) -- Ajusté pour 15 colonnes
    
    -- Headers
    local headers = {
        {name = "Name", width = config.name_width, type = "text"},
        {name = "Source", width = config.source_width, type = "text"},
        {name = "Position", width = base_width, type = "text"},
        {name = "Length", width = base_width, type = "text"},
        {name = "Snap", width = base_width, type = "time"},
        {name = "FadeIn", width = base_width, type = "time"},
        {name = "FadeOut", width = base_width, type = "time"},
        {name = "Volume", width = base_width, type = "volume"},
        {name = "TakeVol", width = base_width, type = "takevol"},
        {name = "Pitch", width = base_width, type = "pitch"},
        {name = "PresPitch", width = base_width, type = "bool"},
        {name = "Pan", width = base_width, type = "pan"},
        {name = "Rate", width = base_width, type = "rate"},
        {name = "Phase", width = base_width, type = "bool"},
        {name = "Mute", width = base_width, type = "bool"}
    }
 
    x = 0
    for _, header in ipairs(headers) do
        drawHeaderCell(header.name, x, 0, header.width)
        x = x + header.width
    end
 
    local item = r.GetSelectedMediaItem(0, 0)
    if not item then return end
    
    local take = r.GetActiveTake(item)
    if not take then return end
    
    -- Get item data
    local data = {
        name = take and ({r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)})[2] or "",
        source = r.GetMediaSourceFileName(r.GetMediaItemTake_Source(take), ""),
        position = r.GetMediaItemInfo_Value(item, "D_POSITION"),
        length = r.GetMediaItemInfo_Value(item, "D_LENGTH"),
        snap = r.GetMediaItemInfo_Value(item, "D_SNAPOFFSET"),
        fadein = r.GetMediaItemInfo_Value(item, "D_FADEINLEN"),
        fadeout = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN"),
        volume = r.GetMediaItemInfo_Value(item, "D_VOL"),
        takevol = r.GetMediaItemTakeInfo_Value(take, "D_VOL"),
        pitch = r.GetMediaItemTakeInfo_Value(take, "D_PITCH"),
        pan = r.GetMediaItemTakeInfo_Value(take, "D_PAN"),
        rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"),
        preserve_pitch = r.GetMediaItemTakeInfo_Value(take, "B_PPITCH") == 1,
        phase_invert = r.GetMediaItemTakeInfo_Value(take, "D_PHASE") > 0,
        mute = r.GetMediaItemInfo_Value(item, "B_MUTE") == 1
    }
    
    -- Reset x for values
    x = 0
    local controls = {}
    
    -- Draw cells
    -- Name
    controls.name = drawValueCell(data.name, x, config.entry_height, 
        config.name_width, state.active_control == "name", "name")
    controls.name.value = data.name
    x = x + config.name_width
    
    -- Source
    local source_name = data.source:match("([^/\\]+)$") or "[No source]"
    controls.source = drawValueCell(truncateString(source_name, config.source_width - 8), 
        x, config.entry_height, config.source_width)
    controls.source = {
        x = x, y = config.entry_height,
        w = config.source_width, h = config.entry_height,
        value = source_name,
        full_source = data.source
    }
    x = x + config.source_width

    -- Value cells
    local value_params = {
        {key = "position", type = "text"},
        {key = "length", type = "text"},
        {key = "snap", type = "time"},
        {key = "fadein", type = "time"},
        {key = "fadeout", type = "time"},
        {key = "volume", type = "volume"},
        {key = "takevol", type = "takevol"},
        {key = "pitch", type = "pitch"},
        {key = "preserve_pitch", type = "bool"},
        {key = "pan", type = "pan"},
        {key = "rate", type = "rate"},
        {key = "phase_invert", type = "bool"},
        {key = "mute", type = "bool"}
    }
    
    for _, param in ipairs(value_params) do
        controls[param.key] = drawValueCell(
            data[param.key],
            x, config.entry_height,
            base_width,
            state.active_control == param.key,
            param.type,
            param.key
        )
        controls[param.key].value = data[param.key]
        x = x + base_width
    end
    
    handleMouseInput(data, gfx.mouse_x, gfx.mouse_y, controls)
end

function loop()
    -- Clear background
    gfx.set(table.unpack(config.background_color))
    gfx.rect(0, 0, gfx.w, gfx.h, true)
    
    -- Draw interface
    drawInterface()
    
    -- Check dock state
    local dock_state = gfx.dock(-1)
    if dock_state ~= state.dock_id or 
       (dock_state > 0) ~= state.is_docked then
        state.dock_id = dock_state
        state.is_docked = dock_state > 0
        saveDockState()
    end
    
    -- Handle window state
    local char = gfx.getchar()
    if char >= 0 then
        r.defer(loop)
    end
    
    gfx.update()
end

init()
loop()