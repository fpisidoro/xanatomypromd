import Foundation
import simd

// MARK: - Multi-Planar Reconstruction (MPR) Plane Definitions
// Essential enums and structures for 3D medical imaging

/// Medical imaging plane orientations for MPR views
public enum MPRPlane: String, CaseIterable {
    case axial = "axial"
    case sagittal = "sagittal"
    case coronal = "coronal"
    
    /// Human-readable description
    public var displayName: String {
        switch self {
        case .axial:
            return "Axial (Transverse)"
        case .sagittal:
            return "Sagittal (Lateral)"
        case .coronal:
            return "Coronal (Frontal)"
        }
    }
    
    /// Medical abbreviation
    var abbreviation: String {
        switch self {
        case .axial: return "AX"
        case .sagittal: return "SAG"
        case .coronal: return "COR"
        }
    }
    
    /// Vector indicating the normal direction for the plane
    var normalVector: SIMD3<Float> {
        switch self {
        case .axial:
            return SIMD3<Float>(0, 0, 1)  // Z-axis (superior-inferior)
        case .sagittal:
            return SIMD3<Float>(1, 0, 0)  // X-axis (left-right)
        case .coronal:
            return SIMD3<Float>(0, 1, 0)  // Y-axis (anterior-posterior)
        }
    }
    
    /// Primary axis for slice navigation
    var sliceAxis: Int {
        switch self {
        case .axial: return 2    // Z-axis
        case .sagittal: return 0 // X-axis  
        case .coronal: return 1  // Y-axis
        }
    }
    
    /// Get the two axes that define the 2D plane
    var planeAxes: (Int, Int) {
        switch self {
        case .axial:
            return (0, 1)  // X, Y
        case .sagittal:
            return (1, 2)  // Y, Z
        case .coronal:
            return (0, 2)  // X, Z
        }
    }
    
    /// Create MPRPlane from string (for backwards compatibility)
    public static func from(string: String) -> MPRPlane {
        switch string.lowercased() {
        case "axial":
            return .axial
        case "sagittal":
            return .sagittal
        case "coronal":
            return .coronal
        default:
            return .axial
        }
    }
}

/// Window/Level presets for different tissue types
public struct CTWindowPresets {
    public struct WindowLevel {
        public let center: Float
        public let width: Float
        public let name: String
        
        public init(center: Float, width: Float, name: String) {
            self.center = center
            self.width = width
            self.name = name
        }
    }
    
    public static let softTissue = WindowLevel(center: 50, width: 350, name: "Soft Tissue")
    public static let bone = WindowLevel(center: 500, width: 2000, name: "Bone")
    public static let lung = WindowLevel(center: -600, width: 1600, name: "Lung")
    public static let brain = WindowLevel(center: 40, width: 80, name: "Brain")
    public static let liver = WindowLevel(center: 60, width: 160, name: "Liver")
    
    public static let allPresets: [WindowLevel] = [
        softTissue, bone, lung, brain, liver
    ]
}

/// Configuration for MPR slice generation
public struct MPRSliceConfig {
    public let plane: MPRPlane
    public let sliceIndex: Int
    public let windowLevel: CTWindowPresets.WindowLevel
    public let interpolationMode: InterpolationMode
    
    public init(
        plane: MPRPlane,
        sliceIndex: Int,
        windowLevel: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue,
        interpolationMode: InterpolationMode = .linear
    ) {
        self.plane = plane
        self.sliceIndex = sliceIndex
        self.windowLevel = windowLevel
        self.interpolationMode = interpolationMode
    }
}

/// Interpolation modes for MPR reconstruction
public enum InterpolationMode: String, CaseIterable {
    case nearest = "nearest"
    case linear = "linear"
    case cubic = "cubic"
    
    public var displayName: String {
        switch self {
        case .nearest: return "Nearest Neighbor"
        case .linear: return "Linear"
        case .cubic: return "Cubic"
        }
    }
}

/// MPR view transformation matrix helpers
public struct MPRTransforms {
    
    /// Get transformation matrix for converting 3D volume coordinates to 2D plane coordinates
    public static func getPlaneTransform(for plane: MPRPlane) -> simd_float3x3 {
        switch plane {
        case .axial:
            // X, Y unchanged, Z becomes depth
            return simd_float3x3(
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(0, 1, 0),
                SIMD3<Float>(0, 0, 1)
            )
        case .sagittal:
            // Y, Z become X, Y; X becomes depth
            return simd_float3x3(
                SIMD3<Float>(0, 1, 0),
                SIMD3<Float>(0, 0, 1),
                SIMD3<Float>(1, 0, 0)
            )
        case .coronal:
            // X, Z become X, Y; Y becomes depth
            return simd_float3x3(
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(0, 0, 1),
                SIMD3<Float>(0, 1, 0)
            )
        }
    }
    
    /// Convert 3D volume coordinates to 2D plane coordinates
    public static func volumeToPlane(
        _ volumeCoord: SIMD3<Float>,
        plane: MPRPlane
    ) -> SIMD2<Float> {
        let axes = plane.planeAxes
        return SIMD2<Float>(volumeCoord[axes.0], volumeCoord[axes.1])
    }
    
    /// Convert 2D plane coordinates back to 3D volume coordinates
    public static func planeToVolume(
        _ planeCoord: SIMD2<Float>,
        plane: MPRPlane,
        slicePosition: Float
    ) -> SIMD3<Float> {
        let axes = plane.planeAxes
        let sliceAxis = plane.sliceAxis
        
        var volumeCoord = SIMD3<Float>(0, 0, 0)
        volumeCoord[axes.0] = planeCoord.x
        volumeCoord[axes.1] = planeCoord.y
        volumeCoord[sliceAxis] = slicePosition
        
        return volumeCoord
    }
}

// MARK: - MPR Slice Information

/// Information about a specific MPR slice
public struct MPRSliceInfo {
    public let plane: MPRPlane
    public let sliceIndex: Int
    public let slicePosition: Float  // Position in mm
    public let thickness: Float      // Slice thickness in mm
    public let dimensions: SIMD2<Int> // Width, height in pixels
    public let spacing: SIMD2<Float>  // Pixel spacing in mm
    public let origin: SIMD2<Float>   // Origin offset in mm
    
    public init(
        plane: MPRPlane,
        sliceIndex: Int,
        slicePosition: Float,
        thickness: Float,
        dimensions: SIMD2<Int>,
        spacing: SIMD2<Float>,
        origin: SIMD2<Float> = SIMD2<Float>(0, 0)
    ) {
        self.plane = plane
        self.sliceIndex = sliceIndex
        self.slicePosition = slicePosition
        self.thickness = thickness
        self.dimensions = dimensions
        self.spacing = spacing
        self.origin = origin
    }
    
    /// Calculate the number of slices available for this plane given volume dimensions
    public static func getSliceCount(for plane: MPRPlane, volumeDimensions: SIMD3<Int>) -> Int {
        return volumeDimensions[plane.sliceAxis]
    }
    
    /// Get the slice position in mm for a given slice index
    public static func getSlicePosition(
        for sliceIndex: Int,
        plane: MPRPlane,
        volumeOrigin: SIMD3<Float>,
        volumeSpacing: SIMD3<Float>
    ) -> Float {
        let axis = plane.sliceAxis
        return volumeOrigin[axis] + Float(sliceIndex) * volumeSpacing[axis]
    }
}

// MARK: - Extensions for Volume Integration

extension MPRPlane {
    
    /// Get the dimensions of a 2D slice for this plane from 3D volume dimensions
    public func getSliceDimensions(from volumeDimensions: SIMD3<Int>) -> SIMD2<Int> {
        let axes = self.planeAxes
        return SIMD2<Int>(volumeDimensions[axes.0], volumeDimensions[axes.1])
    }
    
    /// Get the spacing for a 2D slice for this plane from 3D volume spacing
    public func getSliceSpacing(from volumeSpacing: SIMD3<Float>) -> SIMD2<Float> {
        let axes = self.planeAxes
        return SIMD2<Float>(volumeSpacing[axes.0], volumeSpacing[axes.1])
    }
    
    /// Calculate aspect ratio for proper display
    public func getAspectRatio(volumeSpacing: SIMD3<Float>, volumeDimensions: SIMD3<Int>) -> Float {
        let sliceSpacing = getSliceSpacing(from: volumeSpacing)
        let sliceDimensions = getSliceDimensions(from: volumeDimensions)
        
        let physicalWidth = Float(sliceDimensions.x) * sliceSpacing.x
        let physicalHeight = Float(sliceDimensions.y) * sliceSpacing.y
        
        return physicalWidth / physicalHeight
    }
}
