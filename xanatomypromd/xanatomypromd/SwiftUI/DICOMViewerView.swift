@preconcurrency import SwiftUI
@preconcurrency import MetalKit

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

// MARK: - Main DICOM Viewer Interface

struct DICOMViewerView: View {
    @StateObject private var viewModel = DICOMViewerViewModel()
    @State private var selectedWindowingPreset: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
    @State private var showingPresets = false
    @State private var currentSlice = 0
    @State private var isLoading = true
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // MARK: - Header with Series Info
                    headerView
                    
                    // MARK: - Main Image Display
                    imageDisplayView(geometry: geometry)
                    
                    // MARK: - Controls Section
                    controlsView
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
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("X-Anatomy Pro v2.0")
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let seriesInfo = viewModel.seriesInfo {
                    Text(seriesInfo.patientName ?? "Unknown Patient")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Text(seriesInfo.studyDate ?? "Unknown Date")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Slice Counter
            VStack(alignment: .trailing, spacing: 4) {
                Text("Slice \(currentSlice + 1)/\(viewModel.totalSlices)")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(selectedWindowingPreset.name)
                    .font(.caption)
                    .foregroundColor(.blue)
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
                ProgressView("Loading DICOM Series...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
            } else {
                // Metal-rendered DICOM image
                MetalDICOMImageView(
                    viewModel: viewModel,
                    currentSlice: currentSlice,
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
            .disabled(currentSlice == viewModel.totalSlices - 1)
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
    
    // MARK: - Controls View
    private var controlsView: some View {
        VStack(spacing: 16) {
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
                            .foregroundColor(.white)
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
                
                if viewModel.totalSlices > 1 {
                    Slider(
                        value: Binding(
                            get: { Double(currentSlice) },
                            set: { newValue in
                                currentSlice = Int(newValue)
                                viewModel.navigateToSlice(currentSlice)
                            }
                        ),
                        in: 0...Double(viewModel.totalSlices - 1),
                        step: 1
                    )
                    .accentColor(.blue)
                }
                
                Text("\(viewModel.totalSlices)")
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
    
    // MARK: - Actions
    private func previousSlice() {
        guard currentSlice > 0 else { return }
        withAnimation(.easeInOut(duration: 0.1)) {
            currentSlice -= 1
        }
        viewModel.navigateToSlice(currentSlice)
    }
    
    private func nextSlice() {
        guard currentSlice < viewModel.totalSlices - 1 else { return }
        withAnimation(.easeInOut(duration: 0.1)) {
            currentSlice += 1
        }
        viewModel.navigateToSlice(currentSlice)
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
        // TODO: Show DICOM metadata info sheet
        print("Show DICOM info")
    }
    
}

// MARK: - Metal-based DICOM Image View

struct MetalDICOMImageView: UIViewRepresentable {
    let viewModel: DICOMViewerViewModel
    let currentSlice: Int
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
        context.coordinator.updateSlice(currentSlice, windowing: windowingPreset)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    // MARK: - Cleaned Up Coordinator Class for DICOMViewerView.swift
    // Replace the existing Coordinator class with this version

    class Coordinator: NSObject, MTKViewDelegate {
        let viewModel: DICOMViewerViewModel
        private var metalRenderer: MetalRenderer?
        private var currentTexture: MTLTexture?
        private var currentWindowing: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
        
        // NEW: Add these properties
         private var aspectRatioBuffer: MTLBuffer?
         private var lastViewportSize: CGSize = .zero
        
        // Metal pipeline for texture display
        private var displayPipelineState: MTLRenderPipelineState?
        private var vertexBuffer: MTLBuffer?
        
        // Debug flag - set to true only when debugging
        private let DEBUG_LOGGING = false
        
        init(viewModel: DICOMViewerViewModel) {
            self.viewModel = viewModel
            super.init()
            
            // Initialize MetalRenderer
            do {
                self.metalRenderer = try MetalRenderer()
                setupDisplayPipeline()
                print("✅ MetalRenderer initialized for SwiftUI")
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
            
            // Create render pipeline for displaying textures
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_display_texture")
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm // Match drawable format
            
            do {
                displayPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("✅ Display pipeline created successfully")
            } catch {
                print("❌ Failed to create display pipeline: \(error)")
            }
            
            // Create vertex buffer for full-screen quad
            let vertices: [Float] = [
                // Position (x,y)  TexCoord (u,v)
                -1.0, -1.0,        0.0, 1.0,  // Bottom-left
                 1.0, -1.0,        1.0, 1.0,  // Bottom-right
                -1.0,  1.0,        0.0, 0.0,  // Top-left
                 1.0,  1.0,        1.0, 0.0   // Top-right
            ]
            
            vertexBuffer = device.makeBuffer(bytes: vertices,
                                            length: vertices.count * MemoryLayout<Float>.size,
                                            options: [])
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            if DEBUG_LOGGING {
                print("📱 MTKView size changed to: \(size)")
            }
            
            updateAspectRatio(for: size)  // ADD this line
        }
        
        func draw(in view: MTKView) {
            guard let texture = currentTexture else {
                clearView(view)
                return
            }
            
            renderTextureWithPipeline(texture: texture, view: view)
        }
        
        func updateSlice(_ slice: Int, windowing: CTWindowPresets.WindowLevel) {
            guard let renderer = metalRenderer else {
                print("❌ No MetalRenderer available")
                return
            }
            
            if DEBUG_LOGGING {
                print("🔍 Loading slice \(slice) with \(windowing.name) windowing")
            }
            
            self.currentWindowing = windowing
            
            Task { @MainActor in
                if let pixelData = await viewModel.getPixelData(for: slice) {
                    if DEBUG_LOGGING {
                        print("✅ Got pixel data: \(pixelData.columns)×\(pixelData.rows)")
                    }
                    
                    do {
                        let inputTexture = try renderer.createTexture(from: pixelData)
                        
                        if DEBUG_LOGGING {
                            print("✅ Created input texture")
                        }
                        
                        // Apply windowing
                        let config = MetalRenderer.RenderConfig(
                            windowCenter: Float(windowing.center),
                            windowWidth: Float(windowing.width)
                        )
                        
                        renderer.renderCTImage(
                            inputTexture: inputTexture,
                            config: config
                        ) { [weak self] windowedTexture in
                            guard let self = self, let windowedTexture = windowedTexture else {
                                print("❌ Windowing failed for slice \(slice)")
                                return
                            }
                            
                            DispatchQueue.main.async {
                                self.currentTexture = windowedTexture
                                
                                if self.DEBUG_LOGGING {
                                    print("✅ Set windowed texture for display")
                                }
                            }
                        }
                    } catch {
                        print("❌ Failed to process slice \(slice): \(error)")
                    }
                } else {
                    print("❌ No pixel data available for slice \(slice)")
                }
            }
        }
        
        private func renderTextureWithPipeline(texture: MTLTexture, view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let pipelineState = displayPipelineState,
                  let vertexBuffer = vertexBuffer,
                  let commandBuffer = view.device?.makeCommandQueue()?.makeCommandBuffer() else {
                print("❌ Missing Metal components for pipeline rendering")
                clearView(view)
                return
            }
            
            // Ensure aspect ratio is updated for current view size
            let currentSize = view.drawableSize
            if currentSize != lastViewportSize {
                updateAspectRatio(for: currentSize)
            }
            
            guard let aspectBuffer = aspectRatioBuffer else {
                print("❌ No aspect ratio buffer")
                clearView(view)
                return
            }
            
            // Create render pass
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                print("❌ Failed to create render encoder")
                return
            }
            
            // Setup render pipeline with aspect ratio correction
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(aspectBuffer, offset: 0, index: 1)  // NEW: Aspect ratio uniforms
            renderEncoder.setFragmentTexture(texture, index: 0)
            
            // Draw full-screen quad with corrected aspect ratio
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
            
            // Present drawable
            commandBuffer.present(drawable)
            commandBuffer.commit()
            
//            print("🎨 Rendered texture with aspect ratio correction")
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
            
            // Calculate viewport aspect ratio
            let viewportAspect = Float(viewSize.width / viewSize.height)
            let imageAspect: Float = 1.0  // DICOM images are 512×512 (square)
            
            // Calculate scaling factors for 1:1 pixel aspect ratio
            let scaleX: Float
            let scaleY: Float
            
            if viewportAspect > imageAspect {
                // Viewport is wider than image (landscape-ish)
                scaleX = imageAspect / viewportAspect
                scaleY = 1.0
            } else {
                // Viewport is taller than image (portrait-ish)
                scaleX = 1.0
                scaleY = viewportAspect / imageAspect
            }
            
            // Create aspect ratio uniforms
            var aspectUniforms = AspectRatioUniforms(
                scaleX: scaleX,
                scaleY: scaleY,
                offset: SIMD2<Float>(0, 0)
            )
            
            // Update or create buffer
            aspectRatioBuffer = device.makeBuffer(
                bytes: &aspectUniforms,
                length: MemoryLayout<AspectRatioUniforms>.size,
                options: []
            )
            
            lastViewportSize = viewSize
            
            print("📐 Aspect ratio updated: Scale X=\(scaleX), Y=\(scaleY)")
        }

    }
}
// MARK: - View Model

@MainActor
class DICOMViewerViewModel: ObservableObject {
    @Published var seriesInfo: DICOMSeriesInfo?
    @Published var totalSlices: Int = 0
    @Published var currentSlice: Int = 0
    @Published var isLoading: Bool = true
    
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
        
        // Get DICOM files from bundle (original filename order)
        let originalFiles = getDICOMFiles()
        print("📁 Found \(originalFiles.count) DICOM files")
        
        // NEW: Sort by anatomical position instead of filename
        dicomFiles = await sortDICOMFilesByAnatomicalPosition(originalFiles)
        totalSlices = dicomFiles.count
        
        // Parse first file for series info (rest of method unchanged)
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
                
                // Pre-load first few slices in correct order
                await preloadSlices(0..<min(5, dicomFiles.count))
                
            } catch {
                print("Error loading series info: \(error)")
            }
        }
        
        // Initialize Metal renderer
        if let device = MTLCreateSystemDefaultDevice() {
            do {
                metalRenderer = try MetalRenderer()
                print("✅ DICOM series loaded with proper anatomical ordering")
            } catch {
                print("Failed to initialize MetalRenderer: \(error)")
            }
        }
        
        isLoading = false
    }
    
    func navigateToSlice(_ slice: Int) {
        guard slice >= 0 && slice < totalSlices else { return }
        
        currentSlice = slice
        
        // Pre-load adjacent slices in background
        Task {
            let preloadRange = max(0, slice - 2)..<min(totalSlices, slice + 3)
            await preloadSlices(preloadRange)
        }
    }
    
    
    func prepareSliceForRendering(_ slice: Int, windowing: CTWindowPresets.WindowLevel) async {
        // Just ensure pixel data is loaded
        if pixelDataCache[slice] == nil {
            await loadPixelData(for: slice)
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
        print("🔍 Loading slice \(sliceIndex)")
        
        guard sliceIndex >= 0 && sliceIndex < dicomFiles.count else {
            print("❌ Invalid slice index: \(sliceIndex)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: dicomFiles[sliceIndex])
            let dataset = try DICOMParser.parse(data)
            
            if let pixelData = DICOMParser.extractPixelData(from: dataset) {
                print("✅ Pixel data: \(pixelData.columns)×\(pixelData.rows)")
                return pixelData
            } else {
                print("❌ No pixel data extracted")
            }
        } catch {
            print("❌ Error: \(error)")
        }
        
        return nil
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
          
          // Sort by anatomical position: Superior (top) to Inferior (bottom)
          let sortedInfos = sliceInfos.sorted { slice1, slice2 in
              // Higher Z = slice 1 (top of head)
              return slice1.sliceLocation > slice2.sliceLocation
          }
          
          // Debug output
          print("📋 First 5 slices after sorting:")
          for (index, info) in sortedInfos.prefix(5).enumerated() {
              let shortName = String(info.fileURL.lastPathComponent.suffix(15))
              print("   \(index + 1): \(shortName) | Loc: \(String(format: "%.1f", info.sliceLocation))")
          }
          
          return sortedInfos.map { $0.fileURL }
      }
  }


// MARK: - Preview

struct DICOMViewerView_Previews: PreviewProvider {
    static var previews: some View {
        DICOMViewerView()
            .preferredColorScheme(.dark)
    }
}
