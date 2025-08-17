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
    uint3 volumeDimensions;   // Dynamic: 53, 500, 1000+ slices
    float3 spacing;
};

// FIXED: Hardware-accelerated MPR slice extraction with universal boundary checking
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
    
    // CRITICAL FIX: Clamp coordinates to prevent texture overflow
    // For any volume size (53, 500, 1000+ slices), ensure we never exceed bounds
    volumeCoord = clamp(volumeCoord, 0.0, 0.999);
    
    // Convert to integer coordinates with explicit bounds checking
    uint3 intCoord = uint3(volumeCoord * float3(params.volumeDimensions));
    
    // SAFETY: Double-check bounds for any volume size
    intCoord = min(intCoord, params.volumeDimensions - 1);
    
    // Verify coordinates are valid (debug safety)
    if (intCoord.x >= params.volumeDimensions.x || 
        intCoord.y >= params.volumeDimensions.y || 
        intCoord.z >= params.volumeDimensions.z) {
        // Invalid coordinate - output black instead of crashing
        outputTexture.write(float4(0.0, 0.0, 0.0, 1.0), gid);
        return;
    }
    
    // Sample the volume texture safely
    short rawValue = volumeTexture.read(intCoord).r;
    
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
    float showROI;       // 1.0 if ROI should be shown
    float roiCount;      // Number of ROI contours
    float originX;       // Volume origin in world coordinates
    float originY;
    float originZ;
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

// FIXED: 3D Volume Rendering with universal bounds checking
kernel void volumeRender3D(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant Volume3DRenderParams& params [[buffer(0)]],
    constant float* roiData [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Screen coordinates to normalized device coordinates [-1, 1]
    float2 ndc = (float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height())) * 2.0 - 1.0;
    
    // DYNAMIC: Volume dimensions work for any scan size
    uint3 volumeDim = uint3(volumeTexture.get_width(), volumeTexture.get_height(), volumeTexture.get_depth());
    
    // CRITICAL: Calculate physical dimensions and aspect ratio for ANY volume
    float physicalWidthX = float(volumeDim.x) * params.spacingX;
    float physicalHeightZ = float(volumeDim.z) * params.spacingZ;
    float physicalAspectRatio = physicalWidthX / physicalHeightZ;
    
    // Use ACTUAL display aspect ratio from display dimensions
    float displayAspectRatio = params.displayWidth / params.displayHeight;
    
    // Calculate letterboxing to preserve medical accuracy for ANY scan
    float2 letterboxScale;
    if (physicalAspectRatio > displayAspectRatio) {
        letterboxScale.x = 1.0;
        letterboxScale.y = displayAspectRatio / physicalAspectRatio;
    } else {
        letterboxScale.x = physicalAspectRatio / displayAspectRatio;
        letterboxScale.y = 1.0;
    }
    
    // Check if we're outside the letterboxed area
    if (abs(ndc.x) > letterboxScale.x || abs(ndc.y) > letterboxScale.y) {
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
    
    // Volume center for rotation - in voxel space (adapts to any size)
    float3 volumeCenter = float3(volumeDim) * 0.5;
    
    // Apply Z-axis rotation to viewing direction (calculate once)
    float cosZ = cos(params.rotationZ);
    float sinZ = sin(params.rotationZ);
    
    // ADAPTIVE: Ray march through volume along Y-axis (anterior-posterior)
    float minSpacing = min(min(params.spacingX, params.spacingY), params.spacingZ);
    float stepSize = minSpacing;
    int numSteps = int(float(volumeDim.y) * params.spacingY / stepSize);
    
    for (int step = 0; step < numSteps && accumulatedAlpha < 0.95; step++) {
        // Map normalized NDC to volume space (works for any dimensions)
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
        
        // UNIVERSAL BOUNDS CHECKING: Works for 53, 500, 1000+ slices
        if (volumePos.x < 0 || volumePos.x >= float(volumeDim.x) ||
            volumePos.y < 0 || volumePos.y >= float(volumeDim.y) ||
            volumePos.z < 0 || volumePos.z >= float(volumeDim.z)) {
            continue;
        }
        
        // SAFE CONVERSION: Clamp to valid integer coordinates
        uint3 samplePos = uint3(clamp(volumePos, 0.0, float3(volumeDim - 1)));
        
        short rawValue = volumeTexture.read(samplePos).r;
        float hounsfield = float(rawValue);
        
        // Apply windowing
        float windowMin = params.windowCenter - params.windowWidth / 2.0;
        float windowMax = params.windowCenter + params.windowWidth / 2.0;
        float windowed = clamp((hounsfield - windowMin) / (windowMax - windowMin), 0.0, 1.0);
        
        // Get alpha and color based on tissue type
        float alpha = 0.0;
        float3 color = float3(0.0);
        
        // Cool Blue Medical scheme
        if (hounsfield > 300) {
            alpha = 0.15;
            color = float3(0.9, 0.95, 1.0) * windowed;
        } else if (hounsfield > 100) {
            alpha = 0.05;
            color = float3(0.8, 0.85, 0.95) * windowed;
        } else if (hounsfield > 40) {
            alpha = 0.15;
            color = float3(0.3, 0.5, 0.9) * windowed;
        } else if (hounsfield > -10) {
            alpha = 0.08;
            color = float3(0.4, 0.6, 0.8) * windowed;
        } else if (hounsfield > -100) {
            alpha = 0.03;
            color = float3(0.7, 0.8, 0.9) * windowed;
        }
        
        // Front-to-back compositing
        float stepAlpha = alpha / float(numSteps) * 60.0;
        accumulatedColor += color * stepAlpha * (1.0 - accumulatedAlpha);
        accumulatedAlpha += stepAlpha * (1.0 - accumulatedAlpha);
    }
    
    outputTexture.write(float4(accumulatedColor, 1.0), gid);
}
