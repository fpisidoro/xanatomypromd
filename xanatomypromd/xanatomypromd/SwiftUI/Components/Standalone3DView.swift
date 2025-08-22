import SwiftUI
import Metal
import MetalKit
import simd
import Combine

// MARK: - Standalone 3D View with Optimized Rotation Performance
// Optimized for minimal CPU usage during auto-rotation

struct Standalone3DView: View, LoadableView {
    
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    @ObservedObject var sharedState: SharedViewingState
    @ObservedObject var dataCoordinator: ViewDataCoordinator
    
    let viewSize: CGSize
    let allowInteraction: Bool
    
    // MARK: - Per-View Loading State
    @StateObject internal var loadingState = ThreeDViewLoadingState()
    @StateObject private var renderer = Metal3DVolumeRenderer()
    
    // Gesture state (persistent via SharedViewingState)
    @State private var lastZoom: CGFloat = 1.0
    @State private var dragStartRotation: Float = 0.0
    @State private var dragStartLocation: CGPoint = .zero
    @State private var isDragging: Bool = false
    @State private var lastCrosshairPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    // OPTIMIZED: Auto-rotation state with smart timer management
    @State private var autoRotationTimer: Timer?
    @State private var isAutoRotating: Bool = true
    @State private var shouldBeRotating: Bool = true  // Intent to rotate
    @State private var lastRotationUpdate: Float = 0  // Track last rotation value
    
    // OPTIMIZED: Reduced frequency and increased speed
    private let autoRotationSpeed: Float = 0.006  // Doubled speed (was 0.003)
    private let rotationUpdateInterval: TimeInterval = 1.0/15.0  // 15fps instead of 30fps
    private let rotationDeltaThreshold: Float = 0.001  // Skip tiny changes
    
    private let viewId = UUID().uuidString
    
    // MARK: - Computed Properties for Optimization
    private var isInQuadView: Bool {
        // Detect if we're in quad view based on view size or shared state
        return viewSize.width < 300 || viewSize.height < 300
    }
    
    private var renderScale: CGFloat {
        // OPTIMIZED: Reduce render quality in quad view
        return isInQuadView ? 0.75 : 1.0
    }
    
    // MARK: - Initialization (Updated)
    init(
        coordinateSystem: DICOMCoordinateSystem,
        sharedState: SharedViewingState,
        dataCoordinator: ViewDataCoordinator,
        viewSize: CGSize = CGSize(width: 512, height: 512),
        allowInteraction: Bool = true
    ) {
        self.coordinateSystem = coordinateSystem
        self.sharedState = sharedState
        self.dataCoordinator = dataCoordinator
        self.viewSize = viewSize
        self.allowInteraction = allowInteraction
    }
    
    // MARK: - Convenience Initializer (Backward Compatibility)
    init(
        coordinateSystem: DICOMCoordinateSystem,
        sharedState: SharedViewingState,
        volumeData: VolumeData? = nil,
        roiData: MinimalRTStructParser.SimpleRTStructData? = nil,
        viewSize: CGSize = CGSize(width: 512, height: 512),
        allowInteraction: Bool = true
    ) {
        // Create a temporary data coordinator for backward compatibility
        let tempCoordinator = ViewDataCoordinator()
        tempCoordinator.volumeData = volumeData
        tempCoordinator.roiData = roiData
        
        self.coordinateSystem = coordinateSystem
        self.sharedState = sharedState
        self.dataCoordinator = tempCoordinator
        self.viewSize = viewSize
        self.allowInteraction = allowInteraction
    }
    
    var body: some View {
        ZStack {
            if loadingState.isLoading {
                // Per-view loading indicator
                ViewLoadingIndicator(
                    loadingState: loadingState,
                    viewType: "3D Volume",
                    viewSize: viewSize
                )
            } else {
                // Actual 3D content
                threeDContentView
                    .opacity(loadingState.isLoading ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: loadingState.isLoading)
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .clipped()
        .background(.black)
        .onAppear {
            setupView()
            evaluateRotationState()
        }
        .onDisappear {
            cleanupView()
            stopAutoRotation()
        }
        .onChange(of: dataCoordinator.volumeData) { _, newVolumeData in
            if newVolumeData != nil && loadingState.volumeDataReady == false {
                Task {
                    await process3DData()
                }
            }
        }
        // OPTIMIZED: Smart timer management - restart/stop based on MPR scrolling
        .onChange(of: sharedState.isActivelyScrollingMPR) { _, isScrolling in
            if isScrolling {
                stopAutoRotation()  // Completely stop timer
            } else if shouldBeRotating && !isDragging {
                // Restart after a small delay to ensure MPR is done
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if !sharedState.isActivelyScrollingMPR && shouldBeRotating && !isDragging {
                        startAutoRotation()
                    }
                }
            }
        }
    }
    
    // MARK: - 3D Content View
    private var threeDContentView: some View {
        ZStack {
            if let volumeData = dataCoordinator.volumeData {
                Metal3DRenderView(
                    renderer: renderer,
                    volumeData: volumeData,
                    rotationZ: sharedState.rotation3D,
                    crosshairPosition: coordinateSystem.currentWorldPosition,
                    coordinateSystem: coordinateSystem,
                    windowLevel: sharedState.windowLevel,
                    zoom: sharedState.zoom3D,
                    pan: sharedState.pan3D,
                    showROI: sharedState.roiSettings.isVisible,
                    renderScale: renderScale,  // OPTIMIZED: Pass render scale
                    rotationDeltaThreshold: rotationDeltaThreshold  // OPTIMIZED: Pass threshold
                )
                .clipped()
                .onReceive(coordinateSystem.$currentWorldPosition) { newPosition in
                    if newPosition != lastCrosshairPosition {
                        lastCrosshairPosition = newPosition
                    }
                }
            }
            
            // 3D View label overlay
            viewLabelOverlay
        }
        .gesture(allowInteraction ? createGestureRecognizer() : nil)
    }
    
    // MARK: - View Overlays (Updated with Performance Indicator)
    private var viewLabelOverlay: some View {
        VStack {
            HStack {
                // 3D label with loading indicator
                HStack(spacing: 4) {
                    Text("3D")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    // Small ready indicator
                    if !loadingState.isLoading {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                    
                    // OPTIMIZED: Performance mode indicator
                    if isInQuadView {
                        Text("Q")  // Quad mode indicator
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                    }
                }
                .padding(4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(3)
                
                Spacer()
                
                // 3D controls indicator
                if allowInteraction {
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(spacing: 2) {
                            Image(systemName: "hand.draw")
                                .font(.system(size: 8))
                            Text("Drag to control")
                        }
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                        
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8))
                            Text("Pinch to zoom")
                        }
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                }
            }
            .padding(4)
            
            Spacer()
            
            // 3D transformation status with timer state
            HStack {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        if sharedState.isActivelyScrollingMPR {
                            // MPR has priority - timer stopped
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.orange.opacity(0.8))
                        } else if autoRotationTimer != nil && isAutoRotating {
                            // Timer active and rotating
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 8))
                                .foregroundColor(.green.opacity(0.8))
                        } else if !isAutoRotating {
                            // Timer stopped, manual control
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.cyan.opacity(0.8))
                        }
                        Text("Rotation: \(String(format: "%.0f°", (sharedState.rotation3D * 180 / .pi).truncatingRemainder(dividingBy: 360)))")
                            .font(.caption2)
                            .foregroundColor(sharedState.isActivelyScrollingMPR ? .orange.opacity(0.8) : (isAutoRotating ? .green.opacity(0.8) : .cyan.opacity(0.8)))
                    }
                    
                    if abs(sharedState.zoom3D - 1.0) > 0.1 {
                        Text("Zoom: \(String(format: "%.1fx", sharedState.zoom3D))")
                            .font(.caption2)
                            .foregroundColor(.yellow.opacity(0.8))
                    }
                    
                    // OPTIMIZED: Show render quality in quad mode
                    if isInQuadView {
                        Text("Quality: 75%")
                            .font(.system(size: 8))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
                .padding(4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
            }
            .padding(4)
        }
    }
    
    // MARK: - LoadableView Protocol Implementation
    func startLoading() {
        loadingState.isLoading = true
        loadingState.updateStage(.volumeData)
    }
    
    func updateLoadingProgress(_ progress: Float, message: String) {
        loadingState.progress = progress
        loadingState.message = message
    }
    
    func completeLoading() {
        loadingState.updateStage(.complete)
    }
    
    // MARK: - View Lifecycle
    private func setupView() {
        // Start loading immediately
        startLoading()
        
        // Register for data updates
        dataCoordinator.registerViewCallback(viewId: viewId) { [self] isReady in
            if isReady {
                Task {
                    await process3DData()
                }
            }
        }
        
        // Initialize persistent state
        lastCrosshairPosition = coordinateSystem.currentWorldPosition
        dragStartRotation = sharedState.rotation3D
        lastRotationUpdate = sharedState.rotation3D
        
        // If data is already available, start processing
        if dataCoordinator.volumeData != nil {
            Task {
                await process3DData()
            }
        }
    }
    
    private func cleanupView() {
        dataCoordinator.unregisterViewCallback(viewId: viewId)
        stopAutoRotation()
    }
    
    // MARK: - OPTIMIZED Auto-Rotation Methods
    
    private func evaluateRotationState() {
        // Determine if we should start rotating
        if shouldBeRotating && !isDragging && !sharedState.isActivelyScrollingMPR {
            startAutoRotation()
        }
    }
    
    private func startAutoRotation() {
        // OPTIMIZED: Only create timer if actually needed
        guard shouldBeRotating && !isDragging && !sharedState.isActivelyScrollingMPR else {
            return
        }
        
        // Clean up any existing timer
        stopAutoRotation()
        
        isAutoRotating = true
        
        // OPTIMIZED: Create timer with reduced frequency (15fps instead of 30fps)
        autoRotationTimer = Timer.scheduledTimer(withTimeInterval: rotationUpdateInterval, repeats: true) { [self] _ in
            // OPTIMIZED: Stop timer immediately if conditions change
            if sharedState.isActivelyScrollingMPR || !isAutoRotating || isDragging {
                stopAutoRotation()
                return
            }
            
            // OPTIMIZED: Batch state update with transaction
            let rotationDelta = autoRotationSpeed
            let newRotation = sharedState.rotation3D + rotationDelta
            
            // OPTIMIZED: Skip update if change is too small
            if abs(newRotation - lastRotationUpdate) > rotationDeltaThreshold {
                withTransaction(Transaction(animation: nil)) {
                    sharedState.update3DRotation(newRotation.truncatingRemainder(dividingBy: Float.pi * 2))
                }
                lastRotationUpdate = newRotation
            }
        }
    }
    
    private func stopAutoRotation() {
        // OPTIMIZED: Completely stop and deallocate timer
        autoRotationTimer?.invalidate()
        autoRotationTimer = nil
    }
    
    // MARK: - 3D Data Processing Pipeline
    @MainActor
    private func process3DData() async {
        guard let volumeData = dataCoordinator.volumeData else {
            loadingState.setError("No volume data available")
            return
        }
        
        do {
            // Stage 1: Volume data ready
            loadingState.updateStage(.volumeData)
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms delay for UI
            
            // Stage 2: Initialize Metal 3D renderer
            loadingState.updateStage(.metalSetup)
            try await initialize3DRenderer(volumeData: volumeData)
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms for Metal setup
            
            // Stage 3: Compile 3D shaders
            loadingState.updateStage(.shaderCompilation)
            try await compile3DShaders()
            try await Task.sleep(nanoseconds: 150_000_000) // 150ms for shader compilation
            
            // Stage 4: Setup 3D ROI (if available)
            loadingState.updateStage(.roiSetup)
            try await setup3DROI()
            try await Task.sleep(nanoseconds: 50_000_000)
            
            // Stage 5: Complete
            completeLoading()
            
        } catch {
            print("❌ 3D View: Loading failed - \(error)")
            loadingState.setError("Failed to load 3D: \(error.localizedDescription)")
        }
    }
    
    private func initialize3DRenderer(volumeData: VolumeData) async throws {
        // Setup 3D volume in renderer with render scale consideration
        renderer.setupVolume(volumeData, renderScale: renderScale)
    }
    
    private func compile3DShaders() async throws {
        // Simulate shader compilation time
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms for shader compilation
    }
    
    private func setup3DROI() async throws {
        if let roiData = dataCoordinator.roiData {
            try await Task.sleep(nanoseconds: 50_000_000) // Simulate setup time
            renderer.setupROI(roiData)
        }
    }
    
    // MARK: - Gesture Handling (Updated with better rotation control)
    private func createGestureRecognizer() -> some Gesture {
        let dragGesture = DragGesture()
            .onChanged { value in
                // Stop auto-rotation when user interacts
                isAutoRotating = false
                shouldBeRotating = false  // User has taken control
                stopAutoRotation()  // Stop timer immediately
                
                if !isDragging {
                    isDragging = true
                    dragStartLocation = value.startLocation
                    dragStartRotation = sharedState.rotation3D
                }
                
                // Calculate rotation based on total drag distance from start
                let rotationSensitivity: Float = -0.01  // Negative for intuitive control
                let deltaX = Float(value.location.x - dragStartLocation.x)
                let newRotation = dragStartRotation + deltaX * rotationSensitivity
                
                // OPTIMIZED: Only update if change is significant
                if abs(newRotation - lastRotationUpdate) > rotationDeltaThreshold {
                    sharedState.update3DRotation(newRotation)
                    lastRotationUpdate = newRotation
                }
            }
            .onEnded { _ in
                isDragging = false
                
                // Resume auto-rotation after 3 seconds of no interaction
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if !self.isDragging {  // Double-check user isn't dragging again
                        self.shouldBeRotating = true
                        self.isAutoRotating = true
                        self.evaluateRotationState()  // Re-evaluate and start if appropriate
                    }
                }
            }
        
        let magnificationGesture = MagnificationGesture()
            .onChanged { value in
                // Stop auto-rotation when zooming
                isAutoRotating = false
                shouldBeRotating = false
                stopAutoRotation()
                
                let newZoom = max(0.5, min(3.0, value))
                sharedState.update3DZoom(newZoom)
            }
            .onEnded { _ in
                // Resume auto-rotation after interaction
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if !self.isDragging {
                        self.shouldBeRotating = true
                        self.isAutoRotating = true
                        self.evaluateRotationState()
                    }
                }
            }
        
        return dragGesture.simultaneously(with: magnificationGesture)
    }
}

// MARK: - OPTIMIZED Metal3DVolumeRenderer
@MainActor
class Metal3DVolumeRenderer: ObservableObject {
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var library: MTLLibrary?
    private var pipelineState: MTLComputePipelineState?
    private var copyPipelineState: MTLRenderPipelineState?
    private var volumeTexture: MTLTexture?
    private var hasLoggedFirstRender = false
    
    // ROI data storage
    private var roiBuffer: MTLBuffer?
    private var roiCount: Int = 0
    private var roiData: MinimalRTStructParser.SimpleRTStructData?
    
    // OPTIMIZED: Render scale tracking
    private var currentRenderScale: CGFloat = 1.0
    
    init() {
        setupMetal()
    }
    
    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.library = device.makeDefaultLibrary()
        setupVolumeRenderingPipeline()
        setupCopyPipeline()
    }
    
    private func setupCopyPipeline() {
        guard let device = device,
              let library = library else { return }
        
        let vertexFunction = library.makeFunction(name: "vertex_simple")
        let fragmentFunction = library.makeFunction(name: "fragment_simple")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            copyPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("❌ Copy pipeline state creation failed: \(error)")
        }
    }
    
    private func setupVolumeRenderingPipeline() {
        guard let device = device,
              let library = library,
              let function = library.makeFunction(name: "volumeRender3D") else { return }
        
        do {
            pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            print("❌ 3D pipeline state creation failed: \(error)")
        }
    }
    
    private func getCopyPipelineState() -> MTLRenderPipelineState? {
        return copyPipelineState
    }
    
    // OPTIMIZED: Accept render scale parameter
    func setupVolume(_ volumeData: VolumeData, renderScale: CGFloat = 1.0) {
        guard let device = device else { return }
        
        currentRenderScale = renderScale
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type3D
        textureDescriptor.pixelFormat = .r16Sint
        textureDescriptor.width = volumeData.dimensions.x
        textureDescriptor.height = volumeData.dimensions.y
        textureDescriptor.depth = volumeData.dimensions.z
        textureDescriptor.usage = [.shaderRead]
        
        volumeTexture = device.makeTexture(descriptor: textureDescriptor)
        
        volumeTexture?.replace(
            region: MTLRegionMake3D(0, 0, 0, volumeData.dimensions.x, volumeData.dimensions.y, volumeData.dimensions.z),
            mipmapLevel: 0,
            slice: 0,
            withBytes: volumeData.voxelData,
            bytesPerRow: volumeData.dimensions.x * 2,
            bytesPerImage: volumeData.dimensions.x * volumeData.dimensions.y * 2
        )
    }
    
    func setupROI(_ roiData: MinimalRTStructParser.SimpleRTStructData) {
        guard let device = device else { return }
        self.roiData = roiData
        
        guard let firstROI = roiData.roiStructures.first,
              !firstROI.contours.isEmpty else {
            return
        }
        
        var roiBufferData: [Float] = []
        
        roiBufferData.append(firstROI.displayColor.x)
        roiBufferData.append(firstROI.displayColor.y)
        roiBufferData.append(firstROI.displayColor.z)
        roiBufferData.append(Float(firstROI.contours.count))
        
        for contour in firstROI.contours {
            roiBufferData.append(contour.slicePosition)
            roiBufferData.append(Float(contour.points.count))
            
            for point in contour.points {
                roiBufferData.append(point.x)
                roiBufferData.append(point.y)
                roiBufferData.append(point.z)
            }
        }
        
        let bufferSize = roiBufferData.count * MemoryLayout<Float>.size
        roiBuffer = device.makeBuffer(bytes: roiBufferData, length: bufferSize, options: [])
        roiCount = firstROI.contours.count
    }
    
    // OPTIMIZED: Add render scale to render method
    func render(to texture: MTLTexture, 
                rotationZ: Float,
                crosshairPosition: SIMD3<Float>,
                volumeOrigin: SIMD3<Float>,
                volumeSpacing: SIMD3<Float>,
                windowLevel: CTWindowLevel,
                zoom: CGFloat,
                pan: CGSize,
                showROI: Bool = false,
                renderScale: CGFloat = 1.0) {
        
        guard let commandQueue = commandQueue,
              let pipelineState = pipelineState,
              let volumeTexture = volumeTexture,
              let device = device else { 
            print("❌ 3D Render failed - missing components")
            return 
        }
        
        // OPTIMIZED: Use scaled texture size for performance
        let scaledWidth = Int(CGFloat(texture.width) * renderScale)
        let scaledHeight = Int(CGFloat(texture.height) * renderScale)
        
        // Create intermediate texture for compute shader output
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: scaledWidth,  // OPTIMIZED: Use scaled dimensions
            height: scaledHeight,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderWrite, .shaderRead]
        
        guard let intermediateTexture = device.makeTexture(descriptor: textureDescriptor) else {
            print("❌ Failed to create intermediate texture")
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(volumeTexture, index: 0)
        encoder.setTexture(intermediateTexture, index: 1)
        
        var params = Volume3DRenderParams(
            rotationZ: rotationZ,
            crosshairPosition: crosshairPosition,
            volumeOrigin: volumeOrigin,
            volumeSpacing: volumeSpacing,
            windowCenter: windowLevel.center,
            windowWidth: windowLevel.width,
            zoom: Float(zoom),
            panX: Float(pan.width),
            panY: Float(pan.height),
            displaySize: CGSize(width: scaledWidth, height: scaledHeight),  // OPTIMIZED: Scaled size
            showROI: showROI ? 1.0 : 0.0,
            roiCount: Float(roiCount)
        )
        
        encoder.setBytes(&params, length: MemoryLayout<Volume3DRenderParams>.size, index: 0)
        
        if let roiBuffer = roiBuffer, showROI {
            encoder.setBuffer(roiBuffer, offset: 0, index: 1)
        }
        
        let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
        let groupsCount = MTLSize(
            width: (scaledWidth + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (scaledHeight + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(groupsCount, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        // Copy intermediate texture to final texture using render pass
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            if let copyPipelineState = getCopyPipelineState() {
                renderEncoder.setRenderPipelineState(copyPipelineState)
                renderEncoder.setFragmentTexture(intermediateTexture, index: 0)
                
                let vertices: [Float] = [
                    -1, -1, 0, 1,
                     1, -1, 1, 1,
                    -1,  1, 0, 0,
                     1,  1, 1, 0
                ]
                
                renderEncoder.setVertexBytes(vertices, length: vertices.count * 4, index: 0)
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            renderEncoder.endEncoding()
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

// Volume3DRenderParams struct remains unchanged
struct Volume3DRenderParams {
    let rotationZ: Float
    let windowCenter: Float
    let windowWidth: Float
    let zoom: Float
    let panX: Float
    let panY: Float
    let crosshairX: Float
    let crosshairY: Float
    let crosshairZ: Float
    let spacingX: Float
    let spacingY: Float
    let spacingZ: Float
    let displayWidth: Float
    let displayHeight: Float
    let showROI: Float
    let roiCount: Float
    let originX: Float
    let originY: Float
    let originZ: Float
    
    init(rotationZ: Float, crosshairPosition: SIMD3<Float>, volumeOrigin: SIMD3<Float>, volumeSpacing: SIMD3<Float>, windowCenter: Float, windowWidth: Float, zoom: Float, panX: Float, panY: Float, displaySize: CGSize, showROI: Float = 0.0, roiCount: Float = 0.0) {
        self.rotationZ = rotationZ
        self.windowCenter = windowCenter
        self.windowWidth = windowWidth
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.crosshairX = (crosshairPosition.x - volumeOrigin.x) / volumeSpacing.x
        self.crosshairY = (crosshairPosition.y - volumeOrigin.y) / volumeSpacing.y
        self.crosshairZ = (crosshairPosition.z - volumeOrigin.z) / volumeSpacing.z
        self.spacingX = volumeSpacing.x
        self.spacingY = volumeSpacing.y
        self.spacingZ = volumeSpacing.z
        self.displayWidth = Float(displaySize.width)
        self.displayHeight = Float(displaySize.height)
        self.showROI = showROI
        self.roiCount = roiCount
        self.originX = volumeOrigin.x
        self.originY = volumeOrigin.y
        self.originZ = volumeOrigin.z
    }
}

// OPTIMIZED: Updated Metal3DRenderView with improved render control
struct Metal3DRenderView: UIViewRepresentable {
    let renderer: Metal3DVolumeRenderer
    let volumeData: VolumeData
    let rotationZ: Float
    let crosshairPosition: SIMD3<Float>
    let coordinateSystem: DICOMCoordinateSystem
    let windowLevel: CTWindowLevel
    let zoom: CGFloat
    let pan: CGSize
    let showROI: Bool
    let renderScale: CGFloat  // OPTIMIZED: Accept render scale
    let rotationDeltaThreshold: Float  // OPTIMIZED: Accept threshold
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.backgroundColor = UIColor.black
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true  // Start paused, only render on demand
        mtkView.preferredFramesPerSecond = 30
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        let hasChanges = context.coordinator.updateParams(
            rotationZ: rotationZ,
            crosshairPosition: crosshairPosition,
            volumeOrigin: coordinateSystem.volumeOrigin,
            volumeSpacing: coordinateSystem.volumeSpacing,
            windowLevel: windowLevel,
            zoom: zoom,
            pan: pan,
            showROI: showROI,
            renderScale: renderScale,
            rotationDeltaThreshold: rotationDeltaThreshold
        )
        
        // Only render a single frame when parameters change significantly
        if hasChanges {
            uiView.isPaused = false
            uiView.draw()
            uiView.isPaused = true
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        let renderer: Metal3DVolumeRenderer
        private var rotationZ: Float = 0
        private var crosshairPosition = SIMD3<Float>(0, 0, 0)
        private var volumeOrigin = SIMD3<Float>(0, 0, 0)
        private var volumeSpacing = SIMD3<Float>(1, 1, 1)
        private var windowLevel: CTWindowLevel = .softTissue
        private var zoom: CGFloat = 1.0
        private var pan: CGSize = .zero
        private var showROI: Bool = false
        private var renderScale: CGFloat = 1.0
        private var rotationDeltaThreshold: Float = 0.001
        private var lastRenderTime: CFTimeInterval = 0
        private var hasRenderedCurrentState: Bool = false
        
        init(renderer: Metal3DVolumeRenderer) {
            self.renderer = renderer
        }
        
        func updateParams(rotationZ: Float, crosshairPosition: SIMD3<Float>, volumeOrigin: SIMD3<Float>, volumeSpacing: SIMD3<Float>, windowLevel: CTWindowLevel, zoom: CGFloat, pan: CGSize, showROI: Bool, renderScale: CGFloat, rotationDeltaThreshold: Float) -> Bool {
            // OPTIMIZED: More intelligent change detection
            let rotationChanged = abs(self.rotationZ - rotationZ) > rotationDeltaThreshold
            let crosshairChanged = length(self.crosshairPosition - crosshairPosition) > 0.1
            let originChanged = length(self.volumeOrigin - volumeOrigin) > 0.1
            let spacingChanged = length(self.volumeSpacing - volumeSpacing) > 0.001
            let windowChanged = abs(self.windowLevel.center - windowLevel.center) > 1.0 || 
                               abs(self.windowLevel.width - windowLevel.width) > 1.0
            let zoomChanged = abs(self.zoom - zoom) > 0.01
            let panChanged = abs(self.pan.width - pan.width) > 0.5 || 
                            abs(self.pan.height - pan.height) > 0.5
            let roiChanged = self.showROI != showROI
            let scaleChanged = abs(self.renderScale - renderScale) > 0.01
            
            let hasChanges = rotationChanged || crosshairChanged || originChanged || 
                           spacingChanged || windowChanged || zoomChanged || 
                           panChanged || roiChanged || scaleChanged
            
            if hasChanges {
                self.rotationZ = rotationZ
                self.crosshairPosition = crosshairPosition
                self.volumeOrigin = volumeOrigin
                self.volumeSpacing = volumeSpacing
                self.windowLevel = windowLevel
                self.zoom = zoom
                self.pan = pan
                self.showROI = showROI
                self.renderScale = renderScale
                self.rotationDeltaThreshold = rotationDeltaThreshold
                self.hasRenderedCurrentState = false
            }
            
            return hasChanges
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable else { return }
            
            // Skip if already rendered current state
            if hasRenderedCurrentState {
                return
            }
            
            // OPTIMIZED: Throttle rendering more aggressively
            let now = CACurrentMediaTime()
            if now - lastRenderTime < 0.066 { // Max 15 FPS for 3D view
                return
            }
            lastRenderTime = now
            
            renderer.render(
                to: drawable.texture,
                rotationZ: rotationZ,
                crosshairPosition: crosshairPosition,
                volumeOrigin: volumeOrigin,
                volumeSpacing: volumeSpacing,
                windowLevel: windowLevel,
                zoom: zoom,
                pan: pan,
                showROI: showROI,
                renderScale: renderScale  // OPTIMIZED: Pass render scale
            )
            
            drawable.present()
            hasRenderedCurrentState = true
            
            // Auto-pause after render
            DispatchQueue.main.async {
                view.isPaused = true
            }
        }
    }
}
