import Foundation
import simd

// MARK: - Safe Data Reading Extension
extension Data {
    /// Safely read UInt16 from data at offset
    func safeReadUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        let bytes = self.subdata(in: offset..<offset + 2)
        return bytes.withUnsafeBytes { $0.load(as: UInt16.self) }
    }
    
    /// Safely read UInt32 from data at offset
    func safeReadUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let bytes = self.subdata(in: offset..<offset + 4)
        return bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
    }
    
    /// Safely read Float from data at offset
    func safeReadFloat(at offset: Int) -> Float {
        guard offset + 4 <= count else { return 0.0 }
        let bytes = self.subdata(in: offset..<offset + 4)
        return bytes.withUnsafeBytes { $0.load(as: Float.self) }
    }
}

// MARK: - Enhanced DICOM Sequence Structures
struct DICOMSequenceItem {
    let data: Data
    let elements: [DICOMTag: Data]
    let nestedSequences: [DICOMTag: DICOMSequence]
}

struct DICOMSequence {
    let items: [DICOMSequenceItem]
}

// MARK: - Fixed RTStruct Parser with Proper FFFE Handling
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
        print("🔧 FIXED RTStruct Parser - Starting parse...")
        
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
        
        // Parse ROI structures with fixed sequence parsing
        let roiStructures = parseROIStructuresWithFixedFFEHandling(dataset: dataset)
        
        if roiStructures.isEmpty {
            print("   ❌ No ROI structures with contour data found")
            print("   💡 SUGGESTION: Try test_rtstruct2.dcm instead of test_rtstruct.dcm")
            print("   💡 Current file may be reference-only (no geometry data)")
            return SimpleRTStructData(
                structureSetName: structureSetName,
                patientName: patientName,
                roiStructures: []
            )
        }
        
        print("   ✅ Successfully parsed \(roiStructures.count) ROI structures with contour data")
        return SimpleRTStructData(
            structureSetName: structureSetName,
            patientName: patientName,
            roiStructures: roiStructures
        )
    }
    
    // MARK: - Fixed ROI Structure Parsing
    private static func parseROIStructuresWithFixedFFEHandling(dataset: DICOMDataset) -> [SimpleROIStructure] {
        print("   🔧 Using FIXED FFFE sequence parsing...")
        
        // Step 1: Parse Structure Set ROI Sequence for metadata
        guard let roiSequenceElement = dataset.elements[.structureSetROISequence] else {
            print("   ❌ Structure Set ROI Sequence (3006,0020) not found")
            return []
        }
        
        let roiMetadata = parseStructureSetROIWithFixedDelimiters(roiSequenceElement.data)
        if roiMetadata.isEmpty {
            print("   ❌ No ROI metadata found")
            return []
        }
        
        print("   📋 Found \(roiMetadata.count) ROI metadata entries")
        
        // Step 2: Parse ROI Contour Sequence with FIXED FFFE handling
        guard let contourSequenceElement = dataset.elements[.roiContourSequence] else {
            print("   ❌ ROI Contour Sequence (3006,0039) not found")
            return []
        }
        
        let contourData = parseROIContourSequenceWithFixedDelimiters(contourSequenceElement.data)
        
        print("   📐 Found contour data for \(contourData.count) ROIs")
        
        // Step 3: Combine metadata with contour data
        return combineROIMetadataWithContours(metadata: roiMetadata, contours: contourData)
    }
    
    // MARK: - FIXED Structure Set ROI Sequence Parser
    private static func parseStructureSetROIWithFixedDelimiters(_ data: Data) -> [(roiNumber: Int, roiName: String, displayColor: SIMD3<Float>)] {
        print("     🔧 FIXED Structure Set ROI parsing...")
        
        let sequence = parseSequenceWithProperFFEHandling(data)
        var metadata: [(roiNumber: Int, roiName: String, displayColor: SIMD3<Float>)] = []
        
        for (index, item) in sequence.items.enumerated() {
            // Extract ROI Number (3006,0022)
            let roiNumber = extractIntegerFromSequenceItem(item, group: 0x3006, element: 0x0022) ?? (8240 + index + 1)
            
            // Extract ROI Name (3006,0026)
            let roiName = extractStringFromSequenceItem(item, group: 0x3006, element: 0x0026) ?? "ROI-\(index + 1)"
            
            // Generate color
            let color = generateROIColor(for: index)
            
            metadata.append((roiNumber: roiNumber, roiName: roiName, displayColor: color))
            print("     📋 ROI \(roiNumber): '\(roiName)'")
        }
        
        return metadata
    }
    
    // MARK: - FIXED ROI Contour Sequence Parser
    private static func parseROIContourSequenceWithFixedDelimiters(_ data: Data) -> [Int: [SimpleContour]] {
        print("     🔧 FIXED ROI Contour Sequence parsing (\(data.count) bytes)...")
        
        // Show diagnostic info
        if data.count < 1000 {
            print("     ⚠️ WARNING: Very small ROI Contour Sequence (\(data.count) bytes)")
            print("     💡 This suggests reference-only RTStruct (no geometry)")
        }
        
        let sequence = parseSequenceWithProperFFEHandling(data)
        var contoursByROI: [Int: [SimpleContour]] = [:]
        
        print("     📊 Found \(sequence.items.count) ROI Contour items")
        
        for (itemIndex, item) in sequence.items.enumerated() {
            print("     📦 ROI Contour item \(itemIndex + 1): \(item.data.count) bytes, \(item.elements.count) elements")
            
            // Debug: Show what elements we have
            for (tag, elementData) in item.elements {
                let tagStr = String(format: "(%04X,%04X)", tag.group, tag.element)
                print("         📋 Element \(tagStr): \(elementData.count) bytes")
            }
            
            // Extract Referenced ROI Number (3006,0084)
            let roiNumber = extractIntegerFromSequenceItem(item, group: 0x3006, element: 0x0084) ?? (itemIndex + 1)
            
            print("     📐 Processing contours for ROI \(roiNumber)...")
            
            // CRITICAL FIX: Look for nested Contour Sequence (3006,0040) within this item
            let contours = parseNestedContourSequence(item, roiNumber: roiNumber)
            
            if !contours.isEmpty {
                contoursByROI[roiNumber] = contours
                print("     ✅ Found \(contours.count) contours for ROI \(roiNumber)")
            } else {
                print("     ⚠️ No contour data found for ROI \(roiNumber) - may be reference-only")
            }
        }
        
        if contoursByROI.isEmpty {
            print("     ❌ CRITICAL: No contour data found in any ROI Contour items")
            print("     💡 This RTStruct file appears to be reference-only (no geometry data)")
            print("     💡 SUGGESTION: Try test_rtstruct2.dcm instead")
        }
        
        return contoursByROI
    }
    
    // MARK: - CRITICAL FIX: Parse Nested Contour Sequence (3006,0040)
    private static func parseNestedContourSequence(_ roiContourItem: DICOMSequenceItem, roiNumber: Int) -> [SimpleContour] {
        print("       🔧 FIXED nested Contour Sequence (3006,0040) parsing...")
        
        var contours: [SimpleContour] = []
        
        // Method 1: Look for nested sequence in parsed elements
        let contourSequenceTag = DICOMTag(group: 0x3006, element: 0x0040)
        if let nestedSequence = roiContourItem.nestedSequences[contourSequenceTag] {
            print("       ✅ Found nested Contour Sequence with \(nestedSequence.items.count) items")
            
            for (contourIndex, contourItem) in nestedSequence.items.enumerated() {
                if let contour = parseIndividualContour(contourItem, index: contourIndex) {
                    contours.append(contour)
                }
            }
        }
        
        // Method 2: Manual search for Contour Sequence (3006,0040) in raw data
        if contours.isEmpty {
            print("       🔍 Manual search for Contour Sequence (3006,0040)...")
            contours = manualSearchForContourSequence(roiContourItem.data, roiNumber: roiNumber)
        }
        
        // Method 3: Direct search for Contour Data (3006,0050) tags
        if contours.isEmpty {
            print("       🔍 Direct search for Contour Data (3006,0050) tags...")
            contours = directSearchForContourData(roiContourItem.data, roiNumber: roiNumber)
        }
        
        // CRITICAL DEBUG: Show what we found
        if contours.isEmpty {
            print("       ❌ NO CONTOUR DATA FOUND - This RTStruct file appears to be reference-only")
            print("       💡 Try test_rtstruct2.dcm instead of test_rtstruct.dcm")
            
            // Show what elements we do have
            print("       📋 Available elements in this ROI item:")
            for (tag, data) in roiContourItem.elements {
                let tagStr = String(format: "(%04X,%04X)", tag.group, tag.element)
                print("         • \(tagStr): \(data.count) bytes")
            }
        }
        
        return contours
    }
    
    // MARK: - Manual Search for Contour Sequence (3006,0040)
    private static func manualSearchForContourSequence(_ data: Data, roiNumber: Int) -> [SimpleContour] {
        print("         🔍 Manual search for (3006,0040) in \(data.count) bytes...")
        
        var contours: [SimpleContour] = []
        var offset = 0
        
        while offset + 8 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            
            // Found Contour Sequence tag!
            if group == 0x3006 && element == 0x0040 {
                print("         ✅ FOUND Contour Sequence (3006,0040) at offset \(offset)!")
                
                let length = data.safeReadUInt32(at: offset + 4)
                let sequenceStart = offset + 8
                
                let sequenceData: Data
                if length == 0xFFFFFFFF {
                    // Undefined length - search for sequence delimiter
                    sequenceData = findUndefinedLengthSequenceData(data, startOffset: sequenceStart)
                } else if length > 0 && sequenceStart + Int(length) <= data.count {
                    sequenceData = data.subdata(in: sequenceStart..<sequenceStart + Int(length))
                } else {
                    offset += 2
                    continue
                }
                
                // Parse the contour sequence
                let nestedContours = parseContourSequenceItems(sequenceData)
                contours.append(contentsOf: nestedContours)
                
                print("         ✅ Parsed \(nestedContours.count) contours from nested sequence")
                
                // Move past this sequence
                offset = sequenceStart + sequenceData.count
            } else {
                offset += 2
            }
        }
        
        return contours
    }
    
    // MARK: - Direct Search for Contour Data
    private static func directSearchForContourData(_ data: Data, roiNumber: Int) -> [SimpleContour] {
        print("         🔍 Direct search for Contour Data (3006,0050) tags...")
        
        var contours: [SimpleContour] = []
        var offset = 0
        
        while offset + 8 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            
            // Found Contour Data tag!
            if group == 0x3006 && element == 0x0050 {
                print("         ✅ FOUND Contour Data (3006,0050) at offset \(offset)!")
                
                let length = data.safeReadUInt32(at: offset + 4)
                let valueOffset = offset + 8
                
                if length > 0 && length < 100000 && valueOffset + Int(length) <= data.count {
                    let contourDataRaw = data.subdata(in: valueOffset..<valueOffset + Int(length))
                    
                    if let coordinates = parseContourCoordinatesWithAllMethods(contourDataRaw) {
                        if coordinates.count >= 6 && coordinates.count % 3 == 0 {
                            // Convert to 3D points
                            var points: [SIMD3<Float>] = []
                            var zPosition: Float = 0.0
                            
                            for i in stride(from: 0, to: coordinates.count - 2, by: 3) {
                                let x = coordinates[i]
                                let y = coordinates[i + 1]
                                let z = coordinates[i + 2]
                                points.append(SIMD3<Float>(x, y, z))
                                zPosition = z
                            }
                            
                            print("         ✅ SUCCESS: Direct search found \(points.count) contour points at Z=\(String(format: "%.1f", zPosition))")
                            contours.append(SimpleContour(points: points, slicePosition: zPosition))
                        }
                    }
                }
                
                // Move past this tag
                offset = valueOffset + Int(length)
            } else {
                offset += 2
            }
        }
        
        return contours
    }
    
    // MARK: - Parse Contour Sequence Items
    private static func parseContourSequenceItems(_ data: Data) -> [SimpleContour] {
        print("           🔍 Parsing contour sequence items from \(data.count) bytes...")
        
        var contours: [SimpleContour] = []
        var offset = 0
        
        while offset + 8 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            
            // Look for sequence item start (FFFE,E000)
            if group == 0xFFFE && element == 0xE000 {
                let length = data.safeReadUInt32(at: offset + 4)
                let itemStart = offset + 8
                
                let itemData: Data
                if length == 0xFFFFFFFF {
                    // Undefined length - find item delimiter
                    itemData = findUndefinedLengthItemData(data, startOffset: itemStart)
                    offset = itemStart + itemData.count + 8 // Skip item delimiter
                } else if length > 0 && itemStart + Int(length) <= data.count {
                    itemData = data.subdata(in: itemStart..<itemStart + Int(length))
                    offset = itemStart + Int(length)
                } else {
                    offset += 2
                    continue
                }
                
                // Parse this contour item
                if let contour = parseContourItemForContourData(itemData) {
                    contours.append(contour)
                    print("           ✅ Parsed contour with \(contour.points.count) points")
                }
                
            } else if group == 0xFFFE && element == 0xE0DD {
                // Sequence delimiter - end
                print("           🏁 Found sequence delimiter")
                break
            } else {
                offset += 2
            }
        }
        
        return contours
    }
    
    // MARK: - Parse Individual Contour Item for Contour Data
    private static func parseContourItemForContourData(_ data: Data) -> SimpleContour? {
        print("             🔍 Searching for Contour Data (3006,0050) in item...")
        
        var offset = 0
        
        while offset + 8 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            
            // Found Contour Data!
            if group == 0x3006 && element == 0x0050 {
                print("             ✅ FOUND Contour Data (3006,0050) at offset \(offset)!")
                
                let length = data.safeReadUInt32(at: offset + 4)
                let valueOffset = offset + 8
                
                if length > 0 && length < 1000000 && valueOffset + Int(length) <= data.count {
                    let contourDataRaw = data.subdata(in: valueOffset..<valueOffset + Int(length))
                    
                    // Parse the coordinate data
                    if let coordinates = parseContourCoordinatesWithAllMethods(contourDataRaw) {
                        if coordinates.count >= 6 && coordinates.count % 3 == 0 {
                            // Convert to 3D points
                            var points: [SIMD3<Float>] = []
                            var zPosition: Float = 0.0
                            
                            for i in stride(from: 0, to: coordinates.count - 2, by: 3) {
                                let x = coordinates[i]
                                let y = coordinates[i + 1]
                                let z = coordinates[i + 2]
                                points.append(SIMD3<Float>(x, y, z))
                                zPosition = z
                            }
                            
                            print("             ✅ SUCCESS: Parsed \(points.count) contour points at Z=\(String(format: "%.1f", zPosition))")
                            return SimpleContour(points: points, slicePosition: zPosition)
                        }
                    }
                }
            }
            
            offset += 2
        }
        
        return nil
    }
    
    // MARK: - Direct Search for Contour Data (Fallback)
    private static func directSearchForContourData(_ data: Data, roiNumber: Int) -> [SimpleContour] {
        print("         🔍 Direct search for Contour Data (3006,0050) tags...")
        
        var contours: [SimpleContour] = []
        var offset = 0
        
        while offset + 8 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            
            // Found Contour Data tag directly!
            if group == 0x3006 && element == 0x0050 {
                print("         ✅ DIRECT FIND: Contour Data (3006,0050) at offset \(offset)!")
                
                let length = data.safeReadUInt32(at: offset + 4)
                let valueOffset = offset + 8
                
                if length > 0 && length < 1000000 && valueOffset + Int(length) <= data.count {
                    let contourDataRaw = data.subdata(in: valueOffset..<valueOffset + Int(length))
                    
                    if let coordinates = parseContourCoordinatesWithAllMethods(contourDataRaw) {
                        if coordinates.count >= 6 && coordinates.count % 3 == 0 {
                            var points: [SIMD3<Float>] = []
                            var zPosition: Float = 0.0
                            
                            for i in stride(from: 0, to: coordinates.count - 2, by: 3) {
                                let x = coordinates[i]
                                let y = coordinates[i + 1]
                                let z = coordinates[i + 2]
                                points.append(SIMD3<Float>(x, y, z))
                                zPosition = z
                            }
                            
                            let contour = SimpleContour(points: points, slicePosition: zPosition)
                            contours.append(contour)
                            
                            print("         ✅ DIRECT SUCCESS: \(points.count) points at Z=\(String(format: "%.1f", zPosition))")
                        }
                    }
                }
                
                // Move past this contour data
                offset = valueOffset + Int(length)
            } else {
                offset += 2
            }
        }
        
        return contours
    }
    
    // MARK: - Enhanced Contour Coordinate Parser with All Methods
    private static func parseContourCoordinatesWithAllMethods(_ data: Data) -> [Float]? {
        print("             📍 ENHANCED coordinate parsing from \(data.count) bytes...")
        
        // Show more detailed hex preview
        let hexPreview = data.prefix(min(128, data.count)).map { String(format: "%02X", $0) }.joined(separator: " ")
        print("             📍 Hex: \(hexPreview)")
        
        // Method 1: DICOM Decimal String (DS) with backslash separators
        if let coordinates = parseAsDecimalString(data) {
            return coordinates
        }
        
        // Method 2: Space-separated decimal string
        if let coordinates = parseAsSpaceSeparatedString(data) {
            return coordinates
        }
        
        // Method 3: Comma-separated decimal string
        if let coordinates = parseAsCommaSeparatedString(data) {
            return coordinates
        }
        
        // Method 4: Binary IEEE 754 float array
        if let coordinates = parseAsBinaryFloats(data) {
            return coordinates
        }
        
        // Method 5: ASCII numbers without separators (continuous string)
        if let coordinates = parseAsContinuousNumbers(data) {
            return coordinates
        }
        
        print("             ❌ All coordinate parsing methods failed")
        return nil
    }
    
    // MARK: - Coordinate Parsing Methods
    private static func parseAsDecimalString(_ data: Data) -> [Float]? {
        guard let asciiString = String(data: data, encoding: .ascii) else { return nil }
        
        let cleanString = asciiString.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !cleanString.isEmpty else { return nil }
        
        print("             📍 DS format: '\(cleanString.prefix(100))'...")
        
        let components = cleanString.components(separatedBy: "\\")
        let numbers = components.compactMap { 
            Float($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        if numbers.count >= 6 && numbers.count % 3 == 0 {
            print("             ✅ DS SUCCESS: \(numbers.count) coordinates")
            return numbers
        }
        
        return nil
    }
    
    private static func parseAsSpaceSeparatedString(_ data: Data) -> [Float]? {
        guard let asciiString = String(data: data, encoding: .ascii) else { return nil }
        
        let cleanString = asciiString.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !cleanString.isEmpty else { return nil }
        
        let components = cleanString.components(separatedBy: .whitespacesAndNewlines)
        let numbers = components.compactMap { Float($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        
        if numbers.count >= 6 && numbers.count % 3 == 0 {
            print("             ✅ SPACE SUCCESS: \(numbers.count) coordinates")
            return numbers
        }
        
        return nil
    }
    
    private static func parseAsCommaSeparatedString(_ data: Data) -> [Float]? {
        guard let asciiString = String(data: data, encoding: .ascii) else { return nil }
        
        let cleanString = asciiString.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !cleanString.isEmpty else { return nil }
        
        let components = cleanString.components(separatedBy: ",")
        let numbers = components.compactMap { Float($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        
        if numbers.count >= 6 && numbers.count % 3 == 0 {
            print("             ✅ COMMA SUCCESS: \(numbers.count) coordinates")
            return numbers
        }
        
        return nil
    }
    
    private static func parseAsBinaryFloats(_ data: Data) -> [Float]? {
        guard data.count % 4 == 0 && data.count >= 12 else { return nil }
        
        var numbers: [Float] = []
        for i in stride(from: 0, to: data.count - 3, by: 4) {
            let floatValue = data.safeReadFloat(at: i)
            // Validate reasonable coordinate range for medical imaging
            if abs(floatValue) < 10000 && !floatValue.isNaN && !floatValue.isInfinite {
                numbers.append(floatValue)
            } else {
                return nil // Invalid binary data
            }
        }
        
        if numbers.count >= 6 && numbers.count % 3 == 0 {
            print("             ✅ BINARY SUCCESS: \(numbers.count) coordinates")
            return numbers
        }
        
        return nil
    }
    
    private static func parseAsContinuousNumbers(_ data: Data) -> [Float]? {
        guard let asciiString = String(data: data, encoding: .ascii) else { return nil }
        
        let cleanString = asciiString.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard cleanString.count > 10 else { return nil } 
        
        // Try to split continuous numbers by detecting patterns
        let regex = try? NSRegularExpression(pattern: "-?\\d+\\.?\\d*", options: [])
        let matches = regex?.matches(in: cleanString, options: [], range: NSRange(location: 0, length: cleanString.count)) ?? []
        
        let numbers = matches.compactMap { match -> Float? in
            let range = Range(match.range, in: cleanString)!
            return Float(String(cleanString[range]))
        }
        
        if numbers.count >= 6 && numbers.count % 3 == 0 {
            print("             ✅ CONTINUOUS SUCCESS: \(numbers.count) coordinates")
            return numbers
        }
        
        return nil
    }
    
    // MARK: - FIXED FFFE Sequence Parser
    private static func parseSequenceWithProperFFEHandling(_ data: Data) -> DICOMSequence {
        print("       🔧 FIXED FFFE sequence parsing (\(data.count) bytes)...")
        
        var items: [DICOMSequenceItem] = []
        var offset = 0
        
        while offset + 8 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            
            // Sequence item start (FFFE,E000)
            if group == 0xFFFE && element == 0xE000 {
                let length = data.safeReadUInt32(at: offset + 4)
                offset += 8 // Skip item header
                
                let itemData: Data
                
                if length == 0xFFFFFFFF {
                    // Undefined length - find proper delimiter
                    itemData = findUndefinedLengthItemData(data, startOffset: offset)
                    offset += itemData.count + 8 // Skip past item and delimiter
                } else {
                    // Explicit length
                    if offset + Int(length) <= data.count {
                        itemData = data.subdata(in: offset..<offset + Int(length))
                        offset += Int(length)
                    } else {
                        break
                    }
                }
                
                // Parse elements and nested sequences within this item
                let (elements, nestedSequences) = parseSequenceItemWithNestedSequences(itemData)
                let item = DICOMSequenceItem(data: itemData, elements: elements, nestedSequences: nestedSequences)
                items.append(item)
                
                print("       📦 Parsed item: \(elements.count) elements, \(nestedSequences.count) nested sequences")
                
            } else if group == 0xFFFE && element == 0xE0DD {
                // Sequence delimiter - end of sequence
                print("       🏁 Found sequence delimiter")
                break
            } else {
                offset += 2
            }
        }
        
        print("       ✅ FIXED sequence parsing: \(items.count) items")
        return DICOMSequence(items: items)
    }
    
    // MARK: - Find Undefined Length Data with Proper Delimiter Detection
    private static func findUndefinedLengthItemData(_ data: Data, startOffset: Int) -> Data {
        var offset = startOffset
        
        while offset + 8 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            
            // Item delimiter (FFFE,E00D) or Sequence delimiter (FFFE,E0DD)
            if group == 0xFFFE && (element == 0xE00D || element == 0xE0DD) {
                return data.subdata(in: startOffset..<offset)
            }
            
            offset += 2
        }
        
        // No delimiter found - return rest of data
        return data.subdata(in: startOffset..<data.count)
    }
    
    private static func findUndefinedLengthSequenceData(_ data: Data, startOffset: Int) -> Data {
        var offset = startOffset
        
        while offset + 8 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            
            // Sequence delimiter (FFFE,E0DD)
            if group == 0xFFFE && element == 0xE0DD {
                return data.subdata(in: startOffset..<offset)
            }
            
            offset += 2
        }
        
        // No delimiter found - return rest of data
        return data.subdata(in: startOffset..<data.count)
    }
    
    // MARK: - Parse Sequence Item with Nested Sequences
    private static func parseSequenceItemWithNestedSequences(_ data: Data) -> ([DICOMTag: Data], [DICOMTag: DICOMSequence]) {
        var elements: [DICOMTag: Data] = [:]
        var nestedSequences: [DICOMTag: DICOMSequence] = [:]
        var offset = 0
        
        while offset + 8 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            
            // Skip FFFE delimiters
            if group == 0xFFFE {
                offset += 8
                continue
            }
            
            guard group > 0 && group < 0x7FFF && element < 0x7FFF else {
                offset += 2
                continue
            }
            
            let tag = DICOMTag(group: group, element: element)
            
            // Check for explicit VR
            let vr = String(data: data.subdata(in: (offset + 4)..<min(offset + 6, data.count)), encoding: .ascii)
            let isExplicitVR = vr?.count == 2 && vr!.allSatisfy({ $0.isLetter })
            
            let lengthOffset: Int
            let valueOffset: Int
            
            if isExplicitVR {
                if ["OB", "OW", "OF", "SQ", "UT", "UN"].contains(vr!) {
                    lengthOffset = offset + 8
                    valueOffset = offset + 12
                } else {
                    lengthOffset = offset + 6
                    valueOffset = offset + 8
                }
            } else {
                lengthOffset = offset + 4
                valueOffset = offset + 8
            }
            
            guard lengthOffset + 4 <= data.count else {
                offset += 2
                continue
            }
            
            let length: UInt32
            if valueOffset == offset + 8 && !isExplicitVR {
                length = data.safeReadUInt32(at: lengthOffset)
            } else if valueOffset == offset + 8 {
                length = UInt32(data.safeReadUInt16(at: lengthOffset))
            } else {
                length = data.safeReadUInt32(at: lengthOffset)
            }
            
            if length == 0xFFFFFFFF {
                // Undefined length - this is a sequence
                let sequenceData = findUndefinedLengthSequenceData(data, startOffset: valueOffset)
                let sequence = parseSequenceWithProperFFEHandling(sequenceData)
                nestedSequences[tag] = sequence
                
                print("         📦 Found nested sequence (\(String(format: "%04X", group)),\(String(format: "%04X", element))) with \(sequence.items.count) items")
                
                offset = valueOffset + sequenceData.count + 8 // Skip sequence delimiter
                
            } else if length > 0 && length < 1000000 && valueOffset + Int(length) <= data.count {
                let elementData = data.subdata(in: valueOffset..<valueOffset + Int(length))
                
                // Check if this is a sequence by VR or content
                if vr == "SQ" || (group == 0x3006 && element == 0x0040) {
                    let sequence = parseSequenceWithProperFFEHandling(elementData)
                    nestedSequences[tag] = sequence
                    print("         📦 Found nested sequence (\(String(format: "%04X", group)),\(String(format: "%04X", element))) with \(sequence.items.count) items")
                } else {
                    elements[tag] = elementData
                }
                
                offset = valueOffset + Int(length)
            } else {
                offset += 2
            }
        }
        
        return (elements, nestedSequences)
    }
    
    // MARK: - Contour Coordinate Parsing
    private static func parseContourCoordinatesWithAllMethods(_ data: Data) -> [Float]? {
        print("           🔢 Parsing contour coordinates from \(data.count) bytes...")
        
        // Method 1: Try as DICOM Decimal String (DS) format with backslash separators
        if let coordinates = parseAsDecimalString(data) {
            print("           ✅ SUCCESS: Parsed \(coordinates.count) coordinates as decimal string")
            return coordinates
        }
        
        // Method 2: Try as binary float array
        if let coordinates = parseAsBinaryFloats(data) {
            print("           ✅ SUCCESS: Parsed \(coordinates.count) coordinates as binary floats")
            return coordinates
        }
        
        // Method 3: Try as space-separated decimal string
        if let coordinates = parseAsSpaceSeparatedDecimals(data) {
            print("           ✅ SUCCESS: Parsed \(coordinates.count) coordinates as space-separated decimals")
            return coordinates
        }
        
        print("           ❌ FAILED: Could not parse coordinate data")
        // Debug: Show first 100 bytes as hex and text
        let debugBytes = data.prefix(100)
        let hexString = debugBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("           🔍 First 100 bytes (hex): \(hexString)")
        
        if let textString = String(data: debugBytes, encoding: .ascii) {
            print("           🔍 As ASCII text: '\(textString)'")
        }
        
        return nil
    }
    
    private static func parseAsDecimalString(_ data: Data) -> [Float]? {
        guard let string = String(data: data, encoding: .ascii) else { return nil }
        
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedString.isEmpty else { return nil }
        
        // Split by backslashes (DICOM DS format)
        let components = trimmedString.components(separatedBy: "\\")
        
        var coordinates: [Float] = []
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let value = Float(trimmed) {
                coordinates.append(value)
            }
        }
        
        return coordinates.count >= 6 && coordinates.count % 3 == 0 ? coordinates : nil
    }
    
    private static func parseAsBinaryFloats(_ data: Data) -> [Float]? {
        guard data.count >= 12 && data.count % 4 == 0 else { return nil }
        
        let floatCount = data.count / 4
        var coordinates: [Float] = []
        
        for i in 0..<floatCount {
            let offset = i * 4
            if offset + 4 <= data.count {
                let floatValue = data.safeReadFloat(at: offset)
                coordinates.append(floatValue)
            }
        }
        
        return coordinates.count >= 6 && coordinates.count % 3 == 0 ? coordinates : nil
    }
    
    private static func parseAsSpaceSeparatedDecimals(_ data: Data) -> [Float]? {
        guard let string = String(data: data, encoding: .ascii) else { return nil }
        
        let components = string.components(separatedBy: .whitespacesAndNewlines)
        var coordinates: [Float] = []
        
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let value = Float(trimmed) {
                coordinates.append(value)
            }
        }
        
        return coordinates.count >= 6 && coordinates.count % 3 == 0 ? coordinates : nil
    }
    
    // MARK: - CRITICAL FIX: Missing parseContourCoordinatesWithAllMethods function
    private static func parseContourCoordinatesWithAllMethods(_ data: Data) -> [Float]? {
        print("             🔍 Parsing contour coordinates from \(data.count) bytes...")
        
        // Method 1: Try as DICOM Decimal String (DS) format with backslash separators
        if let coordinates = parseAsDecimalString(data) {
            print("             ✅ SUCCESS: Parsed as decimal string format (\(coordinates.count/3) points)")
            return coordinates
        }
        
        // Method 2: Try as binary floats
        if let coordinates = parseAsBinaryFloats(data) {
            print("             ✅ SUCCESS: Parsed as binary floats (\(coordinates.count/3) points)")
            return coordinates
        }
        
        // Method 3: Try as space-separated decimals
        if let coordinates = parseAsSpaceSeparatedDecimals(data) {
            print("             ✅ SUCCESS: Parsed as space-separated decimals (\(coordinates.count/3) points)")
            return coordinates
        }
        
        // Debug: Show what we couldn't parse
        print("             ❌ FAILED to parse coordinates from \(data.count) bytes")
        if data.count < 200 {
            let hex = data.prefix(min(50, data.count)).map { String(format: "%02X", $0) }.joined(separator: " ")
            print("             🔍 Hex data: \(hex)")
            
            if let string = String(data: data, encoding: .ascii) {
                print("             🔍 ASCII: \"\(string.prefix(100))\"")
            }
        }
        
        return nil
    }
    
    // MARK: - Missing Helper Functions for Undefined Length Parsing
    private static func findUndefinedLengthSequenceData(_ data: Data, startOffset: Int) -> Data {
        var offset = startOffset
        
        while offset + 4 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            
            // Found sequence delimiter (FFFE,E0DD)
            if group == 0xFFFE && element == 0xE0DD {
                return data.subdata(in: startOffset..<offset)
            }
            
            offset += 2
        }
        
        // If no delimiter found, return rest of data
        return data.subdata(in: startOffset..<data.count)
    }
    
    private static func findUndefinedLengthItemData(_ data: Data, startOffset: Int) -> Data {
        var offset = startOffset
        
        while offset + 4 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            
            // Found item delimiter (FFFE,E00D) or sequence delimiter (FFFE,E0DD)
            if group == 0xFFFE && (element == 0xE00D || element == 0xE0DD) {
                return data.subdata(in: startOffset..<offset)
            }
            
            offset += 2
        }
        
        // If no delimiter found, return rest of data
        return data.subdata(in: startOffset..<data.count)
    }
    
    private static func parseSequenceWithProperFFEHandling(_ data: Data) -> DICOMSequence {
        print("       🔧 FIXED FFFE sequence parsing (\(data.count) bytes)...")
        
        var items: [DICOMSequenceItem] = []
        var offset = 0
        
        while offset + 8 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            
            // Found sequence item (FFFE,E000)
            if group == 0xFFFE && element == 0xE000 {
                let length = data.safeReadUInt32(at: offset + 4)
                let itemStart = offset + 8
                
                let itemData: Data
                if length == 0xFFFFFFFF {
                    // Undefined length - find delimiter
                    itemData = findUndefinedLengthItemData(data, startOffset: itemStart)
                    offset = itemStart + itemData.count + 8 // Skip delimiter
                } else if length > 0 && itemStart + Int(length) <= data.count {
                    itemData = data.subdata(in: itemStart..<itemStart + Int(length))
                    offset = itemStart + Int(length)
                } else {
                    offset += 2
                    continue
                }
                
                // Parse elements within this item
                let (elements, nestedSequences) = parseElementsInItem(itemData)
                
                let item = DICOMSequenceItem(
                    data: itemData,
                    elements: elements,
                    nestedSequences: nestedSequences
                )
                
                items.append(item)
                print("       📦 Parsed item: \(elements.count) elements, \(nestedSequences.count) nested sequences")
                
            } else if group == 0xFFFE && element == 0xE0DD {
                // Sequence delimiter - end
                print("       ✅ FIXED sequence parsing: \(items.count) items")
                break
            } else {
                offset += 2
            }
        }
        
        if items.isEmpty {
            print("       ⚠️ No sequence items found in \(data.count) bytes")
        }
        
        return DICOMSequence(items: items)
    }
    
    private static func parseElementsInItem(_ data: Data) -> ([DICOMTag: Data], [DICOMTag: DICOMSequence]) {
        var elements: [DICOMTag: Data] = [:]
        var nestedSequences: [DICOMTag: DICOMSequence] = [:]
        var offset = 0
        
        while offset + 8 <= data.count {
            let group = data.safeReadUInt16(at: offset)
            let element = data.safeReadUInt16(at: offset + 2)
            let tag = DICOMTag(group: group, element: element)
            
            // Skip FFFE tags (they are delimiters, not data)
            if group == 0xFFFE {
                offset += 8
                continue
            }
            
            let length = data.safeReadUInt32(at: offset + 4)
            let valueOffset = offset + 8
            
            if length == 0xFFFFFFFF {
                // Undefined length sequence
                let sequenceData = findUndefinedLengthSequenceData(data, startOffset: valueOffset)
                let sequence = parseSequenceWithProperFFEHandling(sequenceData)
                nestedSequences[tag] = sequence
                
                // Move past the sequence and its delimiter
                offset = valueOffset + sequenceData.count + 8
                print("         📦 Found nested sequence (\(String(format: \"%04X,%04X\", group, element))) with \(sequence.items.count) items")
                
            } else if length > 0 && valueOffset + Int(length) <= data.count {
                // Regular element with defined length
                let elementData = data.subdata(in: valueOffset..<valueOffset + Int(length))
                elements[tag] = elementData
                offset = valueOffset + Int(length)
                
            } else {
                // Invalid or zero-length element
                offset += 8
            }
        }
        
        return (elements, nestedSequences)
    }

    // MARK: - Parse Individual Contour
    private static func parseIndividualContour(_ contourItem: DICOMSequenceItem, index: Int) -> SimpleContour? {
        // Look for Contour Data (3006,0050) in this contour item
        let contourDataTag = DICOMTag(group: 0x3006, element: 0x0050)
        
        guard let contourDataElement = contourItem.elements[contourDataTag] else {
            print("         ⚠️ No Contour Data (3006,0050) in contour item \(index)")
            return nil
        }
        
        guard let coordinates = parseContourCoordinatesWithAllMethods(contourDataElement) else {
            print("         ❌ Could not parse contour coordinates in item \(index)")
            return nil
        }
        
        guard coordinates.count >= 6 && coordinates.count % 3 == 0 else {
            print("         ❌ Invalid coordinate count in item \(index): \(coordinates.count)")
            return nil
        }
        
        // Convert to 3D points
        var points: [SIMD3<Float>] = []
        var zPosition: Float = 0.0
        
        for i in stride(from: 0, to: coordinates.count - 2, by: 3) {
            let x = coordinates[i]
            let y = coordinates[i + 1]
            let z = coordinates[i + 2]
            points.append(SIMD3<Float>(x, y, z))
            zPosition = z
        }
        
        print("         ✅ Parsed contour \(index): \(points.count) points at Z=\(String(format: "%.1f", zPosition))")
        return SimpleContour(points: points, slicePosition: zPosition)
    }
    
    // MARK: - Utility Functions
    private static func extractIntegerFromSequenceItem(_ item: DICOMSequenceItem, group: UInt16, element: UInt16) -> Int? {
        let tag = DICOMTag(group: group, element: element)
        guard let data = item.elements[tag] else { return nil }
        
        if data.count == 2 {
            return Int(data.safeReadUInt16(at: 0))
        } else if data.count == 4 {
            return Int(data.safeReadUInt32(at: 0))
        } else if let stringValue = String(data: data, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let intValue = Int(stringValue) {
            return intValue
        }
        
        return nil
    }
    
    private static func extractStringFromSequenceItem(_ item: DICOMSequenceItem, group: UInt16, element: UInt16) -> String? {
        let tag = DICOMTag(group: group, element: element)
        guard let data = item.elements[tag] else { return nil }
        
        return String(data: data, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func combineROIMetadataWithContours(
        metadata: [(roiNumber: Int, roiName: String, displayColor: SIMD3<Float>)],
        contours: [Int: [SimpleContour]]
    ) -> [SimpleROIStructure] {
        
        var roiStructures: [SimpleROIStructure] = []
        
        for meta in metadata {
            let roiContours = contours[meta.roiNumber] ?? []
            
            // Only create ROI structure if we have actual contours
            if !roiContours.isEmpty {
                let roi = SimpleROIStructure(
                    roiNumber: meta.roiNumber,
                    roiName: meta.roiName,
                    displayColor: meta.displayColor,
                    contours: roiContours
                )
                roiStructures.append(roi)
                print("   ✅ Created ROI \(meta.roiNumber) '\(meta.roiName)' with \(roiContours.count) contours")
            } else {
                print("   ⚠️ Skipping ROI \(meta.roiNumber) '\(meta.roiName)' - no contour data found")
            }
        }
        
        return roiStructures
    }
    
    private static func generateROIColor(for index: Int) -> SIMD3<Float> {
        let colors: [SIMD3<Float>] = [
            SIMD3<Float>(1.0, 0.0, 0.0), // Red
            SIMD3<Float>(0.0, 1.0, 0.0), // Green
            SIMD3<Float>(0.0, 0.0, 1.0), // Blue
            SIMD3<Float>(1.0, 1.0, 0.0), // Yellow
            SIMD3<Float>(1.0, 0.0, 1.0), // Magenta
            SIMD3<Float>(0.0, 1.0, 1.0), // Cyan
            SIMD3<Float>(1.0, 0.5, 0.0), // Orange
            SIMD3<Float>(0.5, 0.0, 1.0), // Purple
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
