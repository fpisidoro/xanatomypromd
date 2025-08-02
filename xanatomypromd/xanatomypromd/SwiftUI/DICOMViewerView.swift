@preconcurrency import SwiftUI
@preconcurrency import MetalKit
import Foundation
import Combine
import Metal

// MARK: - RESTORED CT DICOM Viewer - Working CT Display
// CT rendering restored with ROI integration support

struct DICOMViewerView: View {
    @StateObject private var viewModel = DICOMViewerViewModel()
    @StateObject private var roiManager = CleanROIManager() // ROI display management
    @StateObject private var crosshairManager = CrosshairManager() // 3D crosshair coordination
    @State private var selectedWindowingPreset: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
    @State private var currentPlane: MPRPlane = .axial
    @State private var isLoading = true
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    // Current slice based on crosshair position
    private var currentSlice: Int {
        return crosshairManager.getSliceIndex(for: currentPlane)
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // MARK: - Header
                    headerView
                    
                    // MARK: - Main CT Display (RESTORED)
                    mainImageDisplay(geometry: geometry)
                        .frame(height: geometry.size.height * 0.6)
                    
                    // MARK: - Controls
                    controlsView
                        .frame(height: geometry.size.height * 0.4)
                }
                .background(Color.black)
                .navigationBarHidden(true)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            Task {
                await viewModel.loadDICOMSeries()
                isLoading = false
                
                // Load ROI data
                if let rtStructData = viewModel.getRTStructData() {
                    roiManager.loadRTStructData(rtStructData)
                }
                
                // Update crosshair manager with real volume dimensions
                await loadVolumeDataForCrosshairs()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("X-Anatomy Pro v2.0 - CT Display")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(viewModel.seriesInfo?.patientName ?? "Test Patient")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Plane and slice info
            VStack(alignment: .trailing, spacing: 4) {
                Text(currentPlane.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Slice \(currentSlice + 1)/\(crosshairManager.getMaxSlices(for: currentPlane))")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                // Show crosshair coordinates
                Text(crosshairManager.getDebugInfo())
                    .font(.caption2)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal)
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Main Image Display (RESTORED CT RENDERING)
    private func mainImageDisplay(geometry: GeometryProxy) -> some View {
        ZStack {
            if isLoading {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Loading DICOM series...")
                        .foregroundColor(.gray)
                        .padding(.top)
                }
            } else {
                // RESTORED: Actual CT rendering with ROI overlays
                ZStack {
                    // STEP 1: CT Image Background
                    CTWithROIView(
                        plane: currentPlane,
                        sliceIndex: currentSlice,
                        windowLevel: selectedWindowingPreset,
                        roiManager: roiManager,
                        volumeData: viewModel.getVolumeData() // Pass volume data
                    )
                    
                    // STEP 2: Crosshair overlay on top
                    CrosshairOverlayView(
                        crosshairManager: crosshairManager,
                        plane: currentPlane,
                        viewSize: CGSize(width: 400, height: 400)
                    )
                    
                    // STEP 3: Debug info overlay
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("CT + ROI Display:")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                if let volumeData = viewModel.getVolumeData() {
                                    Text("Volume: \(volumeData.dimensions.x)×\(volumeData.dimensions.y)×\(volumeData.dimensions.z)")
                                        .font(.caption2)
                                        .foregroundColor(.yellow)
                                } else {
                                    Text("Volume: Loading...")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                Text("Window: \(selectedWindowingPreset.name)")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                Text("ROIs: \(roiManager.getROIStructures().count)")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                        }
                    }
                }
                .scaleEffect(scale)
                .offset(dragOffset)
                .gesture(
                    SimultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                            }
                            .onEnded { _ in
                                // Reset or constrain drag offset if needed
                            },
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { value in
                                lastScale = scale
                            }
                    )
                )
            }
        }
        .background(Color.black)
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    // MARK: - Controls View
    private var controlsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                
                // Plane Selection
                planeSelectionView
                
                // Slice Navigation
                sliceNavigationView
                
                // Windowing Controls (NOW CONNECTED TO CT DISPLAY)
                windowingControlsView
                
                // ROI Controls
                roiControlsView
                
            }
            .padding()
        }
        .background(Color.gray.opacity(0.1))
    }
    
    private var planeSelectionView: some View {
        VStack(spacing: 8) {
            Text("View Plane")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack(spacing: 20) {
                ForEach(MPRPlane.allCases, id: \.self) { plane in
                    Button(plane.displayName) {
                        currentPlane = plane
                        // Crosshair maintains position across plane changes
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(currentPlane == plane ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - ROI Controls
    
    private var roiControlsView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("ROI Display")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Toggle("Show ROIs", isOn: $roiManager.isROIVisible)
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    .labelsHidden()
            }
            
            if roiManager.isROIVisible {
                // ROI Opacity Slider
                HStack {
                    Text("Opacity")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    Slider(value: $roiManager.roiOpacity, in: 0.0...1.0)
                        .accentColor(.green)
                    
                    Text("\(Int(roiManager.roiOpacity * 100))%")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .frame(width: 35)
                }
                
                // ROI List
                if !roiManager.getROINames().isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(roiManager.getROIStructures(), id: \.roiNumber) { roi in
                                Button(roi.roiName) {
                                    roiManager.toggleROI(roi.roiNumber)
                                    // Center crosshair on selected ROI
                                    crosshairManager.centerOnROI(roi)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    roiManager.selectedROIs.contains(roi.roiNumber) || roiManager.selectedROIs.isEmpty ?
                                    Color(red: Double(roi.displayColor.x), green: Double(roi.displayColor.y), blue: Double(roi.displayColor.z)) :
                                    Color.gray.opacity(0.3)
                                )
                                .foregroundColor(.white)
                                .cornerRadius(6)
                                .font(.caption2)
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    Text("No ROI structures loaded")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
    }
    
    private var sliceNavigationView: some View {
        VStack(spacing: 8) {
            Text("Slice Navigation")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack {
                Button("←") {
                    let newSlice = max(0, currentSlice - 1)
                    crosshairManager.updateFromSliceScroll(plane: currentPlane, sliceIndex: newSlice)
                }
                .disabled(currentSlice <= 0)
                
                Slider(
                    value: Binding(
                        get: { Double(currentSlice) },
                        set: { newSlice in
                            crosshairManager.updateFromSliceScroll(plane: currentPlane, sliceIndex: Int(newSlice))
                        }
                    ),
                    in: 0...Double(crosshairManager.getMaxSlices(for: currentPlane) - 1),
                    step: 1
                )
                .accentColor(.blue)
                
                Button("→") {
                    let maxSlices = crosshairManager.getMaxSlices(for: currentPlane)
                    let newSlice = min(maxSlices - 1, currentSlice + 1)
                    crosshairManager.updateFromSliceScroll(plane: currentPlane, sliceIndex: newSlice)
                }
                .disabled(currentSlice >= crosshairManager.getMaxSlices(for: currentPlane) - 1)
            }
            
            // Crosshair controls
            HStack {
                Button("Center on Volume") {
                    crosshairManager.setCrosshairPosition(
                        SIMD3<Float>(
                            Float(crosshairManager.volumeDimensions.x) * crosshairManager.volumeSpacing.x / 2.0,
                            Float(crosshairManager.volumeDimensions.y) * crosshairManager.volumeSpacing.y / 2.0,
                            Float(crosshairManager.volumeDimensions.z) * crosshairManager.volumeSpacing.z / 2.0
                        )
                    )
                }
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(4)
                
                Toggle("Show Crosshairs", isOn: $crosshairManager.isVisible)
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    .font(.caption2)
            }
        }
    }
    
    // MARK: - Windowing Controls (CONNECTED TO CT DISPLAY)
    private var windowingControlsView: some View {
        VStack(spacing: 8) {
            Text("CT Windowing")
                .font(.caption)
                .foregroundColor(.gray)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CTWindowPresets.allPresets, id: \.name) { preset in
                        Button(preset.name) {
                            selectedWindowingPreset = preset
                            // This will automatically update the CTWithROIView
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedWindowingPreset.name == preset.name ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .font(.caption)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    /// Load real volume dimensions from DICOM data for crosshair manager
    private func loadVolumeDataForCrosshairs() async {
        if let volumeData = viewModel.getVolumeData() {
            // Use real volume data
            crosshairManager.updateVolumeParameters(
                dimensions: volumeData.dimensions,
                spacing: volumeData.spacing
            )
            print("✅ Crosshair manager updated with real volume data: \(volumeData.dimensions)")
        } else {
            // Fallback to estimated dimensions
            let fileManager = FileManager.default
            let testDataPath = Bundle.main.path(forResource: "TestData", ofType: nil) ?? ""
            let dicomPath = testDataPath + "/XAPMD^COUSINALPHA"
            
            do {
                let dicomFiles = try fileManager.contentsOfDirectory(atPath: dicomPath)
                    .filter { $0.hasSuffix(".dcm") && !$0.contains("rtstruct") }
                    .sorted()
                
                let actualSliceCount = dicomFiles.count
                
                if actualSliceCount > 0 {
                    let realDimensions = SIMD3<Int>(512, 512, actualSliceCount)
                    let realSpacing = SIMD3<Float>(0.7, 0.7, 3.0)
                    
                    crosshairManager.updateVolumeParameters(
                        dimensions: realDimensions,
                        spacing: realSpacing
                    )
                    
                    print("✅ Crosshair manager updated with estimated parameters: \(actualSliceCount) slices")
                }
            } catch {
                print("⚠️ Error loading DICOM files: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DICOMViewerView()
}
