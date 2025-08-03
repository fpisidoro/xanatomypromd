import SwiftUI
import MetalKit
import Metal

// MARK: - Layer 1: CT Display Layer (FIXED - Aspect Ratio Preserving)
// AUTHORITATIVE layer that renders DICOM slices in true patient coordinates
// FIXED: Now maintains correct aspect ratio in ALL orientations and screen sizes

struct CTDisplayLayer: UIViewRepresentable {
    
    // MARK: - Configuration
    
    /// The authoritative coordinate system (shared with all layers)
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    
    /// Current anatomical plane to display
    let plane: MPRPlane
    
    /// CT windowing settings
    let windowLevel: CTWindowLevel
    
    /// Volume data source
    let volumeData: VolumeData?
    
    // MARK: - UIViewRepresentable Implementation
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.framebufferOnly = false
        mtkView.backgroundColor = UIColor.black
        
        // FIXED: Remove contentMode - we handle aspect ratio in Metal rendering
        // This allows the MTKView to fill the SwiftUI frame while we control
        // the actual image aspect ratio in the shaders
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateRenderingParameters(
            coordinateSystem: coordinateSystem,
            plane: plane,
            windowLevel: windowLevel,
            volumeData: volumeData
        )
        uiView.setNeedsDisplay()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - CT Rendering Coordinator (FIXED - Aspect Ratio Preserving)
    
    class Coordinator: NSObject, MTKViewDelegate {
        
        private var volumeRenderer: MetalVolumeRenderer?
        private var displayPipelineState: MTLRenderPipelineState?
        
        // FIXED: Dynamic vertex buffer for aspect-ratio preserving quads
        private var vertexBuffer: MTLBuffer?
        private var currentViewSize: CGSize = .zero
        private var currentTextureSize: CGSize = .zero
        
        // Current rendering state
        private var currentCoordinateSystem: DICOMCoordinateSystem?
        private var currentPlane: MPRPlane = .axial
        private var currentWindowLevel: CTWindowLevel = CTWindowLevel.softTissue
        private var currentVolumeData: VolumeData?
        
        // Texture caching for performance
        private var cachedTexture: MTLTexture?
        private var cacheKey: String = ""
        
        override init() {
            super.init()
            setupRenderer()
            setupDisplayPipeline()
        }
        
        private func setupRenderer() {
            do {
                volumeRenderer = try MetalVolumeRenderer()
                print("✅ CT Display Layer: Volume renderer initialized")
            } catch {
                print("❌ CT Display Layer: Failed to initialize volume renderer: \(error)")
            }
        }
        
        private func setupDisplayPipeline() {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let library = device.makeDefaultLibrary() else {
                print("❌ CT Display Layer: Failed to create Metal device/library")
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_simple")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_simple")
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            do {
                displayPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("✅ CT Display Layer: Display pipeline created")
            } catch {
                print("❌ CT Display Layer: Failed to create display pipeline: \(error)")
            }
        }
        
        // FIXED: Create aspect-ratio preserving quad vertices
        private func createAspectRatioPreservingQuad(
            textureSize: CGSize,
            viewSize: CGSize,
            device: MTLDevice
        ) {
            // Calculate aspect ratios
            let textureAspect = Float(textureSize.width / textureSize.height)
            let viewAspect = Float(viewSize.width / viewSize.height)
            
            // Calculate proper quad size to maintain aspect ratio
            let quadSize: (width: Float, height: Float)
            
            if textureAspect > viewAspect {
                // Texture is wider than view - letterbox top/bottom
                quadSize = (1.0, viewAspect / textureAspect)
                print("🔍 CT Aspect: Letterboxing top/bottom - textureAspect=\(String(format: "%.2f", textureAspect)), viewAspect=\(String(format: "%.2f", viewAspect))")
            } else {
                // Texture is taller than view - letterbox left/right
                quadSize = (textureAspect / viewAspect, 1.0)
                print("🔍 CT Aspect: Letterboxing left/right - textureAspect=\(String(format: "%.2f", textureAspect)), viewAspect=\(String(format: "%.2f", viewAspect))")
            }
            
            // Create vertices for properly sized quad (not full-screen)
            let quadVertices: [Float] = [
                // Positions                                    // Texture coordinates
                -quadSize.width, -quadSize.height,             0.0, 1.0,  // Bottom left
                 quadSize.width, -quadSize.height,             1.0, 1.0,  // Bottom right
                -quadSize.width,  quadSize.height,             0.0, 0.0,  // Top left
                 quadSize.width,  quadSize.height,             1.0, 0.0   // Top right
            ]
            
            print("🔍 CT Aspect: Quad size = \(String(format: "%.3f", quadSize.width))×\(String(format: "%.3f", quadSize.height))")
            print("🔍 CT Aspect: Texture = \(Int(textureSize.width))×\(Int(textureSize.height)), View = \(Int(viewSize.width))×\(Int(viewSize.height))")
            
            vertexBuffer = device.makeBuffer(
                bytes: quadVertices,
                length: quadVertices.count * MemoryLayout<Float>.size,
                options: []
            )
        }
        
        func updateRenderingParameters(
            coordinateSystem: DICOMCoordinateSystem,
            plane: MPRPlane,
            windowLevel: CTWindowLevel,
            volumeData: VolumeData?
        ) {
            print("🔍 CT Display: updateRenderingParameters called")
            print("   Plane: \(plane), VolumeData: \(volumeData != nil ? "present" : "nil")")
            
            self.currentCoordinateSystem = coordinateSystem
            self.currentPlane = plane
            self.currentWindowLevel = windowLevel
            
            // Load volume data into renderer if provided
            if let volumeData = volumeData {
                if currentVolumeData == nil {
                    print("🔍 CT Display: Loading volume data...")
                    do {
                        if volumeRenderer == nil {
                            volumeRenderer = try MetalVolumeRenderer()
                        }
                        try volumeRenderer?.loadVolume(volumeData)
                        self.currentVolumeData = volumeData
                        print("✅ CT Display: Volume data loaded successfully")
                    } catch {
                        print("❌ CT Display: Failed to load volume data: \(error)")
                    }
                } else {
                    self.currentVolumeData = volumeData
                }
            }
            
            // Clear cache to force regeneration
            cachedTexture = nil
            cacheKey = ""
            
            print("🔍 CT Display: Parameters updated, cache cleared")
        }
        
        // MARK: - MTKViewDelegate
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            print("🔍 CT Aspect: Drawable size changed to \(Int(size.width))×\(Int(size.height))")
            currentViewSize = size
            
            // Force vertex buffer regeneration on next draw
            vertexBuffer = nil
        }
        
        private func getImageDimensions(for plane: MPRPlane, volumeData: VolumeData) -> (width: Int, height: Int) {
            let dims = volumeData.dimensions
            
            switch plane {
            case .axial:
                return (dims.x, dims.y)  // 512x512
            case .sagittal:
                return (dims.y, dims.z)  // 512x53
            case .coronal:
                return (dims.x, dims.z)  // 512x53
            }
        }
        
        func draw(in view: MTKView) {
            guard let device = view.device,
                  let commandQueue = device.makeCommandQueue(),
                  let drawable = view.currentDrawable else {
                return
            }
            
            // Update current view size
            currentViewSize = view.drawableSize
            
            // Get current slice from coordinate system
            guard let coordinateSystem = currentCoordinateSystem else {
                clearView(drawable: drawable, commandQueue: commandQueue)
                return
            }
            
            let currentSliceIndex = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
            
            // Create cache key for texture caching
            let newCacheKey = "\(currentPlane.rawValue)-\(currentSliceIndex)-\(currentWindowLevel.name)"
            
            // Generate new MPR slice if cache key changed
            if cacheKey != newCacheKey {
                cacheKey = newCacheKey
                
                guard let volumeRenderer = volumeRenderer,
                      let volumeData = currentVolumeData else {
                    displayLoadingState(drawable: drawable, commandQueue: commandQueue)
                    return
                }
                
                // Calculate normalized slice position using coordinate system
                let maxSlices = coordinateSystem.getMaxSlices(for: currentPlane)
                let normalizedSliceIndex = Float(currentSliceIndex) / Float(maxSlices - 1)
                
                let config = MetalVolumeRenderer.MPRConfig(
                    plane: currentPlane,
                    sliceIndex: normalizedSliceIndex,
                    windowCenter: currentWindowLevel.center,
                    windowWidth: currentWindowLevel.width
                )
                
                // Generate MPR slice with hardware acceleration
                volumeRenderer.generateMPRSlice(config: config) { [weak self] mprTexture in
                    guard let self = self else { return }
                    self.cachedTexture = mprTexture
                    
                    // FIXED: Update current texture size for aspect ratio calculation
                    if let texture = mprTexture {
                        self.currentTextureSize = CGSize(width: texture.width, height: texture.height)
                        print("🔍 CT Aspect: New texture size = \(texture.width)×\(texture.height)")
                    }
                    
                    // Trigger redraw on main thread
                    DispatchQueue.main.async {
                        view.setNeedsDisplay()
                    }
                }
                return
            }
            
            // Display cached texture if available
            guard let mprTexture = cachedTexture else {
                displayLoadingState(drawable: drawable, commandQueue: commandQueue)
                return
            }
            
            // FIXED: Update texture size and regenerate vertex buffer if needed
            let textureSize = CGSize(width: mprTexture.width, height: mprTexture.height)
            if currentTextureSize != textureSize || vertexBuffer == nil {
                currentTextureSize = textureSize
                createAspectRatioPreservingQuad(
                    textureSize: textureSize,
                    viewSize: currentViewSize,
                    device: device
                )
            }
            
            displayTexture(mprTexture, drawable: drawable, commandQueue: commandQueue)
        }
        
        // MARK: - Rendering Methods (FIXED - Using Dynamic Vertex Buffer)
        
        private func displayTexture(_ texture: MTLTexture, drawable: CAMetalDrawable, commandQueue: MTLCommandQueue) {
            let commandBuffer = commandQueue.makeCommandBuffer()
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
            
            guard let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
                  let pipelineState = displayPipelineState,
                  let vertexBuffer = vertexBuffer else {  // FIXED: Use dynamic vertex buffer
                commandBuffer?.present(drawable)
                commandBuffer?.commit()
                return
            }
            
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentTexture(texture, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.endEncoding()
            commandBuffer?.present(drawable)
            commandBuffer?.commit()
        }
        
        private func displayLoadingState(drawable: CAMetalDrawable, commandQueue: MTLCommandQueue) {
            let commandBuffer = commandQueue.makeCommandBuffer()
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            
            if let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderEncoder.endEncoding()
            }
            commandBuffer?.present(drawable)
            commandBuffer?.commit()
        }
        
        private func clearView(drawable: CAMetalDrawable, commandQueue: MTLCommandQueue) {
            let commandBuffer = commandQueue.makeCommandBuffer()
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
            
            if let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderEncoder.endEncoding()
            }
            commandBuffer?.present(drawable)
            commandBuffer?.commit()
        }
    }
}
