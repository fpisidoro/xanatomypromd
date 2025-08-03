#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

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

kernel void ct_windowing(texture2d<half, access::read> inputTexture [[texture(0)]],
                        texture2d<half, access::write> outputTexture [[texture(1)]],
                        constant float& windowCenter [[buffer(0)]],
                        constant float& windowWidth [[buffer(1)]],
                        constant float& rescaleSlope [[buffer(2)]],
                        constant float& rescaleIntercept [[buffer(3)]],
                        uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    half4 inputPixel = inputTexture.read(gid);
    float pixelValue = float(inputPixel.r);
    float hounsfield = pixelValue * rescaleSlope + rescaleIntercept;
    float windowMin = windowCenter - windowWidth / 2.0;
    float normalizedValue = clamp((hounsfield - windowMin) / windowWidth, 0.0, 1.0);
    half4 outputPixel = half4(half(normalizedValue), half(normalizedValue), half(normalizedValue), 1.0h);
    outputTexture.write(outputPixel, gid);
}

kernel void generate_mpr_slice(texture3d<float, access::sample> volumeTexture [[texture(0)]],
                              texture2d<float, access::write> outputTexture [[texture(1)]],
                              constant float& slicePosition [[buffer(0)]],
                              constant int& planeType [[buffer(1)]],
                              constant float& windowCenter [[buffer(2)]],
                              constant float& windowWidth [[buffer(3)]],
                              uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    constexpr sampler volumeSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float2 normalizedPos = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    float3 texCoord;
    if (planeType == 0) {
        texCoord = float3(normalizedPos.x, normalizedPos.y, slicePosition);
    } else if (planeType == 1) {
        texCoord = float3(slicePosition, normalizedPos.x, normalizedPos.y);
    } else {
        texCoord = float3(normalizedPos.x, slicePosition, normalizedPos.y);
    }
    
    float4 sampledValue = volumeTexture.sample(volumeSampler, texCoord);
    float hounsfield = sampledValue.r;
    float windowMin = windowCenter - windowWidth / 2.0;
    float normalizedValue = clamp((hounsfield - windowMin) / windowWidth, 0.0, 1.0);
    float4 outputPixel = float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
    outputTexture.write(outputPixel, gid);
}
