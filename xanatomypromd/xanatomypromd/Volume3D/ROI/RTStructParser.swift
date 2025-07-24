import Foundation
import simd

// MARK: - RTStruct Parser
// Real DICOM sequence parsing for RTStruct files to extract ROI contour data

public class RTStructParser {
    
    // MARK: - Main Parsing Interface
    
    /// Parse RTStruct from DICOM dataset
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
        
        // Parse Structure Set ROI Sequence (ROI definitions)
        let roiDefinitions: [ROIDefinition] = try parseStructureSetROISequence(from: dataset)
        print("   🎯 Found \(roiDefinitions.count) ROI definitions")
        
        // Parse ROI Contour Sequence (contour geometry)
        let roiContours: [ROIContourSet] = try parseROIContourSequence(from: dataset)
        print("   📐 Found \(roiContours.count) ROI contour sets")
        
        // Parse RT ROI Observations Sequence (display properties)
        let roiObservations: [ROIObservation] = parseRTROIObservationsSequence(from: dataset)
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
    
    // MARK: - Structure Set ROI Sequence Parsing (REAL IMPLEMENTATION)
    
    private static func parseStructureSetROISequence(from dataset: DICOMDataset) throws -> [ROIDefinition] {
        guard let sequenceElement = dataset.elements[DICOMTag.structureSetROISequence] else {
            throw RTStructError.missingRequiredSequence("Structure Set ROI Sequence")
        }
        
        print("   📋 Parsing Structure Set ROI Sequence...")
        
        // Parse the actual DICOM sequence structure
        let sequenceItems = try parseDICOMSequence(sequenceElement.data)
        
        var roiDefinitions: [ROIDefinition] = []
        
        for (index, item) in sequenceItems.enumerated() {
            do {
                // Extract ROI Number (3006,0022)
                let roiNumber = extractIntFromSequenceItem(item, tag: DICOMTag.roiNumber) ?? (index + 1)
                
                // Extract ROI Name (3006,0026)
                let roiName = extractStringFromSequenceItem(item, tag: DICOMTag.roiName) ?? "ROI \(roiNumber)"
                
                // Extract optional fields
                let roiDescription = extractStringFromSequenceItem(item, tag: DICOMTag.roiDescription)
                let roiGenerationAlgorithm = extractStringFromSequenceItem(item, tag: DICOMTag.roiGenerationAlgorithm)
                
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
    
    // MARK: - ROI Contour Sequence Parsing (REAL IMPLEMENTATION)
    
    private static func parseROIContourSequence(from dataset: DICOMDataset) throws -> [ROIContourSet] {
        guard let sequenceElement = dataset.elements[DICOMTag.roiContourSequence] else {
            throw RTStructError.missingRequiredSequence("ROI Contour Sequence")
        }
        
        print("   🖼️ Parsing ROI Contour Sequence...")
        
        let sequenceItems = try parseDICOMSequence(sequenceElement.data)
        
        var contourSets: [ROIContourSet] = []
        
        for (index, item) in sequenceItems.enumerated() {
            do {
                // Extract Referenced ROI Number
                let referencedROINumber = extractIntFromSequenceItem(item, tag: DICOMTag.referencedROINumber) ?? (index + 1)
                
                // Extract ROI Display Color (RGB values 0-255)
                let displayColor = extractDisplayColorFromSequenceItem(item)
                
                // Parse Contour Sequence (3006,0040)
                let contours = try parseContourSequence(item)
                
                let contourSet = ROIContourSet(
                    referencedROINumber: referencedROINumber,
                    displayColor: displayColor,
                    contours: contours
                )
                
                contourSets.append(contourSet)
                
                print("      🎨 ROI \(referencedROINumber): \(contours.count) contours, color: RGB(\(String(format: "%.2f", displayColor.x)), \(String(format: "%.2f", displayColor.y)), \(String(format: "%.2f", displayColor.z)))")
                
            } catch {
                print("      ⚠️ Failed to parse contour set \(index): \(error)")
            }
        }
        
        return contourSets
    }
    
    // MARK: - Contour Sequence Parsing (REAL IMPLEMENTATION)
    
    private static func parseContourSequence(_ roiContourItem: DICOMSequenceItem) throws -> [ROIContour] {
        // Look for Contour Sequence tag (3006,0040) within this ROI contour item
        guard let contourSequenceData = extractSequenceFromSequenceItem(roiContourItem, tag: DICOMTag.contourSequence) else {
            print("        ℹ️ No contour sequence found in this ROI")
            return []
        }
        
        let contourItems = try parseDICOMSequence(contourSequenceData)
        var contours: [ROIContour] = []
        
        for (contourIndex, contourItem) in contourItems.enumerated() {
            do {
                // Extract Contour Geometric Type (3006,0042)
                let geometricTypeString = extractStringFromSequenceItem(contourItem, tag: DICOMTag.contourGeometricType) ?? "CLOSED_PLANAR"
                let geometricType = ContourGeometricType(rawValue: geometricTypeString) ?? .closedPlanar
                
                // Extract Number of Contour Points (3006,0046)
                let numberOfPoints = extractIntFromSequenceItem(contourItem, tag: DICOMTag.numberOfContourPoints) ?? 0
                
                // Extract Contour Data (3006,0050) - The actual 3D points
                guard let contourDataString = extractStringFromSequenceItem(contourItem, tag: DICOMTag.contourData) else {
                    print("        ⚠️ No contour data found for contour \(contourIndex)")
                    continue
                }
                
                // Parse the contour data points (x1\y1\z1\x2\y2\z2\...)
                let contourPoints = parseContourDataPoints(contourDataString)
                
                guard contourPoints.count == numberOfPoints else {
                    print("        ⚠️ Point count mismatch: expected \(numberOfPoints), got \(contourPoints.count)")
                }
                
                // Calculate slice position (Z coordinate - typically the same for all points in a contour)
                let slicePosition = contourPoints.first?.z ?? 0.0
                
                // Extract referenced SOP instance UID if present
                let referencedSOPInstanceUID = extractReferencedSOPInstanceUID(contourItem)
                
                let contour = ROIContour(
                    contourNumber: contourIndex + 1,
                    geometricType: geometricType,
                    numberOfPoints: contourPoints.count,
                    contourData: contourPoints,
                    slicePosition: slicePosition,
                    referencedSOPInstanceUID: referencedSOPInstanceUID
                )
                
                contours.append(contour)
                
                print("        📐 Contour \(contourIndex + 1): \(geometricType.rawValue), \(contourPoints.count) points, Z=\(String(format: "%.1f", slicePosition))")
                
            } catch {
                print("        ⚠️ Failed to parse contour \(contourIndex): \(error)")
            }
        }
        
        return contours
    }
    
    // MARK: - RT ROI Observations Sequence Parsing (REAL IMPLEMENTATION)
    
    private static func parseRTROIObservationsSequence(from dataset: DICOMDataset) -> [ROIObservation] {
        guard let sequenceElement = dataset.elements[DICOMTag.rtROIObservationsSequence] else {
            print("   ℹ️ No RT ROI Observations Sequence found (optional)")
            return []
        }
        
        print("   👁️ Parsing RT ROI Observations Sequence...")
        
        do {
            let sequenceItems = try parseDICOMSequence(sequenceElement.data)
            var observations: [ROIObservation] = []
            
            for (index, item) in sequenceItems.enumerated() {
                let observationNumber = extractIntFromSequenceItem(item, tag: DICOMTag.observationNumber) ?? (index + 1)
                let referencedROINumber = extractIntFromSequenceItem(item, tag: DICOMTag.referencedROINumber) ?? (index + 1)
                let roiObservationLabel = extractStringFromSequenceItem(item, tag: DICOMTag.roiObservationLabel)
                let rtROIInterpretedType = extractStringFromSequenceItem(item, tag: DICOMTag.rtROIInterpretedType)
                let roiInterpreter = extractStringFromSequenceItem(item, tag: DICOMTag.roiInterpreter)
                
                let observation = ROIObservation(
                    observationNumber: observationNumber,
                    referencedROINumber: referencedROINumber,
                    roiObservationLabel: roiObservationLabel,
                    rtROIInterpretedType: rtROIInterpretedType,
                    roiInterpreter: roiInterpreter
                )
                
                observations.append(observation)
                
                print("      👁️ Observation \(observationNumber): ROI \(referencedROINumber), Type: \(rtROIInterpretedType ?? "Unknown")")
            }
            
            return observations
        } catch {
            print("   ⚠️ Failed to parse RT ROI Observations: \(error)")
            return []
        }
    }
    
    // MARK: - DICOM Sequence Parsing Infrastructure
    
    /// Parse DICOM sequence data into individual items
    private static func parseDICOMSequence(_ sequenceData: Data) throws -> [DICOMSequenceItem] {
        var items: [DICOMSequenceItem] = []
        var offset = 0
        
        while offset < sequenceData.count {
            // Look for sequence item tag (FFFE,E000)
            guard offset + 8 <= sequenceData.count else { break }
            
            let group = sequenceData.readUInt16(at: offset, littleEndian: true)
            let element = sequenceData.readUInt16(at: offset + 2, littleEndian: true)
            let length = sequenceData.readUInt32(at: offset + 4, littleEndian: true)
            
            offset += 8
            
            if group == 0xFFFE && element == 0xE000 {
                // This is a sequence item
                let itemLength = Int(length)
                
                if length == 0xFFFFFFFF {
                    // Undefined length - find the item delimiter
                    let itemData = findItemWithUndefinedLength(sequenceData, startOffset: offset)
                    if !itemData.isEmpty {
                        let item = try parseSequenceItemData(itemData)
                        items.append(item)
                        offset += itemData.count + 8 // Include delimiter
                    } else {
                        break
                    }
                } else if itemLength > 0 && offset + itemLength <= sequenceData.count {
                    // Defined length
                    let itemData = sequenceData.subdata(in: offset..<offset + itemLength)
                    let item = try parseSequenceItemData(itemData)
                    items.append(item)
                    offset += itemLength
                } else {
                    break
                }
            } else if group == 0xFFFE && element == 0xE0DD {
                // Sequence delimiter - end of sequence
                break
            } else {
                // Skip unknown tags
                offset += Int(length)
            }
        }
        
        return items
    }
    
    /// Parse individual sequence item data into a dictionary of tags
    private static func parseSequenceItemData(_ itemData: Data) throws -> DICOMSequenceItem {
        var elements: [DICOMTag: Data] = [:]
        var offset = 0
        
        while offset + 8 <= itemData.count {
            let group = itemData.readUInt16(at: offset, littleEndian: true)
            let element = itemData.readUInt16(at: offset + 2, littleEndian: true)
            let tag = DICOMTag(group: group, element: element)
            
            offset += 4
            
            // Determine VR and length (assume implicit VR for simplicity)
            guard offset + 4 <= itemData.count else { break }
            let length = itemData.readUInt32(at: offset, littleEndian: true)
            offset += 4
            
            if length == 0xFFFFFFFF {
                // Undefined length - skip for now
                break
            }
            
            let dataLength = Int(length)
            guard offset + dataLength <= itemData.count else { break }
            
            let elementData = itemData.subdata(in: offset..<offset + dataLength)
            elements[tag] = elementData
            
            offset += dataLength
        }
        
        return DICOMSequenceItem(elements: elements)
    }
    
    // MARK: - Sequence Item Data Extraction
    
    private static func extractStringFromSequenceItem(_ item: DICOMSequenceItem, tag: DICOMTag) -> String? {
        guard let data = item.elements[tag] else { return nil }
        return String(data: data, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func extractIntFromSequenceItem(_ item: DICOMSequenceItem, tag: DICOMTag) -> Int? {
        guard let data = item.elements[tag] else { return nil }
        
        if data.count >= 2 {
            return Int(data.readUInt16(at: 0, littleEndian: true))
        } else if data.count >= 4 {
            return Int(data.readUInt32(at: 0, littleEndian: true))
        }
        
        return nil
    }
    
    private static func extractSequenceFromSequenceItem(_ item: DICOMSequenceItem, tag: DICOMTag) -> Data? {
        return item.elements[tag]
    }
    
    private static func extractDisplayColorFromSequenceItem(_ item: DICOMSequenceItem) -> SIMD3<Float> {
        guard let colorData = item.elements[DICOMTag.roiDisplayColor] else {
            // No color specified - generate one based on ROI number
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
    
    // MARK: - Contour Data Processing
    
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
    
    private static func extractReferencedSOPInstanceUID(_ contourItem: DICOMSequenceItem) -> String? {
        // Look for Contour Image Sequence, then Referenced SOP Instance UID
        guard let contourImageSeqData = contourItem.elements[DICOMTag.contourImageSequence] else { return nil }
        
        do {
            let imageItems = try parseDICOMSequence(contourImageSeqData)
            if let firstImageItem = imageItems.first {
                return extractStringFromSequenceItem(firstImageItem, tag: DICOMTag.referencedSOPInstanceUID)
            }
        } catch {
            print("        ⚠️ Failed to parse contour image sequence: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Utility Functions
    
    private static func findItemWithUndefinedLength(_ data: Data, startOffset: Int) -> Data {
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
        
        return Data()
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
            
            // Find matching observation
            let observation = observations.first { $0.referencedROINumber == definition.roiNumber }
            
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
        // This would need to be extracted from Referenced Series Sequence when implemented
        return nil
    }
}

// MARK: - Internal Data Structures

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

// MARK: - DICOM Sequence Item Structure

private struct DICOMSequenceItem {
    let elements: [DICOMTag: Data]
}

// MARK: - Testing and Validation

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
