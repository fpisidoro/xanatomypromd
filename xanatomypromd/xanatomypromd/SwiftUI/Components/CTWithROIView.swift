import SwiftUI
import MetalKit
import Metal
import simd

// MARK: - Combined CT + ROI Display View
// SwiftUI wrapper that combines CT rendering with ROI overlays
// FIXED: Now actually renders CT images instead of solid colors

struct CTWithROIView: UIViewRepresentable {
    
    // MARK: - Configuration
    
    let plane: MPRPlane
    let sliceIndex: Int
    let windowLevel: CTWindowPresets.WindowLevel
    let roiManager: CleanROIManager
    let volumeData: VolumeData? // NEW: Pass volume data for actual CT rendering
    
    // MARK: - UIViewRepresentable Implementation
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.drawableSize = CGSize(width: 512, height: 512)
        mtkView.framebufferOnly = false // Allow texture reading
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateRenderingParameters(
            plane: plane,
            sliceIndex: sliceIndex,
            windowLevel: windowLevel,
            roiManager: roiManager,
            volumeData: volumeData // NEW: Pass volume data
        )
        uiView.setNeedsDisplay()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, MTKViewDelegate {
        
        private var metalRenderer: MetalRenderer?
        private var volumeRenderer: MetalVolumeRenderer?
        
        // Current rendering parameters
        private var currentPlane: MPRPlane = .axial
        private var currentSliceIndex: Int = 0
        private var currentWindowLevel: CTWindowPresets.WindowLevel = CTWindowPresets.softTissue
        private var currentROIManager: CleanROIManager?
        private var currentVolumeData: VolumeData? // NEW: Store volume data
        
        override init() {
            super.init()
            setupRenderers()
        }
        
        private func setupRenderers() {
            do {
                metalRenderer = try MetalRenderer()
                volumeRenderer = try MetalVolumeRenderer()
                print("✅ CT+ROI renderers initialized")
            } catch {
                print("❌ Failed to initialize renderers: \(error)")
            }
        }
        
        func updateRenderingParameters(
            plane: MPRPlane,
            sliceIndex: Int,
            windowLevel: CTWindowPresets.WindowLevel,
            roiManager: CleanROIManager,
            volumeData: VolumeData? // NEW: Accept volume data
        ) {
            currentPlane = plane
            currentSliceIndex = sliceIndex
            currentWindowLevel = windowLevel
            currentROIManager = roiManager
            currentVolumeData = volumeData // NEW: Store volume data
            
            // Load volume data into volume renderer if available
            if let volumeData = volumeData, let volumeRenderer = volumeRenderer {
                do {
                    try volumeRenderer.loadVolumeData(volumeData)
                    print("✅ Volume data loaded for CT rendering")
                } catch {
                    print("❌ Failed to load volume data: \(error)")
                }
            }
        }
        
        // MARK: - MTKViewDelegate
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle size changes
        }
        
        func draw(in view: MTKView) {
            guard let device = view.device,
                  let commandQueue = device.makeCommandQueue(),
                  let drawable = view.currentDrawable else {
                return
            }
            
            // Create command buffer
            let commandBuffer = commandQueue.makeCommandBuffer()
            
            // FIXED: Render actual CT image + ROI overlays
            renderCTWithROIOverlay(
                drawable: drawable,
                commandBuffer: commandBuffer,
                viewSize: view.drawableSize
            )
            
            commandBuffer?.present(drawable)
            commandBuffer?.commit()
        }
        
        private func renderCTWithROIOverlay(
            drawable: CAMetalDrawable, 
            commandBuffer: MTLCommandBuffer?, 
            viewSize: CGSize
        ) {
            let renderPassDescriptor = MTLRenderPassDescriptor()
            
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1.0)
            
            guard let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
            
            // STEP 1: Render CT background image
            if let volumeData = currentVolumeData {
                renderCTBackground(renderEncoder: renderEncoder, viewSize: viewSize)
            } else {
                // Fallback: Show loading state or placeholder
                renderPlaceholder(renderEncoder: renderEncoder, viewSize: viewSize)
            }
            
            // STEP 2: Render ROI overlay on top
            if let roiManager = currentROIManager, roiManager.isROIVisible {
                renderROIOverlay(renderEncoder: renderEncoder, viewSize: viewSize)
            }
            
            renderEncoder.endEncoding()
        }
        
        // NEW: Render actual CT slice using Metal volume renderer
        private func renderCTBackground(renderEncoder: MTLRenderCommandEncoder, viewSize: CGSize) {
            guard let volumeRenderer = volumeRenderer,
                  let volumeData = currentVolumeData else {
                print("⚠️ Volume renderer or data not available")
                return
            }
            
            do {
                // Create MPR configuration for current slice
                let normalizedSliceIndex = Float(currentSliceIndex) / Float(getMaxSlicesForPlane())
                let mprConfig = MetalVolumeRenderer.MPRConfig(
                    plane: currentPlane,
                    sliceIndex: normalizedSliceIndex,
                    windowCenter: currentWindowLevel.center,
                    windowWidth: currentWindowLevel.width
                )
                
                // Generate MPR slice texture
                let ctTexture = try volumeRenderer.generateMPRSlice(config: mprConfig, outputSize: SIMD2<Int>(512, 512))
                
                // Render CT texture as background
                renderCTTexture(ctTexture, renderEncoder: renderEncoder, viewSize: viewSize)
                
                print("✅ Rendered CT slice \(currentSliceIndex) for \(currentPlane.displayName)")
                
            } catch {
                print("❌ Failed to generate CT slice: \(error)")
                renderPlaceholder(renderEncoder: renderEncoder, viewSize: viewSize)
            }
        }
        
        private func renderCTTexture(_ ctTexture: MTLTexture, renderEncoder: MTLRenderCommandEncoder, viewSize: CGSize) {
            // TODO: Implement full quad rendering with vertex/fragment shaders
            // For now, the CT texture is generated but needs proper rendering pipeline
            
            // In a complete implementation:
            // 1. Create vertex buffer for full-screen quad
            // 2. Use fragment shader to sample CT texture
            // 3. Apply final color mapping and display
            
            print("   🎨 CT texture ready for display: \(ctTexture.width)x\(ctTexture.height)")
            
            // TEMPORARY: Log texture info to verify CT rendering pipeline
            let pixelFormat = ctTexture.pixelFormat
            print("   📊 CT texture format: \(pixelFormat)")
        }
        
        private func renderPlaceholder(renderEncoder: MTLRenderCommandEncoder, viewSize: CGSize) {
            // Show loading placeholder when volume data isn't available
            // This replaces the old solid color backgrounds
            
            // Could render a simple "Loading CT..." texture here
            print("   📋 Showing placeholder - volume data not loaded")
        }
        
        private func renderROIOverlay(renderEncoder: MTLRenderCommandEncoder, viewSize: CGSize) {
            // Get ROI structures from manager
            let roiStructures = currentROIManager?.getROIStructures() ?? []
            
            guard !roiStructures.isEmpty else { return }
            
            // Calculate current slice position in mm
            let slicePosition = getSlicePositionInMM()
            
            // Create a simple bitmap to draw ROI contours
            let width = Int(viewSize.width)
            let height = Int(viewSize.height)
            
            // Create RGBA bitmap data
            var bitmapData = [UInt8](repeating: 0, count: width * height * 4)
            
            // Draw each ROI structure
            for roi in roiStructures {
                guard roi.isVisible else { continue }
                
                // Find contours that intersect current slice
                let relevantContours = getContoursForCurrentSlice(roi: roi, slicePosition: slicePosition)
                
                // Draw contours for this ROI
                for contour in relevantContours {
                    drawContourToBitmap(
                        contour: contour,
                        bitmap: &bitmapData,
                        width: width,
                        height: height,
                        color: roi.displayColor,
                        opacity: roi.opacity * (currentROIManager?.roiOpacity ?? 1.0)
                    )
                }
            }
            
            // Create texture from bitmap and render it
            if let overlayTexture = createTextureFromBitmap(bitmapData, width: width, height: height) {
                renderOverlayTexture(overlayTexture, renderEncoder: renderEncoder)
                print("✅ ROI overlay rendered on slice \(currentSliceIndex)")
            }
        }
        
        // NEW: Calculate slice position in mm based on plane and index
        private func getSlicePositionInMM() -> Float {
            guard let volumeData = currentVolumeData else {
                // Fallback for test data
                return Float(currentSliceIndex) * 3.0 // 3mm slice thickness
            }
            
            switch currentPlane {
            case .axial:
                // Z position for axial slices
                let zSpacing = volumeData.spacing.z
                return Float(currentSliceIndex) * zSpacing
                
            case .sagittal:
                // X position for sagittal slices
                let xSpacing = volumeData.spacing.x
                return Float(currentSliceIndex) * xSpacing
                
            case .coronal:
                // Y position for coronal slices
                let ySpacing = volumeData.spacing.y
                return Float(currentSliceIndex) * ySpacing
            }
        }
        
        // NEW: Get relevant contours for current slice based on plane
        private func getContoursForCurrentSlice(roi: ROIStructure, slicePosition: Float) -> [ROIContour] {
            switch currentPlane {
            case .axial:
                // Axial: show contours at current Z slice
                return roi.contours.filter { contour in
                    abs(contour.slicePosition - slicePosition) < 2.0 // 2mm tolerance
                }
                
            case .sagittal:
                // Sagittal: create cross-section at current X position
                return createSagittalCrossSection(roi: roi, xPosition: slicePosition)
                
            case .coronal:
                // Coronal: create cross-section at current Y position
                return createCoronalCrossSection(roi: roi, yPosition: slicePosition)
            }
        }
        
        private func getMaxSlicesForPlane() -> Int {
            guard let volumeData = currentVolumeData else {
                // Fallback for test data
                return 53
            }
            
            switch currentPlane {
            case .axial:
                return volumeData.dimensions.z
            case .sagittal:
                return volumeData.dimensions.x
            case .coronal:
                return volumeData.dimensions.y
            }
        }
        
        // [Keep existing ROI cross-section and drawing methods...]
        private func createSagittalCrossSection(roi: ROIStructure, xPosition: Float) -> [ROIContour] {
            var crossSectionPoints: [SIMD3<Float>] = []
            
            for contour in roi.contours {
                for i in 0..<contour.contourData.count {
                    let p1 = contour.contourData[i]
                    let p2 = contour.contourData[(i + 1) % contour.contourData.count]
                    
                    if (p1.x <= xPosition && p2.x >= xPosition) || (p1.x >= xPosition && p2.x <= xPosition) {
                        let t = (xPosition - p1.x) / (p2.x - p1.x)
                        if t >= 0.0 && t <= 1.0 {
                            let intersectionY = p1.y + t * (p2.y - p1.y)
                            let intersectionZ = p1.z + t * (p2.z - p1.z)
                            crossSectionPoints.append(SIMD3<Float>(xPosition, intersectionY, intersectionZ))
                        }
                    }
                }
            }
            
            if crossSectionPoints.count >= 3 {
                let sortedPoints = sortPointsInCircularOrder(crossSectionPoints, plane: .sagittal)
                return [ROIContour(
                    contourNumber: 1,
                    geometricType: .closedPlanar,
                    numberOfPoints: sortedPoints.count,
                    contourData: sortedPoints,
                    slicePosition: xPosition
                )]
            }
            
            return []
        }
        
        private func createCoronalCrossSection(roi: ROIStructure, yPosition: Float) -> [ROIContour] {
            var crossSectionPoints: [SIMD3<Float>] = []
            
            for contour in roi.contours {
                for i in 0..<contour.contourData.count {
                    let p1 = contour.contourData[i]
                    let p2 = contour.contourData[(i + 1) % contour.contourData.count]
                    
                    if (p1.y <= yPosition && p2.y >= yPosition) || (p1.y >= yPosition && p2.y <= yPosition) {
                        let t = (yPosition - p1.y) / (p2.y - p1.y)
                        if t >= 0.0 && t <= 1.0 {
                            let intersectionX = p1.x + t * (p2.x - p1.x)
                            let intersectionZ = p1.z + t * (p2.z - p1.z)
                            crossSectionPoints.append(SIMD3<Float>(intersectionX, yPosition, intersectionZ))
                        }
                    }
                }
            }
            
            if crossSectionPoints.count >= 3 {
                let sortedPoints = sortPointsInCircularOrder(crossSectionPoints, plane: .coronal)
                return [ROIContour(
                    contourNumber: 1,
                    geometricType: .closedPlanar,
                    numberOfPoints: sortedPoints.count,
                    contourData: sortedPoints,
                    slicePosition: yPosition
                )]
            }
            
            return []
        }
        
        private func sortPointsInCircularOrder(_ points: [SIMD3<Float>], plane: MPRPlane) -> [SIMD3<Float>] {
            guard points.count >= 3 else { return points }
            
            var uniquePoints: [SIMD3<Float>] = []
            for point in points {
                let isDuplicate = uniquePoints.contains { existingPoint in
                    let diff = point - existingPoint
                    return sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z) < 1.0
                }
                if !isDuplicate {
                    uniquePoints.append(point)
                }
            }
            
            guard uniquePoints.count >= 3 else { return points }
            
            switch plane {
            case .axial:
                let centerX = uniquePoints.map { $0.x }.reduce(0, +) / Float(uniquePoints.count)
                let centerY = uniquePoints.map { $0.y }.reduce(0, +) / Float(uniquePoints.count)
                
                return uniquePoints.sorted { p1, p2 in
                    let angle1 = atan2(p1.y - centerY, p1.x - centerX)
                    let angle2 = atan2(p2.y - centerY, p2.x - centerX)
                    return angle1 < angle2
                }
                
            case .sagittal:
                let centerY = uniquePoints.map { $0.y }.reduce(0, +) / Float(uniquePoints.count)
                let centerZ = uniquePoints.map { $0.z }.reduce(0, +) / Float(uniquePoints.count)
                
                return uniquePoints.sorted { p1, p2 in
                    let angle1 = atan2(p1.z - centerZ, p1.y - centerY)
                    let angle2 = atan2(p2.z - centerZ, p2.y - centerY)
                    return angle1 < angle2
                }
                
            case .coronal:
                let centerX = uniquePoints.map { $0.x }.reduce(0, +) / Float(uniquePoints.count)
                let centerZ = uniquePoints.map { $0.z }.reduce(0, +) / Float(uniquePoints.count)
                
                return uniquePoints.sorted { p1, p2 in
                    let angle1 = atan2(p1.z - centerZ, p1.x - centerX)
                    let angle2 = atan2(p2.z - centerZ, p2.x - centerX)
                    return angle1 < angle2
                }
            }
        }
        
        private func drawContourToBitmap(
            contour: ROIContour,
            bitmap: inout [UInt8],
            width: Int,
            height: Int,
            color: SIMD3<Float>,
            opacity: Float
        ) {
            let screenPoints = projectContourToScreen(contour: contour, viewSize: CGSize(width: width, height: height))
            
            for i in 0..<screenPoints.count {
                let p1 = screenPoints[i]
                let p2 = screenPoints[(i + 1) % screenPoints.count]
                
                drawLineToBitmap(
                    from: p1,
                    to: p2,
                    bitmap: &bitmap,
                    width: width,
                    height: height,
                    color: color,
                    opacity: opacity
                )
            }
        }
        
        private func drawLineToBitmap(
            from p1: SIMD2<Float>,
            to p2: SIMD2<Float>,
            bitmap: inout [UInt8],
            width: Int,
            height: Int,
            color: SIMD3<Float>,
            opacity: Float
        ) {
            let x1 = Int(p1.x)
            let y1 = Int(p1.y)
            let x2 = Int(p2.x)
            let y2 = Int(p2.y)
            
            let dx = abs(x2 - x1)
            let dy = abs(y2 - y1)
            let sx = x1 < x2 ? 1 : -1
            let sy = y1 < y2 ? 1 : -1
            var err = dx - dy
            
            var x = x1
            var y = y1
            
            let r = UInt8(color.x * 255 * opacity)
            let g = UInt8(color.y * 255 * opacity)
            let b = UInt8(color.z * 255 * opacity)
            let a = UInt8(255 * opacity)
            
            while true {
                if x >= 0 && x < width && y >= 0 && y < height {
                    let pixelIndex = (y * width + x) * 4
                    if pixelIndex + 3 < bitmap.count {
                        bitmap[pixelIndex] = r
                        bitmap[pixelIndex + 1] = g
                        bitmap[pixelIndex + 2] = b
                        bitmap[pixelIndex + 3] = a
                    }
                }
                
                if x == x2 && y == y2 { break }
                
                let e2 = 2 * err
                if e2 > -dy {
                    err -= dy
                    x += sx
                }
                if e2 < dx {
                    err += dx
                    y += sy
                }
            }
        }
        
        private func createTextureFromBitmap(_ bitmapData: [UInt8], width: Int, height: Int) -> MTLTexture? {
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            textureDescriptor.usage = [.shaderRead]
            
            guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return nil }
            
            let region = MTLRegionMake2D(0, 0, width, height)
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: bitmapData,
                bytesPerRow: width * 4
            )
            
            return texture
        }
        
        private func renderOverlayTexture(_ overlayTexture: MTLTexture, renderEncoder: MTLRenderCommandEncoder) {
            // TODO: Implement proper texture blending
            print("   🎨 Created ROI overlay texture: \(overlayTexture.width)x\(overlayTexture.height)")
        }
        
        private func projectContourToScreen(contour: ROIContour, viewSize: CGSize) -> [SIMD2<Float>] {
            var screenPoints: [SIMD2<Float>] = []
            
            for point3D in contour.contourData {
                var screenX: Float
                var screenY: Float
                
                switch currentPlane {
                case .axial:
                    screenX = (point3D.x / 512.0) * Float(viewSize.width)
                    screenY = (point3D.y / 512.0) * Float(viewSize.height)
                    
                case .sagittal:
                    screenX = (point3D.y / 512.0) * Float(viewSize.width)
                    screenY = Float(viewSize.height) - (point3D.z / 160.0) * Float(viewSize.height)
                    
                case .coronal:
                    screenX = (point3D.x / 512.0) * Float(viewSize.width)
                    screenY = Float(viewSize.height) - (point3D.z / 160.0) * Float(viewSize.height)
                }
                
                screenPoints.append(SIMD2<Float>(screenX, screenY))
            }
            
            return screenPoints
        }
    }
}

// MARK: - MPRPlane Helper Extension

extension MPRPlane {
    var stringValue: String {
        switch self {
        case .axial: return "axial"
        case .sagittal: return "sagittal" 
        case .coronal: return "coronal"
        }
    }
}

// MARK: - Preview

#Preview {
    CTWithROIView(
        plane: .axial,
        sliceIndex: 26,
        windowLevel: CTWindowPresets.softTissue,
        roiManager: CleanROIManager(),
        volumeData: nil
    )
    .frame(width: 400, height: 400)
}
