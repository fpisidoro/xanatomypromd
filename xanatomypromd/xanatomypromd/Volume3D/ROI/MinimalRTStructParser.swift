import Foundation
import simd

// MARK: - Enhanced RTStruct Parser - Full 3D Contour Support
// Handles complex RTStruct files with hundreds of ROIs and multiple contours per ROI

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
    
    // MARK: - Internal Parsing Structures
    private struct ROIInfo {
        let roiNumber: Int
        let roiName: String
        
        init(roiNumber: Int, roiName: String) {
            self.roiNumber = roiNumber
            self.roiName = roiName
        }
    }
    
    private struct ROIContourInfo {
        let roiNumber: Int
        let displayColor: SIMD3<Float>
        let contours: [SimpleContour]
        
        init(roiNumber: Int, displayColor: SIMD3<Float>, contours: [SimpleContour]) {
            self.roiNumber = roiNumber
            self.displayColor = displayColor
            self.contours = contours
        }
    }
    
    // MARK: - Main Parsing Interface
    public static func parseSimpleRTStruct(from dataset: DICOMDataset) -> SimpleRTStructData? {
        print("🎯 Enhanced RTStruct Parser - Full 3D Support")
        
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
        
        // Enhanced parsing: handle sequence structures properly
        let roiStructures = parseROIStructuresFromSequences(dataset: dataset)
        
        if roiStructures.isEmpty {
            print("   ❌ No ROI structures found")
            return nil
        }
        
        // Calculate total contours for verification
        let totalContours = roiStructures.reduce(0) { $0 + $1.contours.count }
        print("   ✅ Successfully parsed \(roiStructures.count) ROI structures with \(totalContours) total contours")
        
        return SimpleRTStructData(
            structureSetName: structureSetName,
            patientName: patientName,
            roiStructures: roiStructures
        )
    }
    
    // MARK: - Enhanced Sequence-Based Parsing
    private static func parseROIStructuresFromSequences(dataset: DICOMDataset) -> [SimpleROIStructure] {
        print("   🔍 Parsing RTStruct sequences for complete 3D structure...")
        
        // Step 1: Parse Structure Set ROI Sequence (3006,0020) for ROI names/numbers
        let roiInfos = parseStructureSetROISequence(dataset: dataset)
        print("   📊 Found \(roiInfos.count) ROI definitions")
        
        // Step 2: Parse ROI Contour Sequence (3006,0039) for contour geometry and colors
        let roiContourInfos = parseROIContourSequence(dataset: dataset)
        print("   🎨 Found \(roiContourInfos.count) ROI contour sets")
        
        // Step 3: Combine ROI info with contour data
        var finalROIStructures: [SimpleROIStructure] = []
        
        for roiInfo in roiInfos {
            // Find matching contour data
            if let roiContour = roiContourInfos.first(where: { $0.roiNumber == roiInfo.roiNumber }) {
                let roiStructure = SimpleROIStructure(
                    roiNumber: roiInfo.roiNumber,
                    roiName: roiInfo.roiName,
                    displayColor: roiContour.displayColor,
                    contours: roiContour.contours
                )
                finalROIStructures.append(roiStructure)
                
                // Calculate Z range for this ROI
                let zPositions = roiContour.contours.map { $0.slicePosition }
                let minZ = zPositions.min() ?? 0
                let maxZ = zPositions.max() ?? 0
                
                print("   ✅ ROI \(roiInfo.roiNumber): '\(roiInfo.roiName)' - \(roiContour.contours.count) contours (Z: \(minZ) to \(maxZ)mm)")
            } else {
                print("   ⚠️ ROI \(roiInfo.roiNumber): '\(roiInfo.roiName)' - no contour data found")
            }
        }
        
        return finalROIStructures
    }
    
    // MARK: - Structure Set ROI Sequence Parsing (3006,0020)
    private static func parseStructureSetROISequence(dataset: DICOMDataset) -> [ROIInfo] {
        print("     🔍 Parsing Structure Set ROI Sequence (3006,0020)...")
        
        var roiInfos: [ROIInfo] = []
        
        // Look for Structure Set ROI Sequence
        if let sequenceElement = dataset.elements[.structureSetROISequence] {
            let sequenceItems = parseSequenceItems(data: sequenceElement.data)
            print("       📦 Found \(sequenceItems.count) Structure Set ROI items")
            
            for (index, itemData) in sequenceItems.enumerated() {
                if let roiInfo = parseStructureSetROIItem(data: itemData, index: index) {
                    roiInfos.append(roiInfo)
                }
            }
        } else {
            print("       ❌ Structure Set ROI Sequence not found")
        }
        
        return roiInfos
    }
    
    // MARK: - ROI Contour Sequence Parsing (3006,0039)
    private static func parseROIContourSequence(dataset: DICOMDataset) -> [ROIContourInfo] {
        print("     🔍 Parsing ROI Contour Sequence (3006,0039)...")
        
        var roiContourInfos: [ROIContourInfo] = []
        
        // Look for ROI Contour Sequence
        if let sequenceElement = dataset.elements[.roiContourSequence] {
            let sequenceItems = parseSequenceItems(data: sequenceElement.data)
            print("       📦 Found \(sequenceItems.count) ROI Contour items")
            
            for (index, itemData) in sequenceItems.enumerated() {
                if let roiContourInfo = parseROIContourItem(data: itemData, index: index) {
                    roiContourInfos.append(roiContourInfo)
                }
            }
        } else {
            print("       ❌ ROI Contour Sequence not found")
        }
        
        return roiContourInfos
    }
    
    // MARK: - Sequence Item Parsing
    private static func parseSequenceItems(data: Data) -> [Data] {
        print("       🔧 Parsing sequence items in \(data.count) bytes...")
        
        var items: [Data] = []
        var offset = 0
        
        while offset < data.count - 8 {
            // Ensure 4-byte alignment for UInt32 reads
            if offset % 4 != 0 {
                offset = (offset + 3) & ~3  // Round up to next 4-byte boundary
            }
            
            if offset + 8 > data.count {
                break
            }
            
            // Look for Item tag (FFFE,E000)
            let itemTag = data.withUnsafeBytes { bytes in
                bytes.load(fromByteOffset: offset, as: UInt32.self)
            }
            
            if itemTag == 0xE000FFFE { // Item tag in little endian
                // Read item length
                let itemLength = data.withUnsafeBytes { bytes in
                    bytes.load(fromByteOffset: offset + 4, as: UInt32.self)
                }
                
                if itemLength == 0xFFFFFFFF {
                    // Undefined length - scan for Item Delimitation tag (FFFE,E00D)
                    let itemStart = offset + 8
                    var itemEnd = itemStart
                    
                    while itemEnd < data.count - 4 {
                        // Ensure 4-byte alignment for UInt32 read
                        if itemEnd % 4 != 0 {
                            itemEnd = (itemEnd + 3) & ~3  // Round up to next 4-byte boundary
                        }
                        
                        if itemEnd + 4 <= data.count {
                            let tag = data.withUnsafeBytes { bytes in
                                bytes.load(fromByteOffset: itemEnd, as: UInt32.self)
                            }
                            
                            if tag == 0xE00DFFFE { // Item Delimitation tag
                                break
                            }
                        }
                        itemEnd += 1
                    }
                    
                    if itemEnd > itemStart {
                        let itemData = data.subdata(in: itemStart..<itemEnd)
                        items.append(itemData)
                        print("         📋 Item \(items.count): \(itemData.count) bytes (undefined length)")
                    }
                    
                    offset = itemEnd + 8 // Skip delimitation tag
                    
                } else if itemLength > 0 && itemLength < data.count {
                    // Defined length
                    let itemStart = offset + 8
                    let itemEnd = itemStart + Int(itemLength)
                    
                    if itemEnd <= data.count {
                        let itemData = data.subdata(in: itemStart..<itemEnd)
                        items.append(itemData)
                        print("         📋 Item \(items.count): \(itemData.count) bytes")
                    }
                    
                    offset = itemEnd
                } else {
                    offset += 1
                }
            } else {
                offset += 1
            }
        }
        
        print("       ✅ Parsed \(items.count) sequence items")
        return items
    }
    
    // MARK: - Individual Item Parsers
    private static func parseStructureSetROIItem(data: Data, index: Int) -> ROIInfo? {
        print("         🔍 Parsing Structure Set ROI item \(index + 1)...")
        
        var roiNumber: Int?
        var roiName: String?
        
        // Scan for ROI Number (3006,0022) and ROI Name (3006,0026)
        var offset = 0
        while offset < data.count - 8 {
            // Skip to next 4-byte boundary if needed
            while offset < data.count - 8 && offset % 4 != 0 {
                offset += 1
            }
            
            if offset + 8 > data.count {
                break
            }
            
            let tag = data.withUnsafeBytes { bytes in
                bytes.load(fromByteOffset: offset, as: UInt32.self)
            }
            let length = data.withUnsafeBytes { bytes in
                bytes.load(fromByteOffset: offset + 4, as: UInt32.self)
            }
            
            print("           🏷️ Found tag: \(String(format: "%08X", tag)), length: \(length)")
            
            if tag == 0x06300022 { // ROI Number (3006,0022) in correct little endian
                if length > 0 && length < 100 && offset + 8 + Int(length) <= data.count {
                    let valueData = data.subdata(in: (offset + 8)..<(offset + 8 + Int(length)))
                    if let numberString = String(data: valueData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        roiNumber = Int(numberString)
                        print("           📊 ROI Number: \(roiNumber!)")
                    }
                }
            } else if tag == 0x06300026 { // ROI Name (3006,0026) in correct little endian
                if length > 0 && length < 1000 && offset + 8 + Int(length) <= data.count {
                    let valueData = data.subdata(in: (offset + 8)..<(offset + 8 + Int(length)))
                    roiName = String(data: valueData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("           📝 ROI Name: '\(roiName ?? "nil")'")
                }
            }
            
            // Move to next tag (skip current tag + length)
            if length > 0 && length < data.count {
                offset += 8 + Int(length)
                // Ensure even byte boundary (DICOM requirement)
                if offset % 2 != 0 {
                    offset += 1
                }
            } else {
                offset += 8
            }
        }
        
        if let number = roiNumber, let name = roiName {
            print("           ✅ ROI \(number): '\(name)'")
            return ROIInfo(roiNumber: number, roiName: name)
        } else {
            print("           ❌ Incomplete ROI info (number: \(roiNumber?.description ?? "nil"), name: \(roiName ?? "nil"))")
            return nil
        }
    }
    
    private static func parseROIContourItem(data: Data, index: Int) -> ROIContourInfo? {
        print("         🔍 Parsing ROI Contour item \(index + 1)...")
        
        var roiNumber: Int?
        var displayColor = SIMD3<Float>(1.0, 0.0, 1.0) // Default magenta
        var contours: [SimpleContour] = []
        
        // First pass: find ROI Number and Display Color
        var offset = 0
        while offset < data.count - 8 {
            // Skip to next 4-byte boundary if needed
            while offset < data.count - 8 && offset % 4 != 0 {
                offset += 1
            }
            
            if offset + 8 > data.count {
                break
            }
            
            let tag = data.withUnsafeBytes { bytes in
                bytes.load(fromByteOffset: offset, as: UInt32.self)
            }
            let length = data.withUnsafeBytes { bytes in
                bytes.load(fromByteOffset: offset + 4, as: UInt32.self)
            }
            
            print("           🏷️ Found tag: \(String(format: "%08X", tag)), length: \(length)")
            
            if tag == 0x06300084 { // Referenced ROI Number (3006,0084) in correct little endian
                if length > 0 && length < 100 && offset + 8 + Int(length) <= data.count {
                    let valueData = data.subdata(in: (offset + 8)..<(offset + 8 + Int(length)))
                    if let numberString = String(data: valueData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        roiNumber = Int(numberString)
                        print("           📊 Referenced ROI Number: \(roiNumber!)")
                    }
                }
            } else if tag == 0x0630002A { // ROI Display Color (3006,002A) in correct little endian
                if length >= 12 && length < 100 && offset + 8 + Int(length) <= data.count {
                    let colorData = data.subdata(in: (offset + 8)..<(offset + 8 + Int(length)))
                    if let colorString = String(data: colorData, encoding: .ascii) {
                        let components = colorString.components(separatedBy: "\\")
                        if components.count >= 3,
                           let r = Int(components[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                           let g = Int(components[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                           let b = Int(components[2].trimmingCharacters(in: .whitespacesAndNewlines)) {
                            displayColor = SIMD3<Float>(Float(r)/255.0, Float(g)/255.0, Float(b)/255.0)
                            print("           🎨 Display Color: (\(r), \(g), \(b))")
                        }
                    }
                }
            } else if tag == 0x06300040 { // Contour Sequence (3006,0040) in correct little endian
                print("           📦 Found Contour Sequence, length: \(length)")
                // Parse all contours within this sequence
                if length > 0 && length < data.count && offset + 8 + Int(length) <= data.count {
                    let contourSequenceData = data.subdata(in: (offset + 8)..<(offset + 8 + Int(length)))
                    let contourItems = parseSequenceItems(data: contourSequenceData)
                    
                    print("           📦 Found \(contourItems.count) contour items")
                    
                    for (contourIndex, contourData) in contourItems.enumerated() {
                        if let contour = parseContourItem(data: contourData, index: contourIndex) {
                            contours.append(contour)
                        }
                    }
                }
            }
            
            // Move to next tag (skip current tag + length)
            if length > 0 && length < data.count {
                offset += 8 + Int(length)
                // Ensure even byte boundary (DICOM requirement)
                if offset % 2 != 0 {
                    offset += 1
                }
            } else {
                offset += 8
            }
        }
        
        if let number = roiNumber {
            print("           ✅ ROI \(number): \(contours.count) contours, color: (\(displayColor.x), \(displayColor.y), \(displayColor.z))")
            return ROIContourInfo(roiNumber: number, displayColor: displayColor, contours: contours)
        } else {
            print("           ❌ No ROI number found in contour item")
            return nil
        }
    }
    
    private static func parseContourItem(data: Data, index: Int) -> SimpleContour? {
        print("             🔍 Parsing contour \(index + 1)...")
        
        // Scan for Contour Data (3006,0050)
        var offset = 0
        while offset < data.count - 8 {
            // Ensure 4-byte alignment
            if offset % 4 != 0 {
                offset = (offset + 3) & ~3
            }
            
            if offset + 8 > data.count {
                break
            }
            
            let tag = data.withUnsafeBytes { bytes in
                bytes.load(fromByteOffset: offset, as: UInt32.self)
            }
            let length = data.withUnsafeBytes { bytes in
                bytes.load(fromByteOffset: offset + 4, as: UInt32.self)
            }
            
            if tag == 0x06300050 { // Contour Data (3006,0050) in correct little endian
                if length > 0 && offset + 8 + Int(length) <= data.count {
                    let contourData = data.subdata(in: (offset + 8)..<(offset + 8 + Int(length)))
                    
                    if let contour = parseContourDataDirectly(contourData) {
                        print("               ✅ Contour: \(contour.points.count) points at Z=\(contour.slicePosition)")
                        return contour
                    }
                }
            }
            
            offset += 8 + Int(length)
        }
        
        print("             ❌ No contour data found")
        return nil
    }
    
    // MARK: - Direct Contour Data Parsing (Shared)
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
            SIMD3<Float>(1.0, 0.5, 0.0), // Orange
            SIMD3<Float>(0.5, 0.0, 1.0), // Purple
            SIMD3<Float>(0.0, 1.0, 0.5), // Spring Green
            SIMD3<Float>(1.0, 1.0, 0.5), // Light Yellow
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
