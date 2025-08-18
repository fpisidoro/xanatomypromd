import SwiftUI
import simd
import MetalKit

// MARK: - X-Anatomy Pro v2.0 Main View with 2-Finger Scrolling
// Clean implementation with proper UIKit gesture integration

struct XAnatomyProV2MainView: View {
    
    // MARK: - Shared State
    @StateObject private var coordinateSystem = DICOMCoordinateSystem()
    @StateObject private var sharedState = SharedViewingState()
    @StateObject private var dataManager = XAnatomyDataManager()
    
    // MARK: - View Configuration
    @State private var layoutMode: LayoutMode = .automatic
    @State private var selectedSingleViewPlane: ViewType = .axial
    @State private var isLoading = true
    @State private var showControls = true
    
    // Adaptive Quality for Performance
    @State private var scrollVelocity: Float = 0.0
    @State private var lastSliceChange: Date = Date()
    @State private var qualityTimer: Timer?
    @State private var currentQuality: ScrollQuality = .full
    
    enum ScrollQuality: Int {
        case full = 1, half = 2, quarter = 4
        
        var description: String {
            switch self {
            case .full: return "Full"
            case .half: return "Half" 
            case .quarter: return "Quarter"
            }
        }
    }
    
    enum ViewType {
        case axial, sagittal, coronal, threeDimensional
        
        var displayName: String {
            switch self {
            case .axial: return "Axial"
            case .sagittal: return "Sagittal"
            case .coronal: return "Coronal"
            case .threeDimensional: return "3D"
            }
        }
        
        var mprPlane: MPRPlane? {
            switch self {
            case .axial: return .axial
            case .sagittal: return .sagittal
            case .coronal: return .coronal
            case .threeDimensional: return nil
            }
        }
    }
    
    enum LayoutMode {
        case single, double, triple, quad, automatic
        
        var displayName: String {
            switch self {
            case .single: return "1-View"
            case .double: return "2-View"
            case .triple: return "3-View"
            case .quad: return "4-View"
            case .automatic: return "Auto"
            }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    if showControls {
                        headerBar
                    }
                    
                    if isLoading {
                        MedicalProgressView(
                            current: dataManager.loadingCurrent,
                            total: dataManager.loadingTotal,
                            message: dataManager.loadingProgress.isEmpty ? "Initializing..." : dataManager.loadingProgress
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ZStack {
                            mprViewsLayout(in: geometry)
                                .background(
                                    TwoFingerScrollHandler { direction, velocity in
                                        handleTwoFingerScroll(direction: direction, velocity: velocity)
                                    }
                                )
                            
                            sliceNavigationOverlay(in: geometry)
                        }
                    }
                    
                    if showControls && !isLoading {
                        bottomControls
                    }
                }
                
                persistentControls
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startLoading()
            determineOptimalLayout()
        }
    }
    
    // MARK: - 2-Finger Scroll Handler
    
    private func handleTwoFingerScroll(direction: Int, velocity: CGFloat) {
        updateScrollVelocity(velocity)
        
        switch layoutMode {
        case .single:
            if let plane = selectedSingleViewPlane.mprPlane {
                navigateSlice(plane: plane, direction: direction)
            }
        default:
            navigateSlice(plane: .axial, direction: direction)
        }
    }
    
    private func updateScrollVelocity(_ velocity: CGFloat) {
        scrollVelocity = Float(velocity)
        lastSliceChange = Date()
        
        let newQuality: ScrollQuality
        if scrollVelocity > 500 {
            newQuality = .quarter
        } else if scrollVelocity > 250 {
            newQuality = .half
        } else {
            newQuality = .full
        }
        
        if newQuality != currentQuality {
            currentQuality = newQuality
            Task { @MainActor in
                sharedState.renderQuality = newQuality.rawValue
            }
        }
        
        qualityTimer?.invalidate()
        qualityTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            Task { @MainActor in
                if currentQuality != .full {
                    currentQuality = .full
                    sharedState.renderQuality = ScrollQuality.full.rawValue
                }
            }
        }
    }
    
    private func navigateSlice(plane: MPRPlane, direction: Int) {
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: plane)
        let totalSlices = coordinateSystem.getMaxSlices(for: plane)
        let newSlice = max(0, min(totalSlices - 1, currentSlice + direction))
        
        if newSlice != currentSlice {
            coordinateSystem.updateFromSliceScroll(plane: plane, sliceIndex: newSlice)
        }
    }
    
    // MARK: - Placeholder Views (implement these from original)
    
    private var headerBar: some View {
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
                Text(selectedSingleViewPlane.displayName)
                    .font(.headline)
                    .foregroundColor(.blue)
                
                let sliceIndex = coordinateSystem.getCurrentSliceIndex(for: selectedSingleViewPlane.mprPlane ?? .axial)
                let maxSlices = coordinateSystem.getMaxSlices(for: selectedSingleViewPlane.mprPlane ?? .axial)
                Text("Slice \(sliceIndex + 1)/\(maxSlices)")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text(sharedState.windowLevel.name)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Button(action: { withAnimation { showControls.toggle() } }) {
                Image(systemName: showControls ? "chevron.down" : "chevron.up")
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
    }
    
    private var bottomControls: some View {
        VStack(spacing: 0) {
            // TEST BUTTONS - Direct from working version
            HStack {
                Button("AXIAL") { 
                    selectedSingleViewPlane = .axial
                    layoutMode = .single
                }
                .foregroundColor(.blue)
                .padding()
                
                Button("SAGITTAL") { 
                    selectedSingleViewPlane = .sagittal
                    layoutMode = .single
                }
                .foregroundColor(.blue)
                .padding()
                
                Button("CORONAL") { 
                    selectedSingleViewPlane = .coronal
                    layoutMode = .single
                }
                .foregroundColor(.blue)
                .padding()
                
                Button("3D") { 
                    selectedSingleViewPlane = .threeDimensional
                    layoutMode = .single
                }
                .foregroundColor(.blue)
                .padding()
                
                Button("BONE") { 
                    sharedState.windowLevel = CTWindowLevel.bone
                }
                .foregroundColor(.red)
                .padding()
                
                Button("LUNG") { 
                    sharedState.windowLevel = CTWindowLevel.lung
                }
                .foregroundColor(.red)
                .padding()
                
                Button("SOFT") { 
                    sharedState.windowLevel = CTWindowLevel.softTissue
                }
                .foregroundColor(.red)
                .padding()
                
                Spacer()
                
                Button("TRIPLE") {
                    layoutMode = .triple
                }
                .foregroundColor(.green)
                .padding()
                
                Button("SINGLE") {
                    layoutMode = .single
                }
                .foregroundColor(.green)
                .padding()
            }
            .background(Color.white)
        }
    }
    
    private var persistentControls: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: { withAnimation { showControls.toggle() } }) {
                    Image(systemName: showControls ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .padding()
            }
            Spacer()
        }
    }
    
    @ViewBuilder
    private func mprViewsLayout(in geometry: GeometryProxy) -> some View {
        let viewSize = calculateViewSize(for: resolveEffectiveLayout(for: geometry.size), in: geometry)
        let effectiveLayout = resolveEffectiveLayout(for: geometry.size)
        
        switch effectiveLayout {
        case .single:
            if selectedSingleViewPlane == .threeDimensional {
                Standalone3DView(
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: viewSize,
                    allowInteraction: true
                )
            } else {
                StandaloneMPRView(
                    plane: selectedSingleViewPlane.mprPlane ?? .axial,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: viewSize,
                    allowInteraction: true
                )
            }
            
        case .triple:
            HStack(spacing: 2) {
                StandaloneMPRView(
                    plane: .axial,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: viewSize,
                    allowInteraction: true
                )
                
                StandaloneMPRView(
                    plane: .sagittal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: viewSize,
                    allowInteraction: true
                )
                
                StandaloneMPRView(
                    plane: .coronal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: viewSize,
                    allowInteraction: true
                )
            }
            
        case .double, .quad, .automatic:
            Text("Layout: \(effectiveLayout.displayName)")
                .foregroundColor(.white)
        }
    }
    
    private func sliceNavigationOverlay(in geometry: GeometryProxy) -> some View {
        HStack {
            Button(action: { navigateSlice(plane: .axial, direction: -1) }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(width: 60, height: geometry.size.height * 0.8)
            
            Spacer()
            
            Button(action: { navigateSlice(plane: .axial, direction: 1) }) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(width: 60, height: geometry.size.height * 0.8)
        }
    }
    
    private func startLoading() {
        Task {
            await dataManager.loadAllData()
            if let volumeData = dataManager.volumeData {
                coordinateSystem.initializeFromVolumeData(volumeData)
            }
            isLoading = false
        }
    }
    
    private func determineOptimalLayout() {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            layoutMode = .single
        } else {
            layoutMode = .triple
        }
        #else
        layoutMode = .triple
        #endif
    }
    
    private func calculateViewSize(for layout: LayoutMode, in geometry: GeometryProxy) -> CGSize {
        let totalHeight = geometry.size.height - (showControls ? 100 : 0)
        let totalWidth = geometry.size.width
        
        switch layout {
        case .single:
            return CGSize(width: totalWidth - 20, height: totalHeight - 20)
        case .double:
            return CGSize(width: (totalWidth - 4) / 2, height: totalHeight - 10)
        case .triple:
            return CGSize(width: (totalWidth - 6) / 3, height: totalHeight - 10)
        case .quad:
            return CGSize(width: (totalWidth - 4) / 2, height: (totalHeight - 4) / 2)
        case .automatic:
            return calculateViewSize(for: resolveEffectiveLayout(for: geometry.size), in: geometry)
        }
    }
    
    private func resolveEffectiveLayout(for size: CGSize) -> LayoutMode {
        guard layoutMode == .automatic else { return layoutMode }
        
        if size.width < 600 {
            return .single  // iPhone
        } else if size.width < 900 {
            return .double  // Small iPad
        } else if size.width < 1200 {
            return .triple  // Regular iPad
        } else {
            return .quad    // Large iPad/Mac
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
            
            guard !dicomFiles.isEmpty else {
                return
            }
            
            // Set total for progress tracking
            loadingTotal = dicomFiles.count
            loadingProgress = "Processing \(dicomFiles.count) DICOM files..."
            
            // Simulate progress updates
            for (index, _) in dicomFiles.enumerated() {
                loadingCurrent = index + 1
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            // Load volume using MetalVolumeRenderer
            if let renderer = volumeRenderer {
                let loadedVolumeData = try await renderer.loadVolumeFromDICOMFiles(dicomFiles)
                volumeData = loadedVolumeData
                loadingProgress = "Volume loaded successfully"
            }
            
        } catch {
            print("❌ Failed to load volume data: \(error)")
            loadingProgress = "Failed to load volume: \(error.localizedDescription)"
        }
    }
    
    private func loadROIData() async {
        loadingProgress = "Loading ROI structures..."
        
        let rtStructFiles = DICOMFileManager.getRTStructFiles()
        
        if !rtStructFiles.isEmpty {
            let rtStructFile = rtStructFiles[0]
            
            do {
                let data = try Data(contentsOf: rtStructFile)
                let dataset = try DICOMParser.parse(data)
                
                if let simpleRTStruct = MinimalRTStructParser.parseSimpleRTStruct(from: dataset) {
                    roiData = simpleRTStruct
                    loadingProgress = "RTStruct loaded: \(simpleRTStruct.roiStructures.count) ROIs"
                } else {
                    loadingProgress = "RTStruct parsing failed - no geometry found"
                }
                
            } catch {
                loadingProgress = "Failed to load RTStruct: \(error.localizedDescription)"
            }
        } else {
            loadingProgress = "No RTStruct files found"
        }
    }
    
    private func loadPatientInfo() async {
        loadingProgress = "Loading patient information..."
        
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
                
                loadingProgress = "Patient information loaded"
                
            } catch {
                patientInfo = PatientInfo(
                    name: "Test Patient XAPV2",
                    studyDate: "2025-01-28",
                    modality: "CT"
                )
            }
        }
    }
    
    private func getDICOMFiles() -> [URL] {
        guard let bundlePath = Bundle.main.resourcePath else {
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
            
            return dicomFiles
            
        } catch {
            return []
        }
    }
    
    func getVolumeRenderer() -> MetalVolumeRenderer? {
        return volumeRenderer
    }
}

// MARK: - Supporting Types

struct PatientInfo {
    let name: String
    let studyDate: String
    let modality: String
}

// MARK: - Preview

struct XAnatomyProV2MainView_Previews: PreviewProvider {
    static var previews: some View {
        XAnatomyProV2MainView()
            .previewDevice("iPad Pro (12.9-inch)")
    }
}
