local r = reaper

function getDockState(hwnd)
    return r.Dock_GetWindowState(hwnd)
end

function closeDockerById(targetDocker)
    local mainHwnd = r.GetMainHwnd()
    
    -- Get array of windows
    local windowArray = r.new_array({})
    r.JS_Window_ArrayAllChild(mainHwnd, windowArray)
    
    -- Process each window
    for i = 0, windowArray.size-1 do
        local hwnd = r.JS_Window_HandleFromAddress(windowArray.table[i])
        local state = getDockState(hwnd)
        if state & 1 == 1 then -- Window is docked
            local dock = (state >> 8) & 0xF -- Get docker number (0-15)
            if dock == targetDocker then
                r.DockWindowClose(hwnd)
            end
        end
    end
end

closeDockerById(1) -- Close windows in docker 1