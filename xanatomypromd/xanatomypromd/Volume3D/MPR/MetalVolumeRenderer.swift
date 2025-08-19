import Foundation
import Metal
import simd

// MARK: - Hardware Accelerated Metal Volume Renderer
// GPU-accelerated 3D volume reconstruction and MPR slice generation
// Uses r16Sint format with hardware sampling for maximum performance

public class MetalVolumeRenderer {
    
    // MARK: - Core Metal Components
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    // 3D Volume Storage
    public var volumeData: VolumeData?
    private var volumeTexture: MTLTexture?
    
    // MPR Compute Pipeline
    private var mprPipelineState: MTLComputePipelineState?
    
    // MARK: - Configuration for MPR Generation
    
    public enum RenderQuality {
        case full      // 512×512 or native resolution
        case half      // 256×256 or half resolution
        case quarter   // 128×128 or quarter resolution
        case eighth    // 64×64 for very fast scrolling
        
        var scaleFactor: Float {
            switch self {
            case .full: return 1.0
            case .half: return 0.5
            case .quarter: return 0.25
            case .eighth: return 0.125
            }
        }
        
        var description: String {
            switch self {
            case .full: return "Full"
            case .half: return "Half"
            case .quarter: return "Quarter"
            case .eighth: return "Eighth"
            }
        }
    }
    
    public struct MPRConfig {
        public let plane: MPRPlane
        public let sliceIndex: Float        // 0.0 to 1.0 normalized position
        public let windowCenter: Float
        public let windowWidth: Float
        public let quality: RenderQuality   // Adaptive quality level
        
        public init(plane: MPRPlane, sliceIndex: Float, windowCenter: Float = 0.0, windowWidth: Float = 2000.0, quality: RenderQuality = .full) {
            self.plane = plane
            self.sliceIndex = sliceIndex
            self.windowCenter = windowCenter
            self.windowWidth = windowWidth
            self.quality = quality
        }
    }
    
    // MARK: - Initialization
    
    public init() throws {
        // Initialize Metal components
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalVolumeError.deviceNotAvailable
        }
        self.device = device
        
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalVolumeError.deviceNotAvailable
        }
        self.commandQueue = commandQueue
        
        guard let library = device.makeDefaultLibrary() else {
            throw MetalVolumeError.shaderCompilationFailed
        }
        self.library = library
        
        // Setup MPR pipeline
        try setupMPRPipeline()
    }
    
    // MARK: - Volume Loading
    
    /// Load volume data into 3D Metal texture with hardware sampling support
    public func loadVolume(_ volumeData: VolumeData) throws {
        self.volumeData = volumeData
        
        // Use r16Sint format directly (no conversion needed)
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r16Sint  // Use signed integer format directly
        descriptor.width = volumeData.dimensions.x
        descriptor.height = volumeData.dimensions.y
        descriptor.depth = volumeData.dimensions.z
        descriptor.usage = [.shaderRead]  // Read-only (enables sampling)
        descriptor.storageMode = .shared  // Accessible by both CPU and GPU
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalVolumeError.textureCreationFailed
        }
        
        // Upload volume data to 3D texture directly as Int16
        let bytesPerRow = volumeData.dimensions.x * MemoryLayout<Int16>.size  // 2 bytes per Int16
        let bytesPerImage = bytesPerRow * volumeData.dimensions.y
        
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(
                width: volumeData.dimensions.x,
                height: volumeData.dimensions.y,
                depth: volumeData.dimensions.z
            )
        )
        
        // Direct upload without conversion
        volumeData.voxelData.withUnsafeBytes { bytes in
            texture.replace(
                region: region,
                mipmapLevel: 0,
                slice: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: bytesPerRow,
                bytesPerImage: bytesPerImage
            )
        }
        
        self.volumeTexture = texture
    }
    
    // MARK: - MPR Slice Generation (Hardware Accelerated)
    
    /// Generate MPR slice from 3D volume using hardware sampling with adaptive quality
    public func generateMPRSlice(
        config: MPRConfig,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        guard let volumeTexture = volumeTexture,
              let pipelineState = mprPipelineState else {
            completion(nil)
            return
        }
        
        // Calculate output dimensions based on plane and quality
        let baseSize = getOutputDimensions(for: config.plane)
        
        // Apply quality scaling
        let scaledWidth = max(32, Int(Float(baseSize.width) * config.quality.scaleFactor))
        let scaledHeight = max(32, Int(Float(baseSize.height) * config.quality.scaleFactor))
        
        // Create output texture at adjusted resolution
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: scaledWidth,
            height: scaledHeight,
            mipmapped: false
        )
        outputDescriptor.usage = [.shaderWrite, .shaderRead]
        
        guard let outputTexture = device.makeTexture(descriptor: outputDescriptor) else {
            completion(nil)
            return
        }
        
        // Execute hardware accelerated MPR compute shader
        executeMPRCompute(
            volumeTexture: volumeTexture,
            outputTexture: outputTexture,
            config: config,
            pipelineState: pipelineState
        ) { success in
            completion(success ? outputTexture : nil)
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Generate sagittal slice at normalized X position (0.0 = left, 1.0 = right)
    public func generateSagittalSlice(
        atPosition position: Float,
        windowCenter: Float = 0.0,
        windowWidth: Float = 2000.0,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        let safePosition = max(0.0, min(1.0, position))
        let config = MPRConfig(
            plane: .sagittal,
            sliceIndex: safePosition,
            windowCenter: windowCenter,
            windowWidth: windowWidth
        )
        
        generateMPRSlice(config: config, completion: completion)
    }
    
    /// Generate coronal slice at normalized Y position (0.0 = posterior, 1.0 = anterior)
    public func generateCoronalSlice(
        atPosition position: Float,
        windowCenter: Float = 0.0,
        windowWidth: Float = 2000.0,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        let safePosition = max(0.0, min(1.0, position))
        let config = MPRConfig(
            plane: .coronal,
            sliceIndex: safePosition,
            windowCenter: windowCenter,
            windowWidth: windowWidth
        )
        
        generateMPRSlice(config: config, completion: completion)
    }
    
    /// Generate axial slice at normalized Z position (0.0 = inferior, 1.0 = superior)
    public func generateAxialSlice(
        atPosition position: Float,
        windowCenter: Float = 0.0,
        windowWidth: Float = 2000.0,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        let safePosition = max(0.0, min(1.0, position))
        let config = MPRConfig(
            plane: .axial,
            sliceIndex: safePosition,
            windowCenter: windowCenter,
            windowWidth: windowWidth
        )
        
        generateMPRSlice(config: config, completion: completion)
    }
    
    // MARK: - Private Implementation
    
    private func setupMPRPipeline() throws {
        guard let function = library.makeFunction(name: "mprSliceExtractionHardware") else {
            throw MetalVolumeError.shaderCompilationFailed
        }
        
        do {
            mprPipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            throw MetalVolumeError.pipelineCreationFailed
        }
    }
    
    private func getOutputDimensions(for plane: MPRPlane) -> (width: Int, height: Int) {
        guard let volumeData = volumeData else {
            return (512, 512)  // Default fallback
        }
        
        let dims = volumeData.dimensions
        
        switch plane {
        case .axial:
            // XY plane - maintain original matrix size
            return (dims.x, dims.y)
            
        case .sagittal:
            // YZ plane - Y (anterior-posterior) x Z (superior-inferior)
            // Keep voxel grid dimensions, let display handle aspect ratio
            return (dims.y, dims.z)
            
        case .coronal:
            // XZ plane - X (left-right) x Z (superior-inferior)
            // Keep voxel grid dimensions, let display handle aspect ratio
            return (dims.x, dims.z)
        }
    }
    
    private func executeMPRCompute(
        volumeTexture: MTLTexture,
        outputTexture: MTLTexture,
        config: MPRConfig,
        pipelineState: MTLComputePipelineState,
        completion: @escaping (Bool) -> Void
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            completion(false)
            return
        }
        
        // Setup compute pipeline
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(volumeTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        // Setup shader parameters
        guard let volumeData = volumeData else {
            completion(false)
            return
        }
        
        var params = MPRParams(
            planeType: {
                switch config.plane {
                case .axial: return 0
                case .sagittal: return 1
                case .coronal: return 2
                }
            }(),
            slicePosition: config.sliceIndex,
            windowCenter: config.windowCenter,
            windowWidth: config.windowWidth,
            volumeDimensions: SIMD3<UInt32>(
                UInt32(volumeData.dimensions.x),
                UInt32(volumeData.dimensions.y),
                UInt32(volumeData.dimensions.z)
            ),
            spacing: volumeData.spacing
        )
        
        encoder.setBytes(&params, length: MemoryLayout<MPRParams>.size, index: 0)
        
        // Calculate thread groups
        let threadgroupSize = MTLSizeMake(16, 16, 1)
        let threadgroupCount = MTLSizeMake(
            (outputTexture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            (outputTexture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            1
        )
        
        encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.addCompletedHandler { _ in
            completion(true)
        }
        
        // Add error handler before commit to catch failures
        commandBuffer.addErrorHandler { commandBuffer in
            print("❌ METAL ERROR: Command buffer failed with error: \(commandBuffer.error?.localizedDescription ?? "Unknown")")
            completion(false)
        }
        
        // Validate command buffer before commit
        guard commandBuffer.status == .notEnqueued else {
            print("❌ METAL ERROR: Invalid command buffer status: \(commandBuffer.status)")
            completion(false)
            return
        }
        
        commandBuffer.commit()
    }
    
    // MARK: - Volume Information and Status
    
    public func getVolumeInfo() -> String? {
        guard let volumeData = volumeData else { return nil }
        
        let stats = volumeData.getStatistics()
        
        return """
        📊 Hardware Accelerated Volume Information:
           🚀 Sampling: Hardware-accelerated r16Sint (.sample() calls)
           📐 Dimensions: \(stats.dimensions.x)×\(stats.dimensions.y)×\(stats.dimensions.z)
           📏 Spacing: \(String(format: "%.2f", stats.spacing.x))×\(String(format: "%.2f", stats.spacing.y))×\(String(format: "%.2f", stats.spacing.z)) mm
           📊 Value range: \(stats.minValue) to \(stats.maxValue) HU
           💾 Memory: \(String(format: "%.1f", Double(stats.memoryUsage) / 1024.0 / 1024.0)) MB
           🔢 Total voxels: \(stats.voxelCount)
        """
    }
    
    public func isVolumeLoaded() -> Bool {
        return volumeTexture != nil && volumeData != nil
    }
    
    // MARK: - Volume Properties Access
    
    public func getVolumeDimensions() -> SIMD3<Int>? {
        return volumeData?.dimensions
    }
    
    public func getVolumeSpacing() -> SIMD3<Float>? {
        return volumeData?.spacing
    }
    
    // MARK: - Load volume from DICOM files
    
    /// Load volume from DICOM files with hardware acceleration
    public func loadVolumeFromDICOMFiles(_ fileURLs: [URL]) async throws -> VolumeData {
        var datasets: [(DICOMDataset, Int)] = []
        
        for (index, fileURL) in fileURLs.enumerated() {
            do {
                let data = try Data(contentsOf: fileURL)
                let dataset = try DICOMParser.parse(data)
                datasets.append((dataset, index))
            } catch {
                throw error
            }
        }
        
        // Create volume from datasets
        let volumeData = try VolumeData(from: datasets)
        
        // Store the volume data in this renderer instance
        try loadVolume(volumeData)
        
        return volumeData
    }
}

// MARK: - Shader Parameters Structure

private struct MPRParams {
    let planeType: UInt32           // 0=axial, 1=sagittal, 2=coronal
    let slicePosition: Float        // 0.0 to 1.0 normalized position
    let windowCenter: Float
    let windowWidth: Float
    let volumeDimensions: SIMD3<UInt32>
    let spacing: SIMD3<Float>
}

// MARK: - Error Handling

public enum MetalVolumeError: Error, LocalizedError {
    case deviceNotAvailable
    case shaderCompilationFailed
    case pipelineCreationFailed
    case textureCreationFailed
    case volumeNotLoaded
    
    public var errorDescription: String? {
        switch self {
        case .deviceNotAvailable:
            return "Metal device not available"
        case .shaderCompilationFailed:
            return "Failed to compile hardware-accelerated MPR shaders"
        case .pipelineCreationFailed:
            return "Failed to create hardware MPR pipeline"
        case .textureCreationFailed:
            return "Failed to create 3D r16Sint texture"
        case .volumeNotLoaded:
            return "Volume data not loaded"
        }
    }
}

// MARK: - Conversion to PixelData

extension MetalVolumeRenderer {
    
    /// Convert hardware-accelerated MPR slice to PixelData for existing pipeline
    public func mprSliceToPixelData(
        plane: MPRPlane,
        slicePosition: Float
    ) -> PixelData? {
        guard let volumeData = volumeData else { return nil }
        
        // Use hardware-accelerated GPU extraction instead of CPU interpolation
        // For now, fall back to CPU but this could be GPU-accelerated texture readback
        let sliceData: [Int16]
        let dimensions: (width: Int, height: Int)
        
        switch plane {
        case .axial:
            let z = slicePosition * Float(volumeData.dimensions.z - 1)
            sliceData = volumeData.extractAxialSlice(atZ: z)
            dimensions = (volumeData.dimensions.x, volumeData.dimensions.y)
            
        case .sagittal:
            let x = slicePosition * Float(volumeData.dimensions.x - 1)
            sliceData = volumeData.extractSagittalSlice(atX: x)
            dimensions = (volumeData.dimensions.y, volumeData.dimensions.z)
            
        case .coronal:
            let y = slicePosition * Float(volumeData.dimensions.y - 1)
            sliceData = volumeData.extractCoronalSlice(atY: y)
            dimensions = (volumeData.dimensions.x, volumeData.dimensions.z)
        }
        
        // Convert to Data
        let data = sliceData.withUnsafeBytes { bytes in
            Data(bytes: bytes.baseAddress!, count: bytes.count)
        }
        
        return PixelData(
            data: data,
            rows: dimensions.height,
            columns: dimensions.width,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            pixelRepresentation: 1  // Signed
        )
    }
}
