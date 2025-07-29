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
        
        do {
            let allFileURLs = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: bundlePath),
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            )
            
            var ctFiles: [URL] = []
            var rtStructFiles: [URL] = []
            var allDICOMFiles: [URL] = []
            
            for fileURL in allFileURLs {
                let fileType = classifyDICOMFile(fileURL)
                
                switch fileType {
                case .ctImage:
                    ctFiles.append(fileURL)
                    allDICOMFiles.append(fileURL)
                case .rtStruct:
                    rtStructFiles.append(fileURL)
                    allDICOMFiles.append(fileURL)
                case .unknown:
                    // Skip non-DICOM files
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
            
            // Log RTStruct files found
            if !rtStructFiles.isEmpty {
                print("   🎯 RTStruct files found:")
                for rtFile in rtStructFiles {
                    print("      - \(rtFile.lastPathComponent)")
                }
            }
            
            return (ctFiles, rtStructFiles, allDICOMFiles)
            
        } catch {
            print("❌ Error reading DICOM files: \(error)")
            return ([], [], [])
        }
    }
    
    /// Get only CT image files (for volume reconstruction)
    static func getCTImageFiles() -> [URL] {
        let (ctFiles, _, _) = discoverDICOMFiles()
        return ctFiles
    }
    
    /// Get only RTStruct files
    static func getRTStructFiles() -> [URL] {
        let (_, rtStructFiles, _) = discoverDICOMFiles()
        return rtStructFiles
    }
    
    /// Get all DICOM files (backwards compatibility)
    static func getAllDICOMFiles() -> [URL] {
        let (_, _, allFiles) = discoverDICOMFiles()
        return allFiles
    }
    
    // MARK: - Dataset Organization
    
    /// Organize files into male/female datasets
    static func organizeDatasets() -> [String: DICOMFileSet] {
        let (ctFiles, rtStructFiles, _) = discoverDICOMFiles()
        
        var datasets: [String: DICOMFileSet] = [:]
        
        // Group by dataset name (male/female/test)
        let maleCtFiles = ctFiles.filter { $0.lastPathComponent.lowercased().contains("male_ct") }
        let femaleCtFiles = ctFiles.filter { $0.lastPathComponent.lowercased().contains("female_ct") }
        let testCtFiles = ctFiles.filter { !$0.lastPathComponent.lowercased().contains("male_ct") &&
                                          !$0.lastPathComponent.lowercased().contains("female_ct") }
        
        let maleRtFiles = rtStructFiles.filter { $0.lastPathComponent.lowercased().contains("male_rtstruct") }
        let femaleRtFiles = rtStructFiles.filter { $0.lastPathComponent.lowercased().contains("female_rtstruct") }
        let testRtFiles = rtStructFiles.filter { !$0.lastPathComponent.lowercased().contains("male_rtstruct") &&
                                                !$0.lastPathComponent.lowercased().contains("female_rtstruct") }
        
        // Create datasets
        if !maleCtFiles.isEmpty {
            datasets["male"] = DICOMFileSet(
                ctFiles: maleCtFiles,
                rtStructFiles: maleRtFiles,
                datasetName: "Male Anatomy"
            )
        }
        
        if !femaleCtFiles.isEmpty {
            datasets["female"] = DICOMFileSet(
                ctFiles: femaleCtFiles,
                rtStructFiles: femaleRtFiles,
                datasetName: "Female Anatomy"
            )
        }
        
        // Test/current dataset
        if !testCtFiles.isEmpty {
            datasets["test"] = DICOMFileSet(
                ctFiles: testCtFiles,
                rtStructFiles: testRtFiles,
                datasetName: "Test Dataset"
            )
        }
        
        return datasets
    }
    
    // MARK: - Validation
    
    /// Validate dataset completeness
    static func validateDataset(_ dataset: DICOMFileSet) -> (isValid: Bool, issues: [String]) {
        var issues: [String] = []
        
        // Check for CT files
        if dataset.ctFiles.isEmpty {
            issues.append("No CT image files found")
        } else if dataset.ctFiles.count < 20 {
            issues.append("Suspiciously few CT slices (\(dataset.ctFiles.count))")
        }
        
        // Check for RTStruct files
        if dataset.rtStructFiles.isEmpty {
            issues.append("No RTStruct files found")
        } else if dataset.rtStructFiles.count > 5 {
            issues.append("Many RTStruct files found (\(dataset.rtStructFiles.count))")
        }
        
        // Check file accessibility
        for file in dataset.ctFiles + dataset.rtStructFiles {
            if !FileManager.default.fileExists(atPath: file.path) {
                issues.append("File not accessible: \(file.lastPathComponent)")
            }
        }
        
        let isValid = issues.isEmpty
        return (isValid, issues)
    }
    
    // MARK: - Debugging and Information
    
    /// Print detailed file organization information
    static func printFileOrganization() {
        print("\n📋 ===========================================")
        print("📋 DICOM File Organization Report")
        print("📋 ===========================================\n")
        
        let datasets = organizeDatasets()
        
        for (key, dataset) in datasets {
            print("📁 Dataset: \(dataset.datasetName) (\(key))")
            print("   🩻 CT Files: \(dataset.ctFiles.count)")
            
            for (index, file) in dataset.ctFiles.prefix(3).enumerated() {
                print("      \(index + 1). \(file.lastPathComponent)")
            }
            if dataset.ctFiles.count > 3 {
                print("      ... and \(dataset.ctFiles.count - 3) more CT files")
            }
            
            print("   📊 RTStruct Files: \(dataset.rtStructFiles.count)")
            for file in dataset.rtStructFiles {
                print("      - \(file.lastPathComponent)")
            }
            
            let validation = validateDataset(dataset)
            if validation.isValid {
                print("   ✅ Dataset validation: PASSED")
            } else {
                print("   ⚠️  Dataset validation issues:")
                for issue in validation.issues {
                    print("      - \(issue)")
                }
            }
            
            print("")
        }
        
        print("📋 ===========================================\n")
    }
    
    // MARK: - Migration Helper
    
    /// Helper for migrating from old file discovery method
    static func migrateFromLegacyFileDiscovery() -> [URL] {
        print("🔄 Migrating from legacy file discovery to filtered approach...")
        
        let ctFiles = getCTImageFiles()
        
        print("   📊 Legacy method would have found: \(getAllDICOMFiles().count) files")
        print("   🎯 Filtered method found: \(ctFiles.count) CT files")
        print("   ✅ Migration complete - using CT files only for volume reconstruction")
        
        return ctFiles
    }
}

// MARK: - Backwards Compatibility Extensions

extension DICOMTestManager {
    
    /// Updated getDICOMFiles method with filtering
    static func getDICOMFilesFiltered() -> [URL] {
        return DICOMFileManager.getCTImageFiles()
    }
}

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
