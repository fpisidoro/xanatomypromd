import SwiftUI
import MetalKit
import Metal

// MARK: - Simplified Working Metal DICOM Image View
struct MetalDICOMImageView: UIViewRepresentable {
    let viewModel: DICOMViewerViewModel
    let currentSlice: Int
    let currentPlane: MPRPlane
    let windowingPreset: CTWindowLevel
    
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
        private var crosshairManager: CrosshairManager?
        
        // Current parameters
        private var currentViewModel: DICOMViewerViewModel?
        private var currentSlice: Int = 0
        private var currentPlane: MPRPlane = .axial
        private var currentWindowingPreset: CTWindowLevel = CTWindowLevel.softTissue
        
        override init() {
            super.init()
            setupRenderer()
        }
        
        private func setupRenderer() {
            do {
                volumeRenderer = try MetalVolumeRenderer()
                // Initialize crosshair manager without main actor requirement
                Task { @MainActor in
                    crosshairManager = CrosshairManager()
                }
            } catch {
                // Initialization failed - renderer will be nil
            }
        }
        
        func updateParameters(
            viewModel: DICOMViewerViewModel,
            currentSlice: Int,
            currentPlane: MPRPlane,
            windowingPreset: CTWindowLevel
        ) {
            self.currentViewModel = viewModel
            self.currentSlice = currentSlice
            self.currentPlane = currentPlane
            self.currentWindowingPreset = windowingPreset
            
            // Load volume data if available
            Task { @MainActor in
                if let volumeData = viewModel.getVolumeData(), let volumeRenderer = volumeRenderer {
                    do {
                        try volumeRenderer.loadVolume(volumeData)
                    } catch {
                        // Volume loading failed
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
                  let drawable = view.currentDrawable as? CAMetalDrawable else {
                return
            }
            
            // Generate MPR slice
            guard let volumeRenderer = volumeRenderer else {
                // Clear to black if no renderer
                clearView(drawable: drawable, commandQueue: commandQueue)
                return
            }
            
            let normalizedSliceIndex = Float(currentSlice) / Float(getMaxSlicesForPlane())
            
            let config = MetalVolumeRenderer.MPRConfig(
                plane: currentPlane,
                sliceIndex: normalizedSliceIndex,
                windowCenter: currentWindowingPreset.center,
                windowWidth: currentWindowingPreset.width
            )
            
            // Generate MPR slice and display it
            volumeRenderer.generateMPRSlice(config: config) { [weak self] mprTexture in
                guard let self = self, let mprTexture = mprTexture else {
                    self?.clearView(drawable: drawable, commandQueue: commandQueue)
                    return
                }
                
                // Display the MPR texture with crosshairs
                self.displayMPRWithCrosshairs(
                    mprTexture: mprTexture,
                    drawable: drawable,
                    commandQueue: commandQueue,
                    device: device
                )
            }
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
        
        private func displayMPRWithCrosshairs(
            mprTexture: MTLTexture,
            drawable: CAMetalDrawable,
            commandQueue: MTLCommandQueue,
            device: MTLDevice
        ) {
            let commandBuffer = commandQueue.makeCommandBuffer()
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
            
            guard let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { 
                commandBuffer?.present(drawable)
                commandBuffer?.commit()
                return 
            }
            
            // Display the MPR texture
            displayTexture(mprTexture, renderEncoder: renderEncoder, device: device)
            
            // Draw crosshairs on top
            if let crosshairManager = self.crosshairManager {
                crosshairManager.drawCrosshairs(
                    renderEncoder: renderEncoder, 
                    device: device, 
                    position: SIMD2<Float>(0.5, 0.5), 
                    viewSize: MTLSize(width: drawable.texture.width, height: drawable.texture.height, depth: 1)
                )
            }
            
            renderEncoder.endEncoding()
            commandBuffer?.present(drawable)
            commandBuffer?.commit()
        }
        
        private func displayTexture(_ texture: MTLTexture, renderEncoder: MTLRenderCommandEncoder, device: MTLDevice) {
            // Create simple display pipeline
            guard let library = device.makeDefaultLibrary(),
                  let vertexFunction = library.makeFunction(name: "vertex_simple"),
                  let fragmentFunction = library.makeFunction(name: "fragment_simple") else {
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            guard let renderPipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
                return
            }
            
            // Create full-screen quad vertices (simple format)
            let quadVertices: [Float] = [
                // Positions        // Texture coordinates
                -1.0, -1.0,        0.0, 1.0,  // Bottom left
                 1.0, -1.0,        1.0, 1.0,  // Bottom right
                -1.0,  1.0,        0.0, 0.0,  // Top left
                 1.0,  1.0,        1.0, 0.0   // Top right
            ]
            
            guard let vertexBuffer = device.makeBuffer(bytes: quadVertices, 
                                                      length: quadVertices.count * MemoryLayout<Float>.size,
                                                      options: []) else {
                return
            }
            
            // Set up render state and display the texture
            renderEncoder.setRenderPipelineState(renderPipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentTexture(texture, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        
        private func drawCrosshairs(renderEncoder: MTLRenderCommandEncoder, device: MTLDevice, viewSize: MTLSize) {
            guard let crosshairManager = crosshairManager else { return }
            
            // Calculate crosshair position based on current slice and plane
            let normalizedPosition = SIMD2<Float>(0.5, 0.5) // Center for now
            
            // Draw the crosshairs
            crosshairManager.drawCrosshairs(
                renderEncoder: renderEncoder,
                device: device,
                position: normalizedPosition,
                viewSize: viewSize
            )
        }
        
        private func getMaxSlicesForPlane() -> Int {
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

