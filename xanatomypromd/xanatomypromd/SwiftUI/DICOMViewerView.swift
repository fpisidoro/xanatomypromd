@preconcurrency import SwiftUI
@preconcurrency import MetalKit
import Foundation
import Combine
import Metal

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

// MARK: - Main DICOM Viewer Interface with MPR and ROI Integration

struct DICOMViewerView: View {
    @StateObject private var viewModel = DICOMViewerViewModel()
    @StateObject private var roiManager = ROIIntegrationManager()
    @State private var selectedWindowingPreset: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
    @State private var currentPlane: MPRPlane = .axial
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
                    
                    // MARK: - Main Image Display WITH ROI SUPPORT
                    imageDisplayViewWithROI(geometry: geometry)
                        .frame(height: geometry.size.height * 0.6)
                    
                    // MARK: - ROI Controls Section
                    roiControlsView
                        .frame(height: geometry.size.height * 0.15)
                    
                    // MARK: - Controls Section
                    controlsView
                        .frame(height: geometry.size.height * 0.25)
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
                
                // CRITICAL: Connect RTStruct data to ROI manager
                if let rtStructData = viewModel.getRTStructData() {
                    roiManager.loadRTStructData(rtStructData)
                    print("🎨 RTStruct data connected to ROI overlay system")
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header View with Plane Info
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("X-Anatomy Pro v2.0 - MPR with ROI")
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let seriesInfo = viewModel.seriesInfo {
                    Text(seriesInfo.patientName ?? "Unknown Patient")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Plane and slice info
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(currentPlane.rawValue.capitalized)")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Slice \(currentSlice + 1)/\(getMaxSlicesForPlane())")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
        .background(Color.black.opacity(0.8))
    }
    
    // UPDATED: Image display with ROI integration
    private func imageDisplayViewWithROI(geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            ZStack {
                if !isLoading {
                    MetalDICOMImageView(
                        viewModel: viewModel,
                        roiManager: roiManager,  // PASS ROI MANAGER
                        currentSlice: currentSlice,
                        currentPlane: currentPlane,
                        windowingPreset: selectedWindowingPreset
                    )
                    .scaleEffect(scale)
                    .offset(dragOffset)
                    .gesture(
                        SimultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { _ in
                                    // Reset or constrain drag offset if needed
                                },
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { value in
                                    lastScale = scale
                                }
                        )
                    )
                } else {
                    ProgressView("Loading DICOM Series...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipped()
        }
    }
    
    // NEW: ROI Controls Section
    private var roiControlsView: some View {
        VStack(spacing: 4) {
            HStack {
                Text("ROI Overlays")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Toggle("Show ROIs", isOn: $roiManager.isROIVisible)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
            }
            
            if roiManager.isROIVisible {
                HStack {
                    Text("Opacity:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Slider(
                        value: $roiManager.globalROIOpacity,
                        in: 0.0...1.0,
                        step: 0.1
                    ) {
                        Text("ROI Opacity")
                    }
                    .accentColor(.blue)
                    
                    Text("\(Int(roiManager.globalROIOpacity * 100))%")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(width: 40)
                }
                
                // ROI Statistics
                if let stats = roiManager.getROIStatistics() {
                    HStack {
                        Text("ROIs: \(stats.visibleROIs)/\(stats.totalROIs)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text("Contours: \(stats.totalContours)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text("Points: \(stats.totalPoints)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(.horizontal)
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Controls Section
    private var controlsView: some View {
        VStack(spacing: 12) {
            // Windowing Presets
            HStack {
                Text("Windowing:")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Picker("Windowing", selection: $selectedWindowingPreset) {
                    Text("Soft Tissue").tag(CTWindowPresets.softTissue)
                    Text("Bone").tag(CTWindowPresets.bone)
                    Text("Lung").tag(CTWindowPresets.lung)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            // Plane Selection
            HStack {
                Text("Plane:")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Picker("Plane", selection: $currentPlane) {
                    Text("Axial").tag(MPRPlane.axial)
                    Text("Sagittal").tag(MPRPlane.sagittal)
                    Text("Coronal").tag(MPRPlane.coronal)
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: currentPlane) { _, newPlane in
                    // Reset slice when changing planes
                    currentSlice = 0
                    debugPlaneInfo()
                }
            }
            
            // Slice Navigation
            VStack(spacing: 8) {
                HStack {
                    Button("Previous") {
                        if currentSlice > 0 {
                            currentSlice -= 1
                        }
                    }
                    .disabled(currentSlice <= 0)
                    
                    Spacer()
                    
                    Button("Next") {
                        if currentSlice < getMaxSlicesForPlane() - 1 {
                            currentSlice += 1
                        }
                    }
                    .disabled(currentSlice >= getMaxSlicesForPlane() - 1)
                }
                
                Slider(
                    value: Binding(
                        get: { Double(currentSlice) },
                        set: { currentSlice = Int($0) }
                    ),
                    in: 0...Double(max(getMaxSlicesForPlane() - 1, 0)),
                    step: 1
                ) {
                    Text("Slice")
                }
                .accentColor(.blue)
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Helper Methods
    
    private func getMaxSlicesForPlane() -> Int {
        switch currentPlane {
        case .axial:
            return viewModel.totalSlices
        case .sagittal, .coronal:
            return 512  // Based on volume dimensions
        }
    }
    
    private func debugPlaneInfo() {
        print("🔍 Current plane: \(currentPlane.rawValue)")
        print("🔍 Max slices for \(currentPlane.rawValue): \(getMaxSlicesForPlane())")
        
        if let volumeData = viewModel.volumeRenderer?.volumeData {
            let dimensions = volumeData.dimensions
            print("🔍 Volume dimensions: \(dimensions)")
            
            let imageAspect: Float
            switch currentPlane {
            case .axial:
                imageAspect = Float(dimensions.x) / Float(dimensions.y)
            case .sagittal:
                imageAspect = Float(dimensions.y) / Float(dimensions.z)
            case .coronal:
                imageAspect = Float(dimensions.x) / Float(dimensions.z)
            }
            print("🔍 Natural aspect ratio: \(String(format: "%.3f", imageAspect))")
        } else {
            print("🔍 Volume dimensions not available")
        }
    }
}

// MARK: - Enhanced Metal-based DICOM Image View with ROI Integration

struct MetalDICOMImageView: UIViewRepresentable {
    let viewModel: DICOMViewerViewModel
    let roiManager: ROIIntegrationManager  // ADD ROI MANAGER
    let currentSlice: Int
    let currentPlane: MPRPlane
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
        Coordinator(viewModel: viewModel, roiManager: roiManager)  // PASS ROI MANAGER
    }
    
    // MARK: - Enhanced Coordinator with ROI Overlay Integration
    @MainActor
    class Coordinator: NSObject, MTKViewDelegate {
        let viewModel: DICOMViewerViewModel
        let roiManager: ROIIntegrationManager  // ADD ROI MANAGER
        private var metalRenderer: MetalRenderer?
        private var currentTexture: MTLTexture?
        private var currentWindowing: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
        private var currentPlane: MPRPlane = .axial
        private var currentSlice: Int = 0
        
        // Metal pipeline for texture display
        private var displayPipelineState: MTLRenderPipelineState?
        private var vertexBuffer: MTLBuffer?
        private var aspectRatioBuffer: MTLBuffer?
        private var lastViewportSize: CGSize = .zero
        
        init(viewModel: DICOMViewerViewModel, roiManager: ROIIntegrationManager) {  // UPDATED INIT
            self.viewModel = viewModel
            self.roiManager = roiManager  // STORE ROI MANAGER
            super.init()
            
            do {
                self.metalRenderer = try MetalRenderer()
                setupDisplayPipeline()
                print("✅ MetalRenderer initialized for SwiftUI MPR with ROI support")
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
            
            drawTexture(texture, in: view)
        }
        
        // CRITICAL FIX: updateSlice with ROI Overlay Integration
        func updateSlice(_ slice: Int, plane: MPRPlane, windowing: CTWindowPresets.WindowLevel) {
            // FIXED: Proper comparison using helper function
            guard currentSlice != slice || currentPlane != plane || !isWindowingEqual(currentWindowing, windowing) else {
                return
            }
            
            currentSlice = slice
            currentPlane = plane
            currentWindowing = windowing
            
            // HARDWARE-ACCELERATED MPR generation
            guard let volumeRenderer = viewModel.volumeRenderer else {
                print("❌ Volume renderer not available")
                return
            }
            
            let maxSlices = getMaxSlicesForPlane(plane)
            let normalizedPosition = Float(slice) / Float(max(maxSlices - 1, 1))
            
            print("🔍 HARDWARE MPR: Generating \(plane.rawValue) slice at position \(normalizedPosition)")
            
            let config = MetalVolumeRenderer.MPRConfig(
                plane: plane,
                sliceIndex: normalizedPosition,
                windowCenter: Float(windowing.center),
                windowWidth: Float(windowing.width)
            )
            
            volumeRenderer.generateMPRSlice(config: config) { @Sendable baseTexture in
                guard let baseTexture = baseTexture else {
                    print("❌ MPR slice generation failed")
                    return
                }
                
                print("✅ Base MPR texture generated: \(baseTexture.width)×\(baseTexture.height)")
                
                // CRITICAL NEW INTEGRATION: Apply ROI overlays
                Task { @MainActor in
                    self.applyROIOverlays(to: baseTexture, plane: plane, slicePosition: normalizedPosition)
                }
            }
        }
        
        // Helper function for windowing comparison
        private func isWindowingEqual(_ lhs: CTWindowPresets.WindowLevel, _ rhs: CTWindowPresets.WindowLevel) -> Bool {
            return lhs.center == rhs.center && lhs.width == rhs.width && lhs.name == rhs.name
        }
        
        // CRITICAL NEW METHOD: Apply ROI overlays to MPR texture
        private func applyROIOverlays(to baseTexture: MTLTexture, plane: MPRPlane, slicePosition: Float) {
            // Get volume information for coordinate transformation
            guard let volumeData = viewModel.volumeRenderer?.volumeData else {
                print("⚠️ No volume data available for ROI coordinate transformation")
                self.currentTexture = baseTexture  // Show base texture without ROIs
                return
            }
            
            // FIXED: Direct access to volumeData properties
            let volumeOrigin = SIMD3<Float>(volumeData.origin.x, volumeData.origin.y, volumeData.origin.z)
            let volumeSpacing = SIMD3<Float>(volumeData.spacing.x, volumeData.spacing.y, volumeData.spacing.z)
            let viewportSize = SIMD2<Float>(Float(baseTexture.width), Float(baseTexture.height))
            
            print("🎨 Applying ROI overlays...")
            print("   📐 Volume origin: \(volumeOrigin)")
            print("   📏 Volume spacing: \(volumeSpacing)")
            print("   📺 Viewport: \(viewportSize)")
            
            // Apply ROI overlays using the integration manager
            roiManager.renderROIOverlays(
                onTexture: baseTexture,
                plane: plane,
                slicePosition: slicePosition,
                volumeOrigin: volumeOrigin,
                volumeSpacing: volumeSpacing,
                viewportSize: viewportSize
            ) { @Sendable compositeTexture in
                Task { @MainActor in
                    if let compositeTexture = compositeTexture {
                        print("✅ ROI overlays applied successfully")
                        self.currentTexture = compositeTexture  // Use composite texture with ROIs
                    } else {
                        print("⚠️ ROI overlay failed, using base texture")
                        self.currentTexture = baseTexture  // Fallback to base texture
                    }
                }
            }
        }
        
        private func getMaxSlicesForPlane(_ plane: MPRPlane) -> Int {
            switch plane {
            case .axial:
                return viewModel.totalSlices
            case .sagittal, .coronal:
                return 512
            }
        }
        
        private func updateAspectRatio(for size: CGSize) {
            guard size != lastViewportSize else { return }
            lastViewportSize = size
            
            // Calculate aspect ratio correction based on current plane
            let aspectRatio = calculateAspectRatioForPlane(currentPlane)
            let viewportAspect = Float(size.width / size.height)
            
            var scaleX: Float = 1.0
            var scaleY: Float = 1.0
            
            if aspectRatio > viewportAspect {
                // Image is wider than viewport
                scaleY = viewportAspect / aspectRatio
            } else {
                // Image is taller than viewport
                scaleX = aspectRatio / viewportAspect
            }
            
            let aspectUniforms = AspectRatioUniforms(scaleX: scaleX, scaleY: scaleY)
            
            guard let device = MTLCreateSystemDefaultDevice() else { return }
            aspectRatioBuffer = device.makeBuffer(
                bytes: [aspectUniforms],
                length: MemoryLayout<AspectRatioUniforms>.size,
                options: []
            )
        }
        
        private func calculateAspectRatioForPlane(_ plane: MPRPlane) -> Float {
            guard let volumeData = viewModel.volumeRenderer?.volumeData else {
                return 1.0  // Fallback to square aspect ratio
            }
            
            let dimensions = volumeData.dimensions
            let spacing = volumeData.spacing  // FIXED: Direct access
            
            switch plane {
            case .axial:
                // XY plane: width vs height in mm
                let widthMM = Float(dimensions.x) * spacing.x
                let heightMM = Float(dimensions.y) * spacing.y
                return widthMM / heightMM
                
            case .sagittal:
                // YZ plane: anterior-posterior vs superior-inferior in mm
                let widthMM = Float(dimensions.y) * spacing.y
                let heightMM = Float(dimensions.z) * spacing.z
                return widthMM / heightMM
                
            case .coronal:
                // XZ plane: left-right vs superior-inferior in mm
                let widthMM = Float(dimensions.x) * spacing.x
                let heightMM = Float(dimensions.z) * spacing.z
                return widthMM / heightMM
            }
        }
        
        private func drawTexture(_ texture: MTLTexture, in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let pipelineState = displayPipelineState,
                  let commandBuffer = view.device?.makeCommandQueue()?.makeCommandBuffer(),
                  let aspectBuffer = aspectRatioBuffer else {
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
    }
}

// MARK: - Enhanced View Model with Dynamic Dimensions

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
    
    // MARK: - Dataset Selection and RTStruct Support
    @Published var availableDatasets: [String: DICOMFileSet] = [:]
    @Published var currentDatasetKey: String = "test"
    @Published var rtStructFiles: [URL] = []
    @Published var isRTStructLoaded: Bool = false
    private var currentRTStructData: RTStructData?
    
    // MARK: - Series Information
    struct DICOMSeriesInfo {
        let patientName: String?
        let studyDescription: String?
        let seriesDescription: String?
        let modality: String?
        let totalSlices: Int
    }
    
    struct DICOMFileSet {
        let ctFiles: [URL]
        let rtStructFiles: [URL]
    }
    
    // MARK: - DICOM Loading with Enhanced Discovery
    
    func loadDICOMSeries() async {
        do {
            print("📁 Initializing DICOM datasets with file filtering...")
            
            // Discover and categorize DICOM files
            let allDICOMFiles = DICOMFileManager.getAllDICOMFiles()
            let categorizedFiles = await categorizeDICOMFiles(allDICOMFiles)
            
            print("📁 DICOM File Discovery Results:")
            for (datasetName, fileSet) in categorizedFiles {
                print("   🩻 \(datasetName): CT=\(fileSet.ctFiles.count), RTStruct=\(fileSet.rtStructFiles.count)")
            }
            
            self.availableDatasets = categorizedFiles
            
            // Load the selected dataset
            if let selectedDataset = categorizedFiles[currentDatasetKey] {
                print("🎯 Selected dataset: \(currentDatasetKey)")
                await loadDataset(selectedDataset)
            } else {
                print("❌ Dataset '\(currentDatasetKey)' not found")
            }
            
        } catch {
            print("❌ Error loading DICOM series: \(error)")
        }
    }
    
    private func categorizeDICOMFiles(_ files: [URL]) async -> [String: DICOMFileSet] {
        var datasets: [String: DICOMFileSet] = [:]
        
        // Group files by dataset name (from filename patterns)
        var ctFilesByDataset: [String: [URL]] = [:]
        var rtStructFilesByDataset: [String: [URL]] = [:]
        
        for file in files {
            let filename = file.lastPathComponent.lowercased()
            
            // Determine dataset name
            let datasetName: String
            if filename.contains("test") {
                datasetName = "test"
            } else {
                datasetName = "unknown"
            }
            
            // Categorize file type
            if filename.contains("rtstruct") || filename.contains("rt_struct") {
                rtStructFilesByDataset[datasetName, default: []].append(file)
                print("   📊 RTStruct: \(filename)")
            } else {
                // Assume CT if not RTStruct
                ctFilesByDataset[datasetName, default: []].append(file)
            }
        }
        
        // Create file sets
        let allDatasetNames = Set(ctFilesByDataset.keys).union(Set(rtStructFilesByDataset.keys))
        for datasetName in allDatasetNames {
            let ctFiles = ctFilesByDataset[datasetName] ?? []
            let rtStructFiles = rtStructFilesByDataset[datasetName] ?? []
            
            datasets[datasetName] = DICOMFileSet(
                ctFiles: ctFiles.sorted { $0.lastPathComponent < $1.lastPathComponent },
                rtStructFiles: rtStructFiles
            )
        }
        
        return datasets
    }
    
    private func loadDataset(_ dataset: DICOMFileSet) async {
        print("📁 Loading \(currentDatasetKey.capitalized) Dataset:")
        print("   🩻 CT files: \(dataset.ctFiles.count)")
        print("   📊 RTStruct files: \(dataset.rtStructFiles.count)")
        
        // Load CT volume
        await loadCTVolume(dataset.ctFiles)
        
        // Load RTStruct if available
        if !dataset.rtStructFiles.isEmpty {
            await loadRTStructData(dataset.rtStructFiles)
        }
    }
    
    private func loadCTVolume(_ ctFiles: [URL]) async {
        do {
            // Sort files by anatomical position for proper ordering
            print("📊 Sorting \(ctFiles.count) CT files by anatomical position...")
            let sortedFiles = try await sortFilesByPosition(ctFiles)
            
            // Initialize volume renderer
            let renderer = try MetalVolumeRenderer()
            
            // Load 3D volume from sorted DICOM files for hardware-accelerated MPR
            print("🧊 Loading 3D volume for MPR from CT files...")
            // FIXED: Use instance method, not static
            let volumeData = try await renderer.loadVolumeFromDICOMFiles(sortedFiles)
            
            // Store renderer and update UI
            self.volumeRenderer = renderer
            self.totalSlices = volumeData.dimensions.z
            self.isVolumeLoaded = true
            
            // Extract series information from first file
            if let firstFile = sortedFiles.first {
                let data = try Data(contentsOf: firstFile)
                let dataset = try DICOMParser.parse(data)
                
                self.seriesInfo = DICOMSeriesInfo(
                    patientName: dataset.patientName,
                    studyDescription: dataset.getString(tag: DICOMTag.studyDescription),
                    seriesDescription: dataset.getString(tag: DICOMTag.seriesDescription),
                    modality: dataset.getString(tag: DICOMTag.modality),
                    totalSlices: sortedFiles.count
                )
            }
            
            print("✅ 3D volume loaded successfully for MPR from \(sortedFiles.count) CT files")
            
        } catch {
            print("❌ Error loading CT volume: \(error)")
        }
    }
    
    private func loadRTStructData(_ rtStructFiles: [URL]) async {
        print("📊 Loading RTStruct files for ROI data...")
        
        for rtStructFile in rtStructFiles {
            do {
                print("✅ Parsing RTStruct: \(rtStructFile.lastPathComponent)")
                
                // Parse RTStruct file
                let data = try Data(contentsOf: rtStructFile)
                let dataset = try DICOMParser.parse(data)
                
                // Show diagnostic info
                let info = RTStructParser.getRTStructInfo(from: dataset)
                print("🔍 RTStruct Diagnostic Info:")
                print(info)
                
                // Parse RTStruct data with raw data fallback
                let rtStructData = try RTStructParser.parseRTStructWithRawData(from: dataset, rawData: data)
                
                // Store RTStruct data
                self.currentRTStructData = rtStructData
                self.isRTStructLoaded = true
                
                let stats = rtStructData.getStatistics()
                print("📊 RTStruct loaded successfully:")
                print("   \(stats.description)")
                
                break // Use first successful RTStruct
                
            } catch {
                print("❌ Error parsing RTStruct \(rtStructFile.lastPathComponent): \(error)")
            }
        }
    }
    
    // MARK: - RTStruct Data Access
    
    func getRTStructData() -> RTStructData? {
        return currentRTStructData
    }
    
    func hasRTStructData() -> Bool {
        return currentRTStructData != nil
    }
    
    // MARK: - File Sorting and Processing
    
    private func sortFilesByPosition(_ files: [URL]) async throws -> [URL] {
        var fileInfo: [(URL, Double)] = []
        
        for file in files {
            let data = try Data(contentsOf: file)
            let dataset = try DICOMParser.parse(data)
            
            // Use Image Position (Patient) Z coordinate for sorting
            let position = dataset.getImagePosition()
            let zPosition = position?.z ?? 0.0
            
            fileInfo.append((file, zPosition))
        }
        
        // Sort by Z position (inferior to superior)
        fileInfo.sort { $0.1 < $1.1 }
        
        return fileInfo.map { $0.0 }
    }
    
    // MARK: - Legacy Support Methods
    
    func getRescaleParameters(for index: Int) async -> RescaleParameters {
        // Return default parameters for MPR rendering
        return RescaleParameters(slope: 1.0, intercept: 0.0)
    }
}
