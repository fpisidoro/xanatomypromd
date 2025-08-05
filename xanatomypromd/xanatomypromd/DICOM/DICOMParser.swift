import Foundation

// MARK: - Core DICOM Parser
// Minimal Swift-native parser optimized for CT imaging
// Designed for educational use with fixed datasets

public struct DICOMParser {
    
    // MARK: - Public API
    
    /// Parse DICOM file from data
    public static func parse(_ data: Data) throws -> DICOMDataset {
        var parser = DICOMParser()
        return try parser.parseDataset(data)
    }
    
    /// Extract pixel data from parsed dataset
    public static func extractPixelData(from dataset: DICOMDataset) -> PixelData? {
        guard let pixelElement = dataset.elements[DICOMTag.pixelData] else {
            return nil
        }
        
        return PixelData(
            data: pixelElement.data,
            rows: Int(dataset.getUInt16(tag: .rows) ?? 0),
            columns: Int(dataset.getUInt16(tag: .columns) ?? 0),
            bitsAllocated: Int(dataset.getUInt16(tag: .bitsAllocated) ?? 16),
            bitsStored: Int(dataset.getUInt16(tag: .bitsStored) ?? 16),
            highBit: Int(dataset.getUInt16(tag: .highBit) ?? 15),
            pixelRepresentation: Int(dataset.getUInt16(tag: .pixelRepresentation) ?? 0)
        )
    }
    
    // MARK: - Private Implementation
    
    private var currentOffset: Int = 0
    
    private mutating func parseDataset(_ data: Data) throws -> DICOMDataset {
        currentOffset = 0
        
        // Validate DICOM file
        try validateDICOMHeader(data)
        
        // Skip preamble and prefix
        currentOffset = 132 // 128 byte preamble + 4 byte "DICM"
        
        var elements: [DICOMTag: DICOMElement] = [:]
        var transferSyntaxUID: String?
        
        // First pass: Parse file meta information (always explicit VR) to get transfer syntax
        while currentOffset < data.count {
            let element = try parseDataElement(data, explicitVR: true)
            elements[element.tag] = element
            
            // Capture transfer syntax
            if element.tag == DICOMTag.transferSyntaxUID {
                transferSyntaxUID = String(data: element.data, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Stop after file meta information group (0002)
            if element.tag.group != 0x0002 {
                // We need to rewind and parse this element with the correct VR
                currentOffset = currentOffset - Int(element.length + 8)
                elements.removeValue(forKey: element.tag)
                break
            }
        }
        
        // Determine if main dataset uses explicit or implicit VR based on transfer syntax
        let useExplicitVR: Bool
        if let transferSyntax = transferSyntaxUID {
            //print("🔍 Transfer Syntax: \(transferSyntax)")
            // Implicit VR Little Endian is the most common
            useExplicitVR = transferSyntax == TransferSyntax.explicitVRLittleEndian ||
                          transferSyntax == TransferSyntax.explicitVRBigEndian
        } else {
            print("⚠️  No transfer syntax found, assuming implicit VR")
            useExplicitVR = false
        }
        
       // print("📋 Using \(useExplicitVR ? "Explicit" : "Implicit") VR for main dataset")
        
        // Continue parsing main dataset with correct VR
        while currentOffset < data.count {
            let element = try parseDataElement(data, explicitVR: useExplicitVR)
            elements[element.tag] = element
        }
        
        return DICOMDataset(elements: elements, rawData: data)
    }
    
    private func validateDICOMHeader(_ data: Data) throws {
        guard data.count >= 132 else {
            throw DICOMError.invalidFileFormat
        }
        
        // Check DICM prefix at position 128
        let prefix = data.subdata(in: 128..<132)
        let dicmString = String(data: prefix, encoding: .ascii)
        
        guard dicmString == "DICM" else {
            throw DICOMError.invalidFileFormat
        }
    }
    
    private mutating func parseDataElement(_ data: Data, explicitVR: Bool) throws -> DICOMElement {
        guard currentOffset + 8 <= data.count else {
            throw DICOMError.unexpectedEndOfFile
        }
        
        // Read tag (group, element)
        let group = data.readUInt16(at: currentOffset, littleEndian: true)
        let element = data.readUInt16(at: currentOffset + 2, littleEndian: true)
        let tag = DICOMTag(group: group, element: element)
        
        currentOffset += 4
        
        let vr: String
        let length: UInt32
        
        if explicitVR {
            // Explicit VR: read VR then length
            guard currentOffset + 2 <= data.count else {
                throw DICOMError.unexpectedEndOfFile
            }
            
            let vrBytes = data.subdata(in: currentOffset..<currentOffset + 2)
            vr = String(data: vrBytes, encoding: .ascii) ?? "UN"
            currentOffset += 2
            
            // Read length based on VR type
            if ["OB", "OW", "OF", "SQ", "UT", "UN"].contains(vr) {
                // Extended length VRs: skip 2 reserved bytes, then read 4-byte length
                guard currentOffset + 6 <= data.count else {
                    throw DICOMError.unexpectedEndOfFile
                }
                currentOffset += 2  // Skip 2 reserved bytes
                length = data.readUInt32(at: currentOffset, littleEndian: true)
                currentOffset += 4
            } else {
                // Standard VRs: 2-byte length
                guard currentOffset + 2 <= data.count else {
                    throw DICOMError.unexpectedEndOfFile
                }
                length = UInt32(data.readUInt16(at: currentOffset, littleEndian: true))
                currentOffset += 2
            }
        } else {
            // Implicit VR: no VR field, 4-byte length
            guard currentOffset + 4 <= data.count else {
                throw DICOMError.unexpectedEndOfFile
            }
            
            vr = "UN"  // Unknown VR for implicit
            length = data.readUInt32(at: currentOffset, littleEndian: true)
            currentOffset += 4
        }
        
        // Validate length doesn't exceed remaining data
        let remainingData = data.count - currentOffset
        
        // Safety check for reasonable length values
        if length == 0xFFFFFFFF {
            // Undefined length - this is a sequence or item
            print("🔄 Found undefined length sequence at tag \(tag) - parsing sequence data...")
            
            // Parse undefined length sequence by finding the sequence delimiter
            let sequenceData = parseUndefinedLengthSequence(data, startOffset: currentOffset)
            currentOffset += sequenceData.totalBytesRead
            
            return DICOMElement(
                tag: tag,
                vr: vr,
                length: UInt32(sequenceData.data.count),
                data: sequenceData.data
            )
        }
        
        if length > 100_000_000 {  // 100MB seems unreasonable for a single element
            print("⚠️  DICOM Parse Error at tag \(tag): unreasonable length=\(length)")
            throw DICOMError.corruptedData
        }
        
        if Int(length) > remainingData {
            print("⚠️  DICOM Parse Error at tag \(tag): length=\(length), remaining=\(remainingData), offset=\(currentOffset)")
            throw DICOMError.corruptedData
        }
        
        // Read value data
        let valueData: Data
        if length > 0 {
            valueData = data.subdata(in: currentOffset..<currentOffset + Int(length))
        } else {
            valueData = Data()
        }
        currentOffset += Int(length)
        
        return DICOMElement(
            tag: tag,
            vr: vr,
            length: length,
            data: valueData
        )
    }
    
    // MARK: - Undefined Length Sequence Parsing
    
    /// Parse undefined length sequence data by finding sequence delimiter
    private func parseUndefinedLengthSequence(_ data: Data, startOffset: Int) -> (data: Data, totalBytesRead: Int) {
        var offset = startOffset
        let sequenceStart = offset
        
        print("   🔍 Parsing undefined length sequence starting at offset \(offset)...")
        
        // Search for sequence delimiter (FFFE,E0DD)
        while offset + 8 <= data.count {
            let group = data.readUInt16(at: offset, littleEndian: true)
            let element = data.readUInt16(at: offset + 2, littleEndian: true)
            
            if group == 0xFFFE && element == 0xE0DD {
                // Found sequence delimiter
                let sequenceLength = offset - sequenceStart
                print("   ✅ Found sequence delimiter at offset \(offset), sequence length: \(sequenceLength) bytes")
                
                let sequenceData = data.subdata(in: sequenceStart..<offset)
                let totalBytesRead = sequenceLength + 8 // Include delimiter
                
                return (data: sequenceData, totalBytesRead: totalBytesRead)
            }
            
            offset += 2 // Move forward to continue searching
        }
        
        // If no delimiter found, treat rest of data as sequence
        print("   ⚠️ No sequence delimiter found, using rest of data as sequence")
        let sequenceData = data.subdata(in: sequenceStart..<data.count)
        let totalBytesRead = data.count - sequenceStart
        
        return (data: sequenceData, totalBytesRead: totalBytesRead)
    }
}
