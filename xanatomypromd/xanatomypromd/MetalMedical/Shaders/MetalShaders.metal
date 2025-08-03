#include <metal_stdlib>
using namespace metal;

// MARK: - Simple Vertex and Fragment Shaders for Basic Display

struct SimpleVertexIn {
    float2 position;
    float2 texCoord;
};

struct SimpleVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Simple vertex shader without aspect ratio complications
vertex SimpleVertexOut vertex_simple(const device float4* vertices [[buffer(0)]],
                                     uint vid [[vertex_id]]) {
    SimpleVertexOut out;
    out.position = float4(vertices[vid].xy, 0.0, 1.0);
    out.texCoord = vertices[vid].zw;
    return out;
}

// Simple fragment shader for texture display
fragment float4 fragment_simple(SimpleVertexOut in [[stage_in]],
                               texture2d<float> inputTexture [[texture(0)]]) {
    constexpr sampler textureSampler(coord::normalized,
                                     filter::linear,
                                     address::clamp_to_edge);
    
    return inputTexture.sample(textureSampler, in.texCoord);
}

// MARK: - Crosshair Vertex and Fragment Shaders

struct CrosshairVertexOut {
    float4 position [[position]];
    float4 color;
};

// Vertex shader for crosshairs
vertex CrosshairVertexOut vertex_crosshair(const device float4* vertices [[buffer(0)]],
                                           const device float4* colors [[buffer(1)]],
                                           uint vid [[vertex_id]]) {
    CrosshairVertexOut out;
    out.position = vertices[vid];
    out.color = colors[vid];
    return out;
}

// Fragment shader for crosshairs
fragment float4 fragment_crosshair(CrosshairVertexOut in [[stage_in]]) {
    return in.color;
}

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

// MARK: - Aspect Ratio Correction

struct AspectRatioUniforms {
    float scaleX;
    float scaleY;
    float2 offset;
};

// MARK: - MPR Shader Parameters

struct MPRParams {
    uint planeType;              // 0=axial, 1=sagittal, 2=coronal
    float slicePosition;         // 0.0 to 1.0 normalized position
    float windowCenter;
    float windowWidth;
    uint3 volumeDimensions;
    float3 spacing;
};

// MARK: - View Transform for Zoom/Pan

struct ViewTransform {
    float2 offset;
    float scale;
    float2 viewportSize;
};

// MARK: - CT Windowing Parameters

struct WindowingParams {
    float windowCenter;
    float windowWidth;
    float rescaleSlope;
    float rescaleIntercept;
};

// MARK: - Vertex Shader with Aspect Ratio Correction

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

// MARK: - CT Windowing Fragment Shaders

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

fragment float4 fragment_display_texture(VertexOut in [[stage_in]],
                                         texture2d<float> inputTexture [[texture(0)]]) {
    constexpr sampler textureSampler(coord::normalized,
                                     filter::linear,
                                     address::clamp_to_edge);
    
    // Sample and return the texture color directly
    return inputTexture.sample(textureSampler, in.texCoord);
}

// MARK: - CT Windowing Compute Shader

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

// MARK: - Hardware Accelerated 3D Volume Sampling for MPR

float sampleVolume3DHardware(texture3d<short, access::sample> volume,
                           float3 texCoord) {
    constexpr sampler volumeSampler(
        coord::normalized,
        filter::linear,
        address::clamp_to_edge
    );
    
    // Hardware-accelerated trilinear sampling with SHORT format
    short4 sampledValue = volume.sample(volumeSampler, texCoord);
    return float(sampledValue.r);  // Convert short to float for processing
}

// MARK: - CT Windowing Function for MPR

float4 applyWindowing(float ctValue, float windowCenter, float windowWidth) {
    float minValue = windowCenter - windowWidth / 2.0;
    
    // Normalize to [0, 1] range
    float normalizedValue = clamp((ctValue - minValue) / windowWidth, 0.0, 1.0);
    
    // Return as grayscale RGBA
    return float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
}

// MARK: - Hardware Accelerated MPR Compute Shaders

kernel void mprSliceExtractionHardware(
    texture3d<short, access::sample> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Convert output pixel coordinates to normalized [0,1] range
    float2 outputCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // Calculate 3D texture coordinate based on plane type
    float3 volumeCoord;
    
    switch (params.planeType) {
        case 0: // Axial (XY plane at fixed Z)
            volumeCoord = float3(outputCoord.x, outputCoord.y, params.slicePosition);
            break;
            
        case 1: // Sagittal (YZ plane at fixed X)
            volumeCoord = float3(params.slicePosition, outputCoord.x, outputCoord.y);
            break;
            
        case 2: // Coronal (XZ plane at fixed Y)
            volumeCoord = float3(outputCoord.x, params.slicePosition, outputCoord.y);
            break;
            
        default:
            volumeCoord = float3(0.5, 0.5, 0.5);
            break;
    }
    
    // Hardware accelerated sampling
    float ctValue = sampleVolume3DHardware(volumeTexture, volumeCoord);
    
    // Apply CT windowing
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    // Write to output texture
    outputTexture.write(windowedColor, gid);
}

kernel void mprAxialSliceHardware(
    texture3d<short, access::sample> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float2 texCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    float3 volumeCoord = float3(texCoord.x, texCoord.y, params.slicePosition);
    
    float ctValue = sampleVolume3DHardware(volumeTexture, volumeCoord);
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    outputTexture.write(windowedColor, gid);
}

kernel void mprSagittalSliceHardware(
    texture3d<short, access::sample> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float2 texCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    float3 volumeCoord = float3(params.slicePosition, texCoord.x, texCoord.y);
    
    float ctValue = sampleVolume3DHardware(volumeTexture, volumeCoord);
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    outputTexture.write(windowedColor, gid);
}

kernel void mprCoronalSliceHardware(
    texture3d<short, access::sample> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float2 texCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    float3 volumeCoord = float3(texCoord.x, params.slicePosition, texCoord.y);
    
    float ctValue = sampleVolume3DHardware(volumeTexture, volumeCoord);
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    outputTexture.write(windowedColor, gid);
}

// MARK: - GPU Zoom/Pan Fragment Shader for MPR

fragment float4 fragment_mpr_windowing_transform(
    VertexOut in [[stage_in]],
    texture3d<short, access::sample> inputTexture [[texture(0)]],
    constant MPRParams& params [[buffer(0)]],
    constant ViewTransform& transform [[buffer(1)]]
) {
    constexpr sampler textureSampler(
        coord::normalized,
        filter::linear,
        address::clamp_to_edge
    );
    
    // Apply view transformation
    float2 transformedCoord = (in.texCoord - 0.5) * transform.scale + 0.5 + transform.offset;
    
    // Check if we're outside the texture bounds
    if (transformedCoord.x < 0.0 || transformedCoord.x > 1.0 ||
        transformedCoord.y < 0.0 || transformedCoord.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);  // Black for outside bounds
    }
    
    // Calculate 3D coordinate based on plane
    float3 volumeCoord;
    switch (params.planeType) {
        case 0: // Axial
            volumeCoord = float3(transformedCoord.x, transformedCoord.y, params.slicePosition);
            break;
        case 1: // Sagittal
            volumeCoord = float3(params.slicePosition, transformedCoord.x, transformedCoord.y);
            break;
        case 2: // Coronal
            volumeCoord = float3(transformedCoord.x, params.slicePosition, transformedCoord.y);
            break;
        default:
            volumeCoord = float3(0.5, 0.5, 0.5);
            break;
    }
    
    // Sample the SHORT texture and convert to float
    short4 sampledValue = inputTexture.sample(textureSampler, volumeCoord);
    float ctValue = float(sampledValue.r);
    
    // Apply CT windowing
    float minValue = params.windowCenter - params.windowWidth / 2.0;
    float maxValue = params.windowCenter + params.windowWidth / 2.0;
    
    // Normalize to 0-1 range
    float normalizedValue = clamp((ctValue - minValue) / (maxValue - minValue), 0.0, 1.0);
    
    // Return as grayscale
    return float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
}

// MARK: - Histogram Generation

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
