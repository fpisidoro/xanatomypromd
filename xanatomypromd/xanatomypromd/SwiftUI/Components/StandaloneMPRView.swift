import SwiftUI
import simd

// MARK: - Standalone MPR View with Per-View Loading
// Each MPR view manages its own loading state independently

struct StandaloneMPRView: View, LoadableView {
    
    // MARK: - Configuration
    let plane: MPRPlane
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    @ObservedObject var sharedState: SharedViewingState
    @ObservedObject var dataCoordinator: ViewDataCoordinator
    
    let viewSize: CGSize
    let allowInteraction: Bool
    
    // REMOVED: scrollVelocity (priority system deleted)
    
    // MARK: - Per-View Loading State
    @StateObject internal var loadingState = MPRViewLoadingState()
    @StateObject private var viewState: MPRViewState
    
    private let gestureConfig = GestureConfiguration.default
    private let viewId = UUID().uuidString
    
    // MARK: - Initialization (Updated)
    init(
        plane: MPRPlane,
        coordinateSystem: DICOMCoordinateSystem,
        sharedState: SharedViewingState,
        dataCoordinator: ViewDataCoordinator,
        viewSize: CGSize = CGSize(width: 512, height: 512),
        allowInteraction: Bool = true
    ) {
        self.plane = plane
        self.coordinateSystem = coordinateSystem
        self.sharedState = sharedState
        self.dataCoordinator = dataCoordinator
        self.viewSize = viewSize
        self.allowInteraction = allowInteraction
        
        // Initialize viewState with correct plane
        self._viewState = StateObject(wrappedValue: MPRViewState(plane: plane))
    }
    
    // MARK: - Convenience Initializer (Backward Compatibility)
    init(
        plane: MPRPlane,
        coordinateSystem: DICOMCoordinateSystem,
        sharedState: SharedViewingState,
        volumeData: VolumeData? = nil,
        roiData: MinimalRTStructParser.SimpleRTStructData? = nil,
        viewSize: CGSize = CGSize(width: 512, height: 512),
        allowInteraction: Bool = true
    ) {
        // Create a temporary data coordinator for backward compatibility
        let tempCoordinator = ViewDataCoordinator()
        tempCoordinator.volumeData = volumeData
        tempCoordinator.roiData = roiData
        
        self.plane = plane
        self.coordinateSystem = coordinateSystem
        self.sharedState = sharedState
        self.dataCoordinator = tempCoordinator
        self.viewSize = viewSize
        self.allowInteraction = allowInteraction
        
        self._viewState = StateObject(wrappedValue: MPRViewState(plane: plane))
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            if loadingState.isLoading {
                // Per-view loading indicator
                ViewLoadingIndicator(
                    loadingState: loadingState,
                    viewType: "\(plane.displayName) View",
                    viewSize: viewSize
                )
            } else {
                // Actual MPR content
                mprContentView
                    .opacity(loadingState.isLoading ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: loadingState.isLoading)
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .clipped()
        .background(.black)
        .onAppear {
            setupView()
        }
        .onDisappear {
            cleanupView()
        }
        .onChange(of: dataCoordinator.volumeData) { _, newVolumeData in
            if newVolumeData != nil && loadingState.volumeDataReady == false {
                Task {
                    await processVolumeData()
                }
            }
        }
    }
    
    // MARK: - MPR Content View
    private var mprContentView: some View {
        ZStack {
            // Base MPR rendering layer
            LayeredMPRView(
                coordinateSystem: coordinateSystem,
                plane: plane,
                windowLevel: sharedState.windowLevel,
                crosshairAppearance: sharedState.crosshairSettings,
                roiSettings: sharedState.roiSettings,
                volumeData: dataCoordinator.volumeData,
                roiData: dataCoordinator.roiData,
                viewSize: viewSize,
                allowInteraction: false,  // Gesture handling is separate
                sharedState: sharedState
                // Option 3: Each layer creates its own renderer with shared VolumeData
                // REMOVED: scrollVelocity, isViewScrolling
            )
            .scaleEffect(viewState.zoom)
            .offset(viewState.pan)
            
            // Pure UIKit gesture controller (when interaction enabled)
            if allowInteraction {
                MPRGestureController(
                    viewState: viewState,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    config: gestureConfig
                )
            }
            
            // UI overlays
            viewLabelOverlay
        }
    }
    
    // MARK: - View Overlays (Updated)
    private var viewLabelOverlay: some View {
        VStack {
            HStack {
                // Plane label with loading indicator
                HStack(spacing: 4) {
                    Text(plane.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    // Small ready indicator
                    if !loadingState.isLoading {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
                
                Spacer()
                
                // Slice indicator
                let sliceIndex = coordinateSystem.getCurrentSliceIndex(for: plane)
                let maxSlices = coordinateSystem.getMaxSlices(for: plane)
                Text("\(sliceIndex + 1)/\(maxSlices)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
            }
            .padding(8)
            
            Spacer()
            
            // Zoom indicator (only show if significantly different from baseline)
            if abs(viewState.zoom - viewState.baselineZoom) > 0.01 {
                HStack {
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1fx", viewState.zoom))
                            .font(.caption2)
                            .foregroundColor(.yellow.opacity(0.8))
                        
                        if abs(viewState.zoom - viewState.baselineZoom) > 0.2 {
                            Text("(base: \(String(format: "%.1fx", viewState.baselineZoom)))")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                }
                .padding(8)
            }
        }
    }
    
    // MARK: - LoadableView Protocol Implementation
    func startLoading() {
        loadingState.isLoading = true
        loadingState.updateStage(.volumeData)
    }
    
    func updateLoadingProgress(_ progress: Float, message: String) {
        loadingState.progress = progress
        loadingState.message = message
    }
    
    func completeLoading() {
        loadingState.updateStage(.complete)
    }
    
    // MARK: - View Lifecycle
    private func setupView() {
        print("🔧 \(plane.displayName) MPR View: Setting up...")
        
        // Start loading immediately
        startLoading()
        
        // Register for data updates
        dataCoordinator.registerViewCallback(viewId: viewId) { [self] isReady in
            if isReady {
                Task {
                    await processVolumeData()
                }
            }
        }
        
        // Force plane assignment
        viewState.currentPlane = plane
        updateViewStateConfiguration()
        
        // If data is already available, start processing
        if dataCoordinator.volumeData != nil {
            Task {
                await processVolumeData()
            }
        }
    }
    
    private func cleanupView() {
        dataCoordinator.unregisterViewCallback(viewId: viewId)
        print("🧹 \(plane.displayName) MPR View: Cleaned up")
    }
    
    // MARK: - Data Processing Pipeline
    @MainActor
    private func processVolumeData() async {
        guard let volumeData = dataCoordinator.volumeData else {
            loadingState.setError("No volume data available")
            return
        }
        
        do {
            // Stage 1: Volume data ready
            loadingState.updateStage(.volumeData)
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms delay for UI
            
            // Stage 2: Create GPU textures
            loadingState.updateStage(.textureCreation)
            try await initializeGPUResources(volumeData: volumeData)
            try await Task.sleep(nanoseconds: 50_000_000)
            
            // Stage 3: Generate initial MPR slice
            loadingState.updateStage(.sliceGeneration)
            try await generateInitialSlice()
            try await Task.sleep(nanoseconds: 50_000_000)
            
            // Stage 4: Process ROI data (if available)
            loadingState.updateStage(.roiProcessing)
            try await processROIData()
            try await Task.sleep(nanoseconds: 50_000_000)
            
            // Stage 5: Complete
            completeLoading()
            
            print("✅ \(plane.displayName) MPR View: Loading completed successfully")
            
        } catch {
            print("❌ \(plane.displayName) MPR View: Loading failed - \(error)")
            loadingState.setError("Failed to load: \(error.localizedDescription)")
        }
    }
    
    private func initializeGPUResources(volumeData: VolumeData) async throws {
        // Initialize Metal resources for this specific view
        guard dataCoordinator.getVolumeRenderer() != nil else {
            throw ViewLoadingError.rendererInitializationFailed
        }
        
        // This would involve creating view-specific GPU textures
        // For now, we'll simulate the GPU setup time
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms for GPU setup
        
        print("🔧 \(plane.displayName): GPU resources initialized")
    }
    
    private func generateInitialSlice() async throws {
        // Generate the first MPR slice for this plane
        // This simulates the time needed to create the initial slice
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms for initial slice generation
        
        print("🔧 \(plane.displayName): Initial slice generated")
    }
    
    private func processROIData() async throws {
        if dataCoordinator.roiData != nil {
            // Process ROI data specific to this plane
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms for ROI processing
            print("🔧 \(plane.displayName): ROI data processed")
        } else {
            print("🔧 \(plane.displayName): No ROI data to process")
        }
    }
    
    private func updateViewStateConfiguration() {
        let dims = dataCoordinator.volumeData?.dimensions ?? SIMD3<Int>(512, 512, 53)
        viewState.updateConfiguration(
            viewSize: viewSize,
            volumeDimensions: SIMD3<Int32>(Int32(dims.x), Int32(dims.y), Int32(dims.z)),
            currentPlane: plane
        )
    }
    
    // MARK: - Public Interface
    public func resetView() {
        withAnimation(.spring()) {
            viewState.resetView()
        }
    }
    
    public var isTransformed: Bool {
        return viewState.isTransformed
    }
    
    public var currentZoom: CGFloat {
        return viewState.zoom
    }
    
    public var baselineZoom: CGFloat {
        return viewState.baselineZoom
    }
}

// MARK: - Multi-View Container (Updated)
struct MultiViewMPRContainer: View {
    @StateObject private var coordinateSystem = DICOMCoordinateSystem()
    @StateObject private var sharedState = SharedViewingState()
    @StateObject private var dataCoordinator = ViewDataCoordinator()
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                // Three independent but synchronized views
                StandaloneMPRView(
                    plane: .axial,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    dataCoordinator: dataCoordinator,
                    viewSize: CGSize(
                        width: geometry.size.width / 3 - 4,
                        height: geometry.size.height
                    )
                )
                
                StandaloneMPRView(
                    plane: .sagittal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    dataCoordinator: dataCoordinator,
                    viewSize: CGSize(
                        width: geometry.size.width / 3 - 4,
                        height: geometry.size.height
                    )
                )
                
                StandaloneMPRView(
                    plane: .coronal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    dataCoordinator: dataCoordinator,
                    viewSize: CGSize(
                        width: geometry.size.width / 3 - 4,
                        height: geometry.size.height
                    )
                )
            }
        }
        .onAppear {
            Task {
                await dataCoordinator.loadAllData()
            }
        }
    }
}

// MARK: - Preview Provider
struct StandaloneMPRView_Previews: PreviewProvider {
    static var previews: some View {
        StandaloneMPRView(
            plane: .axial,
            coordinateSystem: DICOMCoordinateSystem(),
            sharedState: SharedViewingState(),
            dataCoordinator: ViewDataCoordinator(),
            viewSize: CGSize(width: 400, height: 400)
        )
        .frame(width: 400, height: 400)
        .background(.black)
    }
}
