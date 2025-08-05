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
    let roiData: MinimalRTStructParser.SimpleRTStructData?
    
    /// ROI display settings
    let roiSettings: ROIDisplaySettings
    
    // MARK: - Body
    
    var body: some View {
        Canvas { context, size in
            guard let roiData = roiData, roiSettings.isVisible else { 
                // Debug: ROI not visible or no data
                return 
            }
            
            print("🎨 ROI Drawing on \(plane): \(roiData.roiStructures.count) ROI structures, world pos: \(coordinateSystem.currentWorldPosition)")
            
            // Render each ROI structure
            var totalContoursDrawn = 0
            for roiStructure in roiData.roiStructures {
                // SimpleROIStructure doesn't have isVisible, assume all are visible
                
                // Get contours for current slice - no longer need slice position parameter
                let contours = getContoursForCurrentSlice(
                    roiStructure: roiStructure,
                    slicePosition: 0, // Not used anymore
                    plane: plane
                )
                
                // FALLBACK TEST: If no contours found, try showing the first contour regardless of position
                let finalContours: [MinimalRTStructParser.SimpleContour]
                if contours.isEmpty && plane == .axial {
                    print("   ⚠️ No contours at current position, showing first contour for testing")
                    finalContours = Array(roiStructure.contours.prefix(1))
                } else {
                    finalContours = contours
                }
                
                print("   📊 ROI \(roiStructure.roiNumber): '\(roiStructure.roiName)' - \(finalContours.count) contours")
                
                // Draw each contour
                for (index, contour) in finalContours.enumerated() {
                    print("      📐 Drawing contour \(index): \(contour.points.count) points")
                    drawContour(
                        contour: contour,
                        roiStructure: roiStructure,
                        context: context,
                        size: size
                    )
                    totalContoursDrawn += 1
                }
            }
            
            print("🎨 ROI Drawing Complete: \(totalContoursDrawn) contours drawn")
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
        roiStructure: MinimalRTStructParser.SimpleROIStructure,
        slicePosition: Float,
        plane: MPRPlane
    ) -> [MinimalRTStructParser.SimpleContour] {
        // Get current world position from coordinate system
        let currentWorldPos = coordinateSystem.currentWorldPosition
        
        switch plane {
        case .axial:
            // Axial: show contours at current Z slice (use world Z position)
            let axialContours = roiStructure.contours.filter { contour in
                abs(contour.slicePosition - currentWorldPos.z) < roiSettings.sliceTolerance
            }
            print("   📍 Axial: Found \(axialContours.count) contours near Z=\(currentWorldPos.z) (tolerance: \(roiSettings.sliceTolerance))")
            if !axialContours.isEmpty {
                print("      📍 Contour Z positions: \(axialContours.map { $0.slicePosition })")
            }
            return axialContours
            
        case .sagittal:
            // Sagittal: create cross-section at current X position
            return createSagittalCrossSection(
                roiStructure: roiStructure,
                xPosition: currentWorldPos.x
            )
            
        case .coronal:
            // Coronal: create cross-section at current Y position
            return createCoronalCrossSection(
                roiStructure: roiStructure,
                yPosition: currentWorldPos.y
            )
        }
    }
    
    /// Create sagittal cross-section (YZ plane) at specific X position
    private func createSagittalCrossSection(
        roiStructure: MinimalRTStructParser.SimpleROIStructure,
        xPosition: Float
    ) -> [MinimalRTStructParser.SimpleContour] {
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
            return [MinimalRTStructParser.SimpleContour(
                points: sortedPoints,
                slicePosition: xPosition
            )]
        }
        
        return []
    }
    
    /// Create coronal cross-section (XZ plane) at specific Y position
    private func createCoronalCrossSection(
        roiStructure: MinimalRTStructParser.SimpleROIStructure,
        yPosition: Float
    ) -> [MinimalRTStructParser.SimpleContour] {
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
            return [MinimalRTStructParser.SimpleContour(
                points: sortedPoints,
                slicePosition: yPosition
            )]
        }
        
        return []
    }
    
    /// Find intersections between contour edges and a plane
    private func findPlaneIntersections(
        contour: MinimalRTStructParser.SimpleContour,
        planeAxis: Int,
        planePosition: Float
    ) -> [SIMD3<Float>] {
        var intersections: [SIMD3<Float>] = []
        
        for i in 0..<contour.points.count {
            let p1 = contour.points[i]
            let p2 = contour.points[(i + 1) % contour.points.count]
            
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
        contour: MinimalRTStructParser.SimpleContour,
        roiStructure: MinimalRTStructParser.SimpleROIStructure,
        context: GraphicsContext,
        size: CGSize
    ) {
        guard contour.points.count >= 3 else { 
            print("         ⚠️ Skipping contour with only \(contour.points.count) points")
            return 
        }
        
        // Debug: Show first few points
        print("         📍 Sample world coord: \(contour.points.first ?? SIMD3<Float>(0,0,0))")
        
        // Convert 3D contour points to 2D screen coordinates using coordinate system
        let screenPoints = contour.points.map { point3D in
            coordinateSystem.worldToScreen(
                position: point3D,
                plane: plane,
                viewSize: size
            )
        }
        
        // Debug: Show converted screen points
        print("         🖥️ Sample screen coord: \(screenPoints.first ?? CGPoint(x: 0, y: 0))")
        
        // Filter out invalid screen points (outside reasonable bounds)
        let validScreenPoints = screenPoints.filter { point in
            point.x.isFinite && point.y.isFinite &&
            point.x >= -1000 && point.x <= size.width + 1000 &&
            point.y >= -1000 && point.y <= size.height + 1000
        }
        
        guard validScreenPoints.count >= 3 else {
            print("         ⚠️ Only \(validScreenPoints.count) valid screen points, skipping")
            return
        }
        
        // Create path from screen points
        var path = Path()
        if let firstPoint = validScreenPoints.first {
            path.move(to: firstPoint)
            for point in validScreenPoints.dropFirst() {
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
        
        print("         🎨 Drawing path with \(validScreenPoints.count) points, color: \(roiStructure.displayColor)")
        
        // Draw filled contour if enabled
        if roiSettings.showFilled {
            context.fill(
                path,
                with: .color(roiColor.opacity(roiSettings.fillOpacity))
            )
        }
        
        // Draw contour outline
        if roiSettings.showOutline {
            context.stroke(
                path,
                with: .color(roiColor.opacity(roiSettings.outlineOpacity)),
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
