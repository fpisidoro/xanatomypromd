import SwiftUI
import UIKit

// MARK: - UIKit 2-Finger Gesture Handler
// Proper 2-finger detection using UIKit's UIPanGestureRecognizer

struct TwoFingerScrollHandler: UIViewRepresentable {
    let onScroll: (Int, CGFloat) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 2
        panGesture.maximumNumberOfTouches = 2
        panGesture.delegate = context.coordinator  // Enable simultaneous recognition
        view.addGestureRecognizer(panGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onScroll: (Int, CGFloat) -> Void
        private var lastTranslation: CGFloat = 0
        
        init(onScroll: @escaping (Int, CGFloat) -> Void) {
            self.onScroll = onScroll
        }
        
        // MARK: - UIGestureRecognizerDelegate
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow simultaneous recognition with SwiftUI gestures
            return true
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            // Only handle 2-finger gestures
            guard gesture.numberOfTouches == 2 else { return }
            
            switch gesture.state {
            case .began:
                lastTranslation = translation.y
                
            case .changed:
                let deltaY = translation.y - lastTranslation
                let deltaX = translation.x
                
                // Only handle primarily vertical movement
                // If horizontal movement is significant, let SwiftUI handle it (pan/pinch)
                let isVerticalGesture = abs(deltaY) > abs(deltaX) * 0.7
                
                if isVerticalGesture && abs(deltaY) > 8 {
                    let direction = deltaY > 0 ? 1 : -1
                    let speed = abs(velocity.y)
                    onScroll(direction, speed)
                    lastTranslation = translation.y
                }
                // If not vertical enough, ignore - let SwiftUI gestures handle it
                
            case .ended, .cancelled:
                lastTranslation = 0
                
            default:
                break
            }
        }
    }
}
