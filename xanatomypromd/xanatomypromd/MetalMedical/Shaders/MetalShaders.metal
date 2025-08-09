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

// 3D Volume Rendering with ray casting
kernel void volumeRender3D(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant Volume3DRenderParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Screen coordinates to normalized device coordinates
    float2 ndc = (float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height())) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y for correct orientation
    
    // Apply zoom and pan
    ndc /= params.zoom;
    ndc.x += params.panX / params.zoom;
    ndc.y += params.panY / params.zoom;
    
    // Create camera and ray
    float3 cameraPos = float3(0.0, 0.0, -1.5);
    float3 rayDir = normalize(float3(ndc.x, ndc.y, 1.0));
    
    // Apply rotation around Z axis
    float cosZ = cos(params.rotationZ);
    float sinZ = sin(params.rotationZ);
    float3x3 rotationMatrix = float3x3(
        float3(cosZ, -sinZ, 0.0),
        float3(sinZ, cosZ, 0.0),
        float3(0.0, 0.0, 1.0)
    );
    
    cameraPos = rotationMatrix * cameraPos;
    rayDir = rotationMatrix * rayDir;
    
    // Volume bounds [-0.5, 0.5]
    float3 volumeMin = float3(-0.5, -0.5, -0.5);
    float3 volumeMax = float3(0.5, 0.5, 0.5);
    
    // Ray-volume intersection
    float2 intersection = rayBoxIntersect(cameraPos, rayDir, volumeMin, volumeMax);
    float tStart = max(intersection.x, 0.0);
    float tEnd = intersection.y;
    
    // Debug: if no intersection, show red instead of black
    if (tStart >= tEnd) {
        outputTexture.write(float4(1.0, 0.0, 0.0, 1.0), gid); // Red for debugging
        return;
    }
    
    // Ray marching
    float stepSize = 0.01;
    int maxSteps = int((tEnd - tStart) / stepSize) + 1;
    
    float3 accumulatedColor = float3(0.0);
    float accumulatedAlpha = 0.0;
    
    uint3 volumeDim = uint3(volumeTexture.get_width(), volumeTexture.get_height(), volumeTexture.get_depth());
    
    for (int i = 0; i < maxSteps && accumulatedAlpha < 0.95; i++) {
        float t = tStart + float(i) * stepSize;
        float3 samplePos = cameraPos + t * rayDir;
        
        // Convert to texture coordinates [0,1]
        float3 texCoord = samplePos + 0.5;
        
        if (all(texCoord >= 0.0) && all(texCoord <= 1.0)) {
            // Sample volume
            uint3 sampleIdx = uint3(texCoord * float3(volumeDim));
            sampleIdx = min(sampleIdx, volumeDim - 1);
            
            short rawValue = volumeTexture.read(sampleIdx).r;
            float hounsfield = float(rawValue);
            
            // Apply windowing
            float windowMin = params.windowCenter - params.windowWidth / 2.0;
            float windowMax = params.windowCenter + params.windowWidth / 2.0;
            float windowed = clamp((hounsfield - windowMin) / (windowMax - windowMin), 0.0, 1.0);
            
            // Get alpha and color
            float alpha = getAlphaForHU(hounsfield) * stepSize * 80.0;  // Reduced from 200 to 80
            float3 color = getColorForHU(hounsfield) * windowed;
            
            // Compositing
            accumulatedColor += color * alpha * (1.0 - accumulatedAlpha);
            accumulatedAlpha += alpha * (1.0 - accumulatedAlpha);
        }
    }
    
    // Final output - if no accumulation happened, show green for debugging
    if (accumulatedAlpha <= 0.001) {
        outputTexture.write(float4(0.0, 1.0, 0.0, 1.0), gid); // Green = ray marched but found nothing
        return;
    }
    
    float3 finalColor = accumulatedColor;
    outputTexture.write(float4(finalColor, 1.0), gid);
}
