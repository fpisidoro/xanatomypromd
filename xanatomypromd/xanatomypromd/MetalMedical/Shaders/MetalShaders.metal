#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_simple(const device float4* vertices [[buffer(0)]], uint vid [[vertex_id]]) {
    VertexOut out;
    out.position = float4(vertices[vid].xy, 0.0, 1.0);
    out.texCoord = vertices[vid].zw;
    return out;
}

fragment float4 fragment_simple(VertexOut in [[stage_in]], texture2d<float> inputTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    return inputTexture.sample(textureSampler, in.texCoord);
}

// MPR Shader Parameters
struct MPRParams {
    uint planeType;           // 0=axial, 1=sagittal, 2=coronal
    float slicePosition;      // 0.0 to 1.0
    float windowCenter;
    float windowWidth;
    uint3 volumeDimensions;
    float3 spacing;
};

// Hardware-accelerated MPR slice extraction
kernel void mprSliceExtractionHardware(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Calculate normalized coordinates for volume sampling
    float2 normalizedCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // Calculate 3D texture coordinate based on plane type
    float3 volumeCoord;
    
    switch (params.planeType) {
        case 0: // Axial (XY plane, varying Z)
            volumeCoord = float3(normalizedCoord.x, normalizedCoord.y, params.slicePosition);
            break;
        case 1: // Sagittal (YZ plane, varying X)
            volumeCoord = float3(params.slicePosition, normalizedCoord.x, normalizedCoord.y);
            break;
        case 2: // Coronal (XZ plane, varying Y)
            volumeCoord = float3(normalizedCoord.x, params.slicePosition, normalizedCoord.y);
            break;
        default:
            volumeCoord = float3(normalizedCoord.x, normalizedCoord.y, params.slicePosition);
            break;
    }
    
    // Sample the volume texture
    short rawValue = volumeTexture.read(uint3(volumeCoord * float3(params.volumeDimensions))).r;
    
    // Convert to Hounsfield Units and apply windowing
    float hounsfield = float(rawValue);
    
    // Apply CT windowing
    float windowMin = params.windowCenter - params.windowWidth / 2.0;
    float windowMax = params.windowCenter + params.windowWidth / 2.0;
    
    float windowedValue = clamp((hounsfield - windowMin) / (windowMax - windowMin), 0.0, 1.0);
    
    // Output grayscale value
    outputTexture.write(float4(windowedValue, windowedValue, windowedValue, 1.0), gid);
}

// MARK: - 3D Volume Rendering Shaders

struct Volume3DRenderParams {
    float rotationZ;
    float3 crosshairPosition;
    float windowCenter;
    float windowWidth;
    float zoom;
    float panX;
    float panY;
};

// Alpha transfer function for volume rendering - balanced visibility
float getAlphaForHU(float hu) {
    if (hu < -800) return 0.0;          // Air
    if (hu < -100) return 0.05;         // Fat - slightly visible
    if (hu < 50) return 0.08;           // Soft tissue - low opacity
    if (hu < 100) return 0.15;          // Muscle - moderate
    if (hu < 200) return 0.25;          // Dense tissue
    if (hu < 400) return 0.4;           // Bone
    return 0.6;                         // Dense bone
}

// Color mapping for tissues
float3 getColorForHU(float hu) {
    if (hu < -800) return float3(0.0, 0.0, 0.0);        // Air
    if (hu < -100) return float3(0.8, 0.6, 0.3);        // Fat
    if (hu < 50) return float3(0.9, 0.7, 0.6);          // Soft tissue
    if (hu < 200) return float3(0.8, 0.3, 0.3);         // Muscle
    return float3(1.0, 0.9, 0.8);                       // Bone
}

// Ray-box intersection
float2 rayBoxIntersect(float3 rayOrigin, float3 rayDir, float3 boxMin, float3 boxMax) {
    float3 invDir = 1.0 / rayDir;
    float3 t1 = (boxMin - rayOrigin) * invDir;
    float3 t2 = (boxMax - rayOrigin) * invDir;
    
    float3 tMin = min(t1, t2);
    float3 tMax = max(t1, t2);
    
    float tNear = max(max(tMin.x, tMin.y), tMin.z);
    float tFar = min(min(tMax.x, tMax.y), tMax.z);
    
    return float2(tNear, tFar);
}

// Diagnostic version - test volume data directly
kernel void volumeRender3D(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant Volume3DRenderParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Test: directly sample volume at various locations
    uint3 volumeDim = uint3(volumeTexture.get_width(), volumeTexture.get_height(), volumeTexture.get_depth());
    
    // Sample center of volume
    uint3 centerPos = volumeDim / 2;
    short centerValue = volumeTexture.read(centerPos).r;
    
    // Sample corner of volume  
    uint3 cornerPos = uint3(volumeDim.x / 4, volumeDim.y / 4, volumeDim.z / 2);
    short cornerValue = volumeTexture.read(cornerPos).r;
    
    // Map screen position to different volume samples
    float2 uv = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    uint3 testPos = uint3(uv.x * float(volumeDim.x), uv.y * float(volumeDim.y), volumeDim.z / 2);
    testPos = min(testPos, volumeDim - 1);
    short testValue = volumeTexture.read(testPos).r;
    
    // Show raw values as colors
    float normalizedValue = (float(testValue) + 1000.0) / 3000.0; // Map typical CT range to 0-1
    normalizedValue = clamp(normalizedValue, 0.0, 1.0);
    
    // Color code the output
    float3 color;
    if (normalizedValue < 0.1) {
        color = float3(0.0, 0.0, 1.0); // Blue for air/low density
    } else if (normalizedValue < 0.5) {
        color = float3(0.0, 1.0, 0.0); // Green for soft tissue
    } else {
        color = float3(1.0, 0.0, 0.0); // Red for bone/high density
    }
    
    outputTexture.write(float4(color, 1.0), gid);
}
