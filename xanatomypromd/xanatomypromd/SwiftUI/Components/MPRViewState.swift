import SwiftUI
import simd

// MARK: - MPR View State
// Pure state container for MPR view transformations and interaction state
// This holds ALL mutable state for gesture interactions

@MainActor
class MPRViewState: ObservableObject {
    
    // MARK: - Transform State
    
    /// Current zoom level
    @Published var zoom: CGFloat = 1.0
    
    /// Current pan offset
    @Published var pan: CGSize = .zero
    
    /// Baseline zoom (calculated fit-to-view)
    @Published var baselineZoom: CGFloat = 1.0
    
    // MARK: - Interaction State
    
    /// Whether user is currently interacting
    @Published var isInteracting: Bool = false
    
    /// Whether currently in pinch gesture
    @Published var isPinching: Bool = false
    
    /// Whether currently in pan gesture
    @Published var isPanning: Bool = false
    
    /// Whether currently scrolling slices
    @Published var isScrolling: Bool = false
    
    // MARK: - Gesture Configuration
    
    /// View size for baseline calculations
    var viewSize: CGSize = .zero
    
    /// Volume dimensions for baseline calculations
    var volumeDimensions: SIMD3<Int32> = SIMD3<Int32>(512, 512, 53)
    
    /// Current anatomical plane
    var currentPlane: MPRPlane = .axial
    
    // MARK: - Initialization
    
    init(plane: MPRPlane = .axial) {
        self.currentPlane = plane
        updateBaselineZoom()
        print("\(plane) viewState created")
    }
    
    // MARK: - State Management
    
    /// Update configuration and recalculate baseline
    func updateConfiguration(
        viewSize: CGSize,
        volumeDimensions: SIMD3<Int32>,
        currentPlane: MPRPlane
    ) {
        let oldBaseline = baselineZoom
        
        self.viewSize = viewSize
        self.volumeDimensions = volumeDimensions
        self.currentPlane = currentPlane
        
        print("Plane set to: \(currentPlane)")
        
        updateBaselineZoom()
        
        // If baseline changed significantly, adjust current zoom proportionally
        if abs(oldBaseline - baselineZoom) > 0.01 && oldBaseline > 0 {
            let ratio = baselineZoom / oldBaseline
            zoom *= ratio
        }
    }
    
    /// Calculate and update baseline zoom
    private func updateBaselineZoom() {
        baselineZoom = calculateFitToViewBaseline()
        
        // Ensure current zoom meets minimum baseline
        if zoom < baselineZoom {
            zoom = baselineZoom
        }
        
        print("🎯 Baseline calculated: \(String(format: "%.2f", baselineZoom))x for \(currentPlane.displayName) (\(Int(viewSize.width))×\(Int(viewSize.height)))")
    }
    
    private func calculateFitToViewBaseline() -> CGFloat {
        guard viewSize.width > 0 && viewSize.height > 0 else { return 1.0 }
        
        // Get plane-specific image dimensions
        let imageDimensions = getPlaneImageDimensions()
        
        // Calculate scale factors for both dimensions
        let scaleX = viewSize.width / imageDimensions.width
        let scaleY = viewSize.height / imageDimensions.height
        
        // Use the smaller scale factor to ensure the image fits completely
        let fitScale = min(scaleX, scaleY)
        
        // Apply different fill factors based on device type
        let targetFillRatio: CGFloat
        if viewSize.width < 500 {  // iPhone-sized views
            targetFillRatio = 0.95  // Fill almost entire view
        } else {  // iPad or multi-panel views
            targetFillRatio = 0.75  // More conservative
        }
        
        let baseline = fitScale * targetFillRatio
        
        // Apply reasonable bounds - ensure minimum 1.0x for iPhone
        let minBaseline: CGFloat = viewSize.width < 500 ? 1.0 : 0.8
        let maxBaseline: CGFloat = 3.0
        
        return max(minBaseline, min(baseline, maxBaseline))
    }
    
    private func getPlaneImageDimensions() -> CGSize {
        // Convert volume dimensions to image dimensions based on plane
        switch currentPlane {
        case .axial:
            // Axial: width=X, height=Y
            return CGSize(width: CGFloat(volumeDimensions.x), height: CGFloat(volumeDimensions.y))
        case .sagittal:
            // Sagittal: width=Y, height=Z
            return CGSize(width: CGFloat(volumeDimensions.y), height: CGFloat(volumeDimensions.z))
        case .coronal:
            // Coronal: width=X, height=Z
            return CGSize(width: CGFloat(volumeDimensions.x), height: CGFloat(volumeDimensions.z))
        }
    }
    
    // MARK: - Transform Operations
    
    /// Reset view to baseline state
    func resetView() {
        zoom = baselineZoom
        pan = .zero
        isInteracting = false
        isPinching = false
        isPanning = false
        isScrolling = false
    }
    
    /// Check if view has been transformed from default
    var isTransformed: Bool {
        return abs(zoom - baselineZoom) > 0.01 || pan != .zero
    }
    
    /// Apply zoom with constraints
    func setZoom(_ newZoom: CGFloat, constrainToLimits: Bool = true) {
        if constrainToLimits {
            let minZoom = baselineZoom  // Never go below baseline
            let maxZoom = baselineZoom * 4.0
            zoom = max(minZoom, min(newZoom, maxZoom))
        } else {
            zoom = newZoom
        }
    }
    
    /// Apply pan offset
    func setPan(_ newPan: CGSize) {
        pan = newPan
    }
    
    /// Update interaction state
    func setInteractionState(
        isInteracting: Bool = false,
        isPinching: Bool = false,
        isPanning: Bool = false,
        isScrolling: Bool = false
    ) {
        self.isInteracting = isInteracting
        self.isPinching = isPinching
        self.isPanning = isPanning
        self.isScrolling = isScrolling
    }
    
    // MARK: - Zoom Thresholds
    
    /// Get zoom threshold for switching between pan and scroll modes
    var zoomThresholdForPan: CGFloat {
        return baselineZoom * 1.5
    }
    
    /// Check if current zoom allows 1-finger scrolling
    var allowsOneFingerScroll: Bool {
        return zoom <= zoomThresholdForPan
    }
    
    /// Check if current zoom requires pan mode
    var requiresPanMode: Bool {
        return zoom > zoomThresholdForPan
    }
}

// MARK: - Gesture Configuration

struct GestureConfiguration {
    
    // MARK: - Scroll Settings (Adaptive to View Size)
    
    /// ADAPTIVE: Proportional threshold based on view size (percentage of smallest dimension)
    let scrollSensitivityRatio: CGFloat = 0.03  // 3% of smallest dimension
    
    /// ADAPTIVE: Minimum scroll threshold (safety lower bound)
    let minimumScrollThreshold: CGFloat = 8     // Minimum 8 pixels
    
    /// ADAPTIVE: Maximum scroll threshold (safety upper bound)  
    let maximumScrollThreshold: CGFloat = 50    // Maximum 50 pixels
    
    /// DEPRECATED: Base distance threshold (replaced by adaptive calculation)
    let baseScrollThreshold: CGFloat = 15  // Kept for backward compatibility
    
    /// Sensitivity multiplier for different planes
    let planeScrollSensitivity: [MPRPlane: Float] = [
        .axial: 1.0,     // Full sensitivity for axial (most slices)
        .sagittal: 1.0,  // Full sensitivity for sagittal (was 0.7 - too low!)
        .coronal: 1.0    // Full sensitivity for coronal (was 0.7 - too low!)
    ]
    
    // MARK: - Zoom Settings
    
    /// Minimum zoom multiplier relative to baseline
    let minZoomMultiplier: CGFloat = 0.5
    
    /// Maximum zoom multiplier relative to baseline
    let maxZoomMultiplier: CGFloat = 4.0
    
    /// Fill ratio for baseline calculation
    let baselineFillRatio: CGFloat = 0.75
    
    // MARK: - Pan Settings
    
    /// Threshold for distinguishing vertical vs horizontal gestures
    let verticalGestureRatio: CGFloat = 0.7
    
    /// Zoom threshold multiplier for enabling pan mode
    let panModeThresholdMultiplier: CGFloat = 1.5
    
    // MARK: - Quality Settings
    
    /// Velocity thresholds for quality reduction during scrolling
    let qualityThresholds: [CGFloat: Int] = [
        800: 4,  // Quarter quality for very fast scrolling
        400: 2,  // Half quality for medium speed
        0: 1     // Full quality for slow scrolling
    ]
    
    // MARK: - Default Configuration
    
    static let `default` = GestureConfiguration()
    
    // MARK: - Adaptive Threshold Calculation
    
    /// Calculate scroll threshold based on view size (FIXES QUAD MODE LAG)
    func calculateScrollThreshold(for viewSize: CGSize) -> CGFloat {
        let smallestDimension = min(viewSize.width, viewSize.height)
        let proportionalThreshold = smallestDimension * scrollSensitivityRatio
        
        // Clamp between safety bounds
        let adaptiveThreshold = max(minimumScrollThreshold, 
                                   min(proportionalThreshold, maximumScrollThreshold))
        
        return adaptiveThreshold
    }
    
    /// Check if a gesture translation qualifies as vertical scrolling
    func isVerticalScrollGesture(translation: CGPoint) -> Bool {
        return abs(translation.y) > abs(translation.x) * verticalGestureRatio
    }
}
