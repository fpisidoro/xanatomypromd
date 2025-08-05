# Claude Code Integration Guide - X-Anatomy Pro v2.0

## Project Overview for Claude Code

X-Anatomy Pro v2.0 is a **production-ready medical imaging application** for iOS that processes DICOM files and visualizes anatomical structures. The project has achieved major milestones including working RTStruct parsing and hardware-accelerated medical imaging.

## 🎯 CURRENT PROJECT STATUS

### ✅ COMPLETED COMPONENTS (DO NOT MODIFY)
```
Core Medical Imaging Pipeline:
├── ✅ DICOM Parser (Swift-native, 100% working)
├── ✅ 3D Volume Reconstruction (Metal hardware acceleration)  
├── ✅ Multi-planar Reconstruction (axial, sagittal, coronal)
├── ✅ RTStruct Parser (MILESTONE: extracts real contour coordinates)
├── ✅ Professional CT Windowing (bone, lung, soft tissue)
├── ✅ Coordinate System Authority (perfect spatial alignment)
└── ✅ SwiftUI Medical Interface (production ready)
```

### 🔧 AVAILABLE FOR CLAUDE CODE DEVELOPMENT
```
ROI Visualization Layer:
├── 🔄 Contour overlay rendering on MPR slices
├── 🔄 Interactive anatomical structure selection
├── 🔄 ROI display controls (opacity, color, visibility)
├── 🔄 Touch-based anatomy information panels
└── 🔄 Enhanced educational features
```

## 📁 PROJECT STRUCTURE

### Core Architecture (STABLE - Do Not Modify)
```
xanatomypromd/
├── DICOM/                          # ✅ WORKING - Custom DICOM parser
│   ├── DICOMParser.swift           # Parse DICOM files (53 files, 100% success)
│   ├── DICOMDataset.swift          # DICOM data structures
│   ├── DICOMTags.swift             # DICOM tag definitions
│   └── DICOMFileManager.swift      # File discovery with RTStruct prioritization
├── MetalMedical/                   # ✅ WORKING - GPU rendering engine  
│   ├── MetalRenderer.swift         # Hardware-accelerated CT windowing
│   ├── MetalShaders.metal          # GPU compute shaders
│   └── TextureCache.swift          # Memory management
├── Volume3D/                       # ✅ WORKING - 3D reconstruction
│   ├── VolumeData.swift            # 3D volume from DICOM series
│   ├── MetalVolumeRenderer.swift   # Hardware MPR generation
│   ├── MPRShaders.metal            # Hardware sampling shaders
│   ├── Core/
│   │   └── DICOMCoordinateSystem.swift  # ✅ Authority coordinate system
│   └── ROI/
│       └── MinimalRTStructParser.swift  # ✅ MILESTONE: RTStruct parsing
├── SwiftUI/                        # ✅ WORKING - Application interface
│   ├── XAnatomyProMainView.swift   # Main medical imaging interface
│   └── Layers/                     # ✅ Clean layered architecture
│       ├── LayeredMPRView.swift    # Layer orchestrator  
│       ├── CTDisplayLayer.swift    # DICOM slice rendering
│       ├── CrosshairOverlayLayer.swift  # Synchronized crosshairs
│       └── ROIOverlayLayer.swift   # 🔧 AVAILABLE FOR DEVELOPMENT
└── Resources/TestData/             # Test medical data
    ├── test_rtstruct2.dcm          # ✅ WORKING: Contains real contour data
    └── XAPMD^COUSINALPHA/          # 53-slice CT series
```

## 🎯 RTStruct MILESTONE ACHIEVED

### Parsing Success (DO NOT MODIFY)
The RTStruct parser successfully extracts real anatomical coordinates:
```
✅ FOUND Contour Data tag directly in elements!  
📍 Parsing 956 bytes of contour data...
📝 ASCII data: "-6.738\2.93\-112.84\-6.445\2.637\-112.84..."
✅ SUCCESS: 45 points at Z=-112.84
✅ RTStruct SUCCESS: 1 ROI structures loaded
📊 ROI 8241: 'ROI-1' - 1 contours, 45 points
```

### Available Data Structures
```swift
// ROI data is loaded and available in XAnatomyDataManager
SimpleRTStructData {
    structureSetName: "contours1"
    patientName: "XAPMD^COUSINALPHA"
    roiStructures: [SimpleROIStructure] // Contains real contour coordinates
}

SimpleROIStructure {
    roiNumber: 8241
    roiName: "ROI-1"  
    displayColor: SIMD3<Float>(1.0, 0.0, 1.0) // Magenta
    contours: [SimpleContour] // Array of contour slices
}

SimpleContour {
    points: [SIMD3<Float>] // 45 real anatomical coordinates in mm
    slicePosition: -112.84 // Z-position in DICOM space (mm)
}
```

## 🔧 DEVELOPMENT OPPORTUNITIES FOR CLAUDE CODE

### 1. ROI Overlay Rendering (Primary Focus)
**File**: `SwiftUI/Layers/ROIOverlayLayer.swift`
**Status**: Skeleton exists, needs implementation
**Goal**: Render contour overlays on MPR slices

```swift
// Current structure (needs implementation):
struct ROIOverlayLayer: View {
    let coordinateSystem: DICOMCoordinateSystem
    let plane: MPRPlane  
    let roiData: RTStructData?
    let settings: ROIDisplaySettings
    
    var body: some View {
        // TODO: Implement contour overlay rendering
        // - Convert DICOM coordinates to screen coordinates
        // - Draw contour outlines using SwiftUI Path
        // - Handle slice matching (show contours at current Z)
        // - Apply colors and opacity from ROI settings
    }
}
```

**Key Implementation Requirements**:
- Convert DICOM world coordinates (mm) to screen pixel coordinates
- Match contour Z-positions with current MPR slice position
- Draw smooth contour outlines using SwiftUI Path or Metal rendering
- Handle multiple ROIs with different colors and opacity settings

### 2. Interactive ROI Selection
**Location**: Enhanced touch handling in layers
**Goal**: Touch-based anatomical structure selection

```swift
// Enhancement needed in LayeredMPRView:
.onTapGesture { location in
    // TODO: Implement ROI hit testing
    // - Convert screen coordinates to DICOM world coordinates
    // - Test if touch point is inside any ROI contour
    // - Highlight selected ROI and show information panel
}
```

### 3. ROI Display Controls
**Location**: `SwiftUI/XAnatomyProMainView.swift` controls section
**Goal**: Professional ROI visualization controls

```swift
// Add to existing controlsArea:
private var roiControls: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("ROI Display")
            .font(.headline)
            .foregroundColor(.white)
        
        // TODO: Implement ROI controls
        // - Global ROI opacity slider
        // - Individual ROI visibility toggles  
        // - Color picker for ROI customization
        // - Outline/fill display options
    }
}
```

### 4. Anatomy Information Panels  
**Location**: New SwiftUI views for educational content
**Goal**: Display anatomical information when ROIs are selected

```swift
// New file: SwiftUI/Views/AnatomyInfoPanel.swift
struct AnatomyInfoPanel: View {
    let selectedROI: ROIStructure?
    
    var body: some View {
        // TODO: Implement anatomy information display
        // - ROI name and description
        // - Anatomical details and educational content
        // - Statistics (volume, surface area, etc.)
        // - Related anatomical structures
    }
}
```

## 🏗️ TECHNICAL ARCHITECTURE GUIDELINES

### Coordinate System Authority (CRITICAL)
**DO NOT MODIFY**: `DICOMCoordinateSystem.swift` is the single source of truth
```swift
// Always use coordinate system for spatial calculations:
let worldPosition = coordinateSystem.getCurrentWorldPosition()
let screenCoords = coordinateSystem.worldToScreen(worldPos, viewSize: viewSize)
let sliceZ = coordinateSystem.getCurrentSlicePosition(for: .axial)
```

### Layer Independence Principle (CRITICAL)
Each layer operates independently:
- **CTDisplayLayer**: Renders DICOM slices (DO NOT MODIFY)
- **CrosshairOverlayLayer**: Position indicators (DO NOT MODIFY)  
- **ROIOverlayLayer**: Your development target
- **LayeredMPRView**: Lightweight orchestrator (minimal changes)

### Hardware Acceleration Integration
When implementing ROI rendering, consider Metal performance:
```swift
// For high-performance ROI rendering:
// Option 1: SwiftUI Path (simple, adequate for most ROIs)
// Option 2: Metal compute shaders (complex ROIs, many structures)
// Option 3: Metal vertex buffers (smooth curves, anti-aliasing)
```

## 📊 PERFORMANCE REQUIREMENTS

### Current Performance Benchmarks (DO NOT DEGRADE)
- **Volume Loading**: <2 seconds for 53-slice CT series
- **MPR Generation**: 0.5-1.5ms per slice (hardware accelerated)
- **Frame Rate**: 60 FPS interaction maintained
- **Memory Usage**: 26.5MB volume data + efficient caching

### ROI Rendering Performance Targets
- **Overlay Rendering**: <5ms per frame for typical ROI sets
- **Touch Response**: <100ms for ROI selection feedback
- **Memory Addition**: <10MB for ROI visualization features

## 🧪 TESTING & VALIDATION

### Available Test Data
```
Resources/TestData/test_rtstruct2.dcm:
├── Patient: XAPMD^COUSINALPHA
├── Structure Set: contours1  
├── ROI: 8241 "ROI-1" (Magenta)
├── Contour: 45 points at Z=-112.84mm
└── Coordinates: Real anatomical positions in mm
```

### Testing Approach
1. **Load test data**: App automatically loads RTStruct on startup
2. **Verify coordinates**: Check ROI data in `XAnatomyDataManager.roiData`
3. **Test rendering**: Implement overlay and verify visual alignment
4. **Validate interaction**: Test touch selection and information display

## 🚨 CRITICAL DO NOT MODIFY

### Files to Leave Unchanged
```
❌ DO NOT MODIFY:
├── DICOM/DICOMParser.swift          # 100% working DICOM parsing
├── Volume3D/ROI/MinimalRTStructParser.swift  # MILESTONE RTStruct parser
├── Volume3D/Core/DICOMCoordinateSystem.swift # Authority coordinate system
├── MetalMedical/*.swift             # Hardware acceleration pipeline
├── SwiftUI/Layers/CTDisplayLayer.swift      # Base CT rendering
└── SwiftUI/Layers/CrosshairOverlayLayer.swift # Position indicators
```

### Architecture Principles to Maintain
1. **Single authority**: DICOMCoordinateSystem manages all spatial calculations
2. **Layer independence**: No dependencies between visual layers
3. **Medical accuracy**: All coordinates in DICOM patient space (mm)
4. **Hardware acceleration**: Maintain Metal performance throughout

## 🎯 IMMEDIATE DEVELOPMENT PRIORITIES

### Phase 1: Basic ROI Visualization (Recommended Start)
1. **Implement `ROIOverlayLayer.swift`**:
   - Convert DICOM coordinates to screen coordinates
   - Draw contour outlines using SwiftUI Path
   - Match contours to current slice Z-position
   - Apply ROI colors and basic opacity

2. **Test with existing data**:
   - Verify ROI-1 (45 points) renders correctly on axial slice
   - Ensure contour appears at Z=-112.84mm slice position
   - Validate coordinate transformation accuracy

### Phase 2: Interactive Features
1. **Add touch handling** for ROI selection
2. **Implement ROI visibility controls** in main interface
3. **Create anatomy information panels** for educational content

## 📚 REFERENCE DOCUMENTATION

### Key Data Structures
- `DICOMCoordinateSystem`: Spatial authority and coordinate transformations
- `SimpleRTStructData`: RTStruct file contents with real contour data  
- `RTStructData`: Full ROI structure format used by application
- `MPRPlane`: Anatomical plane enumeration (axial, sagittal, coronal)

### Coordinate Systems
- **DICOM World**: Millimeters in patient coordinate system (authority)
- **Slice Indices**: Voxel indices in 3D volume (512×512×53)
- **Screen Coordinates**: SwiftUI view coordinates for rendering

### Current Working State
- App loads successfully with CT and RTStruct data
- All three MPR planes functional with synchronized crosshairs
- RTStruct parsing extracts real anatomical coordinates  
- Ready for ROI overlay implementation

## 🎖️ SUCCESS CRITERIA

### ROI Visualization Success
- [ ] Contour outlines visible on appropriate MPR slices
- [ ] Coordinate alignment verified (contours match anatomy)
- [ ] Multiple ROI support with different colors
- [ ] Performance maintained (60 FPS interaction)

### Educational Enhancement Success  
- [ ] Touch-based ROI selection working
- [ ] Anatomy information panels implemented
- [ ] Professional ROI display controls functional
- [ ] Medical accuracy validated by visualization alignment

This project represents a significant achievement in mobile medical imaging. The RTStruct parsing milestone enables authentic anatomical education using real patient data. Focus development on ROI visualization while maintaining the robust medical imaging foundation already established.
