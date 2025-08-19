import SwiftUI
import simd

// MARK: - Updated Main Application View
// No more global loading overlay - each view manages its own loading

struct XAnatomyProMainView: View {
    
    // MARK: - State Management
    @StateObject var coordinateSystem = DICOMCoordinateSystem()
    @StateObject var sharedViewingState = SharedViewingState()
    @StateObject var dataCoordinator = ViewDataCoordinator()  // NEW: Centralized data coordinator
    
    @State private var currentPlane: MPRPlane = .axial
    @State private var show3D: Bool = false
    @State private var showingControls = true
    
    // View configuration (unified gesture system)
    @State private var scale: CGFloat = 1.0
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
                    
                    // Main viewing area - NO MORE GLOBAL LOADING OVERLAY
                    mainViewingArea(geometry: geometry)
                    
                    // Control buttons
                    controlButtons
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
                
                if let patientInfo = dataCoordinator.patientInfo {
                    Text(patientInfo.name)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(show3D ? "3D Volume" : currentPlane.displayName)
                    .font(.headline)
                    .foregroundColor(.blue)
                
                if !show3D {
                    let sliceIndex = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
                    let maxSlices = coordinateSystem.getMaxSlices(for: currentPlane)
                    Text("Slice \(sliceIndex + 1)/\(maxSlices)")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                
                Text(sharedViewingState.windowLevel.name)
                    .font(.caption2)
                    .foregroundColor(.gray)
                
                // Global data status
                HStack(spacing: 4) {
                    if dataCoordinator.volumeData != nil {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Volume")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    
                    if dataCoordinator.roiData != nil {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 6, height: 6)
                        Text("ROI")
                            .font(.caption2)
                            .foregroundColor(.cyan)
                    }
                }
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
    
    // MARK: - Main Viewing Area (Per-View Loading)
    private func mainViewingArea(geometry: GeometryProxy) -> some View {
        ZStack {
            // Each view now manages its own loading state
            Group {
                if show3D {
                    Standalone3DView(
                        coordinateSystem: coordinateSystem,
                        sharedState: sharedViewingState,
                        dataCoordinator: dataCoordinator,  // Pass data coordinator
                        viewSize: CGSize(
                            width: geometry.size.width,
                            height: geometry.size.height * 0.7
                        ),
                        allowInteraction: true
                    )
                } else {
                    StandaloneMPRView(
                        plane: currentPlane,
                        coordinateSystem: coordinateSystem,
                        sharedState: sharedViewingState,
                        dataCoordinator: dataCoordinator,  // Pass data coordinator
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
            .overlay(
                // PURE UIKIT GESTURE HANDLING (only when not loading)
                UnifiedGestureHandler(
                    onGesture: handleUnifiedGesture,
                    onZoomChange: handleZoomChange,
                    viewSize: CGSize(
                        width: geometry.size.width,
                        height: geometry.size.height * 0.7
                    ),
                    volumeDimensions: {
                        let dims = dataCoordinator.volumeData?.dimensions ?? SIMD3<Int>(512, 512, 53)
                        return SIMD3<Int32>(Int32(dims.x), Int32(dims.y), Int32(dims.z))
                    }(),
                    currentPlane: currentPlane
                )
            )
            .onAppear {
                // Initialize coordinate system when volume data is loaded
                if let volumeData = dataCoordinator.volumeData {
                    coordinateSystem.initializeFromVolumeData(volumeData)
                    print("✅ Coordinate system initialized with volume dimensions: \(volumeData.dimensions)")
                }
            }
            .onChange(of: dataCoordinator.volumeData) { _, volumeData in
                // Update coordinate system when volume data becomes available
                if let volumeData = volumeData {
                    coordinateSystem.initializeFromVolumeData(volumeData)
                    print("✅ Coordinate system updated with new volume data")
                }
            }
        }
        .frame(height: geometry.size.height * 0.7)
    }
    
    // MARK: - Control Buttons
    private var controlButtons: some View {
        VStack(spacing: 8) {
            // Plane selection buttons
            HStack {
                Button("AXIAL") { 
                    currentPlane = .axial
                    show3D = false 
                }
                .foregroundColor(currentPlane == .axial && !show3D ? .blue : .white)
                .padding()
                
                Button("SAGITTAL") { 
                    currentPlane = .sagittal
                    show3D = false 
                }
                .foregroundColor(currentPlane == .sagittal && !show3D ? .blue : .white)
                .padding()
                
                Button("CORONAL") { 
                    currentPlane = .coronal
                    show3D = false 
                }
                .foregroundColor(currentPlane == .coronal && !show3D ? .blue : .white)
                .padding()
                
                Button("3D") { show3D = true }
                    .foregroundColor(show3D ? .blue : .white)
                    .padding()
            }
            
            // Window level buttons
            HStack {
                Button("BONE") { sharedViewingState.setWindowLevel(.bone) }
                    .foregroundColor(.red)
                    .padding()
                Button("LUNG") { sharedViewingState.setWindowLevel(.lung) }
                    .foregroundColor(.red)
                    .padding()
                Button("SOFT") { sharedViewingState.setWindowLevel(.softTissue) }
                    .foregroundColor(.red)
                    .padding()
            }
            
            // Action buttons
            HStack {
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
                
                // Global loading status (if any views are still loading)
                if dataCoordinator.isVolumeLoading {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                            .scaleEffect(0.8)
                        Text("Loading data...")
                            .font(.caption2)
                            .foregroundColor(.cyan)
                    }
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Unified Gesture Handlers (unchanged)
    private func handleUnifiedGesture(_ type: UnifiedGestureHandler.GestureType, _ data: UnifiedGestureHandler.GestureData) {
        switch type {
        case .pan:
            handlePanGesture(data)
        case .pinch:
            break // Handled by handleZoomChange
        case .twoFingerScroll:
            handleTwoFingerScroll(data)
        case .oneFingerScroll:
            handleOneFingerScroll(data)
        case .scrollEnd:
            handleScrollEnd(data)
        case .zoomEnd:
            handleZoomEnd(data)
        }
    }
    
    private func handleZoomChange(_ newZoom: CGFloat) {
        scale = newZoom
    }
    
    private func handlePanGesture(_ data: UnifiedGestureHandler.GestureData) {
        dragOffset = CGSize(width: data.translation.x, height: data.translation.y)
    }
    
    private func handleTwoFingerScroll(_ data: UnifiedGestureHandler.GestureData) {
        updateScrollVelocity(Float(data.speed))
        
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
        let newSlice = currentSlice - data.direction
        let maxSlices = coordinateSystem.getMaxSlices(for: currentPlane)
        let clampedSlice = max(0, min(newSlice, maxSlices - 1))
        
        if clampedSlice != currentSlice {
            coordinateSystem.updateFromSliceScroll(plane: currentPlane, sliceIndex: clampedSlice)
        }
    }
    
    private func handleOneFingerScroll(_ data: UnifiedGestureHandler.GestureData) {
        updateScrollVelocity(Float(data.speed))
        
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
        let newSlice = currentSlice - data.direction
        let maxSlices = coordinateSystem.getMaxSlices(for: currentPlane)
        let clampedSlice = max(0, min(newSlice, maxSlices - 1))
        
        if clampedSlice != currentSlice {
            coordinateSystem.updateFromSliceScroll(plane: currentPlane, sliceIndex: clampedSlice)
        }
    }
    
    private func handleScrollEnd(_ data: UnifiedGestureHandler.GestureData) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.2)) {
                self.scrollVelocity = 0.0
                self.currentQuality = .full
            }
        }
    }
    
    private func handleZoomEnd(_ data: UnifiedGestureHandler.GestureData) {
        print("🔄 Zoom gesture completed at \(String(format: "%.2f", data.zoomLevel))x")
    }
    
    // MARK: - Action Methods (unchanged)
    private func resetViewTransform() {
        withAnimation(.spring()) {
            dragOffset = .zero
        }
        print("🔄 Reset View Transform requested")
    }
    
    private func centerCrosshair() {
        let centerX = coordinateSystem.volumeOrigin.x + (Float(coordinateSystem.volumeDimensions.x) * coordinateSystem.volumeSpacing.x) / 2.0
        let centerY = coordinateSystem.volumeOrigin.y + (Float(coordinateSystem.volumeDimensions.y) * coordinateSystem.volumeSpacing.y) / 2.0
        let centerZ = coordinateSystem.volumeOrigin.z + (Float(coordinateSystem.volumeDimensions.z) * coordinateSystem.volumeSpacing.z) / 2.0
        
        coordinateSystem.updateWorldPosition(SIMD3<Float>(centerX, centerY, centerZ))
    }
    
    private func loadApplicationData() {
        Task {
            await dataCoordinator.loadAllData()
        }
    }
    
    private func testRTStructParsing() {
        print("\n🧪 MANUAL RTStruct Test Called")
        debugROISystem()
        
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
    
    private func updateScrollVelocity(_ velocity: Float) {
        scrollVelocity = velocity
        
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
        
        qualityTimer?.invalidate()
        qualityTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.scrollVelocity = 0.0
                    self.currentQuality = .full
                }
            }
        }
    }
}

// MARK: - Supporting Types (unchanged)
struct PatientInfo {
    let name: String
    let studyDate: String
    let modality: String
}
