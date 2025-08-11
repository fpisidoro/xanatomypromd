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
    float crosshairX;    // Crosshair position in voxel coordinates
    float crosshairY;
    float crosshairZ;
    float spacingX;
    float spacingY;
    float spacingZ;
    float displayWidth;   // Actual display dimensions
    float displayHeight;  // Actual display dimensions
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
    
    // Volume dimensions and setup
    uint3 volumeDim = uint3(volumeTexture.get_width(), volumeTexture.get_height(), volumeTexture.get_depth());
    
    // CRITICAL: Calculate physical dimensions and aspect ratio
    float physicalWidthX = float(volumeDim.x) * params.spacingX;   // e.g., 512 * 1.0 = 512mm
    float physicalHeightZ = float(volumeDim.z) * params.spacingZ;  // e.g., 53 * 3.0 = 159mm
    float physicalAspectRatio = physicalWidthX / physicalHeightZ;  // e.g., 512/159 = 3.22
    
    // Use ACTUAL display aspect ratio from display dimensions
    float displayAspectRatio = params.displayWidth / params.displayHeight;
    
    // Calculate letterboxing to preserve medical accuracy
    float2 letterboxScale;
    if (physicalAspectRatio > displayAspectRatio) {
        // Volume is wider than display - add letterbox top/bottom
        letterboxScale.x = 1.0;
        letterboxScale.y = displayAspectRatio / physicalAspectRatio;
    } else {
        // Volume is taller than display - add letterbox left/right  
        letterboxScale.x = physicalAspectRatio / displayAspectRatio;
        letterboxScale.y = 1.0;
    }
    
    // Check if we're outside the letterboxed area
    // letterboxScale represents the actual quad size like in MPR view
    if (abs(ndc.x) > letterboxScale.x || abs(ndc.y) > letterboxScale.y) {
        // Outside letterbox - render black
        outputTexture.write(float4(0.0, 0.0, 0.0, 1.0), gid);
        return;
    }
    
    // Map the letterboxed area to normalized volume coordinates
    float2 normalizedNdc;
    normalizedNdc.x = ndc.x / letterboxScale.x;
    normalizedNdc.y = ndc.y / letterboxScale.y;
    
    // Apply zoom and pan
    float2 viewNdc = normalizedNdc / params.zoom - float2(params.panX, params.panY) / (params.zoom * 100.0);
    
    float3 accumulatedColor = float3(0.0);
    float accumulatedAlpha = 0.0;
    
    // Volume center for rotation - in voxel space
    float3 volumeCenter = float3(volumeDim) * 0.5;
    
    // Apply Z-axis rotation to viewing direction (calculate once)
    float cosZ = cos(params.rotationZ);
    float sinZ = sin(params.rotationZ);
    
    // Ray march through volume along Y-axis (anterior-posterior)
    // Sample uniformly in physical space
    float minSpacing = min(min(params.spacingX, params.spacingY), params.spacingZ);
    float stepSize = minSpacing;  // Step size in physical mm
    int numSteps = int(float(volumeDim.y) * params.spacingY / stepSize);
    
    for (int step = 0; step < numSteps && accumulatedAlpha < 0.95; step++) {
        // Map normalized NDC to volume space
        // viewNdc ranges from [-1, 1] after normalization
        // Add 0.5 offset to sample voxel centers like texture sampling does
        float3 basePos = float3(
            (viewNdc.x + 1.0) * 0.5 * float(volumeDim.x),
            float(step) * stepSize / params.spacingY,
            (viewNdc.y + 1.0) * 0.5 * float(volumeDim.z)
        );
        
        // Apply rotation around Z-axis
        float3 offsetFromCenter = basePos - volumeCenter;
        float3 rotatedOffset = float3(
            offsetFromCenter.x * cosZ - offsetFromCenter.y * sinZ,
            offsetFromCenter.x * sinZ + offsetFromCenter.y * cosZ,
            offsetFromCenter.z
        );
        float3 volumePos = volumeCenter + rotatedOffset;
        
        // Bounds checking - allow sampling up to but not including volumeDim
        // This allows values like 52.9 which are valid for interpolation
        if (volumePos.x < 0 || volumePos.x > float(volumeDim.x - 1) ||
            volumePos.y < 0 || volumePos.y > float(volumeDim.y - 1) ||
            volumePos.z < 0 || volumePos.z > float(volumeDim.z - 1)) {
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
        
        // Crosshair axes - bright colored lines through actual crosshair position
        // Use the crosshair position from MPR views (already in voxel coordinates)
        float3 crosshairPos = float3(params.crosshairX, params.crosshairY, params.crosshairZ);
        
        // Account for anisotropic voxel spacing when checking line thickness
        float3 spacing = float3(params.spacingX, params.spacingY, params.spacingZ);
        
        // Line thickness in physical mm (not voxels)
        float physicalLineThickness = 2.0;  // 2mm thick lines
        
        // Convert to voxel units for each axis
        float3 lineThicknessVoxels = physicalLineThickness / spacing;
        
        // X-axis (bright red) - runs along X at crosshair Y and Z
        if (abs(volumePos.y - crosshairPos.y) < lineThicknessVoxels.y && 
            abs(volumePos.z - crosshairPos.z) < lineThicknessVoxels.z) {
            color = float3(1.0, 0.2, 0.2);  // Bright red
            alpha = 1.0;
        }
        
        // Y-axis (bright green) - runs along Y at crosshair X and Z
        if (abs(volumePos.x - crosshairPos.x) < lineThicknessVoxels.x && 
            abs(volumePos.z - crosshairPos.z) < lineThicknessVoxels.z) {
            color = float3(0.2, 1.0, 0.2);  // Bright green
            alpha = 1.0;
        }
        
        // Z-axis (bright blue) - runs along Z at crosshair X and Y
        if (abs(volumePos.x - crosshairPos.x) < lineThicknessVoxels.x && 
            abs(volumePos.y - crosshairPos.y) < lineThicknessVoxels.y) {
            color = float3(0.2, 0.2, 1.0);  // Bright blue
            alpha = 1.0;
        }
        
        // Center intersection point - yellow sphere at actual crosshair
        // Convert position difference to physical space for proper sphere shape
        float3 centerOffset = volumePos - crosshairPos;
        float3 physicalOffset = centerOffset * spacing;
        float physicalDist = length(physicalOffset);  // Distance in mm
        
        if (physicalDist < 3.0) {  // 3mm radius sphere
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
