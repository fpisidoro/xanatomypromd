import SwiftUI
import MetalKit
import Metal

// MARK: - Working Metal DICOM Image View (Fixed to use correct MetalVolumeRenderer API)
struct MetalDICOMImageView: UIViewRepresentable {
    let viewModel: DICOMViewerViewModel
    let currentSlice: Int
    let currentPlane: MPRPlane
    let windowingPreset: CTWindowPresets.WindowLevel
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.drawableSize = CGSize(width: 512, height: 512)
        mtkView.framebufferOnly = false
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateParameters(
            viewModel: viewModel,
            currentSlice: currentSlice,
            currentPlane: currentPlane,
            windowingPreset: windowingPreset
        )
        uiView.setNeedsDisplay()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        private var volumeRenderer: MetalVolumeRenderer?
        
        // Current parameters
        private var currentViewModel: DICOMViewerViewModel?
        private var currentSlice: Int = 0
        private var currentPlane: MPRPlane = .axial
        private var currentWindowingPreset: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
        private var cachedTexture: MTLTexture?
        private var cacheKey: String = ""
        
        override init() {
            super.init()
            setupRenderer()
        }
        
        private func setupRenderer() {
            do {
                volumeRenderer = try MetalVolumeRenderer()
                print("✅ MetalDICOMImageView renderer initialized")
            } catch {
                print("❌ Failed to initialize MetalDICOMImageView renderer: \(error)")
            }
        }
        
        func updateParameters(
            viewModel: DICOMViewerViewModel,
            currentSlice: Int,
            currentPlane: MPRPlane,
            windowingPreset: CTWindowPresets.WindowLevel
        ) {
            self.currentViewModel = viewModel
            self.currentSlice = currentSlice
            self.currentPlane = currentPlane
            self.currentWindowingPreset = windowingPreset
            
            // Load volume data if available (async call to main actor)
            Task { @MainActor in
                if let volumeData = viewModel.getVolumeData(), let volumeRenderer = volumeRenderer {
                    do {
                        try volumeRenderer.loadVolume(volumeData)
                    } catch {
                        print("❌ Failed to load volume: \(error)")
                    }
                }
            }
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle size changes
        }
        
        func draw(in view: MTKView) {
            guard let device = view.device,
                  let commandQueue = device.makeCommandQueue(),
                  let drawable = view.currentDrawable,
                  let volumeRenderer = volumeRenderer else {
                return
            }
            
            // Create cache key for texture caching
            let newCacheKey = "\(currentPlane.rawValue)-\(currentSlice)-\(currentWindowingPreset.name)"
            
            // Generate new MPR slice if cache key changed
            if cacheKey != newCacheKey {
                cacheKey = newCacheKey
                
                let normalizedSliceIndex = Float(currentSlice) / Float(getMaxSlicesForPlane())
                
                let config = MetalVolumeRenderer.MPRConfig(
                    plane: currentPlane,
                    sliceIndex: normalizedSliceIndex,
                    windowCenter: currentWindowingPreset.center,
                    windowWidth: currentWindowingPreset.width
                )
                
                // Generate MPR slice using the correct API
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
                // Show black screen while loading
                return 
            }
            
            let commandBuffer = commandQueue.makeCommandBuffer()
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
            
            guard let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
            
            // Simple texture display (already processed by MetalVolumeRenderer)
            displayTexture(mprTexture, renderEncoder: renderEncoder, device: device)
            
            renderEncoder.endEncoding()
            commandBuffer?.present(drawable)
            commandBuffer?.commit()
        }
        
        private func displayTexture(_ texture: MTLTexture, renderEncoder: MTLRenderCommandEncoder, device: MTLDevice) {
            // Create simple display pipeline
            guard let library = device.makeDefaultLibrary(),
                  let vertexFunction = library.makeFunction(name: "vertex_main"),
                  let fragmentFunction = library.makeFunction(name: "fragment_display_texture") else {
                print("❌ Failed to find display shaders")
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            guard let renderPipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
                print("❌ Failed to create display pipeline state")
                return
            }
            
            // Create full-screen quad vertices
            let quadVertices: [Float] = [
                // Positions (NDC)    // Texture coordinates
                -1.0, -1.0, 0.0, 1.0,  // Bottom left
                 1.0, -1.0, 1.0, 1.0,  // Bottom right
                -1.0,  1.0, 0.0, 0.0,  // Top left
                 1.0,  1.0, 1.0, 0.0   // Top right
            ]
            
            guard let vertexBuffer = device.makeBuffer(bytes: quadVertices, 
                                                      length: quadVertices.count * MemoryLayout<Float>.size,
                                                      options: []) else {
                print("❌ Failed to create vertex buffer")
                return
            }
            
            // Set up render state and display the texture
            renderEncoder.setRenderPipelineState(renderPipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentTexture(texture, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        
        private func getMaxSlicesForPlane() -> Int {
            // Use cached volume data from renderer instead of calling main actor
            guard let volumeData = volumeRenderer?.volumeData else {
                return 53 // Fallback
            }
            
            switch currentPlane {
            case .axial:
                return volumeData.dimensions.z
            case .sagittal:
                return volumeData.dimensions.x
            case .coronal:
                return volumeData.dimensions.y
            }
        }
    }
}
