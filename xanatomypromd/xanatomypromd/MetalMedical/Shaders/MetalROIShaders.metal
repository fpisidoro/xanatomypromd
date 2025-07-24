#include <metal_stdlib>
using namespace metal;

// MARK: - ROI Overlay Metal Shaders
// GPU-accelerated rendering of RTStruct ROI contours as transparent overlays

// MARK: - ROI Vertex Structures

struct ROIVertex {
    float2 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct ROIVertexOut {
    float4 position [[position]];
    float4 color;
    float2 texCoord;
};

// MARK: - ROI Uniform Data

struct ROIUniforms {
    float4x4 mvpMatrix;           // Model-View-Projection matrix
    float opacity;                // Global ROI opacity (0.0 to 1.0)
    float lineWidth;              // Contour line width in pixels
    uint renderMode;              // 0=filled, 1=outline, 2=both
    float2 viewportSize;          // Screen dimensions for line width calculation
};

struct ROIRenderParams {
    float4 roiColor;              // RGBA color for this ROI
    float opacity;                // Individual ROI opacity
    uint geometricType;           // 0=point, 1=open, 2=closed
    uint enableAntialiasing;      // 0=off, 1=on
    float2 textureSize;           // For coordinate normalization
};

// MARK: - Coordinate Transformation Utilities

// Convert patient coordinates to normalized device coordinates
float2 patientToNDC(float3 patientCoord, float3 volumeOrigin, float3 volumeSpacing, float2 textureSize) {
    // Convert to voxel coordinates
    float3 voxelCoord = (patientCoord - volumeOrigin) / volumeSpacing;
    
    // Normalize to [0,1] texture coordinates
    float2 texCoord = float2(voxelCoord.x / textureSize.x, voxelCoord.y / textureSize.y);
    
    // Convert to NDC [-1,1]
    return texCoord * 2.0 - 1.0;
}

// MARK: - ROI Contour Vertex Shader

vertex ROIVertexOut roi_vertex_main(ROIVertex in [[stage_in]],
                                    constant ROIUniforms& uniforms [[buffer(0)]],
                                    constant ROIRenderParams& params [[buffer(1)]]) {
    ROIVertexOut out;
    
    // Transform vertex position
    float4 position = float4(in.position, 0.0, 1.0);
    out.position = uniforms.mvpMatrix * position;
    
    // Pass through color with combined opacity
    out.color = float4(in.color.rgb, in.color.a * uniforms.opacity * params.opacity);
    
    // Calculate texture coordinates for antialiasing
    out.texCoord = (in.position + 1.0) * 0.5; // Convert from NDC to [0,1]
    
    return out;
}

// MARK: - ROI Filled Fragment Shader (for closed contours)

fragment float4 roi_filled_fragment(ROIVertexOut in [[stage_in]],
                                    constant ROIRenderParams& params [[buffer(0)]]) {
    
    float4 color = in.color;
    
    // Apply antialiasing for smooth edges
    if (params.enableAntialiasing) {
        // Simple edge smoothing based on fragment position
        float2 edge = abs(in.texCoord - 0.5) * 2.0; // Distance from center
        float edgeFactor = 1.0 - smoothstep(0.8, 1.0, max(edge.x, edge.y));
        color.a *= edgeFactor;
    }
    
    return color;
}

// MARK: - ROI Outline Fragment Shader (for contour lines)

fragment float4 roi_outline_fragment(ROIVertexOut in [[stage_in]],
                                     constant ROIUniforms& uniforms [[buffer(0)]],
                                     constant ROIRenderParams& params [[buffer(1)]]) {
    
    float4 color = in.color;
    
    // Calculate line width in normalized coordinates
    float2 lineWidthNorm = uniforms.lineWidth / uniforms.viewportSize;
    
    // Distance from edge for line rendering
    float2 edge = abs(in.texCoord - 0.5) * 2.0;
    float maxEdge = max(edge.x, edge.y);
    
    // Create line effect
    float lineAlpha = 1.0 - smoothstep(1.0 - lineWidthNorm.x, 1.0, maxEdge);
    
    // Apply antialiasing
    if (params.enableAntialiasing) {
        lineAlpha = smoothstep(0.0, lineWidthNorm.x, lineAlpha);
    }
    
    color.a *= lineAlpha;
    
    return color;
}

// MARK: - ROI Point Fragment Shader (for point ROIs)

fragment float4 roi_point_fragment(ROIVertexOut in [[stage_in]],
                                   constant ROIRenderParams& params [[buffer(0)]]) {
    
    // Calculate distance from center for circular point
    float2 center = float2(0.5, 0.5);
    float dist = distance(in.texCoord, center);
    
    // Create circular point with smooth edges
    float pointRadius = 0.4; // 80% of the quad
    float alpha = 1.0 - smoothstep(pointRadius - 0.1, pointRadius, dist);
    
    float4 color = in.color;
    color.a *= alpha;
    
    return color;
}

// MARK: - ROI Multi-Mode Fragment Shader

fragment float4 roi_multimode_fragment(ROIVertexOut in [[stage_in]],
                                       constant ROIUniforms& uniforms [[buffer(0)]],
                                       constant ROIRenderParams& params [[buffer(1)]]) {
    
    float4 finalColor = float4(0.0);
    
    // Render based on geometric type
    switch (params.geometricType) {
        case 0: // Point
            {
                float2 center = float2(0.5, 0.5);
                float dist = distance(in.texCoord, center);
                float pointRadius = 0.3;
                float alpha = 1.0 - smoothstep(pointRadius - 0.05, pointRadius, dist);
                finalColor = float4(in.color.rgb, in.color.a * alpha);
            }
            break;
            
        case 1: // Open contour (line)
            {
                float2 lineWidthNorm = uniforms.lineWidth / uniforms.viewportSize;
                float2 edge = abs(in.texCoord - 0.5) * 2.0;
                float maxEdge = max(edge.x, edge.y);
                float lineAlpha = 1.0 - smoothstep(1.0 - lineWidthNorm.x, 1.0, maxEdge);
                finalColor = float4(in.color.rgb, in.color.a * lineAlpha);
            }
            break;
            
        case 2: // Closed contour (filled + outline)
            {
                // Filled area
                float4 fillColor = in.color;
                fillColor.a *= 0.3; // Semi-transparent fill
                
                // Outline
                float2 lineWidthNorm = uniforms.lineWidth / uniforms.viewportSize;
                float2 edge = abs(in.texCoord - 0.5) * 2.0;
                float maxEdge = max(edge.x, edge.y);
                float lineAlpha = 1.0 - smoothstep(1.0 - lineWidthNorm.x, 1.0, maxEdge);
                float4 lineColor = float4(in.color.rgb, in.color.a * lineAlpha);
                
                // Combine fill and outline
                finalColor = mix(fillColor, lineColor, lineAlpha);
            }
            break;
            
        default:
            finalColor = in.color;
            break;
    }
    
    return finalColor;
}

// MARK: - ROI Composite Fragment Shader (blend multiple ROIs)

fragment float4 roi_composite_fragment(ROIVertexOut in [[stage_in]],
                                       texture2d<float> backgroundTexture [[texture(0)]],
                                       constant ROIRenderParams& params [[buffer(0)]]) {
    
    constexpr sampler textureSampler(coord::normalized,
                                     filter::linear,
                                     address::clamp_to_edge);
    
    // Sample background (CT image)
    float4 background = backgroundTexture.sample(textureSampler, in.texCoord);
    
    // ROI overlay color
    float4 overlay = in.color;
    
    // Alpha blending: result = overlay * alpha + background * (1 - alpha)
    float alpha = overlay.a;
    float4 result = overlay * alpha + background * (1.0 - alpha);
    
    // Preserve background alpha
    result.a = background.a;
    
    return result;
}

// MARK: - ROI Distance Field Fragment Shader (smooth contours)

fragment float4 roi_distance_field_fragment(ROIVertexOut in [[stage_in]],
                                            constant ROIRenderParams& params [[buffer(0)]]) {
    
    // Calculate distance from edge using texture coordinates
    float2 p = in.texCoord * 2.0 - 1.0; // Convert to [-1,1]
    
    // Simple distance field for rounded rectangle
    float2 d = abs(p) - float2(0.8, 0.8);
    float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    
    // Create smooth edge
    float edgeWidth = 0.02;
    float alpha = 1.0 - smoothstep(-edgeWidth, edgeWidth, dist);
    
    float4 color = in.color;
    color.a *= alpha;
    
    return color;
}

// MARK: - ROI Glow Effect Fragment Shader

fragment float4 roi_glow_fragment(ROIVertexOut in [[stage_in]],
                                  constant ROIRenderParams& params [[buffer(0)]]) {
    
    float2 center = float2(0.5, 0.5);
    float dist = distance(in.texCoord, center);
    
    // Create glow effect
    float glowRadius = 0.6;
    float glowIntensity = exp(-dist * 8.0); // Exponential falloff
    
    // Inner solid area
    float solidRadius = 0.3;
    float solidAlpha = 1.0 - smoothstep(solidRadius - 0.05, solidRadius, dist);
    
    // Combine solid area with glow
    float finalAlpha = max(solidAlpha, glowIntensity * 0.5);
    
    float4 color = in.color;
    color.a *= finalAlpha;
    
    return color;
}

// MARK: - ROI Animation Fragment Shader (pulsing effect)

fragment float4 roi_animated_fragment(ROIVertexOut in [[stage_in]],
                                      constant ROIRenderParams& params [[buffer(0)]],
                                      constant float& time [[buffer(1)]]) {
    
    // Pulsing animation
    float pulse = (sin(time * 3.0) + 1.0) * 0.5; // 0 to 1
    float animatedOpacity = 0.3 + pulse * 0.4; // 0.3 to 0.7
    
    float4 color = in.color;
    color.a *= animatedOpacity;
    
    // Optional color shifting
    color.rgb *= (0.8 + pulse * 0.4); // Brightness modulation
    
    return color;
}

// MARK: - Utility Functions for ROI Rendering

// Calculate smooth line width based on zoom level
float calculateLineWidth(float baseWidth, float zoomLevel, float2 viewportSize) {
    // Maintain consistent visual line width across zoom levels
    float adaptiveWidth = baseWidth / max(zoomLevel, 0.5);
    
    // Clamp to reasonable pixel range
    return clamp(adaptiveWidth, 1.0, 10.0);
}

// Convert ROI geometric type to render parameters
uint getGeometricTypeCode(constant char* geometricType) {
    // This would be handled on CPU side, but useful for reference
    // "POINT" = 0, "OPEN_PLANAR" = 1, "CLOSED_PLANAR" = 2
    return 2; // Default to closed planar
}

// Calculate adaptive opacity based on ROI count
float calculateAdaptiveOpacity(uint roiCount, float baseOpacity) {
    // Reduce opacity when many ROIs are visible to prevent visual clutter
    float opacityFactor = 1.0 / (1.0 + float(roiCount) * 0.1);
    return baseOpacity * clamp(opacityFactor, 0.3, 1.0);
}

// MARK: - ROI Tessellation Support (for complex contours)

// Simple tessellation for converting contour points to triangles
vertex ROIVertexOut roi_tessellated_vertex(uint vid [[vertex_id]],
                                           constant float2* contourPoints [[buffer(0)]],
                                           constant ROIUniforms& uniforms [[buffer(1)]],
                                           constant ROIRenderParams& params [[buffer(2)]]) {
    
    ROIVertexOut out;
    
    // Get tessellated vertex position
    float2 position = contourPoints[vid];
    
    // Transform to clip space
    out.position = uniforms.mvpMatrix * float4(position, 0.0, 1.0);
    
    // Set color
    out.color = params.roiColor;
    out.color.a *= uniforms.opacity * params.opacity;
    
    // Texture coordinates for effects
    out.texCoord = (position + 1.0) * 0.5;
    
    return out;
}
