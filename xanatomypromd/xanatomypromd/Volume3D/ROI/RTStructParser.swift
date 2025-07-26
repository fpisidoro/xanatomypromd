import Foundation
import simd

// MARK: - Direct RTStruct Parser (MIM-Aware)
// Specifically designed to handle the MIM RTStruct format we discovered
// Based on actual structure analysis: 3 ROI sections with nested contour sequences

public class RTStructParser {
    
    // MARK: - Main Parsing Interface
    
    /// Parse RTStruct from DICOM dataset
    public static func parseRTStruct(from dataset: DICOMDataset) throws -> RTStructData {
        print("📊 Parsing RTStruct DICOM data with MIM-aware parser...")
        
        // Extract basic metadata
        let metadata = extractMetadata(from: dataset)
        
        // Use direct MIM-aware parsing
        let roiDefinitions = try parseMIMStructureSetROISequence(from: dataset)
        print("   🎯 Found \(roiDefinitions.count) ROI definitions")
        
        let roiContours = try parseMIMROIContourSequence(from: dataset)
        print("   📐 Found \(roiContours.count) ROI contour sets")
        
        let roiObservations = parseMIMRTROIObservationsSequence(from: dataset)
        print("   🎨 Found \(roiObservations.count) ROI observations")
        
        // Combine all data into complete ROI structures
        let roiStructures = try combineROIData(
            definitions: roiDefinitions,
            contours: roiContours,
            observations: roiObservations
        )
        
        print("   ✅ Successfully parsed \(roiStructures.count) complete ROI structures")
        
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
    
    // MARK: - MIM-Aware Parsing (Direct Approach)
    
    /// Parse Structure Set ROI Sequence with MIM format awareness
    private static func parseMIMStructureSetROISequence(from dataset: DICOMDataset) throws -> [RTStructDefinition] {
        print("   📋 Parsing Structure Set ROI Sequence (MIM-aware)...")
        
        guard let sequenceElement = dataset.elements[DICOMTag.structureSetROISequence] else {
            throw RTStructError.missingRequiredSequence("Structure Set ROI Sequence")
        }
        
        let sequenceData = sequenceElement.data
        print("   🔍 Sequence data: \(sequenceData.count) bytes")
        
        // Parse ROI definitions using direct MIM structure detection
        var definitions: [RTStructDefinition] = []
        var offset = 0
        var roiIndex = 1
        
        // Look for ROI Number tags (3006,0022) which indicate ROI definitions
        while offset + 8 <= sequenceData.count {
            let group = sequenceData.readUInt16(at: offset, littleEndian: true)
            let element = sequenceData.readUInt16(at: offset + 2, littleEndian: true)
            
            if group == 0x3006 && element == 0x0022 { // ROI Number
                print("      🎯 Found ROI Number tag at offset \(offset)")
                
                // Extract ROI data starting from this position
                if let roiData = extractROIDefinitionData(sequenceData, startOffset: offset) {
                    let definition = parseROIDefinitionFromData(roiData, index: roiIndex)
                    definitions.append(definition)
                    print("      📍 ROI \(definition.roiNumber): \(definition.roiName)")
                    roiIndex += 1
                }
            }
            
            offset += 2
        }
        
        return definitions
    }
    
    /// Parse ROI Contour Sequence with MIM format awareness
    private static func parseMIMROIContourSequence(from dataset: DICOMDataset) throws -> [RTStructContourSet] {
        print("   🖼️ Parsing ROI Contour Sequence (MIM-aware)...")
        
        guard let sequenceElement = dataset.elements[DICOMTag.roiContourSequence] else {
            throw RTStructError.missingRequiredSequence("ROI Contour Sequence")
        }
        
        let sequenceData = sequenceElement.data
        print("   🔍 Sequence data: \(sequenceData.count) bytes")
        
        // Based on our previous analysis: 3 ROI sections at specific offsets
        // ROI-1: Offset 0, ROI-2: Offset 9922, ROI-3: Offset 18208
        var contourSets: [RTStructContourSet] = []
        
        // Find ROI Display Color tags (3006,002A) which mark ROI sections
        var roiSectionOffsets: [Int] = []
        var offset = 0
        
        while offset + 8 <= sequenceData.count {
            let group = sequenceData.readUInt16(at: offset, littleEndian: true)
            let element = sequenceData.readUInt16(at: offset + 2, littleEndian: true)
            
            if group == 0x3006 && element == 0x002A { // ROI Display Color
                roiSectionOffsets.append(offset - 8) // Include the item delimiter
                print("      🎯 Found ROI section at offset \(offset - 8)")
            }
            
            offset += 2
        }
        
        print("   📊 Found \(roiSectionOffsets.count) ROI sections")
        
        // Parse each ROI section
        for (index, sectionOffset) in roiSectionOffsets.enumerated() {
            let nextOffset = index < roiSectionOffsets.count - 1 ? roiSectionOffsets[index + 1] : sequenceData.count
            let sectionData = sequenceData.subdata(in: sectionOffset..<nextOffset)
            
            print("      🔍 Processing ROI section \(index + 1): \(sectionData.count) bytes")
            
            if let contourSet = parseROIContourSection(sectionData, roiNumber: index + 1) {
                contourSets.append(contourSet)
                print("      🖼️ ROI \(contourSet.referencedROINumber): \(contourSet.contours.count) contours")
            }
        }
        
        return contourSets
    }
    
    /// Parse RT ROI Observations Sequence with MIM format awareness
    private static func parseMIMRTROIObservationsSequence(from dataset: DICOMDataset) -> [RTStructObservation] {
        print("   👁️ Parsing RT ROI Observations Sequence (MIM-aware)...")
        
        guard let sequenceElement = dataset.elements[DICOMTag.rtROIObservationsSequence] else {
            print("   ℹ️ No RT ROI Observations Sequence found (optional)")
            return []
        }
        
        let sequenceData = sequenceElement.data
        print("   🔍 Sequence data: \(sequenceData.count) bytes")
        
        // Parse observations using similar approach
        var observations: [RTStructObservation] = []
        var offset = 0
        var obsIndex = 1
        
        // Look for Observation Number tags
        while offset + 8 <= sequenceData.count {
            let group = sequenceData.readUInt16(at: offset, littleEndian: true)
            let element = sequenceData.readUInt16(at: offset + 2, littleEndian: true)
            
            if group == 0x3006 && element == 0x0082 { // Observation Number
                print("      🎯 Found Observation Number tag at offset \(offset)")
                
                if let obsData = extractObservationData(sequenceData, startOffset: offset) {
                    let observation = parseObservationFromData(obsData, index: obsIndex)
                    observations.append(observation)
                    print("      👁️ Observation \(observation.observationNumber): ROI \(observation.referencedROINumber)")
                    obsIndex += 1
                }
            }
            
            offset += 2
        }
        
        return observations
    }
    
    // MARK: - ROI Definition Parsing
    
    /// Extract ROI definition data starting from ROI Number tag
    private static func extractROIDefinitionData(_ data: Data, startOffset: Int) -> Data? {
        // Extract approximately 200 bytes of ROI definition data
        let endOffset = min(startOffset + 200, data.count)
        return data.subdata(in: startOffset..<endOffset)
    }
    
    /// Parse ROI definition from extracted data
    private static func parseROIDefinitionFromData(_ data: Data, index: Int) -> RTStructDefinition {
        var roiNumber = index
        var roiName = "ROI \(index)"
        var roiDescription: String? = nil
        var roiGenerationAlgorithm: String? = nil
        
        // Parse ROI Number (3006,0022)
        if let numberData = findTagData(data, group: 0x3006, element: 0x0022) {
            if numberData.count >= 2 {
                roiNumber = Int(numberData.readUInt16(at: 0, littleEndian: true))
            }
        }
        
        // Parse ROI Name (3006,0026)
        if let nameData = findTagData(data, group: 0x3006, element: 0x0026) {
            if let name = String(data: nameData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                roiName = name
            }
        }
        
        // Parse ROI Description (3006,0028)
        if let descData = findTagData(data, group: 0x3006, element: 0x0028) {
            roiDescription = String(data: descData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Parse ROI Generation Algorithm (3006,0036)
        if let algoData = findTagData(data, group: 0x3006, element: 0x0036) {
            roiGenerationAlgorithm = String(data: algoData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return RTStructDefinition(
            roiNumber: roiNumber,
            roiName: roiName,
            roiDescription: roiDescription,
            roiGenerationAlgorithm: roiGenerationAlgorithm
        )
    }
    
    // MARK: - ROI Contour Section Parsing
    
    /// Parse a single ROI contour section
    private static func parseROIContourSection(_ sectionData: Data, roiNumber: Int) -> RTStructContourSet? {
        var referencedROINumber = roiNumber
        var displayColor = StandardROIColors.getColorForROI("ROI \(roiNumber)")
        
        // Parse Referenced ROI Number (3006,0084)
        if let refData = findTagData(sectionData, group: 0x3006, element: 0x0084) {
            if refData.count >= 2 {
                referencedROINumber = Int(refData.readUInt16(at: 0, littleEndian: true))
            }
        }
        
        // Parse ROI Display Color (3006,002A)
        if let colorData = findTagData(sectionData, group: 0x3006, element: 0x002A) {
            if colorData.count >= 6 {
                let r = Float(colorData.readUInt16(at: 0, littleEndian: true)) / 65535.0
                let g = Float(colorData.readUInt16(at: 2, littleEndian: true)) / 65535.0
                let b = Float(colorData.readUInt16(at: 4, littleEndian: true)) / 65535.0
                displayColor = SIMD3<Float>(r, g, b)
            }
        }
        
        // Parse Contour Sequence (3006,0040)
        let contours = parseContourSequenceFromSection(sectionData)
        
        return RTStructContourSet(
            referencedROINumber: referencedROINumber,
            displayColor: displayColor,
            contours: contours
        )
    }
    
    /// Parse contour sequence from ROI section data
    private static func parseContourSequenceFromSection(_ sectionData: Data) -> [ROIContour] {
        var contours: [ROIContour] = []
        
        // Find Contour Sequence tag (3006,0040)
        var offset = 0
        while offset + 8 <= sectionData.count {
            let group = sectionData.readUInt16(at: offset, littleEndian: true)
            let element = sectionData.readUInt16(at: offset + 2, littleEndian: true)
            
            if group == 0x3006 && element == 0x0040 {
                print("        🎯 Found Contour Sequence at offset \(offset)")
                
                // Extract contour sequence data (remaining data after this tag)
                let contourSeqStart = offset + 8 // Skip tag and length
                let contourSeqData = sectionData.subdata(in: contourSeqStart..<sectionData.count)
                
                // Parse individual contours from this sequence
                let parsedContours = parseIndividualContours(contourSeqData)
                contours.append(contentsOf: parsedContours)
                break
            }
            
            offset += 2
        }
        
        return contours
    }
    
    /// Parse individual contours from contour sequence data
    private static func parseIndividualContours(_ contourSeqData: Data) -> [ROIContour] {
        var contours: [ROIContour] = []
        var contourIndex = 1
        
        // Look for Contour Geometric Type tags (3006,0042) which indicate individual contours
        var offset = 0
        while offset + 8 <= contourSeqData.count {
            let group = contourSeqData.readUInt16(at: offset, littleEndian: true)
            let element = contourSeqData.readUInt16(at: offset + 2, littleEndian: true)
            
            if group == 0x3006 && element == 0x0042 {
                print("        📐 Found Contour Geometric Type at offset \(offset)")
                
                // Extract contour data (next ~1000 bytes should contain one contour)
                let contourStart = offset
                let contourEnd = min(offset + 1500, contourSeqData.count)
                let contourData = contourSeqData.subdata(in: contourStart..<contourEnd)
                
                if let contour = parseIndividualContour(contourData, index: contourIndex) {
                    contours.append(contour)
                    print("        ✅ Parsed contour \(contourIndex): \(contour.numberOfPoints) points")
                    contourIndex += 1
                }
            }
            
            offset += 2
        }
        
        return contours
    }
    
    /// Parse a single contour from contour data
    private static func parseIndividualContour(_ contourData: Data, index: Int) -> ROIContour? {
        var geometricType = ContourGeometricType.closedPlanar
        var numberOfPoints = 0
        var points: [SIMD3<Float>] = []
        var referencedSOPInstanceUID: String? = nil
        
        // Parse Contour Geometric Type (3006,0042)
        if let geomData = findTagData(contourData, group: 0x3006, element: 0x0042) {
            if let geomString = String(data: geomData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                geometricType = ContourGeometricType(rawValue: geomString) ?? .closedPlanar
            }
        }
        
        // Parse Number of Contour Points (3006,0046)
        if let pointsData = findTagData(contourData, group: 0x3006, element: 0x0046) {
            if pointsData.count >= 2 {
                numberOfPoints = Int(pointsData.readUInt16(at: 0, littleEndian: true))
            }
        }
        
        // Parse Contour Data (3006,0050)
        if let contourPointsData = findTagData(contourData, group: 0x3006, element: 0x0050) {
            points = parseContourPoints(contourPointsData)
        }
        
        // Parse Referenced SOP Instance UID (0008,1155) if present
        if let sopData = findTagData(contourData, group: 0x0008, element: 0x1155) {
            referencedSOPInstanceUID = String(data: sopData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Calculate slice position from first point
        let slicePosition = points.first?.z ?? 0.0
        
        return ROIContour(
            contourNumber: index,
            geometricType: geometricType,
            numberOfPoints: max(points.count, numberOfPoints),
            contourData: points,
            slicePosition: slicePosition,
            referencedSOPInstanceUID: referencedSOPInstanceUID
        )
    }
    
    /// Parse contour points from contour data
    private static func parseContourPoints(_ contourPointsData: Data) -> [SIMD3<Float>] {
        // Parse as decimal string format (most common)
        let dataString = String(data: contourPointsData, encoding: .ascii) ?? ""
        let components = dataString.components(separatedBy: "\\")
        
        guard components.count % 3 == 0 else {
            print("        ⚠️ Invalid contour data: point count not divisible by 3")
            return []
        }
        
        var points: [SIMD3<Float>] = []
        
        for i in stride(from: 0, to: components.count, by: 3) {
            guard i + 2 < components.count,
                  let x = Float(components[i].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let y = Float(components[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let z = Float(components[i + 2].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                continue
            }
            
            points.append(SIMD3<Float>(x, y, z))
        }
        
        return points
    }
    
    // MARK: - Observation Parsing
    
    /// Extract observation data starting from Observation Number tag
    private static func extractObservationData(_ data: Data, startOffset: Int) -> Data? {
        let endOffset = min(startOffset + 150, data.count)
        return data.subdata(in: startOffset..<endOffset)
    }
    
    /// Parse observation from extracted data
    private static func parseObservationFromData(_ data: Data, index: Int) -> RTStructObservation {
        var observationNumber = index
        var referencedROINumber = index
        var roiObservationLabel: String? = nil
        var rtROIInterpretedType: String? = nil
        var roiInterpreter: String? = nil
        
        // Parse Observation Number (3006,0082)
        if let obsData = findTagData(data, group: 0x3006, element: 0x0082) {
            if obsData.count >= 2 {
                observationNumber = Int(obsData.readUInt16(at: 0, littleEndian: true))
            }
        }
        
        // Parse Referenced ROI Number (3006,0084)
        if let refData = findTagData(data, group: 0x3006, element: 0x0084) {
            if refData.count >= 2 {
                referencedROINumber = Int(refData.readUInt16(at: 0, littleEndian: true))
            }
        }
        
        // Parse ROI Observation Label (3006,0085)
        if let labelData = findTagData(data, group: 0x3006, element: 0x0085) {
            roiObservationLabel = String(data: labelData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Parse RT ROI Interpreted Type (3006,00A4)
        if let typeData = findTagData(data, group: 0x3006, element: 0x00A4) {
            rtROIInterpretedType = String(data: typeData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Parse ROI Interpreter (3006,00A6)
        if let interpData = findTagData(data, group: 0x3006, element: 0x00A6) {
            roiInterpreter = String(data: interpData, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return RTStructObservation(
            observationNumber: observationNumber,
            referencedROINumber: referencedROINumber,
            roiObservationLabel: roiObservationLabel,
            rtROIInterpretedType: rtROIInterpretedType,
            roiInterpreter: roiInterpreter
        )
    }
    
    // MARK: - Data Utilities
    
    /// Find tag data in DICOM data
    private static func findTagData(_ data: Data, group: UInt16, element: UInt16) -> Data? {
        var offset = 0
        
        while offset + 8 <= data.count {
            let foundGroup = data.readUInt16(at: offset, littleEndian: true)
            let foundElement = data.readUInt16(at: offset + 2, littleEndian: true)
            let length = data.readUInt32(at: offset + 4, littleEndian: true)
            
            if foundGroup == group && foundElement == element {
                let dataStart = offset + 8
                let dataLength = Int(length)
                
                guard dataStart + dataLength <= data.count else {
                    return nil
                }
                
                return data.subdata(in: dataStart..<dataStart + dataLength)
            }
            
            offset += 8
            if length != 0xFFFFFFFF && length > 0 {
                offset += Int(length)
            } else {
                offset += 2 // Continue searching
            }
        }
        
        return nil
    }
    
    // MARK: - Metadata and Combination
    
    /// Extract metadata from RTStruct dataset
    private static func extractMetadata(from dataset: DICOMDataset) -> RTStructMetadata {
        return RTStructMetadata(
            patientName: dataset.patientName,
            studyInstanceUID: dataset.getString(tag: DICOMTag.studyInstanceUID) ?? "",
            seriesInstanceUID: dataset.getString(tag: DICOMTag.seriesInstanceUID) ?? "",
            sopInstanceUID: dataset.getString(tag: DICOMTag.sopInstanceUID) ?? "",
            structureSetLabel: dataset.getString(tag: DICOMTag.structureSetLabel) ?? "Unknown",
            structureSetName: dataset.getString(tag: DICOMTag.structureSetName),
            structureSetDescription: dataset.getString(tag: DICOMTag.structureSetDescription),
            structureSetDate: dataset.getString(tag: DICOMTag.structureSetDate),
            structureSetTime: dataset.getString(tag: DICOMTag.structureSetTime),
            referencedFrameOfReferenceUID: dataset.getString(tag: DICOMTag.frameOfReferenceUID),
            referencedStudyInstanceUID: dataset.getString(tag: DICOMTag.studyInstanceUID),
            referencedSeriesInstanceUID: nil
        )
    }
    
    /// Combine ROI data from different sequences into complete structures
    private static func combineROIData(
        definitions: [RTStructDefinition],
        contours: [RTStructContourSet],
        observations: [RTStructObservation]
    ) throws -> [ROIStructure] {
        var roiStructures: [ROIStructure] = []
        
        // Create maps for quick lookup
        let contourMap = Dictionary(uniqueKeysWithValues: contours.map { ($0.referencedROINumber, $0) })
        let observationMap = Dictionary(uniqueKeysWithValues: observations.map { ($0.referencedROINumber, $0) })
        
        for definition in definitions {
            let contourSet = contourMap[definition.roiNumber]
            let observation = observationMap[definition.roiNumber]
            
            // Use display color from contour set or generate one
            let displayColor = contourSet?.displayColor ?? StandardROIColors.getColorForROI(definition.roiName)
            
            let structure = ROIStructure(
                roiNumber: definition.roiNumber,
                roiName: definition.roiName,
                roiDescription: definition.roiDescription,
                roiGenerationAlgorithm: definition.roiGenerationAlgorithm,
                displayColor: displayColor,
                isVisible: true,
                opacity: 0.5,
                contours: contourSet?.contours ?? []
            )
            
            roiStructures.append(structure)
        }
        
        // Sort by ROI number for consistent ordering
        roiStructures.sort { $0.roiNumber < $1.roiNumber }
        
        return roiStructures
    }
    
    // MARK: - Testing and Validation Methods
    
    /// Quick test parse to validate RTStruct format
    public static func testParseRTStruct(from dataset: DICOMDataset) -> (success: Bool, message: String) {
        do {
            let rtStructData = try parseRTStruct(from: dataset)
            let roiCount = rtStructData.roiStructures.count
            let totalContours = rtStructData.roiStructures.reduce(0) { $0 + $1.contours.count }
            let totalPoints = rtStructData.roiStructures.reduce(0) { $0 + $1.totalPoints }
            
            let message = "✅ RTStruct parsed successfully: \(roiCount) ROIs, \(totalContours) contours, \(totalPoints) total points"
            return (true, message)
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
        
        if let structureSetLabel = dataset.getString(tag: DICOMTag.structureSetLabel) {
            info += "   🏷️ Label: \(structureSetLabel)\n"
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
        
        // Validation status
        let validation = RTStructValidator.validateRTStruct(dataset)
        info += "\n📋 RTStruct Validation: \(validation.isValid ? "✅ VALID" : "❌ INVALID")"
        if !validation.issues.isEmpty {
            info += "\n⚠️ Issues: \(validation.issues.joined(separator: ", "))"
        }
        
        return info
    }
    
    /// Parse RTStruct with raw data fallback (for compatibility with existing code)
    public static func parseRTStructWithRawData(from dataset: DICOMDataset, rawData: Data) throws -> RTStructData {
        print("📊 Parsing RTStruct with raw data fallback...")
        
        // DEBUG: Check if sequence elements have data
        if let structSeq = dataset.elements[DICOMTag.structureSetROISequence] {
            print("   🔍 Structure Set ROI element found: \(structSeq.data.count) bytes")
        }
        if let contourSeq = dataset.elements[DICOMTag.roiContourSequence] {
            print("   🔍 ROI Contour element found: \(contourSeq.data.count) bytes")
        }
        if let obsSeq = dataset.elements[DICOMTag.rtROIObservationsSequence] {
            print("   🔍 RT ROI Observations element found: \(obsSeq.data.count) bytes")
        }
        
        // The sequence elements exist but have no data - use raw data extraction
        print("   🔧 Sequence elements have no data - using raw data extraction")
        
        let metadata = extractMetadata(from: dataset)
        
        // Use raw data extraction with the working getSequenceData method
        let roiDefinitions = try parseStructureSetROISequenceFromRaw(dataset: dataset, rawData: rawData)
        print("   🎯 Found \(roiDefinitions.count) ROI definitions")
        
        let roiContours = try parseROIContourSequenceFromRaw(dataset: dataset, rawData: rawData, definitions: roiDefinitions)
        print("   📐 Found \(roiContours.count) ROI contour sets")
        
        let roiObservations = parseRTROIObservationsSequenceFromRaw(dataset: dataset, rawData: rawData)
        print("   🎨 Found \(roiObservations.count) ROI observations")
        
        // Combine all data into complete ROI structures
        let roiStructures = try combineROIDataFromRaw(
            definitions: roiDefinitions,
            contours: roiContours,
            observations: roiObservations
        )
        
        print("   ✅ Successfully parsed \(roiStructures.count) complete ROI structures")
        
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
    
    // MARK: - Raw Data Parsing (Working Methods)
    
    /// Parse Structure Set ROI Sequence from raw DICOM data
    private static func parseStructureSetROISequenceFromRaw(dataset: DICOMDataset, rawData: Data) throws -> [RTStructRawDefinition] {
        print("   📋 Parsing Structure Set ROI Sequence from raw data...")
        
        guard let sequenceData = dataset.getSequenceData(tag: DICOMTag.structureSetROISequence, fromRawData: rawData) else {
            throw RTStructError.missingRequiredSequence("Structure Set ROI Sequence")
        }
        
        print("   🔍 Extracted sequence data: \(sequenceData.count) bytes")
        
        // Use the working raw sequence parser
        let sequenceItems = parseUniversalSequenceItems(from: sequenceData)
        print("   📊 Found \(sequenceItems.count) sequence items")
        
        var roiDefinitions: [RTStructRawDefinition] = []
        
        for (index, item) in sequenceItems.enumerated() {
            let roiNumber = extractIntFromRawItem(item, tag: DICOMTag.roiNumber) ?? (index + 1)
            let roiName = extractStringFromRawItem(item, tag: DICOMTag.roiName) ?? "ROI \(roiNumber)"
            let roiDescription = extractStringFromRawItem(item, tag: DICOMTag.roiDescription)
            let roiGenerationAlgorithm = extractStringFromRawItem(item, tag: DICOMTag.roiGenerationAlgorithm)
            
            let definition = RTStructRawDefinition(
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
    private static func parseROIContourSequenceFromRaw(dataset: DICOMDataset, rawData: Data, definitions: [RTStructRawDefinition]) throws -> [RTStructRawContourSet] {
        print("   🖼️ Parsing ROI Contour Sequence from raw data...")
        
        guard let sequenceData = dataset.getSequenceData(tag: DICOMTag.roiContourSequence, fromRawData: rawData) else {
            throw RTStructError.missingRequiredSequence("ROI Contour Sequence")
        }
        
        print("   🔍 Extracted sequence data: \(sequenceData.count) bytes")
        
        // MIM-specific parsing: Find the 3 ROI sections by Display Color tags
        // Based on our analysis: ROI sections at offsets with Display Color markers
        var roiSectionOffsets: [Int] = []
        var offset = 0
        
        // Look for ROI Display Color tags (3006,002A) which mark the start of each ROI section
        while offset + 8 <= sequenceData.count {
            let group = sequenceData.readUInt16(at: offset, littleEndian: true)
            let element = sequenceData.readUInt16(at: offset + 2, littleEndian: true)
            
            if group == 0x3006 && element == 0x002A { // ROI Display Color
                // Look back for the item delimiter that starts this ROI section
                var itemStart = offset
                while itemStart >= 8 {
                    let checkGroup = sequenceData.readUInt16(at: itemStart - 8, littleEndian: true)
                    let checkElement = sequenceData.readUInt16(at: itemStart - 6, littleEndian: true)
                    if checkGroup == 0xFFFE && checkElement == 0xE000 {
                        itemStart -= 8
                        break
                    }
                    itemStart -= 2
                }
                
                roiSectionOffsets.append(itemStart)
                print("      🎯 Found ROI section at offset \(itemStart) (Display Color at \(offset))")
            }
            
            offset += 2
        }
        
        print("   📊 Found \(roiSectionOffsets.count) ROI sections")
        
        var contourSets: [RTStructRawContourSet] = []
        
        // Parse each ROI section separately
        for (index, sectionOffset) in roiSectionOffsets.enumerated() {
            let nextOffset = index < roiSectionOffsets.count - 1 ? roiSectionOffsets[index + 1] : sequenceData.count
            let sectionData = sequenceData.subdata(in: sectionOffset..<nextOffset)
            
            print("      🔍 Processing ROI section \(index + 1): \(sectionData.count) bytes")
            
            // Parse this ROI section as a single item
            let item = parseRawSequenceItem(sectionData.subdata(in: 8..<sectionData.count)) // Skip item delimiter
            
            // CRITICAL FIX: Extract the actual Referenced ROI Number from the section
            // If not found, map to the corresponding ROI definition by index
            var referencedROINumber = extractIntFromRawItem(item, tag: DICOMTag.referencedROINumber)
            
            if referencedROINumber == nil {
                print("      ⚠️ No Referenced ROI Number found in contour section, using ROI definition mapping")
                // Map to the corresponding ROI definition by index
                if index < definitions.count {
                    referencedROINumber = definitions[index].roiNumber
                    print("      ✅ Mapped section \(index + 1) to ROI \(referencedROINumber!)")
                } else {
                    referencedROINumber = index + 1 // Fallback
                    print("      ⚠️ Using fallback ROI number: \(referencedROINumber!)")
                }
            } else {
                print("      ✅ Found Referenced ROI Number: \(referencedROINumber!)")
            }
            
            let displayColor = extractDisplayColorFromRawItem(item)
            
            // Parse nested contour sequence from this specific ROI section
            let contours = parseContourSequenceFromRawItem(item)
            
            let contourSet = RTStructRawContourSet(
                referencedROINumber: referencedROINumber!,
                displayColor: displayColor,
                contours: contours
            )
            
            contourSets.append(contourSet)
            print("      🖼️ ROI \(referencedROINumber!): \(contours.count) contours")
        }
        
        return contourSets
    }
    
    /// Parse RT ROI Observations Sequence from raw DICOM data
    private static func parseRTROIObservationsSequenceFromRaw(dataset: DICOMDataset, rawData: Data) -> [RTStructRawObservation] {
        print("   👁️ Parsing RT ROI Observations Sequence from raw data...")
        
        guard let sequenceData = dataset.getSequenceData(tag: DICOMTag.rtROIObservationsSequence, fromRawData: rawData) else {
            print("   ℹ️ No RT ROI Observations Sequence found (optional)")
            return []
        }
        
        print("   🔍 Extracted sequence data: \(sequenceData.count) bytes")
        
        let sequenceItems = parseUniversalSequenceItems(from: sequenceData)
        print("   📊 Found \(sequenceItems.count) sequence items")
        
        var observations: [RTStructRawObservation] = []
        
        for (index, item) in sequenceItems.enumerated() {
            let observationNumber = extractIntFromRawItem(item, tag: DICOMTag.observationNumber) ?? (index + 1)
            let referencedROINumber = extractIntFromRawItem(item, tag: DICOMTag.referencedROINumber) ?? (index + 1)
            let roiObservationLabel = extractStringFromRawItem(item, tag: DICOMTag.roiObservationLabel)
            let rtROIInterpretedType = extractStringFromRawItem(item, tag: DICOMTag.rtROIInterpretedType)
            let roiInterpreter = extractStringFromRawItem(item, tag: DICOMTag.roiInterpreter)
            
            let observation = RTStructRawObservation(
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
    
    /// Parse contour sequence from raw ROI item
    private static func parseContourSequenceFromRawItem(_ item: RawSequenceItem) -> [ROIContour] {
        guard let contourSequenceData = item.elements[DICOMTag.contourSequence] else {
            print("        ⚠️ No contour sequence found in ROI item")
            return []
        }
        
        print("        ✅ Found contour sequence data: \(contourSequenceData.count) bytes")
        
        // CRITICAL: Instead of using the broken sequence parser, search for actual contour data
        // Look for patterns that indicate real contour coordinates
        let contours = findActualContourData(in: contourSequenceData)
        
        if !contours.isEmpty {
            print("        ✅ Found \(contours.count) contours with actual coordinate data")
            return contours
        }
        
        // Fallback to the previous method if no real contour data found
        print("        ⚠️ No actual contour data found, falling back to sequence parsing")
        
        // Debug: Check what's in the contour sequence data
        let debugBytes = contourSequenceData.prefix(32)
        let hexString = debugBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("        🔍 First 32 bytes of contour sequence: \(hexString)")
        
        // Use universal sequence parser for nested contour items
        let contourItems = parseUniversalSequenceItems(from: contourSequenceData)
        print("        📊 Found \(contourItems.count) contour items")
        
        var fallbackContours: [ROIContour] = []
        
        for (index, contourItem) in contourItems.enumerated() {
            print("        🔍 DEBUG: Processing contour item \(index + 1):")
            print("        🔍 DEBUG: Available tags in contour item:")
            for (tag, data) in contourItem.elements {
                print("           Tag (\(String(format: "%04X", tag.group)),\(String(format: "%04X", tag.element))): \(data.count) bytes")
            }
            
            let geometricTypeString = extractStringFromRawItem(contourItem, tag: DICOMTag.contourGeometricType) ?? "CLOSED_PLANAR"
            let geometricType = ContourGeometricType(rawValue: geometricTypeString) ?? .closedPlanar
            
            let numberOfContourPoints = extractIntFromRawItem(contourItem, tag: DICOMTag.numberOfContourPoints) ?? 0
            let referencedSOPInstanceUID = extractStringFromRawItem(contourItem, tag: DICOMTag.referencedSOPInstanceUID)
            
            // Parse contour data points from raw item with enhanced debugging
            let points = parseContourDataFromRawItemWithDebug(contourItem)
            
            // Calculate slice position from first point
            let slicePosition = points.first?.z ?? 0.0
            
            // CRITICAL FIX: Use actual point count, not the numberOfContourPoints field
            let actualPointCount = points.count
            print("        🔍 CRITICAL DEBUG:")
            print("           numberOfContourPoints field: \(numberOfContourPoints)")
            print("           actual points parsed: \(actualPointCount)")
            print("           geometric type: \(geometricTypeString)")
            print("           slice position: \(slicePosition)")
            
            let contour = ROIContour(
                contourNumber: index + 1,
                geometricType: geometricType,
                numberOfPoints: actualPointCount, // USE ACTUAL COUNT
                contourData: points,
                slicePosition: slicePosition,
                referencedSOPInstanceUID: referencedSOPInstanceUID
            )
            
            fallbackContours.append(contour)
            print("        📐 Contour \(index + 1): \(actualPointCount) points (\(geometricTypeString)) at Z=\(slicePosition)")
            
            if points.isEmpty {
                print("        ⚠️ WARNING: Contour has no points!")
            } else {
                print("        ✅ SUCCESS: Contour created with \(actualPointCount) points")
                // Debug: Show first few points
                let firstPoints = points.prefix(3)
                for (pointIndex, point) in firstPoints.enumerated() {
                    print("           Point \(pointIndex + 1): (\(point.x), \(point.y), \(point.z))")
                }
            }
        }
        
        print("        📊 FINAL RESULT: Created \(fallbackContours.count) contours with total points: \(fallbackContours.reduce(0) { $0 + $1.numberOfPoints })")
        return fallbackContours
    }
    
    /// Find actual contour data by searching for contour coordinate patterns
    private static func findActualContourData(in sequenceData: Data) -> [ROIContour] {
        print("        🔍 Searching for actual contour coordinate data in \(sequenceData.count) bytes...")
        
        var contours: [ROIContour] = []
        var offset = 0
        var contourIndex = 1
        
        // Strategy 1: Look for Contour Data tags (3006,0050)
        print("        🔍 Strategy 1: Looking for Contour Data tags (3006,0050)...")
        while offset + 8 <= sequenceData.count {
            let group = sequenceData.readUInt16(at: offset, littleEndian: true)
            let element = sequenceData.readUInt16(at: offset + 2, littleEndian: true)
            let length = sequenceData.readUInt32(at: offset + 4, littleEndian: true)
            
            if group == 0x3006 && element == 0x0050 { // Contour Data tag
                print("        🎯 Found Contour Data tag at offset \(offset), length: \(length)")
                
                let dataStart = offset + 8
                let dataLength = Int(length)
                
                guard dataStart + dataLength <= sequenceData.count else {
                    print("        ⚠️ Contour data extends beyond sequence")
                    offset += 8
                    continue
                }
                
                let contourData = sequenceData.subdata(in: dataStart..<dataStart + dataLength)
                print("        🔍 Extracted contour data: \(contourData.count) bytes")
                
                // Parse the contour points
                let points = parseContourPointsFromData(contourData)
                
                if !points.isEmpty {
                    print("        ✅ Found \(points.count) actual contour points!")
                    
                    // Show first few points for debugging
                    let firstPoints = points.prefix(3)
                    for (pointIndex, point) in firstPoints.enumerated() {
                        print("           Point \(pointIndex + 1): (\(point.x), \(point.y), \(point.z))")
                    }
                    
                    // Calculate slice position from first point
                    let slicePosition = points.first?.z ?? 0.0
                    
                    let contour = ROIContour(
                        contourNumber: contourIndex,
                        geometricType: .closedPlanar,
                        numberOfPoints: points.count,
                        contourData: points,
                        slicePosition: slicePosition,
                        referencedSOPInstanceUID: nil
                    )
                    
                    contours.append(contour)
                    print("        📐 Created contour \(contourIndex): \(points.count) points at Z=\(slicePosition)")
                    contourIndex += 1
                }
                
                offset = dataStart + dataLength
            } else {
                offset += 2 // Continue searching
            }
        }
        
        if !contours.isEmpty {
            print("        📊 Strategy 1 found \(contours.count) contours")
            return contours
        }
        
        print("        ⚠️ Strategy 1 failed - no Contour Data tags found")
        
        // Strategy 2: Look for ASCII decimal strings (backslash-separated coordinates)
        print("        🔍 Strategy 2: Looking for ASCII decimal coordinate strings...")
        if let dataString = String(data: sequenceData, encoding: .ascii) {
            // Look for patterns like "123.45\678.90\-12.34" (decimal coordinates separated by backslashes)
            if dataString.contains("\\") && dataString.contains(".") {
                print("        🎯 Found backslash-separated decimal pattern")
                
                // Extract coordinate strings
                let coordinatePattern = try! NSRegularExpression(pattern: "[-+]?\\d+\\.\\d+", options: [])
                let matches = coordinatePattern.matches(in: dataString, options: [], range: NSRange(location: 0, length: dataString.count))
                
                if matches.count >= 3 && matches.count % 3 == 0 {
                    var points: [SIMD3<Float>] = []
                    
                    for i in stride(from: 0, to: matches.count, by: 3) {
                        guard i + 2 < matches.count else { break }
                        
                        let xRange = matches[i].range
                        let yRange = matches[i + 1].range
                        let zRange = matches[i + 2].range
                        
                        let xString = String(dataString[Range(xRange, in: dataString)!])
                        let yString = String(dataString[Range(yRange, in: dataString)!])
                        let zString = String(dataString[Range(zRange, in: dataString)!])
                        
                        if let x = Float(xString), let y = Float(yString), let z = Float(zString) {
                            // Validate that these are reasonable anatomical coordinates
                            if abs(x) < 1000 && abs(y) < 1000 && abs(z) < 1000 {
                                points.append(SIMD3<Float>(x, y, z))
                            }
                        }
                    }
                    
                    if !points.isEmpty {
                        print("        ✅ Found \(points.count) coordinate points from ASCII pattern!")
                        
                        // Show first few points
                        let firstPoints = points.prefix(3)
                        for (pointIndex, point) in firstPoints.enumerated() {
                            print("           Point \(pointIndex + 1): (\(point.x), \(point.y), \(point.z))")
                        }
                        
                        let slicePosition = points.first?.z ?? 0.0
                        
                        let contour = ROIContour(
                            contourNumber: 1,
                            geometricType: .closedPlanar,
                            numberOfPoints: points.count,
                            contourData: points,
                            slicePosition: slicePosition,
                            referencedSOPInstanceUID: nil
                        )
                        
                        return [contour]
                    }
                }
            }
        }
        
        print("        ⚠️ Strategy 2 failed - no ASCII coordinate patterns found")
        
        // Strategy 3: Look for binary floating point patterns
        print("        🔍 Strategy 3: Looking for binary floating point coordinate arrays...")
        
        // Search for sequences of reasonable floating point values
        var bestPoints: [SIMD3<Float>] = []
        var searchOffset = 0
        
        while searchOffset + 12 <= sequenceData.count {
            var candidatePoints: [SIMD3<Float>] = []
            var currentOffset = searchOffset
            
            // Try to read a sequence of 3D points
            while currentOffset + 12 <= sequenceData.count {
                let x = sequenceData.readFloat32(at: currentOffset, littleEndian: true)
                let y = sequenceData.readFloat32(at: currentOffset + 4, littleEndian: true)
                let z = sequenceData.readFloat32(at: currentOffset + 8, littleEndian: true)
                
                // Check if these look like reasonable anatomical coordinates
                if abs(x) < 1000 && abs(y) < 1000 && abs(z) < 1000 &&
                   !x.isNaN && !y.isNaN && !z.isNaN &&
                   !x.isInfinite && !y.isInfinite && !z.isInfinite {
                    candidatePoints.append(SIMD3<Float>(x, y, z))
                    currentOffset += 12
                } else {
                    break
                }
            }
            
            // Keep the longest sequence found
            if candidatePoints.count > bestPoints.count && candidatePoints.count >= 3 {
                bestPoints = candidatePoints
                print("        🎯 Found \(candidatePoints.count) candidate points starting at offset \(searchOffset)")
            }
            
            searchOffset += 4 // Move search position
        }
        
        if bestPoints.count >= 3 {
            print("        ✅ Found \(bestPoints.count) coordinate points from binary pattern!")
            
            // Show first few points
            let firstPoints = bestPoints.prefix(3)
            for (pointIndex, point) in firstPoints.enumerated() {
                print("           Point \(pointIndex + 1): (\(point.x), \(point.y), \(point.z))")
            }
            
            let slicePosition = bestPoints.first?.z ?? 0.0
            
            let contour = ROIContour(
                contourNumber: 1,
                geometricType: .closedPlanar,
                numberOfPoints: bestPoints.count,
                contourData: bestPoints,
                slicePosition: slicePosition,
                referencedSOPInstanceUID: nil
            )
            
            return [contour]
        }
        
        print("        ⚠️ Strategy 3 failed - no valid binary coordinate patterns found")
        print("        📊 Total contours found with actual data: 0")
        return []
    }
    
    /// Parse contour data points from raw contour item with enhanced debugging
    private static func parseContourDataFromRawItemWithDebug(_ contourItem: RawSequenceItem) -> [SIMD3<Float>] {
        print("        🔍 Looking for contour data tag (3006,0050)...")
        
        // First check for the standard contour data tag
        if let contourData = contourItem.elements[DICOMTag.contourData] {
            print("        ✅ Found contour data: \(contourData.count) bytes")
            return parseContourPointsFromData(contourData)
        }
        
        // If no direct contour data, check what we do have
        print("        ❌ No contour data found in contour item")
        print("        🔍 Available elements in contour item:")
        for (tag, data) in contourItem.elements {
            print("           (\(String(format: "%04X", tag.group)),\(String(format: "%04X", tag.element))): \(data.count) bytes")
            
            // Check if this is a Contour Image Sequence (3006,0016)
            if tag.group == 0x3006 && tag.element == 0x0016 {
                print("        🔍 Found Contour Image Sequence - examining nested structure...")
                
                // This might contain nested contour data - let's parse it
                let nestedContours = parseNestedContourSequence(data)
                if !nestedContours.isEmpty {
                    print("        ✅ Found \(nestedContours.count) points in nested structure")
                    return nestedContours
                }
            }
        }
        
        return []
    }
    
    /// Parse nested contour sequence that might contain the actual contour data
    private static func parseNestedContourSequence(_ sequenceData: Data) -> [SIMD3<Float>] {
        print("        🔍 Parsing nested contour sequence (\(sequenceData.count) bytes)...")
        
        // Debug the nested sequence structure
        let debugBytes = sequenceData.prefix(64)
        let hexString = debugBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("        🔍 First 64 bytes: \(hexString)")
        
        // Parse as sequence items to find nested contour data
        let nestedItems = parseUniversalSequenceItems(from: sequenceData)
        print("        📊 Found \(nestedItems.count) nested items")
        
        var allPoints: [SIMD3<Float>] = []
        
        for (index, nestedItem) in nestedItems.enumerated() {
            print("        🔍 Processing nested item \(index + 1):")
            for (tag, data) in nestedItem.elements {
                print("           Tag (\(String(format: "%04X", tag.group)),\(String(format: "%04X", tag.element))): \(data.count) bytes")
                
                // Check for contour data in nested item
                if tag.group == 0x3006 && tag.element == 0x0050 {
                    print("        ✅ Found contour data in nested item!")
                    let points = parseContourPointsFromData(data)
                    allPoints.append(contentsOf: points)
                }
            }
        }
        
        // If no nested contour data found, try parsing the entire sequence as raw contour data
        if allPoints.isEmpty {
            print("        🔍 No nested contour data found, trying to parse as raw contour points...")
            
            // Try different approaches to extract contour data
            // Approach 1: Look for decimal strings in the raw data
            if let dataString = String(data: sequenceData, encoding: .ascii) {
                print("        🔍 Trying ASCII interpretation...")
                let preview = dataString.prefix(200)
                print("        🔍 ASCII preview: \(preview)")
                
                // Look for patterns like "123.45\678.90\-12.34"
                if dataString.contains("\\") && dataString.contains(".") {
                    print("        ✅ Found decimal string pattern!")
                    return parseContourPointsFromData(sequenceData)
                }
            }
            
            // Approach 2: Look for floating point numbers in binary format
            if sequenceData.count >= 12 { // At least one 3D point (3 * 4 bytes)
                print("        🔍 Trying binary float interpretation...")
                var binaryPoints: [SIMD3<Float>] = []
                var offset = 0
                
                while offset + 12 <= sequenceData.count {
                    let x = sequenceData.readFloat32(at: offset, littleEndian: true)
                    let y = sequenceData.readFloat32(at: offset + 4, littleEndian: true)
                    let z = sequenceData.readFloat32(at: offset + 8, littleEndian: true)
                    
                    // Sanity check - reasonable coordinate values
                    if abs(x) < 10000 && abs(y) < 10000 && abs(z) < 10000 {
                        binaryPoints.append(SIMD3<Float>(x, y, z))
                        offset += 12
                    } else {
                        offset += 4 // Try next position
                    }
                }
                
                if binaryPoints.count > 0 {
                    print("        ✅ Found \(binaryPoints.count) binary float points!")
                    return binaryPoints
                }
            }
        }
        
        return allPoints
    }
    
    /// Parse contour points from raw data
    private static func parseContourPointsFromData(_ contourData: Data) -> [SIMD3<Float>] {
        // Debug the raw contour data
        if contourData.count > 0 {
            let debugBytes = contourData.prefix(min(64, contourData.count))
            let hexString = debugBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("        🔍 First bytes of contour data: \(hexString)")
            
            // Try to interpret as ASCII string
            if let dataString = String(data: contourData, encoding: .ascii) {
                let preview = dataString.prefix(100)
                print("        🔍 Contour data as ASCII: \(preview)...")
            }
        }
        
        // Parse as decimal string format (most common)
        let dataString = String(data: contourData, encoding: .ascii) ?? ""
        let components = dataString.components(separatedBy: "\\")
        
        print("        🔍 Split into \(components.count) components")
        if components.count > 0 {
            print("        🔍 First few components: \(components.prefix(6).joined(separator: ", "))")
        }
        
        guard components.count % 3 == 0 else {
            print("        ⚠️ Invalid contour data: point count not divisible by 3 (\(components.count) components)")
            return []
        }
        
        var points: [SIMD3<Float>] = []
        
        for i in stride(from: 0, to: components.count, by: 3) {
            guard i + 2 < components.count,
                  let x = Float(components[i].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let y = Float(components[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let z = Float(components[i + 2].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                print("        ⚠️ Failed to parse point at index \(i): '\(components[i])', '\(components[i+1])', '\(components[i+2])'")
                continue
            }
            
            points.append(SIMD3<Float>(x, y, z))
        }
        
        print("        ✅ Successfully parsed \(points.count) contour points")
        
        return points
    }
    
    /// Universal sequence parser that handles any DICOM sequence format
    private static func parseUniversalSequenceItems(from sequenceData: Data) -> [RawSequenceItem] {
        var items: [RawSequenceItem] = []
        var offset = 0
        
        while offset + 8 <= sequenceData.count {
            let group = sequenceData.readUInt16(at: offset, littleEndian: true)
            let element = sequenceData.readUInt16(at: offset + 2, littleEndian: true)
            let length = sequenceData.readUInt32(at: offset + 4, littleEndian: true)
            
            // Look for sequence item delimiters
            if group == 0xFFFE && element == 0xE000 {
                // Found sequence item start
                let itemStart = offset + 8
                let itemData: Data
                
                if length == 0xFFFFFFFF {
                    // Undefined length item - find the item delimiter
                    itemData = findUndefinedLengthItemData(sequenceData, startOffset: itemStart)
                    offset = itemStart + itemData.count
                    
                    // Skip past item delimiter if present
                    if offset + 8 <= sequenceData.count {
                        let delimGroup = sequenceData.readUInt16(at: offset, littleEndian: true)
                        let delimElement = sequenceData.readUInt16(at: offset + 2, littleEndian: true)
                        if delimGroup == 0xFFFE && delimElement == 0xE00D {
                            offset += 8
                        }
                    }
                } else {
                    // Defined length item
                    let itemLength = Int(length)
                    guard itemStart + itemLength <= sequenceData.count else {
                        print("        ⚠️ Item extends beyond sequence data")
                        break
                    }
                    
                    itemData = sequenceData.subdata(in: itemStart..<itemStart + itemLength)
                    offset = itemStart + itemLength
                }
                
                // Parse the item data
                let item = parseRawSequenceItem(itemData)
                items.append(item)
                
            } else if group == 0xFFFE && element == 0xE0DD {
                // Sequence delimiter - end of sequence
                break
            } else {
                // Skip unexpected data
                offset += 8
                if length != 0xFFFFFFFF && length > 0 {
                    offset += Int(length)
                }
            }
        }
        
        return items
    }
    
    /// Find undefined length item data by looking for item delimiter
    private static func findUndefinedLengthItemData(_ data: Data, startOffset: Int) -> Data {
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
                        nestingLevel -= 1
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
                    // Sequence delimiter
                    if nestingLevel == 0 {
                        return data.subdata(in: startOffset..<offset)
                    } else {
                        offset += 8
                    }
                } else {
                    // Other FFFE element
                    offset += 8
                    if length != 0xFFFFFFFF && length > 0 {
                        offset += Int(length)
                    }
                }
            } else {
                // Regular DICOM element
                offset += 8
                if length != 0xFFFFFFFF && length > 0 {
                    offset += Int(length)
                }
            }
        }
        
        // If no delimiter found, return remaining data
        return data.subdata(in: startOffset..<data.count)
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
            
            // Handle implicit VR
            guard offset + 4 <= itemData.count else { break }
            let length = itemData.readUInt32(at: offset, littleEndian: true)
            offset += 4
            
            if length == 0xFFFFFFFF {
                // Undefined length sequence - extract all remaining data
                let elementData = itemData.subdata(in: offset..<itemData.count)
                elements[tag] = elementData
                break
            }
            
            let dataLength = Int(length)
            guard offset + dataLength <= itemData.count else { break }
            
            let elementData = itemData.subdata(in: offset..<offset + dataLength)
            elements[tag] = elementData
            
            offset += dataLength
            
            // Handle odd-length padding
            if dataLength % 2 == 1 && offset < itemData.count {
                offset += 1
            }
        }
        
        return RawSequenceItem(elements: elements)
    }
    
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
    
    /// Combine ROI data from raw sequences into complete structures
    private static func combineROIDataFromRaw(
        definitions: [RTStructRawDefinition],
        contours: [RTStructRawContourSet],
        observations: [RTStructRawObservation]
    ) throws -> [ROIStructure] {
        print("   🔗 COMBINING ROI DATA:")
        print("      📋 Definitions: \(definitions.count)")
        print("      🖼️ Contour sets: \(contours.count)")
        print("      👁️ Observations: \(observations.count)")
        
        var roiStructures: [ROIStructure] = []
        
        // Create maps for quick lookup
        let contourMap = Dictionary(uniqueKeysWithValues: contours.map { ($0.referencedROINumber, $0) })
        let observationMap = Dictionary(uniqueKeysWithValues: observations.map { ($0.referencedROINumber, $0) })
        
        print("      🗂️ Created lookup maps:")
        print("         Contour map keys: \(contourMap.keys.sorted())")
        print("         Observation map keys: \(observationMap.keys.sorted())")
        
        for definition in definitions {
            print("      🔍 Processing definition: ROI \(definition.roiNumber) (\(definition.roiName))")
            
            let contourSet = contourMap[definition.roiNumber]
            let observation = observationMap[definition.roiNumber]
            
            if let contourSet = contourSet {
                print("         ✅ Found contour set with \(contourSet.contours.count) contours")
                for (i, contour) in contourSet.contours.enumerated() {
                    print("            Contour \(i + 1): \(contour.numberOfPoints) points")
                }
            } else {
                print("         ⚠️ No contour set found for ROI \(definition.roiNumber)")
            }
            
            if let observation = observation {
                print("         ✅ Found observation")
            } else {
                print("         ⚠️ No observation found for ROI \(definition.roiNumber)")
            }
            
            // Use display color from contour set or generate one
            let displayColor = contourSet?.displayColor ?? StandardROIColors.getColorForROI(definition.roiName)
            
            let finalContours = contourSet?.contours ?? []
            print("         📊 Final contours for ROI \(definition.roiNumber): \(finalContours.count)")
            
            let structure = ROIStructure(
                roiNumber: definition.roiNumber,
                roiName: definition.roiName,
                roiDescription: definition.roiDescription,
                roiGenerationAlgorithm: definition.roiGenerationAlgorithm,
                displayColor: displayColor,
                isVisible: true,
                opacity: 0.5,
                contours: finalContours
            )
            
            roiStructures.append(structure)
            print("         ✅ Created ROI structure with \(structure.contours.count) contours")
        }
        
        // Sort by ROI number for consistent ordering
        roiStructures.sort { $0.roiNumber < $1.roiNumber }
        
        print("   🎯 FINAL COMBINATION RESULT:")
        for structure in roiStructures {
            print("      ROI \(structure.roiNumber) (\(structure.roiName)): \(structure.contours.count) contours, \(structure.totalPoints) total points")
        }
        
        return roiStructures
    }
}


// MARK: - Internal Data Structures

/// RTStruct metadata
private struct RTStructMetadata {
    let patientName: String?
    let studyInstanceUID: String?
    let seriesInstanceUID: String?
    let sopInstanceUID: String?
    let structureSetLabel: String?
    let structureSetName: String?
    let structureSetDescription: String?
    let structureSetDate: String?
    let structureSetTime: String?
    let referencedFrameOfReferenceUID: String?
    let referencedStudyInstanceUID: String?
    let referencedSeriesInstanceUID: String?
}

/// ROI definition from Structure Set ROI Sequence
private struct RTStructDefinition {
    let roiNumber: Int
    let roiName: String
    let roiDescription: String?
    let roiGenerationAlgorithm: String?
}

/// ROI contour set from ROI Contour Sequence
private struct RTStructContourSet {
    let referencedROINumber: Int
    let displayColor: SIMD3<Float>
    let contours: [ROIContour]
}

/// ROI observation from RT ROI Observations Sequence
private struct RTStructObservation {
    let observationNumber: Int
    let referencedROINumber: Int
    let roiObservationLabel: String?
    let rtROIInterpretedType: String?
    let roiInterpreter: String?
}

/// Raw sequence item parsed from DICOM data
private struct RawSequenceItem {
    let elements: [DICOMTag: Data]
}

/// Raw ROI definition (for raw data parsing)
private struct RTStructRawDefinition {
    let roiNumber: Int
    let roiName: String
    let roiDescription: String?
    let roiGenerationAlgorithm: String?
}

/// Raw ROI contour set (for raw data parsing)
private struct RTStructRawContourSet {
    let referencedROINumber: Int
    let displayColor: SIMD3<Float>
    let contours: [ROIContour]
}

/// Raw ROI observation (for raw data parsing)
private struct RTStructRawObservation {
    let observationNumber: Int
    let referencedROINumber: Int
    let roiObservationLabel: String?
    let rtROIInterpretedType: String?
    let roiInterpreter: String?
}
