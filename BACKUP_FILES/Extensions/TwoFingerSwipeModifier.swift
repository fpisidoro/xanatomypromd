import SwiftUI
import UIKit

// MARK: - Two-Finger Swipe Gesture for Slice Navigation
// Enables medical-style two-finger vertical scrolling through slices

struct TwoFingerSwipeModifier: ViewModifier {
    let onSwipe: (CGFloat, CGFloat) -> Void  // translation, velocity
    @State private var initialTouchPoint: CGPoint = .zero
    
    func body(content: Content) -> some View {
        content
            .background(
                TwoFingerSwipeView(onSwipe: onSwipe)
                    .allowsHitTesting(true)
            )
    }
}

extension View {
    /// Detects two-finger swipe gestures for slice navigation
    func onTwoFingerSwipe(perform action: @escaping (CGFloat, CGFloat) -> Void) -> some View {
        self.modifier(TwoFingerSwipeModifier(onSwipe: action))
    }
}

// MARK: - UIKit Integration

struct TwoFingerSwipeView: UIViewRepresentable {
    let onSwipe: (CGFloat, CGFloat) -> Void
    
    func makeUIView(context: Context) -> TwoFingerGestureView {
        let view = TwoFingerGestureView()
        view.onSwipe = onSwipe
        return view
    }
    
    func updateUIView(_ uiView: TwoFingerGestureView, context: Context) {
        uiView.onSwipe = onSwipe
    }
}

class TwoFingerGestureView: UIView {
    var onSwipe: ((CGFloat, CGFloat) -> Void)?
    private var lastTranslation: CGFloat = 0
    private var velocityTracker: VelocityTracker = VelocityTracker()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
    }
    
    private func setupGestures() {
        isUserInteractionEnabled = true
        backgroundColor = .clear
        
        // Two-finger pan gesture
        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        addGestureRecognizer(twoFingerPan)
        
        // Also detect trackpad two-finger scroll
        let scrollPan = UIPanGestureRecognizer(target: self, action: #selector(handleScrollPan(_:)))
        scrollPan.allowedScrollTypesMask = .continuous
        addGestureRecognizer(scrollPan)
    }
    
    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        
        switch gesture.state {
        case .began:
            lastTranslation = 0
            velocityTracker.reset()
            
        case .changed:
            let delta = translation.y - lastTranslation
            if abs(delta) > 0.5 {  // Threshold to avoid jitter
                // Calculate instantaneous velocity
                let instantVelocity = abs(velocity.y / 100.0)
                velocityTracker.addSample(velocity: instantVelocity)
                
                onSwipe?(delta, velocityTracker.averageVelocity)
                lastTranslation = translation.y
            }
            
        case .ended, .cancelled:
            // Send final velocity for momentum
            onSwipe?(0, 0)
            velocityTracker.reset()
            
        default:
            break
        }
    }
    
    @objc private func handleScrollPan(_ gesture: UIPanGestureRecognizer) {
        // Handle trackpad scrolling (when numberOfTouches == 0)
        if gesture.numberOfTouches == 0 {
            let translation = gesture.translation(in: self)
            let velocity = gesture.velocity(in: self)
            
            if abs(translation.y) > 0 {
                onSwipe?(-translation.y, abs(velocity.y / 100.0))
                gesture.setTranslation(.zero, in: self)
            }
        }
    }
}

// MARK: - Velocity Tracking Helper

private class VelocityTracker {
    private var samples: [(velocity: CGFloat, time: Date)] = []
    private let maxSamples = 5
    private let sampleTimeout: TimeInterval = 0.1
    
    func addSample(velocity: CGFloat) {
        let now = Date()
        samples.append((velocity, now))
        
        // Remove old samples
        samples = samples.filter { now.timeIntervalSince($0.time) < sampleTimeout }
        
        // Keep only recent samples
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }
    
    var averageVelocity: CGFloat {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0) { $0 + $1.velocity }
        return sum / CGFloat(samples.count)
    }
    
    func reset() {
        samples.removeAll()
    }
}
