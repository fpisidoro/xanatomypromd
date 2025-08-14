import SwiftUI
import simd

// MARK: - Main Application Integration
// Replaces the complex DICOMViewerView with clean layered architecture

struct XAnatomyProMainView: View {
    
    // MARK: - State Management
    
    @StateObject var coordinateSystem = DICOMCoordinateSystem()
    @StateObject var dataManager = XAnatomyDataManager()
    @StateObject var sharedViewingState = SharedViewingState()  // Shared across all views
    
    @State private var currentPlane: MPRPlane = .axial
    @State private var show3D: Bool = false
    @State private var isLoading = true
    @State private var showingControls = true
    
    // View configuration
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    
    // Adaptive Quality for Performance
    @State private var scrollVelocity: Float = 0.0
    @State private var lastSliceChange: Date = Date()
    @State private var qualityTimer: Timer?
    @State private var currentQuality: ScrollQuality = .full
    
    enum ScrollQuality {
        case full, half, quarter
        
        var description: String {
            switch self {
            case .full: return "Full"
            case .half: return "Half" 
            case .quarter: return "Quarter"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Header
                    headerView
                    
                    // Main viewing area
                    mainViewingArea(geometry: geometry)
                    
                    // Controls (collapsible)
                    if showingControls {
                        controlsArea
                            .transition(.move(edge: .bottom))
                    }
                }
                .background(Color.black)
                .navigationBarHidden(true)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
        .onAppear {
            loadApplicationData()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("X-Anatomy Pro v2.0")
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let patientInfo = dataManager.patientInfo {
                    Text(patientInfo.name)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(currentPlane.displayName)
                    .font(.headline)
                    .foregroundColor(.blue)
                
                let sliceIndex = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
                let maxSlices = coordinateSystem.getMaxSlices(for: currentPlane)
                Text("Slice \(sliceIndex + 1)/\(maxSlices)")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text(sharedViewingState.windowLevel.name)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Button(action: { showingControls.toggle() }) {
                Image(systemName: showingControls ? "chevron.down" : "chevron.up")
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Main Viewing Area
    
    private func mainViewingArea(geometry: GeometryProxy) -> some View {
        ZStack {
            if isLoading {
                loadingView
            } else {
                // THE CLEAN LAYERED SYSTEM
                Group {
                    if show3D {
                        Standalone3DView(
                            coordinateSystem: coordinateSystem,
                            sharedState: sharedViewingState,  // Use the shared instance
                            volumeData: dataManager.volumeData,
                            roiData: dataManager.roiData,
                            viewSize: CGSize(
                                width: geometry.size.width,
                                height: geometry.size.height * 0.7
                            ),
                            allowInteraction: true
                        )
                    } else {
                        LayeredMPRView(
                            coordinateSystem: coordinateSystem,
                            plane: currentPlane,
                            windowLevel: sharedViewingState.windowLevel,
                            crosshairAppearance: sharedViewingState.crosshairSettings,
                            roiSettings: sharedViewingState.roiSettings,
                            volumeData: dataManager.volumeData,
                            roiData: dataManager.roiData,
                            viewSize: CGSize(
                                width: geometry.size.width,
                                height: geometry.size.height * 0.7
                            ),
                            allowInteraction: true,
                            scrollVelocity: scrollVelocity
                        )
                    }
                }
                .scaleEffect(scale)
                .offset(dragOffset)
                .clipped()
                .onTwoFingerSwipe { translation, velocity in
                    handleTwoFingerScroll(translation: translation, velocity: velocity)
                }
                .gesture(panGesture)  // Single finger pan
                .gesture(zoomGesture)  // Pinch to zoom
                .onScrollWheel { delta in
                    handleScrollWheel(delta: delta)
                }
                .onAppear {
                    // Initialize coordinate system when volume data is loaded
                    if let volumeData = dataManager.volumeData {
                        coordinateSystem.initializeFromVolumeData(volumeData)
                        print("✅ Coordinate system initialized with volume dimensions: \(volumeData.dimensions)")
                    }
                }
                .onChange(of: dataManager.isVolumeLoaded) { _, isLoaded in
                    // Update coordinate system when volume data becomes available
                    if isLoaded, let volumeData = dataManager.volumeData {
                        coordinateSystem.initializeFromVolumeData(volumeData)
                        print("✅ Coordinate system updated with new volume data")
                    }
                }
            }
        }
        .frame(height: geometry.size.height * 0.7)
    }
    
    // MARK: - Controls Area
    
    private var controlsArea: some View {
        ScrollView {
            VStack(spacing: 16) {
                planeSelectionControls
                windowingControls
                sliceNavigationControls
                displayOptionsControls
                actionButtons
            }
            .padding()
        }
        .background(Color.gray.opacity(0.1))
        .frame(maxHeight: 300)
    }
    
    // MARK: - Control Sections
    
    private var planeSelectionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Anatomical Plane")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                ForEach([MPRPlane.axial, MPRPlane.sagittal, MPRPlane.coronal], id: \.self) { plane in
                    Button(action: { 
                        currentPlane = plane
                        sharedViewingState.lastActivePlane = plane
                        show3D = false
                    }) {
                        VStack(spacing: 4) {
                            Text(plane.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            
                            Text(getPlaneDescription(plane))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(!show3D && currentPlane == plane ? Color.blue : Color.gray.opacity(0.3))
                        .cornerRadius(8)
                    }
                }
                
                // 3D Button
                Button(action: { show3D = true }) {
                    VStack(spacing: 4) {
                        Text("3D")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        Text("Volume")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(show3D ? Color.blue : Color.gray.opacity(0.3))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private var windowingControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CT Windowing")
                .font(.headline)
                .foregroundColor(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CTWindowLevel.allPresets, id: \.name) { preset in
                        Button(action: { sharedViewingState.setWindowLevel(preset) }) {
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
                            .background(sharedViewingState.windowLevel.name == preset.name ? Color.blue : Color.gray.opacity(0.3))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var sliceNavigationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Slice Navigation")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack {
                Button("←") { previousSlice() }
                    .disabled(!canNavigateToPreviousSlice())
                    .foregroundColor(.white)
                
                Slider(
                    value: Binding(
                        get: { Double(coordinateSystem.getCurrentSliceIndex(for: currentPlane)) },
                        set: { newValue in
                            let sliceIndex = Int(newValue)
                            coordinateSystem.updateFromSliceScroll(plane: currentPlane, sliceIndex: sliceIndex)
                        }
                    ),
                    in: 0...Double(coordinateSystem.getMaxSlices(for: currentPlane) - 1),
                    step: 1
                )
                .accentColor(.blue)
                
                Button("→") { nextSlice() }
                    .disabled(!canNavigateToNextSlice())
                    .foregroundColor(.white)
            }
        }
    }
    
    private var displayOptionsControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Options")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack {
                Toggle("Crosshairs", isOn: Binding(
                    get: { sharedViewingState.crosshairSettings.isVisible },
                    set: { _ in sharedViewingState.toggleCrosshairs() }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                
                Spacer()
                
                Toggle("ROI Overlay", isOn: Binding(
                    get: { sharedViewingState.roiSettings.isVisible },
                    set: { _ in sharedViewingState.toggleROIOverlay() }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .blue))
            }
            .foregroundColor(.white)
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button("Reset View") { resetViewTransform() }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(8)
            
            Button("Center") { centerCrosshair() }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(8)
            
            Button("Test RTStruct") { testRTStructParsing() }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(8)
            
            Spacer()
            
            statusIndicator
        }
    }
    
    // MARK: - Helper Views
    
    private var loadingView: some View {
        MedicalProgressView(
            current: dataManager.loadingCurrent,
            total: dataManager.loadingTotal,
            message: dataManager.loadingProgress.isEmpty ? "Initializing..." : dataManager.loadingProgress
        )
    }
    
    private var statusIndicator: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if dataManager.isVolumeLoaded {
                Text("✅ Volume")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            if dataManager.isROILoaded {
                Text("✅ ROI")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }
    
    private func sliceNavigationOverlay(geometry: GeometryProxy) -> some View {
        HStack {
            Button(action: previousSlice) {
                Image(systemName: "chevron.left")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: geometry.size.width * 0.2)
            .disabled(!canNavigateToPreviousSlice())
            
            Spacer()
            
            Button(action: nextSlice) {
                Image(systemName: "chevron.right")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: geometry.size.width * 0.2)
            .disabled(!canNavigateToNextSlice())
        }
    }
    
    // MARK: - Gesture Handlers
    
    // Single finger pan for view movement
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { _ in
                withAnimation(.spring()) {
                    dragOffset = .zero
                }
            }
    }
    
    // MARK: - Two-Finger Scroll Handler
    
    private func handleTwoFingerScroll(translation: CGFloat, velocity: CGFloat) {
        // Calculate slice delta from translation
        let sensitivity: CGFloat = 5.0  // Pixels per slice
        let sliceDelta = Int(translation / sensitivity)
        
        if sliceDelta != 0 {
            let currentSlice = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
            let newSlice = currentSlice - sliceDelta  // Negative for natural scrolling
            let maxSlices = coordinateSystem.getMaxSlices(for: currentPlane)
            let clampedSlice = max(0, min(newSlice, maxSlices - 1))
            
            if clampedSlice != currentSlice {
                coordinateSystem.updateFromSliceScroll(plane: currentPlane, sliceIndex: clampedSlice)
            }
        }
    }
    
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in scale = lastScale * value }
            .onEnded { value in
                lastScale = scale
                withAnimation(.spring()) {
                    scale = max(0.5, min(scale, 3.0))
                    lastScale = scale
                }
            }
    }
    
    // MARK: - Action Methods
    
    private func previousSlice() {
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
        if currentSlice > 0 {
            coordinateSystem.updateFromSliceScroll(plane: currentPlane, sliceIndex: currentSlice - 1)
        }
    }
    
    private func nextSlice() {
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
        let maxSlices = coordinateSystem.getMaxSlices(for: currentPlane)
        if currentSlice < maxSlices - 1 {
            coordinateSystem.updateFromSliceScroll(plane: currentPlane, sliceIndex: currentSlice + 1)
        }
    }
    

    
    private func canNavigateToPreviousSlice() -> Bool {
        return coordinateSystem.getCurrentSliceIndex(for: currentPlane) > 0
    }
    
    private func canNavigateToNextSlice() -> Bool {
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
        let maxSlices = coordinateSystem.getMaxSlices(for: currentPlane)
        return currentSlice < maxSlices - 1
    }
    
    private func resetViewTransform() {
        withAnimation(.spring()) {
            scale = 1.0
            lastScale = 1.0
            dragOffset = .zero
        }
    }
    
    private func centerCrosshair() {
        let centerX = coordinateSystem.volumeOrigin.x + (Float(coordinateSystem.volumeDimensions.x) * coordinateSystem.volumeSpacing.x) / 2.0
        let centerY = coordinateSystem.volumeOrigin.y + (Float(coordinateSystem.volumeDimensions.y) * coordinateSystem.volumeSpacing.y) / 2.0
        let centerZ = coordinateSystem.volumeOrigin.z + (Float(coordinateSystem.volumeDimensions.z) * coordinateSystem.volumeSpacing.z) / 2.0
        
        coordinateSystem.updateWorldPosition(SIMD3<Float>(centerX, centerY, centerZ))
    }
    
    private func loadApplicationData() {
        Task {
            await dataManager.loadAllData()
            isLoading = false
        }
    }
    
    private func getPlaneDescription(_ plane: MPRPlane) -> String {
        switch plane {
        case .axial: return "Top-Down"
        case .sagittal: return "Side View"
        case .coronal: return "Front View"
        }
    }
    
    // MARK: - Scroll Wheel Support
    
    private func handleScrollWheel(delta: CGFloat) {
        // Scroll wheel delta: positive = scroll up = next slice
        let sensitivity: CGFloat = 10.0  // Adjust for scroll wheel sensitivity
        let sliceDelta = Int(delta / sensitivity)
        
        if sliceDelta != 0 {
            let currentSlice = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
            let newSlice = currentSlice + sliceDelta
            let maxSlices = coordinateSystem.getMaxSlices(for: currentPlane)
            let clampedSlice = max(0, min(newSlice, maxSlices - 1))
            
            if clampedSlice != currentSlice {
                coordinateSystem.updateFromSliceScroll(plane: currentPlane, sliceIndex: clampedSlice)
            }
        }
    }
    
    private func testRTStructParsing() {
        print("\n🧪 MANUAL RTStruct Test Called")
        debugROISystem()  // Call comprehensive debug
        
        Task {
            let rtStructFiles = DICOMFileManager.getRTStructFiles()
            
            if rtStructFiles.isEmpty {
                print("❌ No RTStruct files found for testing")
                return
            }
            
            for (index, file) in rtStructFiles.enumerated() {
                print("\n📄 Testing RTStruct file \(index + 1): \(file.lastPathComponent)")
                
                do {
                    let data = try Data(contentsOf: file)
                    let dataset = try DICOMParser.parse(data)
                    
                    if let result = MinimalRTStructParser.parseSimpleRTStruct(from: dataset) {
                        print("✅ SUCCESS: Found \(result.roiStructures.count) ROI structures")
                        
                        let totalContours = result.roiStructures.reduce(0) { $0 + $1.contours.count }
                        let totalPoints = result.roiStructures.reduce(0) { total, roi in
                            total + roi.contours.reduce(0) { $0 + $1.points.count }
                        }
                        
                        print("📊 Total: \(totalContours) contours, \(totalPoints) points")
                        
                        for roi in result.roiStructures {
                            let zPositions = roi.contours.map { $0.slicePosition }
                            let minZ = zPositions.min() ?? 0
                            let maxZ = zPositions.max() ?? 0
                            print("   🏷️ ROI \(roi.roiNumber): '\(roi.roiName)' - \(roi.contours.count) contours (Z: \(minZ) to \(maxZ)mm)")
                        }
                    } else {
                        print("❌ Parsing failed - no data returned")
                    }
                } catch {
                    print("❌ Error testing file: \(error)")
                }
            }
        }
    }
}

// MARK: - Data Manager

@MainActor
class XAnatomyDataManager: ObservableObject {
    @Published var volumeData: VolumeData?
    @Published var roiData: MinimalRTStructParser.SimpleRTStructData?
    @Published var patientInfo: PatientInfo?
    @Published var isLoading = false
    @Published var loadingProgress: String = ""
    @Published var loadingCurrent: Int = 0
    @Published var loadingTotal: Int = 0
    @Published var isAxialReady = false
    
    private var volumeRenderer: MetalVolumeRenderer?
    
    var isVolumeLoaded: Bool { volumeData != nil }
    var isROILoaded: Bool { roiData != nil }
    
    init() {
        // Initialize volume renderer
        do {
            volumeRenderer = try MetalVolumeRenderer()
            print("✅ MetalVolumeRenderer initialized")
        } catch {
            print("❌ Failed to initialize MetalVolumeRenderer: \(error)")
        }
    }
    
    func loadAllData() async {
        isLoading = true
        loadingProgress = "Initializing..."
        
        await loadVolumeData()
        await loadROIData()
        await loadPatientInfo()
        
        isLoading = false
        loadingProgress = "Complete"
    }
    
    private func loadVolumeData() async {
        loadingProgress = "Loading DICOM files..."
        
        do {
            // Get DICOM files from bundle
            let dicomFiles = getDICOMFiles()
            debugLog("Found \(dicomFiles.count) DICOM files", category: .volume)
            
            guard !dicomFiles.isEmpty else {
                debugLog("No DICOM files found in bundle", category: .volume)
                return
            }
            
            // Set total for progress tracking
            loadingTotal = dicomFiles.count
            loadingProgress = "Processing \(dicomFiles.count) DICOM files..."
            
            // Simulate progress updates (in real implementation, update during actual loading)
            for (index, _) in dicomFiles.enumerated() {
                loadingCurrent = index + 1
                // Small delay to show progress animation
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            // Load volume using MetalVolumeRenderer
            if let renderer = volumeRenderer {
                let loadedVolumeData = try await renderer.loadVolumeFromDICOMFiles(dicomFiles)
                
                // Update published property on main actor
                volumeData = loadedVolumeData
                
                loadingProgress = "Volume loaded successfully"
                debugLog("Volume data loaded: \(loadedVolumeData.dimensions)", category: .volume)
                
                // Log volume info
                if let info = renderer.getVolumeInfo() {
                    debugLog("Volume Info: \(info)", category: .volume)
                }
            }
            
        } catch {
            print("❌ Failed to load volume data: \(error)")
            loadingProgress = "Failed to load volume: \(error.localizedDescription)"
        }
    }
    
    private func loadROIData() async {
        loadingProgress = "Loading ROI structures..."
        
        // Use the new DICOMFileManager to find RTStruct files
        let rtStructFiles = DICOMFileManager.getRTStructFiles()
        
        if !rtStructFiles.isEmpty {
            print("🎯 Found \(rtStructFiles.count) RTStruct files:")
            for file in rtStructFiles {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                print("   - \(file.lastPathComponent) (\(size) bytes)")
            }
            
            // Try to parse the first RTStruct file (prioritized by DICOMFileManager)
            let rtStructFile = rtStructFiles[0]
            
            do {
                print("\n📋 PARSING RTStruct file: \(rtStructFile.lastPathComponent)")
                print("📂 File path: \(rtStructFile.path)")
                
                let data = try Data(contentsOf: rtStructFile)
                print("📊 File size: \(data.count) bytes")
                
                let dataset = try DICOMParser.parse(data)
                print("✅ DICOM parsing successful - \(dataset.elements.count) elements")
                
                // Check modality
                if let modality = dataset.getString(tag: .modality) {
                    print("🏷️ Modality confirmed: \(modality)")
                }
                
                // Use the new direct parser to extract ROI data
                print("\n🔍 Starting RTStruct parsing...")
                if let simpleRTStruct = MinimalRTStructParser.parseSimpleRTStruct(from: dataset) {
                    // Update published property on main actor
                    roiData = simpleRTStruct
                    
                    print("\n✅ RTStruct SUCCESS: \(simpleRTStruct.roiStructures.count) ROI structures loaded")
                    for roi in simpleRTStruct.roiStructures {
                        print("   📊 ROI \(roi.roiNumber): '\(roi.roiName)' - \(roi.contours.count) contours")
                    }
                    loadingProgress = "RTStruct loaded: \(simpleRTStruct.roiStructures.count) ROIs"
                } else {
                    print("\n❌ RTStruct parsing returned no data")
                    loadingProgress = "RTStruct parsing failed - no geometry found"
                }
                
            } catch {
                print("\n❌ Failed to load RTStruct file: \(error)")
                loadingProgress = "Failed to load RTStruct: \(error.localizedDescription)"
            }
        } else {
            print("📝 No RTStruct files found - continuing without ROI")
            loadingProgress = "No RTStruct files found"
        }
    }
    
    private func loadPatientInfo() async {
        loadingProgress = "Loading patient information..."
        
        // Extract patient info from first DICOM file
        let dicomFiles = getDICOMFiles()
        if let firstFile = dicomFiles.first {
            do {
                let data = try Data(contentsOf: firstFile)
                let dataset = try DICOMParser.parse(data)
                
                let patientName = dataset.getString(tag: DICOMTag.patientName) ?? "Unknown Patient"
                let studyDate = dataset.getString(tag: DICOMTag.studyDate) ?? "Unknown Date"
                let modality = dataset.getString(tag: DICOMTag.modality) ?? "CT"
                
                patientInfo = PatientInfo(
                    name: patientName,
                    studyDate: studyDate,
                    modality: modality
                )
                
                print("👤 Patient info loaded: \(patientName)")
                loadingProgress = "Patient information loaded"
                
            } catch {
                print("❌ Failed to extract patient info: \(error)")
                // Use fallback
                patientInfo = PatientInfo(
                    name: "Test Patient XAPV2",
                    studyDate: "2025-01-28",
                    modality: "CT"
                )
            }
        }
    }
    
    // MARK: - File Discovery
    
    private func getDICOMFiles() -> [URL] {
        guard let bundlePath = Bundle.main.resourcePath else {
            print("❌ Could not find bundle resource path")
            return []
        }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: bundlePath),
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            let dicomFiles = fileURLs.filter { url in
                let filename = url.lastPathComponent
                return (url.pathExtension.lowercased() == "dcm" ||
                        filename.contains("2.16.840.1.114362")) &&
                       !filename.contains("rtstruct") &&
                       !filename.contains("test_")
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            print("📂 Found \(dicomFiles.count) DICOM files in bundle root")
            return dicomFiles
            
        } catch {
            print("❌ Error reading bundle root: \(error)")
            return []
        }
    }
    
    private func getRTStructFiles() -> [URL] {
        guard let bundlePath = Bundle.main.resourcePath else { return [] }
        
        let testDataPath = (bundlePath as NSString).appendingPathComponent("TestData")
        
        // Check for both RTStruct files, prioritize test_rtstruct2.dcm
        var rtStructFiles: [URL] = []
        
        let rtStruct2Path = (testDataPath as NSString).appendingPathComponent("test_rtstruct2.dcm")
        if FileManager.default.fileExists(atPath: rtStruct2Path) {
            rtStructFiles.append(URL(fileURLWithPath: rtStruct2Path))
            print("📄 Found test_rtstruct2.dcm (priority file with geometry)")
        }
        
        let rtStructPath = (testDataPath as NSString).appendingPathComponent("test_rtstruct.dcm")
        if FileManager.default.fileExists(atPath: rtStructPath) {
            rtStructFiles.append(URL(fileURLWithPath: rtStructPath))
            print("📄 Found test_rtstruct.dcm (backup file)")
        }
        
        return rtStructFiles
    }
    
    // MARK: - Volume Renderer Access
    
    func getVolumeRenderer() -> MetalVolumeRenderer? {
        return volumeRenderer
    }
    
    // MARK: - Gesture Handlers
    
    private func handleTwoFingerScroll(translation: CGFloat, velocity: CGFloat) {
        updateScrollVelocity(Float(velocity))
        handleSliceNavigation(delta: translation)
    }
    
    private func handleScrollWheel(delta: CGFloat) {
        // Calculate velocity from delta magnitude
        let wheelVelocity = abs(delta) / 10.0  // Scale wheel sensitivity
        updateScrollVelocity(Float(wheelVelocity))
        handleSliceNavigation(delta: delta)
    }
    
    private func handleSliceNavigation(delta: CGFloat) {
        let sliceChange = Int(delta / 10.0)  // Sensitivity adjustment
        
        if sliceChange != 0 {
            let currentSliceIndex = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
            let newSliceIndex = currentSliceIndex + sliceChange
            coordinateSystem.updateFromSliceScroll(plane: currentPlane, sliceIndex: newSliceIndex)
            lastSliceChange = Date()
            
            // Reset quality timer
            qualityTimer?.invalidate()
            qualityTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                // Restore full quality after scroll stops
                withAnimation(.easeOut(duration: 0.2)) {
                    scrollVelocity = 0.0
                    currentQuality = .full
                }
            }
        }
    }
    
    private func updateScrollVelocity(_ velocity: Float) {
        scrollVelocity = velocity
        
        // Determine quality based on velocity
        if velocity < 2.0 {
            currentQuality = .full
        } else if velocity < 5.0 {
            currentQuality = .half
        } else {
            currentQuality = .quarter
        }
        
        if currentQuality != .full {
            print("🎯 Adaptive Quality: \(currentQuality.description) (velocity: \(velocity))")
        }
    }
    
    // MARK: - Gesture Properties
    
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
    }
    
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale *= delta
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale < 0.5 { scale = 0.5 }
                if scale > 3.0 { scale = 3.0 }
            }
    }
    
    // MARK: - View Components (Simplified for now)
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading Medical Data...")
                .foregroundColor(.white)
        }
    }
    
    private var controlsArea: some View {
        VStack(spacing: 16) {
            // Simplified controls
            HStack {
                Button("Axial") { currentPlane = .axial }
                    .foregroundColor(currentPlane == .axial ? .blue : .white)
                Button("Sagittal") { currentPlane = .sagittal }
                    .foregroundColor(currentPlane == .sagittal ? .blue : .white)
                Button("Coronal") { currentPlane = .coronal }
                    .foregroundColor(currentPlane == .coronal ? .blue : .white)
            }
            
            HStack {
                Text("Quality: \(currentQuality.description)")
                    .foregroundColor(.gray)
                    .font(.caption)
                Spacer()
                Text("Velocity: \(String(format: "%.1f", scrollVelocity))")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}

// MARK: - Supporting Types

struct PatientInfo {
    let name: String
    let studyDate: String
    let modality: String
}
