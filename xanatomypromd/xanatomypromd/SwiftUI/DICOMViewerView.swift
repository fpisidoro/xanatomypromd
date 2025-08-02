@preconcurrency import SwiftUI
@preconcurrency import MetalKit
import Foundation
import Combine
import Metal

// MARK: - CLEAN DICOM Viewer - ROI Integration Ready
// This is the restored working CT viewer WITHOUT breaking ROI integration
// ROI display can be added later through clean protocols

struct DICOMViewerView: View {
    @StateObject private var viewModel = DICOMViewerViewModel()
    @StateObject private var roiManager = CleanROIManager() // ROI display management
    @StateObject private var crosshairManager = CrosshairManager() // NEW: 3D crosshair coordination
    @State private var selectedWindowingPreset: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
    @State private var currentPlane: MPRPlane = .axial // Changed to use MPRPlane enum
    @State private var isLoading = true
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var showROITest = false
    
    // NEW: Computed property for current slice based on crosshair position
    private var currentSlice: Int {
        return crosshairManager.getSliceIndex(for: currentPlane)
    }
    
    // Test ROI integration (optional) - DISABLED
    // @StateObject private var roiTest = ROITestImplementation()
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // MARK: - Header
                    headerView
                    
                    // MARK: - Main CT Display (WORKING)
                    mainImageDisplay(geometry: geometry)
                        .frame(height: geometry.size.height * 0.6)  // Reduced from 0.7 to 0.6
                    
                    // MARK: - Controls
                    controlsView
                        .frame(height: geometry.size.height * 0.4)  // Increased from 0.3 to 0.4
                }
                .background(Color.black)
                .navigationBarHidden(true)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        // DISABLED: ROI Test View
        /*
        .sheet(isPresented: $showROITest) {
            ROITestView()
        }
        */
        .onAppear {
            Task {
                await viewModel.loadDICOMSeries()
                isLoading = false
                
                // Load ROI data
                if let rtStructData = viewModel.getRTStructData() {
                    roiManager.loadRTStructData(rtStructData)
                }
                
                // NEW: Update crosshair manager with real volume dimensions if available
                await loadVolumeDataForCrosshairs()
            }
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
                
                // NEW: Show crosshair coordinates
                Text(crosshairManager.getDebugInfo())
                    .font(.caption2)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.trailing)
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
                // Enhanced approach: Background + ROI overlay + Crosshairs
                ZStack {
                    // Background color to show current plane
                    Rectangle()
                        .fill(getPlaneColor())
                    
                    // Simple ROI overlay
                    SimpleROIOverlay(
                        roiManager: roiManager,
                        currentSlice: currentSlice,
                        currentPlane: currentPlane,
                        viewSize: CGSize(width: 400, height: 400)
                    )
                    
                    // NEW: Crosshair overlay on top
                    CrosshairOverlayView(
                        crosshairManager: crosshairManager,
                        plane: currentPlane,
                        viewSize: CGSize(width: 400, height: 400)
                    )
                    
                    // DEBUG: Show ROI data info
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("ROI Debug:")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                Text("Total ROIs: \(roiManager.getROIStructures().count)")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                Text("Slice \(currentSlice) (\(Float(currentSlice) * 3.0)mm)")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                                if let firstROI = roiManager.getROIStructures().first {
                                    Text("\(firstROI.roiName): \(firstROI.contours.count) contours")
                                        .font(.caption2)
                                        .foregroundColor(.yellow)
                                    if let firstContour = firstROI.contours.first {
                                        Text("Z: \(firstContour.slicePosition)mm")
                                            .font(.caption2)
                                            .foregroundColor(.yellow)
                                    }
                                }
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
                
                // Windowing Controls
                windowingControlsView
                
                // ROI Controls - NEW!
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
                // NEW: Use MPRPlane enum properly
                ForEach(MPRPlane.allCases, id: \.self) { plane in
                    Button(plane.displayName) {
                        currentPlane = plane
                        // NO LONGER RESET SLICE - crosshair maintains position!
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
    
    // MARK: - ROI Controls - NEW!
    
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
                                    // NEW: Center crosshair on selected ROI
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
            
            // NEW: Crosshair controls
            HStack {
                Button("Center on Volume") {
                    // Reset crosshair to center of volume (using dynamic calculation)
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
    // NOTE: getMaxSlicesForPlane() removed - now handled by CrosshairManager
    
    /// Load real volume dimensions from DICOM data for crosshair manager
    private func loadVolumeDataForCrosshairs() async {
        // TODO: Replace with actual DICOM volume loading
        // For now, detect available DICOM files and count them
        
        let fileManager = FileManager.default
        let testDataPath = Bundle.main.path(forResource: "TestData", ofType: nil) ?? ""
        let dicomPath = testDataPath + "/XAPMD^COUSINALPHA"
        
        do {
            let dicomFiles = try fileManager.contentsOfDirectory(atPath: dicomPath)
                .filter { $0.hasSuffix(".dcm") && !$0.contains("rtstruct") }
                .sorted()
            
            let actualSliceCount = dicomFiles.count
            
            if actualSliceCount > 0 {
                print("📁 Found \(actualSliceCount) DICOM slices (not hardcoded 53!)")
                
                // Create volume dimensions based on actual data
                let realDimensions = SIMD3<Int>(512, 512, actualSliceCount)
                let realSpacing = SIMD3<Float>(0.7, 0.7, 3.0) // TODO: Extract from DICOM headers
                
                // Update crosshair manager with real parameters
                crosshairManager.updateVolumeParameters(
                    dimensions: realDimensions,
                    spacing: realSpacing
                )
                
                print("✅ Updated crosshair manager for \(actualSliceCount) slices")
            } else {
                print("⚠️ No DICOM files found, using default parameters")
            }
        } catch {
            print("⚠️ Error loading DICOM files: \(error)")
            print("⚠️ Using default crosshair parameters")
        }
    }
    
    private func getPlaneColor() -> Color {
        switch currentPlane {
        case .axial:
            return Color.blue.opacity(0.3)
        case .sagittal:
            return Color.red.opacity(0.3)
        case .coronal:
            return Color.green.opacity(0.3)
        }
    }
}

// MARK: - Simple ROI Overlay View
// Just draws visible shapes on top of the background - no Metal complexity

struct SimpleROIOverlay: View {
    @ObservedObject var roiManager: CleanROIManager  // Change let to var
    let currentSlice: Int
    let currentPlane: MPRPlane
    let viewSize: CGSize
    
    var body: some View {
        ZStack {
            if roiManager.isROIVisible {
                ForEach(visibleROIsForCurrentSlice, id: \.roiNumber) { roi in
                    ForEach(contoursForROI(roi), id: \.contourNumber) { contour in
                        ROIContourShape(
                            contour: contour,
                            color: Color(
                                red: Double(roi.displayColor.x),
                                green: Double(roi.displayColor.y), 
                                blue: Double(roi.displayColor.z)
                            ),
                            opacity: Double(roi.opacity * roiManager.roiOpacity),
                            viewSize: viewSize,
                            currentPlane: currentPlane  // Pass the plane
                        )
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: roiManager.isROIVisible)
    }
    
    private var visibleROIsForCurrentSlice: [ROIStructure] {
        let slicePosition = Float(currentSlice) * 3.0 // 3mm slices
        
        return roiManager.getROIStructures().filter { roi in
            // Check ROI visibility
            guard roi.isVisible else { return false }
            
            // Check individual ROI selection
            if !roiManager.selectedROIs.isEmpty && !roiManager.selectedROIs.contains(roi.roiNumber) {
                return false
            }
            
            // Check if this ROI has contours near current slice
            return roi.contours.contains { contour in
                abs(contour.slicePosition - slicePosition) < 2.0 // 2mm tolerance
            }
        }
    }
    
    private func contoursForROI(_ roi: ROIStructure) -> [ROIContour] {
        switch currentPlane {
        case .axial:
            // Axial: show contours at current Z slice
            let currentSlicePosition = Float(currentSlice) * 3.0
            return roi.contours.filter { contour in
                abs(contour.slicePosition - currentSlicePosition) < 2.0
            }
            
        case .sagittal:
            // Sagittal: need to create cross-section through 3D structure at current X position
            let currentXPosition = (Float(currentSlice) / 53.0) * 512.0
            return createSagittalCrossSection(roi: roi, xPosition: currentXPosition)
            
        case .coronal:
            // Coronal: need to create cross-section through 3D structure at current Y position  
            let currentYPosition = (Float(currentSlice) / 53.0) * 512.0
            return createCoronalCrossSection(roi: roi, yPosition: currentYPosition)
        }
    }
    
    private func createSagittalCrossSection(roi: ROIStructure, xPosition: Float) -> [ROIContour] {
        // Create a cross-section by finding where the 3D ROI intersects the sagittal plane at xPosition
        var crossSectionPoints: [SIMD3<Float>] = []
        
        // Go through all contours and find intersection points
        for contour in roi.contours {
            for i in 0..<contour.contourData.count {
                let p1 = contour.contourData[i]
                let p2 = contour.contourData[(i + 1) % contour.contourData.count]
                
                // Check if line segment crosses our X plane
                if (p1.x <= xPosition && p2.x >= xPosition) || (p1.x >= xPosition && p2.x <= xPosition) {
                    // Linear interpolation to find intersection point
                    let t = (xPosition - p1.x) / (p2.x - p1.x)
                    if t >= 0.0 && t <= 1.0 {
                        let intersectionY = p1.y + t * (p2.y - p1.y)
                        let intersectionZ = p1.z + t * (p2.z - p1.z)
                        crossSectionPoints.append(SIMD3<Float>(xPosition, intersectionY, intersectionZ))
                    }
                }
            }
        }
        
        // Sort points in circular order around their center (not linearly!)
        if crossSectionPoints.count >= 3 {
            let sortedPoints = sortPointsInCircularOrder(crossSectionPoints, plane: .sagittal)
            return [ROIContour(
                contourNumber: 1,
                geometricType: .closedPlanar,
                numberOfPoints: sortedPoints.count,
                contourData: sortedPoints,
                slicePosition: xPosition
            )]
        }
        
        return []
    }
    
    private func createCoronalCrossSection(roi: ROIStructure, yPosition: Float) -> [ROIContour] {
        // Create a cross-section by finding where the 3D ROI intersects the coronal plane at yPosition
        var crossSectionPoints: [SIMD3<Float>] = []
        
        // Go through all contours and find intersection points
        for contour in roi.contours {
            for i in 0..<contour.contourData.count {
                let p1 = contour.contourData[i]
                let p2 = contour.contourData[(i + 1) % contour.contourData.count]
                
                // Check if line segment crosses our Y plane
                if (p1.y <= yPosition && p2.y >= yPosition) || (p1.y >= yPosition && p2.y <= yPosition) {
                    // Linear interpolation to find intersection point
                    let t = (yPosition - p1.y) / (p2.y - p1.y)
                    if t >= 0.0 && t <= 1.0 {
                        let intersectionX = p1.x + t * (p2.x - p1.x)
                        let intersectionZ = p1.z + t * (p2.z - p1.z)
                        crossSectionPoints.append(SIMD3<Float>(intersectionX, yPosition, intersectionZ))
                    }
                }
            }
        }
        
        // Sort points in circular order around their center (not linearly!)
        if crossSectionPoints.count >= 3 {
            let sortedPoints = sortPointsInCircularOrder(crossSectionPoints, plane: .coronal)
            return [ROIContour(
                contourNumber: 1,
                geometricType: .closedPlanar,
                numberOfPoints: sortedPoints.count,
                contourData: sortedPoints,
                slicePosition: yPosition
            )]
        }
        
        return []
    }
    
    // MARK: - FIXED Circular Point Sorting Algorithm
    
    private func sortPointsInCircularOrder(_ points: [SIMD3<Float>], plane: MPRPlane) -> [SIMD3<Float>] {
        guard points.count >= 3 else { return points }
        
        // First, remove any duplicate points (within tolerance)
        var uniquePoints: [SIMD3<Float>] = []
        for point in points {
            let isDuplicate = uniquePoints.contains { existingPoint in
                let diff = point - existingPoint
                return sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z) < 1.0 // 1mm tolerance
            }
            if !isDuplicate {
                uniquePoints.append(point)
            }
        }
        
        guard uniquePoints.count >= 3 else { return points }
        
        // Calculate the center point based on the viewing plane
        switch plane {
        case .axial:
            // Z is constant, work in X-Y plane
            let centerX = uniquePoints.map { $0.x }.reduce(0, +) / Float(uniquePoints.count)
            let centerY = uniquePoints.map { $0.y }.reduce(0, +) / Float(uniquePoints.count)
            
            return uniquePoints.sorted { p1, p2 in
                let angle1 = atan2(p1.y - centerY, p1.x - centerX)
                let angle2 = atan2(p2.y - centerY, p2.x - centerX)
                return angle1 < angle2
            }
            
        case .sagittal:
            // X is constant, work in Y-Z plane
            let centerY = uniquePoints.map { $0.y }.reduce(0, +) / Float(uniquePoints.count)
            let centerZ = uniquePoints.map { $0.z }.reduce(0, +) / Float(uniquePoints.count)
            
            return uniquePoints.sorted { p1, p2 in
                let angle1 = atan2(p1.z - centerZ, p1.y - centerY)
                let angle2 = atan2(p2.z - centerZ, p2.y - centerY)
                return angle1 < angle2
            }
            
        case .coronal:
            // Y is constant, work in X-Z plane
            let centerX = uniquePoints.map { $0.x }.reduce(0, +) / Float(uniquePoints.count)
            let centerZ = uniquePoints.map { $0.z }.reduce(0, +) / Float(uniquePoints.count)
            
            return uniquePoints.sorted { p1, p2 in
                let angle1 = atan2(p1.z - centerZ, p1.x - centerX)
                let angle2 = atan2(p2.z - centerZ, p2.x - centerX)
                return angle1 < angle2
            }
        }
    }
}

// MARK: - ROI Contour Shape
// SwiftUI Shape that draws actual visible ROI contours

struct ROIContourShape: View {
    let contour: ROIContour
    let color: Color
    let opacity: Double
    let viewSize: CGSize
    let currentPlane: MPRPlane  // Add plane parameter
    
    var body: some View {
        Path { path in
            let points = contour.contourData
            guard !points.isEmpty else { return }
            
            // Convert first point to screen coordinates
            let firstPoint = projectToScreen(points[0])
            path.move(to: firstPoint)
            
            // Draw lines to all other points
            for i in 1..<points.count {
                let screenPoint = projectToScreen(points[i])
                path.addLine(to: screenPoint)
            }
            
            // Close the contour
            path.closeSubpath()
        }
        .stroke(color.opacity(opacity), lineWidth: 2.0)
    }
    
    private func projectToScreen(_ point3D: SIMD3<Float>) -> CGPoint {
        // Proper 3D to 2D projection based on current viewing plane
        // DICOM coordinates: X=left-right, Y=anterior-posterior, Z=superior-inferior
        
        var screenX: Double
        var screenY: Double
        
        switch currentPlane {
        case .axial:
            // Axial view: looking down from head to feet (Z constant)
            // X maps to screen X (left-right)
            // Y maps to screen Y (anterior-posterior)
            screenX = (Double(point3D.x) / 512.0) * viewSize.width
            screenY = (Double(point3D.y) / 512.0) * viewSize.height
            
        case .sagittal:
            // Sagittal view: looking from left side (X constant)
            // Y maps to screen X (anterior-posterior) 
            // Z maps to screen Y (superior-inferior, flipped)
            screenX = (Double(point3D.y) / 512.0) * viewSize.width
            screenY = viewSize.height - (Double(point3D.z) / 160.0) * viewSize.height // Z range 0-160mm
            
        case .coronal:
            // Coronal view: looking from front (Y constant)
            // X maps to screen X (left-right)
            // Z maps to screen Y (superior-inferior, flipped) 
            screenX = (Double(point3D.x) / 512.0) * viewSize.width
            screenY = viewSize.height - (Double(point3D.z) / 160.0) * viewSize.height // Z range 0-160mm
        }
        
        return CGPoint(x: screenX, y: screenY)
    }
}

// MARK: - Preview

#Preview {
    DICOMViewerView()
}
