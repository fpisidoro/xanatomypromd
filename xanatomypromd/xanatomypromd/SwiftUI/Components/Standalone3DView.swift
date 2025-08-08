import SwiftUI
import Metal
import MetalKit
import simd

// MARK: - Standalone 3D View
// Volume rendered 3D visualization with translucent CT and ROI overlay
// Integrates with existing modular architecture for seamless synchronization

struct Standalone3DView: View {
    
    // MARK: - Configuration
    
    /// Shared coordinate system (for crosshair plane sync)
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    
    /// Shared viewing state (for ROI selection sync)  
    @ObservedObject var sharedState: SharedViewingState
    
    /// Data sources
    let volumeData: VolumeData?
    let roiData: MinimalRTStructParser.SimpleRTStructData?
    
    /// View configuration
    let viewSize: CGSize
    let allowInteraction: Bool
    
    // MARK: - Local 3D State (Independent)
    
    @State private var rotationZ: Float = 0.0  // Only Z-axis rotation
    @State private var localZoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var localPan: CGSize = .zero
    @State private var isDragging = false
    
    // 3D Rendering engine
    @StateObject private var renderer = Metal3DVolumeRenderer()
    
    // MARK: - Initialization
    
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
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.black
            
            if let volumeData = volumeData {
                Metal3DRenderView(
                    renderer: renderer,
                    volumeData: volumeData,
                    roiData: roiData,
                    rotationZ: rotationZ,
                    crosshairPosition: coordinateSystem.currentWorldPosition,
                    zoom: localZoom,
                    pan: localPan
                )
                .clipped()
            } else {
                // Loading placeholder
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Loading 3D Volume...")
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding(.top)
                }
            }
            
            // View label overlay
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
        .gesture(
            allowInteraction ? createGestureRecognizer() : nil
        )
        .onAppear {
            setupRenderer()
        }
        .onChange(of: volumeData) { _ in
            setupRenderer()
        }
    }
    
    // MARK: - Setup
    
    private func setupRenderer() {
        guard let volumeData = volumeData else { return }
        renderer.setupVolume(volumeData)
        if let roiData = roiData {
            renderer.setupROI(roiData)
        }
    }
    
    // MARK: - Gesture Handling
    
    private func createGestureRecognizer() -> some Gesture {
        SimultaneousGesture(
            // Rotation gesture (horizontal drag)
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    // Horizontal drag = rotation around Z-axis
                    let rotationSensitivity: Float = 0.01
                    rotationZ += Float(value.translation.x) * rotationSensitivity
                    
                    // Vertical drag = zoom (for now)
                    let zoomSensitivity: CGFloat = 0.01
                    let newZoom = max(0.5, min(3.0, localZoom + value.translation.y * zoomSensitivity))
                    localZoom = newZoom
                }
                .onEnded { _ in
                    isDragging = false
                },
            
            // Zoom gesture
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

// MARK: - Metal 3D Renderer

@MainActor
class Metal3DVolumeRenderer: ObservableObject {
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var library: MTLLibrary?
    private var pipelineState: MTLComputePipelineState?
    
    // Volume data
    private var volumeTexture: MTLTexture?
    private var roiMeshes: [Metal3DROIMesh] = []
    
    init() {
        setupMetal()
    }
    
    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ Metal device creation failed")
            return
        }
        
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        
        guard let library = device.makeDefaultLibrary() else {
            print("❌ Metal library creation failed")
            return
        }
        self.library = library
        
        setupVolumeRenderingPipeline()
    }
    
    private func setupVolumeRenderingPipeline() {
        guard let device = device,
              let library = library else { return }
        
        guard let function = library.makeFunction(name: "volumeRender3D") else {
            print("❌ 3D volume render function not found")
            return
        }
        
        do {
            pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            print("❌ 3D pipeline state creation failed: \(error)")
        }
    }
    
    func setupVolume(_ volumeData: VolumeData) {
        guard let device = device else { return }
        
        // Create 3D texture from volume data
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type3D
        textureDescriptor.pixelFormat = .r16Sint
        textureDescriptor.width = volumeData.dimensions.x
        textureDescriptor.height = volumeData.dimensions.y
        textureDescriptor.depth = volumeData.dimensions.z
        textureDescriptor.usage = [.shaderRead]
        
        volumeTexture = device.makeTexture(descriptor: textureDescriptor)
        
        // Copy volume data to texture
        volumeTexture?.replace(
            region: MTLRegionMake3D(0, 0, 0, volumeData.dimensions.x, volumeData.dimensions.y, volumeData.dimensions.z),
            mipmapLevel: 0,
            slice: 0,
            withBytes: volumeData.data,
            bytesPerRow: volumeData.dimensions.x * 2,
            bytesPerImage: volumeData.dimensions.x * volumeData.dimensions.y * 2
        )
    }
    
    func setupROI(_ roiData: MinimalRTStructParser.SimpleRTStructData) {
        // Convert RTStruct contours to 3D meshes
        roiMeshes = roiData.roiStructures.compactMap { roi in
            Metal3DROIMesh.fromROIStructure(roi, device: device)
        }
    }
    
    func render(to texture: MTLTexture, 
                rotationZ: Float,
                crosshairPosition: SIMD3<Float>,
                zoom: CGFloat,
                pan: CGSize) {
        
        guard let commandQueue = commandQueue,
              let pipelineState = pipelineState,
              let volumeTexture = volumeTexture else { return }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(volumeTexture, index: 0)
        encoder.setTexture(texture, index: 1)
        
        // Setup render parameters
        var params = Volume3DRenderParams(
            rotationZ: rotationZ,
            crosshairPosition: crosshairPosition,
            windowCenter: 50.0,   // Default soft tissue window
            windowWidth: 350.0,   // Default soft tissue window
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
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

// MARK: - Render Parameters

struct Volume3DRenderParams {
    let rotationZ: Float
    let crosshairPosition: SIMD3<Float>
    let windowCenter: Float
    let windowWidth: Float
    let zoom: Float
    let panX: Float
    let panY: Float
}

// MARK: - ROI Mesh

struct Metal3DROIMesh {
    let vertices: [SIMD3<Float>]
    let color: SIMD3<Float>
    let name: String
    
    static func fromROIStructure(_ roi: MinimalRTStructParser.SimpleROIStructure, device: MTLDevice?) -> Metal3DROIMesh? {
        // Convert contours to 3D mesh vertices
        var vertices: [SIMD3<Float>] = []
        
        for contour in roi.contours {
            vertices.append(contentsOf: contour.points)
        }
        
        return Metal3DROIMesh(
            vertices: vertices,
            color: roi.displayColor,
            name: roi.roiName
        )
    }
}

// MARK: - Metal View Wrapper

struct Metal3DRenderView: UIViewRepresentable {
    let renderer: Metal3DVolumeRenderer
    let volumeData: VolumeData
    let roiData: MinimalRTStructParser.SimpleRTStructData?
    let rotationZ: Float
    let crosshairPosition: SIMD3<Float>
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
        private var zoom: CGFloat = 1.0
        private var pan: CGSize = .zero
        
        init(renderer: Metal3DVolumeRenderer) {
            self.renderer = renderer
        }
        
        func updateParams(rotationZ: Float, crosshairPosition: SIMD3<Float>, zoom: CGFloat, pan: CGSize) {
            self.rotationZ = rotationZ
            self.crosshairPosition = crosshairPosition
            self.zoom = zoom
            self.pan = pan
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle resize
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable else { return }
            
            renderer.render(
                to: drawable.texture,
                rotationZ: rotationZ,
                crosshairPosition: crosshairPosition,
                zoom: zoom,
                pan: pan
            )
            
            drawable.present()
        }
    }
}
