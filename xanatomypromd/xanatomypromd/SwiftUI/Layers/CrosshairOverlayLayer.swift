import SwiftUI
import MetalKit

// MARK: - Layer 3: Crosshair Overlay Layer (Uses Central Coordinate Authority)
// MEDICAL PRINCIPLE: Uses DICOMCoordinateSystem as single source of truth
// NO coordinate math here - all handled by central coordinate system

struct CrosshairOverlayLayer: View {
    
    // MARK: - Configuration
    
    /// The authoritative coordinate system (shared with all layers)
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    
    /// Current anatomical plane being displayed
    let plane: MPRPlane
    
    /// Volume data for physical spacing calculations (used by coordinate system)
    let volumeData: VolumeData?
    
    /// View size for coordinate transformations
    let viewSize: CGSize
    
    /// Crosshair appearance settings
    let appearance: CrosshairAppearance
    
    // MARK: - Crosshair Rendering (Uses Coordinate System Authority)
    
    var body: some View {
        GeometryReader { geometry in
            let currentViewSize = geometry.size
            
            // Calculate image bounds using coordinate system
            let imageBounds = coordinateSystem.calculateImageBounds(
                plane: plane,
                viewSize: currentViewSize
            )
            
            // Get crosshair position using coordinate system
            let crosshairPosition = coordinateSystem.worldToScreen(
                position: coordinateSystem.currentWorldPosition,
                plane: plane,
                viewSize: currentViewSize,
                imageBounds: imageBounds
            )
            
            ZStack {
                if appearance.isVisible {
                    // Horizontal crosshair line (constrained to image bounds)
                    CrosshairLine(
                        startPoint: CGPoint(x: imageBounds.minX, y: crosshairPosition.y),
                        endPoint: CGPoint(x: imageBounds.maxX, y: crosshairPosition.y),
                        intersectionPoint: crosshairPosition,
                        appearance: appearance,
                        isHorizontal: true
                    )
                    
                    // Vertical crosshair line (constrained to image bounds)
                    CrosshairLine(
                        startPoint: CGPoint(x: crosshairPosition.x, y: imageBounds.minY),
                        endPoint: CGPoint(x: crosshairPosition.x, y: imageBounds.maxY),
                        intersectionPoint: crosshairPosition,
                        appearance: appearance,
                        isHorizontal: false
                    )
                }
            }
        }
        .allowsHitTesting(false) // Crosshairs are visual only
        .onAppear {
            print("🎯 Crosshairs: Using coordinate system authority for \(plane) plane")
            logCoordinateSystemState()
        }
        .onChange(of: plane) { newPlane in
            print("🎯 Crosshairs: Plane changed to \(newPlane)")
            logCoordinateSystemState()
        }
        .onChange(of: coordinateSystem.currentWorldPosition) { _ in
            logCoordinateSystemState()
        }
    }
    
    // MARK: - Debug and Logging
    
    /// Log coordinate system state for debugging
    private func logCoordinateSystemState() {
        print("🎯 Crosshair Debug (\(plane)):")
        print("   \(coordinateSystem.getDebugInfo())")
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

// MARK: - Crosshair Interaction Handler (Uses Coordinate System Authority)

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
                        // Use coordinate system for screen-to-world conversion
                        let imageBounds = coordinateSystem.calculateImageBounds(
                            plane: plane,
                            viewSize: viewSize
                        )
                        
                        let newWorldPosition = coordinateSystem.screenToWorld(
                            screenPoint: value.location,
                            plane: plane,
                            viewSize: viewSize,
                            imageBounds: imageBounds
                        )
                        
                        // Update coordinate system - broadcasts to all layers
                        coordinateSystem.updateWorldPosition(newWorldPosition)
                        
                        print("🎯 Touch interaction: \(value.location) → \(newWorldPosition) mm")
                    }
            )
    }
}

// MARK: - Combined Crosshair Layer (Uses Coordinate System Authority)

struct InteractiveCrosshairLayer: View {
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    let plane: MPRPlane
    let viewSize: CGSize
    let volumeData: VolumeData?
    let appearance: CrosshairAppearance
    let allowInteraction: Bool
    
    var body: some View {
        ZStack {
            // Display layer - uses coordinate system authority
            CrosshairOverlayLayer(
                coordinateSystem: coordinateSystem,
                plane: plane,
                volumeData: volumeData,
                viewSize: viewSize,
                appearance: appearance
            )
            
            // Interaction layer - uses coordinate system authority
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
