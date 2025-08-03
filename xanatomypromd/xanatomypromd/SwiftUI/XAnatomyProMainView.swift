import SwiftUI
import simd

// MARK: - Main Application Integration
// Replaces the complex DICOMViewerView with clean layered architecture

struct XAnatomyProMainView: View {
    
    // MARK: - State Management
    
    @StateObject private var coordinateSystem = DICOMCoordinateSystem()
    @StateObject private var dataManager = XAnatomyDataManager()
    
    @State private var currentPlane: MPRPlane = .axial
    @State private var windowLevel: CTWindowLevel = CTWindowLevel.softTissue
    @State private var crosshairSettings = CrosshairAppearance.default
    @State private var roiSettings = ROIDisplaySettings.default
    @State private var isLoading = true
    @State private var showingControls = true
    
    // View configuration
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    
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
                
                Text(windowLevel.name)
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
                LayeredMPRView(
                    coordinateSystem: coordinateSystem,
                    plane: currentPlane,
                    windowLevel: windowLevel,
                    crosshairAppearance: crosshairSettings,
                    roiSettings: roiSettings,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: CGSize(
                        width: geometry.size.width,
                        height: geometry.size.height * 0.7
                    ),
                    allowInteraction: true
                )
                .scaleEffect(scale)
                .offset(dragOffset)
                .clipped()
                .gesture(panGesture)
                .gesture(zoomGesture)
                .overlay(sliceNavigationOverlay(geometry: geometry))
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
                    Button(action: { currentPlane = plane }) {
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
                        .background(currentPlane == plane ? Color.blue : Color.gray.opacity(0.3))
                        .cornerRadius(8)
                    }
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
                        Button(action: { windowLevel = preset }) {
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
                            .background(windowLevel.name == preset.name ? Color.blue : Color.gray.opacity(0.3))
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
                    get: { crosshairSettings.isVisible },
                    set: { isVisible in
                        crosshairSettings = CrosshairAppearance(
                            isVisible: isVisible,
                            color: crosshairSettings.color,
                            opacity: crosshairSettings.opacity,
                            lineWidth: crosshairSettings.lineWidth,
                            fadeDistance: crosshairSettings.fadeDistance
                        )
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                
                Spacer()
                
                Toggle("ROI Overlay", isOn: Binding(
                    get: { roiSettings.isVisible },
                    set: { isVisible in
                        roiSettings = ROIDisplaySettings(
                            isVisible: isVisible,
                            globalOpacity: roiSettings.globalOpacity,
                            showOutline: roiSettings.showOutline,
                            showFilled: roiSettings.showFilled,
                            outlineWidth: roiSettings.outlineWidth,
                            outlineOpacity: roiSettings.outlineOpacity,
                            fillOpacity: roiSettings.fillOpacity,
                            sliceTolerance: roiSettings.sliceTolerance
                        )
                    }
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
            
            Spacer()
            
            statusIndicator
        }
    }
    
    // MARK: - Helper Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView("Loading...")
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .foregroundColor(.white)
            
            if dataManager.isVolumeLoaded {
                Text("✅ Volume Ready")
                    .foregroundColor(.green)
            }
            
            if dataManager.isROILoaded {
                Text("✅ ROI Ready")
                    .foregroundColor(.green)
            }
        }
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
    
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in dragOffset = value.translation }
            .onEnded { _ in withAnimation(.spring()) { dragOffset = .zero } }
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
}

// MARK: - Data Manager

@MainActor
class XAnatomyDataManager: ObservableObject {
    @Published var volumeData: VolumeData?
    @Published var roiData: RTStructData?
    @Published var patientInfo: PatientInfo?
    @Published var isLoading = false
    
    var isVolumeLoaded: Bool { volumeData != nil }
    var isROILoaded: Bool { roiData != nil }
    
    func loadAllData() async {
        isLoading = true
        await loadVolumeData()
        await loadROIData()
        await loadPatientInfo()
        isLoading = false
    }
    
    private func loadVolumeData() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        print("📊 Volume data loaded (simulated)")
    }
    
    private func loadROIData() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        print("🎨 ROI data loaded (simulated)")
    }
    
    private func loadPatientInfo() async {
        patientInfo = PatientInfo(
            name: "Test Patient XAPV2",
            studyDate: "2025-01-28",
            modality: "CT"
        )
        print("👤 Patient info loaded")
    }
}

// MARK: - Supporting Types

struct PatientInfo {
    let name: String
    let studyDate: String
    let modality: String
}
