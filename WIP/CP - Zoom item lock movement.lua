-- @description Zoom to selected item and lock view (Corrected)
-- @author Assistant
-- @version 1.2
-- @about
--   This script zooms to the selected item, making it fill the entire arrange view,
--   and temporarily prevents horizontal and vertical scrolling. It has an ON/OFF toggle.

local origStart, origEnd, origTop, origBottom
local isActive = false

function saveCurrentView()
  origStart, origEnd = reaper.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
  _, origTop, origBottom = reaper.JS_Window_GetScrollInfo(reaper.GetMainHwnd(), "v")
end

function restoreView()
  reaper.GetSet_ArrangeView2(0, true, 0, 0, origStart, origEnd)
  reaper.JS_Window_SetScrollPos(reaper.GetMainHwnd(), "v", origTop)
  reaper.UpdateArrange()
end

function preventScrolling()
  if isActive then
    local start, end_ = reaper.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
    reaper.GetSet_ArrangeView2(0, true, 0, 0, start, end_)
    reaper.defer(preventScrolling)
  end
end

function zoomToItem()
  local item = reaper.GetSelectedMediaItem(0, 0)
  if item then
    local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local itemTrack = reaper.GetMediaItem_Track(item)
    
    -- Zoom horizontally
    reaper.GetSet_ArrangeView2(0, true, 0, 0, itemStart, itemEnd)
    
    -- Zoom vertically
    local trackY = reaper.GetMediaTrackInfo_Value(itemTrack, "I_TCPY")
    local trackH = reaper.GetMediaTrackInfo_Value(itemTrack, "I_TCPH")
    local windowH = reaper.GetAppVersion():match('OSX') and 35 or 25 -- Adjust for title bar
    reaper.JS_Window_SetScrollPos(reaper.GetMainHwnd(), "v", trackY - windowH)
    
    reaper.SetEditCurPos(itemStart, true, false)  -- Move edit cursor without seeking
    reaper.UpdateArrange()
  end
end

function Main()
  if not isActive then
    local item = reaper.GetSelectedMediaItem(0, 0)
    if item then
      reaper.Undo_BeginBlock()
      saveCurrentView()
      zoomToItem()
      reaper.Undo_EndBlock("Zoom to item and lock view", -1)
      isActive = true
      reaper.defer(preventScrolling)
    else
      reaper.ShowMessageBox("Please select an item before running the script.", "No item selected", 0)
    end
  else
    reaper.Undo_BeginBlock()
    restoreView()
    reaper.Undo_EndBlock("Restore view", -1)
    isActive = false
  end
end

function Exit()
  if isActive then
    restoreView()
  end
  reaper.SetToggleCommandState(sectionID, cmdID, 0)
  reaper.RefreshToolbar2(sectionID, cmdID)
end

-- Get the command ID for this script
_, _, sectionID, cmdID = reaper.get_action_context()

-- Check if the script is already running
if reaper.GetToggleCommandState(cmdID) == 0 then
  reaper.SetToggleCommandState(sectionID, cmdID, 1)
  reaper.RefreshToolbar2(sectionID, cmdID)
  
  reaper.atexit(Exit)
  Main()
else
  -- If the script is already running, toggle it off
  Exit()
end
