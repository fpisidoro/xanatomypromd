@preconcurrency import SwiftUI
@preconcurrency import MetalKit

struct RescaleParameters {
    let slope: Float
    let intercept: Float
    
    init(slope: Float = 1.0, intercept: Float = 0.0) {
        self.slope = slope
        self.intercept = intercept
    }
}

struct DICOMSliceInfo {
    let fileURL: URL
    let sliceLocation: Double
    let instanceNumber: Int
}

// MARK: - Aspect Ratio Support
struct AspectRatioUniforms {
    let scaleX: Float
    let scaleY: Float
    let offset: SIMD2<Float>
    
    init(scaleX: Float, scaleY: Float, offset: SIMD2<Float> = SIMD2<Float>(0, 0)) {
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.offset = offset
    }
}

// MARK: - Main DICOM Viewer Interface with MPR

struct DICOMViewerView: View {
    @StateObject private var viewModel = DICOMViewerViewModel()
    @State private var selectedWindowingPreset: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
    @State private var currentPlane: MPRPlane = .axial
    @State private var currentSlice = 0
    @State private var isLoading = true
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // MARK: - Header with Series Info + Plane Info
                    headerView
                    
                    // MARK: - Main Image Display
                    imageDisplayView(geometry: geometry)
                        .frame(height: geometry.size.height * 0.7)
                    
                    // MARK: - Controls Section
                    controlsView
                        .frame(height: geometry.size.height * 0.3)
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
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header View with Plane Info
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("X-Anatomy Pro v2.0 - MPR")
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let seriesInfo = viewModel.seriesInfo {
                    Text(seriesInfo.patientName ?? "Unknown Patient")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(currentPlane.rawValue)
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Text("Slice \\(currentSlice + 1)/\\(getMaxSlicesForPlane())")
                    .font(.caption)
                    .foregroundColor(.white)
                
                Text(selectedWindowingPreset.name)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Image Display View (RESTORED TO WORKING VERSION)
    private func imageDisplayView(geometry: GeometryProxy) -> some View {
        ZStack {
            if isLoading {
                VStack {
                    ProgressView("Loading DICOM Series...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                    
                    if viewModel.isVolumeLoaded {
                        Text("3D Volume Ready!")
                            .foregroundColor(.green)
                            .padding(.top, 8)
                    }
                }
            } else {
                // RESTORED: Metal-rendered DICOM image with proper MPR support
                MetalDICOMImageView(
                    viewModel: viewModel,
                    currentSlice: currentSlice,
                    currentPlane: currentPlane,
                    windowingPreset: selectedWindowingPreset
                )
                .scaleEffect(scale)
                .offset(dragOffset)
                .clipped()
                .gesture(DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { _ in
                        withAnimation(.spring()) {
                            dragOffset = .zero
                        }
                    }
                )
                .gesture(MagnificationGesture()
                    .onChanged { value in
                        scale = lastScale * value
                    }
                    .onEnded { value in
                        lastScale = scale
                        withAnimation(.spring()) {
                            scale = max(0.5, min(scale, 3.0))
                            lastScale = scale
                        }
                    }
                )
                
                // Slice navigation overlay
                sliceNavigationOverlay(geometry: geometry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
    
    // MARK: - Slice Navigation Overlay
    private func sliceNavigationOverlay(geometry: GeometryProxy) -> some View {
        HStack {
            // Left side - Previous slice
            Button(action: previousSlice) {
                Image(systemName: "chevron.left")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: geometry.size.width * 0.2, height: geometry.size.height)
            .contentShape(Rectangle())
            .disabled(currentSlice == 0)
            
            Spacer()
            
            // Right side - Next slice
            Button(action: nextSlice) {
                Image(systemName: "chevron.right")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: geometry.size.width * 0.2, height: geometry.size.height)
            .contentShape(Rectangle())
            .disabled(currentSlice == getMaxSlicesForPlane() - 1)
        }
        .background(Color.clear)
        .gesture(
            DragGesture()
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.height > threshold {
                        previousSlice()
                    } else if value.translation.height < -threshold {
                        nextSlice()
                    }
                }
        )
    }
    
    // MARK: - Controls View with MPR Plane Switching
    private var controlsView: some View {
        VStack(spacing: 12) {
            // MPR Plane Selection
            mprPlaneSelector
            
            // Windowing Presets
            windowingPresetsView
            
            // Slice Slider
            sliceSliderView
            
            // Action Buttons
            actionButtonsView
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
    
    // MARK: - MPR Plane Selector
    private var mprPlaneSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Anatomical Plane")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                ForEach([MPRPlane.axial, MPRPlane.sagittal, MPRPlane.coronal], id: \.self) { plane in
                    Button(action: {
                        switchToPlane(plane)
                    }) {
                        VStack(spacing: 4) {
                            Text(plane.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            
                            Text(getPlaneDescription(plane))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            currentPlane == plane
                                ? Color.blue
                                : Color.gray.opacity(0.3)
                        )
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    // MARK: - Windowing Presets
    private var windowingPresetsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CT Windowing")
                .font(.headline)
                .foregroundColor(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CTWindowPresets.all, id: \CTWindowPresets.WindowLevel.name) { preset in
                        windowingPresetButton(preset)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Individual Windowing Preset Button
    private func windowingPresetButton(_ preset: CTWindowPresets.WindowLevel) -> some View {
        Button(action: {
            selectedWindowingPreset = preset
        }) {
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
            .background(
                selectedWindowingPreset.name == preset.name
                    ? Color.blue
                    : Color.gray.opacity(0.3)
            )
            .cornerRadius(8)
        }
    }
    
    // MARK: - Slice Slider
    private var sliceSliderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Slice Navigation")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack {
                Button("←") {
                    previousSlice()
                }
                .disabled(currentSlice <= 0)
                .foregroundColor(.white)
                
                Slider(
                    value: Binding(
                        get: { Double(currentSlice) },
                        set: { currentSlice = Int($0) }
                    ),
                    in: 0...Double(getMaxSlicesForPlane() - 1),
                    step: 1
                )
                .accentColor(.blue)
                
                Button("→") {
                    nextSlice()
                }
                .disabled(currentSlice >= getMaxSlicesForPlane() - 1)
                .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Action Buttons
    private var actionButtonsView: some View {
        HStack(spacing: 16) {
            Button("Reset View") {
                withAnimation {
                    scale = 1.0
                    lastScale = 1.0
                    dragOffset = .zero
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(8)
            
            Spacer()
            
            if viewModel.isVolumeLoaded {
                Text("✅ 3D Volume Ready")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Text("⏳ Loading Volume...")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func switchToPlane(_ plane: MPRPlane) {
        currentPlane = plane
        currentSlice = 0 // Reset to first slice when switching planes
    }
    
    private func previousSlice() {
        if currentSlice > 0 {
            currentSlice -= 1
        }
    }
    
    private func nextSlice() {
        if currentSlice < getMaxSlicesForPlane() - 1 {
            currentSlice += 1
        }
    }
    
    private func getMaxSlicesForPlane() -> Int {
        guard let volumeData = viewModel.getVolumeData() else {
            return 53 // Fallback to known test data size
        }
        
        switch currentPlane {
        case .axial:
            return volumeData.dimensions.z
        case .sagittal:
            return volumeData.dimensions.x
        case .coronal:
            return volumeData.dimensions.y
        }
    }
    
    private func getPlaneDescription(_ plane: MPRPlane) -> String {
        switch plane {
        case .axial:
            return "Top-Down"
        case .sagittal:
            return "Side View"
        case .coronal:
            return "Front View"
        }
    }
}

// MARK: - Preview

#Preview {
    DICOMViewerView()
}
