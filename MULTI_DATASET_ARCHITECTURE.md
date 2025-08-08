# Enhanced StandaloneMPRView Architecture - Multi-Dataset Support

## New Requirements (Not Yet Implemented)
The architecture must support displaying multiple independent datasets simultaneously (e.g., male and female CT scans) with proper coordination within each dataset but independence between datasets.

## Proposed Architecture Enhancement

### 1. Dataset Identity System
Each view needs to know which dataset it belongs to:

```swift
enum DatasetIdentity: String, CaseIterable {
    case testScan = "Test"
    case male = "Male"
    case female = "Female"
    
    var displayName: String {
        switch self {
        case .testScan: return "Test Patient"
        case .male: return "Male Reference"
        case .female: return "Female Reference"
        }
    }
}
```

### 2. Enhanced StandaloneMPRView
```swift
struct StandaloneMPRView: View {
    let plane: MPRPlane
    let datasetID: DatasetIdentity  // NEW: Which dataset this view shows
    
    // Each dataset has its own coordinate system
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    
    // Shared state is now per-dataset
    @ObservedObject var sharedState: SharedViewingState
    
    // Each dataset has its own data
    let volumeData: VolumeData?
    let roiData: MinimalRTStructParser.SimpleRTStructData?
}
```

### 3. Multi-Dataset Manager
```swift
@MainActor
class MultiDatasetManager: ObservableObject {
    // Separate coordinate systems for each dataset
    @Published var coordinateSystems: [DatasetIdentity: DICOMCoordinateSystem] = [:]
    
    // Separate shared states for each dataset
    @Published var sharedStates: [DatasetIdentity: SharedViewingState] = [:]
    
    // Separate volume data for each dataset
    @Published var volumeData: [DatasetIdentity: VolumeData] = [:]
    
    // Separate ROI data for each dataset
    @Published var roiData: [DatasetIdentity: SimpleRTStructData] = [:]
    
    // Global anatomy selection (affects all datasets)
    @Published var selectedAnatomyStructure: String? = nil
    
    func loadDataset(_ id: DatasetIdentity) async {
        // Load appropriate DICOM files for this dataset
        // Initialize coordinate system for this dataset
        // Create shared state for this dataset
    }
}
```

### 4. Synchronization Rules

#### Within Same Dataset:
- **Crosshairs**: Sync only views showing the same dataset
- **Window Levels**: Sync only views showing the same dataset
- **Slice Navigation**: Updates only affect same dataset views

#### Across All Datasets:
- **Anatomy Selection**: When user selects "Liver":
  - Highlight liver ROI in all male views (if exists)
  - Highlight liver ROI in all female views (if exists)
  - Different ROI geometries but same anatomical structure

### 5. Layout Examples

#### iPad Split Comparison Layout:
```
┌─────────────────────┬─────────────────────┐
│   Male - Axial      │   Female - Axial    │
├─────────────────────┼─────────────────────┤
│   Male - Sagittal   │   Female - Sagittal │
├─────────────────────┼─────────────────────┤
│   Male - Coronal    │   Female - Coronal  │
└─────────────────────┴─────────────────────┘
```

#### iPad Mixed Layout:
```
┌──────────────┬──────────────┬──────────────┐
│ Male-Axial   │ Male-Sagittal│ Female-Axial │
└──────────────┴──────────────┴──────────────┘
```

### 6. Implementation Changes Needed

#### A. Coordinate System Independence
```swift
// Instead of single shared coordinate system:
@StateObject var coordinateSystem = DICOMCoordinateSystem()

// Use per-dataset coordinate systems:
@StateObject var multiDatasetManager = MultiDatasetManager()

// Access like:
let coordSystem = multiDatasetManager.coordinateSystems[.male]
```

#### B. View Creation
```swift
StandaloneMPRView(
    plane: .axial,
    datasetID: .male,  // NEW
    coordinateSystem: multiDatasetManager.coordinateSystems[.male]!,
    sharedState: multiDatasetManager.sharedStates[.male]!,
    volumeData: multiDatasetManager.volumeData[.male],
    roiData: multiDatasetManager.roiData[.male]
)
```

#### C. Anatomy Selection
```swift
// In SharedViewingState
func selectAnatomy(_ structureName: String) {
    // This triggers ROI highlighting in ALL datasets
    multiDatasetManager.selectedAnatomyStructure = structureName
    
    // Each view checks if it has ROI for this anatomy
    if let roi = findROIForAnatomy(structureName, in: datasetID) {
        highlightROI(roi)
    }
}
```

### 7. Database Integration (Future)

The anatomy database will need to map:
```swift
struct AnatomyMapping {
    let structureName: String  // e.g., "Liver"
    let maleROINumber: Int?    // ROI number in male dataset
    let femaleROINumber: Int?  // ROI number in female dataset
    let testROINumber: Int?    // ROI number in test dataset
    let isMaleOnly: Bool       // e.g., prostate
    let isFemaleOnly: Bool     // e.g., uterus
}
```

### 8. UI Indicators

Each view should show its dataset identity:
```swift
// Visual indicator in corner
Text(datasetID.displayName)
    .font(.caption2)
    .padding(4)
    .background(datasetColor)
    .cornerRadius(4)

// Color coding
var datasetColor: Color {
    switch datasetID {
    case .male: return .blue
    case .female: return .pink
    case .testScan: return .gray
    }
}
```

### 9. Benefits of This Architecture

1. **True Independence**: Each dataset operates independently
2. **Proper Coordination**: Views of same dataset stay synchronized
3. **Cross-Dataset Features**: Anatomy selection works across all
4. **Scalable**: Can add more datasets easily
5. **Clear Visual Separation**: Users know which dataset they're viewing
6. **Comparison Friendly**: Side-by-side male/female comparison

### 10. Testing Scenarios

1. **Load male and female datasets**
2. **Scroll in male axial** → Only male sagittal/coronal crosshairs update
3. **Change window in female axial** → Only female views update
4. **Select "Liver" anatomy** → Highlights in both male and female (different ROIs)
5. **Select "Prostate"** → Only highlights in male views
6. **Select "Uterus"** → Only highlights in female views

## Current Status
- ✅ Basic StandaloneMPRView architecture complete
- ✅ Single dataset coordination working
- ⏳ Multi-dataset support designed (this document)
- ❌ Not yet implemented
- ❌ Database integration pending

## Next Steps
1. Implement MultiDatasetManager
2. Update StandaloneMPRView with datasetID
3. Create per-dataset coordinate systems
4. Update UI to show dataset identity
5. Implement anatomy mapping system
6. Test with male/female datasets