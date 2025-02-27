function Main()
  local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
  if not take then return end

  local item = reaper.GetMediaItemTake_Item(take)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_start + item_length

  local retval, notes, ccs, sysex = reaper.MIDI_CountEvts(take)
  
  -- Obtenir la position du curseur d'édition
  local cursor_pos = reaper.GetCursorPosition()
  
  -- Calculer la position relative au début de l'item
  local note_start = cursor_pos - item_start
  
  -- Définir une longueur de note par défaut (par exemple, un quart de note)
  local ppq = reaper.MIDI_GetPPQPosFromProjTime(take, cursor_pos)
  local quarter_note_length = reaper.MIDI_GetPPQPosFromProjTime(take, cursor_pos + 1) - ppq
  
  local note_end = math.min(note_start + reaper.MIDI_GetProjTimeFromPPQPos(take, ppq + quarter_note_length) - cursor_pos, item_length)
  
  reaper.MIDI_InsertNote(take, false, false, ppq, ppq + quarter_note_length, 0, 60, 100, false)
  
  reaper.MIDI_Sort(take)
  reaper.UpdateArrange()
end

Main()
