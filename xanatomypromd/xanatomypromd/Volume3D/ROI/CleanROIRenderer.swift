import Foundation
import Metal
import simd

// MARK: - Simple ROI Display System
// Clean, minimal ROI overlay implementation that doesn't break existing CT viewer
// Follows separation of concerns principle from handover lessons learned

/// Simple ROI renderer that overlays contours on existing CT textures
public class SimpleROIRenderer {
    
    // MARK: - Core Components
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue?
    
    // MARK: - ROI Render Modes
    
    public enum RenderMode {
        case outline        // Just contour lines
        case filled         // Filled regions
        case both          // Outline + filled
    }
    
    // MARK: - Initialization
    
    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ROIDisplayError.metalNotAvailable
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        
        print("✅ SimpleROIRenderer initialized")
    }
    
    // MARK: - Simple ROI Overlay Generation
    
    /// Create ROI overlay texture for a specific slice
    public func createROIOverlay(
        for roiStructures: [ROIStructure],
        plane: MPRPlane,
        slicePosition: Float,
        textureSize: SIMD2<Int>,
        volumeOrigin: SIMD3<Float>,
        volumeSpacing: SIMD3<Float>
    ) -> MTLTexture? {
        
        // Create output texture for ROI overlay
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: textureSize.x,
            height: textureSize.y,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderWrite, .renderTarget]
        
        guard let overlayTexture = device.makeTexture(descriptor: textureDescriptor) else {
            print("❌ Failed to create ROI overlay texture")
            return nil
        }
        
        // Find ROIs that intersect this slice
        let relevantROIs = getROIsForSlice(
            roiStructures: roiStructures,
            plane: plane,
            slicePosition: slicePosition,
            tolerance: 2.0  // 2mm tolerance
        )
        
        if relevantROIs.isEmpty {
            // Return transparent texture if no ROIs on this slice
            clearTexture(overlayTexture)
            return overlayTexture
        }
        
        print("🎨 Rendering \(relevantROIs.count) ROIs on \(plane.rawValue) slice at \(slicePosition)mm")
        
        // Simple CPU-based rendering for now (can optimize with Metal shaders later)
        renderROIsToTexture(
            relevantROIs: relevantROIs,
            texture: overlayTexture,
            plane: plane,
            slicePosition: slicePosition,
            volumeOrigin: volumeOrigin,
            volumeSpacing: volumeSpacing
        )
        
        return overlayTexture
    }
    
    // MARK: - ROI Processing
    
    private func getROIsForSlice(
        roiStructures: [ROIStructure],
        plane: MPRPlane,
        slicePosition: Float,
        tolerance: Float
    ) -> [(roi: ROIStructure, contours: [ROIContour])] {
        
        var relevantROIs: [(roi: ROIStructure, contours: [ROIContour])] = []
        
        for roi in roiStructures {
            guard roi.isVisible else { continue }
            
            let contoursOnSlice = roi.contours.filter { contour in
                contour.intersectsSlice(slicePosition, plane: plane, tolerance: tolerance)
            }
            
            if !contoursOnSlice.isEmpty {
                relevantROIs.append((roi: roi, contours: contoursOnSlice))
            }
        }
        
        return relevantROIs
    }
    
    private func renderROIsToTexture(
        relevantROIs: [(roi: ROIStructure, contours: [ROIContour])],
        texture: MTLTexture,
        plane: MPRPlane,
        slicePosition: Float,
        volumeOrigin: SIMD3<Float>,
        volumeSpacing: SIMD3<Float>
    ) {
        // Simple CPU-based contour rendering
        // This is a placeholder - in production you'd use Metal compute shaders for performance
        
        // Create a basic 2D canvas
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4  // RGBA
        let bytesPerRow = width * bytesPerPixel
        let bufferSize = height * bytesPerRow
        
        var pixelBuffer = [UInt8](repeating: 0, count: bufferSize)
        
        // Render each ROI
        for (roi, contours) in relevantROIs {
            let color = roi.displayColor
            let rgba = [
                UInt8(color.x * 255),
                UInt8(color.y * 255),
                UInt8(color.z * 255),
                UInt8(roi.opacity * 255)
            ]
            
            // Render each contour
            for contour in contours {
                renderContourToBuffer(
                    contour: contour,
                    buffer: &pixelBuffer,
                    width: width,
                    height: height,
                    color: rgba,
                    plane: plane,
                    volumeOrigin: volumeOrigin,
                    volumeSpacing: volumeSpacing
                )
            }
        }
        
        // Upload buffer to texture
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: pixelBuffer,
            bytesPerRow: bytesPerRow
        )
    }
    
    private func renderContourToBuffer(
        contour: ROIContour,
        buffer: inout [UInt8],
        width: Int,
        height: Int,
        color: [UInt8],
        plane: MPRPlane,
        volumeOrigin: SIMD3<Float>,
        volumeSpacing: SIMD3<Float>
    ) {
        // Convert 3D contour points to 2D screen coordinates
        let screenPoints = contour.projectToPlane(plane, volumeOrigin: volumeOrigin, volumeSpacing: volumeSpacing)
        
        // Simple line drawing between consecutive points
        for i in 0..<screenPoints.count {
            let p1 = screenPoints[i]
            let p2 = screenPoints[(i + 1) % screenPoints.count]  // Wrap around for closed contours
            
            // Convert to pixel coordinates
            let x1 = Int(p1.x)
            let y1 = Int(p1.y)
            let x2 = Int(p2.x)
            let y2 = Int(p2.y)
            
            // Simple line drawing (Bresenham's algorithm would be better)
            drawLine(
                from: (x1, y1),
                to: (x2, y2),
                buffer: &buffer,
                width: width,
                height: height,
                color: color
            )
        }
    }
    
    private func drawLine(
        from: (Int, Int),
        to: (Int, Int),
        buffer: inout [UInt8],
        width: Int,
        height: Int,
        color: [UInt8]
    ) {
        let (x1, y1) = from
        let (x2, y2) = to
        
        // Bounds checking
        guard x1 >= 0, x1 < width, y1 >= 0, y1 < height,
              x2 >= 0, x2 < width, y2 >= 0, y2 < height else {
            return
        }
        
        // Simple line drawing - just plot start and end points for now
        // In production, use proper line drawing algorithm
        let pixels = [(x1, y1), (x2, y2)]
        
        for (x, y) in pixels {
            let pixelIndex = (y * width + x) * 4
            if pixelIndex + 3 < buffer.count {
                buffer[pixelIndex] = color[0]     // R
                buffer[pixelIndex + 1] = color[1] // G
                buffer[pixelIndex + 2] = color[2] // B
                buffer[pixelIndex + 3] = color[3] // A
            }
        }
    }
    
    private func clearTexture(_ texture: MTLTexture) {
        let width = texture.width
        let height = texture.height
        let bufferSize = width * height * 4
        let clearBuffer = [UInt8](repeating: 0, count: bufferSize)
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: clearBuffer,
            bytesPerRow: width * 4
        )
    }
}

// MARK: - ROI Display Manager
// Clean interface for managing ROI display without breaking existing system

@MainActor
public class CleanROIManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published public var isROIVisible: Bool = true
    @Published public var roiOpacity: Float = 0.5
    @Published public var selectedROIs: Set<Int> = []
    
    // MARK: - Core Components
    
    private var roiRenderer: SimpleROIRenderer?
    private var currentRTStructData: RTStructData?
    
    // MARK: - Initialization
    
    public init() {
        setupRenderer()
    }
    
    private func setupRenderer() {
        do {
            roiRenderer = try SimpleROIRenderer()
            print("✅ CleanROIManager initialized")
        } catch {
            print("❌ Failed to initialize ROI renderer: \(error)")
        }
    }
    
    // MARK: - RTStruct Data Management
    
    /// Load RTStruct data for display
    public func loadRTStructData(_ rtStructData: RTStructData) {
        self.currentRTStructData = rtStructData
        print("✅ Loaded RTStruct with \(rtStructData.roiStructures.count) ROIs")
    }
    
    /// Get available ROI structures
    public func getROIStructures() -> [ROIStructure] {
        return currentRTStructData?.roiStructures ?? []
    }
    
    /// Get ROI names for UI display
    public func getROINames() -> [String] {
        return getROIStructures().map { $0.roiName }
    }
    
    // MARK: - ROI Overlay Generation
    
    /// Generate ROI overlay texture for a specific slice
    public func generateROIOverlay(
        plane: MPRPlane,
        slicePosition: Float,
        textureSize: SIMD2<Int>,
        volumeOrigin: SIMD3<Float>,
        volumeSpacing: SIMD3<Float>
    ) -> MTLTexture? {
        
        guard let renderer = roiRenderer,
              isROIVisible,
              let rtStructData = currentRTStructData else {
            return nil
        }
        
        // Apply opacity to all visible ROIs
        var adjustedROIs = rtStructData.roiStructures.map { roi in
            ROIStructure(
                roiNumber: roi.roiNumber,
                roiName: roi.roiName,
                roiDescription: roi.roiDescription,
                roiGenerationAlgorithm: roi.roiGenerationAlgorithm,
                displayColor: roi.displayColor,
                isVisible: roi.isVisible && (selectedROIs.isEmpty || selectedROIs.contains(roi.roiNumber)),
                opacity: roi.opacity * roiOpacity,
                contours: roi.contours
            )
        }
        
        return renderer.createROIOverlay(
            for: adjustedROIs,
            plane: plane,
            slicePosition: slicePosition,
            textureSize: textureSize,
            volumeOrigin: volumeOrigin,
            volumeSpacing: volumeSpacing
        )
    }
    
    // MARK: - ROI Selection
    
    /// Toggle ROI selection
    public func toggleROI(_ roiNumber: Int) {
        if selectedROIs.contains(roiNumber) {
            selectedROIs.remove(roiNumber)
        } else {
            selectedROIs.insert(roiNumber)
        }
    }
    
    /// Clear all selections (show all ROIs)
    public func clearSelection() {
        selectedROIs.removeAll()
    }
    
    /// Select only one ROI
    public func selectOnly(_ roiNumber: Int) {
        selectedROIs = [roiNumber]
    }
    
    // MARK: - ROI Information
    
    /// Get ROI info for current slice
    public func getROIInfoForSlice(
        plane: MPRPlane,
        slicePosition: Float
    ) -> [String] {
        guard let rtStructData = currentRTStructData else { return [] }
        
        var info: [String] = []
        
        for roi in rtStructData.roiStructures {
            let contoursOnSlice = roi.contours.filter { contour in
                contour.intersectsSlice(slicePosition, plane: plane, tolerance: 2.0)
            }
            
            if !contoursOnSlice.isEmpty {
                info.append("\(roi.roiName): \(contoursOnSlice.count) contours")
            }
        }
        
        return info
    }
}

// MARK: - Error Handling

public enum ROIDisplayError: Error, LocalizedError {
    case metalNotAvailable
    case textureCreationFailed
    case invalidROIData
    
    public var errorDescription: String? {
        switch self {
        case .metalNotAvailable:
            return "Metal graphics API not available"
        case .textureCreationFailed:
            return "Failed to create Metal texture for ROI overlay"
        case .invalidROIData:
            return "Invalid ROI structure data"
        }
    }
}
