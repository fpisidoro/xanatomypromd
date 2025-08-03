import SwiftUI
import MetalKit
import Metal

// MARK: - Restored Working Metal DICOM Image View with Crosshairs
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
        
        // Current parameters
        private var currentViewModel: DICOMViewerViewModel?
        private var currentSlice: Int = 0
        private var currentPlane: MPRPlane = .axial
        private var currentWindowingPreset: CTWindowLevel = CTWindowLevel.softTissue
        private var cachedTexture: MTLTexture?
        private var cacheKey: String = ""
        
        // Metal pipeline for display
        private var displayPipelineState: MTLRenderPipelineState?
        private var vertexBuffer: MTLBuffer?
        private var aspectRatioBuffer: MTLBuffer?
        
        override init() {
            super.init()
            setupRenderer()
            setupDisplayPipeline()
        }
        
        private func setupRenderer() {
            do {
                volumeRenderer = try MetalVolumeRenderer()
            } catch {
                // Initialization failed - renderer will be nil
            }
        }
        
        private func setupDisplayPipeline() {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let library = device.makeDefaultLibrary() else {
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_simple")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_simple")
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            do {
                displayPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                // Pipeline creation failed
            }
            
            // Create full-screen quad vertices
            let quadVertices: [Float] = [
                // Positions        // Texture coordinates
                -1.0, -1.0,        0.0, 1.0,  // Bottom left
                 1.0, -1.0,        1.0, 1.0,  // Bottom right
                -1.0,  1.0,        0.0, 0.0,  // Top left
                 1.0,  1.0,        1.0, 0.0   // Top right
            ]
            
            vertexBuffer = device.makeBuffer(bytes: quadVertices, 
                                           length: quadVertices.count * MemoryLayout<Float>.size,
                                           options: [])
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
            if let volumeData = viewModel.getVolumeData(), let volumeRenderer = volumeRenderer {
                do {
                    try volumeRenderer.loadVolume(volumeData)
                } catch {
                    // Volume loading failed
                }
            }
            
            // Update aspect ratio for current plane
            updateAspectRatio()
        }
        
        private func updateAspectRatio() {
            guard let volumeData = volumeRenderer?.volumeData,
                  let device = MTLCreateSystemDefaultDevice() else {
                return
            }
            
            // Calculate correct aspect ratio using physical spacing
            let dimensions = volumeData.dimensions
            let spacing = volumeData.spacing
            
            let aspectRatio: Float
            switch currentPlane {
            case .axial:
                // XY plane: width vs height in mm
                let widthMM = Float(dimensions.x) * spacing.x
                let heightMM = Float(dimensions.y) * spacing.y
                aspectRatio = widthMM / heightMM
                
            case .sagittal:
                // YZ plane: anterior-posterior vs superior-inferior in mm
                let widthMM = Float(dimensions.y) * spacing.y
                let heightMM = Float(dimensions.z) * spacing.z
                aspectRatio = widthMM / heightMM
                
            case .coronal:
                // XZ plane: left-right vs superior-inferior in mm
                let widthMM = Float(dimensions.x) * spacing.x
                let heightMM = Float(dimensions.z) * spacing.z
                aspectRatio = widthMM / heightMM
            }
            
            // Apply aspect ratio correction to maintain proper proportions
            let aspectUniforms = AspectRatioUniforms(
                scaleX: aspectRatio > 1.0 ? 1.0 : aspectRatio,
                scaleY: aspectRatio > 1.0 ? 1.0 / aspectRatio : 1.0
            )
            
            aspectRatioBuffer = device.makeBuffer(
                bytes: [aspectUniforms],
                length: MemoryLayout<AspectRatioUniforms>.size,
                options: []
            )
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
            
            // Create cache key for texture caching
            let newCacheKey = "\(currentPlane.rawValue)-\(currentSlice)-\(currentWindowingPreset.name)"
            
            // Generate new MPR slice if cache key changed
            if cacheKey != newCacheKey {
                cacheKey = newCacheKey
                
                guard let volumeRenderer = volumeRenderer else {
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
                
                // Generate MPR slice without excessive logging
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
                clearView(drawable: drawable, commandQueue: commandQueue)
                return 
            }
            
            displayTexture(mprTexture, drawable: drawable, commandQueue: commandQueue, device: device)
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
        
        private func displayTexture(_ texture: MTLTexture, drawable: CAMetalDrawable, commandQueue: MTLCommandQueue, device: MTLDevice) {
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
            
            // Apply aspect ratio correction if available
            if let aspectBuffer = aspectRatioBuffer {
                renderEncoder.setVertexBuffer(aspectBuffer, offset: 0, index: 1)
            }
            
            renderEncoder.setFragmentTexture(texture, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.endEncoding()
            commandBuffer?.present(drawable)
            commandBuffer?.commit()
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
