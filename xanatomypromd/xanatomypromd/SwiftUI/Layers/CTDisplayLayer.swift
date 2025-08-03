import SwiftUI
import MetalKit
import Metal

// MARK: - Layer 1: CT Display Layer
// AUTHORITATIVE layer that renders DICOM slices in true patient coordinates
// All other layers align to THIS coordinate system

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
        mtkView.drawableSize = CGSize(width: 512, height: 512)
        mtkView.framebufferOnly = false
        mtkView.backgroundColor = UIColor.black
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
    
    // MARK: - CT Rendering Coordinator
    
    class Coordinator: NSObject, MTKViewDelegate {
        
        private var volumeRenderer: MetalVolumeRenderer?
        private var displayPipelineState: MTLRenderPipelineState?
        private var vertexBuffer: MTLBuffer?
        
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
            
            // Create full-screen quad vertices
            let quadVertices: [Float] = [
                // Positions        // Texture coordinates
                -1.0, -1.0,        0.0, 1.0,  // Bottom left
                 1.0, -1.0,        1.0, 1.0,  // Bottom right
                -1.0,  1.0,        0.0, 0.0,  // Top left
                 1.0,  1.0,        1.0, 0.0   // Top right
            ]
            
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
            // Handle size changes if needed
        }
        
        func draw(in view: MTKView) {
            guard let device = view.device,
                  let commandQueue = device.makeCommandQueue(),
                  let drawable = view.currentDrawable else {
                return
            }
            
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
            
            displayTexture(mprTexture, drawable: drawable, commandQueue: commandQueue)
        }
        
        // MARK: - Rendering Methods
        
        private func displayTexture(_ texture: MTLTexture, drawable: CAMetalDrawable, commandQueue: MTLCommandQueue) {
            let commandBuffer = commandQueue.makeCommandBuffer()
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
            
            guard let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
                  let pipelineState = displayPipelineState,
                  let vertexBuffer = vertexBuffer else {
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
