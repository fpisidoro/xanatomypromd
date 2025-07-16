import Foundation

// MARK: - DICOM Debug Helper
// Analyzes raw DICOM file structure to understand parsing issues

class DICOMDebugHelper {
    
    static func analyzeDICOMFile(_ fileURL: URL) {
        print("🔬 DETAILED DICOM ANALYSIS: \(fileURL.lastPathComponent)")
        
        do {
            let data = try Data(contentsOf: fileURL)
            print("   📊 Total file size: \(data.count) bytes")
            
            // Check basic DICOM structure
            analyzeHeader(data)
            analyzeFirstElements(data)
            findPixelData(data)
            
        } catch {
            print("   ❌ Could not read file: \(error)")
        }
        
        print("")
    }
    
    private static func analyzeHeader(_ data: Data) {
        print("   🔍 HEADER ANALYSIS:")
        
        guard data.count >= 132 else {
            print("      ❌ File too small for DICOM header (\(data.count) bytes)")
            return
        }
        
        // Check preamble (should be 128 zeros, but could be anything)
        let preamble = data.subdata(in: 0..<128)
        let isZeroPreamble = preamble.allSatisfy { $0 == 0 }
        print("      📝 Preamble (128 bytes): \(isZeroPreamble ? "All zeros" : "Contains data")")
        
        // Check DICM prefix
        let prefix = data.subdata(in: 128..<132)
        let prefixString = String(data: prefix, encoding: .ascii) ?? "NON-ASCII"
        print("      🏷️  DICM prefix: '\(prefixString)'")
        
        if prefixString == "DICM" {
            print("      ✅ Valid DICOM file signature")
        } else {
            print("      ❌ Invalid DICOM signature - expected 'DICM'")
            
            // Check if DICM appears elsewhere (sometimes at beginning)
            if let dicmRange = data.range(of: "DICM".data(using: .ascii)!) {
                print("      💡 Found 'DICM' at offset \(dicmRange.lowerBound)")
            }
        }
    }
    
    private static func analyzeFirstElements(_ data: Data) {
        print("   🔍 FIRST ELEMENTS ANALYSIS:")
        
        var offset = 132  // Skip preamble and DICM
        
        guard offset < data.count else {
            print("      ❌ No data after header")
            return
        }
        
        // Try to parse first few elements to understand transfer syntax
        for i in 0..<5 {
            guard offset + 8 < data.count else {
                print("      ⚠️  Reached end of data at element \(i)")
                break
            }
            
            let group = data.readUInt16(at: offset, littleEndian: true)
            let element = data.readUInt16(at: offset + 2, littleEndian: true)
            
            print("      Element \(i): (\(String(format: "%04X", group)),\(String(format: "%04X", element)))")
            
            // Try to read VR
            let vrBytes = data.subdata(in: offset + 4..<offset + 6)
            let vr = String(data: vrBytes, encoding: .ascii) ?? "??"
            print("         Potential VR: '\(vr)'")
            
            // Check if this looks like explicit VR
            let isValidVR = ["AE", "AS", "AT", "CS", "DA", "DS", "DT", "FL", "FD", "IS", "LO", "LT", "OB", "OF", "OW", "PN", "SH", "SL", "SS", "ST", "TM", "UI", "UL", "UN", "US", "UT"].contains(vr)
            print("         Valid VR: \(isValidVR ? "✅" : "❌")")
            
            if isValidVR {
                // Try explicit VR parsing
                let length: UInt32
                if ["OB", "OW", "OF", "SQ", "UT", "UN"].contains(vr) {
                    // 4-byte length after 2 reserved bytes
                    guard offset + 12 < data.count else { break }
                    length = data.readUInt32(at: offset + 8, littleEndian: true)
                    offset += 12
                } else {
                    // 2-byte length
                    guard offset + 8 < data.count else { break }
                    length = UInt32(data.readUInt16(at: offset + 6, littleEndian: true))
                    offset += 8
                }
                print("         Length: \(length)")
                offset += Int(length)
            } else {
                // Try implicit VR parsing
                guard offset + 8 < data.count else { break }
                let length = data.readUInt32(at: offset + 4, littleEndian: true)
                print("         Implicit VR length: \(length)")
                offset += 8 + Int(length)
            }
            
            if offset >= data.count {
                print("      ⚠️  Parsing went past end of file")
                break
            }
        }
    }
    
    private static func findPixelData(_ data: Data) {
        print("   🔍 PIXEL DATA SEARCH:")
        
        // Search for pixel data tag (7FE0,0010)
        let pixelDataPattern: [UInt8] = [0xE0, 0x7F, 0x10, 0x00]  // Little endian
        
        var searchOffset = 0
        var foundCount = 0
        
        while searchOffset < data.count - 4 && foundCount < 3 {
            if let range = data.range(of: Data(pixelDataPattern), in: searchOffset..<data.count) {
                let offset = range.lowerBound
                print("      Found pixel data tag at offset: \(offset)")
                
                // Try to read what follows
                if offset + 8 < data.count {
                    let vr1 = data[offset + 4]
                    let vr2 = data[offset + 5]
                    let vrString = String(format: "%c%c", vr1, vr2)
                    print("         Following bytes (potential VR): '\(vrString)'")
                    
                    if offset + 12 < data.count {
                        let length = data.readUInt32(at: offset + 8, littleEndian: true)
                        print("         Potential length: \(length)")
                    }
                }
                
                searchOffset = offset + 4
                foundCount += 1
            } else {
                break
            }
        }
        
        if foundCount == 0 {
            print("      ❌ No pixel data tag found")
        }
    }
}

// MARK: - Quick Debug Function

extension DICOMTestManager {
    
    /// Debug a specific DICOM file structure
    static func debugFirstFile() {
        print("\n🔬 DEBUGGING FIRST DICOM FILE\n")
        
        let dicomFiles = getDICOMFiles()
        guard let firstFile = dicomFiles.first else {
            print("❌ No DICOM files found")
            return
        }
        
        DICOMDebugHelper.analyzeDICOMFile(firstFile)
    }
}