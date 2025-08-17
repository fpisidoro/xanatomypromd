import SwiftUI
import simd

// MARK: - Standalone MPR View (Clean Declarative Architecture)
// 
// This view is now PURELY DECLARATIVE - no gesture handling logic
// All gesture behavior is handled by MPRGestureController (pure UIKit)
// This eliminates SwiftUI/UIKit gesture conflicts and compiler errors

struct StandaloneMPRView: View {
    
    // MARK: - Configuration
    
    /// The anatomical plane this view displays
    let plane: MPRPlane
    
    /// Shared coordinate system (for crosshair sync)
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    
    /// Shared viewing state (for window level sync)
    @ObservedObject var sharedState: SharedViewingState
    
    /// Data sources
    let volumeData: VolumeData?
    let roiData: MinimalRTStructParser.SimpleRTStructData?
    
    /// View configuration
    let viewSize: CGSize
    let allowInteraction: Bool
    
    // MARK: - Local State (Pure View State)
    
    @StateObject private var viewState = MPRViewState()
    
    // MARK: - Gesture Configuration
    
    private let gestureConfig = GestureConfiguration.default
    
    // MARK: - Initialization
    
    init(
        plane: MPRPlane,
        coordinateSystem: DICOMCoordinateSystem,
        sharedState: SharedViewingState,
        volumeData: VolumeData? = nil,
        roiData: MinimalRTStructParser.SimpleRTStructData? = nil,
        viewSize: CGSize = CGSize(width: 512, height: 512),
        allowInteraction: Bool = true
    ) {
        self.plane = plane
        self.coordinateSystem = coordinateSystem
        self.sharedState = sharedState
        self.volumeData = volumeData
        self.roiData = roiData
        self.viewSize = viewSize
        self.allowInteraction = allowInteraction
    }
    
    // MARK: - Body (PURELY DECLARATIVE)
    
    var body: some View {
        ZStack {
            // Base MPR rendering layer
            LayeredMPRView(
                coordinateSystem: coordinateSystem,
                plane: plane,
                windowLevel: sharedState.windowLevel,
                crosshairAppearance: sharedState.crosshairSettings,
                roiSettings: sharedState.roiSettings,
                volumeData: volumeData,
                roiData: roiData,
                viewSize: viewSize,
                allowInteraction: false,  // Gesture handling is separate
                sharedState: sharedState
            )
            .scaleEffect(viewState.zoom)
            .offset(viewState.pan)
            
            // Pure UIKit gesture controller (when interaction enabled)
            if allowInteraction {
                MPRGestureController(
                    viewState: viewState,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    config: gestureConfig
                )
            }
            
            // UI overlays
            viewLabelOverlay
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .clipped()
        .background(.black)
        .onAppear {
            updateViewStateConfiguration()
        }
        .onChange(of: viewSize) {
            updateViewStateConfiguration()
        }
        .onChange(of: volumeData?.dimensions) {
            updateViewStateConfiguration()
        }
    }
    
    // MARK: - Configuration Updates
    
    private func updateViewStateConfiguration() {
        viewState.updateConfiguration(
            viewSize: viewSize,
            volumeDimensions: volumeData?.dimensions ?? SIMD3<Int32>(512, 512, 53),
            currentPlane: plane
        )
    }
    
    // MARK: - View Components
    
    private var viewLabelOverlay: some View {
        VStack {
            HStack {
                // Plane label
                Text(plane.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                
                Spacer()
                
                // Slice indicator
                let sliceIndex = coordinateSystem.getCurrentSliceIndex(for: plane)
                let maxSlices = coordinateSystem.getMaxSlices(for: plane)
                Text("\(sliceIndex + 1)/\(maxSlices)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
            }
            .padding(8)
            
            Spacer()
            
            // Zoom indicator (only show if significantly different from baseline)
            if abs(viewState.zoom - viewState.baselineZoom) > 0.01 {
                HStack {
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        // Current zoom
                        Text(String(format: "%.1fx", viewState.zoom))
                            .font(.caption2)
                            .foregroundColor(.yellow.opacity(0.8))
                        
                        // Baseline reference (when significantly different)
                        if abs(viewState.zoom - viewState.baselineZoom) > 0.2 {
                            Text("(base: \(String(format: "%.1fx", viewState.baselineZoom)))")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                }
                .padding(8)
            }
            
            // Interaction state indicator (debug/development)
            if viewState.isInteracting {
                HStack {
                    if viewState.isPinching {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.blue)
                    }
                    if viewState.isPanning {
                        Image(systemName: "hand.draw")
                            .foregroundColor(.green)
                    }
                    if viewState.isScrolling {
                        Image(systemName: "scroll")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption2)
                .padding(4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
                .padding(.bottom, 8)
            }
        }
    }
    
    // MARK: - Public Interface
    
    /// Reset view transformations to baseline
    public func resetView() {
        withAnimation(.spring()) {
            viewState.resetView()
        }
    }
    
    /// Check if view has been transformed from baseline
    public var isTransformed: Bool {
        return viewState.isTransformed
    }
    
    /// Get current zoom level
    public var currentZoom: CGFloat {
        return viewState.zoom
    }
    
    /// Get baseline zoom level
    public var baselineZoom: CGFloat {
        return viewState.baselineZoom
    }
}

// MARK: - Multi-View Container (Updated)

struct MultiViewMPRContainer: View {
    @StateObject private var coordinateSystem = DICOMCoordinateSystem()
    @StateObject private var sharedState = SharedViewingState()
    
    let volumeData: VolumeData?
    let roiData: MinimalRTStructParser.SimpleRTStructData?
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                // Three independent but synchronized views
                StandaloneMPRView(
                    plane: .axial,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: volumeData,
                    roiData: roiData,
                    viewSize: CGSize(
                        width: geometry.size.width / 3 - 4,
                        height: geometry.size.height
                    )
                )
                
                StandaloneMPRView(
                    plane: .sagittal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: volumeData,
                    roiData: roiData,
                    viewSize: CGSize(
                        width: geometry.size.width / 3 - 4,
                        height: geometry.size.height
                    )
                )
                
                StandaloneMPRView(
                    plane: .coronal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: volumeData,
                    roiData: roiData,
                    viewSize: CGSize(
                        width: geometry.size.width / 3 - 4,
                        height: geometry.size.height
                    )
                )
            }
        }
    }
}

// MARK: - Preview Provider

struct StandaloneMPRView_Previews: PreviewProvider {
    static var previews: some View {
        StandaloneMPRView(
            plane: .axial,
            coordinateSystem: DICOMCoordinateSystem(),
            sharedState: SharedViewingState(),
            viewSize: CGSize(width: 400, height: 400)
        )
        .frame(width: 400, height: 400)
        .background(.black)
    }
}
