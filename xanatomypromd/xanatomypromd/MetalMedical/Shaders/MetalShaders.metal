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

// Simple struct matching Swift - just floats, no SIMD types
struct Volume3DRenderParams {
    float rotationZ;
    float windowCenter;
    float windowWidth;
    float zoom;
    float panX;
    float panY;
    float spacingX;
    float spacingY;
    float spacingZ;
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
    // Don't flip Y - keep image right-side up
    
    // Volume dimensions and setup
    uint3 volumeDim = uint3(volumeTexture.get_width(), volumeTexture.get_height(), volumeTexture.get_depth());
    
    // Apply zoom and pan
    float2 viewNdc = ndc / params.zoom - float2(params.panX, params.panY) / (params.zoom * 100.0);
    
    float3 accumulatedColor = float3(0.0);
    float accumulatedAlpha = 0.0;
    
    // Volume center for rotation - in voxel space
    float3 volumeCenter = float3(volumeDim) * 0.5;
    
    // Physical volume dimensions in mm
    float3 physicalDimensions = float3(volumeDim) * float3(params.spacingX, params.spacingY, params.spacingZ);
    
    // Apply Z-axis rotation to viewing direction (calculate once)
    float cosZ = cos(params.rotationZ);
    float sinZ = sin(params.rotationZ);
    
    // Ray march through volume along Y-axis (anterior-posterior)
    int numSteps = int(volumeDim.y);
    
    for (int step = 0; step < numSteps && accumulatedAlpha < 0.95; step++) {
        // The volume is 512x512x53 but Z voxels are ~4.74x thicker
        // So 53 Z voxels = ~251 X voxels worth of physical distance
        // Map screen Y to only the equivalent X-distance worth of Z voxels
        float physicallyEquivalentZ = float(volumeDim.z) * params.spacingZ / params.spacingX; // ~251
        float zCenter = float(volumeDim.z) * 0.5;
        
        float3 basePos = float3(
            (viewNdc.x + 1.0) * 0.5 * float(volumeDim.x),
            float(step),
            zCenter + viewNdc.y * physicallyEquivalentZ * 0.5
        );
        
        // Apply rotation around Z-axis
        float3 offsetFromCenter = basePos - volumeCenter;
        float3 rotatedOffset = float3(
            offsetFromCenter.x * cosZ - offsetFromCenter.y * sinZ,
            offsetFromCenter.x * sinZ + offsetFromCenter.y * cosZ,
            offsetFromCenter.z
        );
        float3 volumePos = volumeCenter + rotatedOffset;
        
        // Bounds checking
        if (volumePos.x < 0 || volumePos.x >= float(volumeDim.x) ||
            volumePos.y < 0 || volumePos.y >= float(volumeDim.y) ||
            volumePos.z < 0 || volumePos.z >= float(volumeDim.z)) {
            continue;
        }
        
        uint3 samplePos = uint3(volumePos);
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
            alpha = 0.8;
            color = float3(1.0, 1.0, 1.0) * windowed;
        } else if (hounsfield > 50) {  // Dense tissue
            alpha = 0.3;
            color = float3(1.0, 0.2, 0.2) * windowed;
        } else if (hounsfield > -100) {  // Soft tissue
            alpha = 0.1;
            color = float3(0.8, 0.4, 0.4) * windowed;
        }
        
        // Crosshair axes - bright colored lines through volume center
        float lineThickness = 2.5;  // Thicker lines
        
        // X-axis (bright red) - runs along X at center Y and Z
        if (abs(volumePos.y - volumeCenter.y) < lineThickness && 
            abs(volumePos.z - volumeCenter.z) < lineThickness) {
            color = float3(1.0, 0.2, 0.2);  // Bright red
            alpha = 1.0;
        }
        
        // Y-axis (bright green) - runs along Y at center X and Z
        if (abs(volumePos.x - volumeCenter.x) < lineThickness && 
            abs(volumePos.z - volumeCenter.z) < lineThickness) {
            color = float3(0.2, 1.0, 0.2);  // Bright green
            alpha = 1.0;
        }
        
        // Z-axis (bright blue) - runs along Z at center X and Y
        if (abs(volumePos.x - volumeCenter.x) < lineThickness && 
            abs(volumePos.y - volumeCenter.y) < lineThickness) {
            color = float3(0.2, 0.2, 1.0);  // Bright blue
            alpha = 1.0;
        }
        
        // Center intersection point - white sphere
        float centerDist = length(volumePos - volumeCenter);
        if (centerDist < 3.0) {
            color = float3(1.0, 1.0, 0.0);  // Yellow center
            alpha = 1.0;
        }
        
        // Front-to-back compositing with higher visibility
        float stepAlpha = alpha / float(numSteps) * 80.0;  // Increased from 50
        accumulatedColor += color * stepAlpha * (1.0 - accumulatedAlpha);
        accumulatedAlpha += stepAlpha * (1.0 - accumulatedAlpha);
    }
    
    outputTexture.write(float4(accumulatedColor, 1.0), gid);
}
