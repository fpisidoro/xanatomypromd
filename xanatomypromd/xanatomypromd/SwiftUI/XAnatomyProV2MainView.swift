import SwiftUI
import simd
import MetalKit

// MARK: - X-Anatomy Pro v2.0 Main View
// Uses the new modular StandaloneMPRView architecture

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
    
    // 2-finger gesture tracking
    @GestureState private var twoFingerDrag = CGSize.zero
    @State private var lastDragPosition = CGSize.zero
    
    enum ScrollQuality: Int {
        case full = 1, half = 2, quarter = 4
        
        var description: String {
            switch self {
            case .full: return "Full"
            case .half: return "Half" 
            case .quarter: return "Quarter"
            }

// MARK: - UIKit 2-Finger Gesture Handler

struct TwoFingerScrollHandler: UIViewRepresentable {
    let onScroll: (Int, CGFloat) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 2
        panGesture.maximumNumberOfTouches = 2
        view.addGestureRecognizer(panGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }
    
    class Coordinator: NSObject {
        let onScroll: (Int, CGFloat) -> Void
        private var lastTranslation: CGFloat = 0
        
        init(onScroll: @escaping (Int, CGFloat) -> Void) {
            self.onScroll = onScroll
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            switch gesture.state {
            case .began:
                lastTranslation = translation.y
            case .changed:
                let deltaY = translation.y - lastTranslation
                if abs(deltaY) > 8 {
                    let direction = deltaY > 0 ? 1 : -1
                    let speed = abs(velocity.y)
                    onScroll(direction, speed)
                    lastTranslation = translation.y
                }
            case .ended, .cancelled:
                lastTranslation = 0
            default:
                break
            }
        }
    }
}
        }
    }
    
    enum ViewType {
        case axial
        case sagittal
        case coronal
        case threeDimensional
        
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
        case single
        case double
        case triple
        case quad
        case automatic
        
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
                    // Compact header
                    if showControls {
                        headerBar
                    }
                    
                    // Main content area
                    if isLoading {
                        // Loading view
                        MedicalProgressView(
                            current: dataManager.loadingCurrent,
                            total: dataManager.loadingTotal,
                            message: dataManager.loadingProgress.isEmpty ? "Initializing..." : dataManager.loadingProgress
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // MPR Views with navigation overlay
                        ZStack {
                            mprViewsLayout(in: geometry)
                                .background(
                                    TwoFingerScrollHandler(
                                        onScroll: { direction, velocity in
                                            handleTwoFingerScroll(direction: direction, velocity: velocity)
                                        }
                                    )
                                )
                            
                            // PERSISTENT slice navigation overlay
                            sliceNavigationOverlay(in: geometry)
                        }
                    }
                    
                    // Bottom controls
                    if showControls && !isLoading {
                        bottomControls
                    }
                }
                
                // PERSISTENT controls - always visible
                persistentControls
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startLoading()
            determineOptimalLayout()
        }
    }
    
    // MARK: - Persistent Controls (Always Visible)
    
    private var persistentControls: some View {
        VStack {
            HStack {
                Spacer()
                
                // ALWAYS-visible toggle button (never hidden)
                Button(action: { withAnimation { showControls.toggle() } }) {
                    Image(systemName: showControls ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Circle())
                }
                .padding(.trailing, 16)
                .padding(.top, 8)
                .zIndex(1000) // Ensure it's on top
            }
            
            Spacer()
            
            // Persistent slice indicator (bottom-left)
            if !isLoading && !showControls {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedSingleViewPlane.displayName)
                            .font(.caption)
                            .foregroundColor(.white)
                        
                        if let plane = selectedSingleViewPlane.mprPlane {
                            let currentSlice = coordinateSystem.getCurrentSliceIndex(for: plane)
                            let totalSlices = coordinateSystem.getMaxSlices(for: plane)
                            
                            Text("\(currentSlice + 1)/\(totalSlices)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(6)
                    
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.bottom, 16)
            }
        }
    }
    
    // MARK: - Slice Navigation Overlay
    
    private func sliceNavigationOverlay(in geometry: GeometryProxy) -> some View {
        HStack {
            // Left navigation area
            Button(action: previousSlice) {
                Image(systemName: "chevron.left")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(width: 60, height: geometry.size.height * 0.8)
            .contentShape(Rectangle())
            .disabled(!canNavigatePrevious())
            
            Spacer()
            
            // Right navigation area  
            Button(action: nextSlice) {
                Image(systemName: "chevron.right")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(width: 60, height: geometry.size.height * 0.8)
            .contentShape(Rectangle())
            .disabled(!canNavigateNext())
        }
        .background(Color.clear)
    }
    
    // MARK: - Navigation Helpers
    
    private func previousSlice() {
        guard let plane = selectedSingleViewPlane.mprPlane else { return }
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: plane)
        if currentSlice > 0 {
            // Update world position to move to previous slice
            var newPos = coordinateSystem.currentWorldPosition
            let axis = plane.sliceAxis
            newPos[axis] -= coordinateSystem.volumeSpacing[axis]
            coordinateSystem.currentWorldPosition = newPos
        }
    }
    
    private func nextSlice() {
        guard let plane = selectedSingleViewPlane.mprPlane else { return }
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: plane)
        let totalSlices = coordinateSystem.getMaxSlices(for: plane)
        if currentSlice < totalSlices - 1 {
            // Update world position to move to next slice
            var newPos = coordinateSystem.currentWorldPosition
            let axis = plane.sliceAxis
            newPos[axis] += coordinateSystem.volumeSpacing[axis]
            coordinateSystem.currentWorldPosition = newPos
        }
    }
    
    private func canNavigatePrevious() -> Bool {
        guard let plane = selectedSingleViewPlane.mprPlane else { return false }
        return coordinateSystem.getCurrentSliceIndex(for: plane) > 0
    }
    
    private func canNavigateNext() -> Bool {
        guard let plane = selectedSingleViewPlane.mprPlane else { return false }
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: plane)
        let totalSlices = coordinateSystem.getMaxSlices(for: plane)
        return currentSlice < totalSlices - 1
    }
    
    // MARK: - Layout Selection
    
    @ViewBuilder
    private func mprViewsLayout(in geometry: GeometryProxy) -> some View {
        let effectiveLayout = resolveEffectiveLayout(for: geometry.size)
        
        switch effectiveLayout {
        case .single:
            singleViewLayout(in: geometry)
        case .double:
            doubleViewLayout(in: geometry)
        case .triple:
            tripleViewLayout(in: geometry)
        case .quad:
            quadViewLayout(in: geometry)
        case .automatic:
            // Should never reach here
            singleViewLayout(in: geometry)
        }
    }
    
    // MARK: - Layout Implementations
    
    private func singleViewLayout(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Plane selector for single view
            if layoutMode == .single {
                Picker("", selection: $selectedSingleViewPlane) {
                    Text("Axial").tag(ViewType.axial)
                    Text("Sag").tag(ViewType.sagittal)
                    Text("Cor").tag(ViewType.coronal)
                    Text("3D").tag(ViewType.threeDimensional)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            
            if selectedSingleViewPlane == .threeDimensional {
                Standalone3DView(
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: calculateViewSize(for: .single, in: geometry),
                    allowInteraction: true
                )
            } else if let plane = selectedSingleViewPlane.mprPlane {
                StandaloneMPRView(
                    plane: plane,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: calculateViewSize(for: .single, in: geometry),
                    allowInteraction: true
                )
            }
        }
    }
    
    private func doubleViewLayout(in geometry: GeometryProxy) -> some View {
        HStack(spacing: 2) {
            StandaloneMPRView(
                plane: .axial,
                coordinateSystem: coordinateSystem,
                sharedState: sharedState,
                volumeData: dataManager.volumeData,
                roiData: dataManager.roiData,
                viewSize: calculateViewSize(for: .double, in: geometry),
                allowInteraction: true
            )
            
            StandaloneMPRView(
                plane: .sagittal,
                coordinateSystem: coordinateSystem,
                sharedState: sharedState,
                volumeData: dataManager.volumeData,
                roiData: dataManager.roiData,
                viewSize: calculateViewSize(for: .double, in: geometry),
                allowInteraction: true
            )
        }
    }
    
    private func tripleViewLayout(in geometry: GeometryProxy) -> some View {
        HStack(spacing: 2) {
            StandaloneMPRView(
                plane: .axial,
                coordinateSystem: coordinateSystem,
                sharedState: sharedState,
                volumeData: dataManager.volumeData,
                roiData: dataManager.roiData,
                viewSize: calculateViewSize(for: .triple, in: geometry),
                allowInteraction: true
            )
            
            StandaloneMPRView(
                plane: .sagittal,
                coordinateSystem: coordinateSystem,
                sharedState: sharedState,
                volumeData: dataManager.volumeData,
                roiData: dataManager.roiData,
                viewSize: calculateViewSize(for: .triple, in: geometry),
                allowInteraction: true
            )
            
            StandaloneMPRView(
                plane: .coronal,
                coordinateSystem: coordinateSystem,
                sharedState: sharedState,
                volumeData: dataManager.volumeData,
                roiData: dataManager.roiData,
                viewSize: calculateViewSize(for: .triple, in: geometry),
                allowInteraction: true
            )
        }
    }
    
    private func quadViewLayout(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                StandaloneMPRView(
                    plane: .axial,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: calculateViewSize(for: .quad, in: geometry),
                    allowInteraction: true
                )
                
                StandaloneMPRView(
                    plane: .sagittal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: calculateViewSize(for: .quad, in: geometry),
                    allowInteraction: true
                )
            }
            
            HStack(spacing: 2) {
                StandaloneMPRView(
                    plane: .coronal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: calculateViewSize(for: .quad, in: geometry),
                    allowInteraction: true
                )
                
                // Fourth quadrant - 3D view
                Standalone3DView(
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: calculateViewSize(for: .quad, in: geometry),
                    allowInteraction: true
                )
            }
        }
    }
    
    // MARK: - Controls
    
    private var headerBar: some View {
        HStack {
            // App title
            Text("X-Anatomy Pro v2.0")
                .font(.headline)
                .foregroundColor(.white)
            
            if let patientInfo = dataManager.patientInfo {
                Text("• \(patientInfo.name)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Layout selector
            HStack(spacing: 12) {
                ForEach([LayoutMode.single, .double, .triple, .quad], id: \.self) { mode in
                    Button(action: { layoutMode = mode }) {
                        Text(mode.displayName)
                            .font(.caption)
                            .foregroundColor(layoutMode == mode ? .black : .white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(layoutMode == mode ? Color.cyan : Color.gray.opacity(0.3))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.9))
    }
    
    private var bottomControls: some View {
        VStack(spacing: 8) {
            // Slice slider when controls are visible
            if let plane = selectedSingleViewPlane.mprPlane {
                HStack {
                    Text("Slice")
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    Slider(
                        value: Binding(
                            get: { Double(coordinateSystem.getCurrentSliceIndex(for: plane)) },
                            set: { newValue in
                                let targetSlice = Int(newValue)
                                let currentSlice = coordinateSystem.getCurrentSliceIndex(for: plane)
                                let sliceDiff = targetSlice - currentSlice
                                var newPos = coordinateSystem.currentWorldPosition
                                let axis = plane.sliceAxis
                                newPos[axis] += Float(sliceDiff) * coordinateSystem.volumeSpacing[axis]
                                coordinateSystem.currentWorldPosition = newPos
                            }
                        ),
                        in: 0...Double(coordinateSystem.getMaxSlices(for: plane) - 1),
                        step: 1
                    )
                    .accentColor(.cyan)
                    
                    Text("\(coordinateSystem.getCurrentSliceIndex(for: plane) + 1)/\(coordinateSystem.getMaxSlices(for: plane))")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(width: 60)
                }
            }
            
            HStack(spacing: 20) {
                // Window level
                Menu {
                    ForEach(CTWindowLevel.allPresets, id: \.name) { preset in
                        Button(preset.name) {
                            sharedState.setWindowLevel(preset)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text(sharedState.windowLevel.name)
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.3))
                    .cornerRadius(6)
                }
                
                // Crosshairs
                Button(action: { sharedState.toggleCrosshairs() }) {
                    HStack {
                        Image(systemName: sharedState.crosshairSettings.isVisible ? "plus.circle.fill" : "plus.circle")
                        Text("Crosshairs")
                            .font(.caption)
                    }
                    .foregroundColor(sharedState.crosshairSettings.isVisible ? .cyan : .gray)
                }
                
                // ROI
                Button(action: { sharedState.toggleROIOverlay() }) {
                    HStack {
                        Image(systemName: sharedState.roiSettings.isVisible ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                        Text("ROI")
                            .font(.caption)
                    }
                    .foregroundColor(sharedState.roiSettings.isVisible ? .green : .gray)
                }
                
                Spacer()
                
                // Status
                HStack(spacing: 8) {
                    if dataManager.isVolumeLoaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    if dataManager.isROILoaded {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.9))
    }
    
    // MARK: - Helper Methods
    
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
        
        // Auto-detect based on screen size
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
    
    private func determineOptimalLayout() {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            layoutMode = .single
        } else {
            layoutMode = .triple  // Default for iPad
        }
        #else
        layoutMode = .triple
        #endif
    }
    
    private func startLoading() {
        Task {
            await dataManager.loadAllData()
            
            // Initialize coordinate system
            if let volumeData = dataManager.volumeData {
                coordinateSystem.initializeFromVolumeData(volumeData)
            }
            
            isLoading = false
        }
    }
    
    // MARK: - Adaptive Quality Methods
    
    private func updateScrollVelocity(_ velocity: CGFloat) {
        scrollVelocity = Float(velocity)
        lastSliceChange = Date()
        
        // Update quality based on velocity  
        let newQuality: ScrollQuality
        if scrollVelocity > 0.5 {
            newQuality = .quarter
        } else if scrollVelocity > 0.25 {
            newQuality = .half
        } else {
            newQuality = .full
        }
        
        if newQuality != currentQuality {
            currentQuality = newQuality
            // Pass quality to shared state for renderer
            Task { @MainActor in
                sharedState.renderQuality = newQuality.rawValue
            }
        }
        
        // Reset timer
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
    
    private func handleTwoFingerScroll(direction: Int, velocity: CGFloat) {
        updateScrollVelocity(velocity)
        
        switch layoutMode {
        case .single:
            if let plane = selectedSingleViewPlane.mprPlane {
                navigateSlice(plane: plane, direction: direction)
            }
        default:
            // Multi-view: update axial
            navigateSlice(plane: .axial, direction: direction)
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
}

// MARK: - Preview

struct XAnatomyProV2MainView_Previews: PreviewProvider {
    static var previews: some View {
        XAnatomyProV2MainView()
            .previewDevice("iPad Pro (12.9-inch)")
            .previewDisplayName("iPad Pro")
        
        XAnatomyProV2MainView()
            .previewDevice("iPhone 14 Pro")
            .previewDisplayName("iPhone")
    }
}
