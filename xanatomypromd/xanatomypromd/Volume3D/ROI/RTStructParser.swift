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
    
    // MARK: - FIXED: Added missing methods
    
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
        
        return info
    }
    
    /// Parse RTStruct with raw data fallback (for compatibility with existing code)
    public static func parseRTStructWithRawData(from dataset: DICOMDataset, rawData: Data) throws -> RTStructData {
        print("📊 Parsing RTStruct with raw data fallback...")
        
        // For now, use the standard parsing method
        // This can be enhanced later with raw data extraction if needed
        return try parseRTStruct(from: dataset)
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
        
        // Parse Contour Sequence (3006,0040) - FIXED COMPREHENSIVE SEARCH
        let contours = parseContourSequenceFromSection(sectionData)
        
        return RTStructContourSet(
            referencedROINumber: referencedROINumber,
            displayColor: displayColor,
            contours: contours
        )
    }
    
    /// Parse contour sequence from ROI section data with comprehensive search
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
                
                // CRITICAL FIX: Use comprehensive search for actual contour data
                let parsedContours = findActualContourData(in: contourSeqData)
                
                if !parsedContours.isEmpty {
                    print("        ✅ Found \(parsedContours.count) contours with actual coordinate data")
                    contours.append(contentsOf: parsedContours)
                } else {
                    print("        ⚠️ No actual contour data found, trying fallback parsing")
                    // Fallback to traditional parsing if comprehensive search fails
                    let fallbackContours = parseIndividualContours(contourSeqData)
                    contours.append(contentsOf: fallbackContours)
                }
                break
            }
            
            offset += 2
        }
        
        return contours
    }
    
    /// CRITICAL FIX: Find actual contour data by searching for contour coordinate patterns
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
                let points = parseContourPoints(contourData)
                
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
        
        print("        📊 Strategy 1 found \(contours.count) contours")
        return contours
    }
    
    /// Parse individual contours from contour sequence data (fallback method)
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
        // Debug the raw contour data
        if contourPointsData.count > 0 {
            let debugBytes = contourPointsData.prefix(min(64, contourPointsData.count))
            let hexString = debugBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("        🔍 First bytes of contour data: \(hexString)")
            
            // Try to interpret as ASCII string
            if let dataString = String(data: contourPointsData, encoding: .ascii) {
                let preview = dataString.prefix(100)
                print("        🔍 Contour data as ASCII: \(preview)...")
            }
        }
        
        // Parse as decimal string format (most common)
        let dataString = String(data: contourPointsData, encoding: .ascii) ?? ""
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
    
} // END OF RTStructParser CLASS - ALL METHODS MUST BE INSIDE HERE

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
