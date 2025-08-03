import Foundation
import simd

// MARK: - Clean ROI Manager
// Simple manager for ROI display without complex dependencies

public class CleanROIManager: ObservableObject {
    
    // MARK: - Properties
    
    @Published public var isROIVisible: Bool = true
    @Published public var roiOpacity: Float = 0.7
    @Published public var selectedROI: String? = nil
    
    private var roiStructures: [ROIStructure] = []
    private var rtStructData: RTStructData?
    
    // MARK: - Initialization
    
    public init() {
        // Load test ROI data
        loadTestROIData()
    }
    
    // MARK: - Public Interface
    
    public func getROIStructures() -> [ROIStructure] {
        return roiStructures
    }
    
    public func setROIVisibility(_ visible: Bool) {
        isROIVisible = visible
    }
    
    public func setROIOpacity(_ opacity: Float) {
        roiOpacity = max(0.0, min(1.0, opacity))
    }
    
    public func selectROI(_ roiName: String?) {
        selectedROI = roiName
    }
    
    public func loadRTStruct(_ rtStruct: RTStructData) {
        rtStructData = rtStruct
        roiStructures = rtStruct.roiStructures
        print("✅ Loaded RTStruct with \(roiStructures.count) ROI structures")
    }
    
    // MARK: - Test Data Generation
    
    private func loadTestROIData() {
        // Create test ROI structures for visualization
        let testROIs = createTestROIStructures()
        roiStructures = testROIs
        
        print("✅ CleanROIManager initialized with \(roiStructures.count) test ROI structures")
    }
    
    private func createTestROIStructures() -> [ROIStructure] {
        var rois: [ROIStructure] = []
        
        // ROI 1: Heart (Red)
        let heartContours = createCircularContours(
            centerX: 256, centerY: 256, 
            radius: 40, 
            startZ: 60, endZ: 100, 
            sliceSpacing: 3.0
        )
        
        let heartROI = ROIStructure(
            roiNumber: 1,
            roiName: "Heart",
            roiDescription: "Cardiac structure",
            displayColor: SIMD3<Float>(1.0, 0.0, 0.0), // Red
            isVisible: true,
            opacity: 0.7,
            contours: heartContours
        )
        rois.append(heartROI)
        
        // ROI 2: Lung Left (Blue)
        let leftLungContours = createCircularContours(
            centerX: 180, centerY: 256,
            radius: 60,
            startZ: 50, endZ: 120,
            sliceSpacing: 3.0
        )
        
        let leftLungROI = ROIStructure(
            roiNumber: 2,
            roiName: "Lung_Left",
            roiDescription: "Left lung",
            displayColor: SIMD3<Float>(0.0, 0.0, 1.0), // Blue
            isVisible: true,
            opacity: 0.5,
            contours: leftLungContours
        )
        rois.append(leftLungROI)
        
        // ROI 3: Lung Right (Green)
        let rightLungContours = createCircularContours(
            centerX: 330, centerY: 256,
            radius: 60,
            startZ: 50, endZ: 120,
            sliceSpacing: 3.0
        )
        
        let rightLungROI = ROIStructure(
            roiNumber: 3,
            roiName: "Lung_Right",
            roiDescription: "Right lung",
            displayColor: SIMD3<Float>(0.0, 1.0, 0.0), // Green
            isVisible: true,
            opacity: 0.5,
            contours: rightLungContours
        )
        rois.append(rightLungROI)
        
        return rois
    }
    
    private func createCircularContours(
        centerX: Float, centerY: Float,
        radius: Float,
        startZ: Float, endZ: Float,
        sliceSpacing: Float
    ) -> [ROIContour] {
        var contours: [ROIContour] = []
        var contourNumber = 1
        
        var currentZ = startZ
        while currentZ <= endZ {
            let points = createCircularContourPoints(
                centerX: centerX, 
                centerY: centerY, 
                radius: radius, 
                z: currentZ
            )
            
            let contour = ROIContour(
                contourNumber: contourNumber,
                geometricType: .closedPlanar,
                numberOfPoints: points.count,
                contourData: points,
                slicePosition: currentZ
            )
            
            contours.append(contour)
            contourNumber += 1
            currentZ += sliceSpacing
        }
        
        return contours
    }
    
    private func createCircularContourPoints(
        centerX: Float, centerY: Float, 
        radius: Float, 
        z: Float,
        numberOfPoints: Int = 16
    ) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        
        for i in 0..<numberOfPoints {
            let angle = Float(i) * 2.0 * .pi / Float(numberOfPoints)
            let x = centerX + radius * cos(angle)
            let y = centerY + radius * sin(angle)
            
            points.append(SIMD3<Float>(x, y, z))
        }
        
        return points
    }
    
    // MARK: - ROI Queries
    
    public func getROIForSlice(_ slicePosition: Float, plane: MPRPlane, tolerance: Float = 2.0) -> [ROIStructure] {
        return roiStructures.filter { roi in
            roi.isVisible && roi.contours.contains { contour in
                contour.intersectsSlice(slicePosition, plane: plane, tolerance: tolerance)
            }
        }
    }
    
    public func getVisibleROIs() -> [ROIStructure] {
        return roiStructures.filter { $0.isVisible }
    }
    
    public func getROINames() -> [String] {
        return roiStructures.map { $0.roiName }
    }
    
    // MARK: - ROI Manipulation
    
    public func setROIVisibility(_ roiName: String, visible: Bool) {
        // Note: ROIStructure is immutable, so we'd need to recreate the array
        // For now, this is a placeholder for the interface
        print("Setting \(roiName) visibility to \(visible)")
    }
    
    public func setROIOpacity(_ roiName: String, opacity: Float) {
        // Note: ROIStructure is immutable, so we'd need to recreate the array
        // For now, this is a placeholder for the interface
        print("Setting \(roiName) opacity to \(opacity)")
    }
    
    public func setROIColor(_ roiName: String, color: SIMD3<Float>) {
        // Note: ROIStructure is immutable, so we'd need to recreate the array
        // For now, this is a placeholder for the interface
        print("Setting \(roiName) color to \(color)")
    }
}

// MARK: - ROI Statistics

extension CleanROIManager {
    
    public func getROIStatistics() -> String {
        let visibleCount = getVisibleROIs().count
        let totalContours = roiStructures.reduce(0) { $0 + $1.contours.count }
        let totalPoints = roiStructures.reduce(0) { $0 + $1.totalPoints }
        
        return """
        📊 ROI Manager Statistics:
           🎯 Total ROIs: \(roiStructures.count) (\(visibleCount) visible)
           📐 Total contours: \(totalContours)
           📍 Total points: \(totalPoints)
           👁️ Visibility: \(isROIVisible ? "ON" : "OFF")
           🎨 Opacity: \(String(format: "%.1f", roiOpacity))
        """
    }
}
