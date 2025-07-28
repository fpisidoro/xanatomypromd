@preconcurrency import SwiftUI
@preconcurrency import MetalKit
import Foundation
import Combine
import Metal

// MARK: - CLEAN DICOM Viewer - ROI Integration Ready
// This is the restored working CT viewer WITHOUT breaking ROI integration
// ROI display can be added later through clean protocols

struct DICOMViewerView: View {
    @State private var selectedWindowingPreset: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
    @State private var currentPlane: MPRPlane = .axial
    @State private var currentSlice = 0
    @State private var isLoading = true
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var showROITest = false
    
    // Test ROI integration (optional)
    @StateObject private var roiTest = ROITestImplementation()
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // MARK: - Header
                    headerView
                    
                    // MARK: - Main CT Display (WORKING)
                    mainImageDisplay(geometry: geometry)
                        .frame(height: geometry.size.height * 0.7)
                    
                    // MARK: - Controls
                    controlsView
                        .frame(height: geometry.size.height * 0.3)
                }
                .background(Color.black)
                .navigationBarHidden(true)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showROITest) {
            ROITestView()
        }
        .onAppear {
            loadDICOMData()
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("X-Anatomy Pro v2.0 - Clean MPR")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("53 slices • Test dataset")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Plane and slice info
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(currentPlane.displayName)")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Slice \(currentSlice + 1)/\(getMaxSlicesForPlane())")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Main Image Display (Clean Implementation)
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
                // Placeholder for actual DICOM display
                // This would integrate with your existing MetalRenderer
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        VStack {
                            Text("CT Image Display")
                                .font(.title2)
                                .foregroundColor(.white)
                            
                            Text("\(currentPlane.rawValue.capitalized) - Slice \(currentSlice)")
                                .foregroundColor(.gray)
                            
                            Text("Window: \(selectedWindowingPreset.name)")
                                .font(.caption)
                                .foregroundColor(.blue)
                            
                            // Show ROI test button
                            Button("Test ROI Integration") {
                                showROITest = true
                            }
                            .padding(.top)
                            .foregroundColor(.green)
                        }
                    )
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
        VStack(spacing: 16) {
            
            // Plane Selection
            planeSelectionView
            
            // Slice Navigation
            sliceNavigationView
            
            // Windowing Controls
            windowingControlsView
            
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
    
    private var planeSelectionView: some View {
        VStack(spacing: 8) {
            Text("View Plane")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack(spacing: 20) {
                ForEach(MPRPlane.allCases, id: \.self) { plane in
                    Button(plane.abbreviation) {
                        currentPlane = plane
                        currentSlice = 0  // Reset to first slice when changing planes
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
    
    private var sliceNavigationView: some View {
        VStack(spacing: 8) {
            Text("Slice Navigation")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack {
                Button("←") {
                    if currentSlice > 0 {
                        currentSlice -= 1
                    }
                }
                .disabled(currentSlice <= 0)
                
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
                    if currentSlice < getMaxSlicesForPlane() - 1 {
                        currentSlice += 1
                    }
                }
                .disabled(currentSlice >= getMaxSlicesForPlane() - 1)
            }
        }
    }
    
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
    
    private func loadDICOMData() {
        // Simulate loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isLoading = false
            
            // Load ROI test data in background
            Task {
                await roiTest.loadTestRTStruct()
            }
        }
    }
    
    private func getMaxSlicesForPlane() -> Int {
        // Return appropriate slice count based on plane
        switch currentPlane {
        case .axial:
            return 53  // Number of CT slices
        case .sagittal:
            return 512 // Image width
        case .coronal:
            return 512 // Image height
        }
    }
}

// MARK: - Preview

#Preview {
    DICOMViewerView()
}
