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
