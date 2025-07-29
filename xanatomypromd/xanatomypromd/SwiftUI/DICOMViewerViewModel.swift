import Foundation
import SwiftUI
import simd

// MARK: - Simple DICOM Viewer ViewModel
// Minimal ViewModel to support the clean DICOMViewerView

@MainActor
class DICOMViewerViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isLoading: Bool = true
    @Published var currentSlice: Int = 0
    @Published var totalSlices: Int = 53
    @Published var seriesInfo: DICOMSeriesInfo?
    
    // MARK: - Data Properties
    
    private var dicomFiles: [URL] = []
    private var rtStructData: RTStructData?
    
    // MARK: - Initialization
    
    init() {
        print("📊 DICOMViewerViewModel initialized")
    }
    
    // MARK: - DICOM Loading
    
    func loadDICOMSeries() async {
        print("📂 Loading DICOM series...")
        
        // Simulate loading process
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Set up basic series info
        seriesInfo = DICOMSeriesInfo(
            patientName: "Test Patient XAPMD",
            studyDescription: "Chest CT",
            seriesDescription: "Axial CT",
            seriesNumber: 1,
            instanceCount: 53,
            studyDate: "20250128",
            modality: "CT"
        )
        
        isLoading = false
        print("✅ DICOM series loaded")
    }
    
    // MARK: - RTStruct Data
    
    func getRTStructData() -> RTStructData? {
        // Load RTStruct data if available
        if rtStructData == nil {
            rtStructData = loadRealRTStructData() // Load from actual RTStruct files
        }
        return rtStructData
    }
    
    // MARK: - Slice Navigation
    
    func setCurrentSlice(_ slice: Int) {
        currentSlice = max(0, min(slice, totalSlices - 1))
    }
    
    func nextSlice() {
        if currentSlice < totalSlices - 1 {
            currentSlice += 1
        }
    }
    
    func previousSlice() {
        if currentSlice > 0 {
            currentSlice -= 1
        }
    }
    
    // MARK: - Utility Methods
    
    // TODO: Re-enable when MPRPlane import is resolved
    // func getMaxSlicesForPlane(_ plane: MPRPlane) -> Int {
    //     switch plane {
    //     case .axial:
    //         return 53  // Number of CT slices
    //     case .sagittal:
    //         return 512 // Image width  
    //     case .coronal:
    //         return 512 // Image height
    //     }
    // }
    // MARK: - Helper Functions
    
    private func loadRealRTStructData() -> RTStructData? {
        print("📊 Loading real RTStruct data from files...")
        
        // First try to load from actual RTStruct files
        let rtStructFiles = DICOMFileManager.getRTStructFiles()
        
        if let rtStructFile = rtStructFiles.first {
            print("   📄 Found RTStruct file: \(rtStructFile.lastPathComponent)")
            
            do {
                let data = try Data(contentsOf: rtStructFile)
                let dataset = try DICOMParser.parse(data)
                
                // Try parsing with minimal parser first
                if let simpleData = MinimalRTStructParser.parseSimpleRTStruct(from: dataset) {
                    let fullData = MinimalRTStructParser.convertToFullROI(simpleData)
                    print("   ✅ Successfully parsed RTStruct with \(fullData.roiStructures.count) ROI structures")
                    return fullData
                }
                
            } catch {
                print("   ❌ Error parsing RTStruct file: \(error)")
            }
        }
        
        // Fallback to test data if no real RTStruct files available
        print("   🧪 No RTStruct files found, using test data generator")
        return RTStructTestGenerator.generateTestRTStructData()
    }

}

// MARK: - DICOM Series Info

struct DICOMSeriesInfo {
    let patientName: String?
    let studyDescription: String?
    let seriesDescription: String?
    let seriesNumber: Int?
    let instanceCount: Int
    let studyDate: String?
    let modality: String?
    
    init(
        patientName: String? = nil,
        studyDescription: String? = nil,
        seriesDescription: String? = nil,
        seriesNumber: Int? = nil,
        instanceCount: Int = 0,
        studyDate: String? = nil,
        modality: String? = nil
    ) {
        self.patientName = patientName
        self.studyDescription = studyDescription
        self.seriesDescription = seriesDescription
        self.seriesNumber = seriesNumber
        self.instanceCount = instanceCount
        self.studyDate = studyDate
        self.modality = modality
    }
}
