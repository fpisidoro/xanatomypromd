# StandaloneMPRView Architecture - Instructions for Next Session

## Current State (MILESTONE ACHIEVED)
The app now uses a fully modular StandaloneMPRView architecture where each MPR view is completely self-contained yet properly synchronized.

## ⚠️ IMPORTANT: Multi-Dataset Support Required
**See MULTI_DATASET_ARCHITECTURE.md for critical enhancement needed:**
- Must support multiple CT scans simultaneously (male/female/test)
- Each dataset needs independent coordinate system
- Each dataset needs independent window level sync
- Anatomy selection affects all datasets (different ROIs, same structure)

This is NOT yet implemented but is a critical requirement for the production app.

## Key Files to Understand

### 1. StandaloneMPRView (`SwiftUI/Components/StandaloneMPRView.swift`)
- **Purpose**: A completely self-contained MPR view that can function independently
- **Key Features**:
  - Takes all needed parameters (plane, coordinateSystem, sharedState, data)
  - Handles its own gestures locally (tap, drag, zoom)
  - Maintains local state for zoom and pan
  - Automatically syncs appropriate elements through shared objects

### 2. SharedViewingState (`SwiftUI/Components/StandaloneMPRView.swift`)
- **Purpose**: Manages properties that need to sync across all views
- **Synchronized Properties**:
  - `windowLevel`: CT windowing (always synced)
  - `crosshairSettings`: Crosshair visibility/appearance
  - `roiSettings`: ROI overlay settings
  - `selectedROI`: Currently selected anatomical structure
- **Important**: Zoom and pan are NOT synchronized (local to each view)

### 3. XAnatomyProV2MainView (`SwiftUI/XAnatomyProV2MainView.swift`)
- **Purpose**: Main app view using the modular architecture
- **Current Implementation**:
  - Layout modes: single, double, triple, quad
  - Dynamic layout switching
  - Uses StandaloneMPRView for each panel
  - Shares coordinateSystem and sharedState across all views

## How Synchronization Works

### Current Implementation (Single Dataset):

#### Synchronized Elements:
1. **Crosshairs**: Via `DICOMCoordinateSystem.currentWorldPosition`
   - When user drags crosshair in one view, it updates world position
   - All views automatically reflect new position

2. **Window Levels**: Via `SharedViewingState.windowLevel`
   - Changing window level updates all views simultaneously
   - Ensures consistent tissue visualization

3. **ROI Visibility**: Via `SharedViewingState.roiSettings`
   - ROI on/off state shared
   - Each view draws ROI in correct orientation

#### Independent Elements:
1. **Zoom**: Each view has `localZoom` state
2. **Pan**: Each view has `localPan` state  
3. **Slice Scrolling**: Updates coordinate system but each view responds independently

### Future Multi-Dataset Synchronization (See MULTI_DATASET_ARCHITECTURE.md):

#### Within Same Dataset:
- **Crosshairs**: Only sync between views showing same dataset (male/female/test)
- **Window Levels**: Only sync between views showing same dataset
- **Slice Navigation**: Only affects views of same dataset

#### Across All Datasets:
- **Anatomy Selection**: Selecting "Liver" highlights it in ALL datasets
  - Different ROI geometries in male vs female
  - Same anatomical structure
  - Handles sex-specific structures (prostate/uterus)

## Gesture Handling

Each StandaloneMPRView handles gestures independently:
```swift
- Tap: Future ROI selection
- Vertical Drag: Slice navigation (updates coordinateSystem)
- Horizontal Drag: Pan view locally
- Pinch: Zoom view locally
- Slider: Slice navigation (alternative to drag)
```

## Adding New Views

### Current Implementation:
To add a new view type (e.g., 3D view, anatomy list):

1. Create the view component
2. Add it to a layout (e.g., in quad view's 4th slot)
3. Pass the shared objects if needed:
   - `coordinateSystem` for spatial coordination
   - `sharedState` for synchronized settings
   - `volumeData` and `roiData` for content

### Future Multi-Dataset Implementation:
When adding views with multi-dataset support:

1. Specify the dataset identity:
   ```swift
   StandaloneMPRView(
       plane: .axial,
       datasetID: .male,  // or .female, .test
       coordinateSystem: multiDatasetManager.coordinateSystems[.male]!,
       sharedState: multiDatasetManager.sharedStates[.male]!,
       volumeData: multiDatasetManager.volumeData[.male],
       roiData: multiDatasetManager.roiData[.male]
   )
   ```

2. Views can show different datasets in same layout:
   - Left side: Male anatomy (all 3 planes)
   - Right side: Female anatomy (all 3 planes)
   - Or mixed: Male axial, Female axial, Male sagittal, etc.

## Current UI State

### What's Working:
- ✅ 1/2/3/4 view layouts
- ✅ Layout switching on the fly
- ✅ Independent scrolling per view
- ✅ Synchronized window levels
- ✅ Synchronized crosshairs
- ✅ Local zoom/pan per view
- ✅ Cool progress bar during loading
- ✅ Clean, minimal logging (controlled by AppConfig)

### Ready for Enhancement:
- Gesture refinement (sensitivity, smoothness)
- Custom layout builder
- View presets/templates
- Anatomy list panel
- 3D view integration
- Measurement tools
- Annotation system

## Important Architecture Principles

### Current (Single Dataset):
1. **Each view is standalone**: Can work alone without other views
2. **Minimal coupling**: Views only share what must be synchronized
3. **Single authority**: DICOMCoordinateSystem is the spatial truth
4. **Platform agnostic**: Works on any screen size/device
5. **Performance**: Each view renders independently (no blocking)

### Future (Multi-Dataset):
6. **Dataset Independence**: Each dataset has its own coordinate space
7. **Smart Synchronization**: Sync within dataset, not across
8. **Anatomy Mapping**: Cross-dataset anatomy selection
9. **Visual Identity**: Clear indication of which dataset each view shows
10. **Comparison Mode**: Side-by-side different datasets

## Debug Controls

Located in `AppConfig.swift`:
- Set `debugMode = true` to enable logging
- Control individual categories (dicom, coordinates, volume, etc.)
- Currently all verbose logging is OFF

## Next Steps for UI Development

1. **Gesture Polish**: Refine scrolling sensitivity, add momentum
2. **Layout Customization**: User-draggable panel dividers
3. **View Persistence**: Save/load custom layouts
4. **Touch Feedback**: Visual feedback for interactions
5. **Anatomy Integration**: Clickable ROIs with info panels
6. **Measurement Tools**: Distance, angle, ROI measurements
7. **Windowing Presets**: Quick access buttons
8. **View Linking**: Option to link/unlink zoom across views

## Testing the Architecture

### Current Single Dataset Testing:
Run the app and verify:
1. Switch between 1/2/3/4 view modes - should be instant
2. Scroll in one view - crosshairs update in others
3. Change window level - all views update
4. Zoom one view - others remain unchanged
5. Toggle ROI - appears in all views correctly oriented

### Future Multi-Dataset Testing:
1. Load male and female datasets simultaneously
2. Scroll in male axial - only male sagittal/coronal crosshairs update
3. Change window in female view - only female views update
4. Select "Liver" anatomy - highlights in both male AND female (different ROIs)
5. Select "Prostate" - only highlights in male views
6. Select "Uterus" - only highlights in female views
7. Compare male vs female anatomy side-by-side with different windowing

The architecture is proven to work and ready for UI enhancement!