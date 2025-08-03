import SwiftUI
import simd

// MARK: - Layer 3: ROI Overlay Layer
// Pure overlay that renders anatomical structures from RTStruct data
// Completely independent - only depends on coordinate system for spatial alignment

struct ROIOverlayLayer: View {
    
    // MARK: - Configuration
    
    /// The authoritative coordinate system (shared with all layers)
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    
    /// Current anatomical plane to display ROIs for
    let plane: MPRPlane
    
    /// View size for coordinate transformations
    let viewSize: CGSize
    
    /// ROI data source
    let roiData: RTStructData?
    
    /// ROI display settings
    let roiSettings: ROIDisplaySettings
    
    // MARK: - Body
    
    var body: some View {
        Canvas { context, size in
            guard let roiData = roiData, roiSettings.isVisible else { return }
            
            // Get current slice position from coordinate system
            let currentSlicePosition = coordinateSystem.getCurrentSliceIndex(for: plane)
            
            // Render each ROI structure
            for roiStructure in roiData.roiStructures {
                guard roiStructure.isVisible else { continue }
                
                // Get contours for current slice
                let contours = getContoursForCurrentSlice(
                    roiStructure: roiStructure,
                    slicePosition: Float(currentSlicePosition),
                    plane: plane
                )
                
                // Draw each contour
                for contour in contours {
                    drawContour(
                        contour: contour,
                        roiStructure: roiStructure,
                        context: context,
                        size: size
                    )
                }
            }
        }
        .allowsHitTesting(false) // Allow touches to pass through
        .opacity(roiSettings.globalOpacity)
        .onChange(of: coordinateSystem.currentWorldPosition) { _ in
            // Automatically updates when coordinate system changes
        }
    }
    
    // MARK: - ROI Geometry Calculation
    
    /// Get contours that should be visible on the current slice
    private func getContoursForCurrentSlice(
        roiStructure: ROIStructure,
        slicePosition: Float,
        plane: MPRPlane
    ) -> [ROIContour] {
        switch plane {
        case .axial:
            // Axial: show contours at current Z slice
            return roiStructure.contours.filter { contour in
                abs(contour.slicePosition - slicePosition) < roiSettings.sliceTolerance
            }
            
        case .sagittal:
            // Sagittal: create cross-section at current X position
            return createSagittalCrossSection(
                roiStructure: roiStructure,
                xPosition: slicePosition
            )
            
        case .coronal:
            // Coronal: create cross-section at current Y position
            return createCoronalCrossSection(
                roiStructure: roiStructure,
                yPosition: slicePosition
            )
        }
    }
    
    /// Create sagittal cross-section (YZ plane) at specific X position
    private func createSagittalCrossSection(
        roiStructure: ROIStructure,
        xPosition: Float
    ) -> [ROIContour] {
        var crossSectionPoints: [SIMD3<Float>] = []
        
        // Find intersections with all contours
        for contour in roiStructure.contours {
            let intersections = findPlaneIntersections(
                contour: contour,
                planeAxis: 0, // X-axis
                planePosition: xPosition
            )
            crossSectionPoints.append(contentsOf: intersections)
        }
        
        // Create contour from intersection points if enough points found
        if crossSectionPoints.count >= 3 {
            let sortedPoints = sortPointsInPlane(crossSectionPoints, plane: .sagittal)
            return [ROIContour(
                contourNumber: 1,
                geometricType: .closedPlanar,
                numberOfPoints: sortedPoints.count,
                contourData: sortedPoints,
                slicePosition: xPosition
            )]
        }
        
        return []
    }
    
    /// Create coronal cross-section (XZ plane) at specific Y position
    private func createCoronalCrossSection(
        roiStructure: ROIStructure,
        yPosition: Float
    ) -> [ROIContour] {
        var crossSectionPoints: [SIMD3<Float>] = []
        
        // Find intersections with all contours
        for contour in roiStructure.contours {
            let intersections = findPlaneIntersections(
                contour: contour,
                planeAxis: 1, // Y-axis
                planePosition: yPosition
            )
            crossSectionPoints.append(contentsOf: intersections)
        }
        
        // Create contour from intersection points if enough points found
        if crossSectionPoints.count >= 3 {
            let sortedPoints = sortPointsInPlane(crossSectionPoints, plane: .coronal)
            return [ROIContour(
                contourNumber: 1,
                geometricType: .closedPlanar,
                numberOfPoints: sortedPoints.count,
                contourData: sortedPoints,
                slicePosition: yPosition
            )]
        }
        
        return []
    }
    
    /// Find intersections between contour edges and a plane
    private func findPlaneIntersections(
        contour: ROIContour,
        planeAxis: Int,
        planePosition: Float
    ) -> [SIMD3<Float>] {
        var intersections: [SIMD3<Float>] = []
        
        for i in 0..<contour.contourData.count {
            let p1 = contour.contourData[i]
            let p2 = contour.contourData[(i + 1) % contour.contourData.count]
            
            let coord1 = p1[planeAxis]
            let coord2 = p2[planeAxis]
            
            // Check if edge crosses the plane
            if (coord1 <= planePosition && coord2 >= planePosition) ||
               (coord1 >= planePosition && coord2 <= planePosition) {
                
                // Calculate intersection point using linear interpolation
                let t = (planePosition - coord1) / (coord2 - coord1)
                if t >= 0.0 && t <= 1.0 {
                    let intersection = p1 + t * (p2 - p1)
                    intersections.append(intersection)
                }
            }
        }
        
        return intersections
    }
    
    /// Sort points in circular order for a given plane
    private func sortPointsInPlane(_ points: [SIMD3<Float>], plane: MPRPlane) -> [SIMD3<Float>] {
        guard points.count >= 3 else { return points }
        
        // Remove duplicate points
        var uniquePoints: [SIMD3<Float>] = []
        for point in points {
            let isDuplicate = uniquePoints.contains { existingPoint in
                let diff = point - existingPoint
                return sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z) < 1.0
            }
            if !isDuplicate {
                uniquePoints.append(point)
            }
        }
        
        guard uniquePoints.count >= 3 else { return points }
        
        // Sort points in circular order based on plane
        switch plane {
        case .axial:
            // Sort by angle in XY plane
            let centerX = uniquePoints.map { $0.x }.reduce(0, +) / Float(uniquePoints.count)
            let centerY = uniquePoints.map { $0.y }.reduce(0, +) / Float(uniquePoints.count)
            
            return uniquePoints.sorted { p1, p2 in
                let angle1 = atan2(p1.y - centerY, p1.x - centerX)
                let angle2 = atan2(p2.y - centerY, p2.x - centerX)
                return angle1 < angle2
            }
            
        case .sagittal:
            // Sort by angle in YZ plane
            let centerY = uniquePoints.map { $0.y }.reduce(0, +) / Float(uniquePoints.count)
            let centerZ = uniquePoints.map { $0.z }.reduce(0, +) / Float(uniquePoints.count)
            
            return uniquePoints.sorted { p1, p2 in
                let angle1 = atan2(p1.z - centerZ, p1.y - centerY)
                let angle2 = atan2(p2.z - centerZ, p2.y - centerY)
                return angle1 < angle2
            }
            
        case .coronal:
            // Sort by angle in XZ plane
            let centerX = uniquePoints.map { $0.x }.reduce(0, +) / Float(uniquePoints.count)
            let centerZ = uniquePoints.map { $0.z }.reduce(0, +) / Float(uniquePoints.count)
            
            return uniquePoints.sorted { p1, p2 in
                let angle1 = atan2(p1.z - centerZ, p1.x - centerX)
                let angle2 = atan2(p2.z - centerZ, p2.x - centerX)
                return angle1 < angle2
            }
        }
    }
    
    // MARK: - ROI Rendering
    
    /// Draw a single contour on the canvas
    private func drawContour(
        contour: ROIContour,
        roiStructure: ROIStructure,
        context: GraphicsContext,
        size: CGSize
    ) {
        guard contour.contourData.count >= 3 else { return }
        
        // Convert 3D contour points to 2D screen coordinates using coordinate system
        let screenPoints = contour.contourData.map { point3D in
            coordinateSystem.worldToScreen(
                position: point3D,
                plane: plane,
                viewSize: size
            )
        }
        
        // Create path from screen points
        var path = Path()
        if let firstPoint = screenPoints.first {
            path.move(to: firstPoint)
            for point in screenPoints.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
        
        // Create color from ROI structure
        let roiColor = Color(
            red: Double(roiStructure.displayColor.x),
            green: Double(roiStructure.displayColor.y),
            blue: Double(roiStructure.displayColor.z)
        )
        
        // Draw filled contour if enabled
        if roiSettings.showFilled {
            context.fill(
                path,
                with: .color(roiColor.opacity(Double(roiStructure.opacity) * roiSettings.fillOpacity))
            )
        }
        
        // Draw contour outline
        if roiSettings.showOutline {
            context.stroke(
                path,
                with: .color(roiColor.opacity(Double(roiStructure.opacity) * roiSettings.outlineOpacity)),
                style: StrokeStyle(
                    lineWidth: roiSettings.outlineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }
}

// MARK: - ROI Display Settings

struct ROIDisplaySettings {
    let isVisible: Bool
    let globalOpacity: Double
    let showOutline: Bool
    let showFilled: Bool
    let outlineWidth: CGFloat
    let outlineOpacity: Double
    let fillOpacity: Double
    let sliceTolerance: Float  // mm tolerance for slice matching
    
    static let `default` = ROIDisplaySettings(
        isVisible: true,
        globalOpacity: 1.0,
        showOutline: true,
        showFilled: true,
        outlineWidth: 1.5,
        outlineOpacity: 0.8,
        fillOpacity: 0.3,
        sliceTolerance: 2.0
    )
    
    static let outlineOnly = ROIDisplaySettings(
        isVisible: true,
        globalOpacity: 1.0,
        showOutline: true,
        showFilled: false,
        outlineWidth: 2.0,
        outlineOpacity: 1.0,
        fillOpacity: 0.0,
        sliceTolerance: 2.0
    )
    
    static let subtle = ROIDisplaySettings(
        isVisible: true,
        globalOpacity: 0.6,
        showOutline: true,
        showFilled: true,
        outlineWidth: 1.0,
        outlineOpacity: 0.6,
        fillOpacity: 0.2,
        sliceTolerance: 2.0
    )
}
