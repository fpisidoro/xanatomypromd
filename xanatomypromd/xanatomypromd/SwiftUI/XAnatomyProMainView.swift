import SwiftUI
import simd

// MARK: - Main Application View
// Clean production version without test functions and verbose logging

struct XAnatomyProMainView: View {
    
    // MARK: - State Management
    @StateObject var coordinateSystem = DICOMCoordinateSystem()
    @StateObject var sharedViewingState = SharedViewingState()
    @StateObject var dataCoordinator = ViewDataCoordinator()
    
    @State private var currentPlane: MPRPlane = .axial
    @State private var show3D: Bool = false
    @State private var showingControls = true
    
    // View configuration (unified gesture system)
    @State private var scale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    
    // REMOVED: Adaptive Quality and scrollVelocity (priority system deleted)
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Header
                    headerView
                    
                    // Main viewing area
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
    
    // MARK: - Main Viewing Area
    private func mainViewingArea(geometry: GeometryProxy) -> some View {
        ZStack {
            Group {
                if show3D {
                    Standalone3DView(
                        coordinateSystem: coordinateSystem,
                        sharedState: sharedViewingState,
                        dataCoordinator: dataCoordinator,
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
                        dataCoordinator: dataCoordinator,
                        viewSize: CGSize(
                            width: geometry.size.width,
                            height: geometry.size.height * 0.7
                        ),
                        allowInteraction: true
                    )
                }
            }
            .scaleEffect(scale)
            .offset(dragOffset)
            .clipped()
            .overlay(
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
                }
            }
            .onChange(of: dataCoordinator.volumeData) { _, volumeData in
                // Update coordinate system when volume data becomes available
                if let volumeData = volumeData {
                    coordinateSystem.initializeFromVolumeData(volumeData)
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
                
                Spacer()
                
                // Global loading status
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
    
    // MARK: - Unified Gesture Handlers
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
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
        let newSlice = currentSlice - data.direction
        let maxSlices = coordinateSystem.getMaxSlices(for: currentPlane)
        let clampedSlice = max(0, min(newSlice, maxSlices - 1))
        
        if clampedSlice != currentSlice {
            coordinateSystem.updateFromSliceScroll(plane: currentPlane, sliceIndex: clampedSlice)
        }
    }
    
    private func handleOneFingerScroll(_ data: UnifiedGestureHandler.GestureData) {
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: currentPlane)
        let newSlice = currentSlice - data.direction
        let maxSlices = coordinateSystem.getMaxSlices(for: currentPlane)
        let clampedSlice = max(0, min(newSlice, maxSlices - 1))
        
        if clampedSlice != currentSlice {
            coordinateSystem.updateFromSliceScroll(plane: currentPlane, sliceIndex: clampedSlice)
        }
    }
    
    private func handleScrollEnd(_ data: UnifiedGestureHandler.GestureData) {
        // Scroll gesture completed
    }
    
    private func handleZoomEnd(_ data: UnifiedGestureHandler.GestureData) {
        // Zoom gesture completed - could add haptic feedback here if needed
    }
    
    // MARK: - Action Methods
    private func resetViewTransform() {
        withAnimation(.spring()) {
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
            await dataCoordinator.loadAllData()
        }
    }
    
    // REMOVED: updateScrollVelocity (priority system deleted)
}

// MARK: - Supporting Types
struct PatientInfo {
    let name: String
    let studyDate: String
    let modality: String
}
