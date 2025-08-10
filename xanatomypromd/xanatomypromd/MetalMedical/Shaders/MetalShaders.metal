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
    
    // Convert crosshair world position (DICOM mm) to voxel coordinates
    // This matches EXACTLY how the MPR views calculate positions
    float3 crosshairVoxel = (params.crosshairPosition - params.volumeOrigin) / params.volumeSpacing;
    
    // Ensure crosshair starts at center if not initialized (0,0,0 in world coords)
    if (length(params.crosshairPosition) < 0.001) {
        // Start at volume center
        crosshairVoxel = float3(volumeDim) * 0.5;
    }
    
    // Clamp crosshair to volume bounds to ensure it's visible
    crosshairVoxel = clamp(crosshairVoxel, float3(1.0), float3(volumeDim) - 1.0);
    
    // Define crosshair line colors (X=red, Y=green, Z=blue for clarity)
    float3 xAxisColor = float3(1.0, 0.0, 0.0);  // Pure red for X-axis (left-right)
    float3 yAxisColor = float3(0.0, 1.0, 0.0);  // Pure green for Y-axis (anterior-posterior)
    float3 zAxisColor = float3(0.0, 0.0, 1.0);  // Pure blue for Z-axis (superior-inferior)
    float lineThickness = 3.0;  // Thickness in voxels (increased for better visibility)
    
    // Apply Z-axis rotation to viewing direction (calculate once)
    float cosZ = cos(params.rotationZ);
    float sinZ = sin(params.rotationZ);
    
    // Volume center for rotation
    float3 volumeCenter = float3(volumeDim) * 0.5;
    
    // Ray march through volume with rotated viewing direction
    int numSteps = int(volumeDim.y);  // Still marching through Y (anterior-posterior)
    
    for (int step = 0; step < numSteps && accumulatedAlpha < 0.95; step++) {
        // Base position in volume using corrected aspect ratio
        float3 basePos = float3(
            (correctedNdc.x + 1.0) * 0.5 * float(volumeDim.x),          // X: left-right
            float(step),                                                  // Y: anterior-posterior (ray direction)
            (1.0 - (correctedNdc.y + 1.0) * 0.5) * float(volumeDim.z)   // Z: superior-inferior (flipped)
        );
        
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
        
        // Draw 3D crosshair lines at the correct position
        // volumePos is the current voxel we're sampling in the ray march
        // crosshairVoxel is where the crosshairs should be (synced with MPR views)
        
        // Check distance to each axis line
        // X-axis line (red): extends along X, passes through (any X, crosshair Y, crosshair Z)
        bool onXLine = (abs(volumePos.y - crosshairVoxel.y) < lineThickness && 
                        abs(volumePos.z - crosshairVoxel.z) < lineThickness);
        
        // Y-axis line (green): extends along Y, passes through (crosshair X, any Y, crosshair Z)
        bool onYLine = (abs(volumePos.x - crosshairVoxel.x) < lineThickness && 
                        abs(volumePos.z - crosshairVoxel.z) < lineThickness);
        
        // Z-axis line (blue): extends along Z, passes through (crosshair X, crosshair Y, any Z)
        bool onZLine = (abs(volumePos.x - crosshairVoxel.x) < lineThickness && 
                        abs(volumePos.y - crosshairVoxel.y) < lineThickness);
        
        // Check if at crosshair center (intersection point)
        float distToCenter = length(volumePos - crosshairVoxel);
        bool atCenter = distToCenter < lineThickness * 1.5;
        
        // Apply crosshair colors with proper blending
        if (atCenter) {
            // Bright yellow center point where all lines meet
            float3 centerColor = float3(1.0, 1.0, 0.0);
            float centerAlpha = 1.0 - (distToCenter / (lineThickness * 1.5));
            color = mix(color, centerColor, centerAlpha * 0.95);
            alpha = max(alpha, 0.95);
        } else if (onXLine) {
            // Red X-axis line
            color = mix(color, xAxisColor, 0.8);
            alpha = max(alpha, 0.8);
        } else if (onYLine) {
            // Green Y-axis line  
            color = mix(color, yAxisColor, 0.8);
            alpha = max(alpha, 0.8);
        } else if (onZLine) {
            // Blue Z-axis line
            color = mix(color, zAxisColor, 0.8);
            alpha = max(alpha, 0.8);
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
