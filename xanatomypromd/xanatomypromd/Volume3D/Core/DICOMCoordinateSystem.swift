import Foundation
import SwiftUI
import simd

// MARK: - DICOM Coordinate System Authority
// THE single source of truth for all spatial transformations in the app
// All layers MUST use this for coordinate conversions to ensure alignment

@MainActor
class DICOMCoordinateSystem: ObservableObject {
    
    // MARK: - DICOM Volume Properties (Authoritative)
    
    /// Volume origin in patient coordinates (mm) - from DICOM ImagePositionPatient
    @Published var volumeOrigin: SIMD3<Float>
    
    /// Voxel spacing in mm (x, y, z) - from DICOM PixelSpacing + SliceThickness
    @Published var volumeSpacing: SIMD3<Float>
    
    /// Volume dimensions in voxels (width, height, depth) - from DICOM matrix
    @Published var volumeDimensions: SIMD3<Int>
    
    /// Current 3D world position in patient coordinates (mm)
    @Published var currentWorldPosition: SIMD3<Float>
    
    // MARK: - Initialization
    
    init(
        volumeOrigin: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        volumeSpacing: SIMD3<Float> = SIMD3<Float>(0.7, 0.7, 3.0),
        volumeDimensions: SIMD3<Int> = SIMD3<Int>(512, 512, 53)
    ) {
        self.volumeOrigin = volumeOrigin
        self.volumeSpacing = volumeSpacing
        self.volumeDimensions = volumeDimensions
        
        // Initialize at center of volume
        let centerX = volumeOrigin.x + (Float(volumeDimensions.x) * volumeSpacing.x) / 2.0
        let centerY = volumeOrigin.y + (Float(volumeDimensions.y) * volumeSpacing.y) / 2.0
        let centerZ = volumeOrigin.z + (Float(volumeDimensions.z) * volumeSpacing.z) / 2.0
        
        self.currentWorldPosition = SIMD3<Float>(centerX, centerY, centerZ)
        
        print("🏥 DICOM Coordinate System initialized:")
        print("   Origin: \(volumeOrigin) mm")
        print("   Spacing: \(volumeSpacing) mm")
        print("   Dimensions: \(volumeDimensions) voxels")
        print("   Center: \(currentWorldPosition) mm")
    }
    
    /// Initialize coordinate system from loaded volume data
    func initializeFromVolumeData(_ volumeData: VolumeData) {
        // Update with real DICOM data
        volumeOrigin = volumeData.origin
        volumeSpacing = volumeData.spacing
        volumeDimensions = volumeData.dimensions
        
        // Calculate center position using real volume data
        let centerX = volumeOrigin.x + (Float(volumeDimensions.x) * volumeSpacing.x) / 2.0
        let centerY = volumeOrigin.y + (Float(volumeDimensions.y) * volumeSpacing.y) / 2.0
        let centerZ = volumeOrigin.z + (Float(volumeDimensions.z) * volumeSpacing.z) / 2.0
        
        currentWorldPosition = SIMD3<Float>(centerX, centerY, centerZ)
        
        print("🔄 Coordinate system updated with real DICOM volume:")
        print("   Real Origin: \(volumeOrigin) mm")
        print("   Real Spacing: \(volumeSpacing) mm")
        print("   Real Dimensions: \(volumeDimensions) voxels")
        print("   New Center: \(currentWorldPosition) mm")
    }
    
    // MARK: - AUTHORITATIVE Coordinate Transformations
    
    /// Convert world position (mm) to slice index for given plane
    func worldToSliceIndex(position: SIMD3<Float>, plane: MPRPlane) -> Int {
        let axis = plane.sliceAxis
        let coordinate = position[axis]
        let sliceIndex = Int((coordinate - volumeOrigin[axis]) / volumeSpacing[axis])
        let maxSlice = volumeDimensions[axis] - 1
        return max(0, min(sliceIndex, maxSlice))
    }
    
    /// Convert slice index to world position (mm) for given plane
    func sliceIndexToWorld(index: Int, plane: MPRPlane) -> Float {
        let axis = plane.sliceAxis
        let clampedIndex = max(0, min(index, volumeDimensions[axis] - 1))
        return volumeOrigin[axis] + Float(clampedIndex) * volumeSpacing[axis]
    }
    
    /// Convert world position (mm) to screen coordinates for given plane and view size
    func worldToScreen(position: SIMD3<Float>, plane: MPRPlane, viewSize: CGSize) -> CGPoint {
        let axes = plane.planeAxes
        let coord1 = position[axes.0]
        let coord2 = position[axes.1]
        
        // Convert to normalized coordinates (0-1) within volume bounds
        let norm1 = (coord1 - volumeOrigin[axes.0]) / (Float(volumeDimensions[axes.0]) * volumeSpacing[axes.0])
        let norm2 = (coord2 - volumeOrigin[axes.1]) / (Float(volumeDimensions[axes.1]) * volumeSpacing[axes.1])
        
        // Convert to screen coordinates
        let screenX = Double(norm1) * viewSize.width
        let screenY = Double(norm2) * viewSize.height
        
        return CGPoint(x: screenX, y: screenY)
    }
    
    /// Convert screen coordinates to world position for given plane
    func screenToWorld(screenPoint: CGPoint, plane: MPRPlane, viewSize: CGSize) -> SIMD3<Float> {
        let axes = plane.planeAxes
        
        // Convert screen to normalized coordinates
        let norm1 = Float(screenPoint.x / viewSize.width)
        let norm2 = Float(screenPoint.y / viewSize.height)
        
        // Convert to world coordinates
        let coord1 = volumeOrigin[axes.0] + norm1 * Float(volumeDimensions[axes.0]) * volumeSpacing[axes.0]
        let coord2 = volumeOrigin[axes.1] + norm2 * Float(volumeDimensions[axes.1]) * volumeSpacing[axes.1]
        
        // Current position for the slice axis
        let sliceCoord = currentWorldPosition[plane.sliceAxis]
        
        // Build 3D position
        var worldPos = currentWorldPosition
        worldPos[axes.0] = coord1
        worldPos[axes.1] = coord2
        worldPos[plane.sliceAxis] = sliceCoord
        
        return worldPos
    }
    
    // MARK: - Position Updates (Thread-Safe)
    
    /// Update world position - broadcasts to all layers
    func updateWorldPosition(_ newPosition: SIMD3<Float>) {
        // Clamp to volume bounds
        let clampedX = max(volumeOrigin.x, min(newPosition.x, volumeOrigin.x + Float(volumeDimensions.x) * volumeSpacing.x))
        let clampedY = max(volumeOrigin.y, min(newPosition.y, volumeOrigin.y + Float(volumeDimensions.y) * volumeSpacing.y))
        let clampedZ = max(volumeOrigin.z, min(newPosition.z, volumeOrigin.z + Float(volumeDimensions.z) * volumeSpacing.z))
        
        currentWorldPosition = SIMD3<Float>(clampedX, clampedY, clampedZ)
        
        // Validate coordinate alignment
        validateCoordinateAlignment()
    }
    
    /// Update position from slice scrolling in specific plane
    func updateFromSliceScroll(plane: MPRPlane, sliceIndex: Int) {
        let newCoordinate = sliceIndexToWorld(index: sliceIndex, plane: plane)
        let axis = plane.sliceAxis
        
        var newPosition = currentWorldPosition
        newPosition[axis] = newCoordinate
        
        updateWorldPosition(newPosition)
    }
    
    // MARK: - Layer Queries (Used by all layers)
    
    /// Get current slice index for given plane
    func getCurrentSliceIndex(for plane: MPRPlane) -> Int {
        return worldToSliceIndex(position: currentWorldPosition, plane: plane)
    }
    
    /// Get maximum slices for given plane
    func getMaxSlices(for plane: MPRPlane) -> Int {
        return volumeDimensions[plane.sliceAxis]
    }
    
    /// Get current slice position in mm for given plane
    func getCurrentSlicePosition(for plane: MPRPlane) -> Float {
        return currentWorldPosition[plane.sliceAxis]
    }
    
    // MARK: - Volume Bounds
    
    /// Check if world position is within volume bounds
    func isWithinVolumeBounds(_ position: SIMD3<Float>) -> Bool {
        let minBounds = volumeOrigin
        let maxBounds = volumeOrigin + SIMD3<Float>(
            Float(volumeDimensions.x) * volumeSpacing.x,
            Float(volumeDimensions.y) * volumeSpacing.y,
            Float(volumeDimensions.z) * volumeSpacing.z
        )
        
        return position.x >= minBounds.x && position.x <= maxBounds.x &&
               position.y >= minBounds.y && position.y <= maxBounds.y &&
               position.z >= minBounds.z && position.z <= maxBounds.z
    }
    
    // MARK: - Validation & Debugging
    
    /// Validate that all coordinate transformations are consistent
    private func validateCoordinateAlignment() {
        // Test round-trip conversions
        for plane in [MPRPlane.axial, MPRPlane.sagittal, MPRPlane.coronal] {
            let sliceIndex = getCurrentSliceIndex(for: plane)
            let backToWorld = sliceIndexToWorld(index: sliceIndex, plane: plane)
            let originalCoord = currentWorldPosition[plane.sliceAxis]
            
            let error = abs(backToWorld - originalCoord)
            if error > volumeSpacing[plane.sliceAxis] * 0.1 { // 10% tolerance
                print("⚠️ Coordinate alignment error in \(plane): \(error)mm")
            }
        }
    }
    
    /// Get debug information for current state
    func getDebugInfo() -> String {
        let axialSlice = getCurrentSliceIndex(for: .axial)
        let sagittalSlice = getCurrentSliceIndex(for: .sagittal)
        let coronalSlice = getCurrentSliceIndex(for: .coronal)
        
        return """
        🏥 DICOM Coordinates: (\(String(format: "%.1f", currentWorldPosition.x)), \(String(format: "%.1f", currentWorldPosition.y)), \(String(format: "%.1f", currentWorldPosition.z))) mm
        📐 Slice Indices: AX=\(axialSlice), SAG=\(sagittalSlice), COR=\(coronalSlice)
        📏 Volume: \(volumeDimensions) @ \(volumeSpacing)mm spacing
        """
    }
}


