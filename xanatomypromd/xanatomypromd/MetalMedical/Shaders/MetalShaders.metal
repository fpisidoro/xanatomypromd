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

// Alpha transfer function - optimized to hide skin surface
float getAlphaForHU(float hu) {
    // Completely transparent: air and bed (very low HU)
    if (hu < -800) return 0.0;          // Air, bed materials
    
    // Mostly transparent: fat and soft tissue (hide skin surface)
    if (hu < -100) return 0.02;         // Fat - barely visible
    if (hu < 50) return 0.05;           // Soft tissue/skin - very transparent
    
    // Semi-transparent: muscle and organs
    if (hu < 100) return 0.15;          // Muscle - somewhat visible
    if (hu < 200) return 0.35;          // Denser soft tissue
    
    // More opaque: bone and dense structures
    if (hu < 400) return 0.6;           // Cancellous bone
    return 0.85;                        // Cortical bone - most visible
}

// Color mapping for different tissue types
float3 getColorForHU(float hu) {
    if (hu < -800) return float3(0.0, 0.0, 0.0);        // Air - black
    if (hu < -100) return float3(0.8, 0.6, 0.3);        // Fat - yellowish
    if (hu < 50) return float3(0.9, 0.7, 0.6);          // Soft tissue - pink
    if (hu < 200) return float3(0.8, 0.3, 0.3);         // Muscle - red
    return float3(1.0, 0.9, 0.8);                       // Bone - white
}

// Ray-volume intersection
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

// Simple test kernel - replace complex volume rendering temporarily
kernel void volumeRender3DTest(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant Volume3DRenderParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Simple test pattern
    float2 uv = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // Test: show gradient instead of volume
    float3 testColor = float3(uv.x, uv.y, 0.5);
    outputTexture.write(float4(testColor, 1.0), gid);
}

// 3D Volume Rendering Kernel
kernel void volumeRender3D(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant Volume3DRenderParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    uint3 volumeDim = uint3(volumeTexture.get_width(), volumeTexture.get_height(), volumeTexture.get_depth());
    float3 volumeSize = float3(volumeDim);
    
    // Screen coordinates to normalized device coordinates
    float2 ndc = (float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height())) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y for correct orientation
    
    // Apply zoom and pan
    ndc /= params.zoom;
    ndc.x += params.panX / params.zoom;
    ndc.y += params.panY / params.zoom;
    
    // Camera setup - anterior view (looking along -Y axis)
    float3 cameraPos = float3(0.0, 2.0, 0.0);  // Camera in front
    float3 target = float3(0.0, 0.0, 0.0);     // Looking at center
    float3 up = float3(0.0, 0.0, 1.0);         // Z is up
    
    // Apply Z-axis rotation
    float cosR = cos(params.rotationZ);
    float sinR = sin(params.rotationZ);
    float3x3 rotationMatrix = float3x3(
        float3(cosR, -sinR, 0.0),
        float3(sinR, cosR, 0.0),
        float3(0.0, 0.0, 1.0)
    );
    
    cameraPos = rotationMatrix * cameraPos;
    up = rotationMatrix * up;
    
    // Create view matrix
    float3 forward = normalize(target - cameraPos);
    float3 right = normalize(cross(forward, up));
    up = cross(right, forward);
    
    // Ray direction
    float3 rayDir = normalize(forward + ndc.x * right * 0.5 + ndc.y * up * 0.5);
    
    // Volume bounding box in normalized coordinates
    float3 boxMin = float3(-0.5, -0.5, -0.5);
    float3 boxMax = float3(0.5, 0.5, 0.5);
    
    // Ray-box intersection
    float2 tRange = rayBoxIntersect(cameraPos, rayDir, boxMin, boxMax);
    
    if (tRange.x > tRange.y || tRange.y < 0.0) {
        outputTexture.write(float4(0.0, 0.0, 0.0, 1.0), gid);
        return;
    }
    
    // Ray marching parameters
    float tStart = max(tRange.x, 0.0);
    float tEnd = tRange.y;
    float stepSize = 0.01;  // Small steps for good quality
    int maxSteps = int((tEnd - tStart) / stepSize) + 1;
    
    // Accumulated color and alpha
    float3 accumulatedColor = float3(0.0);
    float accumulatedAlpha = 0.0;
    
    // Ray marching
    for (int i = 0; i < maxSteps && accumulatedAlpha < 0.95; i++) {
        float t = tStart + float(i) * stepSize;
        float3 samplePos = cameraPos + t * rayDir;
        
        // Convert to texture coordinates (normalized 0-1)
        float3 texCoord = samplePos + 0.5; // Convert from [-0.5, 0.5] to [0, 1]
        
        if (all(texCoord >= 0.0) && all(texCoord <= 1.0)) {
            // Sample volume with proper coordinate scaling
            uint3 volumeDim = uint3(volumeTexture.get_width(), volumeTexture.get_height(), volumeTexture.get_depth());
            uint3 sampleIdx = uint3(texCoord * float3(volumeDim));
            
            // Clamp to valid range
            sampleIdx = min(sampleIdx, volumeDim - 1);
            
            short rawValue = volumeTexture.read(sampleIdx).r;
            float hounsfield = float(rawValue);
            
            // Apply windowing
            float windowMin = params.windowCenter - params.windowWidth / 2.0;
            float windowMax = params.windowCenter + params.windowWidth / 2.0;
            float windowed = clamp((hounsfield - windowMin) / (windowMax - windowMin), 0.0, 1.0);
            
            // Get alpha and color for this HU value
            float alpha = getAlphaForHU(hounsfield) * stepSize * 100.0; // Scale by step size
            float3 color = getColorForHU(hounsfield) * windowed;
            
            // Front-to-back compositing
            accumulatedColor += color * alpha * (1.0 - accumulatedAlpha);
            accumulatedAlpha += alpha * (1.0 - accumulatedAlpha);
        }
    }
    
    // Add crosshair planes if enabled
    float3 crosshairColor = float3(0.0, 1.0, 0.0); // Green crosshair planes
    float planeThickness = 0.02;
    
    // Check if ray intersects crosshair planes
    for (int i = 0; i < maxSteps; i++) {
        float t = tStart + float(i) * stepSize;
        float3 samplePos = cameraPos + t * rayDir;
        
        // Normalize crosshair position to [-0.5, 0.5] space
        float3 normalizedCrosshair = (params.crosshairPosition / volumeSize) - 0.5;
        
        // Check proximity to crosshair planes
        bool nearXPlane = abs(samplePos.x - normalizedCrosshair.x) < planeThickness;
        bool nearYPlane = abs(samplePos.y - normalizedCrosshair.y) < planeThickness;
        bool nearZPlane = abs(samplePos.z - normalizedCrosshair.z) < planeThickness;
        
        if (nearXPlane || nearYPlane || nearZPlane) {
            float planeAlpha = 0.3 * (1.0 - accumulatedAlpha);
            accumulatedColor += crosshairColor * planeAlpha;
            accumulatedAlpha += planeAlpha;
            break;
        }
    }
    
    // Final color with black background
    float3 finalColor = accumulatedColor + float3(0.0) * (1.0 - accumulatedAlpha);
    outputTexture.write(float4(finalColor, 1.0), gid);
}
