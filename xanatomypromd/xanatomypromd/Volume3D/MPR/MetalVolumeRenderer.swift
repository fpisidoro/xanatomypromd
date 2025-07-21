import Metal
import MetalKit
import simd

// MARK: - Metal Volume Renderer
// GPU-accelerated Multi-Planar Reconstruction (MPR)
// WORKING VERSION: Integer textures with manual interpolation

public class MetalVolumeRenderer {
    
    // MARK: - Core Metal Components
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    // MPR Compute Pipelines
    private var mprPipelineState: MTLComputePipelineState?
    private var volumeTexture: MTLTexture?
    private var volumeData: VolumeData?
    
    // MARK: - MPR Configuration
    
    public struct MPRConfig {
        let plane: MPRPlane
        let sliceIndex: Float           // 0.0 to 1.0 normalized position
        let windowCenter: Float
        let windowWidth: Float
        let interpolation: InterpolationType
        
        public init(
            plane: MPRPlane,
            sliceIndex: Float,
            windowCenter: Float = 0.0,
            windowWidth: Float = 2000.0,
            interpolation: InterpolationType = .trilinear
        ) {
            self.plane = plane
            self.sliceIndex = sliceIndex
            self.windowCenter = windowCenter
            self.windowWidth = windowWidth
            self.interpolation = interpolation
        }
    }
    
    public enum InterpolationType {
        case nearestNeighbor
        case trilinear
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
        
        // Setup MPR compute pipeline
        try setupMPRPipeline()
        
        print("✅ MetalVolumeRenderer initialized")
        print("   🖥️  Device: \(device.name)")
        print("   🧠 3D texture support: \(device.supportsFamily(.apple4) ? "Yes" : "Limited")")
    }
    
    // MARK: - Volume Loading (WORKING VERSION - Integer Textures)
    
    /// Load volume data into 3D Metal texture
    public func loadVolume(_ volumeData: VolumeData) throws {
        self.volumeData = volumeData
        
        // WORKING: Create 3D texture descriptor for integer format
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r16Sint  // Integer format (working)
        descriptor.width = volumeData.dimensions.x
        descriptor.height = volumeData.dimensions.y
        descriptor.depth = volumeData.dimensions.z
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared  // Accessible by both CPU and GPU
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalVolumeError.textureCreationFailed
        }
        
        // Upload volume data to 3D texture
        let bytesPerRow = volumeData.dimensions.x * MemoryLayout<Int16>.size
        let bytesPerImage = bytesPerRow * volumeData.dimensions.y
        
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(
                width: volumeData.dimensions.x,
                height: volumeData.dimensions.y,
                depth: volumeData.dimensions.z
            )
        )
        
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
        
        let stats = volumeData.getStatistics()
        print("✅ 3D texture created: \(stats.dimensions.x)×\(stats.dimensions.y)×\(stats.dimensions.z)")
        print("   💾 GPU memory: \(String(format: "%.1f", Double(stats.memoryUsage) / 1024.0 / 1024.0)) MB")
        print("   📊 Value range: \(stats.minValue) to \(stats.maxValue)")
    }
    
    // MARK: - MPR Slice Generation
    
    /// Generate MPR slice from 3D volume
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
        
        // Execute MPR compute shader
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
        let safePosition = max(0.0, min(1.0, position)) // Clamp position
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
        let safePosition = max(0.0, min(1.0, position)) // Clamp position
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
        let safePosition = max(0.0, min(1.0, position)) // Clamp position
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
        guard let function = library.makeFunction(name: "mprSliceExtraction") else {
            throw MetalVolumeError.shaderCompilationFailed
        }
        
        do {
            mprPipelineState = try device.makeComputePipelineState(function: function)
            print("✅ MPR compute pipeline created")
        } catch {
            print("❌ MPR pipeline creation failed: \(error)")
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
            return (dims.x, dims.y)  // XY plane (512 × 512)
        case .sagittal:
            return (dims.y, dims.z)  // YZ plane (512 × 53)
        case .coronal:
            return (dims.x, dims.z)  // XZ plane (512 × 53)
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
        encoder.setTexture(volumeTexture, index: 0)      // Input 3D volume
        encoder.setTexture(outputTexture, index: 1)      // Output 2D slice
        
        // Pass MPR parameters to shader with safe conversions
        let planeTypeValue: UInt32
        switch config.plane {
        case .axial:
            planeTypeValue = 0
        case .sagittal:
            planeTypeValue = 1
        case .coronal:
            planeTypeValue = 2
        }
        
        var mprParams = MPRShaderParams(
            planeType: planeTypeValue,
            slicePosition: max(0.0, min(1.0, config.sliceIndex)), // Clamp to [0,1]
            windowCenter: config.windowCenter,
            windowWidth: config.windowWidth,
            volumeDimensions: SIMD3<UInt32>(
                UInt32(min(volumeTexture.width, 65535)),    // Prevent overflow
                UInt32(min(volumeTexture.height, 65535)),   // Prevent overflow
                UInt32(min(volumeTexture.depth, 65535))     // Prevent overflow
            ),
            spacing: volumeData?.spacing ?? SIMD3<Float>(1, 1, 1)
        )
        
        encoder.setBytes(&mprParams, length: MemoryLayout<MPRShaderParams>.size, index: 0)
        
        // Calculate threadgroups with safety bounds
        let maxThreadsPerGroup = 16 // Conservative for compatibility
        let threadsPerGroup = MTLSize(width: maxThreadsPerGroup, height: maxThreadsPerGroup, depth: 1)
        
        let gridWidth = (outputTexture.width + maxThreadsPerGroup - 1) / maxThreadsPerGroup
        let gridHeight = (outputTexture.height + maxThreadsPerGroup - 1) / maxThreadsPerGroup
        let threadgroupsPerGrid = MTLSize(width: gridWidth, height: gridHeight, depth: 1)
        
        // Bounds check threadgroups
        let maxGridSize = 65535 // Metal limit
        guard gridWidth <= maxGridSize && gridHeight <= maxGridSize else {
            print("❌ Threadgroup size too large: \(gridWidth)x\(gridHeight)")
            completion(false)
            return
        }
        
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        // Execute on GPU
        commandBuffer.addCompletedHandler { _ in
            DispatchQueue.main.async {
                completion(true)
            }
        }
        commandBuffer.commit()
    }
    
    // MARK: - Volume Information
    
    public func getVolumeInfo() -> String? {
        guard let volumeData = volumeData else { return nil }
        
        let stats = volumeData.getStatistics()
        
        return """
        📊 Volume Information:
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
}

// MARK: - Shader Parameters Structure

private struct MPRShaderParams {
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
            return "Failed to compile MPR shaders"
        case .pipelineCreationFailed:
            return "Failed to create MPR pipeline"
        case .textureCreationFailed:
            return "Failed to create 3D texture"
        case .volumeNotLoaded:
            return "Volume data not loaded"
        }
    }
}

// MARK: - Volume Loading Utilities

extension MetalVolumeRenderer {
    
    /// Load volume from DICOM files
    public static func loadVolumeFromDICOMFiles(_ fileURLs: [URL]) async throws -> VolumeData {
        print("📂 Loading volume from \(fileURLs.count) DICOM files...")
        
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
        
        let stats = volumeData.getStatistics()
        print("✅ Volume loading complete:")
        print("   📐 Dimensions: \(stats.dimensions)")
        print("   📏 Spacing: \(stats.spacing) mm")
        print("   📊 Value range: \(stats.minValue) to \(stats.maxValue)")
        
        return volumeData
    }
}

// MARK: - Testing and Validation

extension MetalVolumeRenderer {
    
    /// Test MPR functionality with current volume
    public func testMPRGeneration() {
        guard isVolumeLoaded() else {
            print("❌ No volume loaded for MPR testing")
            return
        }
        
        print("🧪 Testing MPR slice generation...")
        
        let testConfigs = [
            ("Axial Center", MPRConfig(plane: .axial, sliceIndex: 0.5)),
            ("Sagittal Center", MPRConfig(plane: .sagittal, sliceIndex: 0.5)),
            ("Coronal Center", MPRConfig(plane: .coronal, sliceIndex: 0.5))
        ]
        
        for (name, config) in testConfigs {
            generateMPRSlice(config: config) { texture in
                if let texture = texture {
                    print("   ✅ \(name): \(texture.width)×\(texture.height)")
                } else {
                    print("   ❌ \(name): Failed")
                }
            }
        }
    }
}

// MARK: - Conversion to PixelData for Existing Pipeline

extension MetalVolumeRenderer {
    
    /// Convert MPR slice to PixelData for use with existing MetalRenderer
    public func mprSliceToPixelData(
        plane: MPRPlane,
        slicePosition: Float
    ) async -> PixelData? {
        guard let volumeData = volumeData else { return nil }
        
        // Extract slice using CPU interpolation for now
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
