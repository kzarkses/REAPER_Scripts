-- Script pour modifier les modes de pitch/stretch et sous-modes dans REAPER
-- Nécessite ReaImGui et SWS Extension

local r = reaper

-- Charger ReaImGui
if not reaper.APIExists("ImGui_CreateContext") then
  r.MB("Veuillez installer ReaImGui", "Erreur", 0)
  return
end

local ctx = r.ImGui_CreateContext('Pitch/Stretch Mode Selector')

-- Structure des modes et sous-modes
local modes = {
  {name = "Élastique", submodes = {"Pro", "Efficient", "SOLOIST Monophonic", "SOLOIST Speech"}, base_index = 0},
  {name = "IPlug", submodes = {"", "Linear"}, base_index = 5},
  {name = "REAPER", submodes = {"Défaut", "Proponential", "Préservant la hauteur", "Stretch multi-canal"}, base_index = 7},
  {name = "SoundTouch", submodes = {"Défaut", "Synchronisé"}, base_index = 11},
  {name = "Rubber Band", submodes = {"Défaut", "Basse latence"}, base_index = 13},
  {name = "Rrreeeaaa", submodes = {"Simple", "Préservant la hauteur"}, base_index = 15},
  {name = "DIRAC", submodes = {"LE", "DIRAC 3"}, base_index = 17},
}

-- Fonction pour obtenir le mode et sous-mode actuels
local function getCurrentModeAndSubmode(take)
  local mode_value = r.GetMediaItemTakeInfo_Value(take, "I_PITCHMODE")
  for i, mode in ipairs(modes) do
    if mode_value >= mode.base_index and mode_value < mode.base_index + #mode.submodes then
      return i, mode_value - mode.base_index + 1
    end
  end
  return 1, 1  -- Valeur par défaut si non trouvé
end

-- Fonction pour définir le nouveau mode
local function setMode(take, modeIndex, submodeIndex)
  local new_value = modes[modeIndex].base_index + submodeIndex - 1
  r.SetMediaItemTakeInfo_Value(take, "I_PITCHMODE", new_value)
  r.UpdateItemInProject(r.GetMediaItemTake_Item(take))
end

-- Fonction pour créer une chaîne compatible avec ImGui_Combo
local function createComboString(items)
  return table.concat(items, '\0') .. '\0\0'
end

-- Fonction principale
local function main()
  local window_flags = r.ImGui_WindowFlags_AlwaysAutoResize()
  local modeNames = createComboString(table.map(modes, function(m) return m.name end))
  
  local function loop()
    r.ImGui_SetNextWindowSize(ctx, 300, 400, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'Pitch/Stretch Mode Selector', true, window_flags)
    if visible then
      r.ImGui_Text(ctx, "Sélectionnez un élément audio et choisissez le mode :")
      
      local item = r.GetSelectedMediaItem(0, 0)
      if item then
        local take = r.GetActiveTake(item)
        if take and not r.TakeIsMIDI(take) then
          local currentMode, currentSubmode = getCurrentModeAndSubmode(take)
          
          -- Sélection du mode principal
          local changed, newMode = r.ImGui_Combo(ctx, "Mode", currentMode - 1, modeNames)
          if changed then
            currentMode = newMode + 1
            currentSubmode = 1  -- Réinitialiser le sous-mode lors du changement de mode principal
          end
          
          -- Sélection du sous-mode
          r.ImGui_Spacing(ctx)
          r.ImGui_Text(ctx, "Sous-mode :")
          local submodes = modes[currentMode].submodes
          local submodeNames = createComboString(submodes)
          changed, newSubmode = r.ImGui_Combo(ctx, "##Submode", currentSubmode - 1, submodeNames)
          
          if changed then
            currentSubmode = newSubmode + 1
          end
          
          -- Appliquer les changements
          if changed then
            setMode(take, currentMode, currentSubmode)
          end
        else
          r.ImGui_Text(ctx, "Veuillez sélectionner un élément audio valide.")
        end
      else
        r.ImGui_Text(ctx, "Aucun élément sélectionné.")
      end
      
      r.ImGui_End(ctx)
    end
    
    if open then
      r.defer(loop)
    end
  end

  r.defer(loop)
end

-- Fonction utilitaire pour mapper un tableau
table.map = function(t, f)
  local mapped = {}
  for i, v in ipairs(t) do
    mapped[i] = f(v)
  end
  return mapped
end

-- Lancer le script
main()
