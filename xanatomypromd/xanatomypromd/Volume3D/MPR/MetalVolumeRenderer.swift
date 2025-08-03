import Foundation
import Metal
import simd

// MARK: - FIXED HARDWARE ACCELERATED Metal Volume Renderer
// GPU-accelerated 3D volume reconstruction and MPR slice generation
// Uses r16Sint format with hardware sampling for maximum performance

public class MetalVolumeRenderer {
    
    // MARK: - Core Metal Components
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    // 3D Volume Storage (FIXED: Made public)
    public var volumeData: VolumeData?  // FIXED: Changed from private to public
    private var volumeTexture: MTLTexture?
    
    // MPR Compute Pipeline
    private var mprPipelineState: MTLComputePipelineState?
    
    // MARK: - Configuration for MPR Generation
    
    public struct MPRConfig {
        public let plane: MPRPlane
        public let sliceIndex: Float        // 0.0 to 1.0 normalized position
        public let windowCenter: Float
        public let windowWidth: Float
        
        public init(plane: MPRPlane, sliceIndex: Float, windowCenter: Float = 0.0, windowWidth: Float = 2000.0) {
            self.plane = plane
            self.sliceIndex = sliceIndex
            self.windowCenter = windowCenter
            self.windowWidth = windowWidth
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
        
        // Renderer initialized
    }
    
    // MARK: - Volume Loading (FIXED - No Float16 Conversion)
    
    /// Load volume data into 3D Metal texture with hardware sampling support
    public func loadVolume(_ volumeData: VolumeData) throws {
        self.volumeData = volumeData
        
        // FIXED: Use r16Sint format directly (no conversion needed)
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r16Sint  // FIXED: Use signed integer format directly
        descriptor.width = volumeData.dimensions.x
        descriptor.height = volumeData.dimensions.y
        descriptor.depth = volumeData.dimensions.z
        descriptor.usage = [.shaderRead]  // Read-only (enables sampling)
        descriptor.storageMode = .shared  // Accessible by both CPU and GPU
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalVolumeError.textureCreationFailed
        }
        
        // Upload Int16 data directly
        
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
        
        // Volume texture created successfully
    }
    
    // MARK: - MPR Slice Generation (Hardware Accelerated - Fixed)
    
    /// Generate MPR slice from 3D volume using hardware sampling
    public func generateMPRSlice(
        config: MPRConfig,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        guard let volumeTexture = volumeTexture,
              let pipelineState = mprPipelineState else {
            completion(nil)
            return
        }
        
        // Calculate output dimensions based on plane
        let outputSize = getOutputDimensions(for: config.plane)
        
        // Create output texture
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: outputSize.width,
            height: outputSize.height,
            mipmapped: false
        )
        outputDescriptor.usage = [.shaderWrite, .shaderRead]
        
        guard let outputTexture = device.makeTexture(descriptor: outputDescriptor) else {
            completion(nil)
            return
        }
        
        // Execute FIXED HARDWARE ACCELERATED MPR compute shader
        let startTime = CFAbsoluteTimeGetCurrent()
        
        executeMPRCompute(
            volumeTexture: volumeTexture,
            outputTexture: outputTexture,
            config: config,
            pipelineState: pipelineState
        ) { success in
            let renderTime = CFAbsoluteTimeGetCurrent() - startTime
            
            // MPR generation completed
            
            completion(success ? outputTexture : nil)
        }
    }
    
    // MARK: - Convenience Methods with Performance Logging
    
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
        // FIXED: Use shader that works with r16Sint format
        guard let function = library.makeFunction(name: "mprSliceExtractionHardware") else {
            throw MetalVolumeError.shaderCompilationFailed
        }
        
        do {
            mprPipelineState = try device.makeComputePipelineState(function: function)
            // MPR compute pipeline created
        } catch {
            // Pipeline creation failed
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
            planeType: UInt32(config.plane.rawValue.hash % 3),  // Simple hash to ID
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
        
        commandBuffer.commit()
    }
    
    // MARK: - Volume Information and Status
    
    public func getVolumeInfo() -> String? {
        guard let volumeData = volumeData else { return nil }
        
        let stats = volumeData.getStatistics()
        
        return """
        📊 FIXED HARDWARE ACCELERATED Volume Information:
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
    
    // MARK: - FIXED: Instance method for loading volume from DICOM files
    
    /// Load volume from DICOM files with hardware acceleration (FIXED: Instance method)
    public func loadVolumeFromDICOMFiles(_ fileURLs: [URL]) async throws -> VolumeData {
        print("📂 Loading volume from \(fileURLs.count) DICOM files for FIXED HARDWARE ACCELERATION...")
        
        var datasets: [(DICOMDataset, Int)] = []
        
        for (index, fileURL) in fileURLs.enumerated() {
            do {
                let data = try Data(contentsOf: fileURL)
                let dataset = try DICOMParser.parse(data)
                datasets.append((dataset, index))
                
                if index % 10 == 0 || index < 5 {
                    print("   ✅ Loaded file \(index + 1)/\(fileURLs.count)")
                }
            } catch {
                print("   ❌ Failed to load file \(index): \(fileURL.lastPathComponent) - \(error)")
                throw error
            }
        }
        
        // Create volume from datasets
        let volumeData = try VolumeData(from: datasets)
        
        // Store the volume data in this renderer instance
        try loadVolume(volumeData)
        
        let stats = volumeData.getStatistics()
        print("✅ Volume loading complete for FIXED HARDWARE ACCELERATION:")
        print("   📐 Dimensions: \(stats.dimensions)")
        print("   📏 Spacing: \(stats.spacing) mm")
        print("   📊 Value range: \(stats.minValue) to \(stats.maxValue)")
        
        return volumeData
    }
}

// MARK: - Shader Parameters Structure (Updated for r16Sint)

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

// MARK: - Testing and Validation (Fixed Hardware Accelerated)

extension MetalVolumeRenderer {
    
    /// Test fixed hardware-accelerated MPR functionality with performance measurement
    public func testFixedHardwareAcceleratedMPR() {
        guard isVolumeLoaded() else {
            print("❌ No volume loaded for fixed hardware MPR testing")
            return
        }
        
        print("🚀 Testing FIXED HARDWARE ACCELERATED MPR slice generation...")
        
        let testConfigs = [
            ("Axial Center", MPRConfig(plane: .axial, sliceIndex: 0.5)),
            ("Sagittal Center", MPRConfig(plane: .sagittal, sliceIndex: 0.5)),
            ("Coronal Center", MPRConfig(plane: .coronal, sliceIndex: 0.5))
        ]
        
        for (name, config) in testConfigs {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            generateMPRSlice(config: config) { texture in
                let renderTime = CFAbsoluteTimeGetCurrent() - startTime
                
                if let texture = texture {
                    let timeMs = renderTime * 1000
                    let speedStatus = timeMs < 1.5 ? "🚀 EXCELLENT" : timeMs < 3.0 ? "✅ GOOD" : "⚠️ SLOW"
                    print("   \(speedStatus) \(name): \(texture.width)×\(texture.height) in \(String(format: "%.2f", timeMs))ms")
                } else {
                    print("   ❌ \(name): Failed")
                }
            }
        }
    }
}

// MARK: - Conversion to PixelData (Updated for r16Sint)

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
