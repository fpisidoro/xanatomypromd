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
    @State private var isPinching = false  // NEW: Track pinch gesture state
    @State private var baselineZoom: CGFloat = 1.0  // NEW: Calculated baseline zoom
    
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
            LayeredMPRView(
                coordinateSystem: coordinateSystem,
                plane: plane,
                windowLevel: sharedState.windowLevel,
                crosshairAppearance: sharedState.crosshairSettings,
                roiSettings: sharedState.roiSettings,
                volumeData: volumeData,
                roiData: roiData,
                viewSize: viewSize,
                allowInteraction: false,
                sharedState: sharedState
            )
            .scaleEffect(localZoom)
            .offset(localPan)
            
            if allowInteraction {
                UnifiedGestureHandler(
                    onGesture: handleUnifiedGesture,
                    onZoomChange: handleZoomChange,
                    viewSize: viewSize,
                    volumeDimensions: volumeData?.dimensions ?? SIMD3<Int32>(512, 512, 53),
                    currentPlane: plane
                )
            }
            
            viewLabelOverlay
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .clipped()
        .background(.black)
        .onAppear { updateBaselineZoom() }
    }
    
    // MARK: - Baseline Zoom Calculation
    
    private func updateBaselineZoom() {
        let newBaseline = calculateFitToViewBaseline(
            textureSize: getEstimatedTextureSize(),
            availableViewSize: viewSize
        )
        
        // Update baseline zoom
        baselineZoom = newBaseline
        
        // If current zoom is below new baseline, bring it up to baseline
        if localZoom < baselineZoom {
            localZoom = baselineZoom
            lastZoom = baselineZoom
        }
        
        print("📊 Baseline zoom for \(plane.displayName): \(String(format: "%.2f", baselineZoom))x (view: \(Int(viewSize.width))×\(Int(viewSize.height)))")
    }
    
    private func calculateFitToViewBaseline(textureSize: CGSize, availableViewSize: CGSize) -> CGFloat {
        // Calculate zoom needed to fit texture nicely in available view space
        // Target ~75% of available space for comfortable viewing (reduced from 85%)
        
        let targetFillRatio: CGFloat = 0.75
        let availableWidth = availableViewSize.width * targetFillRatio
        let availableHeight = availableViewSize.height * targetFillRatio
        
        // Calculate scale factors for both dimensions
        let scaleX = availableWidth / textureSize.width
        let scaleY = availableHeight / textureSize.height
        
        // Use the smaller scale to ensure image fits within bounds
        let baseline = min(scaleX, scaleY)
        
        // Ensure reasonable bounds: never smaller than 0.8x, never larger than 2.5x
        // This prevents tiny baselines on solo views
        return max(0.8, min(baseline, 2.5))
    }
    
    private func getEstimatedTextureSize() -> CGSize {
        // Get estimated texture dimensions based on volume data or use defaults
        guard let volumeData = volumeData else {
            return CGSize(width: 512, height: 512)  // Default fallback
        }
        
        let dims = volumeData.dimensions
        
        switch plane {
        case .axial:
            return CGSize(width: dims.x, height: dims.y)
        case .sagittal:
            return CGSize(width: dims.y, height: dims.z)
        case .coronal:
            return CGSize(width: dims.x, height: dims.z)
        }
    }
    
    // MARK: - Enhanced Unified Gesture Handler
    
    private func handleUnifiedGesture(type: UnifiedGestureHandler.GestureType, data: UnifiedGestureHandler.GestureData) {
        switch type {
        case .pan:
            handlePanGesture(data)
        case .pinch:
            handlePinchGesture(data)
        case .twoFingerScroll:
            handleTwoFingerScrollSmooth(data)
        case .oneFingerScroll:
            handleOneFingerScrollSmooth(data)
        case .scrollEnd:
            handleScrollEnd()
        case .zoomEnd:
            handleZoomEnd(data)
        }
    }
    
    private func handleZoomChange(_ newZoom: CGFloat) {
        // Direct zoom update from UnifiedGestureHandler
        localZoom = newZoom
    }
    
    private func handlePanGesture(_ data: UnifiedGestureHandler.GestureData) {
        localPan = CGSize(width: data.translation.x, height: data.translation.y)
    }
    
    private func handlePinchGesture(_ data: UnifiedGestureHandler.GestureData) {
        // Handle gesture state transitions
        if data.scale == 1.0 {  // Gesture ended
            isPinching = false
            lastZoom = localZoom
            // Final constraint with animation
            withAnimation(.spring()) {
                localZoom = max(baselineZoom, min(localZoom, baselineZoom * 4.0))
                lastZoom = localZoom
            }
            return
        }
        
        // Start of gesture: sync lastZoom to prevent jumps
        if !isPinching {
            isPinching = true
            lastZoom = localZoom  // CRITICAL: Sync to current zoom to prevent jumps
            print("🔍 Pinch start: lastZoom synced to \(String(format: "%.2f", lastZoom))x")
        }
        
        let newZoom = lastZoom * data.scale
        
        // CONSTRAINT: Never go below baseline zoom, max 4x zoom range
        localZoom = max(baselineZoom, min(newZoom, baselineZoom * 4.0))
    }
    
    // MARK: - Enhanced 2-Finger Scrolling with Quality Control
    
    private func handleTwoFingerScrollSmooth(_ data: UnifiedGestureHandler.GestureData) {
        // Trigger quality reduction on first scroll event
        startScrollQualityReduction(velocity: data.speed)
        
        // Calculate plane-aware sensitivity
        let sensitivity = calculatePlaneAwareSensitivity()
        
        // Determine slice change amount based on accumulated distance and velocity
        let sliceChange = calculateSliceChange(
            accumulatedDistance: data.accumulatedDistance,
            direction: data.direction,
            velocity: data.speed,
            sensitivity: sensitivity
        )
        
        if sliceChange != 0 {
            navigateSlices(by: sliceChange)
        }
    }
    
    // MARK: - NEW: 1-Finger Scrolling (when zoom <= 1.5x)
    
    private func handleOneFingerScrollSmooth(_ data: UnifiedGestureHandler.GestureData) {
        // 1-finger scrolling works the same as 2-finger, just different trigger
        startScrollQualityReduction(velocity: data.speed)
        
        let sensitivity = calculatePlaneAwareSensitivity()
        
        let sliceChange = calculateSliceChange(
            accumulatedDistance: data.accumulatedDistance,
            direction: data.direction,
            velocity: data.speed,
            sensitivity: sensitivity
        )
        
        if sliceChange != 0 {
            navigateSlices(by: sliceChange)
            
            // Visual feedback for 1-finger scroll (optional)
            print("🖱️ 1-finger scroll: \(plane.displayName) slice \(sliceChange > 0 ? "+" : "")\(sliceChange)")
        }
    }
    
    private func handleScrollEnd() {
        // Restore full quality after scrolling ends
        restoreScrollQuality()
    }
    
    private func handleZoomEnd(_ data: UnifiedGestureHandler.GestureData) {
        // Handle zoom gesture completion
        lastZoom = localZoom
        print("🔍 Zoom ended at \(String(format: "%.2f", localZoom))x for \(plane.displayName)")
    }
    
    // MARK: - Plane-Aware Sensitivity Calculation
    
    private func calculatePlaneAwareSensitivity() -> Float {
        let totalSlices = coordinateSystem.getMaxSlices(for: plane)
        
        // Scale sensitivity based on slice count
        // Axial (500+ slices) = fine control
        // Sagittal/Coronal (fewer slices) = coarser control
        switch totalSlices {
        case 0..<50:
            return 0.3      // Very fine for few slices
        case 50..<150:
            return 0.5      // Medium sensitivity
        case 150..<300:
            return 0.7      // Higher sensitivity
        default:
            return 1.0      // Full sensitivity for 500+ slices
        }
    }
    
    private func calculateSliceChange(accumulatedDistance: CGFloat, direction: Int, velocity: CGFloat, sensitivity: Float) -> Int {
        // Base slice change amount (always 1 for educational viewing - no skipping)
        let baseChange = 1
        
        // Apply plane-aware sensitivity
        // For educational use: always show every slice, just control frequency
        return baseChange * direction
    }
    
    private func navigateSlices(by amount: Int) {
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: plane)
        let totalSlices = coordinateSystem.getMaxSlices(for: plane)
        let newSlice = max(0, min(totalSlices - 1, currentSlice + amount))
        
        if newSlice != currentSlice {
            coordinateSystem.updateFromSliceScroll(plane: plane, sliceIndex: newSlice)
        }
    }
    
    // MARK: - Quality Control During Scrolling
    
    private func startScrollQualityReduction(velocity: CGFloat) {
        // Determine quality level based on scroll velocity
        let newQuality: Int
        if velocity > 800 {
            newQuality = 4  // Quarter quality for very fast scrolling
        } else if velocity > 400 {
            newQuality = 2  // Half quality for medium speed
        } else {
            newQuality = 1  // Full quality for slow scrolling
        }
        
        // Update shared quality state
        if sharedState.renderQuality != newQuality {
            sharedState.renderQuality = newQuality
        }
    }
    
    private func restoreScrollQuality() {
        // Restore full quality after a brief delay to avoid flickering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if sharedState.renderQuality != 1 {
                sharedState.renderQuality = 1
            }
        }
    }
    
    // MARK: - Legacy Method (keep for compatibility)
    
    private func updateScrollQuality(velocity: CGFloat) {
        // This method is called from the old implementation
        // Redirect to new implementation
        startScrollQualityReduction(velocity: velocity)
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
            localZoom = baselineZoom  // Reset to calculated baseline
            lastZoom = baselineZoom
            localPan = .zero
        }
    }
    
    /// Check if view has been transformed
    public var isTransformed: Bool {
        return abs(localZoom - 1.0) > 0.01 || localPan != .zero
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
