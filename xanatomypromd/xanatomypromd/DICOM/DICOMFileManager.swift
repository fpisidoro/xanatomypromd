import Foundation

// MARK: - DICOM File Type Classification
// Separates CT image series from RTStruct files for proper dataset handling

enum DICOMFileType {
    case ctImage
    case rtStruct
    case unknown
}

// FIXED: Renamed to avoid conflict with DICOMParser's DICOMDataset
struct DICOMFileSet {
    let ctFiles: [URL]
    let rtStructFiles: [URL]
    let datasetName: String
}

// MARK: - DICOM File Discovery and Filtering

class DICOMFileManager {
    
    // MARK: - File Type Detection
    
    /// Determine DICOM file type based on filename patterns
    static func classifyDICOMFile(_ fileURL: URL) -> DICOMFileType {
        let filename = fileURL.lastPathComponent.lowercased()
        
        // RTStruct file patterns
        if filename.contains("_rtstruct.dcm") ||
           filename.contains("rtstruct") ||
           filename.contains("rs.") {
            return .rtStruct
        }
        
        // CT image file patterns
        if filename.contains("_ct_") ||
           filename.contains("2.16.840.1.114362") ||  // Current test dataset pattern
           filename.hasSuffix(".dcm") {
            return .ctImage
        }
        
        return .unknown
    }
    
    // MARK: - Filtered File Discovery
    
    /// Get all DICOM files separated by type
    static func discoverDICOMFiles() -> (ctFiles: [URL], rtStructFiles: [URL], allFiles: [URL]) {
        guard let bundlePath = Bundle.main.resourcePath else {
            print("❌ Cannot access bundle resource path")
            return ([], [], [])
        }
        
        // Check both bundle root and TestData subdirectory
        let searchPaths = [
            bundlePath,
            bundlePath + "/TestData"
        ]
        
        var ctFiles: [URL] = []
        var rtStructFiles: [URL] = []
        var allDICOMFiles: [URL] = []
        
        for searchPath in searchPaths {
            let searchURL = URL(fileURLWithPath: searchPath)
            
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: searchURL,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: .skipsHiddenFiles
                )
                
                for fileURL in fileURLs {
                    let fileType = classifyDICOMFile(fileURL)
                    
                    switch fileType {
                    case .ctImage:
                        ctFiles.append(fileURL)
                        allDICOMFiles.append(fileURL)
                    case .rtStruct:
                        rtStructFiles.append(fileURL)
                        allDICOMFiles.append(fileURL)
                    case .unknown:
                        continue
                    }
                }
            } catch {
                // Silent fail for missing directories
                continue
            }
        }
        
        // Sort CT files for proper anatomical ordering
        ctFiles.sort { $0.lastPathComponent < $1.lastPathComponent }
        rtStructFiles.sort { $0.lastPathComponent < $1.lastPathComponent }
        
        print("📁 DICOM File Discovery Results:")
        print("   🩻 CT images: \(ctFiles.count)")
        print("   📊 RTStruct files: \(rtStructFiles.count)")
        print("   📋 Total DICOM files: \(allDICOMFiles.count)")
        
        // Log RTStruct files found with details
        if !rtStructFiles.isEmpty {
            print("   🎯 RTStruct files discovered:")
            for rtFile in rtStructFiles {
                let size = (try? rtFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                print("      - \(rtFile.lastPathComponent) (\(size) bytes)")
            }
        } else {
            print("   ⚠️ No RTStruct files found in search paths")
        }
        
        return (ctFiles, rtStructFiles, allDICOMFiles)
    }
    
    // MARK: - Convenience Methods
    
    /// Get only CT image files
    static func getCTImageFiles() -> [URL] {
        let (ctFiles, _, _) = discoverDICOMFiles()
        return ctFiles
    }
    
    /// Get only RTStruct files
    static func getRTStructFiles() -> [URL] {
        let (_, rtStructFiles, _) = discoverDICOMFiles()
        
        // PRIORITIZE test_rtstruct2.dcm over test_rtstruct.dcm
        // Since test_rtstruct.dcm is reference-only (no geometry)
        var prioritizedFiles = rtStructFiles
        
        // Move test_rtstruct2.dcm to front if it exists
        if let test2Index = rtStructFiles.firstIndex(where: { $0.lastPathComponent == "test_rtstruct2.dcm" }) {
            let test2File = rtStructFiles[test2Index]
            prioritizedFiles.remove(at: test2Index)
            prioritizedFiles.insert(test2File, at: 0)
            print("🎯 PRIORITIZED test_rtstruct2.dcm (contains actual contour geometry)")
            print("   📂 Path: \(test2File.path)")
        } else {
            print("⚠️ test_rtstruct2.dcm not found - using available RTStruct files")
        }
        
        return prioritizedFiles
    }
    
    /// Get all DICOM files (CT + RTStruct)
    static func getAllDICOMFiles() -> [URL] {
        let (_, _, allFiles) = discoverDICOMFiles()
        return allFiles
    }
    
    // MARK: - File Validation
    
    /// Check if a file is a valid DICOM file by reading header
    static func isValidDICOMFile(_ fileURL: URL) -> Bool {
        do {
            let data = try Data(contentsOf: fileURL)
            
            // Check for DICOM preamble and prefix
            if data.count >= 132 {
                let prefixStart = 128
                let prefix = data.subdata(in: prefixStart..<prefixStart+4)
                let prefixString = String(data: prefix, encoding: .ascii)
                
                if prefixString == "DICM" {
                    return true
                }
            }
            
            // Fallback: check for common DICOM group tags at start
            if data.count >= 8 {
                let firstTag = data.subdata(in: 0..<4)
                let group = firstTag.withUnsafeBytes { $0.load(as: UInt16.self) }
                
                // Common DICOM groups: 0008, 0010, 0020, etc.
                if group == 0x0008 || group == 0x0010 || group == 0x0020 {
                    return true
                }
            }
            
            return false
            
        } catch {
            return false
        }
    }
    
    // MARK: - Dataset Creation
    
    /// Create a structured dataset from discovered files
    static func createDICOMFileSet() -> DICOMFileSet {
        let (ctFiles, rtStructFiles, _) = discoverDICOMFiles()
        
        // Generate dataset name from CT files
        let datasetName = generateDatasetName(from: ctFiles)
        
        return DICOMFileSet(
            ctFiles: ctFiles,
            rtStructFiles: rtStructFiles,
            datasetName: datasetName
        )
    }
    
    /// Generate a meaningful dataset name from CT files
    private static func generateDatasetName(from ctFiles: [URL]) -> String {
        if ctFiles.isEmpty {
            return "Unknown Dataset"
        }
        
        // Extract common patterns from CT filenames
        let firstFilename = ctFiles.first!.lastPathComponent
        
        // Look for patient/study identifiers
        if firstFilename.contains("2.16.840.1.114362") {
            return "Test CT Dataset"
        } else if firstFilename.contains("XAPMD") {
            return "XAPMD Patient Dataset"
        } else {
            return "CT Dataset (\(ctFiles.count) files)"
        }
    }
    
    // MARK: - Organization and Validation
    
    /// Print file organization for debugging
    static func printFileOrganization() {
        let (ctFiles, rtStructFiles, allFiles) = discoverDICOMFiles()
        
        print("📁 DICOM File Organization:")
        print("   📊 Total files: \(allFiles.count)")
        print("   🩻 CT images: \(ctFiles.count)")
        print("   📋 RTStruct files: \(rtStructFiles.count)")
        
        if !ctFiles.isEmpty {
            print("   📄 CT files:")
            for file in ctFiles.prefix(5) {
                print("      - \(file.lastPathComponent)")
            }
            if ctFiles.count > 5 {
                print("      ... and \(ctFiles.count - 5) more")
            }
        }
        
        if !rtStructFiles.isEmpty {
            print("   📋 RTStruct files:")
            for file in rtStructFiles {
                print("      - \(file.lastPathComponent)")
            }
        }
    }
    
    /// Organize files into datasets
    static func organizeDatasets() -> [String: DICOMFileSet] {
        let fileSet = createDICOMFileSet()
        return [fileSet.datasetName: fileSet]
    }
    
    /// Validation result structure
    struct ValidationResult {
        let isValid: Bool
        let issues: [String]
    }
    
    /// Validate a dataset
    static func validateDataset(_ dataset: DICOMFileSet) -> ValidationResult {
        var issues: [String] = []
        
        // Check if we have CT files
        guard !dataset.ctFiles.isEmpty else {
            let issue = "No CT files found"
            print("❌ Dataset validation failed: \(issue)")
            return ValidationResult(isValid: false, issues: [issue])
        }
        
        // Validate CT files are readable
        for ctFile in dataset.ctFiles.prefix(3) {
            if !isValidDICOMFile(ctFile) {
                let issue = "Invalid CT file \(ctFile.lastPathComponent)"
                issues.append(issue)
            }
        }
        
        // Validate RTStruct files if present
        for rtFile in dataset.rtStructFiles {
            if !isValidDICOMFile(rtFile) {
                let issue = "Invalid RTStruct file \(rtFile.lastPathComponent)"
                issues.append(issue)
            }
        }
        
        let isValid = issues.isEmpty
        if isValid {
            print("✅ Dataset validation passed: \(dataset.datasetName)")
        } else {
            print("❌ Dataset validation failed with \(issues.count) issues")
        }
        
        return ValidationResult(isValid: isValid, issues: issues)
    }
}

// MARK: - Extensions for Integration

extension DICOMViewerViewModel {
    
    /// Updated getDICOMFiles method for view model
    func getDICOMFilesFiltered() -> [URL] {
        return DICOMFileManager.getCTImageFiles()
    }
}

// MARK: - DISABLED EXTENSIONS (VolumeTestManager not available)

/*
extension VolumeTestManager {
    
    /// Updated volume loading with proper CT file filtering
    static func loadVolumeWithFiltering() {
        print("🧊 Loading volume with proper CT file filtering...")
        
        let ctFiles = DICOMFileManager.getCTImageFiles()
        
        guard !ctFiles.isEmpty else {
            print("❌ No CT files found for volume reconstruction")
            return
        }
        
        // Continue with existing volume loading logic using ctFiles
        print("✅ Found \(ctFiles.count) CT files for volume reconstruction")
    }
}
*/
