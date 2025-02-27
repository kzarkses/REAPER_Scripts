-- Configuration
local ADD_STRETCH_MARKERS = true  -- Mettre à false pour désactiver les stretch markers

function generateSineWave(samplerate, duration, frequency, db)
  local buffer = {}
  local amplitude = 10^(db/20)  -- Convertir dB en amplitude linéaire
  for i = 1, samplerate * duration do
    buffer[i] = amplitude * math.sin(2 * math.pi * frequency * (i-1) / samplerate)
  end
  return buffer
end

function Main()
  -- Obtenir la sélection temporelle
  local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if start_time == end_time then
    reaper.ShowMessageBox("Veuillez faire une sélection temporelle.", "Erreur", 0)
    return
  end

  -- Obtenir la piste sélectionnée
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    reaper.ShowMessageBox("Veuillez sélectionner une piste.", "Erreur", 0)
    return
  end

  -- Paramètres du son
  local frequency = 440  -- 440 Hz (La4)
  local samplerate = 44100
  local duration = end_time - start_time
  local channels = 1  -- Mono
  local db = -10  -- -10dB
  local fadeDuration = 0.01  -- 10 ms
  
  -- Générer l'onde sinusoïdale
  local audio_data = generateSineWave(samplerate, duration, frequency, db)
  
  -- Créer un fichier audio temporaire avec un nom unique
  local temp_file = reaper.GetProjectPath() .. "/temp_sine_wave_" .. os.time() .. ".wav"
  local file = io.open(temp_file, "wb")
  if file then
    -- Écrire l'en-tête WAV
    file:write("RIFF", string.char(0,0,0,0), "WAVE", "fmt ", 
               string.char(16,0,0,0,1,0,channels,0), 
               string.pack("<I4I4I2I2", samplerate, samplerate * channels * 2, channels * 2, 16),
               "data", string.char(0,0,0,0))
    
    -- Écrire les données audio
    for _, sample in ipairs(audio_data) do
      local value = math.floor(sample * 32767)
      file:write(string.pack("<h", value))
    end
    
    file:close()
    
    -- Créer un nouvel item dans la time selection
    local new_item = reaper.AddMediaItemToTrack(track)
    reaper.SetMediaItemPosition(new_item, start_time, false)
    reaper.SetMediaItemLength(new_item, duration, false)
    
    -- Ajouter le fichier audio à l'item
    local new_take = reaper.AddTakeToMediaItem(new_item)
    local source = reaper.PCM_Source_CreateFromFile(temp_file)
    reaper.SetMediaItemTake_Source(new_take, source)
    
    -- Ajouter les fades à l'item
    reaper.SetMediaItemInfo_Value(new_item, "D_FADEINLEN", fadeDuration)
    reaper.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", fadeDuration)
    
    -- Ajouter les stretch markers si l'option est activée
    if ADD_STRETCH_MARKERS then
      reaper.SetTakeStretchMarker(new_take, -1, 0)
      reaper.SetTakeStretchMarker(new_take, -1, duration)
    end
    
    -- Supprimer le fichier temporaire
    os.remove(temp_file)
    
    -- Forcer la mise à jour de l'affichage
    reaper.UpdateArrange()
    reaper.UpdateTimeline()
    reaper.TrackList_AdjustWindows(false)
    reaper.SetMediaItemSelected(new_item, true)
    reaper.Main_OnCommand(40047, 0) -- Build any missing peak files
    reaper.SetMediaItemSelected(new_item, false)
  else
    reaper.ShowMessageBox("Impossible de créer le fichier audio temporaire.", "Erreur", 0)
  end
end

reaper.Undo_BeginBlock()
Main()
reaper.Undo_EndBlock("Générer ton à -10dB avec fades et stretch markers", -1)
