#include <metal_stdlib>
using namespace metal;

// MARK: - MPR Shader Parameters

struct MPRParams {
    uint planeType;              // 0=axial, 1=sagittal, 2=coronal
    float slicePosition;         // 0.0 to 1.0 normalized position
    float windowCenter;
    float windowWidth;
    uint3 volumeDimensions;
    float3 spacing;
};

// MARK: - 3D Volume Sampling Functions

// Manual trilinear interpolation for integer 3D textures
float sampleVolume3D(texture3d<short, access::read> volume,
                     float3 texCoord) {
    // Convert normalized coordinates to texture coordinates
    uint3 dimensions = uint3(volume.get_width(), volume.get_height(), volume.get_depth());
    float3 scaledCoord = texCoord * float3(dimensions - 1);
    
    // Get integer coordinates for interpolation
    uint3 coord0 = uint3(floor(scaledCoord));
    uint3 coord1 = min(coord0 + 1, dimensions - 1);
    
    // Interpolation weights
    float3 weights = scaledCoord - float3(coord0);
    
    // Sample 8 corner voxels
    float v000 = float(volume.read(uint3(coord0.x, coord0.y, coord0.z)).r);
    float v001 = float(volume.read(uint3(coord0.x, coord0.y, coord1.z)).r);
    float v010 = float(volume.read(uint3(coord0.x, coord1.y, coord0.z)).r);
    float v011 = float(volume.read(uint3(coord0.x, coord1.y, coord1.z)).r);
    float v100 = float(volume.read(uint3(coord1.x, coord0.y, coord0.z)).r);
    float v101 = float(volume.read(uint3(coord1.x, coord0.y, coord1.z)).r);
    float v110 = float(volume.read(uint3(coord1.x, coord1.y, coord0.z)).r);
    float v111 = float(volume.read(uint3(coord1.x, coord1.y, coord1.z)).r);
    
    // Trilinear interpolation
    float c00 = mix(v000, v100, weights.x);
    float c01 = mix(v001, v101, weights.x);
    float c10 = mix(v010, v110, weights.x);
    float c11 = mix(v011, v111, weights.x);
    
    float c0 = mix(c00, c10, weights.y);
    float c1 = mix(c01, c11, weights.y);
    
    return mix(c0, c1, weights.z);
}

// Nearest neighbor sampling for exact voxel values
float sampleVolumeNearest(texture3d<short, access::read> volume,
                         float3 texCoord) {
    // Convert normalized coordinates to texture coordinates
    uint3 dimensions = uint3(volume.get_width(), volume.get_height(), volume.get_depth());
    uint3 coord = uint3(texCoord * float3(dimensions));
    
    // Clamp to valid range
    coord = min(coord, dimensions - 1);
    
    short sampledValue = volume.read(coord).r;
    return float(sampledValue);
}

// MARK: - CT Windowing Function

float4 applyWindowing(float ctValue, float windowCenter, float windowWidth) {
    float minValue = windowCenter - windowWidth / 2.0;
    float maxValue = windowCenter + windowWidth / 2.0;
    
    // Normalize to [0, 1] range
    float normalizedValue = clamp((ctValue - minValue) / (maxValue - minValue), 0.0, 1.0);
    
    // Return as grayscale RGBA
    return float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
}

// MARK: - Main MPR Compute Shader

kernel void mprSliceExtraction(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Check bounds
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Convert output pixel coordinates to normalized [0,1] range
    float2 outputCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // Calculate 3D texture coordinate based on plane type
    float3 volumeCoord;
    
    switch (params.planeType) {
        case 0: // Axial (XY plane at fixed Z)
            volumeCoord = float3(outputCoord.x, outputCoord.y, params.slicePosition);
            break;
            
        case 1: // Sagittal (YZ plane at fixed X)
            volumeCoord = float3(params.slicePosition, outputCoord.x, outputCoord.y);
            break;
            
        case 2: // Coronal (XZ plane at fixed Y)
            volumeCoord = float3(outputCoord.x, params.slicePosition, outputCoord.y);
            break;
            
        default:
            volumeCoord = float3(0.5, 0.5, 0.5); // Fallback to center
            break;
    }
    
    // Sample the 3D volume with trilinear interpolation
    float ctValue = sampleVolume3D(volumeTexture, volumeCoord);
    
    // Apply CT windowing
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    // Write to output texture
    outputTexture.write(windowedColor, gid);
}

// MARK: - Specialized MPR Shaders for Each Plane

// Optimized Axial Slice Extraction
kernel void mprAxialSlice(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Direct mapping for axial slices (no coordinate transformation needed)
    float2 texCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    float3 volumeCoord = float3(texCoord.x, texCoord.y, params.slicePosition);
    
    float ctValue = sampleVolume3D(volumeTexture, volumeCoord);
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    outputTexture.write(windowedColor, gid);
}

// Optimized Sagittal Slice Extraction
kernel void mprSagittalSlice(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Map output coordinates to YZ plane sampling
    float2 texCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    float3 volumeCoord = float3(params.slicePosition, texCoord.x, texCoord.y);
    
    float ctValue = sampleVolume3D(volumeTexture, volumeCoord);
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    outputTexture.write(windowedColor, gid);
}

// Optimized Coronal Slice Extraction
kernel void mprCoronalSlice(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Map output coordinates to XZ plane sampling
    float2 texCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    float3 volumeCoord = float3(texCoord.x, params.slicePosition, texCoord.y);
    
    float ctValue = sampleVolume3D(volumeTexture, volumeCoord);
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    outputTexture.write(windowedColor, gid);
}

// MARK: - Volume Statistics Compute Shader

kernel void computeVolumeHistogram(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    device atomic_uint* histogram [[buffer(0)]],
    constant uint& binCount [[buffer(1)]],
    uint3 gid [[thread_position_in_grid]]
) {
    // Check bounds
    if (gid.x >= volumeTexture.get_width() ||
        gid.y >= volumeTexture.get_height() ||
        gid.z >= volumeTexture.get_depth()) {
        return;
    }
    
    // Read voxel value
    short voxelValue = volumeTexture.read(gid).r;
    
    // Convert to histogram bin (assuming 4096 bins for CT range)
    int binIndex = clamp(int(voxelValue + 2048), 0, int(binCount - 1));
    
    // Atomically increment histogram bin
    atomic_fetch_add_explicit(&histogram[binIndex], 1, memory_order_relaxed);
}

// MARK: - Volume Preprocessing Shaders

// Apply rescale parameters to entire volume
kernel void rescaleVolume(
    texture3d<short, access::read> inputVolume [[texture(0)]],
    texture3d<float, access::write> outputVolume [[texture(1)]],
    constant float& rescaleSlope [[buffer(0)]],
    constant float& rescaleIntercept [[buffer(1)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inputVolume.get_width() ||
        gid.y >= inputVolume.get_height() ||
        gid.z >= inputVolume.get_depth()) {
        return;
    }
    
    // Read raw pixel value
    short rawValue = inputVolume.read(gid).r;
    
    // Apply rescale to get Hounsfield Units
    float housefieldValue = float(rawValue) * rescaleSlope + rescaleIntercept;
    
    // Write rescaled value
    outputVolume.write(float4(housefieldValue, 0, 0, 0), gid);
}

// MARK: - Advanced MPR with Oblique Planes

struct ObliquePlaneParams {
    float3 planeOrigin;     // Origin point of the plane
    float3 planeNormal;     // Normal vector of the plane
    float3 planeRight;      // Right direction on the plane
    float3 planeUp;         // Up direction on the plane
    float windowCenter;
    float windowWidth;
};

kernel void mprObliquePlane(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant ObliquePlaneParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Convert pixel coordinates to plane coordinates
    float2 planeCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    planeCoord = (planeCoord - 0.5) * 2.0; // Convert to [-1, 1] range
    
    // Calculate 3D position on the oblique plane
    float3 worldPos = params.planeOrigin +
                     planeCoord.x * params.planeRight +
                     planeCoord.y * params.planeUp;
    
    // Convert world position to texture coordinates [0, 1]
    float3 texCoord = worldPos; // Assuming normalized coordinates
    
    // Sample volume if within bounds
    if (all(texCoord >= 0.0) && all(texCoord <= 1.0)) {
        float ctValue = sampleVolume3D(volumeTexture, texCoord);
        float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
        outputTexture.write(windowedColor, gid);
    } else {
        // Outside volume bounds - write black
        outputTexture.write(float4(0, 0, 0, 1), gid);
    }
}

// MARK: - Quality Enhancement Shaders

// Anisotropic filtering for better image quality
kernel void mprWithAnisotropicFiltering(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float2 texCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // Calculate 3D coordinate based on plane type
    float3 volumeCoord;
    switch (params.planeType) {
        case 0: // Axial
            volumeCoord = float3(texCoord.x, texCoord.y, params.slicePosition);
            break;
        case 1: // Sagittal
            volumeCoord = float3(params.slicePosition, texCoord.x, texCoord.y);
            break;
        case 2: // Coronal
            volumeCoord = float3(texCoord.x, params.slicePosition, texCoord.y);
            break;
    }
    
    // Multi-sample for better quality
    float ctValue = 0.0;
    const int samples = 4;
    const float offset = 0.5 / max(outputTexture.get_width(), outputTexture.get_height());
    
    for (int i = 0; i < samples; i++) {
        float2 sampleOffset = float2(
            (i & 1) ? offset : -offset,
            (i & 2) ? offset : -offset
        );
        
        float3 sampleCoord = volumeCoord;
        switch (params.planeType) {
            case 0: // Axial
                sampleCoord.xy += sampleOffset;
                break;
            case 1: // Sagittal
                sampleCoord.yz += sampleOffset;
                break;
            case 2: // Coronal
                sampleCoord.xz += sampleOffset;
                break;
        }
        
        ctValue += sampleVolume3D(volumeTexture, sampleCoord);
    }
    
    ctValue /= float(samples);
    
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    outputTexture.write(windowedColor, gid);
}
