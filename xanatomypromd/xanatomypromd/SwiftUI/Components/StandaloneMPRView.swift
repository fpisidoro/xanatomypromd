import SwiftUI
import simd

// MARK: - Standalone MPR View
// A completely self-contained MPR view that can function independently
// while maintaining synchronization with other views through shared state

struct StandaloneMPRView: View {
    
    // MARK: - Configuration
    
    /// The anatomical plane this view displays
    let plane: MPRPlane
    
    /// Shared coordinate system (for crosshair sync)
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    
    /// Shared viewing state (for window level sync)
    @ObservedObject var sharedState: SharedViewingState
    
    /// Data sources
    let volumeData: VolumeData?
    let roiData: MinimalRTStructParser.SimpleRTStructData?
    
    /// View configuration
    let viewSize: CGSize
    let allowInteraction: Bool
    
    // MARK: - Local State (Independent per view)
    
    @State private var localZoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var localPan: CGSize = .zero
    @State private var isDragging = false
    
    // MARK: - Initialization
    
    init(
        plane: MPRPlane,
        coordinateSystem: DICOMCoordinateSystem,
        sharedState: SharedViewingState,
        volumeData: VolumeData? = nil,
        roiData: MinimalRTStructParser.SimpleRTStructData? = nil,
        viewSize: CGSize = CGSize(width: 512, height: 512),
        allowInteraction: Bool = true
    ) {
        self.plane = plane
        self.coordinateSystem = coordinateSystem
        self.sharedState = sharedState
        self.volumeData = volumeData
        self.roiData = roiData
        self.viewSize = viewSize
        self.allowInteraction = allowInteraction
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // The core layered MPR view
            LayeredMPRView(
                coordinateSystem: coordinateSystem,
                plane: plane,
                windowLevel: sharedState.windowLevel,  // Synchronized across views
                crosshairAppearance: sharedState.crosshairSettings,
                roiSettings: sharedState.roiSettings,
                volumeData: volumeData,
                roiData: roiData,
                viewSize: viewSize,
                allowInteraction: false  // We handle interaction at this level
            )
            .scaleEffect(localZoom)  // Local zoom per view
            .offset(localPan)  // Local pan per view
            
            // Gesture overlay for pan/zoom (ON TOP to receive touches first)
            if allowInteraction {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(createCompositeGesture())
            }
            
            // 2-finger scroll handler underneath (only gets touches SwiftUI doesn't want)
            if allowInteraction {
                TwoFingerScrollHandler { direction, velocity in
                    handleTwoFingerScroll(direction: direction, velocity: velocity)
                }
            }
            
            // View label overlay
            viewLabelOverlay
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .clipped()
        .background(Color.black)
        .border(Color.gray.opacity(0.3), width: 1)
    }
    
    // MARK: - Gesture Handling
    
    private func createCompositeGesture() -> some Gesture {
        let tapGesture = TapGesture()
            .onEnded { _ in
                handleTap()
            }
        
        // Only create drag gesture for 1-finger (pan) - let 2-finger fall through
        let dragGesture = DragGesture(minimumDistance: 10)
            .onChanged { value in
                handleDrag(value)
            }
            .onEnded { value in
                handleDragEnd(value)
            }
        
        let zoomGesture = MagnificationGesture()
            .onChanged { value in
                handleZoom(value)
            }
            .onEnded { value in
                handleZoomEnd(value)
            }
        
        // Combine gestures - pinch and 1-finger drag only
        return tapGesture.simultaneously(with: dragGesture).simultaneously(with: zoomGesture)
    }
    
    private func handleTap() {
        // Future: ROI selection at tap point
        print("🎯 Tap on \(plane.displayName) view")
    }
    
    private func handleDrag(_ value: DragGesture.Value) {
        if !isDragging {
            isDragging = true
        }
        
        // Only handle 1-finger drag for panning
        // Let 2-finger vertical drags fall through to UIKit handler
        localPan = CGSize(
            width: value.translation.width,
            height: value.translation.height
        )
    }
    
    private func handleDragEnd(_ value: DragGesture.Value) {
        isDragging = false
        
        // Animate pan back if small
        if abs(localPan.width) < 50 && abs(localPan.height) < 50 {
            withAnimation(.spring()) {
                localPan = .zero
            }
        }
    }
    
    private func handleSliceNavigation(_ translation: CGSize) {
        let sensitivity: Float = 0.5
        let deltaSlices = Int(translation.height * CGFloat(sensitivity))
        
        if deltaSlices != 0 {
            let currentSlice = coordinateSystem.getCurrentSliceIndex(for: plane)
            let maxSlices = coordinateSystem.getMaxSlices(for: plane)
            let newSlice = max(0, min(currentSlice - deltaSlices, maxSlices - 1))
            
            if newSlice != currentSlice {
                coordinateSystem.updateFromSliceScroll(plane: plane, sliceIndex: newSlice)
            }
        }
    }
    
    private func handleZoom(_ value: CGFloat) {
        localZoom = lastZoom * value
    }
    
    private func handleZoomEnd(_ value: CGFloat) {
        lastZoom = localZoom
        
        // Constrain zoom levels
        withAnimation(.spring()) {
            localZoom = max(0.5, min(localZoom, 4.0))
            lastZoom = localZoom
        }
    }
    
    // MARK: - 2-Finger Scroll Handler
    
    private func handleTwoFingerScroll(direction: Int, velocity: CGFloat) {
        // Update quality based on velocity for this view's rendering
        updateScrollQuality(velocity: velocity)
        
        // Navigate slices for this specific plane
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: plane)
        let totalSlices = coordinateSystem.getMaxSlices(for: plane)
        let newSlice = max(0, min(totalSlices - 1, currentSlice + direction))
        
        if newSlice != currentSlice {
            coordinateSystem.updateFromSliceScroll(plane: plane, sliceIndex: newSlice)
        }
    }
    
    private func updateScrollQuality(velocity: CGFloat) {
        // Update shared state quality based on scroll velocity
        let newQuality: Int
        if velocity > 500 {
            newQuality = 4  // Quarter quality
        } else if velocity > 250 {
            newQuality = 2  // Half quality  
        } else {
            newQuality = 1  // Full quality
        }
        
        // Update shared quality for this view's rendering
        if newQuality != sharedState.renderQuality {
            sharedState.renderQuality = newQuality
            
            // Reset to full quality after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if sharedState.renderQuality != 1 {
                    sharedState.renderQuality = 1
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var viewLabelOverlay: some View {
        VStack {
            HStack {
                // Plane label
                Text(plane.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
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
            
            // Zoom indicator (only show if not 1.0)
            if abs(localZoom - 1.0) > 0.01 {
                HStack {
                    Spacer()
                    Text(String(format: "%.1fx", localZoom))
                        .font(.caption2)
                        .foregroundColor(.yellow.opacity(0.7))
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                }
                .padding(8)
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Reset view transformations
    public func resetView() {
        withAnimation(.spring()) {
            localZoom = 1.0
            lastZoom = 1.0
            localPan = .zero
        }
    }
    
    /// Check if view has been transformed
    public var isTransformed: Bool {
        return abs(localZoom - 1.0) > 0.01 || localPan != .zero
    }
}

// MARK: - Multi-View Container Example

struct MultiViewMPRContainer: View {
    @StateObject private var coordinateSystem = DICOMCoordinateSystem()
    @StateObject private var sharedState = SharedViewingState()
    
    let volumeData: VolumeData?
    let roiData: MinimalRTStructParser.SimpleRTStructData?
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                // Three independent but synchronized views
                StandaloneMPRView(
                    plane: .axial,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: volumeData,
                    roiData: roiData,
                    viewSize: CGSize(
                        width: geometry.size.width / 3 - 4,
                        height: geometry.size.height
                    )
                )
                
                StandaloneMPRView(
                    plane: .sagittal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: volumeData,
                    roiData: roiData,
                    viewSize: CGSize(
                        width: geometry.size.width / 3 - 4,
                        height: geometry.size.height
                    )
                )
                
                StandaloneMPRView(
                    plane: .coronal,
                    coordinateSystem: coordinateSystem,
                    sharedState: sharedState,
                    volumeData: volumeData,
                    roiData: roiData,
                    viewSize: CGSize(
                        width: geometry.size.width / 3 - 4,
                        height: geometry.size.height
                    )
                )
            }
        }
    }
}
