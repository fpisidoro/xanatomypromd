import SwiftUI
import simd
import MetalKit

// MARK: - X-Anatomy Pro v2.0 Main View with 2-Finger Scrolling
// Clean implementation with proper UIKit gesture integration

struct XAnatomyProV2MainView: View {
    
    // MARK: - Shared State
    @StateObject private var coordinateSystem = DICOMCoordinateSystem()
    @StateObject private var sharedState = SharedViewingState()
    @StateObject private var dataCoordinator = ViewDataCoordinator()
    
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
                            current: dataCoordinator.loadingCurrent,
                            total: dataManager.loadingTotal,
                            message: dataManager.loadingProgress.isEmpty ? "Initializing..." : dataManager.loadingProgress
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ZStack {
                            mprViewsLayout(in: geometry)
                            
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
        
        // FIXED: Lower thresholds for better responsiveness, especially in quad mode
        let effectiveLayout = resolveEffectiveLayout(for: UIScreen.main.bounds.size)
        let velocityMultiplier = effectiveLayout == .quad ? 0.5 : 1.0  // Quad mode is more sensitive
        
        let adjustedVelocity = scrollVelocity * Float(velocityMultiplier)
        
        let newQuality: ScrollQuality
        if adjustedVelocity > 200 {  // Reduced from 500
            newQuality = .quarter
        } else if adjustedVelocity > 100 {  // Reduced from 250
            newQuality = .half
        } else {
            newQuality = .full
        }
        
        if newQuality != currentQuality {
            currentQuality = newQuality
            Task { @MainActor in
                // FIXED: Apply quality to ALL planes, not just axial
                applyQualityToAllViews(quality: newQuality)
            }
        }
        
        qualityTimer?.invalidate()
        qualityTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in  // Faster restore
            Task { @MainActor in
                if currentQuality != .full {
                    currentQuality = .full
                    // FIXED: Restore quality to ALL planes
                    applyQualityToAllViews(quality: .full)
                }
            }
        }
    }
    
    // FIXED: Apply quality changes to all visible views based on layout mode
    private func applyQualityToAllViews(quality: ScrollQuality) {
        let effectiveLayout = resolveEffectiveLayout(for: UIScreen.main.bounds.size)
        
        switch effectiveLayout {
        case .single:
            if let plane = selectedSingleViewPlane.mprPlane {
                sharedState.setQuality(for: plane, quality: quality.rawValue)
            }
        case .triple:
            // Apply to all three MPR planes
            sharedState.setQuality(for: .axial, quality: quality.rawValue)
            sharedState.setQuality(for: .sagittal, quality: quality.rawValue)
            sharedState.setQuality(for: .coronal, quality: quality.rawValue)
        case .quad:
            // Apply to all three MPR planes (3D doesn't use quality setting)
            sharedState.setQuality(for: .axial, quality: quality.rawValue)
            sharedState.setQuality(for: .sagittal, quality: quality.rawValue)
            sharedState.setQuality(for: .coronal, quality: quality.rawValue)
        default:
            // Default to axial for other layouts
            sharedState.setQuality(for: .axial, quality: quality.rawValue)
        }
        
        // Debug logging
        print("🎛️ Applied quality \(quality.description) to \(effectiveLayout.displayName) layout")
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
                
                Button("2x2") {
                    layoutMode = .quad
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
                .id("3d-view")  // 🔧 FIX: Force unique @StateObject identity
            } else {
                StandaloneMPRView(
                    plane: selectedSingleViewPlane.mprPlane ?? .axial,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: viewSize,
                    allowInteraction: true,
                    scrollVelocity: scrollVelocity  // NEW: Pass scroll velocity
                )
                .id("single-\(selectedSingleViewPlane.displayName.lowercased())")  // 🔧 FIX: Unique identity per plane
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
                    allowInteraction: true,
                    scrollVelocity: scrollVelocity  // NEW: Pass scroll velocity
                )
                .id("axial-view")  // 🔧 FIX: Force separate @StateObject for axial
                
                StandaloneMPRView(
                    plane: .sagittal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: viewSize,
                    allowInteraction: true,
                    scrollVelocity: scrollVelocity  // NEW: Pass scroll velocity
                )
                .id("sagittal-view")  // 🔧 FIX: Force separate @StateObject for sagittal
                
                StandaloneMPRView(
                    plane: .coronal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: dataManager.volumeData,
                    roiData: dataManager.roiData,
                    viewSize: viewSize,
                    allowInteraction: true,
                    scrollVelocity: scrollVelocity  // NEW: Pass scroll velocity
                )
                .id("coronal-view")  // 🔧 FIX: Force separate @StateObject for coronal
            }
            
        case .double, .quad, .automatic:
            if effectiveLayout == .quad {
                // 2x2 Grid: Axial (top-left), Coronal (top-right), Sagittal (bottom-left), 3D (bottom-right)
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        // Top-left: Axial
                        StandaloneMPRView(
                            plane: .axial,
                            coordinateSystem: coordinateSystem,
                            sharedState: sharedState,
                            volumeData: dataManager.volumeData,
                            roiData: dataManager.roiData,
                            viewSize: viewSize,
                            allowInteraction: true,
                            scrollVelocity: scrollVelocity  // NEW: Pass scroll velocity
                        )
                        .id("quad-axial-view")
                        
                        // Top-right: Coronal
                        StandaloneMPRView(
                            plane: .coronal,
                            coordinateSystem: coordinateSystem,
                            sharedState: sharedState,
                            volumeData: dataManager.volumeData,
                            roiData: dataManager.roiData,
                            viewSize: viewSize,
                            allowInteraction: true,
                            scrollVelocity: scrollVelocity  // NEW: Pass scroll velocity
                        )
                        .id("quad-coronal-view")
                    }
                    
                    HStack(spacing: 2) {
                        // Bottom-left: Sagittal
                        StandaloneMPRView(
                            plane: .sagittal,
                            coordinateSystem: coordinateSystem,
                            sharedState: sharedState,
                            volumeData: dataManager.volumeData,
                            roiData: dataManager.roiData,
                            viewSize: viewSize,
                            allowInteraction: true,
                            scrollVelocity: scrollVelocity  // NEW: Pass scroll velocity
                        )
                        .id("quad-sagittal-view")
                        
                        // Bottom-right: 3D
                        Standalone3DView(
                            coordinateSystem: coordinateSystem,
                            sharedState: sharedState,
                            volumeData: dataManager.volumeData,
                            roiData: dataManager.roiData,
                            viewSize: viewSize,
                            allowInteraction: true
                        )
                        .id("quad-3d-view")
                    }
                }
            } else {
                Text("Layout: \(effectiveLayout.displayName)")
                    .foregroundColor(.white)
            }
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

// MARK: - Preview

struct XAnatomyProV2MainView_Previews: PreviewProvider {
    static var previews: some View {
        XAnatomyProV2MainView()
            .previewDevice("iPad Pro (12.9-inch)")
    }
}
