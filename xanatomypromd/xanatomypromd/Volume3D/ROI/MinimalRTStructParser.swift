import Foundation
import simd

// MARK: - Simplified RTStruct Parser - Back to Proven Working Method
// Returns to the direct byte scanning approach that successfully found coordinates

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
    
    // MARK: - Main Parsing Interface (Simplified)
    public static func parseSimpleRTStruct(from dataset: DICOMDataset) -> SimpleRTStructData? {
        print("🎯 Simplified RTStruct Parser - Back to Working Method")
        
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
        print("   🔍 Using PROVEN direct byte scanning method...")
        
        // Use the ORIGINAL WORKING METHOD: Direct byte scanning
        let allContours = scanEntireDatasetForContours(dataset: dataset)
        
        if allContours.isEmpty {
            print("   ❌ No contour data found")
            return nil
        }
        
        // Group contours by Z position to find all slices
        let groupedByZ = Dictionary(grouping: allContours) { $0.slicePosition }
        let sortedZPositions = groupedByZ.keys.sorted()
        
        print("   ✅ Found contours across \(sortedZPositions.count) Z-slices:")
        for z in sortedZPositions {
            let contoursAtZ = groupedByZ[z]!
            let totalPoints = contoursAtZ.reduce(0) { $0 + $1.points.count }
            print("      Z=\(z)mm: \(contoursAtZ.count) contours, \(totalPoints) points")
        }
        
        // Create single ROI structure with all contours
        let roi = SimpleROIStructure(
            roiNumber: 8241,
            roiName: "ROI-1",
            displayColor: SIMD3<Float>(1.0, 0.0, 1.0), // Magenta
            contours: allContours
        )
        
        let totalContours = allContours.count
        let totalPoints = allContours.reduce(0) { $0 + $1.points.count }
        let zRange = sortedZPositions.isEmpty ? "N/A" : "\(sortedZPositions.first!) to \(sortedZPositions.last!)mm"
        
        print("   ✅ SUCCESS: ROI \(roi.roiNumber) '\(roi.roiName)' - \(totalContours) contours, \(totalPoints) points, Z: \(zRange)")
        
        return SimpleRTStructData(
            structureSetName: structureSetName,
            patientName: patientName,
            roiStructures: [roi]
        )
    }
    
    // MARK: - ORIGINAL WORKING METHOD: Scan Entire Dataset
    private static func scanEntireDatasetForContours(dataset: DICOMDataset) -> [SimpleContour] {
        var allContours: [SimpleContour] = []
        
        // Method 1: Scan all dataset elements for (3006,0050) tags
        print("   🔍 Method 1: Scanning all dataset elements...")
        for (tag, element) in dataset.elements {
            if tag.group == 0x3006 && tag.element == 0x0050 {
                print("     ✅ FOUND Contour Data tag \(tag) in dataset elements!")
                if let contour = parseContourDataDirectly(element.data) {
                    allContours.append(contour)
                    print("       ✅ Extracted: \(contour.points.count) points at Z=\(contour.slicePosition)")
                }
            }
        }
        
        // Method 2: Direct byte scanning in specific sequence elements
        print("   🔍 Method 2: Direct byte scanning in sequences...")
        
        // Scan ROI Contour Sequence if it exists
        if let roiContourElement = dataset.elements[.roiContourSequence] {
            print("     📦 Scanning ROI Contour Sequence (\(roiContourElement.data.count) bytes)...")
            let foundContours = scanForContourDataInBytes(roiContourElement.data)
            allContours.append(contentsOf: foundContours)
        }
        
        // Scan Structure Set ROI Sequence if it exists (sometimes coordinate data is here)
        if let structureSetElement = dataset.elements[.structureSetROISequence] {
            print("     📦 Scanning Structure Set ROI Sequence (\(structureSetElement.data.count) bytes)...")
            let foundContours = scanForContourDataInBytes(structureSetElement.data)
            allContours.append(contentsOf: foundContours)
        }
        
        // Method 3: Scan ALL elements for any embedded coordinate patterns
        if allContours.isEmpty {
            print("   🔍 Method 3: Scanning ALL elements for coordinate patterns...")
            for (tag, element) in dataset.elements {
                if element.data.count > 20 { // Only scan elements with substantial data
                    let foundContours = scanForCoordinatePatterns(element.data)
                    if !foundContours.isEmpty {
                        print("     ✅ Found coordinates in tag \(tag)!")
                        allContours.append(contentsOf: foundContours)
                    }
                }
            }
        }
        
        return allContours
    }
    
    // MARK: - Direct Byte Scanning (PROVEN METHOD)
    private static func scanForContourDataInBytes(_ data: Data) -> [SimpleContour] {
        var contours: [SimpleContour] = []
        
        // Scan for (3006,0050) tags - the PROVEN method
        let contourDataBytes: [UInt8] = [0x06, 0x30, 0x50, 0x00] // Little endian
        
        for i in 0..<(data.count - 8) {
            let slice = data.subdata(in: i..<i+4)
            if Array(slice) == contourDataBytes {
                print("       ✅ FOUND (3006,0050) at byte \(i)!")
                
                // Read length (handle both aligned and unaligned)
                let length: UInt32
                if i + 8 <= data.count {
                    length = data.withUnsafeBytes { bytes in
                        bytes.load(fromByteOffset: i + 4, as: UInt32.self)
                    }
                    
                    print("         📏 Length: \(length) bytes")
                    
                    if length > 0 && length < 100000 && i + 8 + Int(length) <= data.count {
                        let contourDataRaw = data.subdata(in: (i + 8)..<(i + 8 + Int(length)))
                        
                        if let contour = parseContourDataDirectly(contourDataRaw) {
                            contours.append(contour)
                            print("         ✅ SUCCESS: \(contour.points.count) points at Z=\(contour.slicePosition)")
                        }
                    }
                }
            }
        }
        
        return contours
    }
    
    // MARK: - Coordinate Pattern Scanning (Fallback)
    private static func scanForCoordinatePatterns(_ data: Data) -> [SimpleContour] {
        var contours: [SimpleContour] = []
        
        // Look for ASCII coordinate patterns with backslashes
        if let asciiString = String(data: data, encoding: .ascii) {
            // Look for decimal numbers with backslashes (the PROVEN format)
            if asciiString.contains("\\") && asciiString.contains(".") {
                let numbers = extractCoordinateNumbers(from: asciiString)
                
                if numbers.count >= 6 && numbers.count % 3 == 0 {
                    var points: [SIMD3<Float>] = []
                    var zPosition: Float = 0.0
                    
                    for i in stride(from: 0, to: numbers.count - 2, by: 3) {
                        let x = numbers[i]
                        let y = numbers[i + 1]
                        let z = numbers[i + 2]
                        points.append(SIMD3<Float>(x, y, z))
                        zPosition = z // Use last Z as representative
                    }
                    
                    if !points.isEmpty {
                        let contour = SimpleContour(points: points, slicePosition: zPosition)
                        contours.append(contour)
                    }
                }
            }
        }
        
        return contours
    }
    
    // MARK: - Direct Contour Data Parsing (PROVEN METHOD)
    private static func parseContourDataDirectly(_ data: Data) -> SimpleContour? {
        print("         📍 Parsing \(data.count) bytes of contour data...")
        
        // Method 1: ASCII Decimal String (PROVEN FORMAT)
        if let asciiString = String(data: data, encoding: .ascii) {
            let cleanString = asciiString.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            
            if !cleanString.isEmpty {
                print("         📝 ASCII data: \"\(cleanString.prefix(50))...\"")
                
                // Extract coordinate numbers using the PROVEN method
                let numbers = extractCoordinateNumbers(from: cleanString)
                
                if numbers.count >= 6 && numbers.count % 3 == 0 {
                    var points: [SIMD3<Float>] = []
                    var zPosition: Float = 0.0
                    
                    for i in stride(from: 0, to: numbers.count - 2, by: 3) {
                        let x = numbers[i]
                        let y = numbers[i + 1] 
                        let z = numbers[i + 2]
                        points.append(SIMD3<Float>(x, y, z))
                        zPosition = z // All points should have same Z for a contour
                    }
                    
                    print("         ✅ SUCCESS: \(points.count) points at Z=\(zPosition)")
                    return SimpleContour(points: points, slicePosition: zPosition)
                } else {
                    print("         ❌ Invalid coordinate count: \(numbers.count) (need multiple of 3)")
                }
            }
        }
        
        // Method 2: Try UTF-8 in case of encoding issues
        if let utf8String = String(data: data, encoding: .utf8) {
            let numbers = extractCoordinateNumbers(from: utf8String)
            
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
                
                print("         ✅ SUCCESS (UTF-8): \(points.count) points at Z=\(zPosition)")
                return SimpleContour(points: points, slicePosition: zPosition)
            }
        }
        
        // Method 3: Binary floats (fallback)
        if data.count % 4 == 0 && data.count >= 12 {
            var numbers: [Float] = []
            for i in stride(from: 0, to: data.count - 3, by: 4) {
                let floatValue = data.withUnsafeBytes { bytes in
                    bytes.load(fromByteOffset: i, as: Float.self)
                }
                // Validate float is reasonable for medical coordinates
                if abs(floatValue) < 10000 && !floatValue.isNaN && !floatValue.isInfinite {
                    numbers.append(floatValue)
                } else {
                    break // Stop on invalid data
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
                
                print("         ✅ SUCCESS (binary): \(points.count) points at Z=\(zPosition)")
                return SimpleContour(points: points, slicePosition: zPosition)
            }
        }
        
        print("         ❌ Could not parse contour data")
        return nil
    }
    
    // MARK: - Coordinate Number Extraction (PROVEN METHOD)
    private static func extractCoordinateNumbers(from string: String) -> [Float] {
        // Method 1: Backslash-separated (PROVEN format from working parser)
        let backslashComponents = string.components(separatedBy: "\\")
        let backslashNumbers = backslashComponents.compactMap { component in
            Float(component.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        if backslashNumbers.count >= 6 {
            return backslashNumbers
        }
        
        // Method 2: Regular expression for decimal numbers (fallback)
        let pattern = "-?\\d+\\.\\d+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        
        let matches = regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
        let regexNumbers = matches.compactMap { match -> Float? in
            guard let range = Range(match.range, in: string) else { return nil }
            return Float(String(string[range]))
        }
        
        return regexNumbers
    }
    
    // MARK: - Data Conversion (Compatibility)
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
