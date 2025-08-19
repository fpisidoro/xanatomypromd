import SwiftUI

// MARK: - Flexible MPR Layout View
// Demonstrates standalone MPR views that can be arranged in any configuration
// Each view is independent but synchronized through shared state

struct FlexibleMPRLayoutView: View {
    
    // MARK: - Shared State
    @StateObject private var coordinateSystem = DICOMCoordinateSystem()
    @StateObject private var sharedState = SharedViewingState()
    @StateObject private var dataCoordinator = ViewDataCoordinator()
    
    // MARK: - Layout Configuration
    @State private var layoutMode: LayoutMode = .automatic
    @State private var selectedPlane: MPRPlane = .axial  // For single view mode
    
    enum LayoutMode: String, CaseIterable {
        case single = "Single View"
        case sideBySide = "Side by Side"
        case triple = "Triple Panel"
        case quad = "Quad View"
        case automatic = "Auto"
        
        var icon: String {
            switch self {
            case .single: return "square"
            case .sideBySide: return "square.split.2x1"
            case .triple: return "square.split.1x2"
            case .quad: return "square.grid.2x2"
            case .automatic: return "sparkles"
            }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header controls
                headerControls
                
                // Main viewing area
                if dataCoordinator.volumeData != nil {
                    viewingArea(in: geometry)
                } else {
                    loadingView
                }
                
                // Bottom controls
                bottomControls
            }
        }
        .background(Color.black)
        .onAppear {
            loadData()
            determineOptimalLayout()
        }
    }
    
    // MARK: - Layout Views
    
    @ViewBuilder
    private func viewingArea(in geometry: GeometryProxy) -> some View {
        let effectiveLayout = resolveLayout(for: geometry.size)
        
        switch effectiveLayout {
        case .single:
            singleViewLayout(in: geometry)
        case .sideBySide:
            sideBySideLayout(in: geometry)
        case .triple:
            tripleViewLayout(in: geometry)
        case .quad:
            quadViewLayout(in: geometry)
        case .automatic:
            // Should never reach here as automatic resolves to a specific layout
            singleViewLayout(in: geometry)
        }
    }
    
    private func singleViewLayout(in geometry: GeometryProxy) -> some View {
        VStack {
            // Plane selector for single view
            Picker("Plane", selection: $selectedPlane) {
                Text("Axial").tag(MPRPlane.axial)
                Text("Sagittal").tag(MPRPlane.sagittal)
                Text("Coronal").tag(MPRPlane.coronal)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            StandaloneMPRView(
                plane: selectedPlane,
                coordinateSystem: coordinateSystem,
                sharedState: sharedState,
                dataCoordinator: dataCoordinator,
                viewSize: CGSize(
                    width: geometry.size.width - 20,
                    height: geometry.size.height - 150
                )
            )
            .padding(10)
        }
    }
    
    private func sideBySideLayout(in geometry: GeometryProxy) -> some View {
        HStack(spacing: 2) {
            StandaloneMPRView(
                plane: .axial,
                coordinateSystem: coordinateSystem,
                sharedState: sharedState,
                dataCoordinator: dataCoordinator,
                viewSize: CGSize(
                    width: (geometry.size.width - 4) / 2,
                    height: geometry.size.height - 100
                )
            )
            
            StandaloneMPRView(
                plane: .sagittal,
                coordinateSystem: coordinateSystem,
                sharedState: sharedState,
                dataCoordinator: dataCoordinator,
                viewSize: CGSize(
                    width: (geometry.size.width - 4) / 2,
                    height: geometry.size.height - 100
                )
            )
        }
    }
    
    private func tripleViewLayout(in geometry: GeometryProxy) -> some View {
        HStack(spacing: 2) {
            StandaloneMPRView(
                plane: .axial,
                coordinateSystem: coordinateSystem,
                sharedState: sharedState,
                dataCoordinator: dataCoordinator,
                viewSize: CGSize(
                    width: (geometry.size.width - 6) / 3,
                    height: geometry.size.height - 100
                )
            )
            
            StandaloneMPRView(
                plane: .sagittal,
                coordinateSystem: coordinateSystem,
                sharedState: sharedState,
                dataCoordinator: dataCoordinator,
                viewSize: CGSize(
                    width: (geometry.size.width - 6) / 3,
                    height: geometry.size.height - 100
                )
            )
            
            StandaloneMPRView(
                plane: .coronal,
                coordinateSystem: coordinateSystem,
                sharedState: sharedState,
                dataCoordinator: dataCoordinator,
                viewSize: CGSize(
                    width: (geometry.size.width - 6) / 3,
                    height: geometry.size.height - 100
                )
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
                    dataCoordinator: dataCoordinator,
                    viewSize: CGSize(
                        width: (geometry.size.width - 4) / 2,
                        height: (geometry.size.height - 104) / 2
                    )
                )
                
                StandaloneMPRView(
                    plane: .sagittal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    dataCoordinator: dataCoordinator,
                    viewSize: CGSize(
                        width: (geometry.size.width - 4) / 2,
                        height: (geometry.size.height - 104) / 2
                    )
                )
            }
            
            HStack(spacing: 2) {
                StandaloneMPRView(
                    plane: .coronal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    dataCoordinator: dataCoordinator,
                    viewSize: CGSize(
                        width: (geometry.size.width - 4) / 2,
                        height: (geometry.size.height - 104) / 2
                    )
                )
                
                // Fourth view - could be 3D or duplicate view
                Standalone3DView(
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    dataCoordinator: dataCoordinator,
                    viewSize: CGSize(
                        width: (geometry.size.width - 4) / 2,
                        height: (geometry.size.height - 104) / 2
                    )
                )
            }
        }
    }
    
    // MARK: - Controls
    
    private var headerControls: some View {
        HStack {
            // Layout mode selector
            Menu {
                ForEach(LayoutMode.allCases, id: \.self) { mode in
                    Button(action: { layoutMode = mode }) {
                        Label(mode.rawValue, systemImage: mode.icon)
                    }
                }
            } label: {
                Label(layoutMode.rawValue, systemImage: layoutMode.icon)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
            }
            
            Spacer()
            
            // Window level selector
            Menu {
                ForEach(CTWindowLevel.allPresets, id: \.name) { preset in
                    Button(preset.name) {
                        sharedState.setWindowLevel(preset)
                    }
                }
            } label: {
                Label(sharedState.windowLevel.name, systemImage: "slider.horizontal.3")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.blue.opacity(0.3))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
    }
    
    private var bottomControls: some View {
        HStack(spacing: 20) {
            // Crosshair toggle
            Button(action: { sharedState.toggleCrosshairs() }) {
                Image(systemName: sharedState.crosshairSettings.isVisible ? "plus.circle.fill" : "plus.circle")
                    .foregroundColor(sharedState.crosshairSettings.isVisible ? .cyan : .gray)
            }
            
            // ROI toggle
            Button(action: { sharedState.toggleROIOverlay() }) {
                Image(systemName: sharedState.roiSettings.isVisible ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                    .foregroundColor(sharedState.roiSettings.isVisible ? .green : .gray)
            }
            
            Spacer()
            
            // Status indicators
            if dataCoordinator.volumeData != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            if dataCoordinator.roiData != nil {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView("Loading DICOM Data...")
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .foregroundColor(.white)
            
            if dataCoordinator.isVolumeLoading {
                Text("Loading volume: \(Int(dataCoordinator.volumeLoadingProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func resolveLayout(for size: CGSize) -> LayoutMode {
        guard layoutMode == .automatic else { return layoutMode }
        
        // Automatic layout based on screen size
        let isCompact = size.width < 600
        let isRegular = size.width >= 768
        let isLarge = size.width >= 1024
        
        if isLarge {
            return .quad
        } else if isRegular {
            return .triple
        } else if isCompact {
            return .single
        } else {
            return .sideBySide
        }
    }
    
    private func determineOptimalLayout() {
        // Set automatic layout based on device
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            layoutMode = .single
        } else {
            layoutMode = .automatic
        }
        #else
        layoutMode = .automatic
        #endif
    }
    
    private func loadData() {
        Task {
            await dataCoordinator.loadAllData()
            
            // Initialize coordinate system when data loads
            if let volumeData = dataCoordinator.volumeData {
                coordinateSystem.initializeFromVolumeData(volumeData)
            }
        }
    }
}

// MARK: - Preview Provider

struct FlexibleMPRLayoutView_Previews: PreviewProvider {
    static var previews: some View {
        FlexibleMPRLayoutView()
            .previewDevice("iPad Pro (12.9-inch)")
            .previewDisplayName("iPad Pro")
        
        FlexibleMPRLayoutView()
            .previewDevice("iPhone 14 Pro")
            .previewDisplayName("iPhone")
    }
}
