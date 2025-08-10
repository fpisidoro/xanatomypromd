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
    float3 volumeOrigin;        // Add volume origin
    float3 volumeSpacing;       // Add volume spacing
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
    
    // Apply correct aspect ratio using DICOM spacing
    // From logs: Spacing: SIMD3<Float>(0.585938, 0.585938, 2.78) mm
    float3 spacing = float3(0.585938, 0.585938, 2.78);
    
    // Normalize NDC by spacing to get correct proportions
    float2 correctedNdc = float2(
        ndc.x * spacing.x / spacing.y,  // X relative to Y
        ndc.y * spacing.z / spacing.y   // Z relative to Y (correct vertical scaling)
    );
    
    // Volume dimensions and setup
    uint3 volumeDim = uint3(volumeTexture.get_width(), volumeTexture.get_height(), volumeTexture.get_depth());
    
    float3 accumulatedColor = float3(0.0);
    float accumulatedAlpha = 0.0;
    
    // CROSSHAIR POSITION IN 3D VOLUME
    // The MPR views send us currentWorldPosition which is the center in DICOM mm
    // We convert to voxel space: (world - origin) / spacing
    float3 crosshairVoxel = (params.crosshairPosition - params.volumeOrigin) / params.volumeSpacing;
    
    // If the position hasn't been initialized, default to center
    // Center of 512x512x53 volume is at voxel (256, 256, 26.5)
    if (crosshairVoxel.x < 1.0 && crosshairVoxel.y < 1.0 && crosshairVoxel.z < 1.0) {
        crosshairVoxel = float3(float(volumeDim.x) * 0.5, 
                               float(volumeDim.y) * 0.5, 
                               float(volumeDim.z) * 0.5);
    }
    
    // Clamp to volume bounds for safety
    crosshairVoxel = clamp(crosshairVoxel, float3(0.0), float3(volumeDim) - float3(1.0));
    
    // Define crosshair line colors (X=red, Y=green, Z=blue for clarity)
    float3 xAxisColor = float3(1.0, 0.0, 0.0);  // Pure red for X-axis (left-right)
    float3 yAxisColor = float3(0.0, 1.0, 0.0);  // Pure green for Y-axis (anterior-posterior)
    float3 zAxisColor = float3(0.0, 0.0, 1.0);  // Pure blue for Z-axis (superior-inferior)
    float lineThickness = 1.0;  // THIN lines (was 3.0)
    
    // Apply Z-axis rotation to viewing direction (calculate once)
    float cosZ = cos(params.rotationZ);
    float sinZ = sin(params.rotationZ);
    
    // Volume center for rotation
    float3 volumeCenter = float3(volumeDim) * 0.5;
    
    // Ray march through volume with rotated viewing direction
    int numSteps = int(volumeDim.y);  // Still marching through Y (anterior-posterior)
    
    for (int step = 0; step < numSteps && accumulatedAlpha < 0.95; step++) {
        // Simple 3D position in volume space
        // We're ray marching through Y (front to back)
        
        // MAINTAIN ASPECT RATIO - don't stretch to fill screen
        // Volume is 512x512x53, so Z dimension is much smaller
        // Map screen coordinates to volume maintaining proportions
        
        // Get screen position in normalized coordinates [0,1]
        float2 screenNorm = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
        
        // Center the volume in screen space
        float2 centered = screenNorm - 0.5;
        
        // Apply aspect ratio correction based on volume dimensions
        // X and Y are 512, Z is 53, so Z is ~10% of X/Y
        float volumeAspectZ = float(volumeDim.z) / float(volumeDim.x);  // 53/512 = ~0.1
        
        float3 basePos = float3(
            (centered.x + 0.5) * float(volumeDim.x),                    // X: maintain full width
            float(step),                                                 // Y: ray depth
            (centered.y * volumeAspectZ + 0.5) * float(volumeDim.x)     // Z: scale by aspect ratio
        );
        
        // Clamp Z to actual volume bounds
        basePos.z = clamp(basePos.z, 0.0, float(volumeDim.z - 1));
        
        // Apply rotation around Z-axis (rotate the sampling position)
        float3 offsetFromCenter = basePos - volumeCenter;
        
        // Rotate X and Y coordinates around Z-axis
        float3 rotatedOffset = float3(
            offsetFromCenter.x * cosZ - offsetFromCenter.y * sinZ,
            offsetFromCenter.x * sinZ + offsetFromCenter.y * cosZ,
            offsetFromCenter.z  // Z unchanged
        );
        
        float3 volumePos = volumeCenter + rotatedOffset;
        
        // FIXED: Proper bounds checking - skip samples outside volume
        if (volumePos.x < 0 || volumePos.x >= float(volumeDim.x) ||
            volumePos.y < 0 || volumePos.y >= float(volumeDim.y) ||
            volumePos.z < 0 || volumePos.z >= float(volumeDim.z)) {
            continue;  // Skip this sample completely
        }
        
        uint3 samplePos = uint3(volumePos);
        
        // Sample volume
        short rawValue = volumeTexture.read(samplePos).r;
        float hounsfield = float(rawValue);
        
        // Apply windowing
        float windowMin = params.windowCenter - params.windowWidth / 2.0;
        float windowMax = params.windowCenter + params.windowWidth / 2.0;
        float windowed = clamp((hounsfield - windowMin) / (windowMax - windowMin), 0.0, 1.0);
        
        // Get alpha and color based on tissue type - enhanced visibility
        float alpha = 0.0;
        float3 color = float3(0.0);
        
        if (hounsfield > 200) {  // Bone
            alpha = 0.8;
            color = float3(1.0, 1.0, 1.0) * windowed;  // Pure white bone
        } else if (hounsfield > 50) {  // Dense tissue
            alpha = 0.3;
            color = float3(1.0, 0.2, 0.2) * windowed;  // Bright red tissue
        } else if (hounsfield > -100) {  // Soft tissue
            alpha = 0.1;
            color = float3(0.8, 0.4, 0.4) * windowed;  // Pink soft tissue
        }
        // Air and fat are transparent
        
        // WE ARE IN A 3D VOLUME. JUST DRAW 3 FUCKING LINES.
        // volumePos is our current position in 3D space
        // crosshairVoxel is where the lines intersect (256, 256, 26.5)
        
        // LINE 1 - RED - Runs along X axis through (ANY X, crosshair.y, crosshair.z)
        if (abs(volumePos.y - crosshairVoxel.y) < lineThickness && 
            abs(volumePos.z - crosshairVoxel.z) < lineThickness) {
            color = xAxisColor;
            alpha = 1.0;
        }
        
        // LINE 2 - GREEN - Runs along Y axis through (crosshair.x, ANY Y, crosshair.z)
        if (abs(volumePos.x - crosshairVoxel.x) < lineThickness && 
            abs(volumePos.z - crosshairVoxel.z) < lineThickness) {
            color = yAxisColor;
            alpha = 1.0;
        }
        
        // LINE 3 - BLUE - Runs along Z axis through (crosshair.x, crosshair.y, ANY Z)
        if (abs(volumePos.x - crosshairVoxel.x) < lineThickness && 
            abs(volumePos.y - crosshairVoxel.y) < lineThickness) {
            color = zAxisColor;
            alpha = 1.0;
        }
        
        // INTERSECTION POINT - YELLOW
        if (abs(volumePos.x - crosshairVoxel.x) < lineThickness * 2.0 &&
            abs(volumePos.y - crosshairVoxel.y) < lineThickness * 2.0 &&
            abs(volumePos.z - crosshairVoxel.z) < lineThickness * 2.0) {
            color = float3(1.0, 1.0, 0.0);
            alpha = 1.0;
        }
        
        // Front-to-back compositing
        float stepAlpha = alpha / float(numSteps) * 80.0;  // Increased from 50
        accumulatedColor += color * stepAlpha * (1.0 - accumulatedAlpha);
        accumulatedAlpha += stepAlpha * (1.0 - accumulatedAlpha);
    }

    
    // Final output
    float3 finalColor = accumulatedColor;
    outputTexture.write(float4(finalColor, 1.0), gid);
}
