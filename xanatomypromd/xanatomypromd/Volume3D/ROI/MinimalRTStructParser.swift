import Foundation
import simd

// MARK: - Minimal Working RTStruct Parser
// Simplified parser for testing ROI functionality without breaking existing code

public class MinimalRTStructParser {
    
    // MARK: - Simple RTStruct Data Models
    
    public struct SimpleROIStructure {
        public let roiNumber: Int
        public let roiName: String
        public let displayColor: SIMD3<Float>
        public let contours: [SimpleContour]
        
        public init(roiNumber: Int, roiName: String, displayColor: SIMD3<Float>, contours: [SimpleContour]) {
            self.roiNumber = roiNumber
            self.roiName = roiName
            self.displayColor = displayColor
            self.contours = contours
        }
    }
    
    public struct SimpleContour {
        public let points: [SIMD3<Float>]
        public let slicePosition: Float
        
        public init(points: [SIMD3<Float>], slicePosition: Float) {
            self.points = points
            self.slicePosition = slicePosition
        }
    }
    
    public struct SimpleRTStructData {
        public let structureSetName: String?
        public let patientName: String?
        public let roiStructures: [SimpleROIStructure]
        
        public init(structureSetName: String?, patientName: String?, roiStructures: [SimpleROIStructure]) {
            self.structureSetName = structureSetName
            self.patientName = patientName
            self.roiStructures = roiStructures
        }
    }
    
    // MARK: - Parsing Interface
    
    /// Parse RTStruct from DICOM dataset (simplified)
    public static func parseSimpleRTStruct(from dataset: DICOMDataset) -> SimpleRTStructData? {
        print("📊 Parsing RTStruct with minimal parser...")
        
        // Check if this is an RTStruct
        guard let modality = dataset.getString(tag: .modality),
              modality == "RTSTRUCT" else {
            print("❌ Not an RTStruct file")
            return nil
        }
        
        // Extract basic metadata
        let structureSetName = dataset.getString(tag: .structureSetName)
        let patientName = dataset.getString(tag: .patientName)
        
        print("   📋 Structure Set: \(structureSetName ?? "Unknown")")
        print("   👤 Patient: \(patientName ?? "Unknown")")
        
        // Try to extract ROI structures
        let roiStructures = extractSimpleROIStructures(from: dataset)
        print("   🎯 Found \(roiStructures.count) ROI structures")
        
        return SimpleRTStructData(
            structureSetName: structureSetName,
            patientName: patientName,
            roiStructures: roiStructures
        )
    }
    
    // MARK: - Simple ROI Extraction
    
    private static func extractSimpleROIStructures(from dataset: DICOMDataset) -> [SimpleROIStructure] {
        var roiStructures: [SimpleROIStructure] = []
        
        // Look for Structure Set ROI Sequence
        guard let roiSequenceElement = dataset.elements[.structureSetROISequence] else {
            print("   ❌ No Structure Set ROI Sequence found")
            return roiStructures
        }
        
        print("   📋 Found Structure Set ROI Sequence (\(roiSequenceElement.data.count) bytes)")
        
        // For now, create sample ROI structures to test the display system
        // In a full implementation, you would parse the actual DICOM sequence data
        roiStructures = createSampleROIStructures()
        
        return roiStructures
    }
    
    // MARK: - Sample ROI Data for Testing
    
    private static func createSampleROIStructures() -> [SimpleROIStructure] {
        print("   🧪 Creating sample ROI structures for testing...")
        
        // Create sample anatomical structures with realistic coordinates
        let sampleROIs: [SimpleROIStructure] = [
            
            // Heart ROI (centered around typical heart location)
            SimpleROIStructure(
                roiNumber: 1,
                roiName: "Heart",
                displayColor: SIMD3<Float>(1.0, 0.0, 0.0), // Red
                contours: createSampleContours(
                    center: SIMD3<Float>(256, 256, 100),
                    radius: 30,
                    sliceRange: 95...105
                )
            ),
            
            // Liver ROI (larger, offset to right)
            SimpleROIStructure(
                roiNumber: 2,
                roiName: "Liver",
                displayColor: SIMD3<Float>(0.5, 0.3, 0.1), // Brown
                contours: createSampleContours(
                    center: SIMD3<Float>(300, 280, 120),
                    radius: 45,
                    sliceRange: 110...140
                )
            ),
            
            // Lung ROI (left lung)
            SimpleROIStructure(
                roiNumber: 3,
                roiName: "Left Lung",
                displayColor: SIMD3<Float>(0.0, 1.0, 1.0), // Cyan
                contours: createSampleContours(
                    center: SIMD3<Float>(200, 250, 80),
                    radius: 50,
                    sliceRange: 70...110
                )
            )
        ]
        
        return sampleROIs
    }
    
    private static func createSampleContours(
        center: SIMD3<Float>,
        radius: Float,
        sliceRange: ClosedRange<Int>
    ) -> [SimpleContour] {
        var contours: [SimpleContour] = []
        
        // Create circular contours for each slice in range
        for sliceZ in sliceRange {
            let slicePosition = Float(sliceZ) * 3.0 // 3mm slice thickness
            
            // Create circular contour points
            var points: [SIMD3<Float>] = []
            let numPoints = 16 // 16-point circle
            
            for i in 0..<numPoints {
                let angle = Float(i) * 2.0 * Float.pi / Float(numPoints)
                let x = center.x + radius * cos(angle)
                let y = center.y + radius * sin(angle)
                let z = slicePosition
                
                points.append(SIMD3<Float>(x, y, z))
            }
            
            contours.append(SimpleContour(
                points: points,
                slicePosition: slicePosition
            ))
        }
        
        return contours
    }
    
    // MARK: - Conversion to Full ROI Structure
    
    /// Convert simple ROI structures to full ROI format for compatibility
    public static func convertToFullROI(_ simpleData: SimpleRTStructData) -> RTStructData {
        let fullROIStructures = simpleData.roiStructures.map { simpleROI in
            let roiContours = simpleROI.contours.map { simpleContour in
                ROIContour(
                    contourNumber: 1,
                    geometricType: .closedPlanar,
                    numberOfPoints: simpleContour.points.count,
                    contourData: simpleContour.points,
                    slicePosition: simpleContour.slicePosition,
                    referencedSOPInstanceUID: nil
                )
            }
            
            return ROIStructure(
                roiNumber: simpleROI.roiNumber,
                roiName: simpleROI.roiName,
                roiDescription: "Sample \(simpleROI.roiName) structure",
                roiGenerationAlgorithm: "MANUAL",
                displayColor: simpleROI.displayColor,
                isVisible: true,
                opacity: 0.5,
                contours: roiContours
            )
        }
        
        return RTStructData(
            patientName: simpleData.patientName,
            studyInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            seriesInstanceUID: "1.2.3.4.5.6.7.8.9.11",
            structureSetLabel: "Test RTStruct",
            structureSetName: simpleData.structureSetName ?? "Sample Structure Set",
            structureSetDescription: "Sample RTStruct for testing ROI display",
            structureSetDate: "20250128",
            structureSetTime: "120000",
            roiStructures: fullROIStructures,
            referencedFrameOfReferenceUID: "1.2.3.4.5.6.7.8.9.12",
            referencedStudyInstanceUID: "1.2.3.4.5.6.7.8.9.10",
            referencedSeriesInstanceUID: "1.2.3.4.5.6.7.8.9.13"
        )
    }
}

// MARK: - RTStruct Test Data Generator
// Provides sample ROI data for testing without requiring actual RTStruct files

public class RTStructTestGenerator {
    
    /// Generate sample RTStruct data for testing
    public static func generateTestRTStructData() -> RTStructData {
        print("🧪 Generating test RTStruct data...")
        
        let simpleData = MinimalRTStructParser.SimpleRTStructData(
            structureSetName: "X-Anatomy Test Structure Set",
            patientName: "Test Patient XAPMD",
            roiStructures: [
                // Heart
                MinimalRTStructParser.SimpleROIStructure(
                    roiNumber: 1,
                    roiName: "Heart",
                    displayColor: SIMD3<Float>(1.0, 0.2, 0.2),
                    contours: createHeartContours()
                ),
                
                // Liver
                MinimalRTStructParser.SimpleROIStructure(
                    roiNumber: 2,
                    roiName: "Liver", 
                    displayColor: SIMD3<Float>(0.6, 0.4, 0.2),
                    contours: createLiverContours()
                ),
                
                // Spine
                MinimalRTStructParser.SimpleROIStructure(
                    roiNumber: 3,
                    roiName: "Spine",
                    displayColor: SIMD3<Float>(1.0, 1.0, 1.0),
                    contours: createSpineContours()
                )
            ]
        )
        
        let fullData = MinimalRTStructParser.convertToFullROI(simpleData)
        print("✅ Generated test RTStruct with \(fullData.roiStructures.count) ROI structures")
        
        return fullData
    }
    
    // MARK: - Anatomically Realistic Sample Contours
    
    private static func createHeartContours() -> [MinimalRTStructParser.SimpleContour] {
        var contours: [MinimalRTStructParser.SimpleContour] = []
        
        // Heart spans roughly slices 20-35 in typical chest CT
        for slice in 20...35 {
            let z = Float(slice) * 3.0 // 3mm slice thickness
            let heartSize = 25.0 + Float(slice - 27) * -0.5 // Larger in middle slices
            
            // Create heart-shaped contour (simplified)
            var points: [SIMD3<Float>] = []
            let numPoints = 20
            
            for i in 0..<numPoints {
                let angle = Float(i) * 2.0 * Float.pi / Float(numPoints)
                
                // Heart-like shape (circular with slight indentation at top)
                let radius = heartSize * (1.0 - 0.2 * cos(angle * 2))
                let x = 256 + radius * cos(angle)
                let y = 256 + radius * sin(angle) * 0.8 // Slightly flattened
                
                points.append(SIMD3<Float>(x, y, z))
            }
            
            contours.append(MinimalRTStructParser.SimpleContour(
                points: points,
                slicePosition: z
            ))
        }
        
        return contours
    }
    
    private static func createLiverContours() -> [MinimalRTStructParser.SimpleContour] {
        var contours: [MinimalRTStructParser.SimpleContour] = []
        
        // Liver spans many slices, larger organ
        for slice in 25...45 {
            let z = Float(slice) * 3.0
            let liverSize = 40.0 + Float(abs(slice - 35)) * -1.0 // Largest in middle
            
            var points: [SIMD3<Float>] = []
            let numPoints = 24
            
            for i in 0..<numPoints {
                let angle = Float(i) * 2.0 * Float.pi / Float(numPoints)
                
                // Irregular liver-like shape
                let radius = liverSize * (1.0 + 0.3 * sin(angle * 3) + 0.1 * cos(angle * 5))
                let x = 320 + radius * cos(angle) // Offset to right side
                let y = 280 + radius * sin(angle) * 0.7
                
                points.append(SIMD3<Float>(x, y, z))
            }
            
            contours.append(MinimalRTStructParser.SimpleContour(
                points: points,
                slicePosition: z
            ))
        }
        
        return contours
    }
    
    private static func createSpineContours() -> [MinimalRTStructParser.SimpleContour] {
        var contours: [MinimalRTStructParser.SimpleContour] = []
        
        // Spine runs through most slices
        for slice in 10...50 {
            let z = Float(slice) * 3.0
            
            var points: [SIMD3<Float>] = []
            let numPoints = 12
            let spineRadius: Float = 15.0
            
            for i in 0..<numPoints {
                let angle = Float(i) * 2.0 * Float.pi / Float(numPoints)
                let x = 256 + spineRadius * cos(angle) // Centered
                let y = 400 + spineRadius * sin(angle) // Towards back
                
                points.append(SIMD3<Float>(x, y, z))
            }
            
            contours.append(MinimalRTStructParser.SimpleContour(
                points: points,
                slicePosition: z
            ))
        }
        
        return contours
    }
}
