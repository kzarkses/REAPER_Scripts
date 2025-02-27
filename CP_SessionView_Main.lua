local r = reaper
local session = {}

dofile(r.GetResourcePath() .. "/Scripts/CP_Scripts/CP_SessionView_State.lua")
dofile(r.GetResourcePath() .. "/Scripts/CP_Scripts/CP_SessionView_Grid.lua")
dofile(r.GetResourcePath() .. "/Scripts/CP_Scripts/CP_SessionView_Transport.lua")
dofile(r.GetResourcePath() .. "/Scripts/CP_Scripts/CP_SessionView_UI.lua")

local ctx = r.ImGui_CreateContext('Session View')
local WINDOW_FLAGS = r.ImGui_WindowFlags_NoCollapse()

function session.Init()
    State.Init()
    Grid.Init()
    Transport.Init()
    UI.Init(ctx)
    session.Loop()
end

function session.Loop()
    local visible, open = r.ImGui_Begin(ctx, 'Session View', true, WINDOW_FLAGS)
    if visible then
        Grid.Update()
        UI.DrawToolbar(ctx)
        UI.DrawGrid(ctx, Grid.GetData())
        Transport.Update()
        r.ImGui_End(ctx)
    end
    
    if open then
        r.defer(session.Loop)
    end
end

function session.Exit()
    local _, _, sectionID, cmdID = r.get_action_context()
    r.SetToggleCommandState(sectionID, cmdID, 0)
    r.RefreshToolbar2(sectionID, cmdID)
    State.Save()
end

function session.Toggle()
    local _, _, sectionID, cmdID = r.get_action_context()
    local state = r.GetToggleCommandState(cmdID)
    
    if state == -1 or state == 0 then
        r.SetToggleCommandState(sectionID, cmdID, 1)
        r.RefreshToolbar2(sectionID, cmdID)
        session.Init()
    else
        r.SetToggleCommandState(sectionID, cmdID, 0)
        r.RefreshToolbar2(sectionID, cmdID)
    end
end

r.atexit(session.Exit)
session.Toggle()