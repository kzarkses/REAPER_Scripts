-- @description Auto Detect Running Scripts
-- @version 1.0
-- @author Claude

local r = reaper
local config = {
    last_state = {},
    enabled = true
}

function LoadConfig()
    local saved = r.GetExtState("AutoDetectStartup", "config")
    if saved ~= "" then
        local success, data = pcall(function() return load("return " .. saved)() end)
        if success and data then
            config = data
        end
    end
    
    if config.enabled and #config.last_state > 0 then
        for _, command_id in ipairs(config.last_state) do
            r.Main_OnCommand(command_id, 0)
        end
    end
end

function SaveConfig()
    local str = "{"
    
    -- Save enabled state
    str = str .. string.format("enabled=%s,", tostring(config.enabled))
    
    -- Save last state array
    str = str .. "last_state={"
    for i, cmd in ipairs(config.last_state) do
        str = str .. tostring(cmd)
        if i < #config.last_state then str = str .. "," end
    end
    str = str .. "}}"
    
    r.SetExtState("AutoDetectStartup", "config", str, true)
end

function ScanRunningScripts()
    local running = {}
    local section = r.GetResourcePath() .. "/Scripts/"
    
    -- Liste statique des IDs de commandes potentielles
    for i = 1, 65535 do  -- Plage raisonnable d'IDs de commandes
        local state = r.GetToggleCommandState(i)
        local _, name = r.GetActionName(i, 0)
        if state == 1 and name:match("^Script:") then
            table.insert(running, i)
        end
    end
    return running
end

function ShowStatus()
    local ctx = r.ImGui_CreateContext('Auto Detect Scripts Status')
    
    local function loop()
        local visible, open = r.ImGui_Begin(ctx, 'Auto Detect Scripts', true)
        
        if visible then
            local changed
            changed, config.enabled = r.ImGui_Checkbox(ctx, "Enable auto-start of last session", config.enabled)
            if changed then SaveConfig() end
            
            r.ImGui_Separator(ctx)
            
            r.ImGui_Text(ctx, "Currently running scripts:")
            local running = ScanRunningScripts()
            for _, cmd in ipairs(running) do
                local _, name = r.GetActionName(cmd, 0)
                r.ImGui_BulletText(ctx, name)
            end
            
            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, "Scripts from last session:")
            for _, cmd in ipairs(config.last_state) do
                local _, name = r.GetActionName(cmd, 0)
                r.ImGui_BulletText(ctx, name)
            end
            
            r.ImGui_End(ctx)
        end
        
        if open then
            r.defer(loop)
        end
    end
    
    r.defer(loop)
end

function Start()
    LoadConfig()
    ShowStatus()
end

function SaveCurrentState()
    config.last_state = ScanRunningScripts()
    SaveConfig()
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
    SaveCurrentState()
    local _, _, sectionID, cmdID = r.get_action_context()
    r.SetToggleCommandState(sectionID, cmdID, 0)
    r.RefreshToolbar2(sectionID, cmdID)
end

r.atexit(Exit)
ToggleScript()