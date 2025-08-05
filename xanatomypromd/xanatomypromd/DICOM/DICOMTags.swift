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
    public static let structureSetName = DICOMTag(group: 0x3006, element: 0x0002)
    public static let structureSetROISequence = DICOMTag(group: 0x3006, element: 0x0020)
    public static let roiContourSequence = DICOMTag(group: 0x3006, element: 0x0039)
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

// MARK: - CT Window Presets

public struct CTWindowLevel {
    public let name: String
    public let center: Float
    public let width: Float
    
    public init(name: String, center: Float, width: Float) {
        self.name = name
        self.center = center
        self.width = width
    }
    
    // Standard CT presets
    public static let bone = CTWindowLevel(name: "Bone", center: 500, width: 2000)
    public static let lung = CTWindowLevel(name: "Lung", center: -600, width: 1600)
    public static let softTissue = CTWindowLevel(name: "Soft Tissue", center: 50, width: 350)
    
    public static let allPresets = [softTissue, bone, lung]
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
