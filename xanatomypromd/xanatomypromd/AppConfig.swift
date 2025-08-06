import Foundation

// MARK: - App Configuration
// Central configuration for app behavior and debugging

struct AppConfig {
    
    // MARK: - Debug Settings
    
    /// Master debug flag - set to false for production
    static let debugMode = false
    
    /// Detailed logging flags
    struct Logging {
        static let dicomParsing = false
        static let coordinateSystem = false
        static let volumeLoading = false
        static let rtstruct = false
        static let metalRendering = false
        static let gestures = false
        static let performance = true  // Keep performance logging
    }
    
    // MARK: - Loading Settings
    
    struct Loading {
        /// Progressive loading - load axial first, then others in background
        static let progressiveLoading = true
        
        /// Pre-cache adjacent slices for smoother scrolling
        static let preCacheSlices = true
        static let preCacheRadius = 2  // Number of slices to pre-cache in each direction
        
        /// Show detailed progress during loading
        static let showDetailedProgress = true
    }
    
    // MARK: - Rendering Settings
    
    struct Rendering {
        /// Use lower quality during active scrolling
        static let adaptiveQuality = true
        
        /// Target frame rate
        static let targetFPS = 60
        
        /// Progressive refinement - show low res first, then refine
        static let progressiveRefinement = true
    }
    
    // MARK: - UI Settings
    
    struct UI {
        /// Default layout mode for iPad
        static let defaultIPadLayout = "triple"  // "single", "double", "triple", "quad"
        
        /// Allow custom layouts
        static let allowCustomLayouts = true
        
        /// Animation duration for view transitions
        static let animationDuration = 0.3
    }
    
    // MARK: - Helper Methods
    
    /// Conditional logging based on category
    static func log(_ category: LogCategory, _ message: String) {
        guard debugMode else { return }
        
        let shouldLog: Bool
        switch category {
        case .dicom:
            shouldLog = Logging.dicomParsing
        case .coordinates:
            shouldLog = Logging.coordinateSystem
        case .volume:
            shouldLog = Logging.volumeLoading
        case .rtstruct:
            shouldLog = Logging.rtstruct
        case .metal:
            shouldLog = Logging.metalRendering
        case .gestures:
            shouldLog = Logging.gestures
        case .performance:
            shouldLog = Logging.performance
        case .general:
            shouldLog = true
        }
        
        if shouldLog {
            print("[\(category.icon)] \(message)")
        }
    }
    
    enum LogCategory {
        case dicom
        case coordinates
        case volume
        case rtstruct
        case metal
        case gestures
        case performance
        case general
        
        var icon: String {
            switch self {
            case .dicom: return "📄"
            case .coordinates: return "📍"
            case .volume: return "📦"
            case .rtstruct: return "🏷️"
            case .metal: return "🎨"
            case .gestures: return "👆"
            case .performance: return "⚡"
            case .general: return "ℹ️"
            }
        }
    }
}

// MARK: - Global Debug Print Replacement

/// Use this instead of print() throughout the app
func debugLog(_ message: String, category: AppConfig.LogCategory = .general) {
    AppConfig.log(category, message)
}
