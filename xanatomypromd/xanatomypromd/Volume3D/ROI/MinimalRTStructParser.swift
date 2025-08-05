import Foundation
import simd

// MARK: - Enhanced RTStruct Parser - Finds ALL Contours Across Multiple Z-Slices
// Fixed to properly extract all contours from RTStruct files, not just the first one

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
        print("🎯 Enhanced RTStruct Parser - Finding ALL Contours")
        
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
        
        // ENHANCED: Find ALL contours using multiple methods
        let allContours = findAllContoursInDataset(dataset: dataset)
        
        if allContours.isEmpty {
            print("   ❌ No contour data found")
            return nil
        }
        
        // Group contours by Z position to show distribution
        let groupedByZ = Dictionary(grouping: allContours) { $0.slicePosition }
        let sortedZPositions = groupedByZ.keys.sorted()
        
        print("   ✅ Found contours across \(sortedZPositions.count) Z-slices:")
        for z in sortedZPositions {
            let contoursAtZ = groupedByZ[z]!
            let totalPoints = contoursAtZ.reduce(0) { $0 + $1.points.count }
            print("      Z=\(z)mm: \(contoursAtZ.count) contours, \(totalPoints) points")
        }
        
        // Create a single ROI with all contours (for now)
        // In a full implementation, we'd parse ROI metadata to group properly
        let roi = SimpleROIStructure(
            roiNumber: 1,
            roiName: "Anatomical Structure",
            displayColor: SIMD3<Float>(1.0, 0.0, 1.0), // Magenta
            contours: allContours
        )
        
        return SimpleRTStructData(
            structureSetName: structureSetName,
            patientName: patientName,
            roiStructures: [roi]
        )
    }
    
    // MARK: - ENHANCED: Find ALL Contours Using Multiple Methods
    private static func findAllContoursInDataset(dataset: DICOMDataset) -> [SimpleContour] {
        var allContours: [SimpleContour] = []
        var foundContourTags = 0
        
        print("\n   🔍 Method 1: Direct Element Scanning for ALL (3006,0050) tags...")
        
        // FIXED: Don't stop after first contour - check ALL elements
        for (tag, element) in dataset.elements {
            if tag.group == 0x3006 && tag.element == 0x0050 {
                foundContourTags += 1
                print("     ✅ Found Contour Data tag #\(foundContourTags) - \(element.data.count) bytes")
                
                if let contour = parseContourDataDirectly(element.data) {
                    allContours.append(contour)
                    print("       📍 Extracted: \(contour.points.count) points at Z=\(contour.slicePosition)")
                }
            }
        }
        
        print("\n   🔍 Method 2: Parse ROI Contour Sequence (3006,0039)...")
        if let roiContourSeq = dataset.elements[.roiContourSequence] {
            print("     📦 Found ROI Contour Sequence (\(roiContourSeq.data.count) bytes)")
            let sequenceContours = parseROIContourSequence(roiContourSeq.data)
            
            for contour in sequenceContours {
                // Check if this contour is unique (different Z position)
                let isUnique = !allContours.contains { existing in
                    abs(existing.slicePosition - contour.slicePosition) < 0.01
                }
                
                if isUnique {
                    allContours.append(contour)
                    print("       🆕 Added unique contour: \(contour.points.count) points at Z=\(contour.slicePosition)")
                }
            }
        }
        
        print("\n   🔍 Method 3: Raw Byte Scanning for ALL (3006,0050) occurrences...")
        
        // Get raw DICOM file data if available
        if let rawData = dataset.rawData {
            let rawContours = scanRawDataForAllContours(rawData)
            
            for contour in rawContours {
                // Check if this contour is unique
                let isUnique = !allContours.contains { existing in
                    abs(existing.slicePosition - contour.slicePosition) < 0.01 &&
                    existing.points.count == contour.points.count
                }
                
                if isUnique {
                    allContours.append(contour)
                    print("       🆕 Found via raw scan: \(contour.points.count) points at Z=\(contour.slicePosition)")
                }
            }
        }
        
        print("\n   📊 Total unique contours found: \(allContours.count)")
        return allContours
    }
    
    // MARK: - Parse ROI Contour Sequence (3006,0039)
    private static func parseROIContourSequence(_ data: Data) -> [SimpleContour] {
        var contours: [SimpleContour] = []
        
        print("     🔄 Parsing ROI Contour Sequence...")
        
        // Parse all sequence items
        let items = parseSequenceItems(data)
        print("       📎 Found \(items.count) sequence items")
        
        for (index, itemData) in items.enumerated() {
            print("       📦 Processing item \(index + 1)/\(items.count) (\(itemData.count) bytes)...")
            
            // Look for Contour Sequence (3006,0040) within this item
            let contourSeqContours = findContourSequenceInItem(itemData)
            contours.append(contentsOf: contourSeqContours)
            
            // Also look for direct Contour Data (3006,0050) in this item
            let directContours = scanDataForContourData(itemData)
            contours.append(contentsOf: directContours)
        }
        
        return contours
    }
    
    // MARK: - Find Contour Sequence (3006,0040) in Item
    private static func findContourSequenceInItem(_ data: Data) -> [SimpleContour] {
        var contours: [SimpleContour] = []
        
        // Look for (3006,0040) Contour Sequence tag
        let contourSeqTag: [UInt8] = [0x06, 0x30, 0x40, 0x00]
        
        var offset = 0
        while offset < data.count - 8 {
            let found = scanForTag(in: data, tag: contourSeqTag, startingAt: offset)
            
            if let tagOffset = found {
                print("         🎯 Found Contour Sequence (3006,0040) at offset \(tagOffset)")
                
                // Read length
                let length = data.withUnsafeBytes { bytes in
                    bytes.load(fromByteOffset: tagOffset + 4, as: UInt32.self)
                }
                
                let seqStart = tagOffset + 8
                var seqEnd: Int
                
                if length == 0xFFFFFFFF {
                    // Undefined length - find delimiter
                    seqEnd = findDelimiter(in: data, startingAt: seqStart) ?? data.count
                    print("         📏 Undefined length sequence, ends at \(seqEnd)")
                } else {
                    seqEnd = seqStart + Int(length)
                    print("         📏 Defined length sequence: \(length) bytes")
                }
                
                if seqEnd <= data.count && seqStart < seqEnd {
                    let seqData = data.subdata(in: seqStart..<seqEnd)
                    
                    // Parse items within this Contour Sequence
                    let seqItems = parseSequenceItems(seqData)
                    print("         📦 Found \(seqItems.count) contour items")
                    
                    for itemData in seqItems {
                        // Each item should contain Contour Data (3006,0050)
                        let itemContours = scanDataForContourData(itemData)
                        contours.append(contentsOf: itemContours)
                    }
                }
                
                offset = seqEnd
            } else {
                break
            }
        }
        
        return contours
    }
    
    // MARK: - Scan Data for Contour Data (3006,0050)
    private static func scanDataForContourData(_ data: Data) -> [SimpleContour] {
        var contours: [SimpleContour] = []
        let contourDataTag: [UInt8] = [0x06, 0x30, 0x50, 0x00]
        
        var offset = 0
        while offset < data.count - 8 {
            let found = scanForTag(in: data, tag: contourDataTag, startingAt: offset)
            
            if let tagOffset = found {
                // Read length
                let length = data.withUnsafeBytes { bytes in
                    bytes.load(fromByteOffset: tagOffset + 4, as: UInt32.self)
                }
                
                if length > 0 && length < 1000000 && tagOffset + 8 + Int(length) <= data.count {
                    let contourData = data.subdata(in: (tagOffset + 8)..<(tagOffset + 8 + Int(length)))
                    
                    if let contour = parseContourDataDirectly(contourData) {
                        contours.append(contour)
                        print("           ✅ Found contour: \(contour.points.count) points at Z=\(contour.slicePosition)")
                    }
                }
                
                offset = tagOffset + 8 + Int(length)
            } else {
                break
            }
        }
        
        return contours
    }
    
    // MARK: - Raw Data Scanning for ALL Contours
    private static func scanRawDataForAllContours(_ data: Data) -> [SimpleContour] {
        var contours: [SimpleContour] = []
        let contourDataTag: [UInt8] = [0x06, 0x30, 0x50, 0x00]
        
        var offset = 0
        var tagCount = 0
        
        while offset < data.count - 8 {
            let found = scanForTag(in: data, tag: contourDataTag, startingAt: offset)
            
            if let tagOffset = found {
                tagCount += 1
                
                // Read length (4 bytes after tag)
                let length = data.withUnsafeBytes { bytes in
                    bytes.load(fromByteOffset: tagOffset + 4, as: UInt32.self)
                }
                
                print("       🔍 Raw scan found (3006,0050) #\(tagCount) at byte \(tagOffset), length: \(length)")
                
                if length > 0 && length < 1000000 && tagOffset + 8 + Int(length) <= data.count {
                    let contourData = data.subdata(in: (tagOffset + 8)..<(tagOffset + 8 + Int(length)))
                    
                    if let contour = parseContourDataDirectly(contourData) {
                        contours.append(contour)
                    }
                }
                
                // Move past this tag to continue searching
                offset = tagOffset + 8 + min(Int(length), data.count - tagOffset - 8)
            } else {
                break
            }
        }
        
        print("       📊 Raw scan found \(tagCount) contour data tags total")
        return contours
    }
    
    // MARK: - Parse Sequence Items
    private static func parseSequenceItems(_ data: Data) -> [Data] {
        var items: [Data] = []
        let itemTag: [UInt8] = [0xFE, 0xFF, 0x00, 0xE0]
        
        var offset = 0
        while offset < data.count - 8 {
            let found = scanForTag(in: data, tag: itemTag, startingAt: offset)
            
            if let tagOffset = found {
                // Read item length
                let length = data.withUnsafeBytes { bytes in
                    bytes.load(fromByteOffset: tagOffset + 4, as: UInt32.self)
                }
                
                let itemStart = tagOffset + 8
                var itemEnd: Int
                
                if length == 0xFFFFFFFF {
                    // Undefined length - find item delimiter
                    itemEnd = findItemDelimiter(in: data, startingAt: itemStart) ?? data.count
                } else {
                    itemEnd = itemStart + Int(length)
                }
                
                if itemEnd <= data.count && itemStart < itemEnd {
                    let itemData = data.subdata(in: itemStart..<itemEnd)
                    items.append(itemData)
                }
                
                offset = itemEnd
            } else {
                break
            }
        }
        
        return items
    }
    
    // MARK: - Utility: Scan for Tag
    private static func scanForTag(in data: Data, tag: [UInt8], startingAt offset: Int) -> Int? {
        for i in offset..<(data.count - tag.count) {
            let slice = data.subdata(in: i..<(i + tag.count))
            if Array(slice) == tag {
                return i
            }
        }
        return nil
    }
    
    // MARK: - Find Delimiters
    private static func findDelimiter(in data: Data, startingAt offset: Int) -> Int? {
        let delimiterTag: [UInt8] = [0xFE, 0xFF, 0x0D, 0xE0]
        return scanForTag(in: data, tag: delimiterTag, startingAt: offset)
    }
    
    private static func findItemDelimiter(in data: Data, startingAt offset: Int) -> Int? {
        let itemDelimiter: [UInt8] = [0xFE, 0xFF, 0x0D, 0xE0]
        return scanForTag(in: data, tag: itemDelimiter, startingAt: offset)
    }
    
    // MARK: - Parse Contour Data (PROVEN METHOD)
    private static func parseContourDataDirectly(_ data: Data) -> SimpleContour? {
        // Try ASCII format first (most common)
        if let asciiString = String(data: data, encoding: .ascii) {
            let cleanString = asciiString.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            
            if !cleanString.isEmpty {
                // Extract numbers using backslash separator
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
                        zPosition = z // All points in a contour share the same Z
                    }
                    
                    return SimpleContour(points: points, slicePosition: zPosition)
                }
            }
        }
        
        // Try UTF-8 as fallback
        if let utf8String = String(data: data, encoding: .utf8) {
            let components = utf8String.components(separatedBy: "\\")
            let numbers = components.compactMap { Float($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            
            if numbers.count >= 6 && numbers.count % 3 == 0 {
                var points: [SIMD3<Float>] = []
                var zPosition: Float = 0.0
                
                for i in stride(from: 0, to: numbers.count - 2, by: 3) {
                    points.append(SIMD3<Float>(numbers[i], numbers[i + 1], numbers[i + 2]))
                    zPosition = numbers[i + 2]
                }
                
                return SimpleContour(points: points, slicePosition: zPosition)
            }
        }
        
        return nil
    }
    
    // MARK: - Data Conversion for Compatibility
    public static func convertToFullROI(_ simpleData: SimpleRTStructData) -> RTStructData {
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
        
        return RTStructData(
            patientName: simpleData.patientName,
            studyInstanceUID: "Unknown",
            seriesInstanceUID: "Unknown",
            structureSetLabel: simpleData.structureSetName,
            structureSetName: simpleData.structureSetName ?? "Unknown",
            structureSetDescription: "Loaded from RTStruct DICOM file",
            roiStructures: fullROIStructures,
            referencedFrameOfReferenceUID: "Unknown"
        )
    }
}
