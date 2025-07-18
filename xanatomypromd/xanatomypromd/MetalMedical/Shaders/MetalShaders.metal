#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex and Fragment Structures

struct VertexIn {
    float2 position;
    float2 texCoord;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct WindowingData {
    float windowCenter;
    float windowWidth;
};

// MARK: - Vertex Shader

// NEW: Aspect ratio correction uniforms
struct AspectRatioUniforms {
    float scaleX;
    float scaleY;
    float2 offset;  // For future centering adjustments
};

// MARK: - Updated Vertex Shader with Aspect Ratio Correction

vertex VertexOut vertex_main(const device float4* vertices [[buffer(0)]],
                             constant AspectRatioUniforms& aspectRatio [[buffer(1)]],
                             uint vid [[vertex_id]]) {
    VertexOut out;
    
    // Get original vertex position
    float2 originalPos = vertices[vid].xy;
    
    // Apply aspect ratio correction to maintain 1:1 pixel ratio
    float2 correctedPos = originalPos * float2(aspectRatio.scaleX, aspectRatio.scaleY);
    
    out.position = float4(correctedPos, 0.0, 1.0);
    out.texCoord = vertices[vid].zw;
    
    return out;
}

// MARK: - Fragment Shader for CT Windowing

fragment float4 fragment_windowing(VertexOut in [[stage_in]],
                                   texture2d<short> inputTexture [[texture(0)]],
                                   constant WindowingData& windowing [[buffer(0)]]) {
    
    constexpr sampler textureSampler(coord::normalized,
                                     filter::linear,
                                     address::clamp_to_edge);
    
    // Sample the signed 16-bit texture
    short pixelValue = inputTexture.sample(textureSampler, in.texCoord).r;
    
    // Convert to float for windowing calculation
    float value = float(pixelValue);
    
    // Apply CT windowing transformation
    float minValue = windowing.windowCenter - windowing.windowWidth / 2.0;
    float maxValue = windowing.windowCenter + windowing.windowWidth / 2.0;
    
    // Clamp and normalize to 0-1 range
    float normalizedValue = clamp((value - minValue) / (maxValue - minValue), 0.0, 1.0);
    
    // Return as grayscale with proper medical imaging appearance
    return float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
}

// MARK: - Enhanced Fragment Shader with Better Contrast

fragment float4 fragment_windowing_enhanced(VertexOut in [[stage_in]],
                                            texture2d<short> inputTexture [[texture(0)]],
                                            constant WindowingData& windowing [[buffer(0)]]) {
    
    constexpr sampler textureSampler(coord::normalized,
                                     filter::linear,
                                     address::clamp_to_edge);
    
    // Sample the signed 16-bit texture
    short pixelValue = inputTexture.sample(textureSampler, in.texCoord).r;
    float value = float(pixelValue);
    
    // Apply CT windowing with enhanced contrast
    float minValue = windowing.windowCenter - windowing.windowWidth / 2.0;
    float maxValue = windowing.windowCenter + windowing.windowWidth / 2.0;
    
    // Normalize to 0-1 range
    float normalizedValue = (value - minValue) / (maxValue - minValue);
    
    // Apply sigmoid curve for better contrast
    float enhanced = 1.0 / (1.0 + exp(-6.0 * (normalizedValue - 0.5)));
    
    // Clamp to valid range
    enhanced = clamp(enhanced, 0.0, 1.0);
    
    // Return as grayscale
    return float4(enhanced, enhanced, enhanced, 1.0);
}

// MARK: - Fragment Shader with Inverted Colors (for X-ray appearance)

fragment float4 fragment_windowing_inverted(VertexOut in [[stage_in]],
                                            texture2d<short> inputTexture [[texture(0)]],
                                            constant WindowingData& windowing [[buffer(0)]]) {
    
    constexpr sampler textureSampler(coord::normalized,
                                     filter::linear,
                                     address::clamp_to_edge);
    
    // Sample the signed 16-bit texture
    short pixelValue = inputTexture.sample(textureSampler, in.texCoord).r;
    float value = float(pixelValue);
    
    // Apply CT windowing
    float minValue = windowing.windowCenter - windowing.windowWidth / 2.0;
    float maxValue = windowing.windowCenter + windowing.windowWidth / 2.0;
    
    // Normalize and invert
    float normalizedValue = clamp((value - minValue) / (maxValue - minValue), 0.0, 1.0);
    float inverted = 1.0 - normalizedValue;
    
    // Return inverted grayscale
    return float4(inverted, inverted, inverted, 1.0);
}

// MARK: - Fragment Shader with Color Mapping

fragment float4 fragment_windowing_color(VertexOut in [[stage_in]],
                                         texture2d<short> inputTexture [[texture(0)]],
                                         constant WindowingData& windowing [[buffer(0)]]) {
    
    constexpr sampler textureSampler(coord::normalized,
                                     filter::linear,
                                     address::clamp_to_edge);
    
    // Sample the signed 16-bit texture
    short pixelValue = inputTexture.sample(textureSampler, in.texCoord).r;
    float value = float(pixelValue);
    
    // Apply CT windowing
    float minValue = windowing.windowCenter - windowing.windowWidth / 2.0;
    float maxValue = windowing.windowCenter + windowing.windowWidth / 2.0;
    
    // Normalize to 0-1 range
    float normalizedValue = clamp((value - minValue) / (maxValue - minValue), 0.0, 1.0);
    
    // Create color mapping for different tissue types
    float3 color;
    
    if (normalizedValue < 0.2) {
        // Low density - dark blue to blue
        color = mix(float3(0.0, 0.0, 0.2), float3(0.0, 0.0, 0.8), normalizedValue * 5.0);
    } else if (normalizedValue < 0.4) {
        // Medium low density - blue to green
        color = mix(float3(0.0, 0.0, 0.8), float3(0.0, 0.8, 0.0), (normalizedValue - 0.2) * 5.0);
    } else if (normalizedValue < 0.6) {
        // Medium density - green to yellow
        color = mix(float3(0.0, 0.8, 0.0), float3(0.8, 0.8, 0.0), (normalizedValue - 0.4) * 5.0);
    } else if (normalizedValue < 0.8) {
        // Medium high density - yellow to red
        color = mix(float3(0.8, 0.8, 0.0), float3(0.8, 0.0, 0.0), (normalizedValue - 0.6) * 5.0);
    } else {
        // High density - red to white
        color = mix(float3(0.8, 0.0, 0.0), float3(1.0, 1.0, 1.0), (normalizedValue - 0.8) * 5.0);
    }
    
    return float4(color, 1.0);
}

// MARK: - Fragment Shader with Zoom and Pan Support

struct ViewTransform {
    float2 offset;
    float scale;
    float2 viewportSize;
};

fragment float4 fragment_windowing_transform(VertexOut in [[stage_in]],
                                            texture2d<short> inputTexture [[texture(0)]],
                                            constant WindowingData& windowing [[buffer(0)]],
                                            constant ViewTransform& transform [[buffer(1)]]) {
    
    constexpr sampler textureSampler(coord::normalized,
                                     filter::linear,
                                     address::clamp_to_edge);
    
    // Apply view transformation
    float2 transformedCoord = (in.texCoord - 0.5) * transform.scale + 0.5 + transform.offset;
    
    // Check if we're outside the texture bounds
    if (transformedCoord.x < 0.0 || transformedCoord.x > 1.0 ||
        transformedCoord.y < 0.0 || transformedCoord.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);  // Black for outside bounds
    }
    
    // Sample the signed 16-bit texture
    short pixelValue = inputTexture.sample(textureSampler, transformedCoord).r;
    float value = float(pixelValue);
    
    // Apply CT windowing
    float minValue = windowing.windowCenter - windowing.windowWidth / 2.0;
    float maxValue = windowing.windowCenter + windowing.windowWidth / 2.0;
    
    // Normalize to 0-1 range
    float normalizedValue = clamp((value - minValue) / (maxValue - minValue), 0.0, 1.0);
    
    // Return as grayscale
    return float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
}

// MARK: - Compute Shader for Histogram Generation

kernel void compute_histogram(texture2d<short, access::read> inputTexture [[texture(0)]],
                              device atomic_uint* histogram [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
    
    // Check bounds
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    // Read pixel value
    short pixelValue = inputTexture.read(gid).r;
    
    // Convert to histogram bin (assuming 4096 bins for 12-bit range)
    int binIndex = clamp(int(pixelValue + 2048), 0, 4095);  // Shift signed range to 0-4095
    
    // Atomically increment histogram bin
    atomic_fetch_add_explicit(&histogram[binIndex], 1, memory_order_relaxed);
}

// MARK: - Compute Shader for Statistics

struct ImageStatistics {
    float mean;
    float stdDev;
    short minValue;
    short maxValue;
};

kernel void compute_statistics(texture2d<short, access::read> inputTexture [[texture(0)]],
                              device ImageStatistics* stats [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
    
    // This would need to be implemented with multiple passes
    // First pass: calculate mean and find min/max
    // Second pass: calculate standard deviation
    
    // For now, this is a placeholder that would need proper implementation
    // using threadgroup memory and multiple kernel passes
}

// MARK: - CT Windowing Compute Shader (missing from your file)

struct WindowingParams {
    float windowCenter;
    float windowWidth;
    float rescaleSlope;
    float rescaleIntercept;
};

kernel void ctWindowing(
    texture2d<int, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant WindowingParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    // Read signed 16-bit CT pixel value
    int rawPixel = inputTexture.read(gid).r;
    
    // Convert raw pixel to Hounsfield Units (HU)
    float housefieldValue = float(rawPixel) * params.rescaleSlope + params.rescaleIntercept;
    
    // Apply CT windowing to Hounsfield Units
    float windowMin = params.windowCenter - (params.windowWidth * 0.5);
    float windowMax = params.windowCenter + (params.windowWidth * 0.5);
    
    // Clamp and normalize HU values to [0, 1] range
    float normalizedValue = (housefieldValue - windowMin) / (windowMax - windowMin);
    normalizedValue = clamp(normalizedValue, 0.0, 1.0);
    
    // Output as RGBA with proper medical grayscale
    float4 outputColor = float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
    
    outputTexture.write(outputColor, gid);
}

fragment float4 fragment_display_texture(VertexOut in [[stage_in]],
                                         texture2d<float> inputTexture [[texture(0)]]) {
    constexpr sampler textureSampler(coord::normalized,
                                     filter::linear,
                                     address::clamp_to_edge);
    
    // Sample and return the texture color directly
    return inputTexture.sample(textureSampler, in.texCoord);
}
