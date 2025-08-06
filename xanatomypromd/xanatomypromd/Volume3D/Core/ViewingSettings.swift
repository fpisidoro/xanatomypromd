import Foundation
import simd

// MARK: - CT Window Level Presets
// Standard medical imaging window/level settings for different tissue types

public struct CTWindowLevel: Equatable {
    public let name: String
    public let center: Float
    public let width: Float
    
    public init(name: String, center: Float, width: Float) {
        self.name = name
        self.center = center
        self.width = width
    }
    
    // MARK: - Standard Medical Presets
    
    /// Soft tissue window - general purpose CT viewing
    public static let softTissue = CTWindowLevel(
        name: "Soft Tissue",
        center: 40,
        width: 400
    )
    
    /// Lung window - for viewing lung parenchyma
    public static let lung = CTWindowLevel(
        name: "Lung",
        center: -600,
        width: 1600
    )
    
    /// Bone window - for viewing bone structures
    public static let bone = CTWindowLevel(
        name: "Bone",
        center: 500,
        width: 2000
    )
    
    /// Brain window - optimized for brain tissue
    public static let brain = CTWindowLevel(
        name: "Brain",
        center: 40,
        width: 80
    )
    
    /// Liver window - for hepatic imaging
    public static let liver = CTWindowLevel(
        name: "Liver",
        center: 60,
        width: 150
    )
    
    /// Mediastinum window - for chest/mediastinal structures
    public static let mediastinum = CTWindowLevel(
        name: "Mediastinum",
        center: 50,
        width: 350
    )
    
    /// Stroke window - narrow window for acute stroke
    public static let stroke = CTWindowLevel(
        name: "Stroke",
        center: 35,
        width: 35
    )
    
    /// Subdural window - for detecting subdural hematomas
    public static let subdural = CTWindowLevel(
        name: "Subdural",
        center: 75,
        width: 150
    )
    
    /// All presets for UI selection
    public static let allPresets: [CTWindowLevel] = [
        .softTissue,
        .lung,
        .bone,
        .brain,
        .liver,
        .mediastinum,
        .stroke,
        .subdural
    ]
}

// MARK: - Crosshair Appearance Settings

public struct CrosshairAppearance: Equatable {
    public let isVisible: Bool
    public let color: SIMD4<Float>  // RGBA
    public let opacity: Float
    public let lineWidth: Float
    public let fadeDistance: Float  // Distance from center where crosshair fades
    
    public init(
        isVisible: Bool = true,
        color: SIMD4<Float> = SIMD4<Float>(0, 1, 1, 1),  // Cyan
        opacity: Float = 0.8,
        lineWidth: Float = 1.0,
        fadeDistance: Float = 50.0
    ) {
        self.isVisible = isVisible
        self.color = color
        self.opacity = opacity
        self.lineWidth = lineWidth
        self.fadeDistance = fadeDistance
    }
    
    public static let `default` = CrosshairAppearance()
    
    public static let subtle = CrosshairAppearance(
        opacity: 0.5,
        lineWidth: 0.5
    )
    
    public static let bold = CrosshairAppearance(
        color: SIMD4<Float>(1, 1, 0, 1),  // Yellow
        opacity: 1.0,
        lineWidth: 2.0
    )
}

// MARK: - ROI Display Settings

public struct ROIDisplaySettings: Equatable {
    public let isVisible: Bool
    public let globalOpacity: Float
    public let showOutline: Bool
    public let showFilled: Bool
    public let outlineWidth: Float
    public let outlineOpacity: Float
    public let fillOpacity: Float
    public let sliceTolerance: Float  // mm tolerance for showing ROI on nearby slices
    
    public init(
        isVisible: Bool = true,
        globalOpacity: Float = 1.0,
        showOutline: Bool = true,
        showFilled: Bool = false,
        outlineWidth: Float = 2.0,
        outlineOpacity: Float = 1.0,
        fillOpacity: Float = 0.3,
        sliceTolerance: Float = 2.0
    ) {
        self.isVisible = isVisible
        self.globalOpacity = globalOpacity
        self.showOutline = showOutline
        self.showFilled = showFilled
        self.outlineWidth = outlineWidth
        self.outlineOpacity = outlineOpacity
        self.fillOpacity = fillOpacity
        self.sliceTolerance = sliceTolerance
    }
    
    public static let `default` = ROIDisplaySettings()
    
    public static let outlined = ROIDisplaySettings(
        showOutline: true,
        showFilled: false
    )
    
    public static let filled = ROIDisplaySettings(
        showOutline: true,
        showFilled: true,
        fillOpacity: 0.5
    )
    
    public static let subtle = ROIDisplaySettings(
        globalOpacity: 0.5,
        outlineWidth: 1.0,
        fillOpacity: 0.2
    )
}
