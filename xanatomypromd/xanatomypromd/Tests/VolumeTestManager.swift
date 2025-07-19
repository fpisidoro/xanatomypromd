import Foundation
import Metal
import simd

// MARK: - 3D Volume Test Manager
// Comprehensive testing for VolumeData and MetalVolumeRenderer
// Validates MPR functionality and spatial reconstruction

class VolumeTestManager {
    
    // MARK: - Test Configuration
    
    private static var volumeData: VolumeData?
    private static var volumeRenderer: MetalVolumeRenderer?
    
    // MARK: - Main Test Runner
    
    static func runVolumeTests() {
        print("\n🧊 ===========================================")
        print("🧊 3D Volume & MPR Test Suite")
        print("🧊 ===========================================\n")
        
        testVolumeDataCreation()
        testSpatialCoordinates()
        testSliceExtraction()
        testMetalVolumeRenderer()
        testMPRGeneration()
        testVolumeStatistics()
        testMemoryPerformance()
        
        print("\n✅ ===========================================")
        print("✅ 3D Volume Tests Complete!")
        print("✅ ===========================================\n")
    }
    
    // MARK: - Individual Tests
    
    static func testVolumeDataCreation() {
        print("🧊 TEST: Volume Data Creation from DICOM Series")
        
        let dicomFiles = DICOMTestManager.getDICOMFiles()
        guard dicomFiles.count > 0 else {
            print("   ❌ No DICOM files available")
            return
        }
        
        print("   📁 Loading \(dicomFiles.count) DICOM files...")
        
        do {
            // Parse all DICOM datasets
            var datasets: [(DICOMDataset, Int)] = []
            
            for (index, fileURL) in dicomFiles.enumerated() {
                let data = try Data(contentsOf: fileURL)
                let dataset = try DICOMParser.parse(data)
                datasets.append((dataset, index))
                
                if index < 3 {
                    print("   📄 File \(index): \(fileURL.lastPathComponent)")
                }
            }
            
            // Create volume
            let startTime = CFAbsoluteTimeGetCurrent()
            let volume = try VolumeData(from: datasets)
            let loadTime = CFAbsoluteTimeGetCurrent() - startTime
            
            volumeData = volume
            
            print("   ✅ Volume created successfully")
            print("   ⏱️  Load time: \(String(format: "%.2f", loadTime * 1000))ms")
            
            let stats = volume.getStatistics()
            print("   📊 Volume statistics:")
            print("      📐 Dimensions: \(stats.dimensions)")
            print("      📏 Spacing: \(String(format: "%.2f", stats.spacing.x))×\(String(format: "%.2f", stats.spacing.y))×\(String(format: "%.2f", stats.spacing.z)) mm")
            print("      📊 Value range: \(stats.minValue) to \(stats.maxValue)")
            print("      💾 Memory: \(String(format: "%.1f", Double(stats.memoryUsage) / 1024.0 / 1024.0)) MB")
            
        } catch {
            print("   ❌ Volume creation failed: \(error)")
        }
        
        print("")
    }
    
    static func testSpatialCoordinates() {
        print("🗺️  TEST: Spatial Coordinate System")
        
        guard let volume = volumeData else {
            print("   ❌ No volume data available")
            return
        }
        
        print("   🧭 Testing coordinate transformations...")
        
        // Test corner coordinates
        let testPoints = [
            ("Origin", SIMD3<Float>(0, 0, 0)),
            ("Center", SIMD3<Float>(Float(volume.dimensions.x/2), Float(volume.dimensions.y/2), Float(volume.dimensions.z/2))),
            ("Max Corner", SIMD3<Float>(Float(volume.dimensions.x-1), Float(volume.dimensions.y-1), Float(volume.dimensions.z-1)))
        ]
        
        for (name, voxelCoord) in testPoints {
            let patientCoord = volume.voxelToPatient(voxelCoord)
            let backToVoxel = volume.patientToVoxel(patientCoord)
            
            let error = simd_length(voxelCoord - backToVoxel)
            
            print("   📍 \(name):")
            print("      Voxel: \(voxelCoord)")
            print("      Patient: \(String(format: "(%.1f, %.1f, %.1f)", patientCoord.x, patientCoord.y, patientCoord.z))")
            print("      Round-trip error: \(String(format: "%.6f", error))")
        }
        
        // Test anatomical directions
        let directions = volume.getAnatomicalDirections()
        print("   🧭 Anatomical directions:")
        print("      Right: \(directions.right)")
        print("      Anterior: \(directions.anterior)")
        print("      Superior: \(directions.superior)")
        
        print("")
    }
    
    static func testSliceExtraction() {
        print("🔪 TEST: CPU Slice Extraction")
        
        guard let volume = volumeData else {
            print("   ❌ No volume data available")
            return
        }
        
        let testSlices = [
            ("Axial Center", MPRPlane.axial, Float(volume.dimensions.z / 2)),
            ("Sagittal Center", MPRPlane.sagittal, Float(volume.dimensions.x / 2)),
            ("Coronal Center", MPRPlane.coronal, Float(volume.dimensions.y / 2))
        ]
        
        for (name, plane, position) in testSlices {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            let sliceData: [Int16]
            let expectedCount: Int
            
            switch plane {
            case .axial:
                sliceData = volume.extractAxialSlice(atZ: position)
                expectedCount = volume.dimensions.x * volume.dimensions.y
            case .sagittal:
                sliceData = volume.extractSagittalSlice(atX: position)
                expectedCount = volume.dimensions.y * volume.dimensions.z
            case .coronal:
                sliceData = volume.extractCoronalSlice(atY: position)
                expectedCount = volume.dimensions.x * volume.dimensions.z
            }
            
            let extractTime = CFAbsoluteTimeGetCurrent() - startTime
            
            print("   🔪 \(name):")
            print("      Expected pixels: \(expectedCount)")
            print("      Extracted pixels: \(sliceData.count)")
            print("      Extraction time: \(String(format: "%.2f", extractTime * 1000))ms")
            
            if !sliceData.isEmpty {
                let minValue = sliceData.min() ?? 0
                let maxValue = sliceData.max() ?? 0
                let avgValue = sliceData.reduce(0) { $0 + Int($1) } / sliceData.count
                
                print("      Value range: \(minValue) to \(maxValue) (avg: \(avgValue))")
                
                // Test for non-zero data
                let nonZeroCount = sliceData.filter { $0 != 0 }.count
                let nonZeroPercent = Double(nonZeroCount) / Double(sliceData.count) * 100
                print("      Non-zero pixels: \(String(format: "%.1f", nonZeroPercent))%")
                
                if nonZeroPercent > 10 {
                    print("      ✅ Slice contains meaningful data")
                } else {
                    print("      ⚠️  Slice appears mostly empty")
                }
            }
        }
        
        print("")
    }
    
    static func testMetalVolumeRenderer() {
        print("🖥️  TEST: Metal Volume Renderer Initialization")
        
        do {
            let renderer = try MetalVolumeRenderer()
            volumeRenderer = renderer
            
            print("   ✅ MetalVolumeRenderer created successfully")
            
            // Load volume if available
            if let volume = volumeData {
                print("   📤 Loading volume into Metal texture...")
                
                let startTime = CFAbsoluteTimeGetCurrent()
                try renderer.loadVolume(volume)
                let loadTime = CFAbsoluteTimeGetCurrent() - startTime
                
                print("   ✅ Volume loaded to GPU")
                print("   ⏱️  GPU upload time: \(String(format: "%.2f", loadTime * 1000))ms")
                
                if let info = renderer.getVolumeInfo() {
                    print("   \(info)")
                }
            }
            
        } catch {
            print("   ❌ MetalVolumeRenderer initialization failed: \(error)")
        }
        
        print("")
    }
    
    static func testMPRGeneration() {
        print("🎬 TEST: GPU MPR Slice Generation")
        
        guard let renderer = volumeRenderer else {
            print("   ❌ No MetalVolumeRenderer available")
            return
        }
        
        guard renderer.isVolumeLoaded() else {
            print("   ❌ No volume loaded in renderer")
            return
        }
        
        let testConfigs = [
            ("Axial Center", MPRPlane.axial, 0.5),
            ("Axial Superior", MPRPlane.axial, 0.8),
            ("Sagittal Center", MPRPlane.sagittal, 0.5),
            ("Sagittal Right", MPRPlane.sagittal, 0.3),
            ("Coronal Center", MPRPlane.coronal, 0.5),
            ("Coronal Anterior", MPRPlane.coronal, 0.7)
        ]
        
        var completedTests = 0
        let totalTests = testConfigs.count
        
        for (name, plane, position) in testConfigs {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            switch plane {
            case .axial:
                renderer.generateAxialSlice(atPosition: Float(position)) { texture in
                    let renderTime = CFAbsoluteTimeGetCurrent() - startTime
                    
                    if let texture = texture {
                        print("   🎬 \(name): ✅ \(texture.width)×\(texture.height) in \(String(format: "%.2f", renderTime * 1000))ms")
                    } else {
                        print("   🎬 \(name): ❌ Failed")
                    }
                    
                    completedTests += 1
                }
                
            case .sagittal:
                renderer.generateSagittalSlice(atPosition: Float(position)) { texture in
                    let renderTime = CFAbsoluteTimeGetCurrent() - startTime
                    
                    if let texture = texture {
                        print("   🎬 \(name): ✅ \(texture.width)×\(texture.height) in \(String(format: "%.2f", renderTime * 1000))ms")
                    } else {
                        print("   🎬 \(name): ❌ Failed")
                    }
                    
                    completedTests += 1
                }
                
            case .coronal:
                renderer.generateCoronalSlice(atPosition: Float(position)) { texture in
                    let renderTime = CFAbsoluteTimeGetCurrent() - startTime
                    
                    if let texture = texture {
                        print("   🎬 \(name): ✅ \(texture.width)×\(texture.height) in \(String(format: "%.2f", renderTime * 1000))ms")
                    } else {
                        print("   🎬 \(name): ❌ Failed")
                    }
                    
                    completedTests += 1
                }
            }
        }
        
        // Wait for async operations to complete
        let timeout = Date().addingTimeInterval(5.0)
        while completedTests < totalTests && Date() < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        
        if completedTests == totalTests {
            print("   📊 All MPR tests completed successfully")
        } else {
            print("   ⚠️  Only \(completedTests)/\(totalTests) MPR tests completed")
        }
        
        print("")
    }
    
    static func testVolumeStatistics() {
        print("📊 TEST: Volume Statistics and Analysis")
        
        guard let volume = volumeData else {
            print("   ❌ No volume data available")
            return
        }
        
        let stats = volume.getStatistics()
        
        print("   📈 Volume Statistics:")
        print("      📐 Dimensions: \(stats.dimensions.x) × \(stats.dimensions.y) × \(stats.dimensions.z)")
        print("      📏 Physical size: \(String(format: "%.1f", Float(stats.dimensions.x) * stats.spacing.x))×\(String(format: "%.1f", Float(stats.dimensions.y) * stats.spacing.y))×\(String(format: "%.1f", Float(stats.dimensions.z) * stats.spacing.z)) mm")
        print("      📊 Intensity range: \(stats.minValue) to \(stats.maxValue) HU")
        print("      📊 Mean intensity: \(String(format: "%.1f", stats.meanValue)) HU")
        print("      🔢 Total voxels: \(stats.voxelCount)")
        print("      💾 Memory usage: \(String(format: "%.2f", Double(stats.memoryUsage) / 1024.0 / 1024.0)) MB")
        
        // Test voxel access patterns
        print("   🔍 Testing voxel access:")
        
        let testCoords = [
            (0, 0, 0),
            (stats.dimensions.x/2, stats.dimensions.y/2, stats.dimensions.z/2),
            (stats.dimensions.x-1, stats.dimensions.y-1, stats.dimensions.z-1)
        ]
        
        for (x, y, z) in testCoords {
            if let voxel = volume.getVoxel(x: x, y: y, z: z) {
                print("      Voxel[\(x),\(y),\(z)] = \(voxel)")
            } else {
                print("      Voxel[\(x),\(y),\(z)] = out of bounds")
            }
        }
        
        // Test interpolation
        print("   🎯 Testing interpolation:")
        let interpValue = volume.getInterpolatedVoxel(
            x: Float(stats.dimensions.x) * 0.5,
            y: Float(stats.dimensions.y) * 0.5,
            z: Float(stats.dimensions.z) * 0.5
        )
        print("      Center interpolated value: \(String(format: "%.2f", interpValue))")
        
        // Test anatomical position mapping
        print("   🧭 Testing anatomical positions:")
        for plane in MPRPlane.allCases {
            let centerPos = volume.sliceIndexToAnatomicalPosition(stats.dimensions.z/2, plane: plane)
            print("      \(plane.rawValue) center: \(centerPos)")
        }
        
        print("")
    }
    
    static func testMemoryPerformance() {
        print("⚡ TEST: Memory and Performance Analysis")
        
        guard let volume = volumeData else {
            print("   ❌ No volume data available")
            return
        }
        
        // Memory footprint analysis
        let stats = volume.getStatistics()
        let memoryMB = Double(stats.memoryUsage) / 1024.0 / 1024.0
        
        print("   💾 Memory Analysis:")
        print("      Raw volume data: \(String(format: "%.2f", memoryMB)) MB")
        print("      Memory per voxel: \(MemoryLayout<Int16>.size) bytes")
        print("      Estimated GPU memory: \(String(format: "%.2f", memoryMB * 1.1)) MB") // Include texture overhead
        
        // Performance benchmarks
        print("   ⚡ Performance Benchmarks:")
        
        // Benchmark slice extraction
        let iterations = 10
        var totalTime: Double = 0
        
        for i in 0..<iterations {
            let position = Float(i) / Float(iterations - 1) * Float(stats.dimensions.z - 1)
            
            let startTime = CFAbsoluteTimeGetCurrent()
            let _ = volume.extractAxialSlice(atZ: position)
            totalTime += CFAbsoluteTimeGetCurrent() - startTime
        }
        
        let avgExtractionTime = totalTime / Double(iterations) * 1000
        print("      Average slice extraction: \(String(format: "%.2f", avgExtractionTime))ms")
        
        // Benchmark interpolation
        totalTime = 0
        let interpIterations = 1000
        
        let startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<interpIterations {
            let x = Float.random(in: 0..<Float(stats.dimensions.x))
            let y = Float.random(in: 0..<Float(stats.dimensions.y))
            let z = Float.random(in: 0..<Float(stats.dimensions.z))
            let _ = volume.getInterpolatedVoxel(x: x, y: y, z: z)
        }
        totalTime = CFAbsoluteTimeGetCurrent() - startTime
        
        let avgInterpolationTime = totalTime / Double(interpIterations) * 1000000 // microseconds
        print("      Average interpolation: \(String(format: "%.2f", avgInterpolationTime))μs")
        
        // Memory efficiency analysis
        let theoreticalMin = stats.voxelCount * MemoryLayout<Int16>.size
        let actualUsage = stats.memoryUsage
        let overhead = Double(actualUsage - theoreticalMin) / Double(theoreticalMin) * 100
        
        print("      Memory efficiency: \(String(format: "%.1f", 100.0 - overhead))%")
        print("      Memory overhead: \(String(format: "%.1f", overhead))%")
        
        print("")
    }
    
    // MARK: - Integration Testing
    
    static func testVolumeToPixelDataConversion() {
        print("🔄 TEST: Volume to PixelData Conversion")
        
        guard let renderer = volumeRenderer else {
            print("   ❌ No MetalVolumeRenderer available")
            return
        }
        
        let testCases = [
            ("Axial Center", MPRPlane.axial, 0.5),
            ("Sagittal Center", MPRPlane.sagittal, 0.5),
            ("Coronal Center", MPRPlane.coronal, 0.5)
        ]
        
        for (name, plane, position) in testCases {
            Task {
                if let pixelData = await renderer.mprSliceToPixelData(plane: plane, slicePosition: Float(position)) {
                    print("   🔄 \(name): ✅ \(pixelData.columns)×\(pixelData.rows)")
                    print("      Bits allocated: \(pixelData.bitsAllocated)")
                    print("      Pixel representation: \(pixelData.pixelRepresentation)")
                    print("      Data size: \(pixelData.data.count) bytes")
                    
                    // Test conversion to arrays
                    let pixels = pixelData.toInt16Array()
                    if !pixels.isEmpty {
                        let minVal = pixels.min() ?? 0
                        let maxVal = pixels.max() ?? 0
                        print("      Value range: \(minVal) to \(maxVal)")
                    }
                } else {
                    print("   🔄 \(name): ❌ Conversion failed")
                }
            }
        }
        
        print("")
    }
    
    // MARK: - Utility Methods
    
    static func getLoadedVolume() -> VolumeData? {
        return volumeData
    }
    
    static func getVolumeRenderer() -> MetalVolumeRenderer? {
        return volumeRenderer
    }
    
    static func printVolumeInfo() {
        guard let volume = volumeData else {
            print("❌ No volume loaded")
            return
        }
        
        let stats = volume.getStatistics()
        print("""
        
        📊 LOADED VOLUME INFORMATION:
           📐 Dimensions: \(stats.dimensions.x) × \(stats.dimensions.y) × \(stats.dimensions.z)
           📏 Spacing: \(String(format: "%.2f", stats.spacing.x)) × \(String(format: "%.2f", stats.spacing.y)) × \(String(format: "%.2f", stats.spacing.z)) mm
           📊 Value range: \(stats.minValue) to \(stats.maxValue) HU
           💾 Memory: \(String(format: "%.2f", Double(stats.memoryUsage) / 1024.0 / 1024.0)) MB
           🔢 Voxels: \(stats.voxelCount)
        
        """)
    }
    
    // MARK: - Quick Test Methods
    
    static func runQuickVolumeTests() {
        print("\n⚡ Quick Volume Tests\n")
        testVolumeDataCreation()
        testMetalVolumeRenderer()
        testMPRGeneration()
        print("⚡ Quick volume tests complete!\n")
    }
    
    static func testSpecificPlane(_ plane: MPRPlane, position: Float = 0.5) {
        print("\n🎯 Testing \(plane.rawValue) plane at position \(position)\n")
        
        guard let renderer = volumeRenderer else {
            print("❌ No renderer available")
            return
        }
        
        let config = MetalVolumeRenderer.MPRConfig(
            plane: plane,
            sliceIndex: position,
            windowCenter: 0.0,
            windowWidth: 2000.0
        )
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        renderer.generateMPRSlice(config: config) { texture in
            let renderTime = CFAbsoluteTimeGetCurrent() - startTime
            
            if let texture = texture {
                print("✅ \(plane.rawValue) slice generated: \(texture.width)×\(texture.height)")
                print("⏱️  Render time: \(String(format: "%.2f", renderTime * 1000))ms")
                print("🎨 Pixel format: \(texture.pixelFormat)")
            } else {
                print("❌ \(plane.rawValue) slice generation failed")
            }
        }
        
        print("")
    }
}
