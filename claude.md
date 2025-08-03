# X-Anatomy Pro v2.0 - Medical Imaging App

## Project Goal
Transform X-Anatomy Pro from PNG-based anatomy reference to DICOM-based radiological viewer with 3D anatomical ROI visualization across synchronized multi-planar reconstruction (MPR) views.

## Test Data vs Production Data

### Current Development
- **Test CT scan**: ~53 slices, 512×512 resolution
- **Spacing**: 0.7mm × 0.7mm × 3.0mm
- **Purpose**: Algorithm development and testing
- **Architecture**: Dynamic handling, no hardcoded slice counts

### Production Target
- **Full-body scans**: Male and female patients, ~500+ slices each
- **Higher resolution**: Larger datasets for comprehensive anatomy
- **Same architecture**: Code scales automatically to any volume size
- **Coordinate system**: Handles any DICOM dimensions/spacing

## Core Requirements
- **DICOM Processing**: Direct DICOM rendering replacing PNG conversion
- **Multi-Planar Reconstruction**: Synchronized axial, sagittal, coronal views
- **3D ROI Visualization**: RTstruct integration with anatomical structure highlighting
- **Medical Accuracy**: Professional-grade CT windowing and spatial alignment
- **Performance**: Hardware-accelerated Metal rendering

## Architecture: Clean Layered System

### Layer 1: DICOM Coordinate System (Authority)
**File**: `Volume3D/Core/DICOMCoordinateSystem.swift`
- Single source of truth for spatial transformations
- Converts between world coordinates (mm) and slice indices
- Manages current 3D position across all views
- Ensures perfect alignment between CT, crosshairs, and ROI

### Layer 2: CT Display (Base Reality)
**File**: `SwiftUI/Layers/CTDisplayLayer.swift`
- Authoritative DICOM slice rendering
- Uses existing `MetalVolumeRenderer` for hardware acceleration
- Hardware-accelerated MPR slice generation
- Professional CT windowing (bone, lung, soft tissue)

### Layer 3: Crosshair Overlay (Position Indicator)
**File**: `SwiftUI/Layers/CrosshairOverlayLayer.swift`
- Independent position indicator overlay
- Synchronized across all three anatomical planes
- Fade effect at intersection point
- Touch interaction for position updates

### Layer 4: ROI Overlay (Anatomical Structures)
**File**: `SwiftUI/Layers/ROIOverlayLayer.swift`
- Renders anatomical structures from RTStruct data
- Cross-section calculation for sagittal/coronal views
- Configurable display settings (outline, fill, opacity)
- Perfect spatial alignment with CT images

### Layer 5: Coordination System
**File**: `SwiftUI/Layers/LayeredMPRView.swift`
- Lightweight orchestrator for independent layers
- No dependencies between layers
- Each layer only depends on coordinate system

## Technical Implementation

### Custom DICOM Parser
**Location**: `/DICOM/` folder
- **Custom Swift implementation**: No external libraries for licensing/performance
- **Reference implementations**: Cornerstone dicomParser, DCMTK, PyDicom
- **Scope**: CT-only, educational use
- **Capabilities**: 53 test files, 100% success rate, 512×512 16-bit signed data
- **Transfer syntax**: Implicit VR Little Endian support
- **Sequence parsing**: Handles nested sequences with undefined length
- **Memory safety**: Bounds checking and safe binary data reading

**Key Files**:
- `DICOMParser.swift` - Main parsing engine with transfer syntax detection
- `DICOMDataset.swift` - Data structures and convenience accessors
- `DICOMTags.swift` - Tag definitions and CT window presets
- `DICOMExtensions.swift` - Safe binary reading extensions

### Metal Hardware Acceleration
**Location**: `/MetalMedical/` folder
- **GPU acceleration**: Metal compute shaders for CT windowing
- **Texture formats**: r16Float for hardware sampling, r16Sint for manual fallback, rgba8Unorm for display
- **Performance**: 30+ FPS capable, memory-efficient caching with LRU eviction
- **HU conversion**: Proper Hounsfield Unit calculations (HU = pixel × rescaleSlope + rescaleIntercept)
- **Aspect ratio correction**: Maintains 1:1 pixel ratio across orientations
- **Professional windowing**: Bone (W:2000 L:500), lung (W:1600 L:-600), soft tissue (W:350 L:50)
- **Texture caching**: Smart caching with configurable limits

**Key Files**:
- `MetalRenderer.swift` - GPU CT windowing with HU conversion
- `MetalShaders.metal` - Compute shaders for medical imaging
- `TextureCache.swift` - Memory management with LRU eviction

### 3D Volume System
**Location**: `/Volume3D/` folder
- **Hardware acceleration**: Native Metal `.sample()` calls with r16Float textures
- **MPR generation**: Real-time slice extraction from 3D volume
- **Physical spacing**: Uses real DICOM voxel dimensions for accuracy
- **Dynamic handling**: Any slice count without hardcoding (scales from 53 to 500+ slices)
- **Hardware sampling breakthrough**: 3-5x performance improvement over manual interpolation
- **Simulator compatibility**: Manual interpolation fallback for development
- **Float16 conversion**: Int16 → Float16 for GPU upload
- **Type safety**: Proper Metal .sample() calls with vec<float, 4> handling

**Key Files**:
- `VolumeData.swift` - 3D volume reconstruction from DICOM series
- `MetalVolumeRenderer.swift` - Hardware-accelerated MPR slice generation
- `MPRShaders.metal` - Hardware sampling shaders with fallback support

### RTStruct Integration
**Location**: `/RTStruct/` folder
- **RTStruct parsing**: Complete DICOM RTStruct file analysis with nested sequence handling
- **3D ROI extraction**: Anatomical structure coordinates from contour data
- **Cross-section calculation**: Real-time plane intersections for sagittal/coronal views
- **Reference-only detection**: Handles both complete and reference-only RTStruct files
- **Test data generation**: Fallback circular contours for missing geometry
- **Coordinate validation**: Ensures ROI data spatial consistency
- **File analysis**: Comprehensive RTStruct structure investigation and debugging

**Key Findings**:
- Test RTStruct file contains reference-only data (no contour geometry)
- Missing critical (3006,0050) Contour Data tags
- Contains only ROI metadata and reference UIDs
- Implemented robust fallback test data generation

## Data Flow

1. **DICOM Loading**: Parse CT series into 3D volume
2. **Coordinate System**: Initialize with real DICOM spacing/dimensions
3. **Layer Rendering**: Each layer queries coordinate system for current position
4. **User Interaction**: Updates coordinate system, automatically updates all layers
5. **MPR Generation**: Hardware-accelerated slice extraction per plane

## Open Source Strategy

### Planned Libraries
1. **SwiftDICOM** - Swift-native DICOM parser
2. **MetalMedical** - GPU medical image rendering
3. **Swift MPR Engine** - Multi-planar reconstruction

### Proprietary Components
- Anatomy database and ROI definitions
- Educational content and interactions
- X-Anatomy Pro branding and UI

## Current Status

### Working Components ✅
- Complete DICOM parsing pipeline
- Hardware-accelerated CT windowing
- 3D volume reconstruction with Metal acceleration
- Multi-planar reconstruction (axial, sagittal, coronal)
- Synchronized crosshairs with fade effects
- Professional SwiftUI interface
- Clean layered architecture

### Integration Points
**Main App**: `SwiftUI/XAnatomyProMainView.swift`
**Scene Setup**: `SceneDelegate.swift` (uses `XAnatomyProMainView`)

## Key Technical Decisions

### Why Custom DICOM Parser
- **Commercial alternatives**: Too expensive (Imebra) or complex compilation (DCMTK)
- **Performance**: No external library overhead
- **Control**: Full Swift implementation for iOS optimization
- **Scope**: Educational CT-only vs full clinical DICOM

### Why Layered Architecture
- **Independence**: Modify one layer without affecting others
- **Medical accuracy**: Single coordinate system ensures spatial alignment
- **Maintainability**: Clear separation of concerns
- **Future development**: Easy to add new overlay layers

### Hardware Acceleration Breakthrough
- **Metal toolchain**: Full Metal support for `.sample()` calls
- **Texture format**: r16Float enables hardware trilinear interpolation
- **Performance**: 3-5x improvement over manual interpolation
- **Compatibility**: Fallback shaders for systems without full Metal support

## File Structure
```
xanatomypromd/
├── DICOM/                     # Custom DICOM parser
├── MetalMedical/              # GPU rendering engine
├── Volume3D/                  # 3D volume and MPR system
│   └── Core/                  # DICOMCoordinateSystem
├── SwiftUI/
│   ├── Layers/                # Independent visual layers
│   └── XAnatomyProMainView.swift  # Main app interface
└── Resources/                 # Test DICOM files
```

## Performance Achievements

### DICOM Parsing
- 100% success rate on 53 test DICOM files
- Memory-safe binary reading with bounds checking
- Efficient nested sequence parsing

### Metal Rendering
- 12.25ms texture creation, 31.69ms windowing (30+ FPS capable)
- Medical accuracy verified against commercial DICOM viewers
- Smart texture caching with LRU eviction

### Hardware Acceleration
- 3-5x performance improvement through Metal hardware sampling
- 4-11ms per MPR slice on simulator (targeting 0.5-1.5ms on real device)
- Native GPU trilinear interpolation vs manual 8-point sampling

### Volume Handling
- Dynamic slice count handling (53 to 500+ slices)
- Physical spacing integration for anatomically correct proportions
- No hardcoded assumptions about scan dimensions

## Development Notes

### Layer Independence
- Each layer has its own file and responsibility
- Only dependency: shared `DICOMCoordinateSystem`
- Can work on CT rendering without affecting crosshairs or ROI
- Can modify crosshairs without affecting CT or ROI

### Medical Accuracy
- All coordinates in millimeters (DICOM patient coordinates)
- Crosshair at (180mm, 200mm, 75mm) shows exact anatomical location in all planes
- ROI contours align perfectly with CT pixel locations
- Real DICOM spacing used for aspect ratio calculations

### Performance Optimizations
- Texture caching with LRU eviction
- Hardware-accelerated MPR generation
- Efficient coordinate transformations
- Metal compute shaders for real-time windowing
