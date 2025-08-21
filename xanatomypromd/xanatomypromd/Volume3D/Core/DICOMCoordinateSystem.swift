import Foundation
import SwiftUI
import simd

// MARK: - Universal DICOM Coordinate System (Scan-Agnostic)
// THE SINGLE source of truth for ALL spatial transformations in the app
// Works with ANY scan: 53-slice test, 500+ slice production, any dimensions/spacing

@MainActor
class DICOMCoordinateSystem: ObservableObject {
    
    // MARK: - Dynamic DICOM Volume Properties (Adapts to Any Scan)
    
    /// Volume data source - contains ALL scan-specific parameters
    private var volumeData: VolumeData?
    
    /// Cache max slices per volume data instance to avoid recalculation in render loops
    private var cachedMaxSlices: [MPRPlane: Int] = [:]
    private var cachedVolumeDataID: ObjectIdentifier?  // Track which volume data the cache is for
    
    /// Current 3D world position in DICOM patient coordinates (mm)
    @Published var currentWorldPosition: SIMD3<Float>
    
    /// Current scroll velocity in slices per second
    @Published var scrollVelocity: Float = 0.0
    
    /// Last slice update time for velocity calculation
    private var lastSliceUpdateTime: Date = Date()
    private var lastSliceIndex: [MPRPlane: Int] = [:]
    private weak var velocityTimer: Timer?  // ✅ FIX: Use weak reference
    
    // MARK: - Computed Properties (Always Current)
    
    /// Volume origin in patient coordinates (mm) - dynamic based on loaded scan
    var volumeOrigin: SIMD3<Float> {
        return volumeData?.origin ?? SIMD3<Float>(0, 0, 0)
    }
    
    /// Voxel spacing in mm (x, y, z) - dynamic based on loaded scan
    var volumeSpacing: SIMD3<Float> {
        return volumeData?.spacing ?? SIMD3<Float>(1.0, 1.0, 1.0)
    }
    
    /// Volume dimensions in voxels - dynamic based on loaded scan
    var volumeDimensions: SIMD3<Int> {
        return volumeData?.dimensions ?? SIMD3<Int>(512, 512, 53)
    }
    
    /// Physical volume size in mm - computed from dimensions and spacing
    var physicalVolumeSize: SIMD3<Float> {
        return SIMD3<Float>(
            Float(volumeDimensions.x) * volumeSpacing.x,
            Float(volumeDimensions.y) * volumeSpacing.y,
            Float(volumeDimensions.z) * volumeSpacing.z
        )
    }
    
    /// Volume bounds in world coordinates (min, max)
    var volumeBounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        let minBounds = volumeOrigin
        let maxBounds = volumeOrigin + physicalVolumeSize
        return (min: minBounds, max: maxBounds)
    }
    
    // MARK: - Initialization (Scan-Agnostic)
    
    init() {
        // Initialize at origin - will be updated when volume loads
        self.currentWorldPosition = SIMD3<Float>(0, 0, 0)
        

    }
    
    /// ✅ FIX: Clean up timer on deallocation
    deinit {
        velocityTimer?.invalidate()
        velocityTimer = nil

    }
    
    /// Initialize coordinate system from ANY loaded volume data
    func initializeFromVolumeData(_ volumeData: VolumeData) {
        self.volumeData = volumeData
        
        // Clear cache when new volume loads (switching between male/female patients)
        cachedMaxSlices.removeAll()
        cachedVolumeDataID = ObjectIdentifier(volumeData)
        
        // Calculate center position using real volume data (works for any scan)
        let centerPosition = volumeOrigin + physicalVolumeSize / 2.0
        self.currentWorldPosition = centerPosition
        

    }
    
    // MARK: - AUTHORITATIVE Coordinate Transformations (Works with Any Scan)
    
    /// Convert world position (mm) to voxel coordinates (for any scan)
    func worldToVoxel(_ worldPos: SIMD3<Float>) -> SIMD3<Float> {
        return (worldPos - volumeOrigin) / volumeSpacing
    }
    
    /// Convert voxel coordinates to world position (mm) (for any scan)
    func voxelToWorld(_ voxelPos: SIMD3<Float>) -> SIMD3<Float> {
        return volumeOrigin + (voxelPos * volumeSpacing)
    }
    
    /// Convert world position to normalized coordinates [0,1] (for any scan)
    func worldToNormalized(_ worldPos: SIMD3<Float>) -> SIMD3<Float> {
        let voxelPos = worldToVoxel(worldPos)
        return SIMD3<Float>(
            voxelPos.x / Float(volumeDimensions.x - 1),
            voxelPos.y / Float(volumeDimensions.y - 1),
            voxelPos.z / Float(volumeDimensions.z - 1)
        )
    }
    
    /// Convert normalized coordinates [0,1] to world position (for any scan)
    func normalizedToWorld(_ normalizedPos: SIMD3<Float>) -> SIMD3<Float> {
        let voxelPos = SIMD3<Float>(
            normalizedPos.x * Float(volumeDimensions.x - 1),
            normalizedPos.y * Float(volumeDimensions.y - 1),
            normalizedPos.z * Float(volumeDimensions.z - 1)
        )
        return voxelToWorld(voxelPos)
    }
    
    /// Get slice index for current position in given plane (EDUCATIONAL: 2mm spacing aware)
    func getCurrentSliceIndex(for plane: MPRPlane) -> Int {
        guard let volumeData = volumeData else { 

            return 0 
        }
        
        let worldPos = currentWorldPosition
        let sliceAxis = plane.sliceAxis
        
        // For axial (original slices), use voxel-based indexing
        if plane == .axial {
            let voxelPos = worldToVoxel(worldPos)
            let maxSlices = volumeData.dimensions[sliceAxis]
            let sliceIndex = Int(round(voxelPos[sliceAxis]))
            return max(0, min(sliceIndex, maxSlices - 1))
        }
        
        // For sagittal and coronal, use 2mm spacing indexing
        let targetSpacing: Float = 2.0 // mm
        let worldCoord = worldPos[sliceAxis]
        let origin = volumeOrigin[sliceAxis]
        let relativePosition = worldCoord - origin
        let educationalSliceIndex = Int(relativePosition / targetSpacing)
        let maxEducationalSlices = getMaxSlices(for: plane)
        
        return max(0, min(educationalSliceIndex, maxEducationalSlices - 1))
    }
    
    /// Get maximum slices for given plane (EDUCATIONAL: 2mm spacing for MPR)
    func getMaxSlices(for plane: MPRPlane) -> Int {
        guard let volumeData = volumeData else { 

            return 1 
        }
        
        let currentVolumeID = ObjectIdentifier(volumeData)
        
        // Clear cache if we're looking at a different volume (male vs female patient)
        if cachedVolumeDataID != currentVolumeID {
            cachedMaxSlices.removeAll()
            cachedVolumeDataID = currentVolumeID
        }
        
        // Return cached value if available for this volume
        if let cached = cachedMaxSlices[plane] {
            return cached
        }
        
        // Calculate once per plane per volume and cache
        let maxSlices = calculateMaxSlicesForPlane(plane, volumeData: volumeData)
        cachedMaxSlices[plane] = maxSlices
        
        return maxSlices
    }
    
    /// Calculate max slices for plane (called once per plane per volume)
    private func calculateMaxSlicesForPlane(_ plane: MPRPlane, volumeData: VolumeData) -> Int {
        // For axial (original slices), use actual DICOM slice count
        if plane == .axial {
            return volumeData.dimensions[plane.sliceAxis]
        }
        
        // For sagittal and coronal, use 2mm educational spacing
        let targetSpacing: Float = 2.0 // mm - optimal for educational viewing
        let physicalSize = Float(volumeData.dimensions[plane.sliceAxis]) * volumeData.spacing[plane.sliceAxis]
        let educationalSliceCount = Int(physicalSize / targetSpacing)
        
        let originalCount = volumeData.dimensions[plane.sliceAxis]
        
        // Log once per plane per volume (not on every render frame!)
        print("📚 Educational slice optimization - \(plane):")
        print("   📐 Physical size: \(String(format: "%.1f", physicalSize))mm")
        print("   📊 Original slices: \(originalCount) (\(String(format: "%.2f", volumeData.spacing[plane.sliceAxis]))mm spacing)")
        print("   🎓 Educational slices: \(educationalSliceCount) (2.0mm spacing)")
        print("   ⚡ Performance gain: \(String(format: "%.1f", Float(originalCount) / Float(educationalSliceCount)))x faster")
        
        return max(1, educationalSliceCount)
    }
    
    /// Convert world position to screen coordinates for given plane and view size
    func worldToScreen(
        position: SIMD3<Float>,
        plane: MPRPlane,
        viewSize: CGSize,
        imageBounds: CGRect? = nil
    ) -> CGPoint {
        
        // Get 2D coordinates for this plane
        let planeCoords = extractPlaneCoordinates(worldPos: position, plane: plane)
        let normalizedCoords = normalizePlaneCoordinates(planeCoords: planeCoords, plane: plane)
        
        // Use provided image bounds or calculate them
        let bounds = imageBounds ?? calculateImageBounds(plane: plane, viewSize: viewSize)
        
        // Convert to screen coordinates
        let screenX = bounds.minX + (CGFloat(normalizedCoords.x) * bounds.width)
        let screenY = bounds.minY + (CGFloat(normalizedCoords.y) * bounds.height)
        
        return CGPoint(x: screenX, y: screenY)
    }
    
    /// Convert screen coordinates to world position for given plane
    func screenToWorld(
        screenPoint: CGPoint,
        plane: MPRPlane,
        viewSize: CGSize,
        imageBounds: CGRect? = nil
    ) -> SIMD3<Float> {
        
        // Use provided image bounds or calculate them
        let bounds = imageBounds ?? calculateImageBounds(plane: plane, viewSize: viewSize)
        
        // Check if point is within bounds
        guard bounds.contains(screenPoint) else {
            print("🎯 Screen point outside image bounds: \(screenPoint) not in \(bounds)")
            return currentWorldPosition
        }
        
        // Convert screen to normalized coordinates [0,1]
        let normalizedX = Float((screenPoint.x - bounds.minX) / bounds.width)
        let normalizedY = Float((screenPoint.y - bounds.minY) / bounds.height)
        let normalizedCoords = SIMD2<Float>(normalizedX, normalizedY)
        
        // Convert to world coordinates for this plane
        return convertPlaneToWorldCoordinates(
            normalizedCoords: normalizedCoords,
            plane: plane,
            currentWorldPos: currentWorldPosition
        )
    }
    
    // MARK: - Plane-Specific Coordinate Helpers (Works with Any Scan)
    
    /// Extract 2D coordinates from 3D world position for given plane
    private func extractPlaneCoordinates(worldPos: SIMD3<Float>, plane: MPRPlane) -> SIMD2<Float> {
        switch plane {
        case .axial:    // XY plane
            return SIMD2<Float>(worldPos.x, worldPos.y)
        case .sagittal: // YZ plane
            return SIMD2<Float>(worldPos.y, worldPos.z)
        case .coronal:  // XZ plane
            return SIMD2<Float>(worldPos.x, worldPos.z)
        }
    }
    
    /// Normalize plane coordinates to [0,1] range
    private func normalizePlaneCoordinates(planeCoords: SIMD2<Float>, plane: MPRPlane) -> SIMD2<Float> {
        let voxelCoords = (planeCoords - getPlaneOrigin(plane: plane)) / getPlaneSpacing(plane: plane)
        let planeDims = getPlaneDimensions(plane: plane)
        
        return SIMD2<Float>(
            voxelCoords.x / Float(planeDims.x - 1),
            voxelCoords.y / Float(planeDims.y - 1)
        )
    }
    
    /// Convert normalized plane coordinates back to 3D world position
    private func convertPlaneToWorldCoordinates(
        normalizedCoords: SIMD2<Float>,
        plane: MPRPlane,
        currentWorldPos: SIMD3<Float>
    ) -> SIMD3<Float> {
        
        // Convert normalized to voxel coordinates
        let planeDims = getPlaneDimensions(plane: plane)
        let voxelCoords = SIMD2<Float>(
            normalizedCoords.x * Float(planeDims.x - 1),
            normalizedCoords.y * Float(planeDims.y - 1)
        )
        
        // Convert to world coordinates
        let planeOrigin = getPlaneOrigin(plane: plane)
        let planeSpacing = getPlaneSpacing(plane: plane)
        let worldCoords = planeOrigin + (voxelCoords * planeSpacing)
        
        // Build 3D world position
        var newWorldPos = currentWorldPos
        
        switch plane {
        case .axial:    // XY plane - update X,Y, keep Z
            newWorldPos.x = worldCoords.x
            newWorldPos.y = worldCoords.y
        case .sagittal: // YZ plane - update Y,Z, keep X
            newWorldPos.y = worldCoords.x
            newWorldPos.z = worldCoords.y
        case .coronal:  // XZ plane - update X,Z, keep Y
            newWorldPos.x = worldCoords.x
            newWorldPos.z = worldCoords.y
        }
        
        return newWorldPos
    }
    
    /// Get 2D origin for given plane
    private func getPlaneOrigin(plane: MPRPlane) -> SIMD2<Float> {
        switch plane {
        case .axial:    return SIMD2<Float>(volumeOrigin.x, volumeOrigin.y)
        case .sagittal: return SIMD2<Float>(volumeOrigin.y, volumeOrigin.z)
        case .coronal:  return SIMD2<Float>(volumeOrigin.x, volumeOrigin.z)
        }
    }
    
    /// Get 2D spacing for given plane
    private func getPlaneSpacing(plane: MPRPlane) -> SIMD2<Float> {
        switch plane {
        case .axial:    return SIMD2<Float>(volumeSpacing.x, volumeSpacing.y)
        case .sagittal: return SIMD2<Float>(volumeSpacing.y, volumeSpacing.z)
        case .coronal:  return SIMD2<Float>(volumeSpacing.x, volumeSpacing.z)
        }
    }
    
    /// Get 2D dimensions for given plane
    private func getPlaneDimensions(plane: MPRPlane) -> SIMD2<Int> {
        switch plane {
        case .axial:    return SIMD2<Int>(volumeDimensions.x, volumeDimensions.y)
        case .sagittal: return SIMD2<Int>(volumeDimensions.y, volumeDimensions.z)
        case .coronal:  return SIMD2<Int>(volumeDimensions.x, volumeDimensions.z)
        }
    }
    
    // MARK: - Image Bounds Calculation (Medical Accurate)
    
    /// Calculate medical image bounds within view (same logic as CTDisplayLayer)
    func calculateImageBounds(plane: MPRPlane, viewSize: CGSize) -> CGRect {
        guard let volumeData = volumeData else {
            return CGRect(origin: .zero, size: viewSize)
        }
        
        // Get plane dimensions and calculate physical size
        let planeDims = getPlaneDimensions(plane: plane)
        let planeSpacing = getPlaneSpacing(plane: plane)
        
        let physicalWidth = Float(planeDims.x) * planeSpacing.x
        let physicalHeight = Float(planeDims.y) * planeSpacing.y
        
        // Calculate aspect ratios
        let physicalAspect = physicalWidth / physicalHeight
        let viewAspect = Float(viewSize.width / viewSize.height)
        
        // Calculate letterbox bounds
        let quadSize: (width: Float, height: Float)
        
        if physicalAspect > viewAspect {
            // Image is physically wider - letterbox top/bottom
            quadSize = (1.0, viewAspect / physicalAspect)
        } else {
            // Image is physically taller - letterbox left/right
            quadSize = (physicalAspect / viewAspect, 1.0)
        }
        
        // Convert to screen pixel bounds
        let quadWidthPixels = CGFloat(quadSize.width) * viewSize.width
        let quadHeightPixels = CGFloat(quadSize.height) * viewSize.height
        
        let quadX = (viewSize.width - quadWidthPixels) / 2.0
        let quadY = (viewSize.height - quadHeightPixels) / 2.0
        
        return CGRect(
            x: quadX,
            y: quadY,
            width: quadWidthPixels,
            height: quadHeightPixels
        )
    }
    
    // MARK: - Position Updates (Thread-Safe)
    
    /// Update world position - broadcasts to all layers
    func updateWorldPosition(_ newPosition: SIMD3<Float>) {
        // ✅ FIX: Add threshold to prevent micro-updates
        let delta = length(newPosition - currentWorldPosition)
        if delta < 0.01 { 
            return  // Ignore tiny movements less than 0.01mm
        }
        
        // Clamp to volume bounds
        let bounds = volumeBounds
        let clampedPosition = SIMD3<Float>(
            max(bounds.min.x, min(newPosition.x, bounds.max.x)),
            max(bounds.min.y, min(newPosition.y, bounds.max.y)),
            max(bounds.min.z, min(newPosition.z, bounds.max.z))
        )
        
        // ✅ FIX: Only update if clamped position is different enough
        let clampedDelta = length(clampedPosition - currentWorldPosition)
        if clampedDelta < 0.01 {
            return
        }
        
        currentWorldPosition = clampedPosition
        

    }
    
    /// Update position from slice scrolling in specific plane (EDUCATIONAL: 2mm spacing aware)
    func updateFromSliceScroll(plane: MPRPlane, sliceIndex: Int) {
        let maxSlice = getMaxSlices(for: plane) - 1
        let clampedIndex = max(0, min(sliceIndex, maxSlice))
        
        // Calculate velocity (reduced logging for performance)
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastSliceUpdateTime)
        
        if timeDelta > 0.001 {  // Avoid division by near-zero
            if let lastIndex = lastSliceIndex[plane] {
                let sliceDelta = abs(clampedIndex - lastIndex)
                let velocity = Float(sliceDelta) / Float(timeDelta)
                
                // ✅ FIX: Only update velocity if there's a significant change
                if abs(velocity - scrollVelocity) > 0.5 {
                    scrollVelocity = velocity
                }
            }
        }
        
        // Update tracking
        lastSliceUpdateTime = now
        lastSliceIndex[plane] = clampedIndex
        
        // ✅ FIX: Proper timer management - always invalidate before creating new one
        velocityTimer?.invalidate()
        velocityTimer = nil  // Clear reference immediately
        
        // Create new timer with weak self capture
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.scrollVelocity = 0.0
                self.velocityTimer?.invalidate()
                self.velocityTimer = nil
            }
        }
        velocityTimer = timer
        
        // Convert slice index to world coordinate based on plane type
        let sliceAxis = plane.sliceAxis
        let worldCoord: Float
        
        if plane == .axial {
            // For axial, use original voxel-based positioning
            let voxelCoord = Float(clampedIndex)
            worldCoord = volumeOrigin[sliceAxis] + (voxelCoord * volumeSpacing[sliceAxis])
        } else {
            // For sagittal and coronal, use 2mm educational spacing
            let targetSpacing: Float = 2.0 // mm
            worldCoord = volumeOrigin[sliceAxis] + (Float(clampedIndex) * targetSpacing)
        }
        
        // ✅ FIX: Only update if position actually changed significantly (> 0.5mm)
        var newPosition = currentWorldPosition
        let previousCoord = newPosition[sliceAxis]
        newPosition[sliceAxis] = worldCoord
        
        if abs(worldCoord - previousCoord) > 0.5 {
            updateWorldPosition(newPosition)
        }
    }
    

    
    // MARK: - Validation & Debugging
    
    /// Check if world position is within volume bounds
    func isWithinVolumeBounds(_ position: SIMD3<Float>) -> Bool {
        let bounds = volumeBounds
        return position.x >= bounds.min.x && position.x <= bounds.max.x &&
               position.y >= bounds.min.y && position.y <= bounds.max.y &&
               position.z >= bounds.min.z && position.z <= bounds.max.z
    }
    
    /// Get debug information for current state
    func getDebugInfo() -> String {
        guard volumeData != nil else {
            return "🏥 No volume data loaded"
        }
        
        let axialSlice = getCurrentSliceIndex(for: .axial)
        let sagittalSlice = getCurrentSliceIndex(for: .sagittal)
        let coronalSlice = getCurrentSliceIndex(for: .coronal)
        
        return """
        🏥 DICOM Coordinates: (\(String(format: "%.1f", currentWorldPosition.x)), \(String(format: "%.1f", currentWorldPosition.y)), \(String(format: "%.1f", currentWorldPosition.z))) mm
        📐 Slice Indices: AX=\(axialSlice)/\(getMaxSlices(for: .axial)-1), SAG=\(sagittalSlice)/\(getMaxSlices(for: .sagittal)-1), COR=\(coronalSlice)/\(getMaxSlices(for: .coronal)-1)
        📏 Volume: \(volumeDimensions) @ \(volumeSpacing)mm spacing
        📊 Physical size: \(physicalVolumeSize) mm
        """
    }
}

// MPRPlane extensions already exist in the project
