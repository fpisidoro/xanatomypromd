import SwiftUI
import UIKit

// MARK: - Unified Gesture Handler with Smooth Scrolling
// Fixed: Distance-based thresholds, velocity damping, proper gesture state tracking

struct UnifiedGestureHandler: UIViewRepresentable {
    let onGesture: (GestureType, GestureData) -> Void
    
    enum GestureType {
        case pan, pinch, twoFingerScroll, scrollEnd
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
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onGesture: onGesture)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onGesture: (GestureType, GestureData) -> Void
        
        // 2-finger scroll state tracking
        private var scrollAccumulator: CGFloat = 0
        private var lastScrollTranslation: CGFloat = 0
        private var isScrolling = false
        
        // Distance thresholds for different slice counts
        private let baseScrollThreshold: CGFloat = 15  // pixels needed to trigger slice change
        
        init(onGesture: @escaping (GestureType, GestureData) -> Void) {
            self.onGesture = onGesture
        }
        
        // MARK: - UIGestureRecognizerDelegate
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        // MARK: - Gesture Handlers
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
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
