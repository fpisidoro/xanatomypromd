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
            // Removed excessive debug logging for performance
            
            guard let roiData = roiData, roiSettings.isVisible else { 
                return 
            }
            
            // Render each ROI structure
            for roiStructure in roiData.roiStructures {
                // Get contours for current slice
                let contours = getContoursForCurrentSlice(
                    roiStructure: roiStructure,
                    slicePosition: 0,
                    plane: plane
                )
                
                // Only draw if we have actual contours at this position
                guard !contours.isEmpty else {
                    continue
                }
                
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
        roiStructure: MinimalRTStructParser.SimpleROIStructure,
        slicePosition: Float,
        plane: MPRPlane
    ) -> [MinimalRTStructParser.SimpleContour] {
        
        let currentWorldPos = coordinateSystem.currentWorldPosition
        
        switch plane {
        case .axial:
            // For axial view, match contours by Z position
            let currentZ = currentWorldPos.z
            
            // Use slice thickness as tolerance (typically 2-3mm for CT)
            // This ensures we show contours on the correct slice
            let tolerance = coordinateSystem.volumeSpacing.z * 0.5  // Half slice thickness
            
            print("   🔍 Axial slice Z-matching:")
            print("      📍 Current slice Z: \(currentZ)mm")
            print("      📏 Tolerance: ±\(tolerance)mm")
            
            // Filter contours that match current Z within tolerance
            let matchingContours = roiStructure.contours.filter { contour in
                let zDifference = abs(contour.slicePosition - currentZ)
                return zDifference <= tolerance
            }
            
            // Debug only if no matches found (error condition)
            if matchingContours.isEmpty && !roiStructure.contours.isEmpty {
                let nearestContour = roiStructure.contours.min { abs($0.slicePosition - currentZ) < abs($1.slicePosition - currentZ) }!
                let distance = abs(nearestContour.slicePosition - currentZ)
                print("      ⚠️ No matching contours! Nearest is at Z=\(nearestContour.slicePosition)mm (distance: \(distance)mm)")
            }
            
            return matchingContours
            
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
        // Group contours by Z position for interpolation
        let sortedContours = roiStructure.contours.sorted { $0.slicePosition < $1.slicePosition }
        var interpolatedPoints: [SIMD3<Float>] = []
        
        // Sample at regular Z intervals for smooth interpolation
        guard let firstZ = sortedContours.first?.slicePosition,
              let lastZ = sortedContours.last?.slicePosition else { return [] }
        
        let zStep = coordinateSystem.volumeSpacing.z * 0.5 // Sample at half slice spacing for smoothness
        var currentZ = firstZ
        
        while currentZ <= lastZ {
            // Find adjacent contours for interpolation
            let (below, above) = findAdjacentContours(sortedContours, targetZ: currentZ)
            
            if let belowContour = below, let aboveContour = above {
                // Interpolate between adjacent contours
                let t = (currentZ - belowContour.slicePosition) / 
                       (aboveContour.slicePosition - belowContour.slicePosition)
                
                // Find points at the X position for both contours
                let belowPoints = findContourPointsAtX(belowContour, xPosition: xPosition)
                let abovePoints = findContourPointsAtX(aboveContour, xPosition: xPosition)
                
                // Interpolate between the points
                for (bp, ap) in zip(belowPoints, abovePoints) {
                    let interpolated = bp + t * (ap - bp)
                    interpolatedPoints.append(interpolated)
                }
            } else if let exactContour = below ?? above {
                // Use exact contour if we're at an exact Z position
                let points = findContourPointsAtX(exactContour, xPosition: xPosition)
                interpolatedPoints.append(contentsOf: points)
            }
            
            currentZ += zStep
        }
        
        // Create smooth contour from interpolated points
        if interpolatedPoints.count >= 3 {
            let sortedPoints = sortPointsInPlane(interpolatedPoints, plane: .sagittal)
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
        // Group contours by Z position for interpolation
        let sortedContours = roiStructure.contours.sorted { $0.slicePosition < $1.slicePosition }
        var interpolatedPoints: [SIMD3<Float>] = []
        
        // Sample at regular Z intervals for smooth interpolation
        guard let firstZ = sortedContours.first?.slicePosition,
              let lastZ = sortedContours.last?.slicePosition else { return [] }
        
        let zStep = coordinateSystem.volumeSpacing.z * 0.5 // Sample at half slice spacing for smoothness
        var currentZ = firstZ
        
        while currentZ <= lastZ {
            // Find adjacent contours for interpolation
            let (below, above) = findAdjacentContours(sortedContours, targetZ: currentZ)
            
            if let belowContour = below, let aboveContour = above {
                // Interpolate between adjacent contours
                let t = (currentZ - belowContour.slicePosition) / 
                       (aboveContour.slicePosition - belowContour.slicePosition)
                
                // Find points at the Y position for both contours
                let belowPoints = findContourPointsAtY(belowContour, yPosition: yPosition)
                let abovePoints = findContourPointsAtY(aboveContour, yPosition: yPosition)
                
                // Interpolate between the points
                for (bp, ap) in zip(belowPoints, abovePoints) {
                    let interpolated = bp + t * (ap - bp)
                    interpolatedPoints.append(interpolated)
                }
            } else if let exactContour = below ?? above {
                // Use exact contour if we're at an exact Z position
                let points = findContourPointsAtY(exactContour, yPosition: yPosition)
                interpolatedPoints.append(contentsOf: points)
            }
            
            currentZ += zStep
        }
        
        // Create smooth contour from interpolated points
        if interpolatedPoints.count >= 3 {
            let sortedPoints = sortPointsInPlane(interpolatedPoints, plane: .coronal)
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
            return 
        }
        
        // Convert 3D contour points to 2D screen coordinates using coordinate system
        let screenPoints = contour.points.map { point3D in
            coordinateSystem.worldToScreen(
                position: point3D,
                plane: plane,
                viewSize: size
            )
        }
        
        // Filter out invalid screen points (outside reasonable bounds)
        let validScreenPoints = screenPoints.filter { point in
            point.x.isFinite && point.y.isFinite &&
            point.x >= -1000 && point.x <= size.width + 1000 &&
            point.y >= -1000 && point.y <= size.height + 1000
        }
        
        guard validScreenPoints.count >= 3 else {
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
    
    // MARK: - Helper Functions for Interpolation
    
    /// Find adjacent contours above and below target Z position
    private func findAdjacentContours(
        _ sortedContours: [MinimalRTStructParser.SimpleContour],
        targetZ: Float
    ) -> (below: MinimalRTStructParser.SimpleContour?, above: MinimalRTStructParser.SimpleContour?) {
        var below: MinimalRTStructParser.SimpleContour?
        var above: MinimalRTStructParser.SimpleContour?
        
        for contour in sortedContours {
            if contour.slicePosition <= targetZ {
                below = contour
            } else if above == nil {
                above = contour
                break
            }
        }
        
        return (below, above)
    }
    
    /// Find points where contour intersects X plane
    private func findContourPointsAtX(
        _ contour: MinimalRTStructParser.SimpleContour,
        xPosition: Float
    ) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        
        for i in 0..<contour.points.count {
            let p1 = contour.points[i]
            let p2 = contour.points[(i + 1) % contour.points.count]
            
            // Check if edge crosses X plane
            if (p1.x <= xPosition && p2.x >= xPosition) ||
               (p1.x >= xPosition && p2.x <= xPosition) {
                // Calculate intersection
                let t = (xPosition - p1.x) / (p2.x - p1.x)
                if t >= 0.0 && t <= 1.0 {
                    let intersection = p1 + t * (p2 - p1)
                    points.append(intersection)
                }
            }
        }
        
        return points
    }
    
    /// Find points where contour intersects Y plane
    private func findContourPointsAtY(
        _ contour: MinimalRTStructParser.SimpleContour,
        yPosition: Float
    ) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        
        for i in 0..<contour.points.count {
            let p1 = contour.points[i]
            let p2 = contour.points[(i + 1) % contour.points.count]
            
            // Check if edge crosses Y plane
            if (p1.y <= yPosition && p2.y >= yPosition) ||
               (p1.y >= yPosition && p2.y <= yPosition) {
                // Calculate intersection
                let t = (yPosition - p1.y) / (p2.y - p1.y)
                if t >= 0.0 && t <= 1.0 {
                    let intersection = p1 + t * (p2 - p1)
                    points.append(intersection)
                }
            }
        }
        
        return points
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
