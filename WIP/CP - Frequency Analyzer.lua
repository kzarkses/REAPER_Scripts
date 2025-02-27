-- Frequency Analyzer Script for REAPER
-- Auteur: Claude
-- License: MIT

local ctx = reaper.ImGui_CreateContext('Frequency Analyzer')
local BUFFER_SIZE = 4096
local windowSize = 2048
local sampleRate = reaper.GetProjectTimeSignature2(0)
local smoothing = 0.8
local floorDB = -90
local ceilDB = 0
local lastPeaks = {}

-- Configuration des options de fenêtrage
local windowType = 1  -- 0: Rectangular, 1: Hanning, 2: Hamming, 3: Blackman
local windowBuffer = {}

function createWindow()
  for i = 0, windowSize - 1 do
    local x = i / (windowSize - 1)
    if windowType == 0 then
      windowBuffer[i] = 1.0
    elseif windowType == 1 then
      windowBuffer[i] = 0.5 - 0.5 * math.cos(2 * math.pi * x)
    elseif windowType == 2 then
      windowBuffer[i] = 0.54 - 0.46 * math.cos(2 * math.pi * x)
    else
      windowBuffer[i] = 0.42 - 0.5 * math.cos(2 * math.pi * x) + 0.08 * math.cos(4 * math.pi * x)
    end
  end
end

function getAudioData()
  local master = reaper.GetMasterTrack(0)
  local curpos = reaper.GetPlayPosition()
  
  -- Créer un audio accessor
  local accessor = reaper.CreateTrackAudioAccessor(master)
  if not accessor then return lastPeaks end
  
  -- Obtenir les samples
  local buffer = reaper.new_array(BUFFER_SIZE)
  reaper.GetAudioAccessorSamples(accessor, sampleRate, 1, curpos, BUFFER_SIZE, buffer)
  reaper.DestroyAudioAccessor(accessor)
  
  -- Convertir en tableau Lua
  local samples = {}
  for i = 1, BUFFER_SIZE do
    samples[i] = buffer[i]
  end
  
  lastPeaks = samples
  return samples
end

function calculateFFT(samples)
  local spectrum = {}
  local fftData = {}
  
  -- Appliquer la fenêtre
  for i = 1, windowSize do
    fftData[i] = (samples[i] or 0) * (windowBuffer[i-1] or 1.0)
  end
  
  -- Calcul basique de FFT
  for k = 1, windowSize/2 do
    local real, imag = 0, 0
    for n = 1, windowSize do
      local angle = 2 * math.pi * (n-1) * (k-1) / windowSize
      real = real + (fftData[n] or 0) * math.cos(angle)
      imag = imag + (fftData[n] or 0) * math.sin(angle)
    end
    spectrum[k] = math.sqrt(real*real + imag*imag)
  end
  
  return spectrum
end

function drawSpectrum(spectrum)
  if not reaper.ImGui_BeginChild then return end
  
  local w, h = reaper.ImGui_GetWindowSize(ctx)
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  
  -- Fond
  reaper.ImGui_DrawList_AddRectFilled(draw_list, 0, 0, w, h, 0x1A1A1AFF)
  
  -- Grille de fréquences
  local freqs = {20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000}
  for _, freq in ipairs(freqs) do
    local x = w * math.log(freq/20) / math.log(20000/20)
    reaper.ImGui_DrawList_AddLine(draw_list, x, 0, x, h, 0x333333FF)
    reaper.ImGui_DrawList_AddText(draw_list, x-15, h-20, 0x888888FF, tostring(freq))
  end
  
  -- Spectre
  local prev_x, prev_y
  for i = 1, #spectrum do
    local freq = i * sampleRate / windowSize
    if freq > 20 and freq < 20000 then
      local mag = spectrum[i]
      if mag and mag > 0 then
        mag = math.max(floorDB, math.min(ceilDB, 20 * math.log10(mag)))
        
        local x = w * math.log(freq/20) / math.log(20000/20)
        local y = h * (ceilDB - mag) / (ceilDB - floorDB)
        
        if prev_x and x < w then
          reaper.ImGui_DrawList_AddLine(draw_list, prev_x, prev_y, x, y, 0x00FF00FF)
        end
        prev_x, prev_y = x, y
      end
    end
  end
end

function loop()
  if reaper.ImGui_Begin(ctx, 'Frequency Analyzer', true) then
    local samples = getAudioData()
    if samples and #samples > 0 then
      local spectrum = calculateFFT(samples)
      drawSpectrum(spectrum)
    end
    reaper.ImGui_End(ctx)
  end
  reaper.defer(loop)
end

-- Initialisation
createWindow()
reaper.defer(loop)
