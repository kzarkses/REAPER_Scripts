local r = reaper

-- Create context at script start
local ctx = r.ImGui_CreateContext('Startup Action Manager')

-- Configuration
local WINDOW_WIDTH = 1200
local WINDOW_HEIGHT = 600
local SECTION_WIDTH = (WINDOW_WIDTH / 3) - 20
local LIST_HEIGHT = WINDOW_HEIGHT - 100
local CHILD_FLAGS = r.ImGui_WindowFlags_None()

-- State variables
local templates = {}
local selected_template = nil
local search_text = ""
local current_action = ""
local filtered_actions = {}
local all_actions = {}
local selected_section = "Main"

-- Function to create a custom action
local function create_custom_action(name, commands)
    -- Generate a unique ID for the custom action
    local custom_id = "CUSTOM_" .. tostring(os.time())
    
    -- Create the custom action section in reaper-kb.ini
    local kb_file = r.GetResourcePath() .. "/reaper-kb.ini"
    local file = io.open(kb_file, "a")
    if file then
        file:write(string.format("\n[Custom Action %s]\n", custom_id))
        for i, cmd in ipairs(commands) do
            file:write(string.format("MIDI %d %d\n", i-1, cmd))
        end
        file:close()
    end
    
    return custom_id
end

-- Function to get command list from data
local function parse_command_list(data, section)
    local commands = {}
    for line in data:gmatch("[^\r\n]+") do
        local cmd_section, cmd_id, cmd_name = line:match("(%w+%s*%w*)\t(%d+)\t(.+)")
        if cmd_section and cmd_id and cmd_name and cmd_section:match(section) then
            table.insert(commands, {
                section = cmd_section,
                id = tonumber(cmd_id),
                name = cmd_name
            })
        end
    end
    return commands
end

-- Function to scan project templates directory
local function scan_templates()
    local templates_path = r.GetResourcePath() .. "/ProjectTemplates"
    local template_list = {}
    
    local i = 0
    repeat
        local file = r.EnumerateFiles(templates_path, i)
        if file then
            if file:match("%.RPP$") or file:match("%.RPP%-bak$") then
                table.insert(template_list, file)
            end
        end
        i = i + 1
    until not file
    
    return template_list
end

-- Function to filter actions based on search text
local function filter_actions(search)
    if search == "" then return all_actions end
    
    local filtered = {}
    local lower_search = search:lower()
    
    for _, action in ipairs(all_actions) do
        if action.name:lower():find(lower_search, 1, true) then
            table.insert(filtered, action)
        end
    end
    
    return filtered
end

-- Function to save template association
local function save_template_association(template, action_id)
    r.SetProjExtState(0, "StartupManager", template, action_id)
end

-- Function to load template association
local function load_template_association(template)
    local retval, str = r.GetProjExtState(0, "StartupManager", template)
    return retval > 0 and str or ""
end

-- Function to set startup action for template
local function set_startup_action(template, action)
    -- Create a custom action with the selected command
    local custom_id = create_custom_action("Startup_" .. template, {action.id})
    
    -- Save the association
    save_template_association(template, custom_id)
    
    -- Update current action display
    current_action = action.id .. ": " .. action.name
end

function Init()
    -- Load project templates
    templates = scan_templates()
    
    -- Parse commands from the data
    local mex_actions = parse_command_list(r.GetExtState("StartupManager", "MediaExplorerCommands") or "", "Media Explorer")
    local midi_actions = parse_command_list(r.GetExtState("StartupManager", "MIDIEditorCommands") or "", "MIDI Editor")
    
    -- Combine all actions
    all_actions = {}
    for _, action in ipairs(mex_actions) do
        table.insert(all_actions, action)
    end
    for _, action in ipairs(midi_actions) do
        table.insert(all_actions, action)
    end
    
    filtered_actions = all_actions
end

function Loop()
    r.ImGui_SetNextWindowSize(ctx, WINDOW_WIDTH, WINDOW_HEIGHT, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'Startup Action Manager', true)
    
    if visible then
        -- Left panel - Templates
        r.ImGui_BeginChild(ctx, "Templates", SECTION_WIDTH, 0, CHILD_FLAGS)
        r.ImGui_Text(ctx, "Project Templates")
        r.ImGui_Separator(ctx)
        
        for i, template in ipairs(templates) do
            if r.ImGui_Selectable(ctx, template, template == selected_template) then
                selected_template = template
                -- Load associated action
                current_action = load_template_association(template)
            end
        end
        r.ImGui_EndChild(ctx)
        
        r.ImGui_SameLine(ctx)
        
        -- Middle panel - Current Action
        r.ImGui_BeginChild(ctx, "CurrentAction", SECTION_WIDTH, 0, CHILD_FLAGS)
        r.ImGui_Text(ctx, "Current Startup Action")
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, current_action ~= "" and current_action or "No action set")
        r.ImGui_EndChild(ctx)
        
        r.ImGui_SameLine(ctx)
        
        -- Right panel - Action Search
        r.ImGui_BeginChild(ctx, "ActionSearch", SECTION_WIDTH, 0, CHILD_FLAGS)
        r.ImGui_Text(ctx, "Search Actions")
        r.ImGui_Separator(ctx)
        
        -- Section selector
        if r.ImGui_BeginCombo(ctx, "Section", selected_section) then
            if r.ImGui_Selectable(ctx, "Main", selected_section == "Main") then 
                selected_section = "Main" 
            end
            if r.ImGui_Selectable(ctx, "Media Explorer", selected_section == "Media Explorer") then 
                selected_section = "Media Explorer" 
            end
            if r.ImGui_Selectable(ctx, "MIDI Editor", selected_section == "MIDI Editor") then 
                selected_section = "MIDI Editor" 
            end
            r.ImGui_EndCombo(ctx)
        end
        
        -- Search input
        local search_changed
        search_changed, search_text = r.ImGui_InputText(ctx, "##Search", search_text)
        if search_changed then
            filtered_actions = filter_actions(search_text)
        end
        
        -- Actions list
        r.ImGui_BeginChild(ctx, "Actions##list", -1, -r.ImGui_GetFrameHeightWithSpacing(ctx), CHILD_FLAGS)
        for _, action in ipairs(filtered_actions) do
            if action.section:match(selected_section) then
                if r.ImGui_Selectable(ctx, action.id .. ": " .. action.name) and selected_template then
                    set_startup_action(selected_template, action)
                end
            end
        end
        r.ImGui_EndChild(ctx)
        
        r.ImGui_EndChild(ctx)
        
        r.ImGui_End(ctx)
    end
    
    if open then
        r.defer(Loop)
    end
end

function Exit()
    local _, _, sectionID, cmdID = r.get_action_context()
    r.SetToggleCommandState(sectionID, cmdID, 0)
    r.RefreshToolbar2(sectionID, cmdID)
end

function Start()
    Init()
    Loop()
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