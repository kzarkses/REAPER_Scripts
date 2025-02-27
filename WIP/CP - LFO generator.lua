-- @description LFO Generator with Envelope Control for Automation Items
-- @version 1.0
-- @author Claude

local r = reaper

-- Constants
local WINDOW_W, WINDOW_H = 800, 400
local ENV_W, ENV_H = 350, 300
local SPACING = 20
local POINT_RADIUS = 5

-- LFO Shapes (matching REAPER's native shapes)
local SHAPES = {
    {name = "Sine", id = 0},
    {name = "Square", id = 1},
    {name = "Triangle", id = 2},
    {name = "Saw", id = 3}
}

-- State
local selected_shape = 0
local env = {
    rate = {
        points = {{0, 0.5}, {1, 0.5}}, -- normalized coordinates
        hot_point = -1,
        dragging = false
    },
    amplitude = {
        points = {{0, 0.5}, {1, 0.5}},
        hot_point = -1,
        dragging = false
    }
}

-- Initialization
local function init()
    gfx.init("LFO Generator", WINDOW_W, WINDOW_H)
    gfx.clear = 0x333333
end

-- Utility functions
local function scale_rate(y)
    -- Scale normalized Y (0-1) to frequency (0.1-20Hz)
    return 0.1 + (y * 19.9)
end

local function scale_amplitude(y)
    -- Scale normalized Y (0-1) to amplitude (0-100%)
    return y * 100
end

local function draw_grid(x, y, w, h)
    gfx.set(0.3, 0.3, 0.3, 1)
    for i = 0, 10 do
        local grid_x = x + (w * i / 10)
        local grid_y = y + (h * i / 10)
        gfx.line(x, grid_y, x + w, grid_y)
        gfx.line(grid_x, y, grid_x, y + h)
    end
end

local function draw_envelope(env_data, x, y, title)
    -- Draw title
    gfx.set(1, 1, 1, 1)
    gfx.x, gfx.y = x, y - 20
    gfx.drawstr(title)
    
    -- Draw background and grid
    gfx.set(0.2, 0.2, 0.2, 1)
    gfx.rect(x, y, ENV_W, ENV_H, true)
    draw_grid(x, y, ENV_W, ENV_H)
    
    -- Draw lines between points
    gfx.set(1, 0.5, 0, 1)
    for i = 2, #env_data.points do
        local x1 = x + env_data.points[i-1][1] * ENV_W
        local y1 = y + (1 - env_data.points[i-1][2]) * ENV_H
        local x2 = x + env_data.points[i][1] * ENV_W
        local y2 = y + (1 - env_data.points[i][2]) * ENV_H
        gfx.line(x1, y1, x2, y2)
    end
    
    -- Draw points
    for i, point in ipairs(env_data.points) do
        if i == env_data.hot_point then
            gfx.set(0, 1, 0, 1)
        else
            gfx.set(1, 0, 0, 1)
        end
        local px = x + point[1] * ENV_W
        local py = y + (1 - point[2]) * ENV_H
        gfx.circle(px, py, POINT_RADIUS, 1, 1)
    end
end

local function handle_envelope_interaction(env_data, base_x, base_y)
    local mouse_x, mouse_y = gfx.mouse_x, gfx.mouse_y
    
    -- Check if mouse is in envelope area
    if mouse_x >= base_x and mouse_x <= base_x + ENV_W and
       mouse_y >= base_y and mouse_y <= base_y + ENV_H then
        
        -- Convert to normalized coordinates
        local norm_x = (mouse_x - base_x) / ENV_W
        local norm_y = 1 - ((mouse_y - base_y) / ENV_H)
        
        -- Handle point selection and dragging
        if gfx.mouse_cap & 1 == 1 then
            if env_data.hot_point == -1 then
                -- Check if clicking near a point
                for i, point in ipairs(env_data.points) do
                    local px = base_x + point[1] * ENV_W
                    local py = base_y + (1 - point[2]) * ENV_H
                    if (mouse_x - px)^2 + (mouse_y - py)^2 < POINT_RADIUS^2 * 2 then
                        env_data.hot_point = i
                        env_data.dragging = true
                        break
                    end
                end
                
                -- Double click to add point
                if env_data.hot_point == -1 and gfx.mouse_cap & 1 == 1 then
                    local new_point = {norm_x, norm_y}
                    -- Find insertion position
                    local pos = 1
                    while pos <= #env_data.points and env_data.points[pos][1] < norm_x do
                        pos = pos + 1
                    end
                    table.insert(env_data.points, pos, new_point)
                    env_data.hot_point = pos
                    return true
                end
            elseif env_data.dragging then
                -- Update point position
                local point = env_data.points[env_data.hot_point]
                point[1] = norm_x
                point[2] = norm_y
                -- Sort points by x coordinate
                table.sort(env_data.points, function(a, b) return a[1] < b[1] end)
                return true
            end
        else
            env_data.hot_point = -1
            env_data.dragging = false
        end
        
        -- Right click to delete point
        if gfx.mouse_cap & 2 == 2 then
            for i, point in ipairs(env_data.points) do
                local px = base_x + point[1] * ENV_W
                local py = base_y + (1 - point[2]) * ENV_H
                if (mouse_x - px)^2 + (mouse_y - py)^2 < POINT_RADIUS^2 * 2 then
                    if #env_data.points > 2 and i > 1 and i < #env_data.points then
                        table.remove(env_data.points, i)
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function draw_shape_buttons()
    local btn_w = 80
    local btn_h = 25
    local x = 10
    local y = 10
    
    for i, shape in ipairs(SHAPES) do
        gfx.set(selected_shape == shape.id and 0.6 or 0.3, 0.3, 0.3, 1)
        gfx.rect(x, y, btn_w, btn_h, true)
        gfx.set(1, 1, 1, 1)
        gfx.x = x + 5
        gfx.y = y + 5
        gfx.drawstr(shape.name)
        
        if gfx.mouse_cap & 1 == 1 and
           gfx.mouse_x >= x and gfx.mouse_x <= x + btn_w and
           gfx.mouse_y >= y and gfx.mouse_y <= y + btn_h then
            selected_shape = shape.id
            return true
        end
        
        x = x + btn_w + 10
    end
    return false
end

local function apply_lfo()
    -- Get selected envelope and automation item
    local sel_env = r.GetSelectedEnvelope(0)
    if not sel_env then return end
    
    local ai_count = r.CountAutomationItems(sel_env)
    local sel_ai = -1
    for i = 0, ai_count - 1 do
        if r.GetSetAutomationItemInfo(sel_env, i, "D_UISEL", 0, false) ~= 0 then
            sel_ai = i
            break
        end
    end
    if sel_ai == -1 then return end
    
    -- Calculate average rate and amplitude from points
    local avg_rate = 0
    local avg_amp = 0
    
    for _, point in ipairs(env.rate.points) do
        avg_rate = avg_rate + scale_rate(point[2])
    end
    avg_rate = avg_rate / #env.rate.points
    
    for _, point in ipairs(env.amplitude.points) do
        avg_amp = avg_amp + scale_amplitude(point[2])
    end
    avg_amp = avg_amp / #env.amplitude.points
    
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock()
    
    -- Get the envelope state chunk
    local _, chunk = r.GetEnvelopeStateChunk(sel_env, "", true)
    
    -- Find the selected automation item in the chunk
    local ai_pattern = "(AI .-\n)"
    local count = 0
    chunk = chunk:gsub(ai_pattern, function(ai_chunk)
        count = count + 1
        if count - 1 == sel_ai then
            -- Convert to LFO if not already
            if not ai_chunk:match("POOL .-TYPE 1") then
                ai_chunk = ai_chunk:gsub("POOL .-TYPE %d+", "POOL TYPE 1")
            end
            
            -- Update LFO properties
            ai_chunk = ai_chunk:gsub("POOL", string.format("POOL SHAPE %d FREQ %f AMP %f", 
                                                         selected_shape, 
                                                         avg_rate,
                                                         avg_amp / 100))
        end
        return ai_chunk
    end)
    
    -- Set the modified chunk back
    r.SetEnvelopeStateChunk(sel_env, chunk, true)
    
    r.Undo_EndBlock("Update LFO Parameters", -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end

local function main()
    local changed = false
    
    -- Clear background
    gfx.clear = 0x333333
    
    -- Draw shape selector
    changed = draw_shape_buttons() or changed
    
    -- Draw and handle rate envelope
    draw_envelope(env.rate, 20, 50, "Rate (0.1-20 Hz)")
    changed = handle_envelope_interaction(env.rate, 20, 50) or changed
    
    -- Draw and handle amplitude envelope
    draw_envelope(env.amplitude, ENV_W + SPACING + 20, 50, "Amplitude (0-100%)")
    changed = handle_envelope_interaction(env.amplitude, ENV_W + SPACING + 20, 50) or changed
    
    -- Apply changes if needed
    if changed then
        apply_lfo()
    end
    
    -- Handle window close
    local char = gfx.getchar()
    if char == 27 or char < 0 then
        gfx.quit()
        return
    end
    
    gfx.update()
    r.defer(main)
end

-- Script entry point
init()
main()