function Main()
    reaper.ShowConsoleMsg("Starting script\n")
    local title = reaper.JS_Localize("Media Explorer", "common")
    local hwndMediaExplorer = reaper.JS_Window_Find(title, true)
    
    if not hwndMediaExplorer then 
        reaper.ShowConsoleMsg("Media Explorer not found\n")
        return
    end
    
    reaper.ShowConsoleMsg("Found Media Explorer\n")
    
    -- Try different approach for finding ListView
    local hwndChild = reaper.JS_Window_GetChild(hwndMediaExplorer, 0)
    if not hwndChild then
        reaper.ShowConsoleMsg("First child not found\n")
        return
    end
    reaper.ShowConsoleMsg("Found first child\n")
    
    local className = reaper.JS_Window_GetClassName(hwndChild)
    reaper.ShowConsoleMsg("Child class: " .. tostring(className) .. "\n")
    
    -- Try to list all child windows
    local i = 0
    while true do
        local child = reaper.JS_Window_GetChild(hwndMediaExplorer, i)
        if not child then break end
        
        local class = reaper.JS_Window_GetClassName(child)
        local id = reaper.JS_Window_GetID(child)
        reaper.ShowConsoleMsg(string.format("Child %d: Class=%s, ID=%s\n", i, tostring(class), tostring(id)))
        i = i + 1
    end
end

reaper.ClearConsole()
Main()