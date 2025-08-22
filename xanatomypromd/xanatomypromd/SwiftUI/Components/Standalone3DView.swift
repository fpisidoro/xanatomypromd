import SwiftUI
import Metal
import MetalKit
import simd
import Combine

// MARK: - Standalone 3D View with Per-View Loading
// 3D view manages its own loading state independently from MPR views

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
    
    // Auto-rotation state
    @State private var autoRotationTimer: Timer?
    @State private var isAutoRotating: Bool = true
    private let autoRotationSpeed: Float = 0.003  // radians per frame (~0.17° per frame, ~5° per second at 30fps)
    
    private let viewId = UUID().uuidString
    
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
            startAutoRotation()
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
                    showROI: sharedState.roiSettings.isVisible
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
    
    // MARK: - View Overlays (Updated)
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
            
            // 3D transformation status
            HStack {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        if isAutoRotating {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 8))
                                .foregroundColor(.green.opacity(0.8))
                        }
                        Text("Rotation: \(String(format: "%.0f°", (sharedState.rotation3D * 180 / .pi).truncatingRemainder(dividingBy: 360)))")
                            .font(.caption2)
                            .foregroundColor(isAutoRotating ? .green.opacity(0.8) : .cyan.opacity(0.8))
                    }
                    
                    if abs(sharedState.zoom3D - 1.0) > 0.1 {
                        Text("Zoom: \(String(format: "%.1fx", sharedState.zoom3D))")
                            .font(.caption2)
                            .foregroundColor(.yellow.opacity(0.8))
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
    
    // MARK: - Auto-Rotation Methods
    
    private func startAutoRotation() {
        // Clean up any existing timer
        stopAutoRotation()
        
        // Create new timer for smooth rotation
        autoRotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            if isAutoRotating && !isDragging {
                // Smooth continuous rotation
                let newRotation = sharedState.rotation3D + autoRotationSpeed
                
                // Keep rotation in reasonable range to avoid float overflow
                let normalizedRotation = newRotation.truncatingRemainder(dividingBy: Float.pi * 2)
                sharedState.update3DRotation(normalizedRotation)
            }
        }
    }
    
    private func stopAutoRotation() {
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
        // Setup 3D volume in renderer
        renderer.setupVolume(volumeData)

    }
    
    private func compile3DShaders() async throws {
        // Simulate shader compilation time
        // In real implementation, this would involve shader compilation
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms for shader compilation

    }
    
    private func setup3DROI() async throws {
        if let roiData = dataCoordinator.roiData {
            try await Task.sleep(nanoseconds: 50_000_000) // Simulate setup time
            renderer.setupROI(roiData)

        } else {

        }
    }
    
    // MARK: - Gesture Handling (Unchanged)
    private func createGestureRecognizer() -> some Gesture {
        let dragGesture = DragGesture()
            .onChanged { value in
                // Stop auto-rotation when user interacts
                isAutoRotating = false
                
                if !isDragging {
                    isDragging = true
                    dragStartLocation = value.startLocation
                    dragStartRotation = sharedState.rotation3D
                }
                
                // Calculate rotation based on total drag distance from start
                let rotationSensitivity: Float = -0.01  // Negative for intuitive control
                let deltaX = Float(value.location.x - dragStartLocation.x)
                let newRotation = dragStartRotation + deltaX * rotationSensitivity
                sharedState.update3DRotation(newRotation)
            }
            .onEnded { _ in
                isDragging = false
                
                // Resume auto-rotation after 3 seconds of no interaction
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if !self.isDragging {  // Double-check user isn't dragging again
                        self.isAutoRotating = true
                    }
                }
            }
        
        let magnificationGesture = MagnificationGesture()
            .onChanged { value in
                // Stop auto-rotation when zooming
                isAutoRotating = false
                
                let newZoom = max(0.5, min(3.0, value))
                sharedState.update3DZoom(newZoom)
            }
            .onEnded { _ in
                // Resume auto-rotation after interaction
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if !self.isDragging {
                        self.isAutoRotating = true
                    }
                }
            }
        
        return dragGesture.simultaneously(with: magnificationGesture)
    }
}

// MARK: - Existing Metal3DVolumeRenderer and related components remain unchanged
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
    
    func setupVolume(_ volumeData: VolumeData) {
        guard let device = device else { return }
        

        
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
        
        // For now, we'll handle the first ROI and its first contour
        // In production, we'd create a more complex buffer structure for multiple ROIs
        guard let firstROI = roiData.roiStructures.first,
              !firstROI.contours.isEmpty else {

            return
        }
        
        // Create a buffer with contour points for the shader
        // We'll pack all contour points into a buffer with metadata
        var roiBufferData: [Float] = []
        
        // Add ROI metadata: color and contour count
        roiBufferData.append(firstROI.displayColor.x)
        roiBufferData.append(firstROI.displayColor.y)
        roiBufferData.append(firstROI.displayColor.z)
        roiBufferData.append(Float(firstROI.contours.count))
        
        // Add each contour's data
        for contour in firstROI.contours {
            // Add contour metadata: slice position and point count
            roiBufferData.append(contour.slicePosition)
            roiBufferData.append(Float(contour.points.count))
            
            // Add contour points (in world coordinates)
            for point in contour.points {
                roiBufferData.append(point.x)
                roiBufferData.append(point.y)
                roiBufferData.append(point.z)
            }
        }
        
        // Create Metal buffer
        let bufferSize = roiBufferData.count * MemoryLayout<Float>.size
        roiBuffer = device.makeBuffer(bytes: roiBufferData, length: bufferSize, options: [])
        roiCount = firstROI.contours.count
        

    }
    
    func render(to texture: MTLTexture, 
                rotationZ: Float,
                crosshairPosition: SIMD3<Float>,
                volumeOrigin: SIMD3<Float>,
                volumeSpacing: SIMD3<Float>,
                windowLevel: CTWindowLevel,
                zoom: CGFloat,
                pan: CGSize,
                showROI: Bool = false) {
        

        
        guard let commandQueue = commandQueue,
              let pipelineState = pipelineState,
              let volumeTexture = volumeTexture,
              let device = device else { 
            print("❌ 3D Render failed - missing components")
            return 
        }
        
        // Create intermediate texture for compute shader output
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,  // Match final texture format
            width: texture.width,
            height: texture.height,
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
        encoder.setTexture(intermediateTexture, index: 1)  // Use intermediate texture
        
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
            displaySize: CGSize(width: texture.width, height: texture.height),
            showROI: showROI ? 1.0 : 0.0,
            roiCount: Float(roiCount)
        )
        
        encoder.setBytes(&params, length: MemoryLayout<Volume3DRenderParams>.size, index: 0)
        
        // Set ROI buffer if available
        if let roiBuffer = roiBuffer, showROI {
            encoder.setBuffer(roiBuffer, offset: 0, index: 1)
        }
        
        let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
        let groupsCount = MTLSize(
            width: (texture.width + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (texture.height + threadsPerGroup.height - 1) / threadsPerGroup.height,
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
            // Use simple copy render pass
            if let copyPipelineState = getCopyPipelineState() {
                renderEncoder.setRenderPipelineState(copyPipelineState)
                renderEncoder.setFragmentTexture(intermediateTexture, index: 0)
                
                // Draw fullscreen quad
                let vertices: [Float] = [
                    -1, -1, 0, 1,  // Bottom-left
                     1, -1, 1, 1,  // Bottom-right
                    -1,  1, 0, 0,  // Top-left
                     1,  1, 1, 0   // Top-right
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

// Simple struct without complex alignment issues
struct Volume3DRenderParams {
    let rotationZ: Float
    let windowCenter: Float
    let windowWidth: Float
    let zoom: Float
    let panX: Float
    let panY: Float
    let crosshairX: Float  // Actual crosshair position from MPR
    let crosshairY: Float
    let crosshairZ: Float
    let spacingX: Float
    let spacingY: Float
    let spacingZ: Float
    let displayWidth: Float
    let displayHeight: Float
    let showROI: Float  // 1.0 if ROI should be shown, 0.0 otherwise
    let roiCount: Float  // Number of ROI contours
    let originX: Float  // Volume origin in world coordinates
    let originY: Float
    let originZ: Float
    
    init(rotationZ: Float, crosshairPosition: SIMD3<Float>, volumeOrigin: SIMD3<Float>, volumeSpacing: SIMD3<Float>, windowCenter: Float, windowWidth: Float, zoom: Float, panX: Float, panY: Float, displaySize: CGSize, showROI: Float = 0.0, roiCount: Float = 0.0) {
        self.rotationZ = rotationZ
        self.windowCenter = windowCenter
        self.windowWidth = windowWidth
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        // Convert world position to voxel coordinates for shader
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
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.backgroundColor = UIColor.black
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = true  // Manual render control
        mtkView.isPaused = true  // ✅ FIX: Start paused, only render on demand
        mtkView.preferredFramesPerSecond = 30  // Only when rendering
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
            showROI: showROI
        )
        
        // ✅ FIX: Only render a single frame when parameters change
        if hasChanges {
            // Unpause briefly for single frame render
            uiView.isPaused = false
            uiView.draw()  // Force immediate single frame render
            uiView.isPaused = true  // Immediately re-pause - NO DELAY!
            
            // NO asyncAfter - we pause immediately!
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
        private var lastRenderTime: CFTimeInterval = 0
        private var hasRenderedCurrentState: Bool = false  // ✅ NEW: Track if we've rendered current state
        
        init(renderer: Metal3DVolumeRenderer) {
            self.renderer = renderer
        }
        
        func updateParams(rotationZ: Float, crosshairPosition: SIMD3<Float>, volumeOrigin: SIMD3<Float>, volumeSpacing: SIMD3<Float>, windowLevel: CTWindowLevel, zoom: CGFloat, pan: CGSize, showROI: Bool) -> Bool {
            // ✅ FIX: More precise change detection with tolerance
            let rotationChanged = abs(self.rotationZ - rotationZ) > 0.001
            let crosshairChanged = length(self.crosshairPosition - crosshairPosition) > 0.1
            let originChanged = length(self.volumeOrigin - volumeOrigin) > 0.1
            let spacingChanged = length(self.volumeSpacing - volumeSpacing) > 0.001
            let windowChanged = abs(self.windowLevel.center - windowLevel.center) > 1.0 || 
                               abs(self.windowLevel.width - windowLevel.width) > 1.0
            let zoomChanged = abs(self.zoom - zoom) > 0.01
            let panChanged = abs(self.pan.width - pan.width) > 0.5 || 
                            abs(self.pan.height - pan.height) > 0.5
            let roiChanged = self.showROI != showROI
            
            let hasChanges = rotationChanged || crosshairChanged || originChanged || 
                           spacingChanged || windowChanged || zoomChanged || 
                           panChanged || roiChanged
            
            if hasChanges {
                self.rotationZ = rotationZ
                self.crosshairPosition = crosshairPosition
                self.volumeOrigin = volumeOrigin
                self.volumeSpacing = volumeSpacing
                self.windowLevel = windowLevel
                self.zoom = zoom
                self.pan = pan
                self.showROI = showROI
                self.hasRenderedCurrentState = false  // ✅ NEW: Mark as needing render
            }
            
            return hasChanges
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable else { return }
            
            // ✅ FIX: Skip if we've already rendered current state
            if hasRenderedCurrentState {
                return
            }
            
            // Throttle rendering to avoid spam
            let now = CACurrentMediaTime()
            if now - lastRenderTime < 0.033 { // Max 30 FPS
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
                showROI: showROI
            )
            
            drawable.present()
            
            // ✅ NEW: Mark as rendered
            hasRenderedCurrentState = true
            
            // ✅ FIX: Auto-pause after render completes
            DispatchQueue.main.async {
                view.isPaused = true
            }
        }
    }
}
