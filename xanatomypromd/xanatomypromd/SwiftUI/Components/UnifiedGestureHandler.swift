import SwiftUI
import UIKit

// MARK: - Unified Gesture Handler with Integrated Zoom Management
// Pure UIKit approach - eliminates SwiftUI/UIKit gesture conflicts

struct UnifiedGestureHandler: UIViewRepresentable {
    let onGesture: (GestureType, GestureData) -> Void
    let onZoomChange: (CGFloat) -> Void  // NEW: Direct zoom callback
    let viewSize: CGSize  // NEW: For baseline calculation
    let volumeDimensions: SIMD3<Int32>  // NEW: For baseline calculation
    let currentPlane: MPRPlane  // NEW: For plane-aware baseline
    
    enum GestureType {
        case pan, pinch, twoFingerScroll, scrollEnd, oneFingerScroll, zoomEnd  // NEW: zoomEnd
    }
    
    struct GestureData {
        let translation: CGPoint
        let velocity: CGPoint
        let scale: CGFloat
        let direction: Int
        let speed: CGFloat
        let accumulatedDistance: CGFloat
        let zoomLevel: CGFloat  // NEW: Current zoom level
        let baselineZoom: CGFloat  // NEW: Calculated baseline
        
        static let zero = GestureData(translation: .zero, velocity: .zero, scale: 1.0, direction: 0, speed: 0, accumulatedDistance: 0, zoomLevel: 1.0, baselineZoom: 1.0)
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        // 1-finger pan gesture
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        
        // 2-finger pan gesture (for scrolling)
        let twoFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        
        // Pinch gesture
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        
        // Allow simultaneous recognition
        panGesture.delegate = context.coordinator
        twoFingerPan.delegate = context.coordinator
        pinchGesture.delegate = context.coordinator
        
        view.addGestureRecognizer(panGesture)
        view.addGestureRecognizer(twoFingerPan)
        view.addGestureRecognizer(pinchGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update coordinator with current parameters
        context.coordinator.updateParameters(
            viewSize: viewSize,
            volumeDimensions: volumeDimensions,
            currentPlane: currentPlane
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            onGesture: onGesture,
            onZoomChange: onZoomChange,
            viewSize: viewSize,
            volumeDimensions: volumeDimensions,
            currentPlane: currentPlane
        )
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onGesture: (GestureType, GestureData) -> Void
        let onZoomChange: (CGFloat) -> Void
        
        // Zoom state management
        private var currentZoom: CGFloat = 1.0
        private var lastZoom: CGFloat = 1.0
        private var baselineZoom: CGFloat = 1.0
        private var isPinching = false
        
        // View parameters for baseline calculation
        private var viewSize: CGSize
        private var volumeDimensions: SIMD3<Int32>
        private var currentPlane: MPRPlane
        
        // 2-finger scroll state tracking
        private var scrollAccumulator: CGFloat = 0
        private var lastScrollTranslation: CGFloat = 0
        private var isScrolling = false
        
        // 1-finger scroll state tracking
        private var oneFingerScrollAccumulator: CGFloat = 0
        private var lastOneFingerTranslation: CGFloat = 0
        
        // Distance thresholds for different slice counts
        private let baseScrollThreshold: CGFloat = 15  // pixels needed to trigger slice change
        
        init(
            onGesture: @escaping (GestureType, GestureData) -> Void,
            onZoomChange: @escaping (CGFloat) -> Void,
            viewSize: CGSize,
            volumeDimensions: SIMD3<Int32>,
            currentPlane: MPRPlane
        ) {
            self.onGesture = onGesture
            self.onZoomChange = onZoomChange
            self.viewSize = viewSize
            self.volumeDimensions = volumeDimensions
            self.currentPlane = currentPlane
            super.init()
            
            // Calculate initial baseline
            updateBaseline()
            currentZoom = baselineZoom
            lastZoom = baselineZoom
        }
        
        // Update parameters for baseline recalculation
        func updateParameters(viewSize: CGSize, volumeDimensions: SIMD3<Int32>, currentPlane: MPRPlane) {
            let oldBaseline = baselineZoom
            
            self.viewSize = viewSize
            self.volumeDimensions = volumeDimensions
            self.currentPlane = currentPlane
            
            updateBaseline()
            
            // If baseline changed significantly, update current zoom proportionally
            if abs(oldBaseline - baselineZoom) > 0.01 && oldBaseline > 0 {
                let ratio = baselineZoom / oldBaseline
                currentZoom *= ratio
                lastZoom *= ratio
                
                print("📐 Baseline changed: \(String(format: "%.2f", oldBaseline))x → \(String(format: "%.2f", baselineZoom))x, zoom adjusted: \(String(format: "%.2f", currentZoom))x")
                onZoomChange(currentZoom)
            }
        }
        
        // MARK: - Baseline Zoom Calculation
        
        private func updateBaseline() {
            baselineZoom = calculateFitToViewBaseline()
            print("🎯 Baseline calculated: \(String(format: "%.2f", baselineZoom))x for \(currentPlane.displayName) (\(Int(viewSize.width))×\(Int(viewSize.height)))")
        }
        
        private func calculateFitToViewBaseline() -> CGFloat {
            guard viewSize.width > 0 && viewSize.height > 0 else { return 1.0 }
            
            // Get plane-specific image dimensions (these are the actual image pixel dimensions)
            let imageDimensions = getPlaneImageDimensions()
            
            // Calculate scale factors for both dimensions
            let scaleX = viewSize.width / imageDimensions.width
            let scaleY = viewSize.height / imageDimensions.height
            
            // Use the smaller scale factor to ensure the image fits completely
            let fitScale = min(scaleX, scaleY)
            
            // Apply 75% fill factor and bounds
            let targetFillRatio: CGFloat = 0.75
            let baseline = fitScale * targetFillRatio
            
            // Apply reasonable bounds
            let minBaseline: CGFloat = 0.1
            let maxBaseline: CGFloat = 2.5
            
            return max(minBaseline, min(baseline, maxBaseline))
        }
        
        private func getPlaneImageDimensions() -> CGSize {
            // Convert volume dimensions to image dimensions based on plane
            switch currentPlane {
            case .axial:
                // Axial: width=X, height=Y
                return CGSize(width: CGFloat(volumeDimensions.x), height: CGFloat(volumeDimensions.y))
            case .sagittal:
                // Sagittal: width=Y, height=Z
                return CGSize(width: CGFloat(volumeDimensions.y), height: CGFloat(volumeDimensions.z))
            case .coronal:
                // Coronal: width=X, height=Z
                return CGSize(width: CGFloat(volumeDimensions.x), height: CGFloat(volumeDimensions.z))
            }
        }
        
        // MARK: - UIGestureRecognizerDelegate
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        // MARK: - Gesture Handlers
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            let zoomThresholdForPan = baselineZoom * 1.5  // Relative threshold
            
            // Determine behavior based on zoom level
            if currentZoom <= zoomThresholdForPan {
                // At default zoom: 1-finger scroll
                if gesture.state == .began {
                    print("🖱️ 1-finger @ \(String(format: "%.1f", currentZoom))x → SCROLL mode (threshold: \(String(format: "%.1f", zoomThresholdForPan))x)")
                }
                handleOneFingerScroll(gesture: gesture, translation: translation, velocity: velocity)
            } else {
                // Zoomed in: 1-finger pan
                if gesture.state == .began {
                    print("🖱️ 1-finger @ \(String(format: "%.1f", currentZoom))x → PAN mode (threshold: \(String(format: "%.1f", zoomThresholdForPan))x)")
                }
                let data = GestureData(
                    translation: translation,
                    velocity: velocity,
                    scale: 1.0,
                    direction: 0,
                    speed: 0,
                    accumulatedDistance: 0,
                    zoomLevel: currentZoom,
                    baselineZoom: baselineZoom
                )
                
                onGesture(.pan, data)
            }
        }
        
        private func handleOneFingerScroll(gesture: UIPanGestureRecognizer, translation: CGPoint, velocity: CGPoint) {
            // Only handle primarily vertical movement for slice scrolling (like 2-finger)
            let isVerticalGesture = abs(translation.y) > abs(translation.x) * 0.7
            
            if isVerticalGesture {
                switch gesture.state {
                case .began:
                    oneFingerScrollAccumulator = 0
                    lastOneFingerTranslation = translation.y
                    
                case .changed:
                    let deltaY = translation.y - lastOneFingerTranslation
                    oneFingerScrollAccumulator += abs(deltaY)
                    
                    // Only trigger slice change when accumulated enough distance
                    if oneFingerScrollAccumulator >= baseScrollThreshold {
                        let direction = translation.y > lastOneFingerTranslation ? 1 : -1
                        let speed = abs(velocity.y)
                        
                        let data = GestureData(
                            translation: CGPoint(x: 0, y: deltaY),
                            velocity: CGPoint(x: 0, y: velocity.y),
                            scale: 1.0,
                            direction: direction,
                            speed: speed,
                            accumulatedDistance: oneFingerScrollAccumulator,
                            zoomLevel: currentZoom,
                            baselineZoom: baselineZoom
                        )
                        
                        onGesture(.oneFingerScroll, data)
                        
                        // Reset accumulator after triggering slice change
                        oneFingerScrollAccumulator = 0
                        lastOneFingerTranslation = translation.y
                    }
                    
                case .ended, .cancelled:
                    oneFingerScrollAccumulator = 0
                    lastOneFingerTranslation = 0
                    
                default:
                    break
                }
            } else {
                // Horizontal 1-finger at low zoom = pan (for slight adjustments)
                let data = GestureData(
                    translation: translation,
                    velocity: velocity,
                    scale: 1.0,
                    direction: 0,
                    speed: 0,
                    accumulatedDistance: 0,
                    zoomLevel: currentZoom,
                    baselineZoom: baselineZoom
                )
                
                onGesture(.pan, data)
            }
        }
        
        @objc func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            // Only handle primarily vertical movement for slice scrolling
            let isVerticalGesture = abs(translation.y) > abs(translation.x) * 0.7
            
            if isVerticalGesture {
                switch gesture.state {
                case .began:
                    // Start scrolling - trigger quality reduction
                    scrollAccumulator = 0
                    lastScrollTranslation = translation.y
                    isScrolling = true
                    
                case .changed:
                    // Accumulate distance for smooth scrolling
                    let deltaY = translation.y - lastScrollTranslation
                    scrollAccumulator += abs(deltaY)
                    
                    // Only trigger slice change when accumulated enough distance
                    if scrollAccumulator >= baseScrollThreshold {
                        let direction = translation.y > lastScrollTranslation ? 1 : -1
                        let speed = abs(velocity.y)
                        
                        let data = GestureData(
                            translation: CGPoint(x: 0, y: deltaY),
                            velocity: CGPoint(x: 0, y: velocity.y),
                            scale: 1.0,
                            direction: direction,
                            speed: speed,
                            accumulatedDistance: scrollAccumulator,
                            zoomLevel: currentZoom,
                            baselineZoom: baselineZoom
                        )
                        
                        onGesture(.twoFingerScroll, data)
                        
                        // Reset accumulator after triggering slice change
                        scrollAccumulator = 0
                        lastScrollTranslation = translation.y
                    }
                    
                case .ended, .cancelled:
                    // End scrolling - restore quality
                    isScrolling = false
                    scrollAccumulator = 0
                    lastScrollTranslation = 0
                    
                    let data = GestureData(
                        translation: .zero,
                        velocity: .zero,
                        scale: 1.0,
                        direction: 0,
                        speed: 0,
                        accumulatedDistance: 0,
                        zoomLevel: currentZoom,
                        baselineZoom: baselineZoom
                    )
                    onGesture(.scrollEnd, data)
                    
                default:
                    break
                }
            } else {
                // Horizontal 2-finger = pan
                let data = GestureData(
                    translation: translation,
                    velocity: velocity,
                    scale: 1.0,
                    direction: 0,
                    speed: 0,
                    accumulatedDistance: 0,
                    zoomLevel: currentZoom,
                    baselineZoom: baselineZoom
                )
                
                onGesture(.pan, data)
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                isPinching = true
                // CRITICAL FIX: Sync lastZoom to currentZoom at gesture start
                lastZoom = currentZoom
                print("🔄 Pinch START: lastZoom synced to \(String(format: "%.2f", lastZoom))x, scale: \(String(format: "%.2f", gesture.scale))")
                
            case .changed:
                // Calculate new zoom based on synced lastZoom
                let newZoom = lastZoom * gesture.scale
                
                // Apply zoom constraints
                let minZoom = baselineZoom * 0.5
                let maxZoom = baselineZoom * 4.0
                currentZoom = max(minZoom, min(newZoom, maxZoom))
                
                // Notify zoom change
                onZoomChange(currentZoom)
                
                // Send gesture data
                let data = GestureData(
                    translation: .zero,
                    velocity: .zero,
                    scale: gesture.scale,
                    direction: 0,
                    speed: 0,
                    accumulatedDistance: 0,
                    zoomLevel: currentZoom,
                    baselineZoom: baselineZoom
                )
                
                onGesture(.pinch, data)
                
            case .ended, .cancelled:
                isPinching = false
                // Update lastZoom for next gesture
                lastZoom = currentZoom
                print("🔄 Pinch END: lastZoom updated to \(String(format: "%.2f", lastZoom))x")
                
                // Notify zoom end for any cleanup
                let data = GestureData(
                    translation: .zero,
                    velocity: .zero,
                    scale: gesture.scale,
                    direction: 0,
                    speed: 0,
                    accumulatedDistance: 0,
                    zoomLevel: currentZoom,
                    baselineZoom: baselineZoom
                )
                
                onGesture(.zoomEnd, data)
                
            default:
                break
            }
        }
        
        // MARK: - Public Interface
        
        func getCurrentZoom() -> CGFloat {
            return currentZoom
        }
        
        func getBaselineZoom() -> CGFloat {
            return baselineZoom
        }
        
        func resetToBaseline() {
            currentZoom = baselineZoom
            lastZoom = baselineZoom
            onZoomChange(currentZoom)
            print("🔄 Zoom reset to baseline: \(String(format: "%.2f", baselineZoom))x")
        }
    }
}
