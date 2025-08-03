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

vertex VertexOut vertex_simple(const device float4* vertices [[buffer(0)]],
                              uint vid [[vertex_id]]) {
    VertexOut out;
    
    float4 vertex = vertices[vid];
    out.position = float4(vertex.xy, 0.0, 1.0);
    out.texCoord = vertex.zw;
    
    return out;
}

fragment float4 fragment_simple(VertexOut in [[stage_in]],
                               texture2d<float> inputTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float4 color = inputTexture.sample(textureSampler, in.texCoord);
    
    return color;
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
