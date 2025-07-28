import Foundation
import Metal
import simd

// MARK: - ROI Integration Manager
// Coordinates RTStruct ROI overlays with existing MPR system

@MainActor
public class ROIIntegrationManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var isROIVisible: Bool = true
    @Published public var globalROIOpacity: Float = 0.5
    @Published public var roiRenderMode: MetalROIRenderer.ROIRenderMode = .filledWithOutline
    @Published public var selectedROIs: Set<Int> = []
    @Published public var roiVisibility: [Int: Bool] = [:]
    
    // MARK: - Core Components
    
    private var roiRenderer: MetalROIRenderer?
    private var currentRTStructData: RTStructData?
    private var metalRenderer: MetalRenderer?
    
    // MARK: - ROI Configuration
    
    public struct ROIDisplayConfig {
        let showFilled: Bool
        let showOutlines: Bool
        let lineWidth: Float
        let enableAntialiasing: Bool
        let adaptiveOpacity: Bool
        
        public init(
            showFilled: Bool = true,
            showOutlines: Bool = true,
            lineWidth: Float = 2.0,
            enableAntialiasing: Bool = true,
            adaptiveOpacity: Bool = true
        ) {
            self.showFilled = showFilled
            self.showOutlines = showOutlines
            self.lineWidth = lineWidth
            self.enableAntialiasing = enableAntialiasing
            self.adaptiveOpacity = adaptiveOpacity
        }
    }
    
    public var displayConfig = ROIDisplayConfig()
    
    // MARK: - Initialization
    
    public init() {
        setupROIRenderer()
    }
    
    private func setupROIRenderer() {
        do {
            roiRenderer = try MetalROIRenderer()
            print("✅ ROI Integration Manager initialized")
        } catch {
            print("❌ Failed to initialize ROI renderer: \(error)")
        }
    }
    
    // MARK: - RTStruct Data Management
    
    /// Load RTStruct data for ROI overlay
    public func loadRTStructData(_ rtStructData: RTStructData) {
        self.currentRTStructData = rtStructData
        
        // Initialize ROI visibility states
        roiVisibility.removeAll()
        for roi in rtStructData.roiStructures {
            roiVisibility[roi.roiNumber] = roi.isVisible
        }
        
        print("✅ Loaded RTStruct with \(rtStructData.roiStructures.count) ROIs for overlay")
        for roi in rtStructData.roiStructures {
            print("   🏷️ \(roi.roiName): \(roi.contours.count) contours")
        }
    }
    
    /// Get currently loaded ROI structures
    public func getROIStructures() -> [ROIStructure] {
        return currentRTStructData?.roiStructures ?? []
    }
    
    /// Get visible ROI structures only
    public func getVisibleROIStructures() -> [ROIStructure] {
        guard let rtStructData = currentRTStructData else { return [] }
        
        return rtStructData.roiStructures.filter { roi in
            isROIVisible && (roiVisibility[roi.roiNumber] ?? roi.isVisible)
        }
    }
    
    // MARK: - ROI Overlay Rendering Integration
    
    /// Render ROI overlays on existing MPR texture
    public func renderROIOverlays(
        onTexture baseTexture: MTLTexture,
        plane: MPRPlane,
        slicePosition: Float,
        volumeOrigin: SIMD3<Float>,
        volumeSpacing: SIMD3<Float>,
        viewportSize: SIMD2<Float>,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        guard let roiRenderer = roiRenderer,
              isROIVisible,
              !getVisibleROIStructures().isEmpty else {
            // No ROIs to render, return original texture
            completion(baseTexture)
            return
        }
        
        let visibleROIs = getVisibleROIStructures()
        
        // Create render configuration
        let config = MetalROIRenderer.ROIRenderConfig(
            opacity: globalROIOpacity,
            lineWidth: displayConfig.lineWidth,
            renderMode: roiRenderMode,
            enableAntialiasing: displayConfig.enableAntialiasing,
            enableAnimation: false,
            viewportSize: viewportSize
        )
        
        // Render ROI overlays
        roiRenderer.renderROIOverlays(
            roiStructures: visibleROIs,
            onTexture: baseTexture,
            plane: plane,
            slicePosition: slicePosition,
            volumeOrigin: volumeOrigin,
            volumeSpacing: volumeSpacing,
            config: config,
            completion: completion
        )
    }
    
    // MARK: - ROI Visibility Control
    
    /// Toggle visibility of specific ROI
    public func toggleROIVisibility(_ roiNumber: Int) {
        let currentVisibility = roiVisibility[roiNumber] ?? true
        roiVisibility[roiNumber] = !currentVisibility
        
        if let roiName = currentRTStructData?.getROI(number: roiNumber)?.roiName {
            print("🔄 ROI '\(roiName)' visibility: \(!currentVisibility ? "ON" : "OFF")")
        }
    }
    
    /// Set visibility for specific ROI
    public func setROIVisibility(_ roiNumber: Int, visible: Bool) {
        roiVisibility[roiNumber] = visible
        
        if let roiName = currentRTStructData?.getROI(number: roiNumber)?.roiName {
            print("👁️ ROI '\(roiName)' visibility: \(visible ? "ON" : "OFF")")
        }
    }
    
    /// Toggle visibility of all ROIs
    public func toggleAllROIs() {
        isROIVisible.toggle()
        print("🔄 All ROIs visibility: \(isROIVisible ? "ON" : "OFF")")
    }
    
    /// Show only selected ROI (hide all others)
    public func showOnlyROI(_ roiNumber: Int) {
        // Hide all ROIs
        for roi in getROIStructures() {
            roiVisibility[roi.roiNumber] = false
        }
        
        // Show only the selected one
        roiVisibility[roiNumber] = true
        
        if let roiName = currentRTStructData?.getROI(number: roiNumber)?.roiName {
            print("🎯 Showing only ROI: '\(roiName)'")
        }
    }
    
    /// Show all ROIs
    public func showAllROIs() {
        for roi in getROIStructures() {
            roiVisibility[roi.roiNumber] = true
        }
        isROIVisible = true
        print("👁️ All ROIs visible")
    }
    
    /// Hide all ROIs
    public func hideAllROIs() {
        isROIVisible = false
        print("🙈 All ROIs hidden")
    }
    
    // MARK: - ROI Selection and Interaction
    
    /// Select/deselect ROI
    public func toggleROISelection(_ roiNumber: Int) {
        if selectedROIs.contains(roiNumber) {
            selectedROIs.remove(roiNumber)
        } else {
            selectedROIs.insert(roiNumber)
        }
        
        if let roiName = currentRTStructData?.getROI(number: roiNumber)?.roiName {
            let action = selectedROIs.contains(roiNumber) ? "selected" : "deselected"
            print("✅ ROI '\(roiName)' \(action)")
        }
    }
    
    /// Clear all selections
    public func clearROISelection() {
        selectedROIs.removeAll()
        print("🗑️ ROI selection cleared")
    }
    
    /// Get information about selected ROIs
    public func getSelectedROIInfo() -> [String] {
        guard let rtStructData = currentRTStructData else { return [] }
        
        return selectedROIs.compactMap { roiNumber in
            guard let roi = rtStructData.getROI(number: roiNumber) else { return nil }
            return "\(roi.roiName) (\(roi.contours.count) contours)"
        }
    }
    
    // MARK: - ROI Information and Statistics
    
    /// Get ROI information for current slice
    public func getROIInfoForSlice(
        plane: MPRPlane,
        slicePosition: Float,
        tolerance: Float = 1.0
    ) -> [ROISliceInfo] {
        guard let rtStructData = currentRTStructData else { return [] }
        
        var sliceInfo: [ROISliceInfo] = []
        
        for roi in rtStructData.roiStructures {
            let contoursOnSlice = roi.contours.filter { contour in
                contour.intersectsSlice(slicePosition, plane: plane, tolerance: tolerance)
            }
            
            if !contoursOnSlice.isEmpty {
                let totalPoints = contoursOnSlice.reduce(0) { $0 + $1.numberOfPoints }
                let info = ROISliceInfo(
                    roiNumber: roi.roiNumber,
                    roiName: roi.roiName,
                    contourCount: contoursOnSlice.count,
                    totalPoints: totalPoints,
                    isVisible: roiVisibility[roi.roiNumber] ?? roi.isVisible,
                    color: roi.displayColor
                )
                sliceInfo.append(info)
            }
        }
        
        return sliceInfo
    }
    
    /// Get overall ROI statistics
    public func getROIStatistics() -> ROIStatistics? {
        guard let rtStructData = currentRTStructData else { return nil }
        
        let stats = rtStructData.getStatistics()
        let visibleCount = getVisibleROIStructures().count
        
        return ROIStatistics(
            totalROIs: stats.roiCount,
            visibleROIs: visibleCount,
            totalContours: stats.totalContours,
            totalPoints: stats.totalPoints,
            zRange: stats.zRange,
            selectedROIs: selectedROIs.count
        )
    }
    
    // MARK: - ROI Display Customization
    
    /// Update global ROI opacity
    public func setGlobalOpacity(_ opacity: Float) {
        globalROIOpacity = max(0.0, min(1.0, opacity))
        print("🎨 Global ROI opacity: \(String(format: "%.1f", globalROIOpacity * 100))%")
    }
    
    /// Update ROI render mode
    public func setRenderMode(_ mode: MetalROIRenderer.ROIRenderMode) {
        roiRenderMode = mode
        
        let modeName = switch mode {
        case .filled: "Filled"
        case .outline: "Outline"
        case .filledWithOutline: "Filled + Outline"
        case .points: "Points"
        case .adaptive: "Adaptive"
        }
        
        print("🎨 ROI render mode: \(modeName)")
    }
    
    /// Update line width for contour outlines
    public func setLineWidth(_ width: Float) {
        displayConfig = ROIDisplayConfig(
            showFilled: displayConfig.showFilled,
            showOutlines: displayConfig.showOutlines,
            lineWidth: max(0.5, min(10.0, width)),
            enableAntialiasing: displayConfig.enableAntialiasing,
            adaptiveOpacity: displayConfig.adaptiveOpacity
        )
        
        print("🖊️ ROI line width: \(String(format: "%.1f", displayConfig.lineWidth))px")
    }
    
    // MARK: - Integration with MPR System
    
    /// Check if ROI data is compatible with volume dimensions
    public func validateROICompatibility(
        volumeOrigin: SIMD3<Float>,
        volumeSpacing: SIMD3<Float>,
        volumeDimensions: SIMD3<Int>
    ) -> (isCompatible: Bool, issues: [String]) {
        guard let rtStructData = currentRTStructData else {
            return (false, ["No RTStruct data loaded"])
        }
        
        var issues: [String] = []
        
        // Check if ROIs have contour data
        let roisWithContours = rtStructData.roiStructures.filter { !$0.contours.isEmpty }
        if roisWithContours.isEmpty {
            issues.append("No ROIs contain contour data")
        }
        
        // Check coordinate ranges
        for roi in roisWithContours {
            if let zRange = roi.zRange {
                let volumeZMin = volumeOrigin.z
                let volumeZMax = volumeOrigin.z + Float(volumeDimensions.z) * volumeSpacing.z
                
                if zRange.max < volumeZMin || zRange.min > volumeZMax {
                    issues.append("ROI '\(roi.roiName)' is outside volume Z-range")
                }
            }
        }
        
        let isCompatible = issues.isEmpty
        return (isCompatible, issues)
    }
    
    /// Update integration with new volume parameters
    public func updateVolumeParameters(
        origin: SIMD3<Float>,
        spacing: SIMD3<Float>,
        dimensions: SIMD3<Int>
    ) {
        let validation = validateROICompatibility(
            volumeOrigin: origin,
            volumeSpacing: spacing,
            volumeDimensions: dimensions
        )
        
        if validation.isCompatible {
            print("✅ ROI-Volume integration validated")
        } else {
            print("⚠️ ROI-Volume compatibility issues:")
            for issue in validation.issues {
                print("   - \(issue)")
            }
        }
    }
    
    // MARK: - Debug and Testing
    
    /// Print current ROI state for debugging
    public func printROIState() {
        guard let rtStructData = currentRTStructData else {
            print("❌ No RTStruct data loaded")
            return
        }
        
        print("\n🎨 ROI Integration State:")
        print("   👁️ Global visibility: \(isROIVisible)")
        print("   🎚️ Global opacity: \(String(format: "%.1f", globalROIOpacity * 100))%")
        print("   🖊️ Line width: \(String(format: "%.1f", displayConfig.lineWidth))px")
        print("   🎯 Render mode: \(roiRenderMode)")
        print("   📊 Total ROIs: \(rtStructData.roiStructures.count)")
        print("   👁️ Visible ROIs: \(getVisibleROIStructures().count)")
        print("   ✅ Selected ROIs: \(selectedROIs.count)")
        
        if !selectedROIs.isEmpty {
            print("   🏷️ Selected: \(getSelectedROIInfo().joined(separator: ", "))")
        }
        
        print("")
    }
    
    /// Get cache statistics from ROI renderer
    public func getCacheStats() -> String? {
        return roiRenderer?.getCacheStats()
    }
    
    /// Clear ROI renderer cache
    public func clearCache() {
        roiRenderer?.clearCache()
    }
}

// MARK: - Supporting Data Structures

public struct ROISliceInfo {
    public let roiNumber: Int
    public let roiName: String
    public let contourCount: Int
    public let totalPoints: Int
    public let isVisible: Bool
    public let color: SIMD3<Float>
}

public struct ROIStatistics {
    public let totalROIs: Int
    public let visibleROIs: Int
    public let totalContours: Int
    public let totalPoints: Int
    public let zRange: (min: Float, max: Float)?
    public let selectedROIs: Int
    
    public var description: String {
        var desc = "ROIs: \(totalROIs) total, \(visibleROIs) visible"
        if selectedROIs > 0 {
            desc += ", \(selectedROIs) selected"
        }
        if let range = zRange {
            desc += String(format: " | Z: %.1f to %.1f mm", range.min, range.max)
        }
        return desc
    }
}

// MARK: - ROI Integration Extensions

extension ROIIntegrationManager {
    
    /// Quick setup for testing with sample ROI data
    public func loadSampleROIData() {
        let sampleData = RTStructTestManager.generateSampleROIData()
        loadRTStructData(sampleData)
        print("🧪 Sample ROI data loaded for testing")
    }
    
    /// Export current ROI visibility state
    public func exportVisibilityState() -> [String: Any] {
        return [
            "globalVisible": isROIVisible,
            "globalOpacity": globalROIOpacity,
            "renderMode": roiRenderMode.rawValue,
            "roiVisibility": roiVisibility,
            "selectedROIs": Array(selectedROIs)
        ]
    }
    
    /// Import ROI visibility state
    public func importVisibilityState(_ state: [String: Any]) {
        if let globalVisible = state["globalVisible"] as? Bool {
            isROIVisible = globalVisible
        }
        
        if let opacity = state["globalOpacity"] as? Float {
            globalROIOpacity = opacity
        }
        
        if let visibility = state["roiVisibility"] as? [Int: Bool] {
            roiVisibility = visibility
        }
        
        if let selected = state["selectedROIs"] as? [Int] {
            selectedROIs = Set(selected)
        }
        
        print("📥 ROI visibility state imported")
    }
}
