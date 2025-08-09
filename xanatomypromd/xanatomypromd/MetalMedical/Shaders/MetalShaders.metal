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

// 3D Volume Rendering - Coronal view with Z rotation
kernel void volumeRender3D(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant Volume3DRenderParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Screen coordinates to normalized device coordinates [-1, 1]
    float2 ndc = (float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height())) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y
    
    // Apply rotation around Z axis
    float cosZ = cos(params.rotationZ);
    float sinZ = sin(params.rotationZ);
    float2 rotatedNdc = float2(
        ndc.x * cosZ - ndc.y * sinZ,
        ndc.x * sinZ + ndc.y * cosZ
    );
    
    // Volume dimensions and setup
    uint3 volumeDim = uint3(volumeTexture.get_width(), volumeTexture.get_height(), volumeTexture.get_depth());
    
    float3 accumulatedColor = float3(0.0);
    float accumulatedAlpha = 0.0;
    
    // Ray march through volume in CORONAL direction (Y-axis)
    // Coronal view: looking from anterior to posterior
    int numSteps = int(volumeDim.y);
    
    for (int step = 0; step < numSteps && accumulatedAlpha < 0.95; step++) {
        // Map to volume coordinates for coronal view
        // X = left-right, Y = anterior-posterior (ray direction), Z = superior-inferior
        float3 volumePos = float3(
            (rotatedNdc.x + 1.0) * 0.5 * float(volumeDim.x),  // X: left-right
            float(step),                                        // Y: anterior-posterior (ray direction)
            (rotatedNdc.y + 1.0) * 0.5 * float(volumeDim.z)   // Z: superior-inferior
        );
        
        // Clamp to volume bounds
        uint3 samplePos = uint3(
            min(uint(volumePos.x), volumeDim.x - 1),
            min(uint(volumePos.y), volumeDim.y - 1),
            min(uint(volumePos.z), volumeDim.z - 1)
        );
        
        // Sample volume
        short rawValue = volumeTexture.read(samplePos).r;
        float hounsfield = float(rawValue);
        
        // Apply windowing
        float windowMin = params.windowCenter - params.windowWidth / 2.0;
        float windowMax = params.windowCenter + params.windowWidth / 2.0;
        float windowed = clamp((hounsfield - windowMin) / (windowMax - windowMin), 0.0, 1.0);
        
        // Get alpha and color based on tissue type
        float alpha = 0.0;
        float3 color = float3(0.0);
        
        if (hounsfield > 200) {  // Bone
            alpha = 0.4;
            color = float3(1.0, 0.9, 0.8) * windowed;
        } else if (hounsfield > 50) {  // Dense tissue
            alpha = 0.1;
            color = float3(0.8, 0.3, 0.3) * windowed;
        } else if (hounsfield > -100) {  // Soft tissue
            alpha = 0.03;
            color = float3(0.9, 0.7, 0.6) * windowed;
        }
        // Air and fat are transparent
        
        // Front-to-back compositing
        float stepAlpha = alpha / float(numSteps) * 50.0;  // Normalize for step count
        accumulatedColor += color * stepAlpha * (1.0 - accumulatedAlpha);
        accumulatedAlpha += stepAlpha * (1.0 - accumulatedAlpha);
    }
    
    // Final output
    float3 finalColor = accumulatedColor;
    outputTexture.write(float4(finalColor, 1.0), gid);
}
