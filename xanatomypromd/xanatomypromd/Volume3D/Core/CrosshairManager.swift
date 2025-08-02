import Foundation
import SwiftUI
import simd

// MARK: - 3D Crosshair Coordinate Manager
// Manages synchronized crosshair position across all MPR views

@MainActor
class CrosshairManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current 3D world position of crosshair in millimeters
    @Published var worldPosition: SIMD3<Float>
    
    /// Crosshair visibility
    @Published var isVisible: Bool = true
    
    /// Crosshair opacity
    @Published var opacity: Float = 0.8
    
    // MARK: - Volume Properties
    
    /// Volume dimensions in voxels (width, height, depth)
    private let volumeDimensions: SIMD3<Int>
    
    /// Voxel spacing in millimeters (x, y, z)
    private let volumeSpacing: SIMD3<Float>
    
    /// Volume origin in millimeters (x, y, z)
    private let volumeOrigin: SIMD3<Float>
    
    // MARK: - Initialization
    
    init(
        volumeDimensions: SIMD3<Int> = SIMD3<Int>(512, 512, 53),
        volumeSpacing: SIMD3<Float> = SIMD3<Float>(0.7, 0.7, 3.0),
        volumeOrigin: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    ) {
        self.volumeDimensions = volumeDimensions
        self.volumeSpacing = volumeSpacing
        self.volumeOrigin = volumeOrigin
        
        // Initialize crosshair at center of volume
        let centerX = volumeOrigin.x + (Float(volumeDimensions.x) * volumeSpacing.x) / 2.0
        let centerY = volumeOrigin.y + (Float(volumeDimensions.y) * volumeSpacing.y) / 2.0
        let centerZ = volumeOrigin.z + (Float(volumeDimensions.z) * volumeSpacing.z) / 2.0
        
        self.worldPosition = SIMD3<Float>(centerX, centerY, centerZ)
        
        print("🎯 CrosshairManager initialized at center: (\(centerX), \(centerY), \(centerZ)) mm")
    }
    
    // MARK: - Slice Index Calculation
    
    /// Get the slice index for the current crosshair position in the specified plane
    func getSliceIndex(for plane: MPRPlane) -> Int {
        let axis = plane.sliceAxis
        let coordinate = worldPosition[axis]
        
        // Convert world coordinate to slice index
        let sliceIndex = Int((coordinate - volumeOrigin[axis]) / volumeSpacing[axis])
        
        // Clamp to valid range
        let maxSlice = volumeDimensions[axis] - 1
        return max(0, min(sliceIndex, maxSlice))
    }
    
    /// Get the maximum number of slices for the specified plane
    func getMaxSlices(for plane: MPRPlane) -> Int {
        return volumeDimensions[plane.sliceAxis]
    }
    
    // MARK: - Crosshair Position Updates
    
    /// Update crosshair position when user scrolls in a specific plane
    func updateFromSliceScroll(plane: MPRPlane, sliceIndex: Int) {
        let axis = plane.sliceAxis
        let clampedIndex = max(0, min(sliceIndex, volumeDimensions[axis] - 1))
        
        // Convert slice index back to world coordinate
        let newCoordinate = volumeOrigin[axis] + Float(clampedIndex) * volumeSpacing[axis]
        
        // Update the appropriate axis of world position
        switch axis {
        case 0: worldPosition.x = newCoordinate
        case 1: worldPosition.y = newCoordinate
        case 2: worldPosition.z = newCoordinate
        default: break
        }
        
        print("🎯 Crosshair updated from \(plane.displayName) scroll: slice \(clampedIndex) → \(newCoordinate)mm")
    }
    
    /// Set crosshair to specific 3D world position
    func setCrosshairPosition(_ position: SIMD3<Float>) {
        // Clamp position to volume bounds
        let clampedX = max(volumeOrigin.x, min(position.x, volumeOrigin.x + Float(volumeDimensions.x) * volumeSpacing.x))
        let clampedY = max(volumeOrigin.y, min(position.y, volumeOrigin.y + Float(volumeDimensions.y) * volumeSpacing.y))
        let clampedZ = max(volumeOrigin.z, min(position.z, volumeOrigin.z + Float(volumeDimensions.z) * volumeSpacing.z))
        
        worldPosition = SIMD3<Float>(clampedX, clampedY, clampedZ)
        
        print("🎯 Crosshair set to: (\(clampedX), \(clampedY), \(clampedZ)) mm")
    }
    
    /// Center crosshair on a specific ROI
    func centerOnROI(_ roi: ROIStructure) {
        guard !roi.contours.isEmpty else { return }
        
        // Calculate center of all ROI contour points
        var totalPoints: [SIMD3<Float>] = []
        for contour in roi.contours {
            totalPoints.append(contentsOf: contour.contourData)
        }
        
        guard !totalPoints.isEmpty else { return }
        
        let centerX = totalPoints.map { $0.x }.reduce(0, +) / Float(totalPoints.count)
        let centerY = totalPoints.map { $0.y }.reduce(0, +) / Float(totalPoints.count)
        let centerZ = totalPoints.map { $0.z }.reduce(0, +) / Float(totalPoints.count)
        
        setCrosshairPosition(SIMD3<Float>(centerX, centerY, centerZ))
        
        print("🎯 Crosshair centered on ROI '\(roi.roiName)' at (\(centerX), \(centerY), \(centerZ)) mm")
    }
    
    // MARK: - Crosshair Display Properties
    
    /// Get crosshair position in 2D screen coordinates for the specified plane
    func getCrosshairScreenPosition(for plane: MPRPlane, viewSize: CGSize) -> CGPoint {
        let axes = plane.planeAxes
        let coord1 = worldPosition[axes.0]
        let coord2 = worldPosition[axes.1]
        
        // Convert to normalized coordinates (0-1)
        let norm1 = (coord1 - volumeOrigin[axes.0]) / (Float(volumeDimensions[axes.0]) * volumeSpacing[axes.0])
        let norm2 = (coord2 - volumeOrigin[axes.1]) / (Float(volumeDimensions[axes.1]) * volumeSpacing[axes.1])
        
        // Convert to screen coordinates
        let screenX = Double(norm1) * viewSize.width
        let screenY = Double(norm2) * viewSize.height
        
        return CGPoint(x: screenX, y: screenY)
    }
    
    /// Get crosshair line endpoints for horizontal line
    func getHorizontalCrosshairLine(for plane: MPRPlane, viewSize: CGSize) -> (CGPoint, CGPoint) {
        let center = getCrosshairScreenPosition(for: plane, viewSize: viewSize)
        return (
            CGPoint(x: 0, y: center.y),
            CGPoint(x: viewSize.width, y: center.y)
        )
    }
    
    /// Get crosshair line endpoints for vertical line
    func getVerticalCrosshairLine(for plane: MPRPlane, viewSize: CGSize) -> (CGPoint, CGPoint) {
        let center = getCrosshairScreenPosition(for: plane, viewSize: viewSize)
        return (
            CGPoint(x: center.x, y: 0),
            CGPoint(x: center.x, y: viewSize.height)
        )
    }
    
    // MARK: - Debug Information
    
    func getDebugInfo() -> String {
        let sliceAxial = getSliceIndex(for: .axial)
        let sliceSagittal = getSliceIndex(for: .sagittal)
        let sliceCoronal = getSliceIndex(for: .coronal)
        
        return """
        🎯 Crosshair: (\(String(format: "%.1f", worldPosition.x)), \(String(format: "%.1f", worldPosition.y)), \(String(format: "%.1f", worldPosition.z))) mm
        📐 Slices: AX=\(sliceAxial), SAG=\(sliceSagittal), COR=\(sliceCoronal)
        """
    }
}

// MARK: - Crosshair Overlay View
// SwiftUI view that renders the green crosshairs with fade pattern

struct CrosshairOverlayView: View {
    @ObservedObject var crosshairManager: CrosshairManager
    let plane: MPRPlane
    let viewSize: CGSize
    
    var body: some View {
        ZStack {
            if crosshairManager.isVisible {
                // Horizontal crosshair line
                CrosshairLine(
                    startPoint: crosshairManager.getHorizontalCrosshairLine(for: plane, viewSize: viewSize).0,
                    endPoint: crosshairManager.getHorizontalCrosshairLine(for: plane, viewSize: viewSize).1,
                    centerPoint: crosshairManager.getCrosshairScreenPosition(for: plane, viewSize: viewSize),
                    opacity: Double(crosshairManager.opacity),
                    isHorizontal: true
                )
                
                // Vertical crosshair line
                CrosshairLine(
                    startPoint: crosshairManager.getVerticalCrosshairLine(for: plane, viewSize: viewSize).0,
                    endPoint: crosshairManager.getVerticalCrosshairLine(for: plane, viewSize: viewSize).1,
                    centerPoint: crosshairManager.getCrosshairScreenPosition(for: plane, viewSize: viewSize),
                    opacity: Double(crosshairManager.opacity),
                    isHorizontal: false
                )
            }
        }
        .allowsHitTesting(false) // Allow touches to pass through
    }
}

// MARK: - Individual Crosshair Line with Fade Pattern

struct CrosshairLine: View {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let centerPoint: CGPoint
    let opacity: Double
    let isHorizontal: Bool
    
    var body: some View {
        Canvas { context, size in
            // Create path for the crosshair line
            var path = Path()
            path.move(to: startPoint)
            path.addLine(to: endPoint)
            
            // Create gradient that fades near center (like MIM)
            let gradient = createCrosshairGradient()
            
            // Draw the line with gradient stroke
            context.stroke(
                path,
                with: .linearGradient(
                    gradient,
                    startPoint: startPoint,
                    endPoint: endPoint
                ),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
        }
        .opacity(opacity)
    }
    
    private func createCrosshairGradient() -> Gradient {
        // Create fade pattern: dense at edges, faded in center (like MIM crosshairs)
        return Gradient(stops: [
            .init(color: .green, location: 0.0),      // Dense at start
            .init(color: .green, location: 0.3),      // Still visible
            .init(color: .green.opacity(0.1), location: 0.45),  // Fade starts
            .init(color: .green.opacity(0.0), location: 0.5),   // Invisible at center
            .init(color: .green.opacity(0.1), location: 0.55),  // Fade ends
            .init(color: .green, location: 0.7),      // Visible again
            .init(color: .green, location: 1.0)       // Dense at end
        ])
    }
}
