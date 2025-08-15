import SwiftUI
import UIKit

// MARK: - Unified Gesture Handler
// Handles all gestures (1-finger, 2-finger, pinch) in UIKit for proper coordination

struct UnifiedGestureHandler: UIViewRepresentable {
    let onGesture: (GestureType, GestureData) -> Void
    
    enum GestureType {
        case pan, pinch, twoFingerScroll
    }
    
    struct GestureData {
        let translation: CGPoint
        let velocity: CGPoint
        let scale: CGFloat
        let direction: Int
        let speed: CGFloat
        
        static let zero = GestureData(translation: .zero, velocity: .zero, scale: 1.0, direction: 0, speed: 0)
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
                speed: 0
            )
            
            onGesture(.pan, data)
        }
        
        @objc func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            // Only handle primarily vertical movement for slice scrolling
            let isVerticalGesture = abs(translation.y) > abs(translation.x) * 0.7
            
            if isVerticalGesture {
                let direction = translation.y > 0 ? 1 : -1
                let speed = abs(velocity.y)
                
                let data = GestureData(
                    translation: translation,
                    velocity: velocity,
                    scale: 1.0,
                    direction: direction,
                    speed: speed
                )
                
                onGesture(.twoFingerScroll, data)
            } else {
                // Horizontal 2-finger = pan
                let data = GestureData(
                    translation: translation,
                    velocity: velocity,
                    scale: 1.0,
                    direction: 0,
                    speed: 0
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
                speed: 0
            )
            
            onGesture(.pinch, data)
        }
    }
}
