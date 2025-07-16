import Foundation

// MARK: - DICOM Data Structures

/// Represents a parsed DICOM dataset
public struct DICOMDataset {
    public let elements: [DICOMTag: DICOMElement]
    
    public init(elements: [DICOMTag: DICOMElement]) {
        self.elements = elements
    }
    
    // MARK: - Convenience Accessors for Common CT Tags
    
    public func getString(tag: DICOMTag) -> String? {
        guard let element = elements[tag] else { return nil }
        return String(data: element.data, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public func getUInt16(tag: DICOMTag) -> UInt16? {
        guard let element = elements[tag], element.data.count >= 2 else { return nil }
        return element.data.readUInt16(at: 0)
    }
    
    public func getUInt32(tag: DICOMTag) -> UInt32? {
        guard let element = elements[tag], element.data.count >= 4 else { return nil }
        return element.data.readUInt32(at: 0)
    }
    
    public func getDouble(tag: DICOMTag) -> Double? {
        guard let string = getString(tag: tag) else { return nil }
        return Double(string)
    }
    
    // MARK: - CT-Specific Convenience Methods
    
    public var patientName: String? { getString(tag: .patientName) }
    public var studyDate: String? { getString(tag: .studyDate) }
    public var rows: UInt16? { getUInt16(tag: .rows) }
    public var columns: UInt16? { getUInt16(tag: .columns) }
    public var windowCenter: Double? { getDouble(tag: .windowCenter) }
    public var windowWidth: Double? { getDouble(tag: .windowWidth) }
    public var pixelSpacing: String? { getString(tag: .pixelSpacing) }
    public var sliceThickness: Double? { getDouble(tag: .sliceThickness) }
    public var imagePosition: String? { getString(tag: .imagePositionPatient) }
    public var imageOrientation: String? { getString(tag: .imageOrientationPatient) }
}

/// Represents a single DICOM data element
public struct DICOMElement {
    public let tag: DICOMTag
    public let vr: String  // Value Representation
    public let length: UInt32
    public let data: Data
    
    public init(tag: DICOMTag, vr: String, length: UInt32, data: Data) {
        self.tag = tag
        self.vr = vr
        self.length = length
        self.data = data
    }
}

/// Represents extracted pixel data ready for rendering
public struct PixelData {
    public let data: Data
    public let rows: Int
    public let columns: Int
    public let bitsAllocated: Int
    public let bitsStored: Int
    public let highBit: Int
    public let pixelRepresentation: Int  // 0 = unsigned, 1 = signed
    
    public init(data: Data, rows: Int, columns: Int, bitsAllocated: Int, bitsStored: Int, highBit: Int, pixelRepresentation: Int) {
        self.data = data
        self.rows = rows
        self.columns = columns
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        self.highBit = highBit
        self.pixelRepresentation = pixelRepresentation
    }
    
    /// Convert pixel data to UInt16 array for CT processing
    public func toUInt16Array() -> [UInt16] {
        let pixelCount = rows * columns
        var pixels: [UInt16] = []
        pixels.reserveCapacity(pixelCount)
        
        if bitsAllocated == 16 {
            // 16-bit data - manual byte assembly
            var i = 0
            while i < data.count - 1 {
                let byte1: UInt8 = data[i]
                let byte2: UInt8 = data[i + 1]
                let pixelValue: UInt16 = UInt16(byte1) | (UInt16(byte2) << 8)  // Little endian
                pixels.append(pixelValue)
                i += 2
            }
        } else if bitsAllocated == 8 {
            // 8-bit data, convert to 16-bit
            for byte in data {
                let pixel: UInt16 = UInt16(byte)
                pixels.append(pixel)
            }
        }
        
        return pixels
    }
    
    /// Convert to signed Int16 array if pixel representation is signed
    public func toInt16Array() -> [Int16] {
        let uint16Array = toUInt16Array()
        
        if pixelRepresentation == 1 {
            // Signed data
            return uint16Array.map { Int16(bitPattern: $0) }
        } else {
            // Unsigned data, convert to signed range
            return uint16Array.map { value in
                Int16(min(value, UInt16(Int16.max)))
            }
        }
    }
}

// MARK: - Error Types

public enum DICOMError: Error, LocalizedError {
    case invalidFileFormat
    case missingPixelData
    case unsupportedTransferSyntax
    case unexpectedEndOfFile
    case corruptedData
    
    public var errorDescription: String? {
        switch self {
        case .invalidFileFormat:
            return "Invalid DICOM file format"
        case .missingPixelData:
            return "Pixel data not found in DICOM file"
        case .unsupportedTransferSyntax:
            return "Unsupported transfer syntax"
        case .unexpectedEndOfFile:
            return "Unexpected end of file while parsing"
        case .corruptedData:
            return "Corrupted DICOM data"
        }
    }
}
