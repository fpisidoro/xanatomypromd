import SwiftUI
import simd

// MARK: - Layer 2: Crosshair Overlay Layer
// Pure overlay that shows current position indicator aligned with CT coordinates
// Completely independent of other layers - only depends on coordinate system

struct CrosshairOverlayLayer: View {
    
    // MARK: - Configuration
    
    /// The authoritative coordinate system (shared with all layers)
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    
    /// Current anatomical plane to display crosshairs for
    let plane: MPRPlane
    
    /// View size for coordinate transformations
    let viewSize: CGSize
    
    /// Crosshair appearance settings
    let appearance: CrosshairAppearance
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            if appearance.isVisible {
                // Get crosshair position from coordinate system
                let screenPosition = coordinateSystem.worldToScreen(
                    position: coordinateSystem.currentWorldPosition,
                    plane: plane,
                    viewSize: viewSize
                )
                
                // Horizontal crosshair line
                CrosshairLine(
                    startPoint: CGPoint(x: 0, y: screenPosition.y),
                    endPoint: CGPoint(x: viewSize.width, y: screenPosition.y),
                    intersectionPoint: screenPosition,
                    appearance: appearance,
                    isHorizontal: true
                )
                
                // Vertical crosshair line
                CrosshairLine(
                    startPoint: CGPoint(x: screenPosition.x, y: 0),
                    endPoint: CGPoint(x: screenPosition.x, y: viewSize.height),
                    intersectionPoint: screenPosition,
                    appearance: appearance,
                    isHorizontal: false
                )
            }
        }
        .allowsHitTesting(false) // Allow touches to pass through to underlying layers
        .onChange(of: coordinateSystem.currentWorldPosition) { _ in
            // Automatically updates when coordinate system changes
            // No manual intervention needed - SwiftUI handles the reactivity
        }
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

// MARK: - Crosshair Interaction Handler
// Handles user interactions with crosshairs (optional - can be used by main view)

struct CrosshairInteractionLayer: View {
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    let plane: MPRPlane
    let viewSize: CGSize
    
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        // Convert screen touch to world coordinates
                        let worldPosition = coordinateSystem.screenToWorld(
                            screenPoint: value.location,
                            plane: plane,
                            viewSize: viewSize
                        )
                        
                        // Update coordinate system - this will automatically update all layers
                        coordinateSystem.updateWorldPosition(worldPosition)
                        
                        // Log for debugging
                        let sliceIndex = coordinateSystem.getCurrentSliceIndex(for: plane)
                        print("🎯 Crosshair moved via touch: \(plane.displayName) slice \(sliceIndex) at (\(String(format: "%.1f", worldPosition.x)), \(String(format: "%.1f", worldPosition.y)), \(String(format: "%.1f", worldPosition.z))) mm")
                    }
            )
    }
}

// MARK: - Combined Crosshair Layer with Interaction
// Complete crosshair layer that includes both display and interaction

struct InteractiveCrosshairLayer: View {
    @ObservedObject var coordinateSystem: DICOMCoordinateSystem
    let plane: MPRPlane
    let viewSize: CGSize
    let appearance: CrosshairAppearance
    let allowInteraction: Bool
    
    var body: some View {
        ZStack {
            // Display layer (always present)
            CrosshairOverlayLayer(
                coordinateSystem: coordinateSystem,
                plane: plane,
                viewSize: viewSize,
                appearance: appearance
            )
            
            // Interaction layer (optional)
            if allowInteraction {
                CrosshairInteractionLayer(
                    coordinateSystem: coordinateSystem,
                    plane: plane,
                    viewSize: viewSize
                )
            }
        }
    }
}
