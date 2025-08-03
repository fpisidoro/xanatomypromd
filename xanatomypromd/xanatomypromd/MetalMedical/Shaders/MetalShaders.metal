#include <metal_stdlib>
using namespace metal;

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

struct AspectRatioUniforms {
    float scaleX;
    float scaleY;
    float2 offset;
};

struct MPRParams {
    uint planeType;              
    float slicePosition;         
    float windowCenter;
    float windowWidth;
    uint3 volumeDimensions;
    float3 spacing;
};

struct ViewTransform {
    float2 offset;
    float scale;
    float2 viewportSize;
};

struct WindowingParams {
    float windowCenter;
    float windowWidth;
    float rescaleSlope;
    float rescaleIntercept;
};

vertex VertexOut vertex_main(const device float4* vertices [[buffer(0)]],
                             constant AspectRatioUniforms& aspectRatio [[buffer(1)]],
                             uint vid [[vertex_id]]) {
    VertexOut out;
    
    float2 originalPos = vertices[vid].xy;
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
    
    return inputTexture.sample(textureSampler, in.texCoord);
}

kernel void ctWindowing(
    texture2d<int, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant WindowingParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    int rawPixel = inputTexture.read(gid).r;
    float housefieldValue = float(rawPixel) * params.rescaleSlope + params.rescaleIntercept;
    
    float windowMin = params.windowCenter - (params.windowWidth * 0.5);
    float windowMax = params.windowCenter + (params.windowWidth * 0.5);
    
    float normalizedValue = (housefieldValue - windowMin) / (windowMax - windowMin);
    normalizedValue = clamp(normalizedValue, 0.0, 1.0);
    
    float4 outputColor = float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
    
    outputTexture.write(outputColor, gid);
}

float sampleVolume3DHardware(texture3d<short, access::sample> volume,
                           float3 texCoord) {
    constexpr sampler volumeSampler(
        coord::normalized,
        filter::linear,
        address::clamp_to_edge
    );
    
    short4 sampledValue = volume.sample(volumeSampler, texCoord);
    return float(sampledValue.r);  
}

float4 applyWindowing(float ctValue, float windowCenter, float windowWidth) {
    float minValue = windowCenter - windowWidth / 2.0;
    float normalizedValue = clamp((ctValue - minValue) / windowWidth, 0.0, 1.0);
    return float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
}

kernel void mprSliceExtractionHardware(
    texture3d<short, access::sample> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float2 outputCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    float3 volumeCoord;
    
    if (params.planeType == 0) {
        volumeCoord = float3(outputCoord.x, outputCoord.y, params.slicePosition);
    } else if (params.planeType == 1) {
        volumeCoord = float3(params.slicePosition, outputCoord.x, outputCoord.y);
    } else if (params.planeType == 2) {
        volumeCoord = float3(outputCoord.x, params.slicePosition, outputCoord.y);
    } else {
        volumeCoord = float3(0.5, 0.5, 0.5);
    }
    
    float ctValue = sampleVolume3DHardware(volumeTexture, volumeCoord);
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    outputTexture.write(windowedColor, gid);
}
