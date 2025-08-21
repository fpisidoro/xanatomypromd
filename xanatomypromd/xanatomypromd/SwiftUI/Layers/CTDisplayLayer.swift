import SwiftUI
import MetalKit
import Metal

// MARK: - Layer 1: CT Display Layer (MEDICAL-ACCURATE)
// AUTHORITATIVE layer that renders DICOM slices with EXACT physical spacing
// MEDICAL PRINCIPLE: Accuracy > Screen Aesthetics - Never compromise DICOM data

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
    
    /// Shared viewing state for quality control
    let sharedState: SharedViewingState?
    
    // REMOVED: scrollVelocity, isViewScrolling (priority system deleted)
    
    // MARK: - UIViewRepresentable Implementation
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.framebufferOnly = false
        mtkView.backgroundColor = UIColor.black
        
        // ✅ FIX: Start paused and enable manual control
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        mtkView.preferredFramesPerSecond = 30  // Only when actively rendering
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        Task { @MainActor in
            context.coordinator.updateRenderingParameters(
                coordinateSystem: coordinateSystem,
                plane: plane,
                windowLevel: windowLevel,
                volumeData: volumeData,
                sharedState: sharedState
            )
            
            // ✅ FIX: Unpause briefly for render, then re-pause
            uiView.isPaused = false
            uiView.setNeedsDisplay()
            
            // Re-pause after a very short delay to ensure render completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { // One frame at 60fps
                uiView.isPaused = true
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Medical-Accurate CT Rendering Coordinator
    
    class Coordinator: NSObject, MTKViewDelegate {
        
        // Individual MetalVolumeRenderer per view (restored)
        private var volumeRenderer: MetalVolumeRenderer?
        private var displayPipelineState: MTLRenderPipelineState?
        
        // MEDICAL-ACCURATE: Vertex buffer with proper physical spacing
        private var vertexBuffer: MTLBuffer?
        private var lastViewSize: CGSize = .zero
        private var lastTextureSize: CGSize = .zero
        private var lastPlane: MPRPlane?
        private var lastSpacing: SIMD3<Float>?
        
        // Current rendering state
        private var currentCoordinateSystem: DICOMCoordinateSystem?
        private var currentPlane: MPRPlane = .axial
        private var currentWindowLevel: CTWindowLevel = CTWindowLevel.softTissue
        private var currentVolumeData: VolumeData?
        
        // Texture caching for performance
        private var cachedTexture: MTLTexture?
        private var cacheKey: String = ""
        
        // SIMPLIFIED: Always use full quality
        private let renderQuality: MetalVolumeRenderer.RenderQuality = .full
        
        // ✅ NEW: Track if we need to render
        private var needsRender: Bool = false
        private var lastRenderedCacheKey: String = ""
        
        override init() {
            super.init()
            setupRenderer()
            setupDisplayPipeline()
        }
        
        private func setupRenderer() {
            do {
                volumeRenderer = try MetalVolumeRenderer()
                print("✅ Individual MetalVolumeRenderer created for view")
            } catch {
                print("❌ Failed to create MetalVolumeRenderer: \(error)")
            }
        }
        
        private func setupDisplayPipeline() {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let library = device.makeDefaultLibrary() else {
                print("❌ CT Medical Display: Failed to create Metal device/library")
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_simple")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_simple")
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            do {
                displayPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("✅ CT Medical Display: Display pipeline created")
            } catch {
                print("❌ CT Medical Display: Failed to create display pipeline: \(error)")
            }
        }
        
        // MEDICAL-ACCURATE: Create quad using PHYSICAL DICOM spacing
        private func createMedicalAccurateQuad(
            textureSize: CGSize,
            viewSize: CGSize,
            plane: MPRPlane,
            dicomSpacing: SIMD3<Float>,
            device: MTLDevice
        ) {
            // Calculate PHYSICAL dimensions using DICOM spacing
            let physicalDimensions = calculatePhysicalDimensions(
                textureSize: textureSize,
                plane: plane,
                spacing: dicomSpacing
            )
            
            // Calculate aspect ratio from PHYSICAL dimensions (not pixels)
            let physicalAspect = physicalDimensions.width / physicalDimensions.height
            let viewAspect = Float(viewSize.width / viewSize.height)
            
            print("🏥 MEDICAL ACCURACY:")
            print("   📐 Texture pixels: \(Int(textureSize.width))×\(Int(textureSize.height))")
            print("   📏 Physical size: \(String(format: "%.1f", physicalDimensions.width))mm × \(String(format: "%.1f", physicalDimensions.height))mm")
            print("   📊 Physical aspect: \(String(format: "%.3f", physicalAspect))")
            print("   📱 View aspect: \(String(format: "%.3f", viewAspect))")
            
            // Calculate proper quad size to maintain MEDICAL accuracy
            let quadSize: (width: Float, height: Float)
            
            if physicalAspect > viewAspect {
                // Image is physically wider - letterbox top/bottom
                quadSize = (1.0, viewAspect / physicalAspect)
                print("   📱 Medical Letterbox: TOP/BOTTOM")
            } else {
                // Image is physically taller - letterbox left/right
                quadSize = (physicalAspect / viewAspect, 1.0)
                print("   📱 Medical Letterbox: LEFT/RIGHT")
            }
            
            // Create vertices for medically accurate quad
            let quadVertices: [Float] = [
                // Positions                                    // Texture coordinates
                -quadSize.width, -quadSize.height,             0.0, 1.0,  // Bottom left
                 quadSize.width, -quadSize.height,             1.0, 1.0,  // Bottom right
                -quadSize.width,  quadSize.height,             0.0, 0.0,  // Top left
                 quadSize.width,  quadSize.height,             1.0, 0.0   // Top right
            ]
            
            print("   ✅ Medical quad: \(String(format: "%.3f", quadSize.width))×\(String(format: "%.3f", quadSize.height))")
            
            vertexBuffer = device.makeBuffer(
                bytes: quadVertices,
                length: quadVertices.count * MemoryLayout<Float>.size,
                options: []
            )
            
            // Update tracking variables
            lastViewSize = viewSize
            lastTextureSize = textureSize
            lastPlane = plane
            lastSpacing = dicomSpacing
        }
        
        // Calculate physical dimensions using DICOM spacing
        private func calculatePhysicalDimensions(
            textureSize: CGSize,
            plane: MPRPlane,
            spacing: SIMD3<Float>
        ) -> (width: Float, height: Float) {
            
            let pixelWidth = Float(textureSize.width)
            let pixelHeight = Float(textureSize.height)
            
            switch plane {
            case .axial:
                // XY plane: X × Y dimensions
                let physicalWidth = pixelWidth * spacing.x
                let physicalHeight = pixelHeight * spacing.y
                return (physicalWidth, physicalHeight)
                
            case .sagittal:
                // YZ plane: Y × Z dimensions  
                let physicalWidth = pixelWidth * spacing.y
                let physicalHeight = pixelHeight * spacing.z
                return (physicalWidth, physicalHeight)
                
            case .coronal:
                // XZ plane: X × Z dimensions
                let physicalWidth = pixelWidth * spacing.x
                let physicalHeight = pixelHeight * spacing.z
                return (physicalWidth, physicalHeight)
            }
        }
        
        @MainActor
        func updateRenderingParameters(
            coordinateSystem: DICOMCoordinateSystem,
            plane: MPRPlane,
            windowLevel: CTWindowLevel,
            volumeData: VolumeData?,
            sharedState: SharedViewingState?
        ) {
            // Store previous state for smart cache management
            let previousPlane = currentPlane
            let previousWindowLevel = currentWindowLevel
            
            self.currentCoordinateSystem = coordinateSystem
            self.currentPlane = plane
            self.currentWindowLevel = windowLevel
            
            // SMART CACHE: Only clear cache when necessary
            var shouldClearCache = false
            
            if plane != previousPlane {
                shouldClearCache = true
                vertexBuffer = nil
            }
            
            if windowLevel.center != previousWindowLevel.center || windowLevel.width != previousWindowLevel.width {
                shouldClearCache = true
            }
            
            if shouldClearCache {
                cachedTexture = nil
                cacheKey = ""
                needsRender = true  // ✅ NEW: Mark as needing render
            }
            
            // Load volume data into individual renderer if provided
            if let volumeData = volumeData {
                if currentVolumeData == nil {
                    do {
                        try volumeRenderer?.loadVolume(volumeData)
                        self.currentVolumeData = volumeData
                    needsRender = true  // ✅ NEW: Mark as needing render
                    } catch {
                        print("❌ Failed to load volume: \(error)")
                    }
                } else {
                    self.currentVolumeData = volumeData
                }
            }
        }
        
        // MARK: - MTKViewDelegate
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // MEDICAL-CRITICAL: Force vertex buffer regeneration on size changes
            vertexBuffer = nil
            lastViewSize = .zero // Reset to force recalculation
        }
        
        func draw(in view: MTKView) {
            guard let device = view.device,
                  let commandQueue = device.makeCommandQueue(),
                  let drawable = view.currentDrawable else {
                return
            }
            
            let currentViewSize = view.drawableSize
            
            // Get current slice from coordinate system
            guard let coordinateSystem = currentCoordinateSystem else {
                clearView(drawable: drawable, commandQueue: commandQueue)
                // ✅ FIX: Auto-pause after clearing
                DispatchQueue.main.async {
                    view.isPaused = true
                }
                return
            }
            
            let currentSliceIndex = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
            
            // Create cache key (simplified - no quality levels)
            let newCacheKey = "\(currentPlane.rawValue)-\(currentSliceIndex)-\(currentWindowLevel.name)"
            
            // ✅ FIX: Skip render if we've already rendered this exact state
            if newCacheKey == lastRenderedCacheKey && cachedTexture != nil && !needsRender {
                // Already rendered this state, pause immediately
                DispatchQueue.main.async {
                    view.isPaused = true
                }
                return
            }
            
            // Generate new MPR slice if cache key changed
            if cacheKey != newCacheKey || needsRender {
                cacheKey = newCacheKey
                needsRender = false  // ✅ Reset render flag
                
                guard let volumeData = currentVolumeData else {
                    displayLoadingState(drawable: drawable, commandQueue: commandQueue)
                    // ✅ FIX: Auto-pause after loading state
                    DispatchQueue.main.async {
                        view.isPaused = true
                    }
                    return
                }
                
                // Use individual MetalVolumeRenderer instead of shared renderer
                guard let individualRenderer = volumeRenderer else {
                    displayLoadingState(drawable: drawable, commandQueue: commandQueue)
                    // ✅ FIX: Auto-pause after loading state
                    DispatchQueue.main.async {
                        view.isPaused = true
                    }
                    return
                }
                
                // Calculate normalized slice position using coordinate system
                let maxSlices = coordinateSystem.getMaxSlices(for: currentPlane)
                let normalizedSliceIndex = Float(currentSliceIndex) / Float(maxSlices - 1)
                
                let config = MetalVolumeRenderer.MPRConfig(
                    plane: currentPlane,
                    sliceIndex: normalizedSliceIndex,
                    windowCenter: currentWindowLevel.center,
                    windowWidth: currentWindowLevel.width,
                    quality: renderQuality  // Always full quality
                )
                
                print("🚀 SIMPLIFIED: Generating \(currentPlane) slice \(currentSliceIndex) (always full quality)")
                
                // SIMPLIFIED: Always immediate generation - no delays, no priority
                let startTime = Date()
                let planeName = currentPlane.rawValue  // Capture for logging
                individualRenderer.generateMPRSlice(config: config) { [weak self] mprTexture in
                    let endTime = Date()
                    let durationMs = endTime.timeIntervalSince(startTime) * 1000
                    print("⏱️ IMMEDIATE: \(planeName) took \(String(format: "%.1f", durationMs))ms")
                    
                    guard let self = self else { return }
                    self.cachedTexture = mprTexture
                    
                    // Update vertex buffer if texture size changed
                    if let texture = mprTexture {
                        let newTextureSize = CGSize(width: texture.width, height: texture.height)
                        if newTextureSize != self.lastTextureSize {
                            self.vertexBuffer = nil
                        }
                    }
                    
                    // Update view immediately
                    DispatchQueue.main.async {
                        view.setNeedsDisplay()
                    }
                }
                return
            }
            
            // Display cached texture if available
            guard let mprTexture = cachedTexture else {
                displayLoadingState(drawable: drawable, commandQueue: commandQueue)
                // ✅ FIX: Auto-pause after loading state
                DispatchQueue.main.async {
                    view.isPaused = true
                }
                return
            }
            
            // Regenerate vertex buffer if needed
            let textureSize = CGSize(width: mprTexture.width, height: mprTexture.height)
            let needsRegeneration = (
                vertexBuffer == nil ||
                currentViewSize != lastViewSize ||
                textureSize != lastTextureSize ||
                currentPlane != lastPlane ||
                currentVolumeData?.spacing != lastSpacing
            )
            
            if needsRegeneration {
                guard let volumeData = currentVolumeData else {
                    displayLoadingState(drawable: drawable, commandQueue: commandQueue)
                    return
                }
                
                createMedicalAccurateQuad(
                    textureSize: textureSize,
                    viewSize: currentViewSize,
                    plane: currentPlane,
                    dicomSpacing: volumeData.spacing,
                    device: device
                )
            }
            
            displayTexture(mprTexture, drawable: drawable, commandQueue: commandQueue)
            
            // ✅ NEW: Mark this state as rendered
            lastRenderedCacheKey = newCacheKey
            
            // ✅ FIX: Auto-pause after successful render
            DispatchQueue.main.async {
                view.isPaused = true
            }
        }
        
        // MARK: - Rendering Methods
        
        private func displayTexture(_ texture: MTLTexture, drawable: CAMetalDrawable, commandQueue: MTLCommandQueue) {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("❌ CT Display: Failed to create command buffer")
                return
            }
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
            
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
                  let pipelineState = displayPipelineState,
                  let vertexBuffer = vertexBuffer else {
                print("❌ CT Display: Failed to create render encoder or missing pipeline/buffer")
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentTexture(texture, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        private func displayLoadingState(drawable: CAMetalDrawable, commandQueue: MTLCommandQueue) {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("❌ CT Display: Failed to create command buffer for loading state")
                return
            }
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderEncoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        private func clearView(drawable: CAMetalDrawable, commandQueue: MTLCommandQueue) {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("❌ CT Display: Failed to create command buffer for clear view")
                return
            }
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
            
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderEncoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        

    }
}
