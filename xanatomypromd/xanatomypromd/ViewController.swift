//
//  ViewController.swift
//  xanatomypromd
//
//  Created by fpisidoro on 7/16/25.
//

import UIKit
import SwiftUI

class ViewController: UIViewController {
    
    private var hostingController: UIHostingController<DICOMViewerView>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up the view for medical imaging
        setupForMedicalImaging()
        
        // Initialize SwiftUI DICOM Viewer
        setupDICOMViewer()
        
        // Optional: Run quick tests in debug mode
        #if DEBUG
        runDevelopmentTests()
        #endif
    }
    
    private func setupForMedicalImaging() {
        // Configure view for medical imaging
        view.backgroundColor = .black
        
        // Force dark mode for medical imaging
        overrideUserInterfaceStyle = .dark
        
        // Hide status bar for full-screen medical viewing
        setNeedsStatusBarAppearanceUpdate()
    }
    
    private func setupDICOMViewer() {
        // Create SwiftUI DICOM Viewer
        let dicomViewer = DICOMViewerView()
        let hostingController = UIHostingController(rootView: dicomViewer)
        
        // Store reference
        self.hostingController = hostingController
        
        // Add SwiftUI view as child
        addChild(hostingController)
        view.addSubview(hostingController.view)
        
        // Set up constraints for full-screen display
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        hostingController.didMove(toParent: self)
        
        print("✅ SwiftUI DICOM Viewer initialized successfully")
    }
    
    override var prefersStatusBarHidden: Bool {
        return true  // Hide status bar for medical imaging
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        // Support all orientations for medical imaging
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        // Handle orientation changes gracefully
        coordinator.animate(alongsideTransition: { _ in
            // Animation block - SwiftUI handles layout automatically
        }, completion: { _ in
            // Completion block
            print("📱 Interface orientation changed to \(size)")
        })
    }
    
    // MARK: - Development Testing
    
    #if DEBUG
    private func runDevelopmentTests() {
        // Run quick tests in background to avoid blocking UI
        DispatchQueue.global(qos: .background).async {
            print("\n🧪 Running development tests...")
            
            // Test DICOM file discovery
            let dicomFiles = self.getDICOMFiles()
            print("📁 Found \(dicomFiles.count) DICOM files")
            
            // Test first file parsing
            if let firstFile = dicomFiles.first {
                do {
                    let data = try Data(contentsOf: firstFile)
                    let dataset = try DICOMParser.parse(data)
                    print("✅ DICOM parsing successful")
                    
                    if let pixelData = DICOMParser.extractPixelData(from: dataset) {
                        print("✅ Pixel data extraction successful: \(pixelData.columns)×\(pixelData.rows)")
                    }
                } catch {
                    print("❌ DICOM parsing failed: \(error)")
                }
            }
            
            // Test Metal device
            if let device = MTLCreateSystemDefaultDevice() {
                print("✅ Metal device available: \(device.name)")
            } else {
                print("❌ Metal device not available")
            }
            
            print("🧪 Development tests complete\n")
        }
    }
    
    private func getDICOMFiles() -> [URL] {
        guard let bundlePath = Bundle.main.resourcePath else { return [] }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: bundlePath),
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            return fileURLs.filter {
                $0.pathExtension.lowercased() == "dcm" ||
                $0.lastPathComponent.contains("2.16.840.1.114362")
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
        } catch {
            print("Error reading DICOM files: \(error)")
            return []
        }
    }
    #endif
    
    // MARK: - Memory Management
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        
        // Clear any cached textures or DICOM data
        print("⚠️ Memory warning received - clearing caches")
        
        // The SwiftUI view model will handle its own memory management
        // but we can send a notification for cache clearing
        NotificationCenter.default.post(name: .init("MemoryWarning"), object: nil)
    }
    
    deinit {
        print("🗑️ ViewController deallocated")
    }
}

// MARK: - Alternative Pure SwiftUI Integration

/*
 If you prefer to use pure SwiftUI without UIKit integration,
 you can modify SceneDelegate.swift instead:
 
 func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
     guard let windowScene = (scene as? UIWindowScene) else { return }
     
     // Create SwiftUI root view
     let contentView = DICOMViewerView()
     
     // Create window with SwiftUI hosting
     window = UIWindow(windowScene: windowScene)
     window?.rootViewController = UIHostingController(rootView: contentView)
     window?.makeKeyAndVisible()
     
     // Force dark mode for medical imaging
     window?.overrideUserInterfaceStyle = .dark
 }
 */
