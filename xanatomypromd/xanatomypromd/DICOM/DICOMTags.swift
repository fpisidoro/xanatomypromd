import Foundation

// MARK: - DICOM Tag Definitions

/// Represents a DICOM tag (group, element)
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
}

// MARK: - Standard DICOM Tags for CT Imaging

extension DICOMTag {
    
    // MARK: - Patient Information
    public static let patientName = DICOMTag(group: 0x0010, element: 0x0010)
    public static let patientID = DICOMTag(group: 0x0010, element: 0x0020)
    public static let patientBirthDate = DICOMTag(group: 0x0010, element: 0x0030)
    public static let patientSex = DICOMTag(group: 0x0010, element: 0x0040)
    
    // MARK: - Study Information
    public static let studyInstanceUID = DICOMTag(group: 0x0020, element: 0x000D)
    public static let studyDate = DICOMTag(group: 0x0008, element: 0x0020)
    public static let studyTime = DICOMTag(group: 0x0008, element: 0x0030)
    public static let studyDescription = DICOMTag(group: 0x0008, element: 0x1030)
    public static let accessionNumber = DICOMTag(group: 0x0008, element: 0x0050)
    
    // MARK: - Series Information
    public static let seriesInstanceUID = DICOMTag(group: 0x0020, element: 0x000E)
    public static let seriesNumber = DICOMTag(group: 0x0020, element: 0x0011)
    public static let seriesDate = DICOMTag(group: 0x0008, element: 0x0021)
    public static let seriesTime = DICOMTag(group: 0x0008, element: 0x0031)
    public static let seriesDescription = DICOMTag(group: 0x0008, element: 0x103E)
    public static let modality = DICOMTag(group: 0x0008, element: 0x0060)
    
    // MARK: - Instance Information
    public static let sopInstanceUID = DICOMTag(group: 0x0008, element: 0x0018)
    public static let instanceNumber = DICOMTag(group: 0x0020, element: 0x0013)
    public static let acquisitionNumber = DICOMTag(group: 0x0020, element: 0x0012)
    
    // MARK: - Image Dimensions
    public static let rows = DICOMTag(group: 0x0028, element: 0x0010)
    public static let columns = DICOMTag(group: 0x0028, element: 0x0011)
    public static let numberOfFrames = DICOMTag(group: 0x0028, element: 0x0008)
    
    // MARK: - Pixel Data Properties
    public static let bitsAllocated = DICOMTag(group: 0x0028, element: 0x0100)
    public static let bitsStored = DICOMTag(group: 0x0028, element: 0x0101)
    public static let highBit = DICOMTag(group: 0x0028, element: 0x0102)
    public static let pixelRepresentation = DICOMTag(group: 0x0028, element: 0x0103)
    public static let samplesPerPixel = DICOMTag(group: 0x0028, element: 0x0002)
    public static let photometricInterpretation = DICOMTag(group: 0x0028, element: 0x0004)
    
    // MARK: - CT-Specific Tags
    public static let windowCenter = DICOMTag(group: 0x0028, element: 0x1050)
    public static let windowWidth = DICOMTag(group: 0x0028, element: 0x1051)
    public static let rescaleIntercept = DICOMTag(group: 0x0028, element: 0x1052)
    public static let rescaleSlope = DICOMTag(group: 0x0028, element: 0x1053)
    public static let kvp = DICOMTag(group: 0x0018, element: 0x0060)
    public static let exposureTime = DICOMTag(group: 0x0018, element: 0x1150)
    public static let xRayTubeCurrent = DICOMTag(group: 0x0018, element: 0x1151)
    
    // MARK: - Spatial Information
    public static let pixelSpacing = DICOMTag(group: 0x0028, element: 0x0030)
    public static let sliceThickness = DICOMTag(group: 0x0018, element: 0x0050)
    public static let sliceLocation = DICOMTag(group: 0x0020, element: 0x1041)
    public static let imagePositionPatient = DICOMTag(group: 0x0020, element: 0x0032)
    public static let imageOrientationPatient = DICOMTag(group: 0x0020, element: 0x0037)
    
    // MARK: - Transfer Syntax and Encoding
    public static let transferSyntaxUID = DICOMTag(group: 0x0002, element: 0x0010)
    public static let implementationClassUID = DICOMTag(group: 0x0002, element: 0x0012)
    public static let implementationVersionName = DICOMTag(group: 0x0002, element: 0x0013)
    
    // MARK: - Pixel Data
    public static let pixelData = DICOMTag(group: 0x7FE0, element: 0x0010)
}

// MARK: - Tag Categories for Organization

extension DICOMTag {
    
    /// Essential tags for basic DICOM parsing
    public static let essential: Set<DICOMTag> = [
        .rows, .columns, .bitsAllocated, .bitsStored, .highBit,
        .pixelRepresentation, .pixelData, .transferSyntaxUID
    ]
    
    /// Tags specifically important for CT imaging
    public static let ctImaging: Set<DICOMTag> = [
        .windowCenter, .windowWidth, .rescaleIntercept, .rescaleSlope,
        .sliceThickness, .pixelSpacing, .kvp
    ]
    
    /// Tags for spatial reconstruction (MPR)
    public static let spatial: Set<DICOMTag> = [
        .imagePositionPatient, .imageOrientationPatient,
        .pixelSpacing, .sliceThickness, .sliceLocation
    ]
    
    /// Patient and study identification tags
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

     
     // Update the all array:
     public static let all: [WindowLevel] = [bone, lung, softTissue, brain, liver]
    
   // public static let all: [WindowLevel] = [bone, lung, softTissue, brain, liver]
}
