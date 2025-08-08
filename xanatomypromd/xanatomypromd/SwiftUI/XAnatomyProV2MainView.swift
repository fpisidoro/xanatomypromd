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
                        // MPR Views
                        mprViewsLayout(in: geometry)
                    }
                    
                    // Bottom controls
                    if showControls && !isLoading {
                        bottomControls
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startLoading()
            determineOptimalLayout()
        }
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
                VStack {
                    Text("Debug: layoutMode = \(layoutMode.displayName)")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    
                    Picker("", selection: $selectedSingleViewPlane) {
                        Text("Axial").tag(ViewType.axial)
                        Text("Sag").tag(ViewType.sagittal)
                        Text("Cor").tag(ViewType.coronal)
                        Text("3D").tag(ViewType.threeDimensional)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    
                    Text("Selected: \(selectedSingleViewPlane.displayName)")
                        .font(.caption)
                        .foregroundColor(.green)
                }
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
            
            // Toggle controls visibility
            Button(action: { withAnimation { showControls.toggle() } }) {
                Image(systemName: showControls ? "chevron.up" : "chevron.down")
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.9))
    }
    
    private var bottomControls: some View {
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
