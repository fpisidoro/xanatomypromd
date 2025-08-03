import Foundation

// MARK: - CT Window Presets for Medical Imaging
// Standard CT windowing presets for different tissue types

public struct CTWindowPresets {
    
    // MARK: - Window Level Structure
    
    public struct WindowLevel: Hashable, Identifiable {
        public let id = UUID()
        public let name: String
        public let center: Float
        public let width: Float
        public let description: String
        
        public init(name: String, center: Float, width: Float, description: String = "") {
            self.name = name
            self.center = center
            self.width = width
            self.description = description
        }
    }
    
    // MARK: - Standard CT Window Presets
    
    /// Bone Window - High contrast for bone structures
    public static let bone = WindowLevel(
        name: "Bone",
        center: 500,
        width: 2000,
        description: "Optimized for bone and high-density structures"
    )
    
    /// Lung Window - Optimized for lung parenchyma
    public static let lung = WindowLevel(
        name: "Lung",
        center: -600,
        width: 1600,
        description: "Optimized for lung tissue and air-filled structures"
    )
    
    /// Soft Tissue Window - Standard for most anatomical structures
    public static let softTissue = WindowLevel(
        name: "Soft Tissue",
        center: 50,
        width: 350,
        description: "Optimized for soft tissue contrast"
    )
    
    /// Brain Window - Optimized for brain tissue
    public static let brain = WindowLevel(
        name: "Brain",
        center: 40,
        width: 80,
        description: "Optimized for brain tissue contrast"
    )
    
    /// Liver Window - Optimized for liver and abdominal organs
    public static let liver = WindowLevel(
        name: "Liver",
        center: 60,
        width: 160,
        description: "Optimized for liver and abdominal organs"
    )
    
    /// Mediastinum Window - For chest structures
    public static let mediastinum = WindowLevel(
        name: "Mediastinum",
        center: 50,
        width: 400,
        description: "Optimized for mediastinal structures"
    )
    
    /// Spine Window - For spinal structures
    public static let spine = WindowLevel(
        name: "Spine",
        center: 250,
        width: 1000,
        description: "Optimized for spinal bone and soft tissue"
    )
    
    // MARK: - Preset Collections
    
    /// All available window presets
    public static let allPresets: [WindowLevel] = [
        .softTissue,
        .bone,
        .lung,
        .brain,
        .liver,
        .mediastinum,
        .spine
    ]
    
    /// Common presets for general use
    public static let commonPresets: [WindowLevel] = [
        .softTissue,
        .bone,
        .lung
    ]
    
    /// All presets (alias for backward compatibility)
    public static let all: [WindowLevel] = allPresets
}

// MARK: - Preset Lookup Functions

extension CTWindowPresets {
    
    /// Find preset by name (case-insensitive)
    public static func preset(named name: String) -> WindowLevel? {
        return allPresets.first { $0.name.lowercased() == name.lowercased() }
    }
    
    /// Get preset for specific anatomical region
    public static func presetForRegion(_ region: AnatomicalRegion) -> WindowLevel {
        switch region {
        case .head, .brain:
            return .brain
        case .chest, .lung:
            return .lung
        case .abdomen, .liver:
            return .liver
        case .spine:
            return .spine
        case .bone:
            return .bone
        case .general:
            return .softTissue
        }
    }
}

// MARK: - Anatomical Regions

public enum AnatomicalRegion: String, CaseIterable {
    case head = "Head"
    case brain = "Brain"
    case chest = "Chest"
    case lung = "Lung"
    case abdomen = "Abdomen"
    case liver = "Liver"
    case spine = "Spine"
    case bone = "Bone"
    case general = "General"
}

// MARK: - Windowing Calculations

extension CTWindowPresets.WindowLevel {
    
    /// Calculate minimum HU value for this window
    public var minHU: Float {
        return center - (width / 2.0)
    }
    
    /// Calculate maximum HU value for this window
    public var maxHU: Float {
        return center + (width / 2.0)
    }
    
    /// Convert HU value to normalized 0-1 range for this window
    public func normalizeHU(_ hounsfield: Float) -> Float {
        let normalized = (hounsfield - minHU) / width
        return max(0.0, min(1.0, normalized))
    }
    
    /// Apply windowing to a HU value, returning 0-1 range
    public func applyWindowing(to hounsfield: Float) -> Float {
        return normalizeHU(hounsfield)
    }
}

// MARK: - Custom Window Creation

extension CTWindowPresets {
    
    /// Create custom window preset
    public static func custom(
        name: String,
        center: Float,
        width: Float,
        description: String = "Custom window"
    ) -> WindowLevel {
        return WindowLevel(
            name: name,
            center: center,
            width: width,
            description: description
        )
    }
    
    /// Create window optimized for specific HU range
    public static func forHURange(
        name: String,
        minHU: Float,
        maxHU: Float,
        description: String = "Custom HU range"
    ) -> WindowLevel {
        let center = (minHU + maxHU) / 2.0
        let width = maxHU - minHU
        
        return WindowLevel(
            name: name,
            center: center,
            width: width,
            description: description
        )
    }
}

// MARK: - Debugging and Display

extension CTWindowPresets.WindowLevel: CustomStringConvertible {
    public var description: String {
        return "\(name): C:\(Int(center)) W:\(Int(width))"
    }
}

extension CTWindowPresets.WindowLevel {
    /// Formatted string for UI display
    public var displayString: String {
        return "C:\(Int(center)) W:\(Int(width))"
    }
    
    /// Detailed info for debugging
    public var detailedInfo: String {
        return """
        \(name) Window:
          Center: \(center) HU
          Width: \(width) HU
          Range: \(Int(minHU)) to \(Int(maxHU)) HU
          Description: \(description)
        """
    }
}
