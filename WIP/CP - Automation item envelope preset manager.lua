-- @description Automation Item Envelope Preset Manager
-- @version 1.0
-- @author Claude

local r = reaper

-- Create context at script start
local ctx = r.ImGui_CreateContext('Automation Item Presets')
local WINDOW_FLAGS = r.ImGui_WindowFlags_NoCollapse()

-- Configuration
local CONFIG = {
    WINDOW_WIDTH = 500,
    WINDOW_HEIGHT = 400,
    DEFAULT_RATE = 1.0
}

-- Preset definition structure with simple shape-based presets
local FACTORY_PRESETS = {
    {
        name = "Sine",
        category = "Basic",
        points = {
            {x = 0, y = 0.5, shape = 5, tension = -0.5},
            {x = 0.25, y = 1, shape = 5, tension = 0.5},
            {x = 0.5, y = 0.5, shape = 5, tension = -0.5},
            {x = 0.75, y = 0, shape = 5, tension = 0.5},
            {x = 1, y = 0.5, shape = 5, tension = -0.5}
        }
    },
    {
        name = "Triangle",
        category = "Basic",
        points = {
            {x = 0, y = 0, shape = 0},
            {x = 0.5, y = 1, shape = 0},
            {x = 1, y = 0, shape = 0}
        }
    },
    {
        name = "Square",
        category = "Basic",
        points = {
            {x = 0, y = 1, shape = 1},
            {x = 0.499, y = 1, shape = 1},
            {x = 0.5, y = 0, shape = 1},
            {x = 1, y = 0, shape = 1}
        }
    },
    {
        name = "Sawtooth",
        category = "Basic",
        points = {
            {x = 0, y = 0, shape = 0},
            {x = 0.999, y = 1, shape = 0},
            {x = 1, y = 0, shape = 0}
        }
    },
    {
        name = "Bezier 1",
        category = "Curves",
        points = {
            {x = 0, y = 0, shape = 5, tension = 0.5},
            {x = 1, y = 1, shape = 5, tension = 0.5}
        }
    },
    {
        name = "Bezier 2",
        category = "Curves",
        points = {
            {x = 0, y = 0, shape = 5, tension = -0.8},
            {x = 1, y = 1, shape = 5, tension = 0.8}
        }
    },
    {
        name = "S-Curve",
        category = "Curves",
        points = {
            {x = 0, y = 0, shape = 5, tension = 0.7},
            {x = 0.5, y = 0.5, shape = 5, tension = 0},
            {x = 1, y = 1, shape = 5, tension = -0.7}
        }
    }
}

-- State variables
local state = {
    selected_envelope = nil,
    selected_ai = -1,
    selected_preset = nil,
    rate = CONFIG.DEFAULT_RATE,
    preview_points = {},
    need_preview_update = true,
    last_valid = false,
    ai_pos = 0,
    ai_len = 0
}

-- Get currently selected envelope and automation item
local function getSelectedEnvelopeAndItem()
    local env = r.GetSelectedEnvelope(0)
    if not env then 
        state.last_valid = false
        return false 
    end
    
    -- Find selected automation item
    local sel_ai = -1
    for i = 0, r.CountAutomationItems(env)-1 do
        if r.GetSetAutomationItemInfo(env, i, "D_UISEL", 0, false) ~= 0 then
            if sel_ai ~= -1 then 
                state.last_valid = false
                return false -- More than one AI selected
            else
                sel_ai = i
                
                -- Store AI properties
                state.ai_pos = r.GetSetAutomationItemInfo(env, sel_ai, "D_POSITION", 0, false)
                state.ai_len = r.GetSetAutomationItemInfo(env, sel_ai, "D_LENGTH", 0, false)
                
                state.selected_envelope = env
                state.selected_ai = sel_ai
                state.last_valid = true
                return true
            end
        end
    end
    
    state.last_valid = false
    return false
end

-- Apply preset points to automation item
local function applyPresetToAI(preset)
    if not (state.selected_envelope and state.selected_ai >= 0) then return end

    -- Get BR envelope for pool operations
    local br_env = r.BR_EnvAlloc(state.selected_envelope, false)
    if not br_env then return end

    -- Get automation item info
    local starttime = r.GetSetAutomationItemInfo(state.selected_envelope, state.selected_ai, "D_POSITION", 0, false)
    local length = r.GetSetAutomationItemInfo(state.selected_envelope, state.selected_ai, "D_LENGTH", 0, false)
    local playrate = r.GetSetAutomationItemInfo(state.selected_envelope, state.selected_ai, "D_PLAYRATE", 0, false)
    
    -- Clear all points in this AI first
    r.DeleteEnvelopePointRangeEx(state.selected_envelope, state.selected_ai, 0, length)

    -- Add the new points
    local repetitions = math.ceil(state.rate)
    for rep = 0, repetitions-1 do
        for _, point in ipairs(preset.points) do
            -- Scale point position by rate and add repetition offset
            local scaled_x = (point.x + rep) / state.rate
            if scaled_x <= 1.0 then
                -- Positions are relative to the start of the AI
                r.InsertEnvelopePointEx(state.selected_envelope, state.selected_ai,
                    scaled_x,  -- Position relative to AI start (0-1)
                    point.y,   -- Value
                    point.shape or 0,
                    point.tension or 0,
                    false, -- Selected
                    true   -- No sort
                )
            end
        end
    end

    -- Add final point if needed
    local last_point = preset.points[#preset.points]
    r.InsertEnvelopePointEx(state.selected_envelope, state.selected_ai,
        1.0,  -- End of AI
        last_point.y,
        last_point.shape or 0,
        last_point.tension or 0,
        false,
        true)

    -- Free BR envelope
    r.BR_EnvFree(br_env, true)
    
    -- Sort and update
    r.Envelope_SortPoints(state.selected_envelope)
end

-- Preview generation
local function updatePreview()
    if not state.selected_preset then return end
    
    state.preview_points = {}
    
    -- Generate preview with repetitions
    local repetitions = math.ceil(state.rate)
    for rep = 0, repetitions-1 do
        for _, point in ipairs(state.selected_preset.points) do
            local scaled_x = (point.x + rep) / state.rate
            if scaled_x <= 1.0 then
                table.insert(state.preview_points, {
                    x = scaled_x,
                    y = point.y,
                    shape = point.shape or 0,
                    tension = point.tension or 0
                })
            end
        end
    end
    
    -- Add final point
    local last_point = state.selected_preset.points[#state.selected_preset.points]
    table.insert(state.preview_points, {
        x = 1.0,
        y = last_point.y,
        shape = last_point.shape or 0,
        tension = last_point.tension or 0
    })
    
    state.need_preview_update = false
end

-- Draw envelope preview
local function drawPreview()
    if state.need_preview_update then
        updatePreview()
    end
    
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local canvas_pos = {r.ImGui_GetCursorScreenPos(ctx)}
    local canvas_size = {r.ImGui_GetContentRegionAvail(ctx)}
    
    -- Background
    r.ImGui_DrawList_AddRectFilled(draw_list, 
        canvas_pos[1], canvas_pos[2],
        canvas_pos[1] + canvas_size[1], canvas_pos[2] + canvas_size[2],
        0x33333333)
        
    -- Grid
    local grid_color = 0x66666666
    for i = 1, 3 do
        local y = canvas_pos[2] + canvas_size[2] * i/4
        r.ImGui_DrawList_AddLine(draw_list,
            canvas_pos[1], y,
            canvas_pos[1] + canvas_size[1], y,
            grid_color)
    end
    for i = 1, 3 do
        local x = canvas_pos[1] + canvas_size[1] * i/4
        r.ImGui_DrawList_AddLine(draw_list,
            x, canvas_pos[2],
            x, canvas_pos[2] + canvas_size[2],
            grid_color)
    end
    
    -- Envelope
    if #state.preview_points > 0 then
        local last_x, last_y
        for i, point in ipairs(state.preview_points) do
            local x = canvas_pos[1] + canvas_size[1] * point.x
            local y = canvas_pos[2] + canvas_size[2] * (1 - point.y)
            
            -- Draw point
            r.ImGui_DrawList_AddCircleFilled(draw_list, x, y, 3, 0xFFFFFFFF)
            
            -- Draw line to previous point
            if last_x then
                r.ImGui_DrawList_AddLine(draw_list, 
                    last_x, last_y, x, y,
                    0xFFFFFFFF,
                    2.0)
            end
            
            last_x, last_y = x, y
            
            -- Draw shape indicator
            if point.shape == 5 then -- Bezier
                local tension_indicator = y + (point.tension or 0) * 20
                r.ImGui_DrawList_AddCircleFilled(draw_list, x, tension_indicator, 2, 0xFF0000FF)
                r.ImGui_DrawList_AddLine(draw_list, x, y, x, tension_indicator, 0x880000FF)
            end
        end
    end
end

-- Variables to detect changes
local last_rate = 0
local last_preset = nil
local last_ai_length = 0
local last_ai_pos = 0
local need_update = false

-- Main UI function
local function frame()
    local visible, open = r.ImGui_Begin(ctx, 'Automation Item Envelope Presets', true, WINDOW_FLAGS)
    
    if visible then
        -- Check if we have a valid selection
        local valid_sel = getSelectedEnvelopeAndItem()
        
        -- Check for changes that require update
        if state.last_valid then
            local ai_length = r.GetSetAutomationItemInfo(state.selected_envelope, state.selected_ai, "D_LENGTH", 0, false)
            local ai_pos = r.GetSetAutomationItemInfo(state.selected_envelope, state.selected_ai, "D_POSITION", 0, false)
            
            if ai_length ~= last_ai_length or 
               ai_pos ~= last_ai_pos or
               state.rate ~= last_rate or
               state.selected_preset ~= last_preset then
                need_update = true
            end
            
            -- Update stored values
            last_ai_length = ai_length
            last_ai_pos = ai_pos
            last_rate = state.rate
            last_preset = state.selected_preset
        end
        
        if not valid_sel then
            if not state.last_valid then
                r.ImGui_Text(ctx, "Please select a single automation item")
            end
            
            -- Keep showing UI but disable controls
            r.ImGui_BeginDisabled(ctx)
        end
        
        -- Show AI info when valid
        if state.last_valid then
            r.ImGui_Text(ctx, string.format("Automation Item at %.2fs, length: %.2fs", 
                state.ai_pos, state.ai_len))
        end
        
        -- Rate control
        local changed
        changed, state.rate = r.ImGui_SliderDouble(ctx, 'Rate (repetitions)', state.rate, 0.25, 4.0, '%.2f')
        if changed then
            state.need_preview_update = true
            need_update = true
        end
        
        r.ImGui_Separator(ctx)
        
        -- Presets list
        local presets_flags = r.ImGui_WindowFlags_None()
        if r.ImGui_BeginChild(ctx, 'presets_list', 150, -1) then
            local last_category = nil
            
            for _, preset in ipairs(FACTORY_PRESETS) do
                if preset.category ~= last_category then
                    if last_category then r.ImGui_Separator(ctx) end
                    r.ImGui_TextColored(ctx, 0xFFAA66FF, preset.category)
                    last_category = preset.category
                end
                
                if r.ImGui_Selectable(ctx, preset.name, state.selected_preset == preset) then
                    state.selected_preset = preset
                    state.need_preview_update = true
                    need_update = true
                end
            end
            r.ImGui_EndChild(ctx)
        end
        
        r.ImGui_SameLine(ctx)
        
        -- Preview and controls
        if r.ImGui_BeginChild(ctx, 'preview', 0, -1) then
            -- Preview
            r.ImGui_Text(ctx, "Preview")
            if r.ImGui_BeginChild(ctx, 'preview_canvas', 0, 200) then
                drawPreview()
                r.ImGui_EndChild(ctx)
            end
            
            -- Apply changes if needed
            if need_update and state.selected_preset then
                r.Undo_BeginBlock()
                applyPresetToAI(state.selected_preset)
                r.Undo_EndBlock('Update Envelope Preset', -1)
                need_update = false
            end
            
            r.ImGui_EndChild(ctx)
        end
        
        if not valid_sel then
            r.ImGui_EndDisabled(ctx)
        end
        
        r.ImGui_End(ctx)
    end
    
    if open then
        r.defer(frame)
    end
end

-- Script entry point
function init()
    r.defer(frame)
end

init()