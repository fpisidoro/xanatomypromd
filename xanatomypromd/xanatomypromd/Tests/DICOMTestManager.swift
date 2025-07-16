import Foundation
import UIKit

// MARK: - DICOM Test Manager
// Comprehensive testing for SwiftDICOM parser development
// Clean separation from main app code

class DICOMTestManager {
    
    // MARK: - Test Configuration
    private static let testDataPath = "" // Files are in bundle root
    private static let expectedFileCount = 53
    
    // MARK: - Main Test Runner
    
    static func runAllTests() {
        print("\n🧪 ===========================================")
        print("🧪 SwiftDICOM Parser Test Suite")
        print("🧪 ===========================================\n")
        
        testFileDiscovery()
        testBasicParsing()
        testPixelDataExtraction()
        testMultipleFiles()
        testWindowingData()
        testSpatialInformation()
        testSeriesAnalysis()
        
        print("\n✅ ===========================================")
        print("✅ Test Suite Complete!")
        print("✅ ===========================================\n")
    }
    
    // MARK: - Individual Tests
    
    static func testFileDiscovery() {
        print("📂 TEST: File Discovery")
        print("   Expected location: Bundle root directory")
        
        guard let bundlePath = Bundle.main.resourcePath else {
            print("   ❌ Could not access bundle resource path")
            return
        }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: bundlePath),
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            )
            
            let dicomFiles = fileURLs.filter {
                $0.pathExtension.lowercased() == "dcm" ||
                $0.lastPathComponent.contains("2.16.840.1.114362")
            }
            
            print("   📁 Total files found: \(fileURLs.count)")
            print("   🩺 DICOM files found: \(dicomFiles.count)")
            print("   📊 Expected files: \(expectedFileCount)")
            
            if dicomFiles.count == expectedFileCount {
                print("   ✅ File count matches expectation")
            } else {
                print("   ⚠️  File count mismatch (expected \(expectedFileCount), found \(dicomFiles.count))")
            }
            
            // Show first few filenames
            print("   📋 Sample files:")
            for (index, file) in dicomFiles.prefix(5).enumerated() {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                let shortName = String(file.lastPathComponent.prefix(40)) + (file.lastPathComponent.count > 40 ? "..." : "")
                print("      \(index + 1). \(shortName) (\(size) bytes)")
            }
            
            if dicomFiles.count > 5 {
                print("      ... and \(dicomFiles.count - 5) more files")
            }
            
        } catch {
            print("   ❌ Error reading directory: \(error)")
        }
        
        print("")
    }
    
    static func testBasicParsing() {
        print("🔍 TEST: Basic DICOM Parsing")
        
        guard let firstFile = getDICOMFiles().first else {
            print("   ❌ No DICOM files available for testing")
            return
        }
        
        print("   📄 Testing file: \(firstFile.lastPathComponent)")
        
        do {
            let data = try Data(contentsOf: firstFile)
            print("   📊 File size: \(formatBytes(data.count))")
            
            let dataset = try DICOMParser.parse(data)
            print("   ✅ Successfully parsed DICOM file!")
            
            // Basic validation
            let elementCount = dataset.elements.count
            print("   🏷️  DICOM elements found: \(elementCount)")
            
            // Check for essential elements
            let hasPixelData = dataset.elements[DICOMTag.pixelData] != nil
            let hasRows = dataset.rows != nil
            let hasColumns = dataset.columns != nil
            
            print("   📐 Has image dimensions: \(hasRows && hasColumns ? "✅" : "❌")")
            print("   🎨 Has pixel data: \(hasPixelData ? "✅" : "❌")")
            
            if let rows = dataset.rows, let columns = dataset.columns {
                print("   📏 Image size: \(columns) × \(rows)")
            }
            
        } catch {
            print("   ❌ Parsing failed: \(error)")
        }
        
        print("")
    }
    
    static func testPixelDataExtraction() {
        print("🎨 TEST: Pixel Data Extraction")
        
        guard let firstFile = getDICOMFiles().first else {
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
            
            print("   ✅ Successfully extracted pixel data!")
            
            print("   📊 Pixel data size: \(formatBytes(pixelData.data.count))")
            print("   📐 Dimensions: \(pixelData.columns) × \(pixelData.rows)")
            print("   🔢 Bits allocated: \(pixelData.bitsAllocated)")
            print("   🔢 Bits stored: \(pixelData.bitsStored)")
            print("   📈 Pixel representation: \(pixelData.pixelRepresentation == 0 ? "Unsigned" : "Signed")")
            
            // Test pixel array conversion
            let pixels = pixelData.toUInt16Array()
            print("   📊 Extracted pixels: \(pixels.count)")
            
            if !pixels.isEmpty {
                let minPixel = pixels.min() ?? 0
                let maxPixel = pixels.max() ?? 0
                let sum = pixels.reduce(0) { $0 + Int($1) }
                let avgPixel = sum / pixels.count
                
                print("   📉 Pixel value range: \(minPixel) - \(maxPixel)")
                print("   📊 Average pixel value: \(avgPixel)")
                
                // Check for reasonable CT values
                if maxPixel > 1000 && maxPixel < 5000 {
                    print("   ✅ Pixel values look reasonable for CT")
                } else {
                    print("   ⚠️  Unusual pixel value range for CT")
                }
            }
            
        } catch {
            print("   ❌ Pixel extraction failed: \(error)")
        }
        
        print("")
    }
    
    static func testMultipleFiles() {
        print("📚 TEST: Multiple File Processing")
        
        let dicomFiles = getDICOMFiles()
        let testCount = min(5, dicomFiles.count) // Test first 5 files
        
        print("   🗂️  Testing \(testCount) files from series of \(dicomFiles.count)")
        
        var successCount = 0
        var failCount = 0
        var imageSizes: Set<String> = []
        
        for (index, file) in dicomFiles.prefix(testCount).enumerated() {
            do {
                let data = try Data(contentsOf: file)
                let dataset = try DICOMParser.parse(data)
                
                if let rows = dataset.rows, let columns = dataset.columns {
                    imageSizes.insert("\(columns)×\(rows)")
                }
                
                successCount += 1
                print("   ✅ File \(index + 1): \(file.lastPathComponent)")
                
            } catch {
                failCount += 1
                print("   ❌ File \(index + 1): \(file.lastPathComponent) - \(error)")
            }
        }
        
        print("   📊 Results: \(successCount) success, \(failCount) failed")
        print("   📐 Image sizes found: \(imageSizes.joined(separator: ", "))")
        
        if imageSizes.count == 1 {
            print("   ✅ Consistent image dimensions across files")
        } else {
            print("   ⚠️  Multiple image sizes detected")
        }
        
        print("")
    }
    
    static func testWindowingData() {
        print("🪟 TEST: CT Windowing Information")
        
        guard let firstFile = getDICOMFiles().first else {
            print("   ❌ No DICOM files available")
            return
        }
        
        do {
            let data = try Data(contentsOf: firstFile)
            let dataset = try DICOMParser.parse(data)
            
            print("   🔍 Checking for windowing information...")
            
            if let windowCenter = dataset.windowCenter {
                print("   🎯 Window Center: \(windowCenter)")
            } else {
                print("   ❌ No Window Center found")
            }
            
            if let windowWidth = dataset.windowWidth {
                print("   📏 Window Width: \(windowWidth)")
            } else {
                print("   ❌ No Window Width found")
            }
            
            // Check for rescale parameters
            if let rescaleSlope = dataset.getDouble(tag: .rescaleSlope) {
                print("   📈 Rescale Slope: \(rescaleSlope)")
            }
            
            if let rescaleIntercept = dataset.getDouble(tag: .rescaleIntercept) {
                print("   📊 Rescale Intercept: \(rescaleIntercept)")
            }
            
            // Compare with standard presets
            if let center = dataset.windowCenter, let width = dataset.windowWidth {
                let preset = identifyWindowPreset(center: center, width: width)
                print("   🏷️  Closest preset: \(preset)")
            }
            
        } catch {
            print("   ❌ Error reading windowing data: \(error)")
        }
        
        print("")
    }
    
    static func testSpatialInformation() {
        print("🗺️  TEST: Spatial Information (MPR Readiness)")
        
        guard let firstFile = getDICOMFiles().first else {
            print("   ❌ No DICOM files available")
            return
        }
        
        do {
            let data = try Data(contentsOf: firstFile)
            let dataset = try DICOMParser.parse(data)
            
            print("   🔍 Checking spatial metadata for MPR...")
            
            if let pixelSpacing = dataset.pixelSpacing {
                print("   📏 Pixel Spacing: \(pixelSpacing)")
            } else {
                print("   ❌ No Pixel Spacing found")
            }
            
            if let sliceThickness = dataset.sliceThickness {
                print("   📐 Slice Thickness: \(sliceThickness)")
            } else {
                print("   ❌ No Slice Thickness found")
            }
            
            if let imagePosition = dataset.imagePosition {
                print("   📍 Image Position: \(imagePosition)")
            } else {
                print("   ❌ No Image Position found")
            }
            
            if let imageOrientation = dataset.imageOrientation {
                print("   🧭 Image Orientation: \(imageOrientation)")
            } else {
                print("   ❌ No Image Orientation found")
            }
            
            // MPR readiness assessment
            let hasSpatialInfo = dataset.pixelSpacing != nil &&
                               dataset.imagePosition != nil &&
                               dataset.imageOrientation != nil
            
            print("   🚀 MPR Ready: \(hasSpatialInfo ? "✅" : "❌")")
            
        } catch {
            print("   ❌ Error reading spatial data: \(error)")
        }
        
        print("")
    }
    
    static func testSeriesAnalysis() {
        print("📈 TEST: Series Analysis")
        
        let dicomFiles = getDICOMFiles()
        print("   📊 Analyzing series of \(dicomFiles.count) files...")
        
        var instanceNumbers: [Int] = []
        var sliceLocations: [Double] = []
        var seriesUID: String?
        
        // Analyze first 10 files to avoid overwhelming output
        let analysisCount = min(10, dicomFiles.count)
        
        for file in dicomFiles.prefix(analysisCount) {
            do {
                let data = try Data(contentsOf: file)
                let dataset = try DICOMParser.parse(data)
                
                if let instanceNum = dataset.getUInt16(tag: .instanceNumber) {
                    instanceNumbers.append(Int(instanceNum))
                }
                
                if let sliceLocation = dataset.getDouble(tag: .sliceLocation) {
                    sliceLocations.append(sliceLocation)
                }
                
                if seriesUID == nil {
                    seriesUID = dataset.getString(tag: .seriesInstanceUID)
                }
                
            } catch {
                print("   ⚠️  Could not analyze file: \(file.lastPathComponent)")
            }
        }
        
        print("   🏷️  Series UID: \(seriesUID?.prefix(20) ?? "Unknown")...")
        print("   🔢 Instance numbers: \(instanceNumbers.sorted())")
        
        if !sliceLocations.isEmpty {
            let sortedLocations = sliceLocations.sorted()
            let spacing = calculateAverageSpacing(sortedLocations)
            print("   📏 Slice locations: \(sortedLocations.prefix(5).map { String(format: "%.1f", $0) }.joined(separator: ", "))...")
            print("   📐 Average slice spacing: \(String(format: "%.2f", spacing)) mm")
        }
        
        print("   📋 Series appears consistent: \(instanceNumbers.count == analysisCount ? "✅" : "❌")")
        
        print("")
    }
    
    // MARK: - Helper Functions
    
    static func getDICOMFiles() -> [URL] {
        guard let bundlePath = Bundle.main.resourcePath else {
            return []
        }
        
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
    
    private static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private static func identifyWindowPreset(center: Double, width: Double) -> String {
        let presets = CTWindowPresets.all
        
        for preset in presets {
            if abs(preset.center - center) < 50 && abs(preset.width - width) < 100 {
                return preset.name
            }
        }
        
        return "Custom (\(Int(center))/\(Int(width)))"
    }
    
    private static func calculateAverageSpacing(_ locations: [Double]) -> Double {
        guard locations.count > 1 else { return 0 }
        
        var spacings: [Double] = []
        for i in 1..<locations.count {
            spacings.append(abs(locations[i] - locations[i-1]))
        }
        
        return spacings.reduce(0, +) / Double(spacings.count)
    }
}

// MARK: - Quick Test Access

extension DICOMTestManager {
    
    /// Run just the essential tests for quick validation
    static func runQuickTests() {
        print("\n⚡ Quick DICOM Tests\n")
        testFileDiscovery()
        testBasicParsing()
        testPixelDataExtraction()
        print("⚡ Quick tests complete!\n")
    }
    
    /// Test a specific file by name
    static func testSpecificFile(_ filename: String) {
        print("\n🎯 Testing specific file: \(filename)\n")
        
        let dicomFiles = getDICOMFiles()
        guard let targetFile = dicomFiles.first(where: { $0.lastPathComponent == filename }) else {
            print("❌ File not found: \(filename)")
            return
        }
        
        do {
            let data = try Data(contentsOf: targetFile)
            let dataset = try DICOMParser.parse(data)
            
            guard let pixelData = DICOMParser.extractPixelData(from: dataset) else {
                print("❌ Could not extract pixel data from \(filename)")
                return
            }
            
            print("✅ Successfully processed \(filename)")
            print("📐 Size: \(pixelData.columns)×\(pixelData.rows)")
            print("🎨 Pixels: \(pixelData.toUInt16Array().count)")
            
        } catch {
            print("❌ Error: \(error)")
        }
        
        print("")
    }
}
