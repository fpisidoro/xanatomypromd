import Foundation
import simd

// MARK: - ROI Data Structures for RTStruct Processing
// Medical imaging ROI (Region of Interest) definitions for anatomical structures

/// Represents a single anatomical ROI from RTStruct
public struct ROIStructure {
    public let roiNumber: Int
    public let roiName: String
    public let roiDescription: String?
    public let roiGenerationAlgorithm: String?
    
    // Display properties
    public let displayColor: SIMD3<Float>  // RGB color for overlay
    public let isVisible: Bool
    public let opacity: Float
    
    // 3D contour data
    public let contours: [ROIContour]
    
    public init(
        roiNumber: Int,
        roiName: String,
        roiDescription: String? = nil,
        roiGenerationAlgorithm: String? = nil,
        displayColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.0, 0.0), // Default red
        isVisible: Bool = true,
        opacity: Float = 0.5,
        contours: [ROIContour] = []
    ) {
        self.roiNumber = roiNumber
        self.roiName = roiName
        self.roiDescription = roiDescription
        self.roiGenerationAlgorithm = roiGenerationAlgorithm
        self.displayColor = displayColor
        self.isVisible = isVisible
        self.opacity = opacity
        self.contours = contours
    }
}

/// Represents a single contour slice within an ROI
public struct ROIContour {
    public let contourNumber: Int
    public let geometricType: ContourGeometricType
    public let numberOfPoints: Int
    public let contourData: [SIMD3<Float>]  // 3D points in patient coordinates
    public let slicePosition: Float         // Z coordinate for slice association
    
    // Attachment to referenced image
    public let referencedSOPInstanceUID: String?
    
    public init(
        contourNumber: Int,
        geometricType: ContourGeometricType,
        numberOfPoints: Int,
        contourData: [SIMD3<Float>],
        slicePosition: Float,
        referencedSOPInstanceUID: String? = nil
    ) {
        self.contourNumber = contourNumber
        self.geometricType = geometricType
        self.numberOfPoints = numberOfPoints
        self.contourData = contourData
        self.slicePosition = slicePosition
        self.referencedSOPInstanceUID = referencedSOPInstanceUID
    }
}

/// DICOM geometric types for contours
public enum ContourGeometricType: String, CaseIterable {
    case point = "POINT"
    case openPlanar = "OPEN_PLANAR"
    case closedPlanar = "CLOSED_PLANAR"
    case openNonplanar = "OPEN_NONPLANAR"
    case closedNonplanar = "CLOSED_NONPLANAR"
    
    public var description: String {
        switch self {
        case .point:
            return "Point"
        case .openPlanar:
            return "Open Planar"
        case .closedPlanar:
            return "Closed Planar"
        case .openNonplanar:
            return "Open Non-planar"
        case .closedNonplanar:
            return "Closed Non-planar"
        }
    }
    
    /// Whether this contour type should be filled (closed shapes)
    public var shouldFill: Bool {
        switch self {
        case .closedPlanar, .closedNonplanar:
            return true
        case .point, .openPlanar, .openNonplanar:
            return false
        }
    }
}

/// Complete RTStruct dataset containing all ROI structures
public struct RTStructData {
    public let patientName: String?
    public let studyInstanceUID: String?
    public let seriesInstanceUID: String?
    public let structureSetLabel: String?
    public let structureSetName: String?
    public let structureSetDescription: String?
    public let structureSetDate: String?
    public let structureSetTime: String?
    
    // All ROI structures in this RTStruct
    public let roiStructures: [ROIStructure]
    
    // Referenced image series (the CT series this RTStruct applies to)
    public let referencedFrameOfReferenceUID: String?
    public let referencedStudyInstanceUID: String?
    public let referencedSeriesInstanceUID: String?
    
    public init(
        patientName: String? = nil,
        studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil,
        structureSetLabel: String? = nil,
        structureSetName: String? = nil,
        structureSetDescription: String? = nil,
        structureSetDate: String? = nil,
        structureSetTime: String? = nil,
        roiStructures: [ROIStructure] = [],
        referencedFrameOfReferenceUID: String? = nil,
        referencedStudyInstanceUID: String? = nil,
        referencedSeriesInstanceUID: String? = nil
    ) {
        self.patientName = patientName
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.structureSetLabel = structureSetLabel
        self.structureSetName = structureSetName
        self.structureSetDescription = structureSetDescription
        self.structureSetDate = structureSetDate
        self.structureSetTime = structureSetTime
        self.roiStructures = roiStructures
        self.referencedFrameOfReferenceUID = referencedFrameOfReferenceUID
        self.referencedStudyInstanceUID = referencedStudyInstanceUID
        self.referencedSeriesInstanceUID = referencedSeriesInstanceUID
    }
}

// MARK: - ROI Processing Utilities

extension ROIStructure {
    
    /// Get all contours for a specific slice position (Z coordinate)
    public func getContoursForSlice(_ sliceZ: Float, tolerance: Float = 1.0) -> [ROIContour] {
        return contours.filter { contour in
            abs(contour.slicePosition - sliceZ) <= tolerance
        }
    }
    
    /// Get contours within a Z range (for thick slice visualization)
    public func getContoursInRange(_ minZ: Float, _ maxZ: Float) -> [ROIContour] {
        return contours.filter { contour in
            contour.slicePosition >= minZ && contour.slicePosition <= maxZ
        }
    }
    
    /// Total number of contour points across all slices
    public var totalPoints: Int {
        return contours.reduce(0) { $0 + $1.numberOfPoints }
    }
    
    /// Z-range covered by this ROI
    public var zRange: (min: Float, max: Float)? {
        guard !contours.isEmpty else { return nil }
        
        let zPositions = contours.map { $0.slicePosition }
        return (min: zPositions.min()!, max: zPositions.max()!)
    }
}

extension RTStructData {
    
    /// Find ROI by number
    public func getROI(number: Int) -> ROIStructure? {
        return roiStructures.first { $0.roiNumber == number }
    }
    
    /// Find ROI by name (case-insensitive)
    public func getROI(name: String) -> ROIStructure? {
        return roiStructures.first { $0.roiName.lowercased() == name.lowercased() }
    }
    
    /// Get all ROI names
    public var roiNames: [String] {
        return roiStructures.map { $0.roiName }
    }
    
    /// Get statistics about the RTStruct dataset
    public func getStatistics() -> RTStructStatistics {
        let totalContours = roiStructures.reduce(0) { $0 + $1.contours.count }
        let totalPoints = roiStructures.reduce(0) { $0 + $1.totalPoints }
        
        var zRanges: [(min: Float, max: Float)] = []
        for roi in roiStructures {
            if let range = roi.zRange {
                zRanges.append(range)
            }
        }
        
        let overallZRange: (min: Float, max: Float)?
        if !zRanges.isEmpty {
            let allMins = zRanges.map { $0.min }
            let allMaxs = zRanges.map { $0.max }
            overallZRange = (min: allMins.min()!, max: allMaxs.max()!)
        } else {
            overallZRange = nil
        }
        
        return RTStructStatistics(
            roiCount: roiStructures.count,
            totalContours: totalContours,
            totalPoints: totalPoints,
            zRange: overallZRange
        )
    }
}

/// Statistics about an RTStruct dataset
public struct RTStructStatistics {
    public let roiCount: Int
    public let totalContours: Int
    public let totalPoints: Int
    public let zRange: (min: Float, max: Float)?
    
    public var description: String {
        var desc = "RTStruct: \(roiCount) ROIs, \(totalContours) contours, \(totalPoints) points"
        if let range = zRange {
            desc += String(format: ", Z: %.1f to %.1f mm", range.min, range.max)
        }
        return desc
    }
}

// MARK: - Error Handling

public enum RTStructError: Error, LocalizedError {
    case invalidRTStructFormat
    case missingRequiredSequence(String)
    case invalidContourData
    case unsupportedGeometricType
    case coordinateConversionFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidRTStructFormat:
            return "Invalid RTStruct DICOM format"
        case .missingRequiredSequence(let sequence):
            return "Missing required DICOM sequence: \(sequence)"
        case .invalidContourData:
            return "Invalid or corrupted contour data"
        case .unsupportedGeometricType:
            return "Unsupported contour geometric type"
        case .coordinateConversionFailed:
            return "Failed to convert contour coordinates"
        }
    }
}

// MARK: - Metal Rendering Preparation

extension ROIContour {
    
    /// Convert 3D contour points to 2D screen coordinates for a specific plane
    public func projectToPlane(_ plane: MPRPlane, volumeOrigin: SIMD3<Float>, volumeSpacing: SIMD3<Float>) -> [SIMD2<Float>] {
        var projectedPoints: [SIMD2<Float>] = []
        
        for point in contourData {
            // Convert from patient coordinates to voxel coordinates
            let voxelPoint = (point - volumeOrigin) / volumeSpacing
            
            // Project to 2D based on plane
            let screenPoint: SIMD2<Float>
            switch plane {
            case .axial:
                screenPoint = SIMD2<Float>(voxelPoint.x, voxelPoint.y)
            case .sagittal:
                screenPoint = SIMD2<Float>(voxelPoint.y, voxelPoint.z)
            case .coronal:
                screenPoint = SIMD2<Float>(voxelPoint.x, voxelPoint.z)
            }
            
            projectedPoints.append(screenPoint)
        }
        
        return projectedPoints
    }
    
    /// Check if this contour intersects with a specific slice
    public func intersectsSlice(_ slicePosition: Float, plane: MPRPlane, tolerance: Float = 1.0) -> Bool {
        switch plane {
        case .axial:
            return abs(self.slicePosition - slicePosition) <= tolerance
        case .sagittal, .coronal:
            // For sagittal/coronal planes, check if any contour points cross the slice
            return contourData.contains { point in
                let relevantCoordinate = plane == .sagittal ? point.x : point.y
                return abs(relevantCoordinate - slicePosition) <= tolerance
            }
        }
    }
}
