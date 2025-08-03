import Foundation
import simd

// MARK: - Type alias to resolve DICOMDataset naming conflict
public typealias ParsedDICOMDataset = DICOMDataset

// MARK: - 3D Volume Data Structure
// Foundation for Multi-Planar Reconstruction (MPR)
// Handles spatial reconstruction from DICOM slice series

public class VolumeData {
    
    // MARK: - Volume Properties
    
    public let dimensions: SIMD3<Int>  // width, height, depth (slices)
    public let voxelData: [Int16]      // Raw voxel values in 3D array
    public let spacing: SIMD3<Float>   // Voxel spacing in mm (x, y, z)
    public let origin: SIMD3<Float>    // Volume origin in patient coordinates
    public let orientation: simd_float3x3  // Volume orientation matrix
    
    // MARK: - Slice Metadata
    
    public struct SliceInfo {
        let position: SIMD3<Float>     // Image position patient
        let orientation: simd_float3x3 // Image orientation patient (as 3x3 matrix)
        let pixelSpacing: SIMD2<Float> // Pixel spacing (row, column)
        let sliceThickness: Float
        let instanceNumber: Int
        let sliceLocation: Float
        let rescaleSlope: Float
        let rescaleIntercept: Float
    }
    
    private let sliceInfos: [SliceInfo]
    
    // MARK: - Initialization
    
    public init(from datasets: [(ParsedDICOMDataset, Int)]) throws {
        guard !datasets.isEmpty else {
            throw VolumeError.emptyDataset
        }
        
        // Sort datasets by anatomical position (superior to inferior)
        let sortedDatasets = datasets.sorted { dataset1, dataset2 in
            let pos1 = Self.extractImagePosition(from: dataset1.0) ?? SIMD3<Float>(0, 0, Float(dataset1.1))
            let pos2 = Self.extractImagePosition(from: dataset2.0) ?? SIMD3<Float>(0, 0, Float(dataset2.1))
            return pos1.z > pos2.z  // Higher Z = superior (top of head)
        }
        
        // Building volume from datasets
        
        // Extract slice information
        var sliceInfos: [SliceInfo] = []
        var allVoxelData: [Int16] = []
        
        // Get dimensions from first slice
        guard let firstDataset = sortedDatasets.first?.0,
              let rows = firstDataset.rows,
              let columns = firstDataset.columns else {
            throw VolumeError.invalidDimensions
        }
        
        let width = Int(columns)
        let height = Int(rows)
        let depth = sortedDatasets.count
        
        self.dimensions = SIMD3<Int>(width, height, depth)
        
        // Process each slice
        for (index, (dataset, _)) in sortedDatasets.enumerated() {
            // Extract slice metadata
            let sliceInfo = try Self.extractSliceInfo(from: dataset, index: index)
            sliceInfos.append(sliceInfo)
            
            // Extract and convert pixel data
            guard let pixelData = DICOMParser.extractPixelData(from: dataset) else {
                throw VolumeError.missingPixelData(slice: index)
            }
            
            // Convert to signed 16-bit and apply rescale parameters
            let signedPixels = pixelData.toInt16Array()
            let rescaledPixels = signedPixels.map { pixel in
                Int16(Float(pixel) * sliceInfo.rescaleSlope + sliceInfo.rescaleIntercept)
            }
            
            allVoxelData.append(contentsOf: rescaledPixels)
            
            // Slice processed
        }
        
        self.sliceInfos = sliceInfos
        self.voxelData = allVoxelData
        
        // Calculate volume spacing and orientation
        self.spacing = Self.calculateVolumeSpacing(from: sliceInfos)
        self.origin = sliceInfos.first?.position ?? SIMD3<Float>(0, 0, 0)
        self.orientation = sliceInfos.first?.orientation ?? matrix_identity_float3x3
        
        print("✅ Volume created: \(width)×\(height)×\(depth)")
        print("   📏 Spacing: \(spacing) mm")
        print("   📍 Origin: \(origin)")
        print("   💾 Memory: \(allVoxelData.count * 2) bytes (\(String(format: "%.1f", Double(allVoxelData.count * 2) / 1024.0 / 1024.0)) MB)")
    }
    
    // MARK: - Voxel Access
    
    /// Get voxel value at specific 3D coordinate
    public func getVoxel(x: Int, y: Int, z: Int) -> Int16? {
        guard x >= 0 && x < dimensions.x &&
              y >= 0 && y < dimensions.y &&
              z >= 0 && z < dimensions.z else {
            return nil
        }
        
        let index = z * (dimensions.x * dimensions.y) + y * dimensions.x + x
        return voxelData[index]
    }
    
    /// Get interpolated voxel value at floating-point coordinates
    public func getInterpolatedVoxel(x: Float, y: Float, z: Float) -> Float {
        // Trilinear interpolation
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let z0 = Int(floor(z))
        
        let x1 = x0 + 1
        let y1 = y0 + 1
        let z1 = z0 + 1
        
        // Interpolation weights
        let fx = x - Float(x0)
        let fy = y - Float(y0)
        let fz = z - Float(z0)
        
        // Get 8 corner voxels
        let v000 = Float(getVoxel(x: x0, y: y0, z: z0) ?? 0)
        let v100 = Float(getVoxel(x: x1, y: y0, z: z0) ?? 0)
        let v010 = Float(getVoxel(x: x0, y: y1, z: z0) ?? 0)
        let v110 = Float(getVoxel(x: x1, y: y1, z: z0) ?? 0)
        let v001 = Float(getVoxel(x: x0, y: y0, z: z1) ?? 0)
        let v101 = Float(getVoxel(x: x1, y: y0, z: z1) ?? 0)
        let v011 = Float(getVoxel(x: x0, y: y1, z: z1) ?? 0)
        let v111 = Float(getVoxel(x: x1, y: y1, z: z1) ?? 0)
        
        // Trilinear interpolation
        let c00 = v000 * (1 - fx) + v100 * fx
        let c01 = v001 * (1 - fx) + v101 * fx
        let c10 = v010 * (1 - fx) + v110 * fx
        let c11 = v011 * (1 - fx) + v111 * fx
        
        let c0 = c00 * (1 - fy) + c10 * fy
        let c1 = c01 * (1 - fy) + c11 * fy
        
        return c0 * (1 - fz) + c1 * fz
    }
    
    // MARK: - Plane Extraction
    
    /// Extract sagittal slice (YZ plane) at given X coordinate
    public func extractSagittalSlice(atX x: Float) -> [Int16] {
        var slice: [Int16] = []
        slice.reserveCapacity(dimensions.y * dimensions.z)
        
        for z in 0..<dimensions.z {
            for y in 0..<dimensions.y {
                let value = getInterpolatedVoxel(x: x, y: Float(y), z: Float(z))
                slice.append(Int16(value))
            }
        }
        
        return slice
    }
    
    /// Extract coronal slice (XZ plane) at given Y coordinate
    public func extractCoronalSlice(atY y: Float) -> [Int16] {
        var slice: [Int16] = []
        slice.reserveCapacity(dimensions.x * dimensions.z)
        
        for z in 0..<dimensions.z {
            for x in 0..<dimensions.x {
                let value = getInterpolatedVoxel(x: Float(x), y: y, z: Float(z))
                slice.append(Int16(value))
            }
        }
        
        return slice
    }
    
    /// Extract axial slice (XY plane) at given Z coordinate
    public func extractAxialSlice(atZ z: Float) -> [Int16] {
        var slice: [Int16] = []
        slice.reserveCapacity(dimensions.x * dimensions.y)
        
        for y in 0..<dimensions.y {
            for x in 0..<dimensions.x {
                let value = getInterpolatedVoxel(x: Float(x), y: Float(y), z: z)
                slice.append(Int16(value))
            }
        }
        
        return slice
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert patient coordinates to voxel coordinates
    public func patientToVoxel(_ patientCoord: SIMD3<Float>) -> SIMD3<Float> {
        let relativePos = patientCoord - origin
        let voxelCoord = simd_mul(simd_inverse(orientation), relativePos) / spacing
        return voxelCoord
    }
    
    /// Convert voxel coordinates to patient coordinates
    public func voxelToPatient(_ voxelCoord: SIMD3<Float>) -> SIMD3<Float> {
        let scaledCoord = voxelCoord * spacing
        let rotatedCoord = simd_mul(orientation, scaledCoord)
        return origin + rotatedCoord
    }
    
    // MARK: - Helper Methods
    
    private static func extractSliceInfo(from dataset: ParsedDICOMDataset, index: Int) throws -> SliceInfo {
        // Extract image position
        let position = extractImagePosition(from: dataset) ?? SIMD3<Float>(0, 0, Float(index))
        
        // Extract image orientation
        let orientation = extractImageOrientation(from: dataset) ?? matrix_identity_float3x3
        
        // Extract pixel spacing
        let pixelSpacing = extractPixelSpacing(from: dataset) ?? SIMD2<Float>(1.0, 1.0)
        
        // Extract other parameters
        let sliceThickness = Float(dataset.sliceThickness ?? 1.0)
        let instanceNumber = Int(dataset.getUInt16(tag: .instanceNumber) ?? UInt16(index))
        let sliceLocation = Float(dataset.getDouble(tag: .sliceLocation) ?? Double(index))
        let rescaleSlope = Float(dataset.getDouble(tag: .rescaleSlope) ?? 1.0)
        let rescaleIntercept = Float(dataset.getDouble(tag: .rescaleIntercept) ?? 0.0)
        
        return SliceInfo(
            position: position,
            orientation: orientation,
            pixelSpacing: pixelSpacing,
            sliceThickness: sliceThickness,
            instanceNumber: instanceNumber,
            sliceLocation: sliceLocation,
            rescaleSlope: rescaleSlope,
            rescaleIntercept: rescaleIntercept
        )
    }
    
    private static func extractImagePosition(from dataset: ParsedDICOMDataset) -> SIMD3<Float>? {
        guard let positionString = dataset.imagePosition else { return nil }
        
        let components = positionString.split(separator: "\\").compactMap { Float(String($0)) }
        guard components.count >= 3 else { return nil }
        
        return SIMD3<Float>(components[0], components[1], components[2])
    }
    
    private static func extractImageOrientation(from dataset: ParsedDICOMDataset) -> simd_float3x3? {
        guard let orientationString = dataset.imageOrientation else { return nil }
        
        let components = orientationString.split(separator: "\\").compactMap { Float(String($0)) }
        guard components.count >= 6 else { return nil }
        
        // DICOM stores row direction (first 3) and column direction (next 3)
        let rowDirection = SIMD3<Float>(components[0], components[1], components[2])
        let colDirection = SIMD3<Float>(components[3], components[4], components[5])
        let sliceDirection = cross(rowDirection, colDirection)
        
        // Create 3x3 orientation matrix
        return simd_float3x3(
            SIMD3<Float>(rowDirection.x, colDirection.x, sliceDirection.x),
            SIMD3<Float>(rowDirection.y, colDirection.y, sliceDirection.y),
            SIMD3<Float>(rowDirection.z, colDirection.z, sliceDirection.z)
        )
    }
    
    private static func extractPixelSpacing(from dataset: ParsedDICOMDataset) -> SIMD2<Float>? {
        guard let spacingString = dataset.pixelSpacing else { return nil }
        
        let components = spacingString.split(separator: "\\").compactMap { Float(String($0)) }
        guard components.count >= 2 else { return nil }
        
        return SIMD2<Float>(components[0], components[1])  // row spacing, column spacing
    }
    
    private static func calculateVolumeSpacing(from sliceInfos: [SliceInfo]) -> SIMD3<Float> {
        guard !sliceInfos.isEmpty else { return SIMD3<Float>(1, 1, 1) }
        
        // Use pixel spacing from first slice for X and Y
        let pixelSpacing = sliceInfos[0].pixelSpacing
        
        // Calculate Z spacing from slice positions
        let zSpacing: Float
        if sliceInfos.count > 1 {
            let firstPos = sliceInfos[0].position
            let lastPos = sliceInfos[sliceInfos.count - 1].position
            let distance = simd_length(lastPos - firstPos)
            zSpacing = distance / Float(sliceInfos.count - 1)
        } else {
            zSpacing = sliceInfos[0].sliceThickness
        }
        
        return SIMD3<Float>(pixelSpacing.x, pixelSpacing.y, zSpacing)
    }
    
    // MARK: - Volume Statistics
    
    public func getStatistics() -> VolumeStatistics {
        let minValue = voxelData.min() ?? 0
        let maxValue = voxelData.max() ?? 0
        let sum = voxelData.reduce(0) { $0 + Int64($1) }
        let mean = Float(sum) / Float(voxelData.count)
        
        return VolumeStatistics(
            dimensions: dimensions,
            spacing: spacing,
            minValue: minValue,
            maxValue: maxValue,
            meanValue: mean,
            voxelCount: voxelData.count,
            memoryUsage: voxelData.count * MemoryLayout<Int16>.size
        )
    }
}

// MARK: - Supporting Types

public struct VolumeStatistics {
    public let dimensions: SIMD3<Int>
    public let spacing: SIMD3<Float>
    public let minValue: Int16
    public let maxValue: Int16
    public let meanValue: Float
    public let voxelCount: Int
    public let memoryUsage: Int
}

public enum VolumeError: Error, LocalizedError {
    case emptyDataset
    case invalidDimensions
    case missingPixelData(slice: Int)
    case spatialMismatch
    
    public var errorDescription: String? {
        switch self {
        case .emptyDataset:
            return "No DICOM datasets provided for volume reconstruction"
        case .invalidDimensions:
            return "Invalid or missing image dimensions in DICOM data"
        case .missingPixelData(let slice):
            return "Missing pixel data for slice \(slice)"
        case .spatialMismatch:
            return "Inconsistent spatial parameters across slices"
        }
    }
}

// MARK: - Volume Orientation Utilities

extension VolumeData {
    
    /// Get anatomical direction labels for current orientation
    public func getAnatomicalDirections() -> (right: SIMD3<Float>, anterior: SIMD3<Float>, superior: SIMD3<Float>) {
        // Standard anatomical directions in patient coordinate system
        let right = SIMD3<Float>(1, 0, 0)      // Patient's right
        let anterior = SIMD3<Float>(0, 1, 0)   // Patient's front
        let superior = SIMD3<Float>(0, 0, 1)   // Patient's top
        
        return (right, anterior, superior)
    }
    
    /// Convert slice index to anatomical position
    public func sliceIndexToAnatomicalPosition(_ index: Int, plane: MPRPlane) -> String {
        switch plane {
        case .axial:
            let position = Float(index) / Float(dimensions.z - 1)
            return position > 0.5 ? "Superior" : "Inferior"
        case .sagittal:
            let position = Float(index) / Float(dimensions.x - 1)
            return position > 0.5 ? "Right" : "Left"
        case .coronal:
            let position = Float(index) / Float(dimensions.y - 1)
            return position > 0.5 ? "Anterior" : "Posterior"
        }
    }
}
