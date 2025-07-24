import Metal
import MetalKit
import simd

// MARK: - Metal ROI Renderer
// GPU-accelerated rendering of RTStruct ROI overlays on MPR views

public class MetalROIRenderer {
    
    // MARK: - Core Metal Components
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    // ROI Render Pipelines
    private var filledPipeline: MTLRenderPipelineState?
    private var outlinePipeline: MTLRenderPipelineState?
    private var pointPipeline: MTLRenderPipelineState?
    private var compositePipeline: MTLRenderPipelineState?
    
    // Vertex buffers for ROI geometry
    private var vertexBuffers: [Int: MTLBuffer] = [:]
    private var indexBuffers: [Int: MTLBuffer] = [:]
    
    // MARK: - ROI Rendering Configuration
    
    public struct ROIRenderConfig {
        let opacity: Float
        let lineWidth: Float
        let renderMode: ROIRenderMode
        let enableAntialiasing: Bool
        let enableAnimation: Bool
        let viewportSize: SIMD2<Float>
        
        public init(
            opacity: Float = 0.5,
            lineWidth: Float = 2.0,
            renderMode: ROIRenderMode = .filledWithOutline,
            enableAntialiasing: Bool = true,
            enableAnimation: Bool = false,
            viewportSize: SIMD2<Float> = SIMD2<Float>(512, 512)
        ) {
            self.opacity = opacity
            self.lineWidth = lineWidth
            self.renderMode = renderMode
            self.enableAntialiasing = enableAntialiasing
            self.enableAnimation = enableAnimation
            self.viewportSize = viewportSize
        }
    }
    
    public enum ROIRenderMode: UInt32 {
        case filled = 0
        case outline = 1
        case filledWithOutline = 2
        case points = 3
        case adaptive = 4
    }
    
    // MARK: - Uniform Structures
    
    private struct ROIUniforms {
        let mvpMatrix: simd_float4x4
        let opacity: Float
        let lineWidth: Float
        let renderMode: UInt32
        let viewportSize: SIMD2<Float>
        
        init(mvpMatrix: simd_float4x4, config: ROIRenderConfig) {
            self.mvpMatrix = mvpMatrix
            self.opacity = config.opacity
            self.lineWidth = config.lineWidth
            self.renderMode = config.renderMode.rawValue
            self.viewportSize = config.viewportSize
        }
    }
    
    private struct ROIRenderParams {
        let roiColor: SIMD4<Float>
        let opacity: Float
        let geometricType: UInt32
        let enableAntialiasing: UInt32
        let textureSize: SIMD2<Float>
        
        init(roi: ROIGeometry, config: ROIRenderConfig, textureSize: SIMD2<Float>) {
            self.roiColor = SIMD4<Float>(roi.color.x, roi.color.y, roi.color.z, roi.opacity)
            self.opacity = roi.opacity
            // Convert geometric type to UInt32 safely
            self.geometricType = Self.geometricTypeToUInt32(roi.geometricType)
            self.enableAntialiasing = config.enableAntialiasing ? 1 : 0
            self.textureSize = textureSize
        }
        
        private static func geometricTypeToUInt32(_ type: ContourGeometricType) -> UInt32 {
            switch type {
            case .point: return 0
            case .openPlanar, .openNonplanar: return 1
            case .closedPlanar, .closedNonplanar: return 2
            }
        }
    }
    
    // MARK: - Initialization
    
    public init() throws {
        // Initialize Metal components
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalROIError.deviceNotAvailable
        }
        self.device = device
        
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalROIError.deviceNotAvailable
        }
        self.commandQueue = commandQueue
        
        guard let library = device.makeDefaultLibrary() else {
            throw MetalROIError.shaderCompilationFailed
        }
        self.library = library
        
        // Setup render pipelines
        try setupRenderPipelines()
        
        print("✅ MetalROIRenderer initialized successfully")
        print("   🎨 ROI overlay rendering ready")
        print("   🖥️  Device: \(device.name)")
    }
    
    // MARK: - Main ROI Rendering Interface
    
    /// Render ROI overlays on top of existing texture
    public func renderROIOverlays(
        roiStructures: [ROIStructure],
        onTexture backgroundTexture: MTLTexture,
        plane: MPRPlane,
        slicePosition: Float,
        volumeOrigin: SIMD3<Float>,
        volumeSpacing: SIMD3<Float>,
        config: ROIRenderConfig,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        // Create output texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: backgroundTexture.pixelFormat,
            width: backgroundTexture.width,
            height: backgroundTexture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite, .shaderRead, .renderTarget]
        
        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            completion(nil)
            return
        }
        
        // Copy background to output texture first
        copyTexture(from: backgroundTexture, to: outputTexture) { success in
            guard success else {
                completion(nil)
                return
            }
            
            // Render ROI overlays on top
            self.renderROIsOnTexture(
                roiStructures: roiStructures,
                outputTexture: outputTexture,
                plane: plane,
                slicePosition: slicePosition,
                volumeOrigin: volumeOrigin,
                volumeSpacing: volumeSpacing,
                config: config,
                completion: completion
            )
        }
    }
    
    // MARK: - ROI Geometry Processing
    
    /// Convert ROI contours to Metal vertex data for specific plane
    public func processROIContours(
        _ roiStructures: [ROIStructure],
        plane: MPRPlane,
        slicePosition: Float,
        volumeOrigin: SIMD3<Float>,
        volumeSpacing: SIMD3<Float>,
        tolerance: Float = 1.0
    ) -> [ROIGeometry] {
        
        var roiGeometries: [ROIGeometry] = []
        
        for roi in roiStructures {
            guard roi.isVisible else { continue }
            
            // Get contours for this slice
            let relevantContours = getContoursForSlice(
                roi: roi,
                plane: plane,
                slicePosition: slicePosition,
                tolerance: tolerance
            )
            
            guard !relevantContours.isEmpty else { continue }
            
            // Convert contours to vertex data
            for contour in relevantContours {
                let vertices = convertContourToVertices(
                    contour: contour,
                    plane: plane,
                    volumeOrigin: volumeOrigin,
                    volumeSpacing: volumeSpacing,
                    color: roi.displayColor
                )
                
                if !vertices.isEmpty {
                    let geometry = ROIGeometry(
                        roiNumber: roi.roiNumber,
                        roiName: roi.roiName,
                        vertices: vertices,
                        geometricType: contour.geometricType,
                        color: roi.displayColor,
                        opacity: roi.opacity
                    )
                    roiGeometries.append(geometry)
                }
            }
        }
        
        return roiGeometries
    }
    
    // MARK: - Private Rendering Implementation
    
    private func renderROIsOnTexture(
        roiStructures: [ROIStructure],
        outputTexture: MTLTexture,
        plane: MPRPlane,
        slicePosition: Float,
        volumeOrigin: SIMD3<Float>,
        volumeSpacing: SIMD3<Float>,
        config: ROIRenderConfig,
        completion: @escaping (MTLTexture?) -> Void
    ) {
        // Process ROI geometries
        let roiGeometries = processROIContours(
            roiStructures,
            plane: plane,
            slicePosition: slicePosition,
            volumeOrigin: volumeOrigin,
            volumeSpacing: volumeSpacing
        )
        
        guard !roiGeometries.isEmpty else {
            // No ROIs to render
            completion(outputTexture)
            return
        }
        
        // Create render pass
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            completion(nil)
            return
        }
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .load  // Preserve background
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            completion(nil)
            return
        }
        
        // Setup viewport
        let viewport = MTLViewport(
            originX: 0, originY: 0,
            width: Double(outputTexture.width), height: Double(outputTexture.height),
            znear: 0.0, zfar: 1.0
        )
        renderEncoder.setViewport(viewport)
        
        // Render each ROI geometry
        for geometry in roiGeometries {
            renderROIGeometry(geometry, encoder: renderEncoder, config: config, outputTexture: outputTexture)
        }
        
        renderEncoder.endEncoding()
        
        // Execute rendering
        commandBuffer.addCompletedHandler { _ in
            DispatchQueue.main.async {
                completion(outputTexture)
            }
        }
        commandBuffer.commit()
    }
    
    private func renderROIGeometry(
        _ geometry: ROIGeometry,
        encoder: MTLRenderCommandEncoder,
        config: ROIRenderConfig,
        outputTexture: MTLTexture
    ) {
        // Choose pipeline based on geometric type
        let pipeline: MTLRenderPipelineState?
        switch geometry.geometricType {
        case .point:
            pipeline = pointPipeline
        case .openPlanar, .openNonplanar:
            pipeline = outlinePipeline
        case .closedPlanar, .closedNonplanar:
            pipeline = config.renderMode == .outline ? outlinePipeline : filledPipeline
        }
        
        guard let renderPipeline = pipeline else {
            print("⚠️ No suitable pipeline for ROI geometry type: \(geometry.geometricType)")
            return
        }
        
        // Set pipeline
        encoder.setRenderPipelineState(renderPipeline)
        
        // Create vertex buffer if needed
        let vertexBuffer = createVertexBuffer(for: geometry)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Set uniforms
        let mvpMatrix = matrix_identity_float4x4 // Identity for screen-space rendering
        var uniforms = ROIUniforms(mvpMatrix: mvpMatrix, config: config)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ROIUniforms>.size, index: 1)
        
        // Set ROI-specific parameters with proper texture dimensions
        let textureSize = SIMD2<Float>(
            Float(outputTexture.width),
            Float(outputTexture.height)
        )
        var params = ROIRenderParams(
            roi: geometry,
            config: config,
            textureSize: textureSize
        )
        encoder.setFragmentBytes(&params, length: MemoryLayout<ROIRenderParams>.size, index: 0)
        
        // Draw geometry using supported Metal primitive types
        let vertexCount = geometry.vertices.count
        if geometry.geometricType.shouldFill {
            // Draw filled contour (use triangle strip instead of fan)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        } else {
            // Draw line strip
            encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: vertexCount)
        }
    }
    
    // MARK: - Geometry Conversion
    
    private func getContoursForSlice(
        roi: ROIStructure,
        plane: MPRPlane,
        slicePosition: Float,
        tolerance: Float
    ) -> [ROIContour] {
        return roi.contours.filter { contour in
            contour.intersectsSlice(slicePosition, plane: plane, tolerance: tolerance)
        }
    }
    
    private func convertContourToVertices(
        contour: ROIContour,
        plane: MPRPlane,
        volumeOrigin: SIMD3<Float>,
        volumeSpacing: SIMD3<Float>,
        color: SIMD3<Float>
    ) -> [ROIVertex] {
        
        let projectedPoints = contour.projectToPlane(plane, volumeOrigin: volumeOrigin, volumeSpacing: volumeSpacing)
        
        return projectedPoints.map { point in
            // Convert to normalized device coordinates [-1, 1]
            let ndcPoint = SIMD2<Float>(
                (point.x / 512.0) * 2.0 - 1.0,  // Assuming 512x512 texture
                (point.y / 512.0) * 2.0 - 1.0
            )
            
            return ROIVertex(
                position: ndcPoint,
                color: SIMD4<Float>(color.x, color.y, color.z, 1.0)
            )
        }
    }
    
    private func createVertexBuffer(for geometry: ROIGeometry) -> MTLBuffer? {
        // Check cache first
        if let cachedBuffer = vertexBuffers[geometry.roiNumber] {
            return cachedBuffer
        }
        
        // Create new buffer
        let bufferSize = geometry.vertices.count * MemoryLayout<ROIVertex>.size
        guard let buffer = device.makeBuffer(
            bytes: geometry.vertices,
            length: bufferSize,
            options: .storageModeShared
        ) else {
            return nil
        }
        
        // Cache for reuse
        vertexBuffers[geometry.roiNumber] = buffer
        return buffer
    }
    
    // MARK: - Pipeline Setup
    
    private func setupRenderPipelines() throws {
        // Create vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        
        // Position attribute
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        // Color attribute
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.size
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        // Buffer layout
        vertexDescriptor.layouts[0].stride = MemoryLayout<ROIVertex>.size
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create pipelines
        try createFilledPipeline(vertexDescriptor: vertexDescriptor)
        try createOutlinePipeline(vertexDescriptor: vertexDescriptor)
        try createPointPipeline(vertexDescriptor: vertexDescriptor)
        
        print("✅ ROI render pipelines created successfully")
    }
    
    private func createFilledPipeline(vertexDescriptor: MTLVertexDescriptor) throws {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.vertexFunction = library.makeFunction(name: "roi_vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "roi_filled_fragment")
        
        // Enable blending for transparency
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        filledPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private func createOutlinePipeline(vertexDescriptor: MTLVertexDescriptor) throws {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.vertexFunction = library.makeFunction(name: "roi_vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "roi_outline_fragment")
        
        // Enable blending
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        outlinePipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private func createPointPipeline(vertexDescriptor: MTLVertexDescriptor) throws {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.vertexFunction = library.makeFunction(name: "roi_vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "roi_point_fragment")
        
        // Enable blending
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        pointPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    // MARK: - Utility Methods
    
    private func copyTexture(from source: MTLTexture, to destination: MTLTexture, completion: @escaping (Bool) -> Void) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            completion(false)
            return
        }
        
        blitEncoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: destination,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        
        blitEncoder.endEncoding()
        
        commandBuffer.addCompletedHandler { _ in
            completion(true)
        }
        commandBuffer.commit()
    }
    
    // MARK: - Cache Management
    
    public func clearCache() {
        vertexBuffers.removeAll()
        indexBuffers.removeAll()
        print("🗑️ ROI renderer cache cleared")
    }
    
    public func getCacheStats() -> String {
        return """
        🎨 ROI Renderer Cache:
           📐 Vertex buffers: \(vertexBuffers.count)
           📊 Index buffers: \(indexBuffers.count)
        """
    }
}

// MARK: - Supporting Data Structures

public struct ROIVertex {
    public let position: SIMD2<Float>
    public let color: SIMD4<Float>
    
    public init(position: SIMD2<Float>, color: SIMD4<Float>) {
        self.position = position
        self.color = color
    }
}

public struct ROIGeometry {
    public let roiNumber: Int
    public let roiName: String
    public let vertices: [ROIVertex]
    public let geometricType: ContourGeometricType
    public let color: SIMD3<Float>
    public let opacity: Float
    
    public init(roiNumber: Int, roiName: String, vertices: [ROIVertex], geometricType: ContourGeometricType, color: SIMD3<Float>, opacity: Float) {
        self.roiNumber = roiNumber
        self.roiName = roiName
        self.vertices = vertices
        self.geometricType = geometricType
        self.color = color
        self.opacity = opacity
    }
}

// MARK: - Error Handling

public enum MetalROIError: Error, LocalizedError {
    case deviceNotAvailable
    case shaderCompilationFailed
    case pipelineCreationFailed
    case geometryProcessingFailed
    
    public var errorDescription: String? {
        switch self {
        case .deviceNotAvailable:
            return "Metal device not available for ROI rendering"
        case .shaderCompilationFailed:
            return "Failed to compile ROI shaders"
        case .pipelineCreationFailed:
            return "Failed to create ROI render pipeline"
        case .geometryProcessingFailed:
            return "Failed to process ROI geometry"
        }
    }
}
