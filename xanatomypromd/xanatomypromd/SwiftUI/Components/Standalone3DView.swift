import SwiftUI
import Metal
import MetalKit
import simd
import Combine

// MARK: - Standalone 3D View
struct Standalone3DView: View {
    
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    @ObservedObject var sharedState: SharedViewingState
    
    let volumeData: VolumeData?
    let roiData: MinimalRTStructParser.SimpleRTStructData?
    let viewSize: CGSize
    let allowInteraction: Bool
    
    // PERSISTENT 3D view state - maintains rotation/zoom when switching views
    @State private var rotationZ: Float = 0.0
    @State private var localZoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var localPan: CGSize = .zero
    @StateObject private var renderer = Metal3DVolumeRenderer()
    
    // SYNC: Track crosshair changes for real-time updates
    @State private var lastCrosshairPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    init(
        coordinateSystem: DICOMCoordinateSystem,
        sharedState: SharedViewingState,
        volumeData: VolumeData? = nil,
        roiData: MinimalRTStructParser.SimpleRTStructData? = nil,
        viewSize: CGSize = CGSize(width: 512, height: 512),
        allowInteraction: Bool = true
    ) {
        self.coordinateSystem = coordinateSystem
        self.sharedState = sharedState
        self.volumeData = volumeData
        self.roiData = roiData
        self.viewSize = viewSize
        self.allowInteraction = allowInteraction
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            if let volumeData = volumeData {
                Metal3DRenderView(
                    renderer: renderer,
                    volumeData: volumeData,
                    rotationZ: rotationZ,
                    crosshairPosition: coordinateSystem.currentWorldPosition,  // ALWAYS synced
                    coordinateSystem: coordinateSystem,
                    windowLevel: sharedState.windowLevel,
                    zoom: localZoom,
                    pan: localPan
                )
                .clipped()
                .onReceive(coordinateSystem.$currentWorldPosition) { newPosition in
                    // SYNC: Update when crosshairs move in MPR views
                    if newPosition != lastCrosshairPosition {
                        lastCrosshairPosition = newPosition
                        // Force 3D view to re-render with new crosshair position
                    }
                }
            } else {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Loading 3D Volume...")
                        .foregroundColor(.white)
                        .font(.caption)
                }
            }
            
            VStack {
                HStack {
                    Text("3D")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(3)
                    Spacer()
                }
                Spacer()
            }
            .padding(4)
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .gesture(allowInteraction ? createGestureRecognizer() : nil)
        .onAppear { 
            setupRenderer()
            // SYNC: Initialize with current crosshair position
            lastCrosshairPosition = coordinateSystem.currentWorldPosition
            print("🎯 3D View appeared - synced to crosshair: \(coordinateSystem.currentWorldPosition)")
        }
        .onDisappear {
            print("🎯 3D View disappeared - preserving rotation: \(rotationZ), zoom: \(localZoom)")
        }
    }
    
    private func setupRenderer() {
        guard let volumeData = volumeData else { return }
        renderer.setupVolume(volumeData)
        if let roiData = roiData {
            renderer.setupROI(roiData)
        }
    }
    
    private func createGestureRecognizer() -> some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { value in
                    // Only rotate with horizontal swipes
                    let rotationSensitivity: Float = 0.01
                    rotationZ += Float(value.translation.width) * rotationSensitivity
                    
                    // Remove vertical zoom - that was the problem!
                    // Vertical swipes should do nothing or could rotate on another axis
                },
            
            MagnificationGesture()
                .onChanged { value in
                    let delta = value / lastZoom
                    lastZoom = value
                    let newZoom = localZoom * delta
                    localZoom = max(0.5, min(3.0, newZoom))
                }
                .onEnded { _ in
                    lastZoom = 1.0
                }
        )
    }
}

@MainActor
class Metal3DVolumeRenderer: ObservableObject {
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var library: MTLLibrary?
    private var pipelineState: MTLComputePipelineState?
    private var copyPipelineState: MTLRenderPipelineState?
    private var volumeTexture: MTLTexture?
    private var hasLoggedFirstRender = false
    
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
        
        print("🎯 Setting up volume: \(volumeData.dimensions)")
        
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
        
        print("✅ Volume texture created: \(volumeTexture?.width ?? 0)x\(volumeTexture?.height ?? 0)x\(volumeTexture?.depth ?? 0)")
    }
    
    func setupROI(_ roiData: MinimalRTStructParser.SimpleRTStructData) {
        // ROI setup placeholder
    }
    
    func render(to texture: MTLTexture, 
                rotationZ: Float,
                crosshairPosition: SIMD3<Float>,
                volumeOrigin: SIMD3<Float>,
                volumeSpacing: SIMD3<Float>,
                windowLevel: CTWindowLevel,
                zoom: CGFloat,
                pan: CGSize) {
        
        // Only log first render to avoid spam
        if !hasLoggedFirstRender {
            print("🎨 3D Render started - Rotation: \(rotationZ), Zoom: \(zoom), Window: \(windowLevel.name)")
            hasLoggedFirstRender = true
        }
        
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
            displaySize: CGSize(width: texture.width, height: texture.height)
        )
        
        print("Swift struct size: \(MemoryLayout<Volume3DRenderParams>.size) bytes")
        print("Swift struct stride: \(MemoryLayout<Volume3DRenderParams>.stride) bytes")
        print("Swift struct alignment: \(MemoryLayout<Volume3DRenderParams>.alignment) bytes")
        encoder.setBytes(&params, length: MemoryLayout<Volume3DRenderParams>.size, index: 0)
        
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
    // Add spacing as individual floats to avoid SIMD alignment issues
    let spacingX: Float
    let spacingY: Float
    let spacingZ: Float
    let displayWidth: Float
    let displayHeight: Float
    
    init(rotationZ: Float, crosshairPosition: SIMD3<Float>, volumeOrigin: SIMD3<Float>, volumeSpacing: SIMD3<Float>, windowCenter: Float, windowWidth: Float, zoom: Float, panX: Float, panY: Float, displaySize: CGSize) {
        self.rotationZ = rotationZ
        self.windowCenter = windowCenter
        self.windowWidth = windowWidth
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.spacingX = volumeSpacing.x
        self.spacingY = volumeSpacing.y
        self.spacingZ = volumeSpacing.z
        self.displayWidth = Float(displaySize.width)
        self.displayHeight = Float(displaySize.height)
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
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.backgroundColor = UIColor.black
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = true  // Manual render control
        mtkView.isPaused = false  // Allow rendering
        mtkView.preferredFramesPerSecond = 30  // Limit to 30 FPS
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateParams(
            rotationZ: rotationZ,
            crosshairPosition: crosshairPosition,
            volumeOrigin: coordinateSystem.volumeOrigin,
            volumeSpacing: coordinateSystem.volumeSpacing,
            windowLevel: windowLevel,
            zoom: zoom,
            pan: pan
        )
        uiView.setNeedsDisplay()  // Trigger single render
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
        private var lastRenderTime: CFTimeInterval = 0
        
        init(renderer: Metal3DVolumeRenderer) {
            self.renderer = renderer
        }
        
        func updateParams(rotationZ: Float, crosshairPosition: SIMD3<Float>, volumeOrigin: SIMD3<Float>, volumeSpacing: SIMD3<Float>, windowLevel: CTWindowLevel, zoom: CGFloat, pan: CGSize) {
            self.rotationZ = rotationZ
            self.crosshairPosition = crosshairPosition
            self.volumeOrigin = volumeOrigin
            self.volumeSpacing = volumeSpacing
            self.windowLevel = windowLevel
            self.zoom = zoom
            self.pan = pan
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable else { return }
            
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
                pan: pan
            )
            
            drawable.present()
        }
    }
}
