import Foundation
import UIKit

// MARK: - DICOM Test Manager (UPDATED with File Filtering)
// Comprehensive testing for SwiftDICOM parser development
// Now properly separates CT images from RTStruct files

class DICOMTestManager {
    
    // MARK: - Test Configuration
    private static let testDataPath = "" // Files are in bundle root
    private static let expectedCTFileCount = 53  // Expected CT slices
    private static let expectedRTStructCount = 1  // Expected RTStruct files
    
    // MARK: - Main Test Runner
    
    static func runAllTests() {
        print("\n🧪 ===========================================")
        print("🧪 SwiftDICOM Parser Test Suite (FILTERED)")
        print("🧪 ===========================================\n")
        
        testFileDiscoveryFiltered()
        testBasicParsing()
        testPixelDataExtraction()
        testMultipleFiles()
        testWindowingData()
        testSpatialInformation()
        testSeriesAnalysis()
        testRTStructDiscovery()
        
        print("\n✅ ===========================================")
        print("✅ Test Suite Complete!")
        print("✅ ===========================================\n")
    }
    
    // MARK: - Individual Tests (Updated)
    
    static func testFileDiscoveryFiltered() {
        print("📂 TEST: Filtered File Discovery")
        print("   Expected CT files: \(expectedCTFileCount)")
        print("   Expected RTStruct files: \(expectedRTStructCount)")
        
        // Use new filtered discovery
        let (ctFiles, rtStructFiles, allFiles) = DICOMFileManager.discoverDICOMFiles()
        
        print("   📁 Total DICOM files found: \(allFiles.count)")
        print("   🩻 CT image files: \(ctFiles.count)")
        print("   📊 RTStruct files: \(rtStructFiles.count)")
        
        // Validate counts
        if ctFiles.count == expectedCTFileCount {
            print("   ✅ CT file count matches expectation")
        } else {
            print("   ⚠️  CT file count mismatch (expected \(expectedCTFileCount), found \(ctFiles.count))")
        }
        
        if rtStructFiles.count >= expectedRTStructCount {
            print("   ✅ RTStruct files found as expected")
        } else {
            print("   ⚠️  No RTStruct files found (expected at least \(expectedRTStructCount))")
        }
        
        // Show sample files
        print("   📋 Sample CT files:")
        for (index, file) in ctFiles.prefix(5).enumerated() {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let shortName = String(file.lastPathComponent.prefix(40)) + (file.lastPathComponent.count > 40 ? "..." : "")
            print("      \(index + 1). \(shortName) (\(size) bytes)")
        }
        
        if ctFiles.count > 5 {
            print("      ... and \(ctFiles.count - 5) more CT files")
        }
        
        // Show RTStruct files
        if !rtStructFiles.isEmpty {
            print("   📊 RTStruct files:")
            for (index, file) in rtStructFiles.enumerated() {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                print("      \(index + 1). \(file.lastPathComponent) (\(size) bytes)")
            }
        }
        
        print("")
    }
    
    static func testRTStructDiscovery() {
        print("📊 TEST: RTStruct File Discovery")
        
        let rtStructFiles = DICOMFileManager.getRTStructFiles()
        
        print("   🔍 Searching for RTStruct files...")
        print("   📊 Found \(rtStructFiles.count) RTStruct file(s)")
        
        if rtStructFiles.isEmpty {
            print("   ⚠️  No RTStruct files found")
            print("   💡 Expected filename pattern: *_rtstruct.dcm")
            print("   💡 Make sure test RTStruct file is named: test_rtstruct.dcm")
        } else {
            for (index, file) in rtStructFiles.enumerated() {
                print("   📄 RTStruct \(index + 1): \(file.lastPathComponent)")
                
                // Try to parse RTStruct file
                do {
                    let data = try Data(contentsOf: file)
                    let dataset = try DICOMParser.parse(data)
                    
                    print("      ✅ Successfully parsed RTStruct DICOM")
                    
                    // Check for RTStruct-specific tags
                    if let modality = dataset.getString(tag: .modality) {
                        print("      🏷️  Modality: \(modality)")
                        if modality == "RTSTRUCT" {
                            print("      ✅ Confirmed RTStruct modality")
                        } else {
                            print("      ⚠️  Unexpected modality for RTStruct file")
                        }
                    }
                    
                    if let seriesDescription = dataset.getString(tag: .seriesDescription) {
                        print("      📝 Series Description: \(seriesDescription)")
                    }
                    
                    // Check for structure set ROI sequence (this will be implemented later)
                    print("      🎯 ROI parsing: Will be implemented in next phase")
                    
                } catch {
                    print("      ❌ Failed to parse RTStruct: \(error)")
                }
            }
        }
        
        print("")
    }
    
    static func testBasicParsing() {
        print("🔍 TEST: Basic DICOM Parsing (CT Files Only)")
        
        let ctFiles = DICOMFileManager.getCTImageFiles()
        guard let firstFile = ctFiles.first else {
            print("   ❌ No CT files available for testing")
            return
        }
        
        print("   📄 Testing CT file: \(firstFile.lastPathComponent)")
        
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
            
            // Verify this is a CT image
            if let modality = dataset.getString(tag: .modality) {
                print("   🏷️  Modality: \(modality)")
                if modality == "CT" {
                    print("   ✅ Confirmed CT image modality")
                } else {
                    print("   ⚠️  Unexpected modality: \(modality)")
                }
            }
            
        } catch {
            print("   ❌ Parsing failed: \(error)")
        }
        
        print("")
    }
    
    static func testPixelDataExtraction() {
        print("🎨 TEST: Pixel Data Extraction (CT Only)")
        
        let ctFiles = DICOMFileManager.getCTImageFiles()
        guard let firstFile = ctFiles.first else {
            print("   ❌ No CT files available")
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
        print("📚 TEST: Multiple CT File Processing")
        
        let ctFiles = DICOMFileManager.getCTImageFiles()
        let testCount = min(5, ctFiles.count) // Test first 5 files
        
        print("   🗂️  Testing \(testCount) CT files from series of \(ctFiles.count)")
        
        var successCount = 0
        var failCount = 0
        var imageSizes: Set<String> = []
        var modalities: Set<String> = []
        
        for (index, file) in ctFiles.prefix(testCount).enumerated() {
            do {
                let data = try Data(contentsOf: file)
                let dataset = try DICOMParser.parse(data)
                
                if let rows = dataset.rows, let columns = dataset.columns {
                    imageSizes.insert("\(columns)×\(rows)")
                }
                
                if let modality = dataset.getString(tag: .modality) {
                    modalities.insert(modality)
                }
                
                successCount += 1
                print("   ✅ CT File \(index + 1): \(file.lastPathComponent)")
                
            } catch {
                failCount += 1
                print("   ❌ CT File \(index + 1): \(file.lastPathComponent) - \(error)")
            }
        }
        
        print("   📊 Results: \(successCount) success, \(failCount) failed")
        print("   📐 Image sizes found: \(imageSizes.joined(separator: ", "))")
        print("   🏷️  Modalities found: \(modalities.joined(separator: ", "))")
        
        if imageSizes.count == 1 {
            print("   ✅ Consistent image dimensions across CT files")
        } else {
            print("   ⚠️  Multiple image sizes detected")
        }
        
        if modalities.count == 1 && modalities.first == "CT" {
            print("   ✅ All files confirmed as CT modality")
        } else {
            print("   ⚠️  Mixed or unexpected modalities found")
        }
        
        print("")
    }
    
    static func testWindowingData() {
        print("🪟 TEST: CT Windowing Information")
        
        let ctFiles = DICOMFileManager.getCTImageFiles()
        guard let firstFile = ctFiles.first else {
            print("   ❌ No CT files available")
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
        
        let ctFiles = DICOMFileManager.getCTImageFiles()
        guard let firstFile = ctFiles.first else {
            print("   ❌ No CT files available")
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
        print("📈 TEST: CT Series Analysis")
        
        let ctFiles = DICOMFileManager.getCTImageFiles()
        print("   📊 Analyzing CT series of \(ctFiles.count) files...")
        
        var instanceNumbers: [Int] = []
        var sliceLocations: [Double] = []
        var seriesUID: String?
        
        // Analyze first 10 files to avoid overwhelming output
        let analysisCount = min(10, ctFiles.count)
        
        for file in ctFiles.prefix(analysisCount) {
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
        
        print("   📋 CT Series appears consistent: \(instanceNumbers.count == analysisCount ? "✅" : "❌")")
        
        print("")
    }
    
    // MARK: - Updated Helper Functions
    
    static func getDICOMFiles() -> [URL] {
        return DICOMFileManager.getCTImageFiles()
    }
    
    static func getCTFiles() -> [URL] {
        return DICOMFileManager.getCTImageFiles()
    }
    
    static func getRTStructFiles() -> [URL] {
        return DICOMFileManager.getRTStructFiles()
    }
    
    // MARK: - Dataset Information
    
    static func printDatasetInfo() {
        print("\n📊 ===========================================")
        print("📊 Current Dataset Information")
        print("📊 ===========================================\n")
        
        DICOMFileManager.printFileOrganization()
        
        let datasets = DICOMFileManager.organizeDatasets()
        print("   📈 Available datasets: \(datasets.keys.joined(separator: ", "))")
        
        for (key, dataset) in datasets {
            let validation = DICOMFileManager.validateDataset(dataset)
            if validation.isValid {
                print("   ✅ \(key): Ready for use")
            } else {
                print("   ⚠️  \(key): \(validation.issues.joined(separator: ", "))")
            }
        }
        
        print("📊 ===========================================\n")
    }
    
    // MARK: - Existing Helper Functions (Unchanged)
    
    private static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private static func identifyWindowPreset(center: Double, width: Double) -> String {
        let presets = CTWindowPresets.allPresets
        
        for preset in presets {
            if abs(Double(preset.center) - center) < 50 && abs(Double(preset.width) - width) < 100 {
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

// MARK: - Quick Test Access (Updated)

extension DICOMTestManager {
    
    /// Run just the essential tests for quick validation
    static func runQuickTests() {
        print("\n⚡ Quick DICOM Tests (Filtered)\n")
        testFileDiscoveryFiltered()
        testBasicParsing()
        testPixelDataExtraction()
        testRTStructDiscovery()
        print("⚡ Quick tests complete!\n")
    }
    
    /// Test a specific file by name
    static func testSpecificFile(_ filename: String) {
        print("\n🎯 Testing specific file: \(filename)\n")
        
        let allFiles = DICOMFileManager.getAllDICOMFiles()
        guard let targetFile = allFiles.first(where: { $0.lastPathComponent == filename }) else {
            print("❌ File not found: \(filename)")
            return
        }
        
        let fileType = DICOMFileManager.classifyDICOMFile(targetFile)
        print("🏷️  File type: \(fileType)")
        
        do {
            let data = try Data(contentsOf: targetFile)
            let dataset = try DICOMParser.parse(data)
            
            if fileType == .ctImage {
                guard let pixelData = DICOMParser.extractPixelData(from: dataset) else {
                    print("❌ Could not extract pixel data from \(filename)")
                    return
                }
                
                print("✅ Successfully processed CT file \(filename)")
                print("📐 Size: \(pixelData.columns)×\(pixelData.rows)")
                print("🎨 Pixels: \(pixelData.toUInt16Array().count)")
            } else if fileType == .rtStruct {
                print("✅ Successfully processed RTStruct file \(filename)")
                
                if let modality = dataset.getString(tag: .modality) {
                    print("🏷️  Modality: \(modality)")
                }
                
                print("🎯 ROI analysis: Will be implemented in next phase")
            }
            
        } catch {
            print("❌ Error: \(error)")
        }
        
        print("")
    }
}
