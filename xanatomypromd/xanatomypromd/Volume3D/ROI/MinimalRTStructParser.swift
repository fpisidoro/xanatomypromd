import Foundation
import simd

// MARK: - Simple RTStruct Parser - Direct Approach
public class MinimalRTStructParser {
    
    // MARK: - Data Models
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
    
    // MARK: - Main Parsing Interface
    public static func parseSimpleRTStruct(from dataset: DICOMDataset) -> SimpleRTStructData? {
        print("🎯 RTStruct Parser - Direct Approach")
        
        // Verify RTStruct modality
        guard let modality = dataset.getString(tag: .modality),
              modality == "RTSTRUCT" else {
            print("❌ Not an RTStruct file")
            return nil
        }
        
        // Extract metadata
        let structureSetName = dataset.getString(tag: .structureSetName)
        let patientName = dataset.getString(tag: .patientName)
        
        print("   📋 Structure Set: \(structureSetName ?? "Unknown")")
        print("   👤 Patient: \(patientName ?? "Unknown")")
        
        // Direct parsing approach
        let roiStructures = parseROIStructuresDirectly(dataset: dataset)
        
        if roiStructures.isEmpty {
            print("   ❌ No ROI structures found")
            return nil
        }
        
        print("   ✅ Successfully parsed \(roiStructures.count) ROI structures")
        return SimpleRTStructData(
            structureSetName: structureSetName,
            patientName: patientName,
            roiStructures: roiStructures
        )
    }
    
    // MARK: - Direct ROI Parsing
    private static func parseROIStructuresDirectly(dataset: DICOMDataset) -> [SimpleROIStructure] {
        print("   🔍 Direct search for Contour Data (3006,0050) in raw DICOM data...")
        
        // Get all raw DICOM data for direct byte scanning
        var allContourData: [SimpleContour] = []
        
        // Scan all elements for Contour Data tags
        for (tag, element) in dataset.elements {
            if tag.group == 0x3006 && tag.element == 0x0050 {
                print("   ✅ FOUND Contour Data tag directly in elements!")
                if let contour = parseContourDataDirectly(element.data) {
                    allContourData.append(contour)
                }
            }
        }
        
        // Also scan raw data of sequence elements
        if let roiContourElement = dataset.elements[.roiContourSequence] {
            print("   🔍 Scanning ROI Contour Sequence raw data...")
            let foundContours = scanForContourDataInBytes(roiContourElement.data)
            allContourData.append(contentsOf: foundContours)
        }
        
        if allContourData.isEmpty {
            print("   ❌ No contour data found")
            return []
        }
        
        print("   ✅ Found \(allContourData.count) contours total")
        
        // Create ROI structures
        var roiStructures: [SimpleROIStructure] = []
        
        // Group contours by approximate Z position (same ROI)
        let groupedContours = Dictionary(grouping: allContourData) { contour in
            Int(contour.slicePosition / 10.0) // Group by 10mm chunks
        }
        
        for (index, (_, contours)) in groupedContours.enumerated() {
            let roi = SimpleROIStructure(
                roiNumber: 8241 + index,
                roiName: "ROI-\(index + 1)",
                displayColor: generateROIColor(for: index),
                contours: contours
            )
            roiStructures.append(roi)
            
            print("   📊 Created ROI \(roi.roiNumber): '\(roi.roiName)' with \(contours.count) contours")
        }
        
        return roiStructures
    }
    
    // MARK: - Direct Byte Scanning for Contour Data
    private static func scanForContourDataInBytes(_ data: Data) -> [SimpleContour] {
        print("     🔍 Byte-level scan for (3006,0050) in \(data.count) bytes...")
        
        var contours: [SimpleContour] = []
        let targetBytes: [UInt8] = [0x06, 0x30, 0x50, 0x00] // (3006,0050) in little endian
        
        for i in 0..<(data.count - 8) {
            // Check for Contour Data tag
            let slice = data.subdata(in: i..<i+4)
            if Array(slice) == targetBytes {
                print("     ✅ FOUND (3006,0050) at byte \(i)!")
                
                // Read length (next 4 bytes)
                let length = data.withUnsafeBytes { bytes in
                    bytes.load(fromByteOffset: i + 4, as: UInt32.self)
                }
                
                if length > 0 && length < 100000 && i + 8 + Int(length) <= data.count {
                    let contourDataRaw = data.subdata(in: (i + 8)..<(i + 8 + Int(length)))
                    
                    if let contour = parseContourDataDirectly(contourDataRaw) {
                        contours.append(contour)
                        print("     ✅ Parsed contour with \(contour.points.count) points at Z=\(contour.slicePosition)")
                    }
                }
            }
        }
        
        return contours
    }
    
    // MARK: - Direct Contour Data Parsing
    private static func parseContourDataDirectly(_ data: Data) -> SimpleContour? {
        print("       📍 Parsing \(data.count) bytes of contour data...")
        
        // Method 1: ASCII Decimal String (most common in RTStruct)
        if let asciiString = String(data: data, encoding: .ascii) {
            let cleanString = asciiString.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            
            if !cleanString.isEmpty {
                print("       📝 ASCII data: \"\(cleanString.prefix(100))...\"")
                
                // Parse backslash-separated coordinates
                let components = cleanString.components(separatedBy: "\\")
                let numbers = components.compactMap { Float($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                
                if numbers.count >= 6 && numbers.count % 3 == 0 {
                    var points: [SIMD3<Float>] = []
                    var zPosition: Float = 0.0
                    
                    for i in stride(from: 0, to: numbers.count - 2, by: 3) {
                        let x = numbers[i]
                        let y = numbers[i + 1] 
                        let z = numbers[i + 2]
                        points.append(SIMD3<Float>(x, y, z))
                        zPosition = z
                    }
                    
                    print("       ✅ SUCCESS: \(points.count) points at Z=\(zPosition)")
                    return SimpleContour(points: points, slicePosition: zPosition)
                }
            }
        }
        
        // Method 2: Binary floats
        if data.count % 4 == 0 && data.count >= 12 {
            var numbers: [Float] = []
            for i in stride(from: 0, to: data.count - 3, by: 4) {
                let floatValue = data.withUnsafeBytes { bytes in
                    bytes.load(fromByteOffset: i, as: Float.self)
                }
                if abs(floatValue) < 10000 && !floatValue.isNaN {
                    numbers.append(floatValue)
                } else {
                    break // Invalid binary data
                }
            }
            
            if numbers.count >= 6 && numbers.count % 3 == 0 {
                var points: [SIMD3<Float>] = []
                var zPosition: Float = 0.0
                
                for i in stride(from: 0, to: numbers.count - 2, by: 3) {
                    let x = numbers[i]
                    let y = numbers[i + 1]
                    let z = numbers[i + 2]
                    points.append(SIMD3<Float>(x, y, z))
                    zPosition = z
                }
                
                print("       ✅ SUCCESS (binary): \(points.count) points at Z=\(zPosition)")
                return SimpleContour(points: points, slicePosition: zPosition)
            }
        }
        
        print("       ❌ Could not parse contour data")
        return nil
    }
    
    // MARK: - Utility Functions
    private static func generateROIColor(for index: Int) -> SIMD3<Float> {
        let colors: [SIMD3<Float>] = [
            SIMD3<Float>(1.0, 0.0, 1.0), // Magenta
            SIMD3<Float>(0.0, 1.0, 0.0), // Green
            SIMD3<Float>(0.0, 0.0, 1.0), // Blue
            SIMD3<Float>(1.0, 1.0, 0.0), // Yellow
            SIMD3<Float>(1.0, 0.0, 0.0), // Red
            SIMD3<Float>(0.0, 1.0, 1.0), // Cyan
        ]
        return colors[index % colors.count]
    }
    
    // MARK: - Data Conversion
    public static func convertToFullROI(_ simpleData: SimpleRTStructData) -> RTStructData {
        print("🔄 Converting SimpleRTStructData to full RTStructData format...")
        
        let fullROIStructures = simpleData.roiStructures.map { simpleROI in
            let fullContours = simpleROI.contours.map { simpleContour in
                ROIContour(
                    contourNumber: 1,
                    geometricType: .closedPlanar,
                    numberOfPoints: simpleContour.points.count,
                    contourData: simpleContour.points,
                    slicePosition: simpleContour.slicePosition
                )
            }
            
            return ROIStructure(
                roiNumber: simpleROI.roiNumber,
                roiName: simpleROI.roiName,
                roiDescription: "Parsed from RTStruct file",
                roiGenerationAlgorithm: "MANUAL",
                displayColor: simpleROI.displayColor,
                isVisible: true,
                opacity: 0.7,
                contours: fullContours
            )
        }
        
        let fullData = RTStructData(
            patientName: simpleData.patientName,
            studyInstanceUID: "Unknown",
            seriesInstanceUID: "Unknown",
            structureSetLabel: simpleData.structureSetName,
            structureSetName: simpleData.structureSetName ?? "Unknown Structure Set",
            structureSetDescription: "Loaded from RTStruct DICOM file",
            roiStructures: fullROIStructures,
            referencedFrameOfReferenceUID: "Unknown"
        )
        
        print("✅ Conversion complete: \(fullROIStructures.count) ROI structures")
        return fullData
    }
}
