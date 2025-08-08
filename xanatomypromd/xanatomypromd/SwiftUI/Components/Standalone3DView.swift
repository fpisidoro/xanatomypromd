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
    
    @State private var rotationZ: Float = 0.0
    @State private var localZoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var localPan: CGSize = .zero
    @StateObject private var renderer = Metal3DVolumeRenderer()
    
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
                    crosshairPosition: coordinateSystem.currentWorldPosition,
                    windowLevel: sharedState.windowLevel,
                    zoom: localZoom,
                    pan: localPan
                )
                .clipped()
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
        .onAppear { setupRenderer() }
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
                    let rotationSensitivity: Float = 0.01
                    rotationZ += Float(value.translation.width) * rotationSensitivity
                    
                    let zoomSensitivity: CGFloat = 0.01
                    let newZoom = max(0.5, min(3.0, localZoom + value.translation.height * zoomSensitivity))
                    localZoom = newZoom
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
    private var volumeTexture: MTLTexture?
    
    init() {
        setupMetal()
    }
    
    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.library = device.makeDefaultLibrary()
        setupVolumeRenderingPipeline()
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
        // ROI setup placeholder
    }
    
    func render(to texture: MTLTexture, 
                rotationZ: Float,
                crosshairPosition: SIMD3<Float>,
                windowLevel: CTWindowLevel,
                zoom: CGFloat,
                pan: CGSize) {
        
        guard let commandQueue = commandQueue,
              let pipelineState = pipelineState,
              let volumeTexture = volumeTexture,
              let device = device else { return }
        
        // Create intermediate texture for compute shader output
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
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
            windowCenter: windowLevel.center,
            windowWidth: windowLevel.width,
            zoom: Float(zoom),
            panX: Float(pan.width),
            panY: Float(pan.height)
        )
        
        encoder.setBytes(&params, length: MemoryLayout<Volume3DRenderParams>.size, index: 0)
        
        let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
        let groupsCount = MTLSize(
            width: (texture.width + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (texture.height + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(groupsCount, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        // Copy intermediate texture to final texture using blit encoder
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.copy(
                from: intermediateTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                to: texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

struct Volume3DRenderParams {
    let rotationZ: Float
    let padding1: Float  // Align to 8 bytes
    let crosshairPosition: SIMD3<Float>
    let padding2: Float  // Align to 16 bytes
    let windowCenter: Float
    let windowWidth: Float
    let zoom: Float
    let padding3: Float  // Align to 16 bytes
    let panX: Float
    let panY: Float
    let padding4: Float
    let padding5: Float  // Total: 64 bytes
    
    init(rotationZ: Float, crosshairPosition: SIMD3<Float>, windowCenter: Float, windowWidth: Float, zoom: Float, panX: Float, panY: Float) {
        self.rotationZ = rotationZ
        self.padding1 = 0
        self.crosshairPosition = crosshairPosition
        self.padding2 = 0
        self.windowCenter = windowCenter
        self.windowWidth = windowWidth
        self.zoom = zoom
        self.padding3 = 0
        self.panX = panX
        self.panY = panY
        self.padding4 = 0
        self.padding5 = 0
    }
}

struct Metal3DRenderView: UIViewRepresentable {
    let renderer: Metal3DVolumeRenderer
    let volumeData: VolumeData
    let rotationZ: Float
    let crosshairPosition: SIMD3<Float>
    let windowLevel: CTWindowLevel
    let zoom: CGFloat
    let pan: CGSize
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.backgroundColor = UIColor.black
        mtkView.delegate = context.coordinator
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateParams(
            rotationZ: rotationZ,
            crosshairPosition: crosshairPosition,
            windowLevel: windowLevel,
            zoom: zoom,
            pan: pan
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        let renderer: Metal3DVolumeRenderer
        private var rotationZ: Float = 0
        private var crosshairPosition = SIMD3<Float>(0, 0, 0)
        private var windowLevel: CTWindowLevel = .softTissue
        private var zoom: CGFloat = 1.0
        private var pan: CGSize = .zero
        
        init(renderer: Metal3DVolumeRenderer) {
            self.renderer = renderer
        }
        
        func updateParams(rotationZ: Float, crosshairPosition: SIMD3<Float>, windowLevel: CTWindowLevel, zoom: CGFloat, pan: CGSize) {
            self.rotationZ = rotationZ
            self.crosshairPosition = crosshairPosition
            self.windowLevel = windowLevel
            self.zoom = zoom
            self.pan = pan
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable else { return }
            
            renderer.render(
                to: drawable.texture,
                rotationZ: rotationZ,
                crosshairPosition: crosshairPosition,
                windowLevel: windowLevel,
                zoom: zoom,
                pan: pan
            )
            
            drawable.present()
        }
    }
}
