import SwiftUI
import MetalKit

// MARK: - Layer 3: Crosshair Overlay Layer (MEDICAL-ACCURATE 3D COORDINATES)
// MEDICAL PRINCIPLE: Crosshairs MUST align with CT image bounds, NOT screen bounds
// Transforms 3D medical coordinates to image-aligned screen coordinates

struct CrosshairOverlayLayer: View {
    
    // MARK: - Configuration
    
    /// The authoritative coordinate system (shared with all layers)
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    
    /// Current anatomical plane being displayed
    let plane: MPRPlane
    
    /// Volume data for physical spacing calculations
    let volumeData: VolumeData?
    
    /// View size for coordinate transformations
    let viewSize: CGSize
    
    /// Crosshair appearance settings
    let appearance: CrosshairAppearance
    
    // MARK: - Medical-Accurate Crosshair Rendering
    
    var body: some View {
        GeometryReader { geometry in
            let currentViewSize = geometry.size
            
            // Calculate medical-accurate crosshair position
            if let medicalCrosshairPosition = calculateMedicalCrosshairPosition(
                viewSize: currentViewSize
            ) {
                ZStack {
                    // Get medical image bounds for constraining crosshair lines
                    let imageBounds = calculateMedicalImageBounds(
                        plane: plane,
                        volumeData: volumeData,
                        viewSize: currentViewSize
                    )
                    
                    if appearance.isVisible {
                        // Horizontal crosshair line (constrained to image bounds)
                        CrosshairLine(
                            startPoint: CGPoint(x: imageBounds.minX, y: medicalCrosshairPosition.y),
                            endPoint: CGPoint(x: imageBounds.maxX, y: medicalCrosshairPosition.y),
                            intersectionPoint: medicalCrosshairPosition,
                            appearance: appearance,
                            isHorizontal: true
                        )
                        
                        // Vertical crosshair line (constrained to image bounds)
                        CrosshairLine(
                            startPoint: CGPoint(x: medicalCrosshairPosition.x, y: imageBounds.minY),
                            endPoint: CGPoint(x: medicalCrosshairPosition.x, y: imageBounds.maxY),
                            intersectionPoint: medicalCrosshairPosition,
                            appearance: appearance,
                            isHorizontal: false
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false) // Crosshairs are visual only
        .onAppear {
            print("🎯 Medical Crosshairs: Initialized for \(plane) plane")
            logMedicalCoordinateMapping()
        }
        .onChange(of: plane) { newPlane in
            print("🎯 Medical Crosshairs: Plane changed to \(newPlane)")
            logMedicalCoordinateMapping()
        }
        .onChange(of: coordinateSystem.currentWorldPosition) { _ in
            logMedicalCoordinateMapping()
        }
    }
    
    // MARK: - Medical 3D Coordinate Transformation
    
    /// Calculate crosshair position using medical-accurate 3D coordinate transformation
    private func calculateMedicalCrosshairPosition(viewSize: CGSize) -> CGPoint? {
        guard let volumeData = volumeData else {
            print("❌ Medical Crosshairs: No volume data available")
            return nil
        }
        
        // Get current 3D medical position from coordinate system
        let currentPosition = coordinateSystem.currentWorldPosition
        
        // Transform 3D medical position to 2D image coordinates for current plane
        let imageCoordinates = transform3DToImageCoordinates(
            medicalPosition: currentPosition,
            plane: plane,
            volumeData: volumeData
        )
        
        // Transform image coordinates to screen coordinates within letterbox bounds
        let screenCoordinates = transformImageToScreenCoordinates(
            imageCoordinates: imageCoordinates,
            plane: plane,
            volumeData: volumeData,
            viewSize: viewSize
        )
        
        print("🎯 Medical Transform: \(currentPosition) → \(imageCoordinates) → \(screenCoordinates)")
        
        return screenCoordinates
    }
    
    /// Transform 3D medical position to 2D image texture coordinates
    private func transform3DToImageCoordinates(
        medicalPosition: SIMD3<Float>,
        plane: MPRPlane,
        volumeData: VolumeData
    ) -> SIMD2<Float> {
        
        // Convert physical position (mm) to normalized texture coordinates [0,1]
        let normalizedPosition = SIMD3<Float>(
            medicalPosition.x / (Float(volumeData.dimensions.x) * volumeData.spacing.x),
            medicalPosition.y / (Float(volumeData.dimensions.y) * volumeData.spacing.y),
            medicalPosition.z / (Float(volumeData.dimensions.z) * volumeData.spacing.z)
        )
        
        // Project 3D position to 2D image coordinates based on plane
        let imageCoordinates: SIMD2<Float>
        
        switch plane {
        case .axial:
            // XY plane - X maps to texture X, Y maps to texture Y
            imageCoordinates = SIMD2<Float>(normalizedPosition.x, normalizedPosition.y)
            
        case .sagittal:
            // YZ plane - Y maps to texture X, Z maps to texture Y
            imageCoordinates = SIMD2<Float>(normalizedPosition.y, normalizedPosition.z)
            
        case .coronal:
            // XZ plane - X maps to texture X, Z maps to texture Y
            imageCoordinates = SIMD2<Float>(normalizedPosition.x, normalizedPosition.z)
        }
        
        print("🎯 3D→2D Transform (\(plane)): \(medicalPosition) → \(imageCoordinates)")
        
        return imageCoordinates
    }
    
    /// Transform 2D image coordinates to screen coordinates within medical image bounds
    private func transformImageToScreenCoordinates(
        imageCoordinates: SIMD2<Float>,
        plane: MPRPlane,
        volumeData: VolumeData,
        viewSize: CGSize
    ) -> CGPoint {
        
        // Calculate the medical image quad bounds (same logic as CTDisplayLayer)
        let medicalImageBounds = calculateMedicalImageBounds(
            plane: plane,
            volumeData: volumeData,
            viewSize: viewSize
        )
        
        // Transform normalized image coordinates [0,1] to screen pixel coordinates
        let screenX = medicalImageBounds.minX + (CGFloat(imageCoordinates.x) * medicalImageBounds.width)
        let screenY = medicalImageBounds.minY + (CGFloat(1.0 - imageCoordinates.y) * medicalImageBounds.height) // Flip Y
        
        let screenCoordinates = CGPoint(x: screenX, y: screenY)
        
        print("🎯 2D→Screen Transform: \(imageCoordinates) → \(screenCoordinates)")
        print("🎯 Medical Image Bounds: \(medicalImageBounds)")
        
        return screenCoordinates
    }
    
    /// Calculate the actual medical image bounds within the screen (matching CTDisplayLayer logic)
    private func calculateMedicalImageBounds(
        plane: MPRPlane,
        volumeData: VolumeData?,
        viewSize: CGSize
    ) -> CGRect {
        
        guard let volumeData = volumeData else {
            // Fallback to full view if no volume data
            return CGRect(origin: .zero, size: viewSize)
        }
        
        // Get texture dimensions for current plane
        let textureDimensions = getTextureDimensions(plane: plane, volumeData: volumeData)
        
        // Calculate physical dimensions using DICOM spacing
        let physicalDimensions = calculatePhysicalDimensions(
            textureWidth: textureDimensions.width,
            textureHeight: textureDimensions.height,
            plane: plane,
            spacing: volumeData.spacing
        )
        
        // Calculate aspect ratios
        let physicalAspect = physicalDimensions.width / physicalDimensions.height
        let viewAspect = Float(viewSize.width / viewSize.height)
        
        // Calculate letterbox bounds (same logic as CTDisplayLayer)
        let quadSize: (width: Float, height: Float)
        
        if physicalAspect > viewAspect {
            // Image is physically wider - letterbox top/bottom
            quadSize = (1.0, viewAspect / physicalAspect)
        } else {
            // Image is physically taller - letterbox left/right
            quadSize = (physicalAspect / viewAspect, 1.0)
        }
        
        // Convert normalized quad size to screen pixel bounds
        let quadWidthPixels = CGFloat(quadSize.width) * viewSize.width
        let quadHeightPixels = CGFloat(quadSize.height) * viewSize.height
        
        let quadX = (viewSize.width - quadWidthPixels) / 2.0
        let quadY = (viewSize.height - quadHeightPixels) / 2.0
        
        let imageBounds = CGRect(
            x: quadX,
            y: quadY,
            width: quadWidthPixels,
            height: quadHeightPixels
        )
        
        print("🎯 Medical Image Bounds Calc:")
        print("   📐 Texture: \(textureDimensions.width)×\(textureDimensions.height)")
        print("   📏 Physical: \(String(format: "%.1f", physicalDimensions.width))×\(String(format: "%.1f", physicalDimensions.height))mm")
        print("   📊 Aspect: \(String(format: "%.3f", physicalAspect)) vs \(String(format: "%.3f", viewAspect))")
        print("   📱 Bounds: \(imageBounds)")
        
        return imageBounds
    }
    
    /// Get texture dimensions for the specified plane
    private func getTextureDimensions(plane: MPRPlane, volumeData: VolumeData) -> (width: Int, height: Int) {
        let dims = volumeData.dimensions
        
        switch plane {
        case .axial:
            return (dims.x, dims.y)  // 512×512
        case .sagittal:
            return (dims.y, dims.z)  // 512×53
        case .coronal:
            return (dims.x, dims.z)  // 512×53
        }
    }
    
    /// Calculate physical dimensions using DICOM spacing (matching CTDisplayLayer logic)
    private func calculatePhysicalDimensions(
        textureWidth: Int,
        textureHeight: Int,
        plane: MPRPlane,
        spacing: SIMD3<Float>
    ) -> (width: Float, height: Float) {
        
        let pixelWidth = Float(textureWidth)
        let pixelHeight = Float(textureHeight)
        
        switch plane {
        case .axial:
            // XY plane: X × Y dimensions
            let physicalWidth = pixelWidth * spacing.x
            let physicalHeight = pixelHeight * spacing.y
            return (physicalWidth, physicalHeight)
            
        case .sagittal:
            // YZ plane: Y × Z dimensions
            let physicalWidth = pixelWidth * spacing.y
            let physicalHeight = pixelHeight * spacing.z
            return (physicalWidth, physicalHeight)
            
        case .coronal:
            // XZ plane: X × Z dimensions
            let physicalWidth = pixelWidth * spacing.x
            let physicalHeight = pixelHeight * spacing.z
            return (physicalWidth, physicalHeight)
        }
    }
    
    // MARK: - Debug and Logging
    
    /// Log medical coordinate mapping for debugging
    private func logMedicalCoordinateMapping() {
        guard let volumeData = volumeData else { return }
        
        let currentPosition = coordinateSystem.currentWorldPosition
        let currentSlice = coordinateSystem.getCurrentSliceIndex(for: plane)
        
        print("🎯 Medical Coordinate Mapping (\(plane)):")
        print("   🏥 Medical Position: \(currentPosition)mm")
        print("   📐 Current Slice: \(currentSlice)")
        print("   📏 Volume Dimensions: \(volumeData.dimensions)")
        print("   🎯 DICOM Spacing: \(volumeData.spacing)")
        
        let imageCoords = transform3DToImageCoordinates(
            medicalPosition: currentPosition,
            plane: plane,
            volumeData: volumeData
        )
        print("   📊 Image Coordinates: \(imageCoords)")
    }
}

// MARK: - Crosshair Appearance Configuration

struct CrosshairAppearance {
    let isVisible: Bool
    let color: Color
    let opacity: Double
    let lineWidth: CGFloat
    let fadeDistance: Double  // Distance from intersection where fade starts (0.0-1.0)
    
    static let `default` = CrosshairAppearance(
        isVisible: true,
        color: .green,
        opacity: 0.6,
        lineWidth: 1.0,
        fadeDistance: 0.3
    )
    
    static let subtle = CrosshairAppearance(
        isVisible: true,
        color: .green,
        opacity: 0.4,
        lineWidth: 0.8,
        fadeDistance: 0.4
    )
    
    static let prominent = CrosshairAppearance(
        isVisible: true,
        color: .green,
        opacity: 0.8,
        lineWidth: 1.5,
        fadeDistance: 0.2
    )
}

// MARK: - Individual Crosshair Line with Anatomically-Correct Fade

struct CrosshairLine: View {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let intersectionPoint: CGPoint
    let appearance: CrosshairAppearance
    let isHorizontal: Bool
    
    var body: some View {
        Canvas { context, size in
            // Create path for the crosshair line
            var path = Path()
            path.move(to: startPoint)
            path.addLine(to: endPoint)
            
            // Create anatomically-correct gradient that fades near intersection
            let gradient = createAnatomicallyCorrectGradient()
            
            // Draw the line with gradient stroke
            context.stroke(
                path,
                with: .linearGradient(
                    gradient,
                    startPoint: startPoint,
                    endPoint: endPoint
                ),
                style: StrokeStyle(
                    lineWidth: appearance.lineWidth,
                    lineCap: .round
                )
            )
        }
        .opacity(appearance.opacity)
    }
    
    private func createAnatomicallyCorrectGradient() -> Gradient {
        // Calculate where the intersection point falls along this line (0.0 to 1.0)
        let lineLength = distance(from: startPoint, to: endPoint)
        let intersectionDistance = isHorizontal ?
            distance(from: startPoint, to: CGPoint(x: intersectionPoint.x, y: startPoint.y)) :
            distance(from: startPoint, to: CGPoint(x: startPoint.x, y: intersectionPoint.y))
        
        let intersectionRatio = lineLength > 0 ? intersectionDistance / lineLength : 0.5
        
        // Create fade pattern around intersection point
        let fadeWidth = appearance.fadeDistance
        let fadeStart = max(0, intersectionRatio - fadeWidth)
        let fadeEnd = min(1, intersectionRatio + fadeWidth)
        
        return Gradient(stops: [
            .init(color: appearance.color.opacity(appearance.opacity), location: 0.0),
            .init(color: appearance.color.opacity(appearance.opacity), location: fadeStart),
            .init(color: appearance.color.opacity(0.0), location: intersectionRatio), // Invisible at intersection
            .init(color: appearance.color.opacity(appearance.opacity), location: fadeEnd),
            .init(color: appearance.color.opacity(appearance.opacity), location: 1.0)
        ])
    }
    
    // Helper function to calculate distance between two points
    private func distance(from point1: CGPoint, to point2: CGPoint) -> Double {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Medical Crosshair Interaction Handler

struct CrosshairInteractionLayer: View {
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    let plane: MPRPlane
    let viewSize: CGSize
    let volumeData: VolumeData?
    
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        // Transform screen touch to medical coordinates
                        if let medicalPosition = transformScreenToMedicalCoordinates(
                            screenLocation: value.location,
                            plane: plane,
                            volumeData: volumeData,
                            viewSize: viewSize
                        ) {
                            // Update coordinate system with new medical position
                            coordinateSystem.updateWorldPosition(medicalPosition)
                            
                            print("🎯 Touch → Medical: \(value.location) → \(medicalPosition)mm")
                        }
                    }
            )
    }
    
    /// Transform screen coordinates back to 3D medical coordinates
    private func transformScreenToMedicalCoordinates(
        screenLocation: CGPoint,
        plane: MPRPlane,
        volumeData: VolumeData?,
        viewSize: CGSize
    ) -> SIMD3<Float>? {
        
        guard let volumeData = volumeData else { return nil }
        
        // Calculate medical image bounds (same logic as CrosshairOverlayLayer)
        let medicalImageBounds = calculateMedicalImageBounds(
            plane: plane,
            volumeData: volumeData,
            viewSize: viewSize
        )
        
        // Check if touch is within image bounds
        guard medicalImageBounds.contains(screenLocation) else {
            print("🎯 Touch outside image bounds: \(screenLocation)")
            return nil
        }
        
        // Convert screen location to normalized image coordinates [0,1]
        let normalizedX = Float((screenLocation.x - medicalImageBounds.minX) / medicalImageBounds.width)
        let normalizedY = Float(1.0 - (screenLocation.y - medicalImageBounds.minY) / medicalImageBounds.height) // Flip Y
        
        let imageCoordinates = SIMD2<Float>(
            max(0.0, min(1.0, normalizedX)),
            max(0.0, min(1.0, normalizedY))
        )
        
        // Convert 2D image coordinates to 3D medical position based on plane
        let currentPosition = coordinateSystem.currentWorldPosition
        var newMedicalPosition = currentPosition
        
        // Calculate physical position from normalized coordinates
        let physicalDimensions = SIMD3<Float>(
            Float(volumeData.dimensions.x) * volumeData.spacing.x,
            Float(volumeData.dimensions.y) * volumeData.spacing.y,
            Float(volumeData.dimensions.z) * volumeData.spacing.z
        )
        
        switch plane {
        case .axial:
            // XY plane - update X and Y, keep Z
            newMedicalPosition.x = imageCoordinates.x * physicalDimensions.x
            newMedicalPosition.y = imageCoordinates.y * physicalDimensions.y
            
        case .sagittal:
            // YZ plane - update Y and Z, keep X
            newMedicalPosition.y = imageCoordinates.x * physicalDimensions.y
            newMedicalPosition.z = imageCoordinates.y * physicalDimensions.z
            
        case .coronal:
            // XZ plane - update X and Z, keep Y
            newMedicalPosition.x = imageCoordinates.x * physicalDimensions.x
            newMedicalPosition.z = imageCoordinates.y * physicalDimensions.z
        }
        
        return newMedicalPosition
    }
    
    /// Calculate medical image bounds (matching CrosshairOverlayLayer logic)
    private func calculateMedicalImageBounds(
        plane: MPRPlane,
        volumeData: VolumeData,
        viewSize: CGSize
    ) -> CGRect {
        
        // Get texture dimensions for current plane
        let textureDimensions = getTextureDimensions(plane: plane, volumeData: volumeData)
        
        // Calculate physical dimensions using DICOM spacing
        let physicalDimensions = calculatePhysicalDimensions(
            textureWidth: textureDimensions.width,
            textureHeight: textureDimensions.height,
            plane: plane,
            spacing: volumeData.spacing
        )
        
        // Calculate aspect ratios
        let physicalAspect = physicalDimensions.width / physicalDimensions.height
        let viewAspect = Float(viewSize.width / viewSize.height)
        
        // Calculate letterbox bounds (same logic as CTDisplayLayer)
        let quadSize: (width: Float, height: Float)
        
        if physicalAspect > viewAspect {
            // Image is physically wider - letterbox top/bottom
            quadSize = (1.0, viewAspect / physicalAspect)
        } else {
            // Image is physically taller - letterbox left/right
            quadSize = (physicalAspect / viewAspect, 1.0)
        }
        
        // Convert normalized quad size to screen pixel bounds
        let quadWidthPixels = CGFloat(quadSize.width) * viewSize.width
        let quadHeightPixels = CGFloat(quadSize.height) * viewSize.height
        
        let quadX = (viewSize.width - quadWidthPixels) / 2.0
        let quadY = (viewSize.height - quadHeightPixels) / 2.0
        
        return CGRect(
            x: quadX,
            y: quadY,
            width: quadWidthPixels,
            height: quadHeightPixels
        )
    }
    
    /// Get texture dimensions for the specified plane
    private func getTextureDimensions(plane: MPRPlane, volumeData: VolumeData) -> (width: Int, height: Int) {
        let dims = volumeData.dimensions
        
        switch plane {
        case .axial:
            return (dims.x, dims.y)  // 512×512
        case .sagittal:
            return (dims.y, dims.z)  // 512×53
        case .coronal:
            return (dims.x, dims.z)  // 512×53
        }
    }
    
    /// Calculate physical dimensions using DICOM spacing
    private func calculatePhysicalDimensions(
        textureWidth: Int,
        textureHeight: Int,
        plane: MPRPlane,
        spacing: SIMD3<Float>
    ) -> (width: Float, height: Float) {
        
        let pixelWidth = Float(textureWidth)
        let pixelHeight = Float(textureHeight)
        
        switch plane {
        case .axial:
            // XY plane: X × Y dimensions
            let physicalWidth = pixelWidth * spacing.x
            let physicalHeight = pixelHeight * spacing.y
            return (physicalWidth, physicalHeight)
            
        case .sagittal:
            // YZ plane: Y × Z dimensions
            let physicalWidth = pixelWidth * spacing.y
            let physicalHeight = pixelHeight * spacing.z
            return (physicalWidth, physicalHeight)
            
        case .coronal:
            // XZ plane: X × Z dimensions
            let physicalWidth = pixelWidth * spacing.x
            let physicalHeight = pixelHeight * spacing.z
            return (physicalWidth, physicalHeight)
        }
    }
}

// MARK: - Combined Medical-Accurate Crosshair Layer

struct InteractiveCrosshairLayer: View {
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    let plane: MPRPlane
    let viewSize: CGSize
    let volumeData: VolumeData?
    let appearance: CrosshairAppearance
    let allowInteraction: Bool
    
    var body: some View {
        ZStack {
            // Display layer (always present) - Medical-accurate
            CrosshairOverlayLayer(
                coordinateSystem: coordinateSystem,
                plane: plane,
                volumeData: volumeData,
                viewSize: viewSize,
                appearance: appearance
            )
            
            // Interaction layer (optional) - Medical-accurate
            if allowInteraction {
                CrosshairInteractionLayer(
                    coordinateSystem: coordinateSystem,
                    plane: plane,
                    viewSize: viewSize,
                    volumeData: volumeData
                )
            }
        }
    }
}
