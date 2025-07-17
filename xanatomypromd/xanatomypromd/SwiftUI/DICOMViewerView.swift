@preconcurrency import SwiftUI
@preconcurrency import MetalKit

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
    
    class Coordinator: NSObject, MTKViewDelegate {
        let viewModel: DICOMViewerViewModel
        private var metalRenderer: MetalRenderer?
        private var currentTexture: MTLTexture?
        private var currentWindowing: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
        
        init(viewModel: DICOMViewerViewModel) {
            self.viewModel = viewModel
            super.init()
            
            // Initialize your existing MetalRenderer
            do {
                self.metalRenderer = try MetalRenderer()
                print("✅ MetalRenderer initialized for SwiftUI")
            } catch {
                print("❌ Failed to initialize MetalRenderer: \(error)")
            }
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle view size changes
            print("📱 MTKView size changed to: \(size)")
        }
        
        func draw(in view: MTKView) {
            print("🎨 Draw called - texture: \(currentTexture != nil ? "✅" : "❌")")
            
            guard let renderer = metalRenderer,
                  let texture = currentTexture else {
                print("⚫ Clearing view - no texture")
                clearView(view)
                return
            }
            
            print("🖼️ Rendering with texture")
            renderWithExistingRenderer(renderer: renderer, texture: texture, view: view)
        }
        
        func updateSlice(_ slice: Int, windowing: CTWindowPresets.WindowLevel) {
            guard let renderer = metalRenderer else {
                print("❌ No MetalRenderer")
                return
            }
            
            print("🔍 Loading slice \(slice) with \(windowing.name) windowing")
            
            // Store current windowing
            self.currentWindowing = windowing
            
            // Get pixel data for this slice from view model
            Task { @MainActor in
                if let pixelData = await viewModel.getPixelData(for: slice) {
                    print("✅ Got pixel data: \(pixelData.columns)×\(pixelData.rows)")
                    
                    do {
                        let texture = try renderer.createTexture(from: pixelData)
                        print("✅ Created texture: \(texture.width)×\(texture.height)")
                        
                        await MainActor.run {
                            self.currentTexture = texture
                            print("✅ Set currentTexture, triggering redraw")
                            self.setNeedsDisplay()
                        }
                    } catch {
                        print("❌ Failed to create texture: \(error)")
                    }
                } else {
                    print("❌ No pixel data for slice \(slice)")
                }
            }
        }
        
        private func renderWithExistingRenderer(renderer: MetalRenderer, texture: MTLTexture, view: MTKView) {
            // Create render config
            let config = MetalRenderer.RenderConfig(
                windowCenter: Float(currentWindowing.center),
                windowWidth: Float(currentWindowing.width)
            )
            
            print("🎨 Rendering with MetalRenderer")
            
            // Use your existing MetalRenderer
            renderer.renderCTImage(
                inputTexture: texture,
                config: config
            ) { windowedTexture in
                guard let windowedTexture = windowedTexture else {
                    print("❌ Windowing failed")
                    return
                }
                
                print("✅ Got windowed texture, converting to UIImage and back")
                
                // Convert to UIImage (this works from your logs)
                if let uiImage = renderer.textureToUIImage(windowedTexture) {
                    print("✅ UIImage created: \(uiImage.size)")
                    
                    // Now convert UIImage back to a Metal texture that matches the drawable
                    DispatchQueue.main.async {
                        self.displayImageSafely(uiImage, in: view)
                    }
                } else {
                    print("❌ UIImage conversion failed")
                }
            }
        }

        // Instead of direct copy, use a render pass to display the image
        private func displayImageSafely(_ image: UIImage, in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let device = view.device,
                  let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer(),
                  let cgImage = image.cgImage else {
                return
            }
            
            // Create texture from UIImage using MTKTextureLoader (this part works)
            let textureLoader = MTKTextureLoader(device: device)
            
            do {
                let sourceTexture = try textureLoader.newTexture(cgImage: cgImage)
                print("✅ Created source texture: \(sourceTexture.width)×\(sourceTexture.height)")
                
                // Use a simple fragment shader to display the texture
                renderTextureToDrawable(sourceTexture: sourceTexture, drawable: drawable, commandBuffer: commandBuffer)
                
            } catch {
                print("❌ MTKTextureLoader failed: \(error)")
                // Fallback to gray screen
                clearToGray(drawable: drawable, commandBuffer: commandBuffer)
            }
        }

        private func renderTextureToDrawable(sourceTexture: MTLTexture, drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer) {
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            
            // For now, let's just clear to a different color to confirm this path works
            // We'll add the actual texture rendering after we confirm this works
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
            
            print("🎯 Render pipeline approach - should show black screen")
        }

        private func clearToGray(drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer) {
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderEncoder.endEncoding()
            }
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        private func displayImage(_ image: UIImage, in view: MTKView) {
            // Convert UIImage back to texture and display it properly
            guard let drawable = view.currentDrawable,
                  let commandBuffer = view.device?.makeCommandQueue()?.makeCommandBuffer() else {
                return
            }
            
            // For now, let's create a simple texture from the UIImage
            guard let cgImage = image.cgImage else { return }
            
            // Create a texture from the UIImage
            let textureLoader = MTKTextureLoader(device: view.device!)
            do {
                let texture = try textureLoader.newTexture(cgImage: cgImage)
                
                // Simple blit to drawable
                let blitEncoder = commandBuffer.makeBlitCommandEncoder()
                blitEncoder?.copy(from: texture, to: drawable.texture)
                blitEncoder?.endEncoding()
                
                commandBuffer.present(drawable)
                commandBuffer.commit()
                
            } catch {
                print("❌ Failed to create texture from UIImage: \(error)")
                // Fallback: just clear the view
                clearView(view)
            }
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
        
        private func setNeedsDisplay() {
            // Trigger a redraw
            // The MTKView will call draw(in:) automatically
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
        
        // Get DICOM files from bundle
        dicomFiles = getDICOMFiles()
        totalSlices = dicomFiles.count
        
        // Parse first file for series info
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
                
                // Pre-load first few slices
                await preloadSlices(0..<min(5, dicomFiles.count))
                
            } catch {
                print("Error loading series info: \(error)")
            }
        }
        
        // Initialize Metal renderer
        if let device = MTLCreateSystemDefaultDevice() {
            do {
                metalRenderer = try MetalRenderer()  // ✅ Add try since it can throw
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
}

// MARK: - Preview

struct DICOMViewerView_Previews: PreviewProvider {
    static var previews: some View {
        DICOMViewerView()
            .preferredColorScheme(.dark)
    }
}
