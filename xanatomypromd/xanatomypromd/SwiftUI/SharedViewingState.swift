import SwiftUI
import simd

// MARK: - Shared Viewing State
// Manages shared state across all MPR and 3D views for synchronized display

@MainActor
class SharedViewingState: ObservableObject {
    
    // MARK: - Display Settings
    
    /// Current CT window level applied to all views
    @Published var windowLevel: CTWindowLevel = .softTissue
    
    /// Crosshair display settings shared across views
    @Published var crosshairSettings = CrosshairAppearance.default
    
    /// ROI overlay display settings
    @Published var roiSettings = ROIDisplaySettings.default
    
    /// FIXED: Plane-specific render quality (1=full, 2=half, 4=quarter)
    @Published var renderQuality: [MPRPlane: Int] = [
        .axial: 1,
        .sagittal: 1,
        .coronal: 1
    ]
    
    // MARK: - 3D View State (Persistent)
    
    /// 3D view rotation around Z-axis (preserved when switching views)
    @Published var rotation3D: Float = 0.0
    
    /// 3D view zoom level (preserved when switching views)
    @Published var zoom3D: CGFloat = 1.0
    
    /// 3D view pan offset (preserved when switching views)
    @Published var pan3D: CGSize = .zero
    
    /// Last active MPR plane before switching to 3D
    @Published var lastActivePlane: MPRPlane = .axial
    
    // MARK: - Quality Management Methods
    
    /// Set quality for a specific plane only
    func setQuality(for plane: MPRPlane, quality: Int) {
        renderQuality[plane] = quality
        print("🎯 Quality set for \(plane): \(quality) (other planes unaffected)")
    }
    
    /// Get quality for a specific plane
    func getQuality(for plane: MPRPlane) -> Int {
        return renderQuality[plane] ?? 1
    }
    
    /// Restore full quality for a specific plane
    func restoreFullQuality(for plane: MPRPlane) {
        if renderQuality[plane] != 1 {
            renderQuality[plane] = 1
            print("🔄 Full quality restored for \(plane)")
        }
    }
    
    /// Restore full quality for all planes
    func restoreAllQuality() {
        for plane in [MPRPlane.axial, .sagittal, .coronal] {
            renderQuality[plane] = 1
        }
        print("🔄 Full quality restored for all planes")
    }
    
    // MARK: - Existing Methods (Updated)
    
    func setWindowLevel(_ level: CTWindowLevel) {
        windowLevel = level
    }
    
    func toggleCrosshairs() {
        crosshairSettings = CrosshairAppearance(
            isVisible: !crosshairSettings.isVisible,
            color: crosshairSettings.color,
            opacity: crosshairSettings.opacity,
            lineWidth: crosshairSettings.lineWidth,
            fadeDistance: crosshairSettings.fadeDistance
        )
    }
    
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
    
    func update3DRotation(_ rotation: Float) {
        rotation3D = rotation
    }
    
    func update3DZoom(_ zoom: CGFloat) {
        zoom3D = zoom
    }
    
    func update3DPan(_ pan: CGSize) {
        pan3D = pan
    }
    
    func reset3DView() {
        rotation3D = 0.0
        zoom3D = 1.0
        pan3D = .zero
    }
}
