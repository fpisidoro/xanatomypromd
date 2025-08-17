import SwiftUI
import UIKit
import simd

// MARK: - MPR Gesture Controller
// Pure UIKit gesture handling with no SwiftUI dependencies
// ALL gesture logic lives here - this is the single source of truth for gesture behavior

struct MPRGestureController: UIViewRepresentable {
    
    // MARK: - Configuration
    
    /// View state object (our only connection to SwiftUI)
    @ObservedObject var viewState: MPRViewState
    
    /// Coordinate system for slice navigation
    let coordinateSystem: DICOMCoordinateSystem
    
    /// Shared state for quality control
    let sharedState: SharedViewingState
    
    /// Gesture configuration
    let config: GestureConfiguration
    
    // MARK: - UIViewRepresentable Implementation
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let coordinator = context.coordinator
        
        // Create all gesture recognizers
        let panGesture = UIPanGestureRecognizer(
            target: coordinator, 
            action: #selector(Coordinator.handlePan(_:))
        )
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        
        let twoFingerPan = UIPanGestureRecognizer(
            target: coordinator, 
            action: #selector(Coordinator.handleTwoFingerPan(_:))
        )
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        
        let pinchGesture = UIPinchGestureRecognizer(
            target: coordinator, 
            action: #selector(Coordinator.handlePinch(_:))
        )
        
        // Configure simultaneous recognition
        panGesture.delegate = coordinator
        twoFingerPan.delegate = coordinator
        pinchGesture.delegate = coordinator
        
        // Add gestures to view
        view.addGestureRecognizer(panGesture)
        view.addGestureRecognizer(twoFingerPan)
        view.addGestureRecognizer(pinchGesture)
        
        // Store gesture references in coordinator
        coordinator.setupGestures(
            panGesture: panGesture,
            twoFingerPan: twoFingerPan,
            pinchGesture: pinchGesture
        )
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update coordinator with current configuration
        context.coordinator.updateConfiguration()
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(
            viewState: viewState,
            coordinateSystem: coordinateSystem,
            sharedState: sharedState,
            config: config
        )
    }
    
    // MARK: - Coordinator (Pure UIKit)
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        
        // MARK: - Dependencies
        
        var viewState: MPRViewState
        let coordinateSystem: DICOMCoordinateSystem
        let sharedState: SharedViewingState
        let config: GestureConfiguration
        
        // MARK: - Gesture State
        
        private var lastZoomForPinch: CGFloat = 1.0
        
        // Scroll state tracking
        private var scrollAccumulator: CGFloat = 0
        private var lastScrollTranslation: CGFloat = 0
        
        // One finger scroll state
        private var oneFingerScrollAccumulator: CGFloat = 0
        private var lastOneFingerTranslation: CGFloat = 0
        
        // Gesture recognizer references
        private weak var panGesture: UIPanGestureRecognizer?
        private weak var twoFingerPan: UIPanGestureRecognizer?
        private weak var pinchGesture: UIPinchGestureRecognizer?
        
        // MARK: - Initialization
        
        init(
            viewState: MPRViewState,
            coordinateSystem: DICOMCoordinateSystem,
            sharedState: SharedViewingState,
            config: GestureConfiguration
        ) {
            self.viewState = viewState
            self.coordinateSystem = coordinateSystem
            self.sharedState = sharedState
            self.config = config
            super.init()
            
            // Initialize zoom state
            self.lastZoomForPinch = viewState.zoom
        }
        
        // MARK: - Setup
        
        func setupGestures(
            panGesture: UIPanGestureRecognizer,
            twoFingerPan: UIPanGestureRecognizer,
            pinchGesture: UIPinchGestureRecognizer
        ) {
            self.panGesture = panGesture
            self.twoFingerPan = twoFingerPan
            self.pinchGesture = pinchGesture
        }
        
        func updateConfiguration() {
            // Sync any configuration changes
            // Currently no dynamic config updates needed
        }
        
        // MARK: - UIGestureRecognizerDelegate
        
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, 
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Allow pinch and pan to work together
            // Prevent conflicts between 1-finger and 2-finger pan
            
            if gestureRecognizer == pinchGesture || otherGestureRecognizer == pinchGesture {
                return true  // Pinch can work with pan
            }
            
            if (gestureRecognizer == panGesture && otherGestureRecognizer == twoFingerPan) ||
               (gestureRecognizer == twoFingerPan && otherGestureRecognizer == panGesture) {
                return false  // Prevent 1-finger and 2-finger pan conflicts
            }
            
            return true
        }
        
        // MARK: - Gesture Handlers
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            // Determine behavior based on current zoom level
            if viewState.allowsOneFingerScroll {
                // At low zoom: 1-finger scroll
                handleOneFingerScroll(gesture: gesture, translation: translation, velocity: velocity)
            } else {
                // At high zoom: 1-finger pan
                handlePanMovement(gesture: gesture, translation: translation, velocity: velocity)
            }
        }
        
        private func handleOneFingerScroll(
            gesture: UIPanGestureRecognizer, 
            translation: CGPoint, 
            velocity: CGPoint
        ) {
            // Only handle primarily vertical movement for slice scrolling
            let isVerticalGesture = abs(translation.y) > abs(translation.x) * config.verticalGestureRatio
            
            if isVerticalGesture {
                switch gesture.state {
                case .began:
                    oneFingerScrollAccumulator = 0
                    lastOneFingerTranslation = translation.y
                    viewState.setInteractionState(isScrolling: true)
                    
                    print("🖱️ 1-finger @ \(String(format: "%.1f", viewState.zoom))x → SCROLL mode")
                    
                case .changed:
                    let deltaY = translation.y - lastOneFingerTranslation
                    oneFingerScrollAccumulator += abs(deltaY)
                    
                    // Trigger slice change when accumulated enough distance
                    if oneFingerScrollAccumulator >= config.baseScrollThreshold {
                        let direction = translation.y > lastOneFingerTranslation ? 1 : -1
                        let speed = abs(velocity.y)
                        
                        handleSliceScroll(direction: direction, speed: speed)
                        
                        // Reset accumulator after triggering slice change
                        oneFingerScrollAccumulator = 0
                        lastOneFingerTranslation = translation.y
                    }
                    
                case .ended, .cancelled:
                    oneFingerScrollAccumulator = 0
                    lastOneFingerTranslation = 0
                    viewState.setInteractionState(isScrolling: false)
                    restoreScrollQuality()
                    
                default:
                    break
                }
            } else {
                // Horizontal 1-finger at low zoom = pan (for slight adjustments)
                handlePanMovement(gesture: gesture, translation: translation, velocity: velocity)
            }
        }
        
        private func handlePanMovement(
            gesture: UIPanGestureRecognizer,
            translation: CGPoint,
            velocity: CGPoint
        ) {
            switch gesture.state {
            case .began:
                viewState.setInteractionState(isPanning: true)
                print("🖱️ 1-finger @ \(String(format: "%.1f", viewState.zoom))x → PAN mode")
                
            case .changed:
                viewState.setPan(CGSize(width: translation.x, height: translation.y))
                
            case .ended, .cancelled:
                viewState.setInteractionState(isPanning: false)
                
            default:
                break
            }
        }
        
        @objc func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            // Only handle primarily vertical movement for slice scrolling
            let isVerticalGesture = abs(translation.y) > abs(translation.x) * config.verticalGestureRatio
            
            if isVerticalGesture {
                switch gesture.state {
                case .began:
                    scrollAccumulator = 0
                    lastScrollTranslation = translation.y
                    viewState.setInteractionState(isScrolling: true)
                    
                case .changed:
                    let deltaY = translation.y - lastScrollTranslation
                    scrollAccumulator += abs(deltaY)
                    
                    // Trigger slice change when accumulated enough distance
                    if scrollAccumulator >= config.baseScrollThreshold {
                        let direction = translation.y > lastScrollTranslation ? 1 : -1
                        let speed = abs(velocity.y)
                        
                        handleSliceScroll(direction: direction, speed: speed)
                        
                        // Reset accumulator after triggering slice change
                        scrollAccumulator = 0
                        lastScrollTranslation = translation.y
                    }
                    
                case .ended, .cancelled:
                    scrollAccumulator = 0
                    lastScrollTranslation = 0
                    viewState.setInteractionState(isScrolling: false)
                    restoreScrollQuality()
                    
                default:
                    break
                }
            } else {
                // Horizontal 2-finger = pan
                handlePanMovement(gesture: gesture, translation: translation, velocity: velocity)
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                viewState.setInteractionState(isPinching: true)
                // CRITICAL: Sync lastZoom to current zoom to prevent jumps
                lastZoomForPinch = viewState.zoom
                
                print("🔄 Pinch START: lastZoom synced to \(String(format: "%.2f", lastZoomForPinch))x")
                
            case .changed:
                // Calculate new zoom based on synced lastZoom
                let newZoom = lastZoomForPinch * gesture.scale
                
                // Apply zoom with constraints - never below baseline
                let minZoom = viewState.baselineZoom
                let maxZoom = viewState.baselineZoom * 4.0
                viewState.zoom = max(minZoom, min(newZoom, maxZoom))
                
            case .ended, .cancelled:
                viewState.setInteractionState(isPinching: false)
                // Update lastZoom for next gesture
                lastZoomForPinch = viewState.zoom
                
                // Apply final constraints with animation
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    withAnimation(.spring()) {
                        self.viewState.setZoom(self.viewState.zoom, constrainToLimits: true)
                    }
                }
                
                print("🔄 Pinch END: lastZoom updated to \(String(format: "%.2f", lastZoomForPinch))x")
                
            default:
                break
            }
        }
        
        // MARK: - Slice Navigation
        
        private func handleSliceScroll(direction: Int, speed: CGFloat) {
            // Start quality reduction based on scroll speed
            startScrollQualityReduction(velocity: speed)
            
            // Calculate plane-aware sensitivity
            let sensitivity = config.planeScrollSensitivity[viewState.currentPlane] ?? 1.0
            
            // For educational use: always navigate one slice at a time
            let sliceChange = Int(Float(direction) * sensitivity).clamped(to: -1...1)
            
            if sliceChange != 0 {
                navigateSlices(by: sliceChange)
            }
        }
        
        private func navigateSlices(by amount: Int) {
            let currentSlice = coordinateSystem.getCurrentSliceIndex(for: viewState.currentPlane)
            let totalSlices = coordinateSystem.getMaxSlices(for: viewState.currentPlane)
            let newSlice = max(0, min(totalSlices - 1, currentSlice + amount))
            
            if newSlice != currentSlice {
                coordinateSystem.updateFromSliceScroll(plane: viewState.currentPlane, sliceIndex: newSlice)
            }
        }
        
        // MARK: - Quality Control
        
        private func startScrollQualityReduction(velocity: CGFloat) {
            // Determine quality level based on scroll velocity
            let newQuality: Int
            if velocity > 800 {
                newQuality = 4  // Quarter quality for very fast scrolling
            } else if velocity > 400 {
                newQuality = 2  // Half quality for medium speed
            } else {
                newQuality = 1  // Full quality for slow scrolling
            }
            
            // Update shared quality state
            if sharedState.renderQuality != newQuality {
                sharedState.renderQuality = newQuality
            }
        }
        
        private func restoreScrollQuality() {
            // Restore full quality after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                if self.sharedState.renderQuality != 1 {
                    self.sharedState.renderQuality = 1
                }
            }
        }
        
        // MARK: - Public Interface
        
        /// Reset view transformations
        func resetView() {
            viewState.resetView()
            lastZoomForPinch = viewState.zoom
        }
    }
}

// MARK: - Extensions

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
