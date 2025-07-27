import Foundation

// MARK: - DICOM Tag Structure

public struct DICOMTag: Hashable, CustomStringConvertible {
    public let group: UInt16
    public let element: UInt16
    
    public init(group: UInt16, element: UInt16) {
        self.group = group
        self.element = element
    }
    
    public var description: String {
        return String(format: "(%04X,%04X)", group, element)
    }
    
    public var hexString: String {
        return String(format: "%04X%04X", group, element)
    }
}

// MARK: - Standard DICOM Tags

extension DICOMTag {
    // Patient Information
    public static let patientName = DICOMTag(group: 0x0010, element: 0x0010)
    public static let patientID = DICOMTag(group: 0x0010, element: 0x0020)
    public static let patientBirthDate = DICOMTag(group: 0x0010, element: 0x0030)
    public static let patientSex = DICOMTag(group: 0x0010, element: 0x0040)
    
    // Study Information
    public static let studyInstanceUID = DICOMTag(group: 0x0020, element: 0x000D)
    public static let studyDate = DICOMTag(group: 0x0008, element: 0x0020)
    public static let studyTime = DICOMTag(group: 0x0008, element: 0x0030)
    public static let studyDescription = DICOMTag(group: 0x0008, element: 0x1030)
    public static let studyID = DICOMTag(group: 0x0020, element: 0x0010)
    
    // Series Information
    public static let seriesInstanceUID = DICOMTag(group: 0x0020, element: 0x000E)
    public static let seriesNumber = DICOMTag(group: 0x0020, element: 0x0011)
    public static let seriesDescription = DICOMTag(group: 0x0008, element: 0x103E)
    public static let modality = DICOMTag(group: 0x0008, element: 0x0060)
    
    // Instance Information
    public static let sopInstanceUID = DICOMTag(group: 0x0008, element: 0x0018)
    public static let sopClassUID = DICOMTag(group: 0x0008, element: 0x0016)
    public static let instanceNumber = DICOMTag(group: 0x0020, element: 0x0013)
    
    // Image Information
    public static let imagePositionPatient = DICOMTag(group: 0x0020, element: 0x0032)
    public static let imageOrientationPatient = DICOMTag(group: 0x0020, element: 0x0037)
    public static let pixelSpacing = DICOMTag(group: 0x0028, element: 0x0030)
    public static let sliceThickness = DICOMTag(group: 0x0018, element: 0x0050)
    public static let sliceLocation = DICOMTag(group: 0x0020, element: 0x1041)
    
    // Pixel Data
    public static let pixelData = DICOMTag(group: 0x7FE0, element: 0x0010)
    public static let rows = DICOMTag(group: 0x0028, element: 0x0010)
    public static let columns = DICOMTag(group: 0x0028, element: 0x0011)
    public static let bitsAllocated = DICOMTag(group: 0x0028, element: 0x0100)
    public static let bitsStored = DICOMTag(group: 0x0028, element: 0x0101)
    public static let highBit = DICOMTag(group: 0x0028, element: 0x0102)
    public static let pixelRepresentation = DICOMTag(group: 0x0028, element: 0x0103)
    public static let photometricInterpretation = DICOMTag(group: 0x0028, element: 0x0004)
    public static let samplesPerPixel = DICOMTag(group: 0x0028, element: 0x0002)
    
    // Transfer Syntax and Encoding
    public static let transferSyntaxUID = DICOMTag(group: 0x0002, element: 0x0010)
    public static let implementationClassUID = DICOMTag(group: 0x0002, element: 0x0012)
    public static let implementationVersionName = DICOMTag(group: 0x0002, element: 0x0013)
    
    // CT-Specific Tags
    public static let rescaleIntercept = DICOMTag(group: 0x0028, element: 0x1052)
    public static let rescaleSlope = DICOMTag(group: 0x0028, element: 0x1053)
    public static let windowCenter = DICOMTag(group: 0x0028, element: 0x1050)
    public static let windowWidth = DICOMTag(group: 0x0028, element: 0x1051)
    
    // Frame of Reference
    public static let frameOfReferenceUID = DICOMTag(group: 0x0020, element: 0x0052)
    
    // RTStruct-Specific Tags
    public static let structureSetLabel = DICOMTag(group: 0x3006, element: 0x0002)
    public static let structureSetName = DICOMTag(group: 0x3006, element: 0x0004)
    public static let structureSetDescription = DICOMTag(group: 0x3006, element: 0x0006)
    public static let structureSetDate = DICOMTag(group: 0x3006, element: 0x0008)
    public static let structureSetTime = DICOMTag(group: 0x3006, element: 0x0009)
    
    // Structure Set ROI Sequence
    public static let structureSetROISequence = DICOMTag(group: 0x3006, element: 0x0020)
    public static let roiNumber = DICOMTag(group: 0x3006, element: 0x0022)
    public static let roiName = DICOMTag(group: 0x3006, element: 0x0026)
    public static let roiDescription = DICOMTag(group: 0x3006, element: 0x0028)
    public static let roiGenerationAlgorithm = DICOMTag(group: 0x3006, element: 0x0036)
    
    // ROI Contour Sequence
    public static let roiContourSequence = DICOMTag(group: 0x3006, element: 0x0039)
    public static let contourSequence = DICOMTag(group: 0x3006, element: 0x0040)
    public static let contourGeometricType = DICOMTag(group: 0x3006, element: 0x0042)
    public static let numberOfContourPoints = DICOMTag(group: 0x3006, element: 0x0046)
    public static let contourData = DICOMTag(group: 0x3006, element: 0x0050)
    public static let referencedROINumber = DICOMTag(group: 0x3006, element: 0x0084)
    public static let roiDisplayColor = DICOMTag(group: 0x3006, element: 0x002A)
    
    // RT ROI Observations Sequence
    public static let rtROIObservationsSequence = DICOMTag(group: 0x3006, element: 0x0080)
    public static let observationNumber = DICOMTag(group: 0x3006, element: 0x0082)
    public static let referencedROINumber2 = DICOMTag(group: 0x3006, element: 0x0084)
    public static let roiObservationLabel = DICOMTag(group: 0x3006, element: 0x0085)
    public static let rtROIInterpretedType = DICOMTag(group: 0x3006, element: 0x00A4)
    public static let roiInterpreter = DICOMTag(group: 0x3006, element: 0x00A6)
    
    // Referenced SOP Instance
    public static let referencedSOPInstanceUID = DICOMTag(group: 0x0008, element: 0x1155)
    public static let referencedSOPClassUID = DICOMTag(group: 0x0008, element: 0x1150)
}

// MARK: - Tag Groups for Filtering

extension DICOMTag {
    /// Patient identification tags
    public static let patientInfo: Set<DICOMTag> = [
        .patientName, .patientID, .patientBirthDate, .patientSex
    ]
    
    /// Study identification tags
    public static let studyInfo: Set<DICOMTag> = [
        .studyInstanceUID, .studyDate, .studyTime, .studyDescription, .studyID
    ]
    
    /// Series identification tags
    public static let seriesInfo: Set<DICOMTag> = [
        .seriesInstanceUID, .seriesNumber, .seriesDescription, .modality
    ]
    
    /// Image geometry tags
    public static let imageGeometry: Set<DICOMTag> = [
        .imagePositionPatient, .imageOrientationPatient, .pixelSpacing, .sliceThickness
    ]
    
    /// Pixel data related tags
    public static let pixelInfo: Set<DICOMTag> = [
        .pixelData, .rows, .columns, .bitsAllocated, .bitsStored, .highBit,
        .pixelRepresentation, .photometricInterpretation, .samplesPerPixel
    ]
    
    /// Essential study identification tags
    public static let identification: Set<DICOMTag> = [
        .patientName, .patientID, .studyInstanceUID, .seriesInstanceUID,
        .sopInstanceUID, .studyDate, .seriesNumber, .instanceNumber
    ]
}

// MARK: - Common Transfer Syntax UIDs

public struct TransferSyntax {
    public static let implicitVRLittleEndian = "1.2.840.10008.1.2"
    public static let explicitVRLittleEndian = "1.2.840.10008.1.2.1"
    public static let explicitVRBigEndian = "1.2.840.10008.1.2.2"
    public static let jpegBaseline = "1.2.840.10008.1.2.4.50"
    public static let jpegLossless = "1.2.840.10008.1.2.4.70"
    public static let rle = "1.2.840.10008.1.2.5"
}

// MARK: - Standard CT Window Presets

public struct CTWindowPresets {
    public struct WindowLevel {
        public let center: Double
        public let width: Double
        public let name: String
        
        public init(center: Double, width: Double, name: String) {
            self.center = center
            self.width = width
            self.name = name
        }
    }
    
    public static let bone = WindowLevel(center: 400, width: 1500, name: "Bone")
    public static let lung = WindowLevel(center: -500, width: 1500, name: "Lung")
    public static let softTissue = WindowLevel(center: 40, width: 350, name: "Soft Tissue")
    public static let brain = WindowLevel(center: 35, width: 80, name: "Brain")
    public static let liver = WindowLevel(center: 60, width: 160, name: "Liver")
    
    public static let all: [WindowLevel] = [bone, lung, softTissue, brain, liver]
}

// MARK: - FIXED: Make WindowLevel Hashable and Equatable

extension CTWindowPresets.WindowLevel: Hashable, Equatable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(center)
        hasher.combine(width)
        hasher.combine(name)
    }
    
    public static func == (lhs: CTWindowPresets.WindowLevel, rhs: CTWindowPresets.WindowLevel) -> Bool {
        return lhs.center == rhs.center && lhs.width == rhs.width && lhs.name == rhs.name
    }
}

// MARK: - FIXED: Add missing DICOMDataset extension

extension DICOMDataset {
    public func getImagePosition() -> SIMD3<Double>? {
        guard let positionString = getString(tag: DICOMTag.imagePositionPatient) else {
            return nil
        }
        
        let components = positionString.components(separatedBy: "\\")
        guard components.count >= 3,
              let x = Double(components[0]),
              let y = Double(components[1]),
              let z = Double(components[2]) else {
            return nil
        }
        
        return SIMD3<Double>(x, y, z)
    }
}
