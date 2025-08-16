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
    
    /// Scroll velocity for adaptive quality (NEW)
    let scrollVelocity: Float
    
    /// Shared viewing state for quality control
    let sharedState: SharedViewingState?
    
    // MARK: - UIViewRepresentable Implementation
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.framebufferOnly = false
        mtkView.backgroundColor = UIColor.black
        
        // MEDICAL PRINCIPLE: Let MTKView fill SwiftUI frame
        // We control accuracy in Metal rendering, not view sizing
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        Task { @MainActor in
            context.coordinator.updateRenderingParameters(
                coordinateSystem: coordinateSystem,
                plane: plane,
                windowLevel: windowLevel,
                volumeData: volumeData,
                scrollVelocity: scrollVelocity,
                sharedState: sharedState
            )
            uiView.setNeedsDisplay()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Medical-Accurate CT Rendering Coordinator
    
    class Coordinator: NSObject, MTKViewDelegate {
        
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
        private var currentScrollVelocity: Float = 0.0
        
        // Texture caching for performance
        private var cachedTexture: MTLTexture?
        private var cacheKey: String = ""
        
        // Quality management
        private var currentQuality: MetalVolumeRenderer.RenderQuality = .full
        private var qualityTimer: Timer?
        private var lastSliceChangeTime: Date = Date()
        
        override init() {
            super.init()
            setupRenderer()
            setupDisplayPipeline()
        }
        
        private func setupRenderer() {
            do {
                volumeRenderer = try MetalVolumeRenderer()
                print("✅ CT Medical Display: Volume renderer initialized")
            } catch {
                print("❌ CT Medical Display: Failed to initialize volume renderer: \(error)")
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
            // CRITICAL: Calculate PHYSICAL dimensions using DICOM spacing
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
            print("   📊 Physical aspect: \(String(format: "%.3f", physicalAspect)) (medical)")
            print("   📱 View aspect: \(String(format: "%.3f", viewAspect)) (screen)")
            print("   🎯 DICOM spacing: \(dicomSpacing)")
            
            // Calculate proper quad size to maintain MEDICAL accuracy
            let quadSize: (width: Float, height: Float)
            
            if physicalAspect > viewAspect {
                // Image is physically wider - letterbox top/bottom
                quadSize = (1.0, viewAspect / physicalAspect)
                print("   📱 Medical Letterbox: TOP/BOTTOM (preserving width)")
            } else {
                // Image is physically taller - letterbox left/right
                quadSize = (physicalAspect / viewAspect, 1.0)
                print("   📱 Medical Letterbox: LEFT/RIGHT (preserving height)")
            }
            
            // Create vertices for medically accurate quad
            let quadVertices: [Float] = [
                // Positions                                    // Texture coordinates
                -quadSize.width, -quadSize.height,             0.0, 1.0,  // Bottom left
                 quadSize.width, -quadSize.height,             1.0, 1.0,  // Bottom right
                -quadSize.width,  quadSize.height,             0.0, 0.0,  // Top left
                 quadSize.width,  quadSize.height,             1.0, 0.0   // Top right
            ]
            
            print("   ✅ Medical quad: \(String(format: "%.3f", quadSize.width))×\(String(format: "%.3f", quadSize.height)) (screen fraction)")
            
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
        
        // MEDICAL-CRITICAL: Calculate physical dimensions using DICOM spacing
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
                let physicalWidth = pixelWidth * spacing.x   // pixels × mm/pixel
                let physicalHeight = pixelHeight * spacing.y
                return (physicalWidth, physicalHeight)
                
            case .sagittal:
                // YZ plane: Y × Z dimensions  
                let physicalWidth = pixelWidth * spacing.y   // Y dimension (anterior-posterior)
                let physicalHeight = pixelHeight * spacing.z // Z dimension (superior-inferior)
                return (physicalWidth, physicalHeight)
                
            case .coronal:
                // XZ plane: X × Z dimensions
                let physicalWidth = pixelWidth * spacing.x   // X dimension (left-right)
                let physicalHeight = pixelHeight * spacing.z // Z dimension (superior-inferior)
                return (physicalWidth, physicalHeight)
            }
        }
        
        @MainActor
        func updateRenderingParameters(
            coordinateSystem: DICOMCoordinateSystem,
            plane: MPRPlane,
            windowLevel: CTWindowLevel,
            volumeData: VolumeData?,
            scrollVelocity: Float,
            sharedState: SharedViewingState?
        ) {
            print("🔍 CT Medical Display: updateRenderingParameters called")
            print("   Plane: \(plane), VolumeData: \(volumeData != nil ? "present" : "nil")")
            
            self.currentCoordinateSystem = coordinateSystem
            self.currentPlane = plane
            self.currentWindowLevel = windowLevel
            self.currentScrollVelocity = scrollVelocity
            
            // Use shared state quality if available, otherwise calculate from velocity
            let newQuality: MetalVolumeRenderer.RenderQuality
            if let sharedState = sharedState {
                // Access @MainActor property safely
                let currentRenderQuality = sharedState.renderQuality
                // Convert SharedViewingState quality to MetalVolumeRenderer quality
                switch currentRenderQuality {
                case 1:
                    newQuality = .full
                case 2:
                    newQuality = .half
                case 4:
                    newQuality = .quarter
                default:
                    newQuality = .full
                }
            } else {
                // Fallback to velocity-based quality
                newQuality = determineQuality(from: scrollVelocity)
            }
            
            if newQuality != currentQuality {
                currentQuality = newQuality
                print("🎯 Quality: \(currentQuality) from shared state")
                cachedTexture = nil  // Force regeneration at new quality
                cacheKey = ""  // Clear cache key
            }
            
            // Reset quality timer
            qualityTimer?.invalidate()
            if scrollVelocity > 0.1 {
                // Set timer to restore quality after scrolling stops
                qualityTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                    self?.restoreFullQuality()
                }
            }
            
            // Load volume data into renderer if provided
            if let volumeData = volumeData {
                if currentVolumeData == nil {
                    print("🔍 CT Medical Display: Loading volume data...")
                    do {
                        if volumeRenderer == nil {
                            volumeRenderer = try MetalVolumeRenderer()
                        }
                        try volumeRenderer?.loadVolume(volumeData)
                        self.currentVolumeData = volumeData
                        print("✅ CT Medical Display: Volume data loaded successfully")
                    } catch {
                        print("❌ CT Medical Display: Failed to load volume data: \(error)")
                    }
                } else {
                    self.currentVolumeData = volumeData
                }
            }
            
            // Clear cache to force regeneration
            cachedTexture = nil
            cacheKey = ""
            
            // MEDICAL-CRITICAL: Force vertex buffer regeneration for plane changes
            if plane != lastPlane {
                vertexBuffer = nil
                print("🔍 CT Medical: Plane changed, forcing vertex buffer regeneration")
            }
            
            print("🔍 CT Medical Display: Parameters updated, cache cleared")
        }
        
        // MARK: - MTKViewDelegate
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            print("🔍 CT Medical: Drawable size changed to \(Int(size.width))×\(Int(size.height))")
            
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
                return
            }
            
            let currentSliceIndex = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
            
            // Create cache key including quality level
            let newCacheKey = "\(currentPlane.rawValue)-\(currentSliceIndex)-\(currentWindowLevel.name)-\(currentQuality)"
            
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
                    windowWidth: currentWindowLevel.width,
                    quality: currentQuality  // Use adaptive quality
                )
                
                volumeRenderer.generateMPRSlice(config: config) { [weak self] mprTexture in
                    guard let self = self else { return }
                    self.cachedTexture = mprTexture
                    
                    // MEDICAL-CRITICAL: Force vertex buffer regeneration for new texture
                    if let texture = mprTexture {
                        let newTextureSize = CGSize(width: texture.width, height: texture.height)
                        if newTextureSize != self.lastTextureSize {
                            self.vertexBuffer = nil
                        }
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
            
            // MEDICAL-CRITICAL: Regenerate vertex buffer if needed
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
        }
        
        // MARK: - Rendering Methods (MEDICAL-ACCURATE)
        
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
        
        // MARK: - Adaptive Quality Methods
        
        private func determineQuality(from velocity: Float) -> MetalVolumeRenderer.RenderQuality {
            // Velocity is in slices per second
            let absVelocity = abs(velocity)
            
            // More aggressive quality reduction for better performance
            if absVelocity < 0.5 {
                return .full  // Very slow or stopped: full quality
            } else if absVelocity < 2.0 {
                return .half  // Slow: half quality
            } else if absVelocity < 5.0 {
                return .quarter  // Medium: quarter quality
            } else {
                return .eighth  // Fast: minimum quality
            }
        }
        
        private func restoreFullQuality() {
            guard currentQuality != .full else { return }
            
            print("🎯 Restoring full quality after scroll stop")
            currentQuality = .full
            cachedTexture = nil
            cacheKey = ""
            
            // Trigger redraw
            if let coordinateSystem = currentCoordinateSystem {
                DispatchQueue.main.async { [weak self] in
                    // Force a refresh by clearing cache
                    self?.cachedTexture = nil
                    self?.cacheKey = ""
                }
            }
        }
    }
}
