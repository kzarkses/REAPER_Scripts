-- @description Generate Brown Noise in time selection
-- @author Assistant
-- @version 1.0
-- @about
--   This script generates brown noise on the selected track within the time selection.

local function generateBrownNoise(buffer, sampleCount)
  local last = 0
  for i = 1, sampleCount do
    local white = math.random() * 2 - 1
    last = (last + (0.02 * white)) / 1.02
    buffer[i] = last * 3.5 -- Normalize to roughly -1 to 1
  end
end

local function createAudioFile(filePath, buffer, sampleRate)
  local file, err = io.open(filePath, "wb")
  if not file then
    reaper.ShowMessageBox("Failed to create audio file: " .. tostring(err), "Error", 0)
    return false
  end
  
  -- Write WAV header
  file:write("RIFF")
  file:write(string.pack("<I4", 36 + #buffer * 2)) -- File size
  file:write("WAVE")
  file:write("fmt ")
  file:write(string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, sampleRate, sampleRate * 2, 2, 16))
  file:write("data")
  file:write(string.pack("<I4", #buffer * 2)) -- Data size
  
  -- Write audio data
  for _, sample in ipairs(buffer) do
    file:write(string.pack("<h", math.floor(sample * 32767)))
  end
  
  file:close()
  return true
end

local function main()
  local start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if start_time == end_time then
    reaper.ShowMessageBox("Please set a time selection before running this script.", "Error", 0)
    return
  end

  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    reaper.ShowMessageBox("Please select a track before running this script.", "Error", 0)
    return
  end

  local sample_rate = 44100 -- You can adjust this if needed
  local duration = end_time - start_time
  local sample_count = math.floor(duration * sample_rate)

  local buffer = {}
  generateBrownNoise(buffer, sample_count)

  -- Create temporary WAV file with unique name
  local temp_file = string.format("%s/temp_brown_noise_%s.wav", reaper.GetProjectPath(""), os.time())
  if not createAudioFile(temp_file, buffer, sample_rate) then
    return
  end

  -- Insert audio item
  reaper.PreventUIRefresh(1)
  
  local new_item = reaper.AddMediaItemToTrack(track)
  reaper.SetMediaItemPosition(new_item, start_time, false)
  reaper.SetMediaItemLength(new_item, duration, false)
  
  local new_take = reaper.AddTakeToMediaItem(new_item)
  reaper.SetMediaItemTake_Source(new_take, reaper.PCM_Source_CreateFromFile(temp_file))
  reaper.UpdateItemInProject(new_item)
  
  reaper.PreventUIRefresh(-1)

  -- Clean up
  os.remove(temp_file)

  reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Generate Brown Noise", -1)
