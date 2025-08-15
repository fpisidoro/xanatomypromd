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
        view.addGestureRecognizer(panGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }
    
    class Coordinator: NSObject {
        let onScroll: (Int, CGFloat) -> Void
        private var lastTranslation: CGFloat = 0
        
        init(onScroll: @escaping (Int, CGFloat) -> Void) {
            self.onScroll = onScroll
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            switch gesture.state {
            case .began:
                lastTranslation = translation.y
            case .changed:
                let deltaY = translation.y - lastTranslation
                if abs(deltaY) > 8 {
                    let direction = deltaY > 0 ? 1 : -1
                    let speed = abs(velocity.y)
                    onScroll(direction, speed)
                    lastTranslation = translation.y
                }
            case .ended, .cancelled:
                lastTranslation = 0
            default:
                break
            }
        }
    }
}
