import SwiftUI
import UIKit

// MARK: - Scroll Wheel Support for iOS/iPadOS
// Enables mouse scroll wheel input for slice navigation

struct ScrollWheelModifier: ViewModifier {
    let onScroll: (CGFloat) -> Void
    
    func body(content: Content) -> some View {
        content
            .background(ScrollWheelDetector(onScroll: onScroll))
    }
}

extension View {
    /// Detects scroll wheel events (mouse/trackpad)
    func onScrollWheel(perform action: @escaping (CGFloat) -> Void) -> some View {
        self.modifier(ScrollWheelModifier(onScroll: action))
    }
}

// MARK: - UIKit Integration for Scroll Detection

struct ScrollWheelDetector: UIViewRepresentable {
    let onScroll: (CGFloat) -> Void
    
    func makeUIView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onScroll = onScroll
        return view
    }
    
    func updateUIView(_ uiView: ScrollWheelView, context: Context) {
        uiView.onScroll = onScroll
    }
}

class ScrollWheelView: UIView {
    var onScroll: ((CGFloat) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
    }
    
    private func setupGestures() {
        // Enable user interaction
        isUserInteractionEnabled = true
        
        // Add pan gesture recognizer for scroll wheel/trackpad
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.allowedScrollTypesMask = [.continuous, .discrete]
        addGestureRecognizer(panGesture)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        // Check if this is a scroll gesture (not touch)
        // numberOfTouches == 0 indicates mouse/trackpad scroll
        if gesture.numberOfTouches == 0 {
            let translation = gesture.translation(in: self)
            
            // Use vertical component for slice scrolling
            if abs(translation.y) > 0 {
                // Invert the scroll direction for natural scrolling
                onScroll?(-translation.y)
                gesture.setTranslation(.zero, in: self)
            }
        }
    }
}
