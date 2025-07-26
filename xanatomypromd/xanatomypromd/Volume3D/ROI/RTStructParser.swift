import Foundation
import simd

// MARK: - Universal RTStruct Parser
// Format-agnostic parser that handles RTStruct files from any medical software
// Works with TotalSegmentator, 3D Slicer, MIM, Eclipse, RayStation, etc.

public class RTStructParser {
    
    // MARK: - Main Parsing Interface
    
    /// Parse RTStruct from DICOM dataset using existing DICOM parser infrastructure
    public static func parseRTStruct(from dataset: DICOMDataset) throws -> RTStructData {
        // Validate RTStruct format
        let validation = RTStructValidator.validateRTStruct(dataset)
        if !validation.isValid {
            print("⚠️ RTStruct validation issues: \(validation.issues.joined(separator: ", "))")
            // Continue parsing despite warnings - some files may be valid but non-standard
        }
        
        print("📊 Parsing RTStruct DICOM data...")
        
        // Extract basic metadata
        let metadata = extractMetadata(from: dataset)
        
        // Parse using DICOM-aware sequence parsing (leverages existing parser)
        let roiDefinitions = try parseStructureSetROISequence(from: dataset)
        print("   🎯 Found \(roiDefinitions.count) ROI definitions")
        
        let roiContours = try parseROIContourSequence(from: dataset)
        print("   📐 Found \(roiContours.count) ROI contour sets")
        
        let roiObservations = parseRTROIObservationsSequence(from: dataset)
        print("   🎨 Found \(roiObservations.count) ROI observations")
        
        // Combine all data into complete ROI structures
        let roiStructures = try combineROIData(
            definitions: roiDefinitions,
            contours: roiContours,
            observations: roiObservations
        )
        
        print("   ✅ Successfully parsed \(roiStructures.count) complete ROI structures")
        
        // Log ROI structure details
        for roi in roiStructures {
            print("      🏷️ \(roi.roiName) (\(roi.contours.count) contours, \(roi.totalPoints) points)")
        }
        
        return RTStructData(
            patientName: metadata.patientName,
            studyInstanceUID: metadata.studyInstanceUID,
            seriesInstanceUID: metadata.seriesInstanceUID,
            structureSetLabel: metadata.structureSetLabel,
            structureSetName: metadata.structureSetName,
            structureSetDescription: metadata.structureSetDescription,
            structureSetDate: metadata.structureSetDate,
            structureSetTime: metadata.structureSetTime,
            roiStructures: roiStructures,
            referencedFrameOfReferenceUID: metadata.referencedFrameOfReferenceUID,
            referencedStudyInstanceUID: metadata.referencedStudyInstanceUID,
            referencedSeriesInstanceUID: metadata.referencedSeriesInstanceUID
        )
    }
    
    // MARK: - Metadata Extraction
    
    private static func extractMetadata(from dataset: DICOMDataset) -> RTStructMetadata {
        return RTStructMetadata(
            patientName: dataset.getString(tag: DICOMTag.patientName),
            studyInstanceUID: dataset.getString(tag: DICOMTag.studyInstanceUID),
            seriesInstanceUID: dataset.getString(tag: DICOMTag.seriesInstanceUID),
            structureSetLabel: dataset.getString(tag: DICOMTag.structureSetLabel),
            structureSetName: dataset.getString(tag: DICOMTag.structureSetName),
            structureSetDescription: dataset.getString(tag: DICOMTag.structureSetDescription),
            structureSetDate: dataset.getString(tag: DICOMTag.structureSetDate),
            structureSetTime: dataset.getString(tag: DICOMTag.structureSetTime),
            referencedFrameOfReferenceUID: extractReferencedFrameOfReference(from: dataset),
            referencedStudyInstanceUID: extractReferencedStudyUID(from: dataset),
            referencedSeriesInstanceUID: extractReferencedSeriesUID(from: dataset)
        )
    }
    
    // MARK: - Universal Sequence Parsing (Format-Agnostic)
    
    /// Parse Structure Set ROI Sequence using DICOM parser infrastructure
    private static func parseStructureSetROISequence(from dataset: DICOMDataset) throws -> [ROIDefinition] {
        guard let sequenceElement = dataset.elements[DICOMTag.structureSetROISequence] else {
            throw RTStructError.missingRequiredSequence("Structure Set ROI Sequence")
        }
        
        print("   📋 Parsing Structure Set ROI Sequence...")
        print("   🔍 DEBUG: Structure Set ROI Sequence data length: \(sequenceElement.data.count) bytes")
        
        // Use robust sequence parsing that handles all formats
        let sequenceItems = try parseUniversalDICOMSequence(sequenceElement.data)
        print("   📊 Found \(sequenceItems.count) sequence items in Structure Set ROI")
        
        var roiDefinitions: [ROIDefinition] = []
        
        for (index, item) in sequenceItems.enumerated() {
            do {
                // Extract ROI Number (3006,0022)
                let roiNumber = extractIntFromItem(item, tag: DICOMTag.roiNumber) ?? (index + 1)
                
                // Extract ROI Name (3006,0026)
                let roiName = extractStringFromItem(item, tag: DICOMTag.roiName) ?? "ROI \(roiNumber)"
                
                // Extract optional fields
                let roiDescription = extractStringFromItem(item, tag: DICOMTag.roiDescription)
                let roiGenerationAlgorithm = extractStringFromItem(item, tag: DICOMTag.roiGenerationAlgorithm)
                
                let definition = ROIDefinition(
                    roiNumber: roiNumber,
                    roiName: roiName,
                    roiDescription: roiDescription,
                    roiGenerationAlgorithm: roiGenerationAlgorithm
                )
                
                roiDefinitions.append(definition)
                
                print("      📍 ROI \(roiNumber): \(roiName)")
                
            } catch {
                print("      ⚠️ Failed to parse ROI definition \(index): \(error)")
            }
        }
        
        return roiDefinitions
    }
    
    /// Parse ROI Contour Sequence using DICOM parser infrastructure
    private static func parseROIContourSequence(from dataset: DICOMDataset) throws -> [ROIContourSet] {
        guard let sequenceElement = dataset.elements[DICOMTag.roiContourSequence] else {
            throw RTStructError.missingRequiredSequence("ROI Contour Sequence")
        }
        
        print("   🖼️ Parsing ROI Contour Sequence...")
        print("   🔍 DEBUG: ROI Contour Sequence data length: \(sequenceElement.data.count) bytes")
        
        let sequenceItems = try parseUniversalDICOMSequence(sequenceElement.data)
        print("   📊 Found \(sequenceItems.count) sequence items in ROI Contour")
        
        var contourSets: [ROIContourSet] = []
        
        for (index, item) in sequenceItems.enumerated() {
            do {
                // Extract Referenced ROI Number
                let referencedROINumber = extractIntFromItem(item, tag: DICOMTag.referencedROINumber) ?? (index + 1)
                
                // Extract display color
                let displayColor = extractDisplayColorFromItem(item)
                
                // Parse contour sequence within this ROI contour set
                let contours = try parseContourSequence(from: item)
                
                let contourSet = ROIContourSet(
                    referencedROINumber: referencedROINumber,
                    displayColor: displayColor,
                    contours: contours
                )
                
                contourSets.append(contourSet)
                
                print("      🖼️ ROI \(referencedROINumber): \(contours.count) contours, Color: (\(displayColor.x), \(displayColor.y), \(displayColor.z))")
                
            } catch {
                print("      ⚠️ Failed to parse ROI contour set \(index): \(error)")
            }
        }
        
        return contourSets
    }
    
    /// Parse RT ROI Observations Sequence using DICOM parser infrastructure
    private static func parseRTROIObservationsSequence(from dataset: DICOMDataset) -> [ROIObservation] {
        guard let sequenceElement = dataset.elements[DICOMTag.rtROIObservationsSequence] else {
            print("   ℹ️ No RT ROI Observations Sequence found (optional)")
            return []
        }
        
        print("   👁️ Parsing RT ROI Observations Sequence...")
        
        do {
            let sequenceItems = try parseUniversalDICOMSequence(sequenceElement.data)
            print("   📊 Found \(sequenceItems.count) sequence items in RT ROI Observations")
            
            var observations: [ROIObservation] = []
            
            for (index, item) in sequenceItems.enumerated() {
                let observationNumber = extractIntFromItem(item, tag: DICOMTag.observationNumber) ?? (index + 1)
                let referencedROINumber = extractIntFromItem(item, tag: DICOMTag.referencedROINumber) ?? (index + 1)
                let roiObservationLabel = extractStringFromItem(item, tag: DICOMTag.roiObservationLabel)
                let rtROIInterpretedType = extractStringFromItem(item, tag: DICOMTag.rtROIInterpretedType)
                let roiInterpreter = extractStringFromItem(item, tag: DICOMTag.roiInterpreter)
                
                let observation = ROIObservation(
                    observationNumber: observationNumber,
                    referencedROINumber: referencedROINumber,
                    roiObservationLabel: roiObservationLabel,
                    rtROIInterpretedType: rtROIInterpretedType,
                    roiInterpreter: roiInterpreter
                )
                
                observations.append(observation)
                
                print("      👁️ Observation \(observationNumber): ROI \(referencedROINumber), Type: \(rtROIInterpretedType ?? "N/A")")
            }
            
            return observations
            
        } catch {
            print("   ⚠️ Failed to parse RT ROI Observations: \(error)")
            return []
        }
    }
    
    // MARK: - Universal DICOM Sequence Parser (Handles All Formats)
    
    /// Universal sequence parser that handles different DICOM formats robustly
    private static func parseUniversalDICOMSequence(_ sequenceData: Data) throws -> [UniversalSequenceItem] {
        var items: [UniversalSequenceItem] = []
        var offset = 0
        
        print("      🔍 DEBUG: Parsing sequence data, total length: \(sequenceData.count) bytes")
        
        // Try multiple parsing strategies to handle different formats
        
        // Strategy 1: Standard DICOM sequence with item tags (FFFE,E000)
        if let standardItems = tryParseStandardSequence(sequenceData) {
            print("      ✅ Successfully parsed using standard DICOM sequence format")
            return standardItems
        }
        
        // Strategy 2: Implicit VR sequence parsing
        if let implicitItems = tryParseImplicitVRSequence(sequenceData) {
            print("      ✅ Successfully parsed using implicit VR sequence format")
            return implicitItems
        }
        
        // Strategy 3: Nested element parsing (for complex RTStruct formats)
        if let nestedItems = tryParseNestedSequence(sequenceData) {
            print("      ✅ Successfully parsed using nested sequence format")
            return nestedItems
        }
        
        // Strategy 4: Raw element list (fallback for non-standard formats)
        if let rawItems = tryParseRawElementSequence(sequenceData) {
            print("      ✅ Successfully parsed using raw element sequence format")
            return rawItems
        }
        
        print("      ⚠️ Unable to parse sequence with any known format")
        return []
    }
    
    /// Try parsing as standard DICOM sequence with proper item delimiters
    private static func tryParseStandardSequence(_ data: Data) -> [UniversalSequenceItem]? {
        var items: [UniversalSequenceItem] = []
        var offset = 0
        
        while offset + 8 <= data.count {
            let group = data.readUInt16(at: offset, littleEndian: true)
            let element = data.readUInt16(at: offset + 2, littleEndian: true)
            let length = data.readUInt32(at: offset + 4, littleEndian: true)
            
            offset += 8
            
            if group == 0xFFFE && element == 0xE000 {
                // Found sequence item
                let itemLength = Int(length)
                
                if length == 0xFFFFFFFF {
                    // Undefined length - find delimiter
                    if let itemData = findItemWithUndefinedLength(data, startOffset: offset) {
                        if let item = parseItemData(itemData) {
                            items.append(item)
                        }
                        offset += itemData.count + 8
                    } else {
                        break
                    }
                } else if itemLength > 0 && offset + itemLength <= data.count {
                    // Defined length
                    let itemData = data.subdata(in: offset..<offset + itemLength)
                    if let item = parseItemData(itemData) {
                        items.append(item)
                    }
                    offset += itemLength
                } else {
                    break
                }
            } else if group == 0xFFFE && element == 0xE0DD {
                // Sequence delimiter
                break
            } else {
                // Skip unknown data
                if length != 0xFFFFFFFF && length > 0 {
                    offset += Int(length)
                } else {
                    break
                }
            }
        }
        
        return items.isEmpty ? nil : items
    }
    
    /// Try parsing as implicit VR sequence
    private static func tryParseImplicitVRSequence(_ data: Data) -> [UniversalSequenceItem]? {
        // Implementation for implicit VR sequences
        // This handles sequences that don't use standard item delimiters
        var items: [UniversalSequenceItem] = []
        var offset = 0
        
        // Look for repeated patterns that suggest sequence items
        while offset + 8 <= data.count {
            var elements: [DICOMTag: Data] = [:]
            let startOffset = offset
            var itemLength = 0
            
            // Try to parse elements until we find a pattern break
            while offset + 8 <= data.count {
                let group = data.readUInt16(at: offset, littleEndian: true)
                let element = data.readUInt16(at: offset + 2, littleEndian: true)
                let tag = DICOMTag(group: group, element: element)
                
                offset += 4
                
                guard offset + 4 <= data.count else { break }
                let length = data.readUInt32(at: offset, littleEndian: true)
                offset += 4
                
                if length == 0xFFFFFFFF || length > UInt32(data.count - offset) {
                    break
                }
                
                let elementLength = Int(length)
                guard offset + elementLength <= data.count else { break }
                
                let elementData = data.subdata(in: offset..<offset + elementLength)
                elements[tag] = elementData
                
                offset += elementLength
                itemLength = offset - startOffset
                
                // Check if we've found ROI-specific tags that suggest item boundary
                if tag == DICOMTag.roiNumber || tag == DICOMTag.referencedROINumber {
                    // This might be the start of a new item
                    if !elements.isEmpty {
                        items.append(UniversalSequenceItem(elements: elements))
                        elements.removeAll()
                    }
                }
            }
            
            if !elements.isEmpty {
                items.append(UniversalSequenceItem(elements: elements))
            }
            
            if itemLength == 0 {
                break
            }
        }
        
        return items.isEmpty ? nil : items
    }
    
    /// Try parsing as nested sequence structure
    private static func tryParseNestedSequence(_ data: Data) -> [UniversalSequenceItem]? {
        // Implementation for nested sequences (common in complex RTStruct files)
        // This handles sequences within sequences
        return nil // Placeholder - implement if needed
    }
    
    /// Try parsing as raw element sequence (fallback)
    private static func tryParseRawElementSequence(_ data: Data) -> [UniversalSequenceItem]? {
        // Last resort: treat entire sequence as single item with all elements
        if let item = parseItemData(data) {
            return [item]
        }
        return nil
    }
    
    // MARK: - Utility Functions
    
    private static func parseItemData(_ itemData: Data) -> UniversalSequenceItem? {
        var elements: [DICOMTag: Data] = [:]
        var offset = 0
        
        while offset + 8 <= itemData.count {
            let group = itemData.readUInt16(at: offset, littleEndian: true)
            let element = itemData.readUInt16(at: offset + 2, littleEndian: true)
            let tag = DICOMTag(group: group, element: element)
            
            offset += 4
            
            guard offset + 4 <= itemData.count else { break }
            let length = itemData.readUInt32(at: offset, littleEndian: true)
            offset += 4
            
            if length == 0xFFFFFFFF {
                break
            }
            
            let dataLength = Int(length)
            guard offset + dataLength <= itemData.count else { break }
            
            let elementData = itemData.subdata(in: offset..<offset + dataLength)
            elements[tag] = elementData
            
            offset += dataLength
        }
        
        return elements.isEmpty ? nil : UniversalSequenceItem(elements: elements)
    }
    
    private static func findItemWithUndefinedLength(_ data: Data, startOffset: Int) -> Data? {
        var offset = startOffset
        
        while offset + 8 <= data.count {
            let group = data.readUInt16(at: offset, littleEndian: true)
            let element = data.readUInt16(at: offset + 2, littleEndian: true)
            
            if group == 0xFFFE && element == 0xE00D {
                // Found item delimiter
                return data.subdata(in: startOffset..<offset)
            }
            
            offset += 8
            let length = data.readUInt32(at: offset - 4, littleEndian: true)
            if length != 0xFFFFFFFF {
                offset += Int(length)
            }
        }
        
        return nil
    }
    
    // MARK: - Data Extraction (Universal)
    
    private static func extractStringFromItem(_ item: UniversalSequenceItem, tag: DICOMTag) -> String? {
        guard let data = item.elements[tag] else { return nil }
        return String(data: data, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func extractIntFromItem(_ item: UniversalSequenceItem, tag: DICOMTag) -> Int? {
        guard let data = item.elements[tag] else { return nil }
        
        if data.count >= 2 {
            return Int(data.readUInt16(at: 0, littleEndian: true))
        } else if data.count >= 4 {
            return Int(data.readUInt32(at: 0, littleEndian: true))
        }
        
        return nil
    }
    
    private static func extractDisplayColorFromItem(_ item: UniversalSequenceItem) -> SIMD3<Float> {
        guard let colorData = item.elements[DICOMTag.roiDisplayColor] else {
            return StandardROIColors.getColorForROI("Unknown")
        }
        
        // DICOM color is stored as 3 unsigned shorts (RGB, 0-65535 range)
        guard colorData.count >= 6 else {
            return StandardROIColors.getColorForROI("Unknown")
        }
        
        let r = Float(colorData.readUInt16(at: 0, littleEndian: true)) / 65535.0
        let g = Float(colorData.readUInt16(at: 2, littleEndian: true)) / 65535.0
        let b = Float(colorData.readUInt16(at: 4, littleEndian: true)) / 65535.0
        
        return SIMD3<Float>(r, g, b)
    }
    
    // MARK: - Contour Parsing
    
    private static func parseContourSequence(from roiContourItem: UniversalSequenceItem) throws -> [ROIContour] {
        guard let contourSequenceData = roiContourItem.elements[DICOMTag.contourSequence] else {
            print("        ℹ️ No contour sequence found in this ROI")
            return []
        }
        
        let contourItems = try parseUniversalDICOMSequence(contourSequenceData)
        var contours: [ROIContour] = []
        
        for (contourIndex, contourItem) in contourItems.enumerated() {
            do {
                // Extract geometric type
                let geometricTypeString = extractStringFromItem(contourItem, tag: DICOMTag.contourGeometricType) ?? "CLOSED_PLANAR"
                let geometricType = ContourGeometricType(rawValue: geometricTypeString) ?? .closedPlanar
                
                // Extract number of points
                let numberOfPoints = extractIntFromItem(contourItem, tag: DICOMTag.numberOfContourPoints) ?? 0
                
                // Extract contour data
                let contourDataString = extractStringFromItem(contourItem, tag: DICOMTag.contourData) ?? ""
                let contourPoints = parseContourDataPoints(contourDataString)
                
                // Extract slice position
                let slicePosition = contourPoints.first?.z ?? 0.0
                
                let contour = ROIContour(
                    contourNumber: contourIndex + 1,
                    geometricType: geometricType,
                    numberOfPoints: contourPoints.count,
                    contourData: contourPoints,
                    slicePosition: slicePosition,
                    referencedSOPInstanceUID: nil
                )
                
                contours.append(contour)
                
                print("        📐 Contour \(contourIndex + 1): \(geometricType.rawValue), \(contourPoints.count) points, Z=\(String(format: "%.1f", slicePosition))")
                
            } catch {
                print("        ⚠️ Failed to parse contour \(contourIndex): \(error)")
            }
        }
        
        return contours
    }
    
    /// Parse contour data string into 3D points
    private static func parseContourDataPoints(_ contourDataString: String) -> [SIMD3<Float>] {
        // DICOM contour data is stored as "x1\y1\z1\x2\y2\z2\..." where \ is the delimiter
        let components = contourDataString.split(separator: "\\").compactMap { Float(String($0)) }
        
        guard components.count % 3 == 0 else {
            print("        ⚠️ Invalid contour data: \(components.count) components (not divisible by 3)")
            return []
        }
        
        var points: [SIMD3<Float>] = []
        
        for i in stride(from: 0, to: components.count, by: 3) {
            let point = SIMD3<Float>(
                components[i],     // X coordinate
                components[i + 1], // Y coordinate
                components[i + 2]  // Z coordinate
            )
            points.append(point)
        }
        
        return points
    }
    
    // MARK: - Data Combination
    
    private static func combineROIData(
        definitions: [ROIDefinition],
        contours: [ROIContourSet],
        observations: [ROIObservation]
    ) throws -> [ROIStructure] {
        
        var roiStructures: [ROIStructure] = []
        
        for definition in definitions {
            // Find matching contour set
            let contourSet = contours.first { $0.referencedROINumber == definition.roiNumber }
            
            // Find matching observation (unused variable fixed)
            _ = observations.first { $0.referencedROINumber == definition.roiNumber }
            
            // Determine display color
            let displayColor = contourSet?.displayColor ?? StandardROIColors.getColorForROI(definition.roiName)
            
            // Create ROI structure
            let roiStructure = ROIStructure(
                roiNumber: definition.roiNumber,
                roiName: definition.roiName,
                roiDescription: definition.roiDescription,
                roiGenerationAlgorithm: definition.roiGenerationAlgorithm,
                displayColor: displayColor,
                isVisible: true,
                opacity: 0.5,
                contours: contourSet?.contours ?? []
            )
            
            roiStructures.append(roiStructure)
        }
        
        return roiStructures
    }
    
    // MARK: - Reference Extraction Helpers
    
    private static func extractReferencedFrameOfReference(from dataset: DICOMDataset) -> String? {
        return dataset.getString(tag: DICOMTag.frameOfReferenceUID)
    }
    
    private static func extractReferencedStudyUID(from dataset: DICOMDataset) -> String? {
        return dataset.getString(tag: DICOMTag.studyInstanceUID)
    }
    
    private static func extractReferencedSeriesUID(from dataset: DICOMDataset) -> String? {
        return nil
    }
}

// MARK: - Universal Sequence Item

private struct UniversalSequenceItem {
    let elements: [DICOMTag: Data]
    
    init(elements: [DICOMTag: Data]) {
        self.elements = elements
    }
}

// MARK: - Internal Data Structures (unchanged)

private struct RTStructMetadata {
    let patientName: String?
    let studyInstanceUID: String?
    let seriesInstanceUID: String?
    let structureSetLabel: String?
    let structureSetName: String?
    let structureSetDescription: String?
    let structureSetDate: String?
    let structureSetTime: String?
    let referencedFrameOfReferenceUID: String?
    let referencedStudyInstanceUID: String?
    let referencedSeriesInstanceUID: String?
}

private struct ROIDefinition {
    let roiNumber: Int
    let roiName: String
    let roiDescription: String?
    let roiGenerationAlgorithm: String?
}

private struct ROIContourSet {
    let referencedROINumber: Int
    let displayColor: SIMD3<Float>
    let contours: [ROIContour]
}

private struct ROIObservation {
    let observationNumber: Int
    let referencedROINumber: Int
    let roiObservationLabel: String?
    let rtROIInterpretedType: String?
    let roiInterpreter: String?
}

private struct RawSequenceItem {
    let elements: [DICOMTag: Data]
    
    init(elements: [DICOMTag: Data]) {
        self.elements = elements
    }
}

// MARK: - Testing and Validation (unchanged)

extension RTStructParser {
    
    /// Quick test parse to validate RTStruct format
    public static func testParseRTStruct(from dataset: DICOMDataset) -> (success: Bool, message: String) {
        do {
            let rtStructData = try parseRTStruct(from: dataset)
            let stats = rtStructData.getStatistics()
            return (true, "✅ RTStruct parsed successfully: \(stats.description)")
        } catch {
            return (false, "❌ RTStruct parsing failed: \(error.localizedDescription)")
        }
    }
    
    /// Get basic RTStruct information without full parsing
    public static func getRTStructInfo(from dataset: DICOMDataset) -> String {
        var info = "📊 RTStruct Information:\n"
        
        if let structureSetName = dataset.getString(tag: DICOMTag.structureSetName) {
            info += "   🏷️ Name: \(structureSetName)\n"
        }
        
        if let structureSetDescription = dataset.getString(tag: DICOMTag.structureSetDescription) {
            info += "   📝 Description: \(structureSetDescription)\n"
        }
        
        if let structureSetDate = dataset.getString(tag: DICOMTag.structureSetDate) {
            info += "   📅 Date: \(structureSetDate)\n"
        }
        
        // Check for required sequences
        let hasStructureSetROI = dataset.elements[DICOMTag.structureSetROISequence] != nil
        let hasROIContour = dataset.elements[DICOMTag.roiContourSequence] != nil
        let hasROIObservations = dataset.elements[DICOMTag.rtROIObservationsSequence] != nil
        
        info += "   📋 Structure Set ROI Sequence: \(hasStructureSetROI ? "✅" : "❌")\n"
        info += "   🖼️ ROI Contour Sequence: \(hasROIContour ? "✅" : "❌")\n"
        info += "   👁️ RT ROI Observations: \(hasROIObservations ? "✅" : "❌")\n"
        
        return info
    }
}

// MARK: - Updated RTStruct Parser with Raw Data Access

// Add this method to RTStructParser.swift to use raw data parsing:

extension RTStructParser {
    
    /// Parse RTStruct using raw data access for sequences
    public static func parseRTStructWithRawData(from dataset: DICOMDataset, rawData: Data) throws -> RTStructData {
        print("📊 Parsing RTStruct DICOM data with raw sequence access...")
        
        // Extract basic metadata (this works fine)
        let metadata = extractMetadata(from: dataset)
        
        // Parse sequences using raw data access
        let roiDefinitions = try parseStructureSetROISequenceFromRaw(dataset: dataset, rawData: rawData)
        print("   🎯 Found \(roiDefinitions.count) ROI definitions")
        
        let roiContours = try parseROIContourSequenceFromRaw(dataset: dataset, rawData: rawData)
        print("   📐 Found \(roiContours.count) ROI contour sets")
        
        let roiObservations = parseRTROIObservationsSequenceFromRaw(dataset: dataset, rawData: rawData)
        print("   🎨 Found \(roiObservations.count) ROI observations")
        
        // Combine all data into complete ROI structures
        let roiStructures = try combineROIData(
            definitions: roiDefinitions,
            contours: roiContours,
            observations: roiObservations
        )
        
        print("   ✅ Successfully parsed \(roiStructures.count) complete ROI structures")
        
        for roi in roiStructures {
            print("      🏷️ \(roi.roiName) (\(roi.contours.count) contours, \(roi.totalPoints) points)")
        }
        
        return RTStructData(
            patientName: metadata.patientName,
            studyInstanceUID: metadata.studyInstanceUID,
            seriesInstanceUID: metadata.seriesInstanceUID,
            structureSetLabel: metadata.structureSetLabel,
            structureSetName: metadata.structureSetName,
            structureSetDescription: metadata.structureSetDescription,
            structureSetDate: metadata.structureSetDate,
            structureSetTime: metadata.structureSetTime,
            roiStructures: roiStructures,
            referencedFrameOfReferenceUID: metadata.referencedFrameOfReferenceUID,
            referencedStudyInstanceUID: metadata.referencedStudyInstanceUID,
            referencedSeriesInstanceUID: metadata.referencedSeriesInstanceUID
        )
    }
    
    /// Parse Structure Set ROI Sequence from raw DICOM data
    private static func parseStructureSetROISequenceFromRaw(dataset: DICOMDataset, rawData: Data) throws -> [ROIDefinition] {
        print("   📋 Parsing Structure Set ROI Sequence from raw data...")
        
        guard let sequenceData = dataset.getSequenceData(tag: DICOMTag.structureSetROISequence, fromRawData: rawData) else {
            throw RTStructError.missingRequiredSequence("Structure Set ROI Sequence")
        }
        
        print("   🔍 Extracted sequence data: \(sequenceData.count) bytes")
        
        // Parse the sequence items from raw data
        let sequenceItems = parseSequenceItemsFromRawData(sequenceData)
        print("   📊 Found \(sequenceItems.count) sequence items")
        
        var roiDefinitions: [ROIDefinition] = []
        
        for (index, item) in sequenceItems.enumerated() {
            let roiNumber = extractIntFromRawItem(item, tag: DICOMTag.roiNumber) ?? (index + 1)
            let roiName = extractStringFromRawItem(item, tag: DICOMTag.roiName) ?? "ROI \(roiNumber)"
            let roiDescription = extractStringFromRawItem(item, tag: DICOMTag.roiDescription)
            let roiGenerationAlgorithm = extractStringFromRawItem(item, tag: DICOMTag.roiGenerationAlgorithm)
            
            let definition = ROIDefinition(
                roiNumber: roiNumber,
                roiName: roiName,
                roiDescription: roiDescription,
                roiGenerationAlgorithm: roiGenerationAlgorithm
            )
            
            roiDefinitions.append(definition)
            print("      📍 ROI \(roiNumber): \(roiName)")
        }
        
        return roiDefinitions
    }
    
    /// Parse ROI Contour Sequence from raw DICOM data
    private static func parseROIContourSequenceFromRaw(dataset: DICOMDataset, rawData: Data) throws -> [ROIContourSet] {
        print("   🖼️ Parsing ROI Contour Sequence from raw data...")
        
        guard let sequenceData = dataset.getSequenceData(tag: DICOMTag.roiContourSequence, fromRawData: rawData) else {
            throw RTStructError.missingRequiredSequence("ROI Contour Sequence")
        }
        
        print("   🔍 Extracted sequence data: \(sequenceData.count) bytes")
        
        // 🎯 MIM ROI CONTOUR RAW DEBUG - Find actual ROI contour items
        print("   🔍 MIM ROI CONTOUR RAW DEBUG:")
        print("   🔍 Total bytes: \(sequenceData.count)")
        print("   🔍 Looking for ROI contour item delimiters...")

        var itemCount = 0
        var offset = 0
        while offset + 8 <= sequenceData.count {
            let group = sequenceData.readUInt16(at: offset, littleEndian: true)
            let element = sequenceData.readUInt16(at: offset + 2, littleEndian: true)
            let length = sequenceData.readUInt32(at: offset + 4, littleEndian: true)
            
            if group == 0xFFFE && element == 0xE000 {
                itemCount += 1
                print("   🎯 Item \(itemCount) at offset \(offset), length: \(length == 0xFFFFFFFF ? "undefined" : String(length))")
                
                // Show next few bytes to see the structure
                let nextBytes = sequenceData.subdata(in: offset+8..<min(offset+32, sequenceData.count))
                let hexString = nextBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                print("      Next 24 bytes: \(hexString)")
            }
            
            offset += 2
        }
        print("   📊 Total items found: \(itemCount)")
        
        // Original contour sequence tag search
        print("   🔍 MIM DEBUG: Analyzing \(sequenceData.count) bytes for hidden contour data...")
        print("   🔍 Searching for contour sequence tags (3006,0040) in raw data...")

        // Search for contour sequence pattern in the raw bytes
        offset = 0
        var foundContourTags = 0
        while offset + 4 <= sequenceData.count {
            let group = sequenceData.readUInt16(at: offset, littleEndian: true)
            let element = sequenceData.readUInt16(at: offset + 2, littleEndian: true)
            
            if group == 0x3006 && element == 0x0040 {
                foundContourTags += 1
                print("   🎯 Found contour sequence tag at offset \(offset)")
            }
            offset += 2
        }
        print("   📊 Total contour sequence tags found: \(foundContourTags)")
        
        let sequenceItems = parseSequenceItemsFromRawData(sequenceData)
        print("   📊 Found \(sequenceItems.count) sequence items")
        
        var contourSets: [ROIContourSet] = []
        
        for (index, item) in sequenceItems.enumerated() {
            let referencedROINumber = extractIntFromRawItem(item, tag: DICOMTag.referencedROINumber) ?? (index + 1)
            let displayColor = extractDisplayColorFromRawItem(item)
            
            // Parse nested contour sequence
            let contours = parseContourSequenceFromRawItem(item)
            
            let contourSet = ROIContourSet(
                referencedROINumber: referencedROINumber,
                displayColor: displayColor,
                contours: contours
            )
            
            contourSets.append(contourSet)
            print("      🖼️ ROI \(referencedROINumber): \(contours.count) contours")
        }
        
        return contourSets
    }
    
    /// Parse RT ROI Observations Sequence from raw DICOM data
    private static func parseRTROIObservationsSequenceFromRaw(dataset: DICOMDataset, rawData: Data) -> [ROIObservation] {
        print("   👁️ Parsing RT ROI Observations Sequence from raw data...")
        
        guard let sequenceData = dataset.getSequenceData(tag: DICOMTag.rtROIObservationsSequence, fromRawData: rawData) else {
            print("   ℹ️ No RT ROI Observations Sequence found (optional)")
            return []
        }
        
        print("   🔍 Extracted sequence data: \(sequenceData.count) bytes")
        
        let sequenceItems = parseSequenceItemsFromRawData(sequenceData)
        print("   📊 Found \(sequenceItems.count) sequence items")
        
        var observations: [ROIObservation] = []
        
        for (index, item) in sequenceItems.enumerated() {
            let observationNumber = extractIntFromRawItem(item, tag: DICOMTag.observationNumber) ?? (index + 1)
            let referencedROINumber = extractIntFromRawItem(item, tag: DICOMTag.referencedROINumber) ?? (index + 1)
            let roiObservationLabel = extractStringFromRawItem(item, tag: DICOMTag.roiObservationLabel)
            let rtROIInterpretedType = extractStringFromRawItem(item, tag: DICOMTag.rtROIInterpretedType)
            let roiInterpreter = extractStringFromRawItem(item, tag: DICOMTag.roiInterpreter)
            
            let observation = ROIObservation(
                observationNumber: observationNumber,
                referencedROINumber: referencedROINumber,
                roiObservationLabel: roiObservationLabel,
                rtROIInterpretedType: rtROIInterpretedType,
                roiInterpreter: roiInterpreter
            )
            
            observations.append(observation)
            print("      👁️ Observation \(observationNumber): ROI \(referencedROINumber)")
        }
        
        return observations
    }
    
    // MARK: - Raw Data Parsing Utilities
    
    /// Parse sequence items from raw sequence data
    /// Fixed sequence parser that handles MIM's undefined length items correctly
    private static func parseSequenceItemsFromRawData(_ sequenceData: Data) -> [RawSequenceItem] {
        print("      🔍 MIM-AWARE SEQUENCE DEBUG: Finding ROI contour items dynamically...")
        
        var items: [RawSequenceItem] = []
        var roiStartOffsets: [Int] = []
        
        // Find ROI Display Color tags (3006,002A) which mark the start of each ROI
        var offset = 0
        while offset + 8 <= sequenceData.count {
            let group = sequenceData.readUInt16(at: offset, littleEndian: true)
            let element = sequenceData.readUInt16(at: offset + 2, littleEndian: true)
            
            if group == 0xFFFE && element == 0xE000 {
                // Check if this item starts with ROI Display Color
                let nextOffset = offset + 8
                if nextOffset + 4 <= sequenceData.count {
                    let nextGroup = sequenceData.readUInt16(at: nextOffset, littleEndian: true)
                    let nextElement = sequenceData.readUInt16(at: nextOffset + 2, littleEndian: true)
                    
                    if nextGroup == 0x3006 && nextElement == 0x002A {
                        roiStartOffsets.append(offset)
                        print("      🎯 Found ROI start at offset \(offset)")
                    }
                }
            }
            offset += 2
        }
        
        print("      📊 Found \(roiStartOffsets.count) ROI sections")
        
        // Parse each ROI section
        for (roiIndex, startOffset) in roiStartOffsets.enumerated() {
            let endOffset = roiIndex < roiStartOffsets.count - 1 ? roiStartOffsets[roiIndex + 1] : sequenceData.count
            
            // Safety check
            guard startOffset < sequenceData.count && endOffset <= sequenceData.count && startOffset < endOffset else {
                print("      ⚠️ Invalid offset range for ROI \(roiIndex + 1): \(startOffset) to \(endOffset)")
                continue
            }
            
            print("      🎯 Processing ROI \(roiIndex + 1) from offset \(startOffset) to \(endOffset) (\(endOffset - startOffset) bytes)")
            
            let roiData = sequenceData.subdata(in: startOffset..<endOffset)
            if let roiItem = parseFullROIItem(roiData) {
                items.append(roiItem)
                print("      ✅ Parsed ROI item \(roiIndex + 1): \(roiItem.elements.count) elements")
            } else {
                print("      ❌ Failed to parse ROI item \(roiIndex + 1)")
            }
        }
        
        print("      📊 Successfully parsed \(items.count) ROI items")
        return items
    }

    private static func parseFullROIItem(_ roiData: Data) -> RawSequenceItem? {
        var elements: [DICOMTag: Data] = [:]
        var offset = 8 // Skip initial item tag
        
        while offset + 8 <= roiData.count {
            let group = roiData.readUInt16(at: offset, littleEndian: true)
            let element = roiData.readUInt16(at: offset + 2, littleEndian: true)
            let tag = DICOMTag(group: group, element: element)
            let length = roiData.readUInt32(at: offset + 4, littleEndian: true)
            
            offset += 8
            
            if length == 0xFFFFFFFF {
                // Undefined length - this is likely the contour sequence
                let sequenceData = roiData.subdata(in: offset..<roiData.count)
                elements[tag] = sequenceData
                print("        📐 Found undefined length sequence for tag (\(String(format: "%04X", tag.group)),\(String(format: "%04X", tag.element))): \(sequenceData.count) bytes")
                break
            } else if length > 0 {
                let dataLength = Int(length)
                guard offset + dataLength <= roiData.count else {
                    print("        ⚠️ Element length exceeds data bounds: \(dataLength) > \(roiData.count - offset)")
                    break
                }
                
                let elementData = roiData.subdata(in: offset..<offset + dataLength)
                elements[tag] = elementData
                offset += dataLength
                
                print("        📋 Parsed tag (\(String(format: "%04X", tag.group)),\(String(format: "%04X", tag.element))): \(dataLength) bytes")
            } else {
                offset += Int(length)
            }
        }
        
        return elements.isEmpty ? nil : RawSequenceItem(elements: elements)
    }

    private static func findUndefinedLengthSequence(_ data: Data, startOffset: Int) -> Data {
        // Return all remaining data as the contour sequence
        return data.subdata(in: startOffset..<data.count)
    }
    /// Enhanced function to find undefined length item data with better delimiter detection
    private static func findUndefinedLengthItemFixed(_ data: Data, startOffset: Int) -> Data {
        var offset = startOffset
        var nestingLevel = 0
        
        while offset + 8 <= data.count {
            let group = data.readUInt16(at: offset, littleEndian: true)
            let element = data.readUInt16(at: offset + 2, littleEndian: true)
            let length = data.readUInt32(at: offset + 4, littleEndian: true)
            
            if group == 0xFFFE {
                if element == 0xE000 {
                    // Nested sequence item start
                    nestingLevel += 1
                    offset += 8
                    if length != 0xFFFFFFFF && length > 0 {
                        offset += Int(length)
                    }
                } else if element == 0xE00D {
                    // Item delimiter
                    if nestingLevel == 0 {
                        // This is our item delimiter
                        return data.subdata(in: startOffset..<offset)
                    } else {
                        nestingLevel -= 1
                        offset += 8
                    }
                } else if element == 0xE0DD {
                    // Sequence delimiter - if we're at nesting level 0, this ends our item
                    if nestingLevel == 0 {
                        return data.subdata(in: startOffset..<offset)
                    } else {
                        offset += 8
                    }
                } else {
                    // Other FFFE tags
                    offset += 8
                    if length != 0xFFFFFFFF && length > 0 {
                        offset += Int(length)
                    }
                }
            } else {
                // Regular DICOM element
                offset += 8
                if length != 0xFFFFFFFF && length > 0 && Int(length) < data.count - offset {
                    offset += Int(length)
                } else if length == 0xFFFFFFFF {
                    // Nested undefined length element - skip for now
                    offset += 8
                } else {
                    // Invalid length - try to skip safely
                    offset += 1
                }
            }
        }
        
        // If we reach here without finding a delimiter, return remaining data
        return data.subdata(in: startOffset..<min(data.count, offset))
    }

    /// Find the next item delimiter to properly advance the offset
    private static func findNextItemDelimiter(_ data: Data, startOffset: Int) -> Int {
        var offset = startOffset
        
        while offset + 8 <= data.count {
            let group = data.readUInt16(at: offset, littleEndian: true)
            let element = data.readUInt16(at: offset + 2, littleEndian: true)
            
            if group == 0xFFFE && (element == 0xE00D || element == 0xE0DD) {
                // Found item delimiter or sequence delimiter
                return offset + 8
            }
            
            offset += 2
        }
        
        return data.count // If no delimiter found, go to end
    }
    
    /// Find undefined length item data
    private static func findUndefinedLengthItem(_ data: Data, startOffset: Int) -> Data {
        var offset = startOffset
        
        while offset + 8 <= data.count {
            let group = data.readUInt16(at: offset, littleEndian: true)
            let element = data.readUInt16(at: offset + 2, littleEndian: true)
            
            if group == 0xFFFE && element == 0xE00D {
                // Found item delimiter
                return data.subdata(in: startOffset..<offset)
            }
            
            // Skip this element
            offset += 8
            let length = data.readUInt32(at: offset - 4, littleEndian: true)
            if length != 0xFFFFFFFF {
                offset += Int(length)
            }
        }
        
        return Data()
    }
    
    /// Parse individual raw sequence item
    private static func parseRawSequenceItem(_ itemData: Data) -> RawSequenceItem {
        var elements: [DICOMTag: Data] = [:]
        var offset = 0
        
        while offset + 8 <= itemData.count {
            let group = itemData.readUInt16(at: offset, littleEndian: true)
            let element = itemData.readUInt16(at: offset + 2, littleEndian: true)
            let tag = DICOMTag(group: group, element: element)
            
            offset += 4
            
            // Assume implicit VR for simplicity
            guard offset + 4 <= itemData.count else { break }
            let length = itemData.readUInt32(at: offset, littleEndian: true)
            offset += 4
            
            if length == 0xFFFFFFFF {
                break
            }
            
            let dataLength = Int(length)
            guard offset + dataLength <= itemData.count else { break }
            
            let elementData = itemData.subdata(in: offset..<offset + dataLength)
            elements[tag] = elementData
            
            offset += dataLength
        }
        
        return RawSequenceItem(elements: elements)
    }
    
    // MARK: - Raw Data Extraction
    
    private static func extractStringFromRawItem(_ item: RawSequenceItem, tag: DICOMTag) -> String? {
        guard let data = item.elements[tag] else { return nil }
        return String(data: data, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func extractIntFromRawItem(_ item: RawSequenceItem, tag: DICOMTag) -> Int? {
        guard let data = item.elements[tag] else { return nil }
        
        if data.count >= 2 {
            return Int(data.readUInt16(at: 0, littleEndian: true))
        } else if data.count >= 4 {
            return Int(data.readUInt32(at: 0, littleEndian: true))
        }
        
        return nil
    }
    
    private static func extractDisplayColorFromRawItem(_ item: RawSequenceItem) -> SIMD3<Float> {
        guard let colorData = item.elements[DICOMTag.roiDisplayColor] else {
            return StandardROIColors.getColorForROI("Unknown")
        }
        
        guard colorData.count >= 6 else {
            return StandardROIColors.getColorForROI("Unknown")
        }
        
        let r = Float(colorData.readUInt16(at: 0, littleEndian: true)) / 65535.0
        let g = Float(colorData.readUInt16(at: 2, littleEndian: true)) / 65535.0
        let b = Float(colorData.readUInt16(at: 4, littleEndian: true)) / 65535.0
        
        return SIMD3<Float>(r, g, b)
    }
    
    // Add this enhanced debugging to your parseContourSequenceFromRawItem method
    // Replace your existing parseContourSequenceFromRawItem method with this version:

    private static func parseContourSequenceFromRawItem(_ item: RawSequenceItem) -> [ROIContour] {
        print("        🔍 DEBUG: Looking for contour sequence in ROI item...")
        print("        🔍 DEBUG: Available tags in ROI item:")
        for (tag, data) in item.elements {
            print("           Tag (\(String(format: "%04X", tag.group)),\(String(format: "%04X", tag.element))): \(data.count) bytes")
        }
        
        guard let contourSequenceData = item.elements[DICOMTag.contourSequence] else {
            print("        ❌ No contour sequence tag (3006,0040) found in ROI item")
            return []
        }
        
        print("        ✅ Found contour sequence data: \(contourSequenceData.count) bytes")
        print("        🔍 DEBUG: First 32 bytes of contour sequence:")
        let debugBytes = contourSequenceData.prefix(32)
        let hexString = debugBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("           \(hexString)")
        
        let contourItems = parseSequenceItemsFromRawData(contourSequenceData)
        print("        📊 Found \(contourItems.count) contour items")
        
        var contours: [ROIContour] = []
        
        for (index, contourItem) in contourItems.enumerated() {
            print("        🔍 DEBUG: Processing contour item \(index):")
            print("        🔍 DEBUG: Available tags in contour item:")
            for (tag, data) in contourItem.elements {
                print("           Tag (\(String(format: "%04X", tag.group)),\(String(format: "%04X", tag.element))): \(data.count) bytes")
            }
            
            let geometricTypeString = extractStringFromRawItem(contourItem, tag: DICOMTag.contourGeometricType) ?? "CLOSED_PLANAR"
            let geometricType = ContourGeometricType(rawValue: geometricTypeString) ?? .closedPlanar
            
            let numberOfPoints = extractIntFromRawItem(contourItem, tag: DICOMTag.numberOfContourPoints) ?? 0
            let contourDataString = extractStringFromRawItem(contourItem, tag: DICOMTag.contourData) ?? ""
            
            print("           Geometric Type: \(geometricTypeString)")
            print("           Number of Points: \(numberOfPoints)")
            print("           Contour Data Length: \(contourDataString.count) characters")
            print("           Contour Data Preview: \(String(contourDataString.prefix(100)))")
            
            let contourPoints = parseContourDataPoints(contourDataString)
            let slicePosition = contourPoints.first?.z ?? 0.0
            
            let contour = ROIContour(
                contourNumber: index + 1,
                geometricType: geometricType,
                numberOfPoints: contourPoints.count,
                contourData: contourPoints,
                slicePosition: slicePosition,
                referencedSOPInstanceUID: nil
            )
            
            contours.append(contour)
            print("        ✅ Created contour \(index + 1): \(contourPoints.count) points at Z=\(slicePosition)")
        }
        
        print("        📊 Total contours created: \(contours.count)")
        return contours
    }
}
