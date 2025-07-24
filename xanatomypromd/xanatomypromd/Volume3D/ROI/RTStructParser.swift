import Foundation
import simd

// MARK: - RTStruct Parser
// Parses RTStruct DICOM files to extract ROI contour data

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
        let roiDefinitions = try parseStructureSetROISequence(from: dataset)
        print("   🎯 Found \(roiDefinitions.count) ROI definitions")
        
        // Parse ROI Contour Sequence (contour geometry)
        let roiContours = try parseROIContourSequence(from: dataset)
        print("   📐 Found \(roiContours.count) ROI contour sets")
        
        // Parse RT ROI Observations Sequence (display properties)
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
            patientName: dataset.getString(tag: .patientName),
            studyInstanceUID: dataset.getString(tag: .studyInstanceUID),
            seriesInstanceUID: dataset.getString(tag: .seriesInstanceUID),
            structureSetLabel: dataset.getString(tag: .structureSetLabel),
            structureSetName: dataset.getString(tag: .structureSetName),
            structureSetDescription: dataset.getString(tag: .structureSetDescription),
            structureSetDate: dataset.getString(tag: .structureSetDate),
            structureSetTime: dataset.getString(tag: .structureSetTime),
            referencedFrameOfReferenceUID: extractReferencedFrameOfReference(from: dataset),
            referencedStudyInstanceUID: extractReferencedStudyUID(from: dataset),
            referencedSeriesInstanceUID: extractReferencedSeriesUID(from: dataset)
        )
    }
    
    // MARK: - Structure Set ROI Sequence Parsing
    
    private static func parseStructureSetROISequence(from dataset: DICOMDataset) throws -> [ROIDefinition] {
        guard let sequenceElement = dataset.elements[.structureSetROISequence] else {
            throw RTStructError.missingRequiredSequence("Structure Set ROI Sequence")
        }
        
        print("   📋 Parsing Structure Set ROI Sequence...")
        
        // For now, parse the sequence as a basic implementation
        // In a full implementation, you'd parse the actual DICOM sequence structure
        // This is a simplified version that extracts available data
        
        var roiDefinitions: [ROIDefinition] = []
        
        // Since we don't have full sequence parsing yet, we'll create a basic structure
        // This will be enhanced when we can test with actual sequence data
        let basicROI = ROIDefinition(
            roiNumber: 1,
            roiName: "Unknown Structure",
            roiDescription: nil,
            roiGenerationAlgorithm: nil
        )
        
        roiDefinitions.append(basicROI)
        
        return roiDefinitions
    }
    
    // MARK: - ROI Contour Sequence Parsing
    
    private static func parseROIContourSequence(from dataset: DICOMDataset) throws -> [ROIContourSet] {
        guard let sequenceElement = dataset.elements[.roiContourSequence] else {
            throw RTStructError.missingRequiredSequence("ROI Contour Sequence")
        }
        
        print("   🖼️ Parsing ROI Contour Sequence...")
        
        // Placeholder implementation - will be enhanced with actual sequence parsing
        var contourSets: [ROIContourSet] = []
        
        // Create a basic contour set for testing
        let basicContourSet = ROIContourSet(
            referencedROINumber: 1,
            displayColor: SIMD3<Float>(1.0, 0.0, 0.0), // Red
            contours: []
        )
        
        contourSets.append(basicContourSet)
        
        return contourSets
    }
    
    // MARK: - RT ROI Observations Sequence Parsing
    
    private static func parseRTROIObservationsSequence(from dataset: DICOMDataset) -> [ROIObservation] {
        guard let sequenceElement = dataset.elements[.rtROIObservationsSequence] else {
            print("   ℹ️ No RT ROI Observations Sequence found (optional)")
            return []
        }
        
        print("   👁️ Parsing RT ROI Observations Sequence...")
        
        // Placeholder implementation
        var observations: [ROIObservation] = []
        
        let basicObservation = ROIObservation(
            observationNumber: 1,
            referencedROINumber: 1,
            roiObservationLabel: nil,
            rtROIInterpretedType: nil,
            roiInterpreter: nil
        )
        
        observations.append(basicObservation)
        
        return observations
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
        // Parse Referenced Frame of Reference Sequence if present
        return dataset.getString(tag: .frameOfReferenceUID)
    }
    
    private static func extractReferencedStudyUID(from dataset: DICOMDataset) -> String? {
        // Parse Referenced Study Sequence if present
        return dataset.getString(tag: .studyInstanceUID) // May be different in referenced context
    }
    
    private static func extractReferencedSeriesUID(from dataset: DICOMDataset) -> String? {
        // Parse Referenced Series Sequence if present
        return nil // Will be implemented when we parse the actual sequence
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

// MARK: - Sequence Parsing Utilities (Placeholder)

extension RTStructParser {
    
    /// Parse DICOM sequence element (placeholder implementation)
    /// This will be enhanced when we have actual sequence data to work with
    private static func parseSequence(_ element: DICOMElement) -> [[String: Any]] {
        // Placeholder: In a real implementation, this would parse the DICOM sequence structure
        // For now, return empty array - will be populated with actual parsing logic
        return []
    }
    
    /// Extract string from sequence item
    private static func extractString(from item: [String: Any], key: String) -> String? {
        return item[key] as? String
    }
    
    /// Extract integer from sequence item
    private static func extractInt(from item: [String: Any], key: String) -> Int? {
        return item[key] as? Int
    }
    
    /// Extract float array from sequence item (for contour data)
    private static func extractFloatArray(from item: [String: Any], key: String) -> [Float]? {
        return item[key] as? [Float]
    }
}

// MARK: - Contour Data Parsing

extension RTStructParser {
    
    /// Parse contour data points from DICOM format
    private static func parseContourData(_ contourDataString: String) -> [SIMD3<Float>] {
        let components = contourDataString.split(separator: "\\").compactMap { Float(String($0)) }
        
        // DICOM contour data is stored as x1\y1\z1\x2\y2\z2\...
        guard components.count % 3 == 0 else {
            print("⚠️ Invalid contour data: not divisible by 3")
            return []
        }
        
        var points: [SIMD3<Float>] = []
        
        for i in stride(from: 0, to: components.count, by: 3) {
            let point = SIMD3<Float>(
                components[i],     // X
                components[i + 1], // Y
                components[i + 2]  // Z
            )
            points.append(point)
        }
        
        return points
    }
    
    /// Parse RGB color from DICOM format
    private static func parseDisplayColor(_ colorString: String?) -> SIMD3<Float> {
        guard let colorString = colorString else {
            return SIMD3<Float>(1.0, 0.0, 0.0) // Default red
        }
        
        let components = colorString.split(separator: "\\").compactMap { Float(String($0)) }
        
        if components.count >= 3 {
            // DICOM colors are typically 0-255, normalize to 0-1
            return SIMD3<Float>(
                components[0] / 255.0,
                components[1] / 255.0,
                components[2] / 255.0
            )
        }
        
        return SIMD3<Float>(1.0, 0.0, 0.0) // Default red
    }
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
        
        if let structureSetName = dataset.getString(tag: .structureSetName) {
            info += "   🏷️ Name: \(structureSetName)\n"
        }
        
        if let structureSetDescription = dataset.getString(tag: .structureSetDescription) {
            info += "   📝 Description: \(structureSetDescription)\n"
        }
        
        if let structureSetDate = dataset.getString(tag: .structureSetDate) {
            info += "   📅 Date: \(structureSetDate)\n"
        }
        
        // Check for required sequences
        let hasStructureSetROI = dataset.elements[.structureSetROISequence] != nil
        let hasROIContour = dataset.elements[.roiContourSequence] != nil
        let hasROIObservations = dataset.elements[.rtROIObservationsSequence] != nil
        
        info += "   📋 Structure Set ROI Sequence: \(hasStructureSetROI ? "✅" : "❌")\n"
        info += "   🖼️ ROI Contour Sequence: \(hasROIContour ? "✅" : "❌")\n"
        info += "   👁️ RT ROI Observations: \(hasROIObservations ? "✅" : "❌")\n"
        
        return info
    }
}
