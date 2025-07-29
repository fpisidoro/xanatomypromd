import Foundation

// MARK: - RTStruct-Specific DICOM Tags
// Extension to DICOMTags for RTStruct parsing

extension DICOMTag {
    
    // MARK: - RTStruct General Information
    public static let structureSetLabel = DICOMTag(group: 0x3006, element: 0x0002)
    public static let structureSetName = DICOMTag(group: 0x3006, element: 0x0004)
    public static let structureSetDescription = DICOMTag(group: 0x3006, element: 0x0006)
    public static let structureSetDate = DICOMTag(group: 0x3006, element: 0x0008)
    public static let structureSetTime = DICOMTag(group: 0x3006, element: 0x0009)
    
    // MARK: - Referenced Frame of Reference
    public static let referencedFrameOfReferenceSequence = DICOMTag(group: 0x3006, element: 0x0010)
    public static let rtReferencedStudySequence = DICOMTag(group: 0x3006, element: 0x0012)
    public static let rtReferencedSeriesSequence = DICOMTag(group: 0x3006, element: 0x0014)
    
    // MARK: - Structure Set ROI Sequence (3006,0020)
    public static let structureSetROISequence = DICOMTag(group: 0x3006, element: 0x0020)
    public static let roiNumber = DICOMTag(group: 0x3006, element: 0x0022)
    public static let roiName = DICOMTag(group: 0x3006, element: 0x0026)
    public static let roiDescription = DICOMTag(group: 0x3006, element: 0x0028)
    public static let roiGenerationAlgorithm = DICOMTag(group: 0x3006, element: 0x0036)
    
    // MARK: - RT ROI Observations Sequence (3006,0080)
    public static let rtROIObservationsSequence = DICOMTag(group: 0x3006, element: 0x0080)
    public static let observationNumber = DICOMTag(group: 0x3006, element: 0x0082)
    public static let referencedROINumber = DICOMTag(group: 0x3006, element: 0x0084)
    public static let roiObservationLabel = DICOMTag(group: 0x3006, element: 0x0085)
    public static let rtROIInterpretedType = DICOMTag(group: 0x3006, element: 0x00A4)
    public static let roiInterpreter = DICOMTag(group: 0x3006, element: 0x00A6)
    
    // MARK: - ROI Contour Sequence (3006,0039)
    public static let roiContourSequence = DICOMTag(group: 0x3006, element: 0x0039)
    public static let referencedROINumber_Contour = DICOMTag(group: 0x3006, element: 0x0084) // Same as above, used in contour context
    public static let roiDisplayColor = DICOMTag(group: 0x3006, element: 0x002A)
    
    // MARK: - Contour Sequence (3006,0040)
    public static let contourSequence = DICOMTag(group: 0x3006, element: 0x0040)
    public static let contourImageSequence = DICOMTag(group: 0x3006, element: 0x0016)
    public static let contourGeometricType = DICOMTag(group: 0x3006, element: 0x0042)
    public static let numberOfContourPoints = DICOMTag(group: 0x3006, element: 0x0046)
    public static let contourData = DICOMTag(group: 0x3006, element: 0x0050)
    
    // MARK: - Contour Image Reference
    public static let referencedSOPClassUID = DICOMTag(group: 0x0008, element: 0x1150)
    public static let referencedSOPInstanceUID = DICOMTag(group: 0x0008, element: 0x1155)
    
    // MARK: - Additional RT Tags
    public static let approvalStatus = DICOMTag(group: 0x300E, element: 0x0002)
    public static let reviewDate = DICOMTag(group: 0x300E, element: 0x0004)
    public static let reviewTime = DICOMTag(group: 0x300E, element: 0x0005)
    public static let reviewerName = DICOMTag(group: 0x300E, element: 0x0008)
}

// MARK: - RTStruct Tag Categories

extension DICOMTag {
    
    /// Essential tags for RTStruct parsing
    public static let rtStructEssential: Set<DICOMTag> = [
        .structureSetROISequence,
        .roiContourSequence,
        .rtROIObservationsSequence,
        .roiNumber,
        .roiName,
        .contourSequence,
        .contourGeometricType,
        .numberOfContourPoints,
        .contourData
    ]
    
    /// Tags for RTStruct metadata
    public static let rtStructMetadata: Set<DICOMTag> = [
        .structureSetLabel,
        .structureSetName,
        .structureSetDescription,
        .structureSetDate,
        .structureSetTime,
        .frameOfReferenceUID,
        .approvalStatus
    ]
    
    /// Tags for ROI display properties
    public static let roiDisplay: Set<DICOMTag> = [
        .roiDisplayColor,
        .roiObservationLabel,
        .rtROIInterpretedType
    ]
    
    /// Tags for image references
    public static let imageReferences: Set<DICOMTag> = [
        .contourImageSequence,
        .referencedSOPClassUID,
        .referencedSOPInstanceUID,
        .referencedFrameOfReferenceSequence
    ]
}

// MARK: - Standard ROI Colors

public struct StandardROIColors {
    
    /// Common anatomical structure colors (RGB 0-255)
    public static let standardColors: [String: SIMD3<UInt8>] = [
        "Brain": SIMD3<UInt8>(255, 192, 203),      // Pink
        "Heart": SIMD3<UInt8>(255, 0, 0),          // Red
        "Liver": SIMD3<UInt8>(139, 69, 19),        // Brown
        "Lung": SIMD3<UInt8>(0, 255, 255),         // Cyan
        "Kidney": SIMD3<UInt8>(255, 255, 0),       // Yellow
        "Spleen": SIMD3<UInt8>(128, 0, 128),       // Purple
        "Bladder": SIMD3<UInt8>(255, 165, 0),      // Orange
        "Prostate": SIMD3<UInt8>(0, 128, 0),       // Green
        "Bone": SIMD3<UInt8>(255, 255, 255),       // White
        "Muscle": SIMD3<UInt8>(255, 20, 147),      // Deep Pink
        "Skin": SIMD3<UInt8>(210, 180, 140),       // Tan
        "Fat": SIMD3<UInt8>(255, 255, 224),        // Light Yellow
        "Vessel": SIMD3<UInt8>(255, 0, 255),       // Magenta
        "Nerve": SIMD3<UInt8>(173, 216, 230),      // Light Blue
        "Tumor": SIMD3<UInt8>(255, 69, 0),         // Red Orange
        "Lesion": SIMD3<UInt8>(220, 20, 60),       // Crimson
        "Target": SIMD3<UInt8>(50, 205, 50),       // Lime Green
        "Organ": SIMD3<UInt8>(100, 149, 237),      // Cornflower Blue
        "Structure": SIMD3<UInt8>(147, 112, 219),  // Medium Purple
        "Region": SIMD3<UInt8>(255, 140, 0)        // Dark Orange
    ]
    
    /// Convert RGB 0-255 to normalized float RGB 0-1
    public static func normalizeColor(_ color: SIMD3<UInt8>) -> SIMD3<Float> {
        return SIMD3<Float>(
            Float(color.x) / 255.0,
            Float(color.y) / 255.0,
            Float(color.z) / 255.0
        )
    }
    
    /// Get color for ROI name (fuzzy matching)
    public static func getColorForROI(_ roiName: String) -> SIMD3<Float> {
        let lowercaseName = roiName.lowercased()
        
        // Try exact match first
        for (structureName, color) in standardColors {
            if lowercaseName.contains(structureName.lowercased()) {
                return normalizeColor(color)
            }
        }
        
        // Default fallback color (red)
        return SIMD3<Float>(1.0, 0.0, 0.0)
    }
    
    /// Generate distinct colors for multiple ROIs
    public static func generateDistinctColors(count: Int) -> [SIMD3<Float>] {
        var colors: [SIMD3<Float>] = []
        
        for i in 0..<count {
            let hue = Float(i) / Float(count)
            let color = hsvToRgb(h: hue, s: 1.0, v: 1.0)
            colors.append(color)
        }
        
        return colors
    }
    
    /// Convert HSV to RGB
    private static func hsvToRgb(h: Float, s: Float, v: Float) -> SIMD3<Float> {
        let c = v * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        
        var rgb: SIMD3<Float>
        
        if h < 1.0/6.0 {
            rgb = SIMD3<Float>(c, x, 0)
        } else if h < 2.0/6.0 {
            rgb = SIMD3<Float>(x, c, 0)
        } else if h < 3.0/6.0 {
            rgb = SIMD3<Float>(0, c, x)
        } else if h < 4.0/6.0 {
            rgb = SIMD3<Float>(0, x, c)
        } else if h < 5.0/6.0 {
            rgb = SIMD3<Float>(x, 0, c)
        } else {
            rgb = SIMD3<Float>(c, 0, x)
        }
        
        return rgb + SIMD3<Float>(repeating: m)
    }
}

// MARK: - RTStruct Validation

public struct RTStructValidator {
    
    /// Validate that a DICOM dataset is a proper RTStruct
    public static func validateRTStruct(_ dataset: DICOMDataset) -> (isValid: Bool, issues: [String]) {
        var issues: [String] = []
        
        // Check modality
        if let modality = dataset.getString(tag: .modality) {
            if modality != "RTSTRUCT" {
                issues.append("Invalid modality: \(modality), expected RTSTRUCT")
            }
        } else {
            issues.append("Missing modality tag")
        }
        
        // Check for required sequences
        if dataset.elements[.structureSetROISequence] == nil {
            issues.append("Missing Structure Set ROI Sequence")
        }
        
        if dataset.elements[.roiContourSequence] == nil {
            issues.append("Missing ROI Contour Sequence")
        }
        
        // Check for basic identification
        if dataset.getString(tag: .seriesInstanceUID) == nil {
            issues.append("Missing Series Instance UID")
        }
        
        if dataset.getString(tag: .studyInstanceUID) == nil {
            issues.append("Missing Study Instance UID")
        }
        
        let isValid = issues.isEmpty
        return (isValid, issues)
    }
    
    /// Quick check if dataset contains RTStruct data
    public static func isRTStruct(_ dataset: DICOMDataset) -> Bool {
        guard let modality = dataset.getString(tag: .modality) else { return false }
        return modality == "RTSTRUCT"
    }
}
