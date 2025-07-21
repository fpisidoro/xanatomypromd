@preconcurrency import SwiftUI
@preconcurrency import MetalKit

struct RescaleParameters {
    let slope: Float
    let intercept: Float
    
    init(slope: Float = 1.0, intercept: Float = 0.0) {
        self.slope = slope
        self.intercept = intercept
    }
}

struct DICOMSliceInfo {
    let fileURL: URL
    let sliceLocation: Double
    let instanceNumber: Int
}

// MARK: - Aspect Ratio Support
struct AspectRatioUniforms {
    let scaleX: Float
    let scaleY: Float
    let offset: SIMD2<Float>
    
    init(scaleX: Float, scaleY: Float, offset: SIMD2<Float> = SIMD2<Float>(0, 0)) {
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.offset = offset
    }
}

// MARK: - Main DICOM Viewer Interface with MPR

struct DICOMViewerView: View {
    @StateObject private var viewModel = DICOMViewerViewModel()
    @State private var selectedWindowingPreset: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
    @State private var currentPlane: MPRPlane = .axial  // NEW: Current viewing plane
    @State private var currentSlice = 0
    @State private var isLoading = true
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // MARK: - Header with Series Info + Plane Info
                    headerView
                    
                    // MARK: - Main Image Display
                    imageDisplayView(geometry: geometry)
                        .frame(height: geometry.size.height * 0.7)  // More space for controls
                    
                    // MARK: - Controls Section
                    controlsView
                        .frame(height: geometry.size.height * 0.3)
                }
                .background(Color.black)
                .navigationBarHidden(true)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            Task {
                await viewModel.loadDICOMSeries()
                isLoading = false
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header View with Plane Info
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("X-Anatomy Pro v2.0 - MPR")
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let seriesInfo = viewModel.seriesInfo {
                    Text(seriesInfo.patientName ?? "Unknown Patient")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // NEW: Current Plane and Slice Info
            VStack(alignment: .trailing, spacing: 4) {
                Text(currentPlane.rawValue)
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Text("Slice \(currentSlice + 1)/\(getMaxSlicesForPlane())")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text(selectedWindowingPreset.name)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Image Display View
    private func imageDisplayView(geometry: GeometryProxy) -> some View {
        ZStack {
            if isLoading {
                VStack {
                    ProgressView("Loading DICOM Series...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                    
                    if viewModel.isVolumeLoaded {
                        Text("3D Volume Ready!")
                            .foregroundColor(.green)
                            .padding(.top, 8)
                    }
                }
            } else {
                // Metal-rendered DICOM image with MPR support
                MetalDICOMImageView(
                    viewModel: viewModel,
                    currentSlice: currentSlice,
                    currentPlane: currentPlane,  // NEW: Pass current plane
                    windowingPreset: selectedWindowingPreset
                )
                .scaleEffect(scale)
                .offset(dragOffset)
                .clipped()
                .gesture(DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { _ in
                        withAnimation(.spring()) {
                            dragOffset = .zero
                        }
                    }
                )
                .gesture(MagnificationGesture()
                    .onChanged { value in
                        scale = lastScale * value
                    }
                    .onEnded { value in
                        lastScale = scale
                        withAnimation(.spring()) {
                            scale = max(0.5, min(scale, 3.0))
                            lastScale = scale
                        }
                    }
                )
                
                // Slice navigation overlay
                sliceNavigationOverlay(geometry: geometry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
    
    // MARK: - Slice Navigation Overlay
    private func sliceNavigationOverlay(geometry: GeometryProxy) -> some View {
        HStack {
            // Left side - Previous slice
            Button(action: previousSlice) {
                Image(systemName: "chevron.left")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: geometry.size.width * 0.2, height: geometry.size.height)
            .contentShape(Rectangle())
            .disabled(currentSlice == 0)
            
            Spacer()
            
            // Right side - Next slice
            Button(action: nextSlice) {
                Image(systemName: "chevron.right")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: geometry.size.width * 0.2, height: geometry.size.height)
            .contentShape(Rectangle())
            .disabled(currentSlice == getMaxSlicesForPlane() - 1)
        }
        .background(Color.clear)
        .gesture(
            DragGesture()
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.height > threshold {
                        previousSlice()
                    } else if value.translation.height < -threshold {
                        nextSlice()
                    }
                }
        )
    }
    
    // MARK: - Controls View with MPR Plane Switching
    private var controlsView: some View {
        VStack(spacing: 12) {
            // NEW: MPR Plane Selection
            mprPlaneSelector
            
            // Windowing Presets
            windowingPresetsView
            
            // Slice Slider
            sliceSliderView
            
            // Action Buttons
            actionButtonsView
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
    
    // MARK: - NEW: MPR Plane Selector
    private var mprPlaneSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Anatomical Plane")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                ForEach([MPRPlane.axial, MPRPlane.sagittal, MPRPlane.coronal], id: \.self) { plane in
                    Button(action: {
                        switchToPlane(plane)
                    }) {
                        VStack(spacing: 4) {
                            Text(plane.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            
                            Text(getPlaneDescription(plane))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            currentPlane == plane
                                ? Color.blue
                                : Color.gray.opacity(0.3)
                        )
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    // MARK: - Windowing Presets
    private var windowingPresetsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CT Windowing")
                .font(.headline)
                .foregroundColor(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CTWindowPresets.all, id: \.name) { preset in
                        Button(action: {
                            selectedWindowingPreset = preset
                        }) {
                            VStack(spacing: 4) {
                                Text(preset.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                
                                Text("C:\(Int(preset.center)) W:\(Int(preset.width))")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedWindowingPreset.name == preset.name
                                    ? Color.blue
                                    : Color.gray.opacity(0.3)
                            )
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Slice Slider
    private var sliceSliderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Slice Navigation")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack {
                Text("1")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                let maxSlices = getMaxSlicesForPlane()
                if maxSlices > 1 {
                    Slider(
                        value: Binding(
                            get: { Double(currentSlice) },
                            set: { newValue in
                                currentSlice = Int(newValue)
                                navigateToSlice(currentSlice)
                            }
                        ),
                        in: 0...Double(maxSlices - 1),
                        step: 1
                    )
                    .accentColor(.blue)
                }
                
                Text("\(maxSlices)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
    
    // MARK: - Action Buttons
    private var actionButtonsView: some View {
        HStack(spacing: 20) {
            Button(action: resetView) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Reset")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.3))
                .cornerRadius(8)
            }
            
            Button(action: toggleFullscreen) {
                HStack {
                    Image(systemName: scale > 1 ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    Text(scale > 1 ? "Fit" : "Zoom")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.3))
                .cornerRadius(8)
            }
            
            Spacer()
            
            Button(action: showInfo) {
                HStack {
                    Image(systemName: "info.circle")
                    Text("Info")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.7))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - NEW: MPR Plane Functions
    
    private func switchToPlane(_ plane: MPRPlane) {
        print("🔄 Switching to \(plane.rawValue) plane")
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPlane = plane
            currentSlice = getMaxSlicesForPlane() / 2  // Start at center slice
        }
        navigateToSlice(currentSlice)
    }
    
    private func getMaxSlicesForPlane() -> Int {
        switch currentPlane {
        case .axial:
            return viewModel.totalSlices  // 53 slices
        case .sagittal:
            return 512  // Image width becomes slice count
        case .coronal:
            return 512  // Image height becomes slice count
        }
    }
    
    private func getPlaneDescription(_ plane: MPRPlane) -> String {
        switch plane {
        case .axial:
            return "Head Slices"
        case .sagittal:
            return "Side View"
        case .coronal:
            return "Front View"
        }
    }
    
    // MARK: - Navigation Actions
    private func previousSlice() {
        guard currentSlice > 0 else { return }
        withAnimation(.easeInOut(duration: 0.1)) {
            currentSlice -= 1
        }
        navigateToSlice(currentSlice)
    }
    
    private func nextSlice() {
        guard currentSlice < getMaxSlicesForPlane() - 1 else { return }
        withAnimation(.easeInOut(duration: 0.1)) {
            currentSlice += 1
        }
        navigateToSlice(currentSlice)
    }
    
    private func navigateToSlice(_ slice: Int) {
        viewModel.navigateToSlice(slice, plane: currentPlane)
    }
    
    private func resetView() {
        withAnimation(.spring()) {
            scale = 1.0
            lastScale = 1.0
            dragOffset = .zero
        }
    }
    
    private func toggleFullscreen() {
        withAnimation(.spring()) {
            if scale > 1 {
                scale = 1.0
                lastScale = 1.0
            } else {
                scale = 2.0
                lastScale = 2.0
            }
        }
    }
    
    private func showInfo() {
        print("🔍 Current plane: \(currentPlane.rawValue)")
        print("🔍 Current slice: \(currentSlice)")
        print("🔍 Volume loaded: \(viewModel.isVolumeLoaded)")
    }
}

// MARK: - Enhanced Metal-based DICOM Image View with MPR

struct MetalDICOMImageView: UIViewRepresentable {
    let viewModel: DICOMViewerViewModel
    let currentSlice: Int
    let currentPlane: MPRPlane  // NEW: Current viewing plane
    let windowingPreset: CTWindowPresets.WindowLevel
    
    func makeUIView(context: Context) -> MTKView {
        let metalView = MTKView()
        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.delegate = context.coordinator
        metalView.backgroundColor = UIColor.black
        metalView.isOpaque = false
        return metalView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateSlice(currentSlice, plane: currentPlane, windowing: windowingPreset)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    // MARK: - Enhanced Coordinator with MPR Support
    class Coordinator: NSObject, MTKViewDelegate {
        let viewModel: DICOMViewerViewModel
        private var metalRenderer: MetalRenderer?
        private var currentTexture: MTLTexture?
        private var currentWindowing: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
        private var currentPlane: MPRPlane = .axial
        
        // Metal pipeline for texture display
        private var displayPipelineState: MTLRenderPipelineState?
        private var vertexBuffer: MTLBuffer?
        private var aspectRatioBuffer: MTLBuffer?
        private var lastViewportSize: CGSize = .zero
        
        init(viewModel: DICOMViewerViewModel) {
            self.viewModel = viewModel
            super.init()
            
            do {
                self.metalRenderer = try MetalRenderer()
                setupDisplayPipeline()
                print("✅ MetalRenderer initialized for SwiftUI MPR")
            } catch {
                print("❌ Failed to initialize MetalRenderer: \(error)")
            }
        }
        
        private func setupDisplayPipeline() {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let library = device.makeDefaultLibrary() else {
                print("❌ Failed to create Metal device or library")
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_display_texture")
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            do {
                displayPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("✅ Display pipeline created successfully")
            } catch {
                print("❌ Failed to create display pipeline: \(error)")
            }
            
            let vertices: [Float] = [
                -1.0, -1.0,        0.0, 1.0,
                 1.0, -1.0,        1.0, 1.0,
                -1.0,  1.0,        0.0, 0.0,
                 1.0,  1.0,        1.0, 0.0
            ]
            
            vertexBuffer = device.makeBuffer(bytes: vertices,
                                            length: vertices.count * MemoryLayout<Float>.size,
                                            options: [])
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            updateAspectRatio(for: size)
        }
        
        func draw(in view: MTKView) {
            guard let texture = currentTexture else {
                clearView(view)
                return
            }
            
            renderTextureWithPipeline(texture: texture, view: view)
        }
        
        // NEW: Enhanced update method with MPR plane support
        func updateSlice(_ slice: Int, plane: MPRPlane, windowing: CTWindowPresets.WindowLevel) {
            guard let renderer = metalRenderer else {
                print("❌ No MetalRenderer available")
                return
            }
            
            print("🔍 Loading \(plane.rawValue) slice \(slice) with \(windowing.name) windowing")
            
            self.currentWindowing = windowing
            self.currentPlane = plane
            
            // FIXED: Update aspect ratio when plane changes
            if plane != currentPlane {
                updateAspectRatio(for: lastViewportSize)
            }
            
            Task { @MainActor in
                // Handle different planes
                switch plane {
                case .axial:
                    // Original axial slice from DICOM files
                    if let pixelData = await viewModel.getPixelData(for: slice) {
                        await renderPixelData(pixelData, with: windowing, using: renderer)
                    }
                    
                case .sagittal, .coronal:
                    // NEW: MPR slices from 3D volume
                    if await viewModel.isVolumeLoaded {
                        await renderMPRSlice(plane: plane, slice: slice, windowing: windowing)
                    } else {
                        print("⚠️ 3D volume not loaded for MPR")
                    }
                }
            }
        }
        
        // NEW: Render MPR slice from 3D volume
        private func renderMPRSlice(plane: MPRPlane, slice: Int, windowing: CTWindowPresets.WindowLevel) async {
            guard let volumeRenderer = await viewModel.volumeRenderer else {
                print("❌ No volume renderer available")
                return
            }
            
            // Convert slice index to normalized position [0, 1]
            let maxSlices = await getMaxSlicesForPlane(plane)
            let normalizedPosition = Float(slice) / Float(maxSlices - 1)
            
            print("🎬 Generating \(plane.rawValue) slice at position \(normalizedPosition)")
            
            let config = MetalVolumeRenderer.MPRConfig(
                plane: plane,
                sliceIndex: normalizedPosition,
                windowCenter: Float(windowing.center),
                windowWidth: Float(windowing.width)
            )
            
            volumeRenderer.generateMPRSlice(config: config) { [weak self] texture in
                guard let self = self, let texture = texture else {
                    print("❌ MPR slice generation failed")
                    return
                }
                
                DispatchQueue.main.async {
                    self.currentTexture = texture
                    print("✅ MPR \(plane.rawValue) slice ready for display")
                }
            }
        }
        
        private func renderPixelData(_ pixelData: PixelData, with windowing: CTWindowPresets.WindowLevel, using renderer: MetalRenderer) async {
            do {
                let inputTexture = try renderer.createTexture(from: pixelData)
                let rescaleParams = await viewModel.getRescaleParameters(for: 0)
                
                let config = MetalRenderer.RenderConfig(
                    windowCenter: Float(windowing.center),
                    windowWidth: Float(windowing.width),
                    rescaleSlope: rescaleParams.slope,
                    rescaleIntercept: rescaleParams.intercept
                )
                
                renderer.renderCTImage(
                    inputTexture: inputTexture,
                    config: config
                ) { [weak self] windowedTexture in
                    guard let self = self, let windowedTexture = windowedTexture else { return }
                    
                    DispatchQueue.main.async {
                        self.currentTexture = windowedTexture
                    }
                }
            } catch {
                print("❌ Failed to render pixel data: \(error)")
            }
        }
        
        private func getMaxSlicesForPlane(_ plane: MPRPlane) async -> Int {
            switch plane {
            case .axial:
                return await viewModel.totalSlices
            case .sagittal, .coronal:
                return 512
            }
        }
        
        private func renderTextureWithPipeline(texture: MTLTexture, view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let pipelineState = displayPipelineState,
                  let vertexBuffer = vertexBuffer,
                  let commandBuffer = view.device?.makeCommandQueue()?.makeCommandBuffer() else {
                clearView(view)
                return
            }
            
            let currentSize = view.drawableSize
            if currentSize != lastViewportSize {
                updateAspectRatio(for: currentSize)
            }
            
            guard let aspectBuffer = aspectRatioBuffer else {
                clearView(view)
                return
            }
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(aspectBuffer, offset: 0, index: 1)
            renderEncoder.setFragmentTexture(texture, index: 0)
            
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        private func clearView(_ view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = view.device?.makeCommandQueue()?.makeCommandBuffer() else {
                return
            }
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderEncoder.endEncoding()
            }
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        private func updateAspectRatio(for viewSize: CGSize) {
            guard let device = MTLCreateSystemDefaultDevice(),
                  viewSize.width > 0 && viewSize.height > 0 else { return }
            
            let viewportAspect = Float(viewSize.width / viewSize.height)
            
            // FIXED: Calculate proper aspect ratio based on current plane
            let imageAspect: Float
            switch currentPlane {
            case .axial:
                imageAspect = 1.0  // 512×512 = square
            case .sagittal, .coronal:
                imageAspect = 512.0 / 53.0  // 512×53 = very wide (9.66:1)
            }
            
            let scaleX: Float
            let scaleY: Float
            
            if viewportAspect > imageAspect {
                scaleX = imageAspect / viewportAspect
                scaleY = 1.0
            } else {
                scaleX = 1.0
                scaleY = viewportAspect / imageAspect
            }
            
            var aspectUniforms = AspectRatioUniforms(
                scaleX: scaleX,
                scaleY: scaleY,
                offset: SIMD2<Float>(0, 0)
            )
            
            aspectRatioBuffer = device.makeBuffer(
                bytes: &aspectUniforms,
                length: MemoryLayout<AspectRatioUniforms>.size,
                options: []
            )
            
            lastViewportSize = viewSize
            
            print("📐 Aspect ratio updated for \(currentPlane.rawValue): Scale X=\(scaleX), Y=\(scaleY)")
        }
    }
}

// MARK: - Enhanced View Model with MPR Support

@MainActor
class DICOMViewerViewModel: ObservableObject {
    @Published var seriesInfo: DICOMSeriesInfo?
    @Published var totalSlices: Int = 0
    @Published var currentSlice: Int = 0
    @Published var isLoading: Bool = true
    @Published var volumeRenderer: MetalVolumeRenderer?
    @Published var currentPlane: MPRPlane = .axial
    @Published var isVolumeLoaded: Bool = false
    @Published var volumeLoadingProgress: Double = 0.0
    
    private var dicomFiles: [URL] = []
    private var parsedDatasets: [DICOMDataset] = []
    private var pixelDataCache: [Int: PixelData] = [:]
    private var metalRenderer: MetalRenderer?
    
    struct DICOMSeriesInfo {
        let patientName: String?
        let studyDate: String?
        let seriesDescription: String?
        let modality: String?
    }
    
    func loadDICOMSeries() async {
        isLoading = true
        
        let originalFiles = getDICOMFiles()
        print("📁 Found \(originalFiles.count) DICOM files")
        
        dicomFiles = await sortDICOMFilesByAnatomicalPosition(originalFiles)
        totalSlices = dicomFiles.count
        
        if let firstFile = dicomFiles.first {
            do {
                let data = try Data(contentsOf: firstFile)
                let dataset = try DICOMParser.parse(data)
                
                seriesInfo = DICOMSeriesInfo(
                    patientName: dataset.patientName,
                    studyDate: dataset.studyDate,
                    seriesDescription: dataset.getString(tag: .seriesDescription),
                    modality: dataset.getString(tag: .modality)
                )
                
                await preloadSlices(0..<min(5, dicomFiles.count))
                
            } catch {
                print("Error loading series info: \(error)")
            }
        }
        
        if let _ = MTLCreateSystemDefaultDevice() {
            do {
                metalRenderer = try MetalRenderer()
                print("✅ DICOM series loaded with proper anatomical ordering")
            } catch {
                print("Failed to initialize MetalRenderer: \(error)")
            }
        }
        
        isLoading = false
        await loadVolumeForMPR()
    }
    
    // NEW: Enhanced navigation with plane support
    func navigateToSlice(_ slice: Int, plane: MPRPlane) {
        guard slice >= 0 else { return }
        
        currentSlice = slice
        currentPlane = plane
        
        // Only preload for axial plane (uses DICOM files)
        if plane == .axial {
            let maxSlices = totalSlices
            guard slice < maxSlices else { return }
            
            Task {
                let preloadRange = max(0, slice - 2)..<min(maxSlices, slice + 3)
                await preloadSlices(preloadRange)
            }
        }
    }
    
    private func preloadSlices(_ range: Range<Int>) async {
        for index in range {
            if pixelDataCache[index] == nil {
                await loadPixelData(for: index)
            }
        }
    }
    
    func getPixelData(for sliceIndex: Int) async -> PixelData? {
        guard sliceIndex >= 0 && sliceIndex < dicomFiles.count else { return nil }
        
        do {
            let data = try Data(contentsOf: dicomFiles[sliceIndex])
            let dataset = try DICOMParser.parse(data)
            return DICOMParser.extractPixelData(from: dataset)
        } catch {
            print("❌ Error: \(error)")
            return nil
        }
    }
    
    private func loadPixelData(for index: Int) async {
        guard index >= 0 && index < dicomFiles.count else { return }
        
        do {
            let data = try Data(contentsOf: dicomFiles[index])
            let dataset = try DICOMParser.parse(data)
            
            if let pixelData = DICOMParser.extractPixelData(from: dataset) {
                pixelDataCache[index] = pixelData
            }
        } catch {
            print("Error loading pixel data for slice \(index): \(error)")
        }
    }
    
    private func getDICOMFiles() -> [URL] {
        guard let bundlePath = Bundle.main.resourcePath else { return [] }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: bundlePath),
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            return fileURLs.filter {
                $0.pathExtension.lowercased() == "dcm" ||
                $0.lastPathComponent.contains("2.16.840.1.114362")
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
        } catch {
            print("Error reading DICOM files: \(error)")
            return []
        }
    }
    
    private func sortDICOMFilesByAnatomicalPosition(_ files: [URL]) async -> [URL] {
        print("📊 Sorting \(files.count) DICOM files by anatomical position...")
        
        var sliceInfos: [DICOMSliceInfo] = []
        
        for (index, file) in files.enumerated() {
            do {
                let data = try Data(contentsOf: file)
                let dataset = try DICOMParser.parse(data)
                
                let sliceLocation = dataset.getDouble(tag: .sliceLocation) ?? Double(index)
                let instanceNumber = Int(dataset.getUInt16(tag: .instanceNumber) ?? UInt16(index))
                
                let sliceInfo = DICOMSliceInfo(
                    fileURL: file,
                    sliceLocation: sliceLocation,
                    instanceNumber: instanceNumber
                )
                
                sliceInfos.append(sliceInfo)
                
            } catch {
                print("⚠️  Could not parse slice info from \(file.lastPathComponent): \(error)")
                let fallbackInfo = DICOMSliceInfo(
                    fileURL: file,
                    sliceLocation: Double(index),
                    instanceNumber: index
                )
                sliceInfos.append(fallbackInfo)
            }
        }
        
        let sortedInfos = sliceInfos.sorted { slice1, slice2 in
            return slice1.sliceLocation > slice2.sliceLocation
        }
        
        print("📋 First 5 slices after sorting:")
        for (index, info) in sortedInfos.prefix(5).enumerated() {
            let shortName = String(info.fileURL.lastPathComponent.suffix(15))
            print("   \(index + 1): \(shortName) | Loc: \(String(format: "%.1f", info.sliceLocation))")
        }
        
        return sortedInfos.map { $0.fileURL }
    }
    
    func getRescaleParameters(for sliceIndex: Int) async -> RescaleParameters {
        guard sliceIndex >= 0 && sliceIndex < dicomFiles.count else {
            return RescaleParameters()
        }
        
        do {
            let data = try Data(contentsOf: dicomFiles[sliceIndex])
            let dataset = try DICOMParser.parse(data)
            
            let slope = Float(dataset.getDouble(tag: .rescaleSlope) ?? 1.0)
            let intercept = Float(dataset.getDouble(tag: .rescaleIntercept) ?? 0.0)
            
            return RescaleParameters(slope: slope, intercept: intercept)
            
        } catch {
            print("❌ Error extracting rescale parameters: \(error)")
            return RescaleParameters()
        }
    }
    
    func loadVolumeForMPR() async {
        print("🧊 Loading 3D volume for MPR...")
        
        await MainActor.run {
            volumeLoadingProgress = 0.0
        }
        
        do {
            let renderer = try MetalVolumeRenderer()
            
            await MainActor.run {
                volumeRenderer = renderer
                volumeLoadingProgress = 0.2
            }
            
            let allFiles = getDICOMFiles()
            let volumeData = try await MetalVolumeRenderer.loadVolumeFromDICOMFiles(allFiles)
            
            await MainActor.run {
                volumeLoadingProgress = 0.8
            }
            
            try renderer.loadVolume(volumeData)
            
            await MainActor.run {
                isVolumeLoaded = true
                volumeLoadingProgress = 1.0
            }
            
            print("✅ 3D volume loaded successfully for MPR")
            
        } catch {
            print("❌ Volume loading failed: \(error)")
            await MainActor.run {
                volumeLoadingProgress = 0.0
            }
        }
    }
}

// MARK: - Preview

struct DICOMViewerView_Previews: PreviewProvider {
    static var previews: some View {
        DICOMViewerView()
            .preferredColorScheme(.dark)
    }
}
