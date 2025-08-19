import SwiftUI
import MetalKit
import Metal

// MARK: - Shared Metal Volume Renderer
// Singleton to avoid GPU resource contention in quad mode
class SharedMetalVolumeRenderer {
    static let shared = SharedMetalVolumeRenderer()
    
    private(set) var renderer: MetalVolumeRenderer?
    private let initQueue = DispatchQueue(label: "SharedRenderer", qos: .userInitiated)
    
    private init() {
        // Initialize renderer synchronously on background queue
        initQueue.sync {
            do {
                self.renderer = try MetalVolumeRenderer()
                print("✅ Shared MetalVolumeRenderer created - eliminating GPU contention")
            } catch {
                print("❌ Failed to create shared MetalVolumeRenderer: \(error)")
            }
        }
    }
    
    func loadVolumeIfNeeded(_ volumeData: VolumeData) {
        guard let renderer = renderer else { return }
        
        if !renderer.isVolumeLoaded() {
            do {
                try renderer.loadVolume(volumeData)
                print("✅ Volume loaded into shared renderer")
            } catch {
                print("❌ Failed to load volume into shared renderer: \(error)")
            }
        }
    }
}

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
    
    /// Per-view scrolling state (true modularity)
    let isViewScrolling: Bool
    
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
                sharedState: sharedState,
                isViewScrolling: isViewScrolling
            )
            uiView.setNeedsDisplay()
        }
        }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Medical-Accurate CT Rendering Coordinator
    
    class Coordinator: NSObject, MTKViewDelegate {
        
        // REMOVED: Individual volumeRenderer - now uses shared instance
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
        private var currentIsViewScrolling: Bool = false
        
        // Texture caching for performance (still independent per view)
        private var cachedTexture: MTLTexture?
        private var cacheKey: String = ""
        
        // Quality management
        private var currentQuality: MetalVolumeRenderer.RenderQuality = .full
        private var qualityTimer: Timer?
        private var lastSliceChangeTime: Date = Date()
        
        override init() {
            super.init()
            // REMOVED: setupRenderer() - now uses shared instance
            setupDisplayPipeline()
        }
        
        // REMOVED: setupRenderer() method - now uses SharedMetalVolumeRenderer
        
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
            quality: MetalVolumeRenderer.RenderQuality,  // NEW: Quality parameter
            device: MTLDevice
        ) {
            // CRITICAL: Calculate PHYSICAL dimensions using DICOM spacing and ORIGINAL dimensions
            let physicalDimensions = calculatePhysicalDimensions(
                textureSize: textureSize,
                plane: plane,
                spacing: dicomSpacing,
                quality: quality  // Pass quality to use original dimensions
            )
            
            // Calculate aspect ratio from PHYSICAL dimensions (not pixels)
            let physicalAspect = physicalDimensions.width / physicalDimensions.height
            let viewAspect = Float(viewSize.width / viewSize.height)
            
            print("🏥 MEDICAL ACCURACY (FIXED):")
            print("   📐 Texture pixels: \(Int(textureSize.width))×\(Int(textureSize.height)) (quality: \(quality))")
            print("   📏 Physical size: \(String(format: "%.1f", physicalDimensions.width))mm × \(String(format: "%.1f", physicalDimensions.height))mm")
            print("   📊 Physical aspect: \(String(format: "%.3f", physicalAspect)) (medical - quality independent)")
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
        
        // MEDICAL-CRITICAL: Calculate physical dimensions using DICOM spacing and ORIGINAL dimensions
        // FIXED: Use original full-resolution dimensions regardless of quality scaling
        private func calculatePhysicalDimensions(
            textureSize: CGSize,
            plane: MPRPlane,
            spacing: SIMD3<Float>,
            quality: MetalVolumeRenderer.RenderQuality  // NEW: Quality parameter
        ) -> (width: Float, height: Float) {
            
            // CRITICAL FIX: Use ORIGINAL full-resolution dimensions for spacing calculation
            // Quality scaling should not affect physical dimensions or aspect ratios
            let originalDimensions = getOriginalPlaneDimensions(plane: plane)
            
            let originalPixelWidth = Float(originalDimensions.width)
            let originalPixelHeight = Float(originalDimensions.height)
            
            print("🔧 ASPECT RATIO FIX:")
            print("   📐 Texture size: \(Int(textureSize.width))×\(Int(textureSize.height)) (quality: \(quality))")
            print("   📏 Original size: \(originalDimensions.width)×\(originalDimensions.height) (for spacing)")
            
            switch plane {
            case .axial:
                // XY plane: X × Y dimensions
                let physicalWidth = originalPixelWidth * spacing.x   // Use ORIGINAL pixels × mm/pixel
                let physicalHeight = originalPixelHeight * spacing.y
                return (physicalWidth, physicalHeight)
                
            case .sagittal:
                // YZ plane: Y × Z dimensions  
                let physicalWidth = originalPixelWidth * spacing.y   // Y dimension (anterior-posterior)
                let physicalHeight = originalPixelHeight * spacing.z // Z dimension (superior-inferior)
                return (physicalWidth, physicalHeight)
                
            case .coronal:
                // XZ plane: X × Z dimensions
                let physicalWidth = originalPixelWidth * spacing.x   // X dimension (left-right)
                let physicalHeight = originalPixelHeight * spacing.z // Z dimension (superior-inferior)
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
            sharedState: SharedViewingState?,
            isViewScrolling: Bool
        ) {
            print("🔍 CT Medical Display: updateRenderingParameters called")
            print("   Plane: \(plane), VolumeData: \(volumeData != nil ? "present" : "nil")")
            
            // Store previous state for smart cache management
            let previousPlane = currentPlane
            let previousWindowLevel = currentWindowLevel
            let previousQuality = currentQuality
            
            self.currentCoordinateSystem = coordinateSystem
            self.currentPlane = plane
            self.currentWindowLevel = windowLevel
            self.currentScrollVelocity = scrollVelocity
            self.currentIsViewScrolling = isViewScrolling
            
            // SIMPLIFIED: Use SharedViewingState quality directly (set by MPRGestureController)
            let newQuality: MetalVolumeRenderer.RenderQuality
            if let sharedState = sharedState {
                let currentRenderQuality = sharedState.getQuality(for: plane)
                print("🎯 Using quality \(currentRenderQuality) for plane \(plane) (from SharedViewingState)")
                
                // Convert SharedViewingState quality to MetalVolumeRenderer quality
                switch currentRenderQuality {
                case 1:
                    newQuality = .full
                case 2:
                    newQuality = .half
                case 4:
                    newQuality = .quarter
                case 8:
                    newQuality = .eighth
                default:
                    newQuality = .full
                }
            } else {
                // Fallback when no shared state
                newQuality = .full
            }
            
            // SMART CACHE: Only clear cache when necessary
            var shouldClearCache = false
            
            if newQuality != currentQuality {
                currentQuality = newQuality
                print("🎯 Quality: \(currentQuality) for plane \(plane) (plane-specific)")
                shouldClearCache = true  // Quality change requires new texture
            }
            
            if plane != previousPlane {
                print("🔍 Plane changed: \(previousPlane) → \(plane)")
                shouldClearCache = true  // Plane change requires new texture
                vertexBuffer = nil  // Only regenerate vertex buffer on plane change
            }
            
            if windowLevel.center != previousWindowLevel.center || windowLevel.width != previousWindowLevel.width {
                print("🔍 Window level changed")
                shouldClearCache = true  // Window level change requires new texture
            }
            
            // SMART CACHE: Only clear when actually needed
            if shouldClearCache {
                cachedTexture = nil
                cacheKey = ""
                print("🛠️ Cache cleared due to parameter change")
            } else {
                print("⚙️ Cache preserved - no significant changes")
            }
            
            // Reset quality timer
            qualityTimer?.invalidate()
            if scrollVelocity > 0.1 {
                // Set timer to restore quality after scrolling stops
                qualityTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                    self?.restoreFullQuality()
                }
            }
            
            // Load volume data into shared renderer if provided
            if let volumeData = volumeData {
                if currentVolumeData == nil {
                    print("🔍 CT Medical Display: Loading volume data into shared renderer...")
                    SharedMetalVolumeRenderer.shared.loadVolumeIfNeeded(volumeData)
                    self.currentVolumeData = volumeData
                } else {
                    self.currentVolumeData = volumeData
                }
            }
            
            print("🔍 CT Medical Display: Parameters updated")
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
                
                guard let volumeData = currentVolumeData else {
                    displayLoadingState(drawable: drawable, commandQueue: commandQueue)
                    return
                }
                
                // RESTORED: Direct synchronous access to shared renderer
                guard let sharedRenderer = SharedMetalVolumeRenderer.shared.renderer else {
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
                
                print("🛠️ Generating MPR slice: \(currentPlane) slice \(currentSliceIndex) quality \(currentQuality)")
                
                // MODULAR FIX: Use per-view scrolling state (true standalone modules)
                let isActiveScrollingView = currentIsViewScrolling && (coordinateSystem.scrollVelocity > 0.1)
                
                print("🚀 MODULAR: plane=\(currentPlane), thisViewScrolling=\(currentIsViewScrolling), priority=\(isActiveScrollingView)")
                
                if isActiveScrollingView {
                    // PRIORITY: Immediate generation for the actively scrolled view
                    sharedRenderer.generateMPRSlice(config: config) { [weak self] mprTexture in
                        guard let self = self else { return }
                        self.cachedTexture = mprTexture
                        
                        // OPTIMIZED: Only regenerate vertex buffer if texture size actually changed
                        if let texture = mprTexture {
                            let newTextureSize = CGSize(width: texture.width, height: texture.height)
                            if newTextureSize != self.lastTextureSize {
                                self.vertexBuffer = nil
                            }
                        }
                        
                        // IMMEDIATE: Update without delay for active view
                        DispatchQueue.main.async {
                            view.setNeedsDisplay()
                        }
                    }
                } else {
                    // DEFERRED: Slight delay for non-active views to prioritize the scrolling view
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        sharedRenderer.generateMPRSlice(config: config) { [weak self] mprTexture in
                            guard let self = self else { return }
                            self.cachedTexture = mprTexture
                            
                            // OPTIMIZED: Only regenerate vertex buffer if texture size actually changed
                            if let texture = mprTexture {
                                let newTextureSize = CGSize(width: texture.width, height: texture.height)
                                if newTextureSize != self.lastTextureSize {
                                    self.vertexBuffer = nil
                                }
                            }
                            
                            // Update view when ready
                            DispatchQueue.main.async {
                                view.setNeedsDisplay()
                            }
                        }
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
                    quality: currentQuality,  // FIXED: Pass current quality
                    device: device
                )
            }
            
            displayTexture(mprTexture, drawable: drawable, commandQueue: commandQueue)
        }
        
        // MARK: - Rendering Methods (MEDICAL-ACCURATE)
        
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
        
        // MARK: - Adaptive Quality Methods
        // NOTE: Quality is now managed by MPRGestureController via SharedViewingState
        
        private func restoreFullQuality() {
            guard currentQuality != .full else { return }
            
            print("🎯 Restoring full quality after scroll stop")
            currentQuality = .full
            cachedTexture = nil
            cacheKey = ""
            
            // Update SharedViewingState to reflect restored quality
            if let coordinateSystem = currentCoordinateSystem {
                // Note: We don't have direct access to sharedState here, but the next
                // updateRenderingParameters call with velocity=0 will set it to quality 1
                
                DispatchQueue.main.async { [weak self] in
                    // Force a refresh by clearing cache
                    self?.cachedTexture = nil
                    self?.cacheKey = ""
                }
            }
        }
        
        // NEW: Get original full-resolution dimensions for each plane
        private func getOriginalPlaneDimensions(plane: MPRPlane) -> (width: Int, height: Int) {
            guard let volumeData = currentVolumeData else {
                return (512, 512)  // Fallback
            }
            
            let dims = volumeData.dimensions
            
            switch plane {
            case .axial:
                // XY plane - original matrix size
                return (dims.x, dims.y)
                
            case .sagittal:
                // YZ plane - Y (anterior-posterior) x Z (superior-inferior)
                return (dims.y, dims.z)
                
            case .coronal:
                // XZ plane - X (left-right) x Z (superior-inferior)
                return (dims.x, dims.z)
            }
        }
    }
}
