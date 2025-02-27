-- @description Create Stretch Markers at Time Selection Intersections or Edit Cursor (Updated)
-- @author Assistant
-- @version 1.1
-- @about
--   This script creates stretch markers at the intersections of the time selection
--   with selected items if the edit cursor is at the start of an item. Otherwise,
--   it creates a single stretch marker at the edit cursor position.

function CreateStretchMarker(item, position)
  local take = reaper.GetActiveTake(item)
  if take then
    local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local relativePos = position - itemPos
    reaper.SetTakeStretchMarker(take, -1, relativePos)
  end
end

function Main()
  reaper.Undo_BeginBlock()
  
  local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local has_time_selection = start_time ~= end_time
  local edit_cursor_pos = reaper.GetCursorPosition()
  
  local num_selected_items = reaper.CountSelectedMediaItems(0)
  local markers_created = false
  
  local cursor_at_item_start = false
  
  -- Check if the edit cursor is at the start of any selected item
  for i = 0, num_selected_items - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    if math.abs(edit_cursor_pos - item_start) < 0.000001 then  -- Using a small threshold for floating point comparison
      cursor_at_item_start = true
      break
    end
  end
  
  if cursor_at_item_start and has_time_selection then
    -- Create stretch markers at time selection intersections
    for i = 0, num_selected_items - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      
      if start_time <= item_end and end_time >= item_start then
        local intersection_start = math.max(start_time, item_start)
        local intersection_end = math.min(end_time, item_end)
        
        CreateStretchMarker(item, intersection_start)
        if intersection_start ~= intersection_end then
          CreateStretchMarker(item, intersection_end)
        end
        markers_created = true
      end
    end
  else
    -- Create a single stretch marker at the edit cursor position
    for i = 0, num_selected_items - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      
      if edit_cursor_pos >= item_start and edit_cursor_pos <= item_end then
        CreateStretchMarker(item, edit_cursor_pos)
        markers_created = true
        break
      end
    end
  end
  
  if markers_created then
    reaper.UpdateTimeline()
  end
  
  reaper.Undo_EndBlock("Create Stretch Markers", -1)
end

Main()
