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
    
    // MARK: - ENHANCED SCANNING: Find ALL Contours in Sequence Structures
    private static func scanEntireDatasetForContours(dataset: DICOMDataset) -> [SimpleContour] {
        var allContours: [SimpleContour] = []
        
        print("   🔍 Method 1: Scanning for direct (3006,0050) elements...")
        for (tag, element) in dataset.elements {
            if tag.group == 0x3006 && tag.element == 0x0050 {
                print("     ✅ FOUND Contour Data tag \(tag) in dataset elements!")
                if let contour = parseContourDataDirectly(element.data) {
                    allContours.append(contour)
                    print("       ✅ Extracted: \(contour.points.count) points at Z=\(contour.slicePosition)")
                }
            }
        }
        
        print("   🔍 Method 2: Deep parsing of ROI Contour Sequence structures...")
        if let roiContourElement = dataset.elements[.roiContourSequence] {
            print("     📦 Processing ROI Contour Sequence (\(roiContourElement.data.count) bytes)...")
            let sequenceContours = parseROIContourSequenceForAllContours(roiContourElement.data)
            print("     📊 Found \(sequenceContours.count) contours in sequence structures")
            
            // Only add contours that are truly different (different Z-positions)
            for contour in sequenceContours {
                let isDifferent = !allContours.contains { existing in
                    abs(existing.slicePosition - contour.slicePosition) < 0.01
                }
                if isDifferent {
                    allContours.append(contour)
                    print("       🆕 Added unique contour: \(contour.points.count) points at Z=\(contour.slicePosition)")
                }
            }
        }
        
        return allContours
    }
    
    // MARK: - ROI Contour Sequence Parser (Multiple Contours)
    private static func parseROIContourSequenceForAllContours(_ data: Data) -> [SimpleContour] {
        var contours: [SimpleContour] = []
        
        print("       🔍 Parsing ROI Contour Sequence for multiple contours...")
        
        // Parse sequence items manually to find all contour data
        var offset = 0
        while offset < data.count - 8 {
            // Look for Item tags (FFFE,E000)
            let itemTagBytes: [UInt8] = [0xFE, 0xFF, 0x00, 0xE0] // Item tag
            
            // Find next item
            var itemFound = false
            for i in offset..<(data.count - 8) {
                let slice = data.subdata(in: i..<i+4)
                if Array(slice) == itemTagBytes {
                    print("         📎 Found sequence item at offset \(i)")
                    
                    // Read item length
                    let itemLength = data.withUnsafeBytes { bytes in
                        bytes.load(fromByteOffset: i + 4, as: UInt32.self)
                    }
                    
                    var itemEndOffset: Int
                    if itemLength == 0xFFFFFFFF {
                        // Undefined length - find delimiter
                        itemEndOffset = findSequenceDelimiter(in: data, startingAt: i + 8) ?? (data.count - 1)
                        print("           🔄 Undefined length item, delimiter at \(itemEndOffset)")
                    } else {
                        itemEndOffset = i + 8 + Int(itemLength)
                        print("           📏 Defined length item: \(itemLength) bytes")
                    }
                    
                    if itemEndOffset <= data.count {
                        let itemData = data.subdata(in: (i + 8)..<itemEndOffset)
                        
                        // Scan this item for contour data
                        let itemContours = scanSingleItemForContours(itemData)
                        if !itemContours.isEmpty {
                            print("           ✅ Found \(itemContours.count) contours in this item")
                            contours.append(contentsOf: itemContours)
                        }
                        
                        offset = itemEndOffset
                        itemFound = true
                        break
                    }
                }
            }
            
            if !itemFound {
                break
            }
        }
        
        return contours
    }
    
    // MARK: - Single Item Contour Scanner
    private static func scanSingleItemForContours(_ data: Data) -> [SimpleContour] {
        var contours: [SimpleContour] = []
        
        print("             🔍 Scanning item content (\(data.count) bytes) for contour data...")
        
        // DEBUG: Show hex dump of item content
        let hexDump = data.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " ")
        print("               🔎 Hex dump: \(hexDump)")
        
        // Look for (3006,0050) Contour Data tags within this item
        let contourDataBytes: [UInt8] = [0x06, 0x30, 0x50, 0x00]
        
        var searchOffset = 0
        while searchOffset < data.count - 8 {
            var found = false
            for i in searchOffset..<(data.count - 8) {
                let slice = data.subdata(in: i..<i+4)
                if Array(slice) == contourDataBytes {
                    print("             ✅ Found (3006,0050) at item offset \(i)")
                    
                    if i + 8 <= data.count {
                        let length = data.withUnsafeBytes { bytes in
                            bytes.load(fromByteOffset: i + 4, as: UInt32.self)
                        }
                        
                        if length > 0 && length < 100000 && i + 8 + Int(length) <= data.count {
                            let contourDataRaw = data.subdata(in: (i + 8)..<(i + 8 + Int(length)))
                            
                            if let contour = parseContourDataDirectly(contourDataRaw) {
                                contours.append(contour)
                                print("               ✅ Parsed: \(contour.points.count) points at Z=\(contour.slicePosition)")
                            }
                            
                            searchOffset = i + 8 + Int(length)
                            found = true
                            break
                        }
                    }
                }
            }
            
            if !found {
                // DEBUG: Look for ANY DICOM tags in this item
                print("               🔎 No (3006,0050) found. Scanning for any DICOM tags...")
                
                // Scan every 2 bytes for DICOM tags (they can start at any even offset)
                for i in stride(from: 0, to: data.count - 4, by: 2) {
                    if i + 4 <= data.count {
                        // Read potential tag
                        let tagBytes = data.subdata(in: i..<i+4)
                        let tag = tagBytes.withUnsafeBytes { bytes in
                            bytes.load(as: UInt32.self)
                        }
                        
                        // Check if this looks like a valid DICOM tag
                        let group = UInt16(tag & 0xFFFF)
                        let element = UInt16((tag >> 16) & 0xFFFF)
                        
                        // Focus on group 3006 tags (RTStruct related)
                        if group == 0x3006 {
                            print("                 🏷️ Found RTStruct tag (\(String(format: "%04X", group)),\(String(format: "%04X", element))) at offset \(i)")
                            
                            if element == 0x0040 {
                                print("                   📦 FOUND Contour Sequence (3006,0040)! Parsing nested contours...")
                                
                                // Parse the nested contour sequence
                                if i + 8 <= data.count {
                                    let lengthBytes = data.subdata(in: (i+4)..<(i+8))
                                    let length = lengthBytes.withUnsafeBytes { bytes in
                                        bytes.load(as: UInt32.self)
                                    }
                                    
                                    let nestedStart = i + 8
                                    var nestedEnd: Int
                                    
                                    if length == 0xFFFFFFFF {
                                        // Find delimiter for undefined length
                                        nestedEnd = findSequenceDelimiter(in: data, startingAt: nestedStart) ?? data.count
                                        print("                     🔄 Undefined length nested sequence, delimiter at \(nestedEnd)")
                                    } else {
                                        nestedEnd = nestedStart + Int(length)
                                        print("                     📏 Defined length nested sequence: \(length) bytes")
                                    }
                                    
                                    if nestedEnd <= data.count && nestedStart < nestedEnd {
                                        let nestedSequenceData = data.subdata(in: nestedStart..<nestedEnd)
                                        print("                     🔄 Parsing nested sequence (\(nestedSequenceData.count) bytes)...")
                                        
                                        // Recursively parse this nested sequence for contour data
                                        let nestedContours = parseROIContourSequenceForAllContours(nestedSequenceData)
                                        contours.append(contentsOf: nestedContours)
                                        
                                        if !nestedContours.isEmpty {
                                            print("                     ✅ Found \(nestedContours.count) nested contours!")
                                        }
                                    }
                                }
                                
                            } else if element == 0x0050 {
                                print("                   ✅ FOUND Contour Data (3006,0050)! Processing...")
                                
                                if i + 8 <= data.count {
                                    let lengthBytes = data.subdata(in: (i+4)..<(i+8))
                                    let length = lengthBytes.withUnsafeBytes { bytes in
                                        bytes.load(as: UInt32.self)
                                    }
                                    
                                    if length > 0 && length < 100000 && i + 8 + Int(length) <= data.count {
                                        let contourDataRaw = data.subdata(in: (i + 8)..<(i + 8 + Int(length)))
                                        
                                        if let contour = parseContourDataDirectly(contourDataRaw) {
                                            contours.append(contour)
                                            print("                     ✅ Direct contour parsed: \(contour.points.count) points at Z=\(contour.slicePosition)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                break // No more contour data found in this item
            }
        }
        
        return contours
    }
    
    // MARK: - Sequence Delimiter Finder
    private static func findSequenceDelimiter(in data: Data, startingAt offset: Int) -> Int? {
        let delimiterBytes: [UInt8] = [0xFE, 0xFF, 0x0D, 0xE0] // Sequence delimiter
        
        for i in offset..<(data.count - 4) {
            let slice = data.subdata(in: i..<i+4)
            if Array(slice) == delimiterBytes {
                return i
            }
        }
        
        return nil
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
