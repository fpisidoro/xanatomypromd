import Metal
import MetalKit
import UIKit

// MARK: - Metal Medical Renderer
// High-performance GPU-based medical image rendering for iOS
// Optimized for CT DICOM data with real-time windowing

public class MetalRenderer {
    
    // MARK: - Core Metal Components
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private var windowingPipelineState: MTLComputePipelineState?
    
    // MARK: - Rendering Configuration
    
    public struct RenderConfig {
        let windowCenter: Float
        let windowWidth: Float
        let outputFormat: MTLPixelFormat
        
        public init(windowCenter: Float, windowWidth: Float, outputFormat: MTLPixelFormat = .rgba8Unorm) {
            self.windowCenter = windowCenter
            self.windowWidth = windowWidth
            self.outputFormat = outputFormat
        }
    }
    
    // MARK: - Error Handling
    
    public enum MetalError: Error, LocalizedError {
        case deviceNotAvailable
        case shaderCompilationFailed
        case pipelineCreationFailed
        case textureCreationFailed
        
        public var errorDescription: String? {
            switch self {
            case .deviceNotAvailable:
                return "Metal device not available on this device"
            case .shaderCompilationFailed:
                return "Failed to compile Metal shaders"
            case .pipelineCreationFailed:
                return "Failed to create Metal pipeline"
            case .textureCreationFailed:
                return "Failed to create Metal texture"
            }
        }
    }
    
    // MARK: - Initialization
    
    public init() throws {
        // Get Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalError.deviceNotAvailable
        }
        self.device = device
        
        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalError.deviceNotAvailable
        }
        self.commandQueue = commandQueue
        
        // Create shader library
        guard let library = device.makeDefaultLibrary() else {
            throw MetalError.shaderCompilationFailed
        }
        self.library = library
        
        // Setup compute pipeline for windowing
        try setupWindowingPipeline()
        
        print("✅ MetalRenderer initialized successfully")
        print("   🖥️  Device: \(device.name)")
        print("   🧠 Max threads per group: \(device.maxThreadsPerThreadgroup)")
    }
    
    // MARK: - Texture Creation from DICOM Pixel Data
    
    /// Create Metal texture from DICOM pixel data
    public func createTexture(from pixelData: PixelData) throws -> MTLTexture {
        let width = pixelData.columns
        let height = pixelData.rows
        guard pixelData.columns > 0 && pixelData.rows > 0 else {
//            print("❌ Invalid texture dimensions: \(pixelData.columns)×\(pixelData.rows)")
            throw MetalError.textureCreationFailed
        }
        // Create texture descriptor for 16-bit signed integer data
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Sint,  // 16-bit signed integer format for signed CT data
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalError.textureCreationFailed
        }
        
        // Use appropriate pixel array based on pixel representation
        let pixelArray: [Int16]
        if pixelData.pixelRepresentation == 1 {
            // Signed pixel data - use Int16 values
            pixelArray = pixelData.toInt16Array()
        } else {
            // Unsigned pixel data - convert to signed range
            let uint16Array = pixelData.toUInt16Array()
            pixelArray = uint16Array.map { value in
                // Convert unsigned to signed, handling overflow
                if value > 32767 {
                    return Int16(Int32(value) - 65536)
                } else {
                    return Int16(value)
                }
            }
        }
        
        // Upload pixel data to GPU texture
        let region = MTLRegionMake2D(0, 0, width, height)
        let bytesPerRow = width * 2  // 2 bytes per Int16 pixel
        
        pixelArray.withUnsafeBytes { bytes in
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: bytesPerRow
            )
        }
        
        return texture
    }
    
    // MARK: - CT Windowing Rendering
    
    /// Render CT image with windowing applied
    public func renderCTImage(
        inputTexture: MTLTexture,
        config: RenderConfig,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        // Create output texture for windowed image
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: config.outputFormat,
            width: inputTexture.width,
            height: inputTexture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite, .shaderRead]
        
        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            completion(nil)
            return
        }
        
        // Execute windowing on GPU
        executeWindowing(
            input: inputTexture,
            output: outputTexture,
            config: config
        ) { success in
            completion(success ? outputTexture : nil)
        }
    }
    
    // MARK: - GPU Compute Execution
    
    private func executeWindowing(
        input: MTLTexture,
        output: MTLTexture,
        config: RenderConfig,
        completion: @escaping (Bool) -> Void
    ) {
        guard let pipelineState = windowingPipelineState else {
            completion(false)
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            completion(false)
            return
        }
        
        // Setup compute pipeline
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        
        // Pass windowing parameters to shader
        var windowingParams = WindowingParams(
            windowCenter: config.windowCenter,
            windowWidth: config.windowWidth
        )
        encoder.setBytes(&windowingParams, length: MemoryLayout<WindowingParams>.size, index: 0)
        
        // Calculate thread groups for parallel execution (iOS Simulator compatible)
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let gridWidth = (input.width + threadsPerGroup.width - 1) / threadsPerGroup.width
        let gridHeight = (input.height + threadsPerGroup.height - 1) / threadsPerGroup.height
        let threadgroupsPerGrid = MTLSize(width: gridWidth, height: gridHeight, depth: 1)
        
        // Use simulator-compatible dispatch method
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
    
    // MARK: - Pipeline Setup
    
    private func setupWindowingPipeline() throws {
        guard let function = library.makeFunction(name: "ctWindowing") else {
            throw MetalError.shaderCompilationFailed
        }
        
        do {
            windowingPipelineState = try device.makeComputePipelineState(function: function)
            print("✅ CT windowing pipeline created successfully")
        } catch {
            print("❌ Pipeline creation failed: \(error)")
            throw MetalError.pipelineCreationFailed
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Quick render with standard CT presets
    public func renderWithPreset(
        inputTexture: MTLTexture,
        preset: CTWindowPresets.WindowLevel,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        let config = RenderConfig(
            windowCenter: Float(preset.center),
            windowWidth: Float(preset.width)
        )
        
        renderCTImage(
            inputTexture: inputTexture,
            config: config,
            completion: completion
        )
    }
    
    /// Convert texture to UIImage for display
    public func textureToUIImage(_ texture: MTLTexture) -> UIImage? {
        guard texture.pixelFormat == .rgba8Unorm else {
            print("⚠️  Texture must be RGBA8Unorm format for UIImage conversion")
            return nil
        }
        
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&pixelData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        guard let dataProvider = CGDataProvider(data: Data(pixelData) as CFData) else {
            return nil
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Windowing Parameters Structure

private struct WindowingParams {
    let windowCenter: Float
    let windowWidth: Float
}

// MARK: - Performance Monitoring Extension

extension MetalRenderer {
    
    /// Get GPU performance metrics
    public func getPerformanceInfo() -> String {
        return """
        🖥️  GPU: \(device.name)
        🧠 Max threads: \(device.maxThreadsPerThreadgroup)
        💾 Max buffer size: \(device.maxBufferLength / 1024 / 1024) MB
        ⚡ Supports non-uniform threadgroups: \(device.supportsFamily(.apple4))
        """
    }
}
