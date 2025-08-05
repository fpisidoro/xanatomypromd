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
        
        // Group contours into separate ROI structures based on Z-position clustering
        let roiStructures = groupContoursIntoROIs(contours: allContours, dataset: dataset)
        
        return SimpleRTStructData(
            structureSetName: structureSetName,
            patientName: patientName,
            roiStructures: roiStructures
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
                
                // Read length (safely handle unaligned data)
                let length: UInt32
                if tagOffset + 8 <= data.count {
                    // Read 4 bytes safely without assuming alignment
                    let lengthData = data.subdata(in: (tagOffset + 4)..<(tagOffset + 8))
                    length = lengthData.withUnsafeBytes { bytes in
                        // Create aligned copy for safe reading
                        var value: UInt32 = 0
                        withUnsafeMutableBytes(of: &value) { dest in
                            dest.copyMemory(from: bytes)
                        }
                        return value
                    }
                } else {
                    length = 0
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
                // Read length (safely handle unaligned data)
                let length: UInt32
                if tagOffset + 8 <= data.count {
                    // Read 4 bytes safely without assuming alignment
                    let lengthData = data.subdata(in: (tagOffset + 4)..<(tagOffset + 8))
                    length = lengthData.withUnsafeBytes { bytes in
                        // Create aligned copy for safe reading
                        var value: UInt32 = 0
                        withUnsafeMutableBytes(of: &value) { dest in
                            dest.copyMemory(from: bytes)
                        }
                        return value
                    }
                } else {
                    length = 0
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
                
                // Read length (4 bytes after tag, safely handle unaligned data)
                let length: UInt32
                if tagOffset + 8 <= data.count {
                    // Read 4 bytes safely without assuming alignment
                    let lengthData = data.subdata(in: (tagOffset + 4)..<(tagOffset + 8))
                    length = lengthData.withUnsafeBytes { bytes in
                        // Create aligned copy for safe reading
                        var value: UInt32 = 0
                        withUnsafeMutableBytes(of: &value) { dest in
                            dest.copyMemory(from: bytes)
                        }
                        return value
                    }
                } else {
                    length = 0
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
                // Read item length (safely handle unaligned data)
                let length: UInt32
                if tagOffset + 8 <= data.count {
                    // Read 4 bytes safely without assuming alignment
                    let lengthData = data.subdata(in: (tagOffset + 4)..<(tagOffset + 8))
                    length = lengthData.withUnsafeBytes { bytes in
                        // Create aligned copy for safe reading
                        var value: UInt32 = 0
                        withUnsafeMutableBytes(of: &value) { dest in
                            dest.copyMemory(from: bytes)
                        }
                        return value
                    }
                } else {
                    length = 0
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
    
    // MARK: - Group Contours into ROI Structures
    private static func groupContoursIntoROIs(contours: [SimpleContour], dataset: DICOMDataset) -> [SimpleROIStructure] {
        guard !contours.isEmpty else { return [] }
        
        print("\n   🔍 Analyzing contour clustering for ROI separation...")
        
        // Sort contours by Z position
        let sortedContours = contours.sorted { $0.slicePosition < $1.slicePosition }
        
        // Group contours that are close together in Z (within 5mm suggests same structure)
        var roiGroups: [[SimpleContour]] = []
        var currentGroup: [SimpleContour] = [sortedContours[0]]
        
        for i in 1..<sortedContours.count {
            let prevZ = sortedContours[i-1].slicePosition
            let currZ = sortedContours[i].slicePosition
            
            // If Z-gap is > 10mm, likely a different anatomical structure
            if abs(currZ - prevZ) > 10.0 {
                roiGroups.append(currentGroup)
                currentGroup = [sortedContours[i]]
                print("      🆕 New ROI group detected (Z-gap: \(abs(currZ - prevZ))mm)")
            } else {
                currentGroup.append(sortedContours[i])
            }
        }
        roiGroups.append(currentGroup)
        
        print("   📦 Identified \(roiGroups.count) separate ROI structures")
        
        // Try to extract ROI metadata from dataset
        let roiMetadata = extractROIMetadata(from: dataset)
        
        // Create ROI structures
        var roiStructures: [SimpleROIStructure] = []
        for (index, group) in roiGroups.enumerated() {
            let roiNumber = index + 1
            
            // Try to get metadata for this ROI
            let metadata = roiMetadata.first { roi in
                // Match based on Z-range overlap
                let roiZMin = group.map { $0.slicePosition }.min() ?? 0
                let roiZMax = group.map { $0.slicePosition }.max() ?? 0
                return roi.zMin <= roiZMax && roi.zMax >= roiZMin
            }
            
            let roiName = metadata?.name ?? "ROI-\(roiNumber)"
            let displayColor = metadata?.color ?? generateROIColor(for: index)
            
            let roi = SimpleROIStructure(
                roiNumber: roiNumber,
                roiName: roiName,
                displayColor: displayColor,
                contours: group
            )
            
            let zPositions = group.map { $0.slicePosition }
            let minZ = zPositions.min() ?? 0
            let maxZ = zPositions.max() ?? 0
            let totalPoints = group.reduce(0) { $0 + $1.points.count }
            
            print("      🏷️ ROI \(roiNumber): '\(roiName)'")
            print("         📍 Z-range: \(minZ)mm to \(maxZ)mm")
            print("         🔢 \(group.count) contours, \(totalPoints) points")
            
            roiStructures.append(roi)
        }
        
        return roiStructures
    }
    
    // MARK: - Extract ROI Metadata from Dataset
    private static func extractROIMetadata(from dataset: DICOMDataset) -> [(name: String, color: SIMD3<Float>, zMin: Float, zMax: Float)] {
        var metadata: [(name: String, color: SIMD3<Float>, zMin: Float, zMax: Float)] = []
        
        print("   📚 Extracting ROI metadata from RTStruct...")
        
        // Parse ROI Contour Sequence (3006,0039) for colors
        if let roiContourSeq = dataset.elements[.roiContourSequence] {
            print("      🎨 Parsing ROI Contour Sequence for colors...")
            
            let items = parseSequenceItems(roiContourSeq.data)
            print("      Found \(items.count) ROI contour items")
            
            for (index, itemData) in items.enumerated() {
                // Extract ROI Display Color (3006,002A) from each item
                let colorTag: [UInt8] = [0x06, 0x30, 0x2A, 0x00] // ROI Display Color
                
                if let colorOffset = scanForTag(in: itemData, tag: colorTag, startingAt: 0) {
                    // Read length
                    if colorOffset + 8 <= itemData.count {
                        let lengthData = itemData.subdata(in: (colorOffset + 4)..<(colorOffset + 8))
                        let length = lengthData.withUnsafeBytes { bytes in
                            var value: UInt32 = 0
                            withUnsafeMutableBytes(of: &value) { dest in
                                dest.copyMemory(from: bytes)
                            }
                            return value
                        }
                        
                        if length > 0 && colorOffset + 8 + Int(length) <= itemData.count {
                            let colorData = itemData.subdata(in: (colorOffset + 8)..<(colorOffset + 8 + Int(length)))
                            
                            // Parse RGB values (format: "R\\G\\B" where values are 0-255)
                            if let colorString = String(data: colorData, encoding: .ascii) {
                                let components = colorString.components(separatedBy: "\\")
                                if components.count >= 3 {
                                    if let r = Int(components[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                                       let g = Int(components[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                                       let b = Int(components[2].trimmingCharacters(in: .whitespacesAndNewlines)) {
                                        
                                        // Convert from 0-255 to 0-1 range
                                        let color = SIMD3<Float>(
                                            Float(r) / 255.0,
                                            Float(g) / 255.0,
                                            Float(b) / 255.0
                                        )
                                        
                                        print("         🌈 ROI \(index + 1) color: RGB(\(r), \(g), \(b))")
                                        
                                        let name = "Structure \(index + 1)"
                                        metadata.append((name: name, color: color, zMin: -200, zMax: 200))
                                    }
                                }
                            }
                        }
                    }
                }
                
                // If no color found, use generated color
                if metadata.count <= index {
                    let color = generateROIColor(for: index)
                    let name = "Structure \(index + 1)"
                    metadata.append((name: name, color: color, zMin: -200, zMax: 200))
                    print("         ⚠️ No color found for ROI \(index + 1), using generated color")
                }
            }
        }
        
        // Parse Structure Set ROI Sequence (3006,0020) for names
        if let structureSetROISeq = dataset.elements[.structureSetROISequence] {
            print("      🏷️ Parsing Structure Set ROI Sequence for names...")
            
            let items = parseSequenceItems(structureSetROISeq.data)
            print("      Found \(items.count) structure set items")
            
            for (index, itemData) in items.enumerated() {
                // Extract ROI Name (3006,0026)
                let nameTag: [UInt8] = [0x06, 0x30, 0x26, 0x00] // ROI Name
                
                if let nameOffset = scanForTag(in: itemData, tag: nameTag, startingAt: 0) {
                    if nameOffset + 8 <= itemData.count {
                        let lengthData = itemData.subdata(in: (nameOffset + 4)..<(nameOffset + 8))
                        let length = lengthData.withUnsafeBytes { bytes in
                            var value: UInt32 = 0
                            withUnsafeMutableBytes(of: &value) { dest in
                                dest.copyMemory(from: bytes)
                            }
                            return value
                        }
                        
                        if length > 0 && nameOffset + 8 + Int(length) <= itemData.count {
                            let nameData = itemData.subdata(in: (nameOffset + 8)..<(nameOffset + 8 + Int(length)))
                            
                            if let roiName = String(data: nameData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                                if index < metadata.count {
                                    // Update the name while keeping the color
                                    let oldMetadata = metadata[index]
                                    metadata[index] = (name: roiName, color: oldMetadata.color, zMin: oldMetadata.zMin, zMax: oldMetadata.zMax)
                                    print("         🆔 ROI \(index + 1) name: '\(roiName)'")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        print("      ✅ Extracted metadata for \(metadata.count) ROIs")
        return metadata
    }
    
    // MARK: - Generate ROI Colors
    private static func generateROIColor(for index: Int) -> SIMD3<Float> {
        let colors: [SIMD3<Float>] = [
            SIMD3<Float>(1.0, 0.0, 0.0),  // Red
            SIMD3<Float>(0.0, 1.0, 0.0),  // Green
            SIMD3<Float>(0.0, 0.0, 1.0),  // Blue
            SIMD3<Float>(1.0, 1.0, 0.0),  // Yellow
            SIMD3<Float>(1.0, 0.0, 1.0),  // Magenta
            SIMD3<Float>(0.0, 1.0, 1.0),  // Cyan
            SIMD3<Float>(1.0, 0.5, 0.0),  // Orange
            SIMD3<Float>(0.5, 0.0, 1.0),  // Purple
            SIMD3<Float>(0.0, 1.0, 0.5),  // Spring Green
            SIMD3<Float>(1.0, 0.5, 0.5),  // Light Red
        ]
        return colors[index % colors.count]
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
