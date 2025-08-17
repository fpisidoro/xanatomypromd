import SwiftUI
import UIKit

// MARK: - Unified Gesture Handler with Smooth Scrolling
// Fixed: Distance-based thresholds, velocity damping, proper gesture state tracking

struct UnifiedGestureHandler: UIViewRepresentable {
    let onGesture: (GestureType, GestureData) -> Void
    let currentZoom: CGFloat  // NEW: Current zoom level for gesture routing
    let baselineZoom: CGFloat  // NEW: Baseline zoom for threshold calculation
    
    enum GestureType {
        case pan, pinch, twoFingerScroll, scrollEnd, oneFingerScroll  // NEW: oneFingerScroll
    }
    
    struct GestureData {
        let translation: CGPoint
        let velocity: CGPoint
        let scale: CGFloat
        let direction: Int
        let speed: CGFloat
        let accumulatedDistance: CGFloat
        
        static let zero = GestureData(translation: .zero, velocity: .zero, scale: 1.0, direction: 0, speed: 0, accumulatedDistance: 0)
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
        // Update the coordinator with the current zoom level
        context.coordinator.updateZoom(currentZoom)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onGesture: onGesture, currentZoom: currentZoom, baselineZoom: baselineZoom)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onGesture: (GestureType, GestureData) -> Void
        private var currentZoom: CGFloat
        private var baselineZoom: CGFloat
        
        // 2-finger scroll state tracking
        private var scrollAccumulator: CGFloat = 0
        private var lastScrollTranslation: CGFloat = 0
        private var isScrolling = false
        
        // 1-finger scroll state tracking
        private var oneFingerScrollAccumulator: CGFloat = 0
        private var lastOneFingerTranslation: CGFloat = 0
        
        // Distance thresholds for different slice counts
        private let baseScrollThreshold: CGFloat = 15  // pixels needed to trigger slice change
        
        init(onGesture: @escaping (GestureType, GestureData) -> Void, currentZoom: CGFloat, baselineZoom: CGFloat) {
            self.onGesture = onGesture
            self.currentZoom = currentZoom
            self.baselineZoom = baselineZoom
        }
        
        // Update zoom level for gesture routing decisions
        func updateZoom(_ zoom: CGFloat) {
            let zoomThresholdForPan = baselineZoom * 1.5  // Relative threshold
            
            if abs(self.currentZoom - zoom) > 0.01 {  // Only log significant changes
                let oldBehavior = self.currentZoom <= zoomThresholdForPan ? "scroll" : "pan"
                let newBehavior = zoom <= zoomThresholdForPan ? "scroll" : "pan"
                
                if oldBehavior != newBehavior {
                    print("🔄 1-finger behavior: \(oldBehavior) → \(newBehavior) (zoom: \(String(format: "%.1f", zoom))x, threshold: \(String(format: "%.1f", zoomThresholdForPan))x)")
                }
            }
            self.currentZoom = zoom
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
                    accumulatedDistance: 0
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
                            accumulatedDistance: oneFingerScrollAccumulator
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
                    accumulatedDistance: 0
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
                            accumulatedDistance: scrollAccumulator
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
                    
                    let data = GestureData.zero
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
                    accumulatedDistance: 0
                )
                
                onGesture(.pan, data)
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            let data = GestureData(
                translation: .zero,
                velocity: .zero,
                scale: gesture.scale,
                direction: 0,
                speed: 0,
                accumulatedDistance: 0
            )
            
            onGesture(.pinch, data)
        }
    }
}
