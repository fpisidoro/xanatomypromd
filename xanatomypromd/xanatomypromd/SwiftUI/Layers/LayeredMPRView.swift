import SwiftUI
import simd

// MARK: - Layer 4: Coordination System
// Lightweight orchestrator that manages independent layers without creating dependencies

struct LayeredMPRView: View {
    
    // MARK: - Configuration
    
    /// The authoritative coordinate system shared by all layers
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    
    /// Current anatomical plane being displayed
    let plane: MPRPlane
    
    /// CT windowing settings
    let windowLevel: CTWindowLevel
    
    /// Crosshair appearance settings
    let crosshairAppearance: CrosshairAppearance
    
    /// ROI display settings
    let roiSettings: ROIDisplaySettings
    
    /// Data sources
    let volumeData: VolumeData?
    let roiData: MinimalRTStructParser.SimpleRTStructData?
    
    /// View configuration
    let viewSize: CGSize
    let allowInteraction: Bool
    
    /// Shared viewing state for quality control
    let sharedState: SharedViewingState?
    
    // REMOVED: Shared volume renderer - each layer creates its own (Option 3)
    // REMOVED: scrollVelocity, isViewScrolling (priority system deleted)
    
    // MARK: - Initialization
    
    init(
        coordinateSystem: DICOMCoordinateSystem,
        plane: MPRPlane,
        windowLevel: CTWindowLevel = CTWindowLevel.softTissue,
        crosshairAppearance: CrosshairAppearance = .default,
        roiSettings: ROIDisplaySettings = .default,
        volumeData: VolumeData? = nil,
        roiData: MinimalRTStructParser.SimpleRTStructData? = nil,
        viewSize: CGSize = CGSize(width: 512, height: 512),
        allowInteraction: Bool = true,
        sharedState: SharedViewingState? = nil
    ) {
        self.coordinateSystem = coordinateSystem
        self.plane = plane
        self.windowLevel = windowLevel
        self.crosshairAppearance = crosshairAppearance
        self.roiSettings = roiSettings
        self.volumeData = volumeData
        self.roiData = roiData
        self.viewSize = viewSize
        self.allowInteraction = allowInteraction
        self.sharedState = sharedState
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Layer 1: CT Display (Base Reality) - ALWAYS BOTTOM
            CTDisplayLayer(
                coordinateSystem: coordinateSystem,
                plane: plane,
                windowLevel: windowLevel,
                volumeData: volumeData,
                sharedState: sharedState
                // Each CTDisplayLayer creates its own renderer (Option 3)
                // REMOVED: scrollVelocity, isViewScrolling
            )
            
            // Layer 3: ROI Overlay (Anatomical Structures) - MIDDLE
            if roiSettings.isVisible {
                ROIOverlayLayer(
                    coordinateSystem: coordinateSystem,
                    plane: plane,
                    viewSize: viewSize,
                    roiData: roiData,
                    roiSettings: roiSettings
                )
            }
            
            // Layer 2: Crosshair Overlay (Position Indicator) - ALWAYS TOP
            if crosshairAppearance.isVisible {
                InteractiveCrosshairLayer(
                    coordinateSystem: coordinateSystem,
                    plane: plane,
                    viewSize: viewSize,
                    volumeData: volumeData,
                    appearance: crosshairAppearance,
                    allowInteraction: allowInteraction
                )
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .clipped()
        .background(Color.black)
    }
}

// MARK: - Layer Coordination State

struct LayerCoordinationState {
    let coordinateSystem: DICOMCoordinateSystem
    let currentPlane: MPRPlane
    let windowLevel: CTWindowLevel
    let crosshairAppearance: CrosshairAppearance
    let roiSettings: ROIDisplaySettings
    let volumeData: VolumeData?
    let roiData: RTStructData?
}

// MARK: - Layer Alignment Report

struct LayerAlignmentReport {
    let isCoordinateSystemValid: Bool
    let isSliceValid: Bool
    let isROIAligned: Bool
    let currentWorldPosition: SIMD3<Float>
    let currentSliceIndex: Int
    let currentPlane: MPRPlane
    
    var isFullyAligned: Bool {
        return isCoordinateSystemValid && isSliceValid && isROIAligned
    }
}
