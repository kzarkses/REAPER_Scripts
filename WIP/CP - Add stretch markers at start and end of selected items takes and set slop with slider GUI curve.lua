local r = reaper

-- Create context at script start
local ctx = r.ImGui_CreateContext('Stretch Markers Curve')
local WINDOW_FLAGS = r.ImGui_WindowFlags_NoCollapse()

-- Settings variables
local settings = {
    curve_amount = 0, -- -1 to 1
    num_points = 8,   -- Number of intermediate points
    last_curve_amount = 0,
    last_num_points = 8
}

function calculateCurvePoints(numPoints, curveAmount, itemLength)
    local points = {}
    local totalPoints = numPoints + 2 -- Including start and end points
    
    for i = 0, totalPoints - 1 do
        local x = i / (totalPoints - 1)
        local y = x -- Linear by default
        
        if curveAmount ~= 0 then
            if curveAmount > 0 then
                -- Exponential curve
                y = math.pow(x, 1 + curveAmount * 2)
            else
                -- Logarithmic curve
                y = 1 - math.pow(1 - x, 1 + math.abs(curveAmount) * 2)
            end
        end
        
        -- Convert to actual position in item
        points[i + 1] = y * itemLength
    end
    
    return points
end

function applyStretchMarkers(item, take, curvePoints)
    -- Remove existing stretch markers
    r.DeleteTakeStretchMarkers(take, 0, r.GetTakeNumStretchMarkers(take))
    
    -- Get item properties
    local itemLength = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local playrate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    
    -- Add new stretch markers based on curve points
    for i, point in ipairs(curvePoints) do
        local sourcePos = point * playrate
        local pos = (i - 1) * (itemLength / (#curvePoints - 1))
        r.SetTakeStretchMarker(take, -1, pos, sourcePos)
    end
end

function processSelectedItems()
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock()
    
    for i = 0, r.CountSelectedMediaItems(0) - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local take = r.GetActiveTake(item)
        if take and not r.TakeIsMIDI(take) then
            local itemLength = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            local curvePoints = calculateCurvePoints(settings.num_points, settings.curve_amount, itemLength)
            applyStretchMarkers(item, take, curvePoints)
        end
    end
    
    r.Undo_EndBlock("Apply Stretch Marker Curve", -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end

function LoadSettings()
    settings.curve_amount = tonumber(r.GetExtState("StretchMarkerCurve", "curve_amount")) or 0
    settings.num_points = tonumber(r.GetExtState("StretchMarkerCurve", "num_points")) or 8
    settings.last_curve_amount = settings.curve_amount
    settings.last_num_points = settings.num_points
end

function SaveSettings()
    r.SetExtState("StretchMarkerCurve", "curve_amount", tostring(settings.curve_amount), true)
    r.SetExtState("StretchMarkerCurve", "num_points", tostring(settings.num_points), true)
end

function Loop()
    local visible, open = r.ImGui_Begin(ctx, 'Stretch Markers Curve', true, WINDOW_FLAGS)
    
    if visible then
        -- Curve amount slider
        r.ImGui_Text(ctx, string.format("Curve Amount: %.2f", settings.curve_amount))
        local curve_changed
        curve_changed, settings.curve_amount = r.ImGui_SliderDouble(ctx, "##curve", 
            settings.curve_amount, -1, 1, "")
        r.ImGui_Spacing(ctx)
        
        -- Number of points slider
        r.ImGui_Text(ctx, string.format("Number of Points: %d", settings.num_points))
        local points_changed
        points_changed, settings.num_points = r.ImGui_SliderInt(ctx, "##points", 
            settings.num_points, 2, 16, "")
        r.ImGui_Spacing(ctx)
        
        -- Preview
        local preview_size = 150
        r.ImGui_Dummy(ctx, preview_size, preview_size)
        local draw_list = r.ImGui_GetWindowDrawList(ctx)
        local pos_x, pos_y = r.ImGui_GetItemRectMin(ctx)
        
        -- Draw grid
        for i = 0, 4 do
            local x = pos_x + (preview_size * i / 4)
            local y = pos_y + (preview_size * i / 4)
            r.ImGui_DrawList_AddLine(draw_list, x, pos_y, x, pos_y + preview_size, 0x44FFFFFF)
            r.ImGui_DrawList_AddLine(draw_list, pos_x, y, pos_x + preview_size, y, 0x44FFFFFF)
        end
        
        -- Draw curve
        local points = calculateCurvePoints(settings.num_points, settings.curve_amount, 1)
        for i = 1, #points - 1 do
            local x1 = pos_x + preview_size * ((i-1) / (#points - 1))
            local y1 = pos_y + preview_size * (1 - points[i])
            local x2 = pos_x + preview_size * (i / (#points - 1))
            local y2 = pos_y + preview_size * (1 - points[i+1])
            r.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2, 0xFFFF7F00, 2)
            r.ImGui_DrawList_AddCircleFilled(draw_list, x1, y1, 3, 0xFFFF7F00)
        end
        -- Draw last point
        r.ImGui_DrawList_AddCircleFilled(draw_list, 
            pos_x + preview_size, 
            pos_y + preview_size * (1 - points[#points]), 
            3, 0xFFFF7F00)
        
        -- Apply changes if needed
        if curve_changed or points_changed or
           settings.last_curve_amount ~= settings.curve_amount or
           settings.last_num_points ~= settings.num_points then
            processSelectedItems()
            settings.last_curve_amount = settings.curve_amount
            settings.last_num_points = settings.num_points
            SaveSettings()
        end
        
        r.ImGui_End(ctx)
    end
    
    if open then
        r.defer(Loop)
    end
end

function Start()
    LoadSettings()
    Loop()
end

function Exit()
    SaveSettings()
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
        Start()
    else
        r.SetToggleCommandState(sectionID, cmdID, 0)
        r.RefreshToolbar2(sectionID, cmdID)
    end
end

r.atexit(Exit)
ToggleScript()