# REAPER Custom Scripts Collection (CP Scripts)

This repository contains a collection of custom scripts for REAPER Digital Audio Workstation. These scripts enhance workflow efficiency and provide additional functionality beyond REAPER's native capabilities.

## Requirements

- REAPER 7.27 or newer
- SWS Extension
- js_ReaScriptAPI Extension

## Installation

1. Download the scripts from this repository
2. Place them in your REAPER scripts directory:
   - Windows: `%APPDATA%\REAPER\Scripts\CP_Scripts\`
   - macOS: `~/Library/Application Support/REAPER/Scripts/CP_Scripts/`
   - Linux: `~/.config/REAPER/Scripts/CP_Scripts/`
3. In REAPER, go to Actions → Action List and use the "ReaScript: Load" button to add the scripts
4. Optionally assign keyboard shortcuts to your most frequently used scripts

## Script Categories

### Media Management

- **CP_MediaPropertiesToolbar** - Display and edit media item properties in a toolbar
- **CP_MediaSourceInfo** - Displays detailed information about media sources with customization
- **CP_UpdateMediaSource_All_Down/Up** - Update all media sources to previous/next versions
- **CP_UpdateMediaSource_Single_Down/Up** - Update selected media sources to previous/next versions
- **CP_CategorizeMediaUCS** - Categorize media files using Universal Category System codes

### Project Management

- **CP_CreateProjectVersion** - Create a new version of the current project
- **CP_CreateProjectAlternativeVersion** - Create an alternative version of the current project
- **CP_ProjectNoteEditor** - Edit project notes with rich text formatting
- **CP_AutoDetectStartupActions** - Automatically detect and run scripts at startup
- **CP_IncrementVersionAndSync** - Increment project version and sync media sources

### Track and Item Manipulation

- **CP_DuplicateTrackForSoundDesign_GUI** - Create duplicate tracks with custom parameters for sound design
- **CP_AutoColorTrackHierarchy_Darken/Lighten** - Automatically color child tracks based on parent track colors
- **CP_AutoColorRegionFromTrack** - Match region colors to corresponding tracks
- **CP_AutoArmVSTiTrack** - Automatically arms tracks with instrument plugins when selected
- **CP_AddStretchMarkersToSelectedItems_GUI** - Add and manipulate stretch markers with GUI controls
- **CP_SyncAudioItemWithAutomation_GUI** - Synchronize audio items with automation items
- **CP_TakeEnvelopeModifier** - Apply LFO patterns to take envelopes

### Generation and Processing

- **CP_GenerateWhiteNoise** - Generate white noise in time selection
- **CP_GeneratePinkNoise** - Generate pink noise in time selection
- **CP_GenerateBrownNoise** - Generate brown noise in time selection
- **CP_GenerateTone** - Generate various waveforms with customizable parameters
- **CP_GranularSynthesis** - Apply granular synthesis processing to audio items

### Multimedia Tools

- **CP_StopMotion** - Control frame rate for stop motion animation
- **CP_StopMotionOnionSkin_GUI** - Apply onion skin effect for stop motion animation
- **CP_StopMotionOBS** - Control OBS for stop motion camera capture
- **CP_OBSVirtualCam** - Interface with OBS Virtual Camera
- **CP_OBSPreview** - Import OBS live video into REAPER

### Performance Tools

- **CP_SessionView_Main** - Ableton Live-style session view for REAPER
- **CP_BPMControlSlider_GUI** - BPM control with slider and presets
- **CP_AutoPlaySelectedItems** - Automatically play items when selected

## Naming Convention

Scripts follow a naming convention for easy identification:

`CP_Action_Context_Variant`

- **CP**: Personal prefix
- **Action**: Main script action in CamelCase (e.g., UpdateMediaSource, AutoColorTrackHierarchy)
- **Context**: Application context if the action repeats across different contexts (e.g., Selected, All)
- **Variant**: Additional modifiers (_GUI, _Up, _Down, _Lighten)

Examples:
- CP_UpdateMediaSource_Selected_Down (Action with context and variant)
- CP_AutoColorTrackHierarchy_Lighten (Action with variant)
- CP_BPMControlSlider_GUI (Action with GUI)
- CP_AutoColorRegionFromTrack (Unique action)

## License

These scripts are provided under the MIT License. See the LICENSE file for details.

## Contributing

Contributions, bug reports, and feature requests are welcome. Please open an issue or submit a pull request.
