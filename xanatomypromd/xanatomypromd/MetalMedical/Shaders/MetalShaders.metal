#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct AspectRatioUniforms {
    float scaleX;
    float scaleY;
    float2 offset;
};

vertex VertexOut vertex_simple(const device float4* vertices [[buffer(0)]],
                              uint vid [[vertex_id]]) {
    VertexOut out;
    
    float4 vertex = vertices[vid];
    out.position = float4(vertex.xy, 0.0, 1.0);
    out.texCoord = vertex.zw;
    
    return out;
}

vertex VertexOut vertex_main(const device float4* vertices [[buffer(0)]],
                            const device AspectRatioUniforms* aspectUniforms [[buffer(1)]],
                            uint vid [[vertex_id]]) {
    VertexOut out;
    
    float4 vertex = vertices[vid];
    float2 position = vertex.xy;
    
    if (aspectUniforms != nullptr) {
        position.x *= aspectUniforms->scaleX;
        position.y *= aspectUniforms->scaleY;
        position += aspectUniforms->offset;
    }
    
    out.position = float4(position, 0.0, 1.0);
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
    constexpr sampler textureSampler(mag_filter::linear, 
                                   min_filter::linear,
                                   address::clamp_to_edge);
    
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
    float windowMax = windowCenter + windowWidth / 2.0;
    
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
    
    constexpr sampler volumeSampler(mag_filter::linear,
                                   min_filter::linear,
                                   mip_filter::linear,
                                   address::clamp_to_edge);
    
    float2 normalizedPos = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    float3 texCoord;
    switch (planeType) {
        case 0:
            texCoord = float3(normalizedPos.x, normalizedPos.y, slicePosition);
            break;
        case 1:
            texCoord = float3(slicePosition, normalizedPos.x, normalizedPos.y);
            break;
        case 2:
            texCoord = float3(normalizedPos.x, slicePosition, normalizedPos.y);
            break;
        default:
            texCoord = float3(normalizedPos.x, normalizedPos.y, slicePosition);
            break;
    }
    
    float4 sampledValue = volumeTexture.sample(volumeSampler, texCoord);
    float hounsfield = sampledValue.r;
    
    float windowMin = windowCenter - windowWidth / 2.0;
    float windowMax = windowCenter + windowWidth / 2.0;
    
    float normalizedValue = clamp((hounsfield - windowMin) / windowWidth, 0.0, 1.0);
    
    float4 outputPixel = float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
    outputTexture.write(outputPixel, gid);
}

kernel void generate_mpr_slice_manual(texture3d<half, access::read> volumeTexture [[texture(0)]],
                                     texture2d<half, access::write> outputTexture [[texture(1)]],
                                     constant float& slicePosition [[buffer(0)]],
                                     constant int& planeType [[buffer(1)]],
                                     constant float& windowCenter [[buffer(2)]],
                                     constant float& windowWidth [[buffer(3)]],
                                     uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    uint3 volumeDims = uint3(volumeTexture.get_width(), volumeTexture.get_height(), volumeTexture.get_depth());
    
    float2 normalizedPos = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    float3 volumeCoord;
    switch (planeType) {
        case 0:
            volumeCoord = float3(normalizedPos.x, normalizedPos.y, slicePosition) * float3(volumeDims);
            break;
        case 1:
            volumeCoord = float3(slicePosition, normalizedPos.x, normalizedPos.y) * float3(volumeDims);
            break;
        case 2:
            volumeCoord = float3(normalizedPos.x, slicePosition, normalizedPos.y) * float3(volumeDims);
            break;
        default:
            volumeCoord = float3(normalizedPos.x, normalizedPos.y, slicePosition) * float3(volumeDims);
            break;
    }
    
    volumeCoord = clamp(volumeCoord, float3(0.0), float3(volumeDims) - 1.0);
    
    uint3 coord0 = uint3(floor(volumeCoord));
    uint3 coord1 = min(coord0 + 1, volumeDims - 1);
    float3 t = volumeCoord - float3(coord0);
    
    half v000 = volumeTexture.read(uint3(coord0.x, coord0.y, coord0.z)).r;
    half v001 = volumeTexture.read(uint3(coord0.x, coord0.y, coord1.z)).r;
    half v010 = volumeTexture.read(uint3(coord0.x, coord1.y, coord0.z)).r;
    half v011 = volumeTexture.read(uint3(coord0.x, coord1.y, coord1.z)).r;
    half v100 = volumeTexture.read(uint3(coord1.x, coord0.y, coord0.z)).r;
    half v101 = volumeTexture.read(uint3(coord1.x, coord0.y, coord1.z)).r;
    half v110 = volumeTexture.read(uint3(coord1.x, coord1.y, coord0.z)).r;
    half v111 = volumeTexture.read(uint3(coord1.x, coord1.y, coord1.z)).r;
    
    half v00 = mix(v000, v001, half(t.z));
    half v01 = mix(v010, v011, half(t.z));
    half v10 = mix(v100, v101, half(t.z));
    half v11 = mix(v110, v111, half(t.z));
    
    half v0 = mix(v00, v01, half(t.y));
    half v1 = mix(v10, v11, half(t.y));
    
    half finalValue = mix(v0, v1, half(t.x));
    float hounsfield = float(finalValue);
    
    float windowMin = windowCenter - windowWidth / 2.0;
    float windowMax = windowCenter + windowWidth / 2.0;
    
    float normalizedValue = clamp((hounsfield - windowMin) / windowWidth, 0.0, 1.0);
    
    half4 outputPixel = half4(half(normalizedValue), half(normalizedValue), half(normalizedValue), 1.0h);
    outputTexture.write(outputPixel, gid);
}
