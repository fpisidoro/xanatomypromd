import Foundation

/// Represents a parsed DICOM dataset
public struct DICOMDataset {
    public let elements: [DICOMTag: DICOMElement]
    public let rawData: Data? // Store raw file data for deep scanning
    
    public init(elements: [DICOMTag: DICOMElement], rawData: Data? = nil) {
        self.elements = elements
        self.rawData = rawData
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

extension DICOMDataset {
    
    /// Get raw sequence data for undefined length sequences
    /// This bypasses the normal DICOM parser's sequence skipping
    public func getSequenceData(tag: DICOMTag, fromRawData data: Data) -> Data? {
        // Find the tag in the raw DICOM data and extract sequence content
        return findSequenceInRawData(tag: tag, data: data)
    }
    
    /// Find and extract undefined length sequence data from raw DICOM file
    private func findSequenceInRawData(tag: DICOMTag, data: Data) -> Data? {
        let targetGroup = tag.group
        let targetElement = tag.element
        
        var offset = 132 // Skip DICOM header
        
        // Search through the raw DICOM data for our target tag
        while offset + 8 <= data.count {
            let group = data.readUInt16(at: offset, littleEndian: true)
            let element = data.readUInt16(at: offset + 2, littleEndian: true)
            
            offset += 4
            
            // Check if this is our target sequence
            if group == targetGroup && element == targetElement {
                print("   🎯 Found target sequence tag (\(String(format: "%04X", group)),\(String(format: "%04X", element))) at offset \(offset - 4)")
                
                // Parse the sequence data
                return extractUndefinedLengthSequence(data: data, startOffset: offset)
            }
            
            // Skip this element to continue searching
            if let nextOffset = skipElement(data: data, currentOffset: offset) {
                offset = nextOffset
            } else {
                break
            }
        }
        
        print("   ❌ Could not find sequence tag (\(String(format: "%04X", targetGroup)),\(String(format: "%04X", targetElement))) in raw data")
        return nil
    }
    
    /// Extract undefined length sequence content
    private func extractUndefinedLengthSequence(data: Data, startOffset: Int) -> Data? {
        var offset = startOffset
        
        // Check if this is explicit or implicit VR
        let potentialVR = data.subdata(in: offset..<min(offset + 2, data.count))
        let vrString = String(data: potentialVR, encoding: .ascii) ?? ""
        
        let isExplicitVR = ["SQ"].contains(vrString)
        
        if isExplicitVR {
            // Explicit VR: VR (2) + Reserved (2) + Length (4)
            guard offset + 8 <= data.count else { return nil }
            offset += 8
        } else {
            // Implicit VR: Length (4)
            guard offset + 4 <= data.count else { return nil }
            let length = data.readUInt32(at: offset, littleEndian: true)
            offset += 4
            
            if length != 0xFFFFFFFF {
                // Defined length sequence
                guard offset + Int(length) <= data.count else { return nil }
                let sequenceData = data.subdata(in: offset..<offset + Int(length))
                print("   ✅ Extracted defined length sequence: \(sequenceData.count) bytes")
                return sequenceData
            }
        }
        
        // Undefined length sequence - find the sequence delimiter
        let sequenceStart = offset
        var nestingLevel = 0
        
        while offset + 8 <= data.count {
            let group = data.readUInt16(at: offset, littleEndian: true)
            let element = data.readUInt16(at: offset + 2, littleEndian: true)
            let length = data.readUInt32(at: offset + 4, littleEndian: true)
            
            offset += 8
            
            if group == 0xFFFE {
                if element == 0xE000 {
                    // Sequence item start
                    nestingLevel += 1
                } else if element == 0xE00D {
                    // Item delimiter
                    nestingLevel -= 1
                } else if element == 0xE0DD {
                    // Sequence delimiter
                    if nestingLevel == 0 {
                        // Found the end of our sequence
                        let sequenceData = data.subdata(in: sequenceStart..<offset - 8)
                        print("   ✅ Extracted undefined length sequence: \(sequenceData.count) bytes")
                        return sequenceData
                    }
                }
            }
            
            // Skip element data
            if length != 0xFFFFFFFF && length > 0 {
                offset += Int(length)
            }
        }
        
        print("   ⚠️ Could not find sequence delimiter for undefined length sequence")
        return nil
    }
    
    /// Skip an element in raw DICOM data
    private func skipElement(data: Data, currentOffset: Int) -> Int? {
        var offset = currentOffset
        
        // Try explicit VR first
        guard offset + 2 <= data.count else { return nil }
        let potentialVR = data.subdata(in: offset..<offset + 2)
        let vrString = String(data: potentialVR, encoding: .ascii) ?? ""
        
        let isValidVR = ["AE", "AS", "AT", "CS", "DA", "DS", "DT", "FL", "FD", "IS", "LO", "LT", "OB", "OF", "OW", "PN", "SH", "SL", "SS", "ST", "TM", "UI", "UL", "UN", "US", "UT", "SQ"].contains(vrString)
        
        if isValidVR {
            // Explicit VR
            offset += 2
            
            let length: UInt32
            if ["OB", "OW", "OF", "SQ", "UT", "UN"].contains(vrString) {
                // 4-byte length after 2 reserved bytes
                guard offset + 6 <= data.count else { return nil }
                offset += 2 // Skip reserved bytes
                length = data.readUInt32(at: offset, littleEndian: true)
                offset += 4
            } else {
                // 2-byte length
                guard offset + 2 <= data.count else { return nil }
                length = UInt32(data.readUInt16(at: offset, littleEndian: true))
                offset += 2
            }
            
            if length != 0xFFFFFFFF {
                offset += Int(length)
            }
        } else {
            // Implicit VR
            guard offset + 4 <= data.count else { return nil }
            let length = data.readUInt32(at: offset, littleEndian: true)
            offset += 4
            
            if length != 0xFFFFFFFF {
                offset += Int(length)
            }
        }
        
        return offset
    }
}

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
