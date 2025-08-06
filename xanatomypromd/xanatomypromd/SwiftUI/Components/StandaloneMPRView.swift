import SwiftUI
import simd

// MARK: - Standalone MPR View
// A completely self-contained MPR view that can function independently
// while maintaining synchronization with other views through shared state

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
    
    // MARK: - Local State (Independent per view)
    
    @State private var localZoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var localPan: CGSize = .zero
    @State private var isDragging = false
    
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
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // The core layered MPR view
            LayeredMPRView(
                coordinateSystem: coordinateSystem,
                plane: plane,
                windowLevel: sharedState.windowLevel,  // Synchronized across views
                crosshairAppearance: sharedState.crosshairSettings,
                roiSettings: sharedState.roiSettings,
                volumeData: volumeData,
                roiData: roiData,
                viewSize: viewSize,
                allowInteraction: false  // We handle interaction at this level
            )
            .scaleEffect(localZoom)  // Local zoom per view
            .offset(localPan)  // Local pan per view
            
            // Gesture overlay
            if allowInteraction {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(createCompositeGesture())
            }
            
            // View label overlay
            viewLabelOverlay
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .clipped()
        .background(Color.black)
        .border(Color.gray.opacity(0.3), width: 1)
    }
    
    // MARK: - Gesture Handling
    
    private func createCompositeGesture() -> some Gesture {
        let tapGesture = TapGesture()
            .onEnded { _ in
                handleTap()
            }
        
        let dragGesture = DragGesture()
            .onChanged { value in
                handleDrag(value)
            }
            .onEnded { value in
                handleDragEnd(value)
            }
        
        let zoomGesture = MagnificationGesture()
            .onChanged { value in
                handleZoom(value)
            }
            .onEnded { value in
                handleZoomEnd(value)
            }
        
        // Combine gestures
        return tapGesture.simultaneously(with: dragGesture).simultaneously(with: zoomGesture)
    }
    
    private func handleTap() {
        // Future: ROI selection at tap point
        print("🎯 Tap on \(plane.displayName) view")
    }
    
    private func handleDrag(_ value: DragGesture.Value) {
        if !isDragging {
            isDragging = true
        }
        
        // Determine if this is a pan or slice navigation
        let velocity = abs(value.translation.height)
        
        if velocity > 10 && !isDragging {
            // Vertical drag = slice navigation
            handleSliceNavigation(value.translation)
        } else {
            // Small movement = pan
            localPan = CGSize(
                width: value.translation.width,
                height: value.translation.height
            )
        }
    }
    
    private func handleDragEnd(_ value: DragGesture.Value) {
        isDragging = false
        
        // Animate pan back if small
        if abs(localPan.width) < 50 && abs(localPan.height) < 50 {
            withAnimation(.spring()) {
                localPan = .zero
            }
        }
    }
    
    private func handleSliceNavigation(_ translation: CGSize) {
        let sensitivity: Float = 0.5
        let deltaSlices = Int(translation.height * CGFloat(sensitivity))
        
        if deltaSlices != 0 {
            let currentSlice = coordinateSystem.getCurrentSliceIndex(for: plane)
            let maxSlices = coordinateSystem.getMaxSlices(for: plane)
            let newSlice = max(0, min(currentSlice - deltaSlices, maxSlices - 1))
            
            if newSlice != currentSlice {
                coordinateSystem.updateFromSliceScroll(plane: plane, sliceIndex: newSlice)
            }
        }
    }
    
    private func handleZoom(_ value: CGFloat) {
        localZoom = lastZoom * value
    }
    
    private func handleZoomEnd(_ value: CGFloat) {
        lastZoom = localZoom
        
        // Constrain zoom levels
        withAnimation(.spring()) {
            localZoom = max(0.5, min(localZoom, 4.0))
            lastZoom = localZoom
        }
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
            
            // Zoom indicator (only show if not 1.0)
            if abs(localZoom - 1.0) > 0.01 {
                HStack {
                    Spacer()
                    Text(String(format: "%.1fx", localZoom))
                        .font(.caption2)
                        .foregroundColor(.yellow.opacity(0.7))
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                }
                .padding(8)
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Reset view transformations
    public func resetView() {
        withAnimation(.spring()) {
            localZoom = 1.0
            lastZoom = 1.0
            localPan = .zero
        }
    }
    
    /// Check if view has been transformed
    public var isTransformed: Bool {
        return abs(localZoom - 1.0) > 0.01 || localPan != .zero
    }
}

// MARK: - Shared Viewing State

@MainActor
class SharedViewingState: ObservableObject {
    
    // MARK: - Synchronized Properties
    
    /// CT Window level (synchronized across all views)
    @Published var windowLevel: CTWindowLevel = CTWindowLevel.softTissue
    
    /// ROI display settings (synchronized)
    @Published var roiSettings: ROIDisplaySettings = .default
    
    /// Crosshair appearance (synchronized)
    @Published var crosshairSettings: CrosshairAppearance = .default
    
    /// Active ROI selection (synchronized)
    @Published var selectedROI: Int? = nil
    
    // MARK: - Methods
    
    /// Update window level for all views
    func setWindowLevel(_ level: CTWindowLevel) {
        windowLevel = level
        print("🔧 Window level changed to: \(level.name) (synced across all views)")
    }
    
    /// Toggle crosshair visibility
    func toggleCrosshairs() {
        crosshairSettings = CrosshairAppearance(
            isVisible: !crosshairSettings.isVisible,
            color: crosshairSettings.color,
            opacity: crosshairSettings.opacity,
            lineWidth: crosshairSettings.lineWidth,
            fadeDistance: crosshairSettings.fadeDistance
        )
    }
    
    /// Toggle ROI overlay
    func toggleROIOverlay() {
        roiSettings = ROIDisplaySettings(
            isVisible: !roiSettings.isVisible,
            globalOpacity: roiSettings.globalOpacity,
            showOutline: roiSettings.showOutline,
            showFilled: roiSettings.showFilled,
            outlineWidth: roiSettings.outlineWidth,
            outlineOpacity: roiSettings.outlineOpacity,
            fillOpacity: roiSettings.fillOpacity,
            sliceTolerance: roiSettings.sliceTolerance
        )
    }
    
    /// Select an ROI (will highlight in all views)
    func selectROI(_ roiNumber: Int?) {
        selectedROI = roiNumber
        if let roi = roiNumber {
            print("🎯 ROI \(roi) selected (visible in all applicable views)")
        }
    }
}

// MARK: - Multi-View Container Example

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
