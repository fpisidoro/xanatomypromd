import UIKit
import simd

// MARK: - Gesture Configuration
// Configurable parameters for MPR gesture recognition and interaction

struct GestureConfiguration {
    
    // MARK: - Scroll Sensitivity (Adaptive to View Size)
    
    /// Proportional threshold based on view size (percentage of smallest dimension)
    let scrollSensitivityRatio: CGFloat = 0.03  // 3% of smallest dimension
    
    /// Minimum scroll threshold (safety lower bound)
    let minimumScrollThreshold: CGFloat = 8     // Minimum 8 pixels
    
    /// Maximum scroll threshold (safety upper bound)  
    let maximumScrollThreshold: CGFloat = 50    // Maximum 50 pixels
    
    // MARK: - Gesture Recognition
    
    /// Ratio for detecting vertical vs horizontal gestures
    let verticalGestureRatio: CGFloat = 1.5     // Vertical must be 1.5x horizontal
    
    /// Minimum zoom level relative to baseline
    let minimumZoomRatio: CGFloat = 0.5         // 50% of baseline
    
    /// Maximum zoom level relative to baseline
    let maximumZoomRatio: CGFloat = 4.0         // 400% of baseline
    
    // MARK: - Plane-Specific Sensitivity
    
    /// Per-plane scroll sensitivity multipliers
    let planeScrollSensitivity: [MPRPlane: Float] = [
        .axial: 1.0,      // Standard sensitivity
        .sagittal: 1.0,   // Standard sensitivity  
        .coronal: 1.0     // Standard sensitivity
    ]
    
    // MARK: - Gesture Timing
    
    /// Delay before considering a gesture "ended" for state cleanup
    let gestureEndDelay: TimeInterval = 0.1
    
    /// Maximum time between taps for double-tap recognition
    let doubleTapMaxInterval: TimeInterval = 0.3
    
    /// Minimum hold time for long press recognition
    let longPressMinDuration: TimeInterval = 0.5
    
    // MARK: - Touch Zones (Future Use)
    
    /// Border area for edge gestures (percentage of view)
    let edgeGestureZone: CGFloat = 0.1          // 10% from edges
    
    /// Minimum touch area for gesture recognition (accessibility)
    let minimumTouchArea: CGSize = CGSize(width: 44, height: 44)
    
    // MARK: - Default Configuration
    
    static let `default` = GestureConfiguration()
    
    // MARK: - Adaptive Threshold Calculation
    
    /// Calculate scroll threshold based on view size
    func calculateScrollThreshold(for viewSize: CGSize) -> CGFloat {
        let smallestDimension = min(viewSize.width, viewSize.height)
        let proportionalThreshold = smallestDimension * scrollSensitivityRatio
        
        // Clamp between safety bounds
        let adaptiveThreshold = max(minimumScrollThreshold, 
                                   min(proportionalThreshold, maximumScrollThreshold))
        
        return adaptiveThreshold
    }
    
    /// Get zoom constraints for a given baseline zoom
    func getZoomConstraints(baselineZoom: CGFloat) -> (min: CGFloat, max: CGFloat) {
        return (
            min: baselineZoom * minimumZoomRatio,
            max: baselineZoom * maximumZoomRatio
        )
    }
    
    /// Check if a gesture translation qualifies as vertical scrolling
    func isVerticalScrollGesture(translation: CGPoint) -> Bool {
        return abs(translation.y) > abs(translation.x) * verticalGestureRatio
    }
}

// MARK: - Debug Extensions

extension GestureConfiguration {
    
    /// Print configuration summary for debugging
    func debugDescription(for viewSize: CGSize) -> String {
        let threshold = calculateScrollThreshold(for: viewSize)
        return """
        GestureConfiguration Debug:
        - View size: \(Int(viewSize.width))×\(Int(viewSize.height))
        - Adaptive threshold: \(String(format: "%.1f", threshold))px
        - Sensitivity ratio: \(String(format: "%.1f", scrollSensitivityRatio * 100))%
        - Bounds: \(String(format: "%.0f", minimumScrollThreshold))-\(String(format: "%.0f", maximumScrollThreshold))px
        """
    }
}
