import UIKit
import Metal

// MARK: - Metal Medical Test Manager
// Tests MetalMedical rendering pipeline with your existing DICOM parser
// Uses UIKit for simple texture-to-image display without SwiftUI complexity

class MetalTestManager {
    
    // MARK: - Test Configuration
    
    private static var metalRenderer: MetalRenderer?
    private static var textureCache: TextureCache?
    
    // MARK: - Main Test Runner
    
    static func runMetalTests() {
        print("\n⚡ ===========================================")
        print("⚡ MetalMedical Test Suite")
        print("⚡ ===========================================\n")
        
        testMetalAvailability()
        testRendererInitialization()
        testTextureCreation()
        testCTWindowing()
        testTextureCache()
        testWindowingPresets()
        testUIImageConversion()
        testPerformanceBenchmark()
        
        print("\n✅ ===========================================")
        print("✅ MetalMedical Tests Complete!")
        print("✅ ===========================================\n")
    }
    
    // MARK: - Individual Tests
    
    static func testMetalAvailability() {
        print("🖥️  TEST: Metal Availability")
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("   ❌ Metal not available on this device")
            return
        }
        
        print("   ✅ Metal device available")
        print("   🏷️  Device name: \(device.name)")
        print("   🧠 Max threads per group: \(device.maxThreadsPerThreadgroup)")
        print("   💾 Max buffer size: \(device.maxBufferLength / 1024 / 1024) MB")
        print("   ⚡ GPU family support: \(device.supportsFamily(.apple4) ? "Apple GPU Family 4+" : "Earlier GPU")")
        print("")
    }
    
    static func testRendererInitialization() {
        print("🔧 TEST: Metal Renderer Initialization")
        
        do {
            let renderer = try MetalRenderer()
            metalRenderer = renderer
            
            print("   ✅ MetalRenderer initialized successfully")
            print("   📊 Performance info:")
            print(renderer.getPerformanceInfo().components(separatedBy: "\n").map { "      \($0)" }.joined(separator: "\n"))
            
        } catch {
            print("   ❌ MetalRenderer initialization failed: \(error)")
            return
        }
        
        print("")
    }
    
    static func testTextureCreation() {
        print("🎨 TEST: DICOM to Metal Texture Conversion")
        
        guard let renderer = metalRenderer else {
            print("   ❌ MetalRenderer not available")
            return
        }
        
        // Get first DICOM file for testing
        guard let firstFile = DICOMTestManager.getDICOMFiles().first else {
            print("   ❌ No DICOM files available")
            return
        }
        
        do {
            print("   📄 Testing with: \(firstFile.lastPathComponent)")
            
            let data = try Data(contentsOf: firstFile)
            let dataset = try DICOMParser.parse(data)
            
            guard let pixelData = DICOMParser.extractPixelData(from: dataset) else {
                print("   ❌ Could not extract pixel data")
                return
            }
            
            print("   📊 Pixel data: \(pixelData.columns)×\(pixelData.rows), \(pixelData.bitsAllocated)-bit")
            
            let texture = try renderer.createTexture(from: pixelData)
            
            print("   ✅ Metal texture created successfully")
            print("   🖼️  Texture size: \(texture.width)×\(texture.height)")
            print("   🎨 Pixel format: \(texture.pixelFormat)")
            print("   💾 Memory usage: \(texture.width * texture.height * 2) bytes")
            
        } catch {
            print("   ❌ Texture creation failed: \(error)")
        }
        
        print("")
    }
    
    static func testCTWindowing() {
        print("🪟 TEST: CT Windowing on GPU")
        
        guard let renderer = metalRenderer else {
            print("   ❌ MetalRenderer not available")
            return
        }
        
        guard let firstFile = DICOMTestManager.getDICOMFiles().first else {
            print("   ❌ No DICOM files available")
            return
        }
        
        do {
            let data = try Data(contentsOf: firstFile)
            let dataset = try DICOMParser.parse(data)
            
            guard let pixelData = DICOMParser.extractPixelData(from: dataset) else {
                print("   ❌ Could not extract pixel data")
                return
            }
            
            let inputTexture = try renderer.createTexture(from: pixelData)
            print("   ✅ Input texture created")
            
            // Test bone windowing
            let boneConfig = MetalRenderer.RenderConfig(
                windowCenter: Float(CTWindowPresets.bone.center),
                windowWidth: Float(CTWindowPresets.bone.width)
            )
            
            let expectation = TestExpectation()
            
            renderer.renderCTImage(
                inputTexture: inputTexture,
                config: boneConfig
            ) { windowedTexture in
                if let texture = windowedTexture {
                    print("   ✅ Bone windowing successful")
                    print("   🖼️  Windowed texture: \(texture.width)×\(texture.height)")
                    print("   🎨 Output format: \(texture.pixelFormat)")
                } else {
                    print("   ❌ Bone windowing failed")
                }
                expectation.fulfill()
            }
            
            expectation.wait()
            
        } catch {
            print("   ❌ CT windowing test failed: \(error)")
        }
        
        print("")
    }
    
    static func testTextureCache() {
        print("💾 TEST: Simple Texture Cache")
        
        guard let renderer = metalRenderer,
              let device = MTLCreateSystemDefaultDevice() else {
            print("   ❌ Metal components not available")
            return
        }
        
        let cache = SimpleTextureCache(device: device, maxCachedTextures: 5)
        
        print("   ✅ SimpleTextureCache initialized")
        
        // Test caching with multiple files
        let dicomFiles = DICOMTestManager.getDICOMFiles()
        let testFiles = Array(dicomFiles.prefix(3))
        
        var completedTests = 0
        let totalTests = testFiles.count
        
        for (index, file) in testFiles.enumerated() {
            cache.getTexture(
                for: index,
                pixelDataProvider: {
                    do {
                        let data = try Data(contentsOf: file)
                        let dataset = try DICOMParser.parse(data)
                        return DICOMParser.extractPixelData(from: dataset)
                    } catch {
                        print("   ❌ Error loading slice \(index): \(error)")
                        return nil
                    }
                },
                metalRenderer: renderer
            ) { texture in
                if texture != nil {
                    print("   ✅ Cached texture \(index)")
                } else {
                    print("   ❌ Failed to cache texture \(index)")
                }
                
                completedTests += 1
                if completedTests == totalTests {
                    // Print cache stats after all tests
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        print("   \(cache.getStats())")
                    }
                }
            }
        }
        
        print("")
    }
    
    static func testWindowingPresets() {
        print("🎛️  TEST: Standard CT Windowing Presets")
        
        guard let renderer = metalRenderer else {
            print("   ❌ MetalRenderer not available")
            return
        }
        
        guard let firstFile = DICOMTestManager.getDICOMFiles().first else {
            print("   ❌ No DICOM files available")
            return
        }
        
        do {
            let data = try Data(contentsOf: firstFile)
            let dataset = try DICOMParser.parse(data)
            
            guard let pixelData = DICOMParser.extractPixelData(from: dataset) else {
                print("   ❌ Could not extract pixel data")
                return
            }
            
            let inputTexture = try renderer.createTexture(from: pixelData)
            
            let presets = [
                CTWindowPresets.bone,
                CTWindowPresets.lung,
                CTWindowPresets.softTissue
            ]
            
            var completedPresets = 0
            
            for preset in presets {
                renderer.renderWithPreset(
                    inputTexture: inputTexture,
                    preset: preset
                ) { windowedTexture in
                    if windowedTexture != nil {
                        print("   ✅ \(preset.name) preset: C=\(Int(preset.center)), W=\(Int(preset.width))")
                    } else {
                        print("   ❌ \(preset.name) preset failed")
                    }
                    
                    completedPresets += 1
                }
            }
            
            // Wait a moment for async operations
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("   📊 Tested \(completedPresets) presets")
            }
            
        } catch {
            print("   ❌ Preset testing failed: \(error)")
        }
        
        print("")
    }
    
    static func testUIImageConversion() {
        print("🖼️  TEST: Metal Texture to UIImage Conversion")
        
        guard let renderer = metalRenderer else {
            print("   ❌ MetalRenderer not available")
            return
        }
        
        guard let firstFile = DICOMTestManager.getDICOMFiles().first else {
            print("   ❌ No DICOM files available")
            return
        }
        
        do {
            let data = try Data(contentsOf: firstFile)
            let dataset = try DICOMParser.parse(data)
            
            guard let pixelData = DICOMParser.extractPixelData(from: dataset) else {
                print("   ❌ Could not extract pixel data")
                return
            }
            
            let inputTexture = try renderer.createTexture(from: pixelData)
            
            // Apply soft tissue windowing
            let config = MetalRenderer.RenderConfig(
                windowCenter: Float(CTWindowPresets.softTissue.center),
                windowWidth: Float(CTWindowPresets.softTissue.width)
            )
            
            renderer.renderCTImage(
                inputTexture: inputTexture,
                config: config
            ) { windowedTexture in
                guard let texture = windowedTexture else {
                    print("   ❌ Windowing failed")
                    return
                }
                
                if let uiImage = renderer.textureToUIImage(texture) {
                    print("   ✅ UIImage conversion successful")
                    print("   📐 Image size: \(uiImage.size.width)×\(uiImage.size.height)")
                    print("   🎨 Scale: \(uiImage.scale)")
                    
                    // Save to photo library for visual verification (optional)
                    // UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                    // print("   💾 Saved to Photos app for verification")
                    
                } else {
                    print("   ❌ UIImage conversion failed")
                }
            }
            
        } catch {
            print("   ❌ UIImage test failed: \(error)")
        }
        
        print("")
    }
    
    static func testPerformanceBenchmark() {
        print("⚡ TEST: Performance Benchmark")
        
        guard let renderer = metalRenderer else {
            print("   ❌ MetalRenderer not available")
            return
        }
        
        guard let firstFile = DICOMTestManager.getDICOMFiles().first else {
            print("   ❌ No DICOM files available")
            return
        }
        
        do {
            let data = try Data(contentsOf: firstFile)
            let dataset = try DICOMParser.parse(data)
            
            guard let pixelData = DICOMParser.extractPixelData(from: dataset) else {
                print("   ❌ Could not extract pixel data")
                return
            }
            
            // Benchmark texture creation
            let textureStart = CFAbsoluteTimeGetCurrent()
            let inputTexture = try renderer.createTexture(from: pixelData)
            let textureTime = CFAbsoluteTimeGetCurrent() - textureStart
            
            print("   ⏱️  Texture creation: \(String(format: "%.2f", textureTime * 1000))ms")
            
            // Benchmark windowing
            let config = MetalRenderer.RenderConfig(
                windowCenter: Float(CTWindowPresets.bone.center),
                windowWidth: Float(CTWindowPresets.bone.width)
            )
            
            let windowingStart = CFAbsoluteTimeGetCurrent()
            
            renderer.renderCTImage(
                inputTexture: inputTexture,
                config: config
            ) { windowedTexture in
                let windowingTime = CFAbsoluteTimeGetCurrent() - windowingStart
                
                if windowedTexture != nil {
                    print("   ⏱️  CT windowing: \(String(format: "%.2f", windowingTime * 1000))ms")
                    print("   🎯 Target: <16ms for 60 FPS")
                    
                    if windowingTime < 0.016 {
                        print("   ✅ Performance excellent for real-time rendering")
                    } else if windowingTime < 0.033 {
                        print("   🟡 Performance good for 30 FPS")
                    } else {
                        print("   ⚠️  Performance may impact real-time interaction")
                    }
                } else {
                    print("   ❌ Windowing benchmark failed")
                }
            }
            
        } catch {
            print("   ❌ Performance benchmark failed: \(error)")
        }
        
        print("")
    }
    
    // MARK: - Utility for Testing Async Operations
    
    private class TestExpectation {
        private var fulfilled = false
        private let semaphore = DispatchSemaphore(value: 0)
        
        func fulfill() {
            if !fulfilled {
                fulfilled = true
                semaphore.signal()
            }
        }
        
        func wait(timeout: TimeInterval = 5.0) {
            _ = semaphore.wait(timeout: .now() + timeout)
        }
    }
    
    // MARK: - Quick Visual Test
    
    /// Create a simple UIImageView to display rendered result
    static func createVisualTest(in viewController: UIViewController) {
        print("\n👁️  Creating visual test in view controller...")
        
        guard let renderer = metalRenderer else {
            print("❌ MetalRenderer not available for visual test")
            return
        }
        
        guard let firstFile = DICOMTestManager.getDICOMFiles().first else {
            print("❌ No DICOM files for visual test")
            return
        }
        
        do {
            let data = try Data(contentsOf: firstFile)
            let dataset = try DICOMParser.parse(data)
            
            guard let pixelData = DICOMParser.extractPixelData(from: dataset) else {
                print("❌ Could not extract pixel data for visual test")
                return
            }
            
            let inputTexture = try renderer.createTexture(from: pixelData)
            
            // Render with bone windowing
            renderer.renderWithPreset(
                inputTexture: inputTexture,
                preset: CTWindowPresets.bone
            ) { windowedTexture in
                guard let texture = windowedTexture,
                      let uiImage = renderer.textureToUIImage(texture) else {
                    print("❌ Visual test rendering failed")
                    return
                }
                
                // Create UIImageView
                let imageView = UIImageView(image: uiImage)
                imageView.contentMode = .scaleAspectFit
                imageView.backgroundColor = .black
                
                // Add to view controller
                viewController.view.addSubview(imageView)
                imageView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    imageView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
                    imageView.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor),
                    imageView.widthAnchor.constraint(equalTo: viewController.view.widthAnchor, multiplier: 0.8),
                    imageView.heightAnchor.constraint(equalTo: viewController.view.heightAnchor, multiplier: 0.8)
                ])
                
                print("✅ Visual test complete - CT image displayed with bone windowing")
            }
            
        } catch {
            print("❌ Visual test failed: \(error)")
        }
    }
}
