//
//  SceneDelegate.swift
//  xanatomypromd
//
//  Created by fpisidoro on 7/16/25.
//

import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // Configure for medical imaging app
        setupMedicalImagingEnvironment(windowScene)
        
        // Choose integration approach
        #if PURE_SWIFTUI
        setupPureSwiftUI(windowScene)
        #else
        setupHybridApproach(windowScene)
        #endif
    }
    
    private func setupMedicalImagingEnvironment(_ windowScene: UIWindowScene) {
        // Configure window for medical imaging
        window = UIWindow(windowScene: windowScene)
        
        // Force dark mode for medical imaging
        window?.overrideUserInterfaceStyle = .dark
        
        // Configure for medical app behavior
        UIApplication.shared.isIdleTimerDisabled = true  // Prevent sleep during medical review
        
        print("🏥 Medical imaging environment configured")
    }
    
    private func setupPureSwiftUI(_ windowScene: UIWindowScene) {
        // Pure SwiftUI approach - using new modular StandaloneMPRView architecture
        let contentView = XAnatomyProV2MainView()  // Using V2 with StandaloneMPRView
            .preferredColorScheme(.dark)
            .statusBarHidden(true)
        
        window?.rootViewController = UIHostingController(rootView: contentView)
        window?.makeKeyAndVisible()
        
        print("📱 Clean layered architecture initialized")
    }
    
    private func setupHybridApproach(_ windowScene: UIWindowScene) {
        // Hybrid approach - works with existing UIKit structure
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateInitialViewController()
        
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()
        
        print("🔄 Hybrid UIKit/SwiftUI integration initialized")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Clean up resources when scene disconnects
        print("🧹 Scene disconnected - cleaning up resources")
        
        // Clear any cached textures or DICOM data
        NotificationCenter.default.post(name: .init("SceneDisconnected"), object: nil)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Resume any background tasks when scene becomes active
        print("▶️ Scene became active")
        
        // Re-enable rendering if paused
        NotificationCenter.default.post(name: .init("SceneActive"), object: nil)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Pause rendering when scene will resign active
        print("⏸️ Scene will resign active")
        
        // Pause expensive operations
        NotificationCenter.default.post(name: .init("SceneInactive"), object: nil)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Resume operations when entering foreground
        print("🌅 Scene entering foreground")
        
        // Resume DICOM processing
        NotificationCenter.default.post(name: .init("EnterForeground"), object: nil)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Save data and pause operations when entering background
        print("🌙 Scene entering background")
        
        // Pause DICOM processing and clear memory
        NotificationCenter.default.post(name: .init("EnterBackground"), object: nil)
        
        // Clear texture cache to free memory
        clearMemoryCache()
    }
    
    private func clearMemoryCache() {
        // Clear memory-intensive caches when entering background
        print("🧹 Clearing memory cache for background")
        
        // Notify view models to clear caches
        NotificationCenter.default.post(name: .init("ClearMemoryCache"), object: nil)
    }
}

// MARK: - Medical Imaging App Configuration

extension SceneDelegate {
    
    /// Configure app behavior specific to medical imaging
    private func configureMedicalAppBehavior() {
        // Prevent screen dimming during medical review
        UIApplication.shared.isIdleTimerDisabled = true
        
        
        // Configure memory management for large medical datasets
        setupMemoryManagement()
    }
    
    private func setupMemoryManagement() {
        // Monitor memory usage for large DICOM datasets
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("⚠️ Memory warning - clearing DICOM caches")
            self.clearMemoryCache()
        }
    }
}

// MARK: - SwiftUI Preview Configuration

#if DEBUG
extension SceneDelegate {
    
    /// Configure scene for SwiftUI previews
    static func configureForPreviews() {
        // This can be called from SwiftUI previews to set up proper environment
        UIApplication.shared.isIdleTimerDisabled = false  // Allow sleep in previews
    }
}
#endif

// MARK: - Orientation Support

extension SceneDelegate {
    
    func windowScene(_ windowScene: UIWindowScene, didUpdate previousCoordinateSpace: UICoordinateSpace, interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation, traitCollection previousTraitCollection: UITraitCollection) {
        
        // Handle orientation changes for medical imaging
        let currentOrientation = windowScene.interfaceOrientation
        print("📱 Interface orientation changed to: \(currentOrientation.rawValue)")
        
        // Notify SwiftUI views about orientation change
        NotificationCenter.default.post(
            name: .init("OrientationChanged"),
            object: currentOrientation
        )
    }
}

// MARK: - App State Management

extension SceneDelegate {
    
    /// Handle app state changes for medical imaging workflow
    private func handleAppStateChange(active: Bool) {
        if active {
            // Resume expensive operations
            resumeMedicalImagingTasks()
        } else {
            // Pause expensive operations
            pauseMedicalImagingTasks()
        }
    }
    
    private func resumeMedicalImagingTasks() {
        // Resume DICOM processing
        // Resume Metal rendering
        // Resume texture caching
        print("▶️ Resuming medical imaging tasks")
    }
    
    private func pauseMedicalImagingTasks() {
        // Pause DICOM processing
        // Pause Metal rendering
        // Clear texture cache
        print("⏸️ Pausing medical imaging tasks")
    }
}
