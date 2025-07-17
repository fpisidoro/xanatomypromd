import UIKit
import Metal

// MARK: - Metal Debug Manager
// Systematic debugging of the Metal rendering pipeline
// Identifies pixel data interpretation and shader issues

class MetalDebugManager {
    
    static func debugMetalPipeline() {
        print("\n🔬 ===========================================")
        print("🔬 METAL PIPELINE DEBUG SESSION")
        print("🔬 ===========================================\n")
        
        debugPixelDataInterpretation()
        debugTextureCreation()
        debugShaderExecution()
        debugPixelValueMapping()
        debugImageOutput()
        
        print("\n🔬 ===========================================")
        print("🔬 Debug Session Complete")
        print("🔬 ===========================================\n")
    }
    
    // MARK: - Debug Pixel Data Interpretation
    
    static func debugPixelDataInterpretation() {
        print("🔍 DEBUG: Pixel Data Interpretation")
        
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
            
            print("   📊 Raw pixel data analysis:")
            print("      Dimensions: \(pixelData.columns) × \(pixelData.rows)")
            print("      Bits allocated: \(pixelData.bitsAllocated)")
            print("      Bits stored: \(pixelData.bitsStored)")
            print("      Pixel representation: \(pixelData.pixelRepresentation) (\(pixelData.pixelRepresentation == 0 ? "unsigned" : "signed"))")
            
            // Analyze raw pixel values
            let uint16Pixels = pixelData.toUInt16Array()
            let int16Pixels = pixelData.toInt16Array()
            
            print("   🔢 UInt16 interpretation:")
            print("      Min: \(uint16Pixels.min() ?? 0)")
            print("      Max: \(uint16Pixels.max() ?? 0)")
            print("      First 10 values: \(Array(uint16Pixels.prefix(10)))")
            
            print("   🔢 Int16 interpretation:")
            print("      Min: \(int16Pixels.min() ?? 0)")
            print("      Max: \(int16Pixels.max() ?? 0)")
            print("      First 10 values: \(Array(int16Pixels.prefix(10)))")
            
            // Check for typical CT value ranges
            let ctLikeValues = int16Pixels.filter { $0 >= -1000 && $0 <= 3000 }
            let percentage = Double(ctLikeValues.count) / Double(int16Pixels.count) * 100
            
            print("   🩻 CT-like values (-1000 to +3000 HU): \(String(format: "%.1f", percentage))%")
            
            if percentage < 50 {
                print("   ⚠️  WARNING: Most values outside typical CT range")
                print("   💡 This suggests pixel interpretation issues")
            }
            
        } catch {
            print("   ❌ Error: \(error)")
        }
        
        print("")
    }
    
    // MARK: - Debug Texture Creation
    
    static func debugTextureCreation() {
        print("🎨 DEBUG: Metal Texture Creation")
        
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
            
            let renderer = try MetalRenderer()
            let texture = try renderer.createTexture(from: pixelData)
            
            print("   ✅ Texture created successfully")
            print("   📊 Texture properties:")
            print("      Size: \(texture.width) × \(texture.height)")
            print("      Pixel format: \(texture.pixelFormat)")
            print("      Usage: \(texture.usage)")
            print("      Storage mode: \(texture.storageMode)")
            
            // Try to read back some texture data to verify upload
            let bytesPerRow = texture.width * 2  // 2 bytes per UInt16
            let totalBytes = texture.height * bytesPerRow
            var readbackData = Data(count: totalBytes)
            
            readbackData.withUnsafeMutableBytes { bytes in
                texture.getBytes(
                    bytes.baseAddress!,
                    bytesPerRow: bytesPerRow,
                    from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                    mipmapLevel: 0
                )
            }
            
            // Convert readback to UInt16 array for analysis
            let readbackPixels = readbackData.withUnsafeBytes { bytes in
                Array(bytes.bindMemory(to: UInt16.self))
            }
            
            print("   📖 Readback verification:")
            print("      First 10 readback values: \(Array(readbackPixels.prefix(10)))")
            
            // Compare with original
            let originalPixels = pixelData.toUInt16Array()
            let matches = zip(originalPixels.prefix(10), readbackPixels.prefix(10)).allSatisfy { $0 == $1 }
            print("      Upload/readback match: \(matches ? "✅" : "❌")")
            
        } catch {
            print("   ❌ Error: \(error)")
        }
        
        print("")
    }
    
    // MARK: - Debug Shader Execution
    
    static func debugShaderExecution() {
        print("🖥️  DEBUG: Metal Shader Execution")
        
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
            
            let renderer = try MetalRenderer()
            let inputTexture = try renderer.createTexture(from: pixelData)
            
            // Test with extreme windowing to see if shader is working
            let testConfigs = [
                ("Very wide", 0.0, 65536.0),    // Show everything
                ("Very narrow", 13666.0, 100.0), // Around average value
                ("Bone preset", 500.0, 2000.0)   // Standard bone
            ]
            
            for (name, center, width) in testConfigs {
                print("   🧪 Testing \(name) (C=\(center), W=\(width)):")
                
                let config = MetalRenderer.RenderConfig(
                    windowCenter: Float(center),
                    windowWidth: Float(width)
                )
                
                let expectation = TestExpectation()
                var testResult: String = "Unknown"
                
                renderer.renderCTImage(
                    inputTexture: inputTexture,
                    config: config
                ) { windowedTexture in
                    if let texture = windowedTexture {
                        // Read back a small sample to verify shader output
                        let sampleSize = 4 * 4 * 4  // 4x4 pixels, 4 bytes each (RGBA)
                        var sampleData = Data(count: sampleSize)
                        
                        sampleData.withUnsafeMutableBytes { bytes in
                            texture.getBytes(
                                bytes.baseAddress!,
                                bytesPerRow: 4 * 4,  // 4 pixels * 4 bytes
                                from: MTLRegionMake2D(0, 0, 4, 4),
                                mipmapLevel: 0
                            )
                        }
                        
                        let rgbaValues = sampleData.withUnsafeBytes { bytes in
                            Array(bytes.bindMemory(to: UInt8.self))
                        }
                        
                        // Check if all values are the same (would indicate shader problem)
                        let uniqueValues = Set(rgbaValues)
                        
                        if uniqueValues.count == 1 {
                            testResult = "❌ All pixels same value (\(uniqueValues.first!))"
                        } else if uniqueValues.count < 5 {
                            testResult = "⚠️  Very few unique values (\(uniqueValues.count))"
                        } else {
                            testResult = "✅ Good variation (\(uniqueValues.count) unique values)"
                        }
                        
                        testResult += " - Sample: \(Array(rgbaValues.prefix(8)))"
                        
                    } else {
                        testResult = "❌ Shader execution failed"
                    }
                    
                    expectation.fulfill()
                }
                
                expectation.wait()
                print("      \(testResult)")
            }
            
        } catch {
            print("   ❌ Error: \(error)")
        }
        
        print("")
    }
    
    // MARK: - Debug Pixel Value Mapping
    
    static func debugPixelValueMapping() {
        print("🗺️  DEBUG: Pixel Value Mapping")
        
        // Test our conversion from raw pixel values to shader input
        let testPixels: [UInt16] = [0, 1000, 13666, 32768, 50000, 65535]
        
        print("   🔄 Raw pixel → CT value conversion:")
        for pixel in testPixels {
            let ctValue = Float(pixel) - 32768.0  // This is what our shader does
            let signedValue = Int16(bitPattern: pixel)
            
            print("      Raw \(pixel) → CT \(ctValue) (signed: \(signedValue))")
        }
        
        print("   🪟 Windowing calculation test:")
        let windowCenter: Float = 500.0
        let windowWidth: Float = 2000.0
        let windowMin = windowCenter - (windowWidth * 0.5)
        let windowMax = windowCenter + (windowWidth * 0.5)
        
        print("      Window: Center=\(windowCenter), Width=\(windowWidth)")
        print("      Range: \(windowMin) to \(windowMax)")
        
        for pixel in testPixels {
            let ctValue = Float(pixel) - 32768.0
            let normalizedValue = (ctValue - windowMin) / windowWidth
            let clampedValue = max(0.0, min(1.0, normalizedValue))
            let displayValue = UInt8(clampedValue * 255.0)
            
            print("      \(pixel) → \(ctValue) → \(String(format: "%.3f", normalizedValue)) → \(displayValue)")
        }
        
        print("")
    }
    
    // MARK: - Debug Image Output
    
    static func debugImageOutput() {
        print("🖼️  DEBUG: Final Image Output")
        
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
            
            let renderer = try MetalRenderer()
            let inputTexture = try renderer.createTexture(from: pixelData)
            
            // Create a very wide window to show all data
            let config = MetalRenderer.RenderConfig(
                windowCenter: 0.0,
                windowWidth: 65536.0
            )
            
            let expectation = TestExpectation()
            
            renderer.renderCTImage(
                inputTexture: inputTexture,
                config: config
            ) { windowedTexture in
                guard let texture = windowedTexture else {
                    print("   ❌ Windowing failed")
                    expectation.fulfill()
                    return
                }
                
                guard let uiImage = renderer.textureToUIImage(texture) else {
                    print("   ❌ UIImage conversion failed")
                    expectation.fulfill()
                    return
                }
                
                print("   ✅ UIImage created successfully")
                print("   📊 Image properties:")
                print("      Size: \(uiImage.size)")
                print("      Scale: \(uiImage.scale)")
                
                // Analyze image data
                guard let cgImage = uiImage.cgImage else {
                    print("   ❌ No CGImage available")
                    expectation.fulfill()
                    return
                }
                
                print("   🔍 CGImage analysis:")
                print("      Dimensions: \(cgImage.width) × \(cgImage.height)")
                print("      Bits per component: \(cgImage.bitsPerComponent)")
                print("      Bits per pixel: \(cgImage.bitsPerPixel)")
                print("      Bytes per row: \(cgImage.bytesPerRow)")
                print("      Color space: \(cgImage.colorSpace?.name as String? ?? "Unknown")")
                
                // Sample a few pixels to see actual values
                if let dataProvider = cgImage.dataProvider,
                   let pixelData = dataProvider.data,
                   let pixelBytes = CFDataGetBytePtr(pixelData) {
                    
                    print("   🎨 Sample pixel values (RGBA):")
                    for i in 0..<min(5, cgImage.width * cgImage.height) {
                        let offset = i * 4
                        let r = pixelBytes[offset]
                        let g = pixelBytes[offset + 1]
                        let b = pixelBytes[offset + 2]
                        let a = pixelBytes[offset + 3]
                        print("      Pixel \(i): R=\(r), G=\(g), B=\(b), A=\(a)")
                    }
                    
                    // Check if image is all black, all white, or has variation
                    let sampleCount = min(1000, cgImage.width * cgImage.height)
                    var histogram: [UInt8: Int] = [:]
                    
                    for i in 0..<sampleCount {
                        let grayValue = pixelBytes[i * 4]  // R channel (should be same as G, B for grayscale)
                        histogram[grayValue, default: 0] += 1
                    }
                    
                    let uniqueValues = histogram.keys.count
                    let mostCommon = histogram.max { $0.value < $1.value }
                    
                    print("   📊 Histogram analysis:")
                    print("      Unique gray values: \(uniqueValues) / 256")
                    print("      Most common value: \(mostCommon?.key ?? 0) (\(mostCommon?.value ?? 0) pixels)")
                    
                    if uniqueValues == 1 {
                        print("   ❌ Image is solid color - rendering problem!")
                    } else if uniqueValues < 10 {
                        print("   ⚠️  Very low variation - possible windowing issue")
                    } else {
                        print("   ✅ Good variation - image likely correct")
                    }
                }
                
                expectation.fulfill()
            }
            
            expectation.wait()
            
        } catch {
            print("   ❌ Error: \(error)")
        }
        
        print("")
    }
    
    // MARK: - Test Expectation Helper
    
    private class TestExpectation {
        private var fulfilled = false
        private let semaphore = DispatchSemaphore(value: 0)
        
        func fulfill() {
            if !fulfilled {
                fulfilled = true
                semaphore.signal()
            }
        }
        
        func wait(timeout: TimeInterval = 10.0) {
            _ = semaphore.wait(timeout: .now() + timeout)
        }
    }
}
