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
    
    // MARK: - Test ROI Contour Generators
    
    private func createTestHeartContours() -> [ROIContour] {
        var contours: [ROIContour] = []
        
        // Heart: roughly centered in chest, oval shaped
        let heartCenter = SIMD3<Float>(256, 300, 75) // Center-left of chest
        
        // Create contours for multiple axial slices through heart
        for slice in 20...35 {
            let z = Float(slice) * 3.0
            let distanceFromCenter = abs(z - heartCenter.z)
            let maxDistance: Float = 24.0 // Heart spans ~8 slices
            
            // Heart gets smaller at edges
            let sizeMultiplier = max(0.2, 1.0 - (distanceFromCenter / maxDistance))
            
            if sizeMultiplier > 0.1 {
                var points: [SIMD3<Float>] = []
                let numPoints = 16
                let heartRadiusX: Float = 40.0 * sizeMultiplier
                let heartRadiusY: Float = 30.0 * sizeMultiplier
                
                for i in 0..<numPoints {
                    let angle = Float(i) * 2.0 * Float.pi / Float(numPoints)
                    
                    // Heart-like shape with slight indentation
                    let radius = heartRadiusX * (1.0 + 0.1 * sin(angle * 2))
                    let x = heartCenter.x + radius * cos(angle)
                    let y = heartCenter.y + heartRadiusY * sin(angle)
                    
                    points.append(SIMD3<Float>(x, y, z))
                }
                
                contours.append(ROIContour(
                    contourNumber: contours.count + 1,
                    geometricType: .closedPlanar,
                    numberOfPoints: points.count,
                    contourData: points,
                    slicePosition: z
                ))
            }
        }
        
        return contours
    }
    
    private func createTestLiverContours() -> [ROIContour] {
        var contours: [ROIContour] = []
        
        // Liver: large, irregular organ in right abdomen
        for slice in 25...40 {
            let z = Float(slice) * 3.0
            
            var points: [SIMD3<Float>] = []
            let numPoints = 20
            let liverSize: Float = 60.0 - Float(abs(slice - 32)) * 2.0 // Largest in middle
            
            for i in 0..<numPoints {
                let angle = Float(i) * 2.0 * Float.pi / Float(numPoints)
                
                // Irregular liver-like shape
                let radius = liverSize * (1.0 + 0.3 * sin(angle * 3) + 0.1 * cos(angle * 5))
                let x = 320 + radius * cos(angle) // Offset to right side
                let y = 280 + radius * sin(angle) * 0.7
                
                points.append(SIMD3<Float>(x, y, z))
            }
            
            contours.append(ROIContour(
                contourNumber: contours.count + 1,
                geometricType: .closedPlanar,
                numberOfPoints: points.count,
                contourData: points,
                slicePosition: z
            ))
        }
        
        return contours
    }
    
    private func createTestLungContours() -> [ROIContour] {
        var contours: [ROIContour] = []
        
        // Left lung: large, curved organ
        for slice in 15...45 {
            let z = Float(slice) * 3.0
            
            var points: [SIMD3<Float>] = []
            let numPoints = 18
            let lungSize: Float = 50.0 - Float(abs(slice - 30)) * 1.5 // Largest in middle
            
            for i in 0..<numPoints {
                let angle = Float(i) * 2.0 * Float.pi / Float(numPoints)
                
                // Lung-like curved shape
                let radius = lungSize * (1.0 + 0.2 * sin(angle * 2))
                let x = 180 + radius * cos(angle) // Left side
                let y = 250 + radius * sin(angle) * 1.2 // Taller than wide
                
                points.append(SIMD3<Float>(x, y, z))
            }
            
            contours.append(ROIContour(
                contourNumber: contours.count + 1,
                geometricType: .closedPlanar,
                numberOfPoints: points.count,
                contourData: points,
                slicePosition: z
            ))
        }
        
        return contours
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
        
        // Create test RTStruct data using our MinimalRTStructParser
        let testROIStructures = [
            // Heart ROI
            ROIStructure(
                roiNumber: 1,
                roiName: "Heart",
                roiDescription: "Test cardiac structure",
                roiGenerationAlgorithm: "MANUAL",
                displayColor: SIMD3<Float>(1.0, 0.0, 0.0),
                isVisible: true,
                opacity: 0.7,
                contours: createTestHeartContours()
            ),
            // Liver ROI
            ROIStructure(
                roiNumber: 2,
                roiName: "Liver",
                roiDescription: "Test hepatic structure",
                roiGenerationAlgorithm: "MANUAL",
                displayColor: SIMD3<Float>(0.6, 0.4, 0.2),
                isVisible: true,
                opacity: 0.7,
                contours: createTestLiverContours()
            ),
            // Lung ROI
            ROIStructure(
                roiNumber: 3,
                roiName: "Left Lung",
                roiDescription: "Test pulmonary structure",
                roiGenerationAlgorithm: "MANUAL",
                displayColor: SIMD3<Float>(0.0, 0.8, 0.8),
                isVisible: true,
                opacity: 0.7,
                contours: createTestLungContours()
            )
        ]
        
        return RTStructData(
            structureSetName: "Test Structure Set",
            structureSetDescription: "Generated test data for ROI visualization",
            patientName: "Test Patient",
            studyInstanceUID: "Test.Study.UID",
            seriesInstanceUID: "Test.Series.UID",
            frameOfReferenceUID: "Test.Frame.UID",
            roiStructures: testROIStructures
        )
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
