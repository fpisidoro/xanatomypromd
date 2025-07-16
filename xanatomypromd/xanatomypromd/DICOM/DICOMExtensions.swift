import Foundation

// MARK: - Data Reading Extensions
// Safe extensions for DICOM binary data processing (handles unaligned data)

extension Data {
    func readUInt16(at offset: Int, littleEndian: Bool = true) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        
        let byte0 = UInt16(self[offset])
        let byte1 = UInt16(self[offset + 1])
        
        if littleEndian {
            return byte0 | (byte1 << 8)
        } else {
            return (byte0 << 8) | byte1
        }
    }
    
    func readUInt32(at offset: Int, littleEndian: Bool = true) -> UInt32 {
        guard offset + 3 < count else { return 0 }
        
        let byte0 = UInt32(self[offset])
        let byte1 = UInt32(self[offset + 1])
        let byte2 = UInt32(self[offset + 2])
        let byte3 = UInt32(self[offset + 3])
        
        if littleEndian {
            return byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24)
        } else {
            return (byte0 << 24) | (byte1 << 16) | (byte2 << 8) | byte3
        }
    }
    
    func readInt16(at offset: Int, littleEndian: Bool = true) -> Int16 {
        let unsignedValue = readUInt16(at: offset, littleEndian: littleEndian)
        return Int16(bitPattern: unsignedValue)
    }
    
    func readInt32(at offset: Int, littleEndian: Bool = true) -> Int32 {
        let unsignedValue = readUInt32(at: offset, littleEndian: littleEndian)
        return Int32(bitPattern: unsignedValue)
    }
    
    func readFloat32(at offset: Int, littleEndian: Bool = true) -> Float32 {
        let bits = readUInt32(at: offset, littleEndian: littleEndian)
        return Float32(bitPattern: bits)
    }
    
    func readFloat64(at offset: Int, littleEndian: Bool = true) -> Float64 {
        guard offset + 7 < count else { return 0.0 }
        
        let byte0 = UInt64(self[offset])
        let byte1 = UInt64(self[offset + 1])
        let byte2 = UInt64(self[offset + 2])
        let byte3 = UInt64(self[offset + 3])
        let byte4 = UInt64(self[offset + 4])
        let byte5 = UInt64(self[offset + 5])
        let byte6 = UInt64(self[offset + 6])
        let byte7 = UInt64(self[offset + 7])
        
        let bits: UInt64
        if littleEndian {
            bits = byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24) |
                   (byte4 << 32) | (byte5 << 40) | (byte6 << 48) | (byte7 << 56)
        } else {
            bits = (byte0 << 56) | (byte1 << 48) | (byte2 << 40) | (byte3 << 32) |
                   (byte4 << 24) | (byte5 << 16) | (byte6 << 8) | byte7
        }
        
        return Float64(bitPattern: bits)
    }
}
