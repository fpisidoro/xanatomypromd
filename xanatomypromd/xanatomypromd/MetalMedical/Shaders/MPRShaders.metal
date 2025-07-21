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

// MARK: - Manual 3D Volume Sampling (WORKING VERSION)

// Manual trilinear interpolation for signed integer 3D textures
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
    uint3 dimensions = uint3(volume.get_width(), volume.get_height(), volume.get_depth());
    uint3 coord = uint3(texCoord * float3(dimensions));
    coord = min(coord, dimensions - 1);
    
    short sampledValue = volume.read(coord).r;
    return float(sampledValue);
}

// MARK: - CT Windowing Function

float4 applyWindowing(float ctValue, float windowCenter, float windowWidth) {
    float minValue = windowCenter - windowWidth / 2.0;
    
    // Normalize to [0, 1] range
    float normalizedValue = clamp((ctValue - minValue) / windowWidth, 0.0, 1.0);
    
    // Return as grayscale RGBA
    return float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
}

// MARK: - Main MPR Compute Shader (WORKING VERSION)

kernel void mprSliceExtraction(
    texture3d<short, access::read> volumeTexture [[texture(0)]],  // Integer texture
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
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
            
        case 1: // Sagittal (YZ plane at fixed X) - FIXED: Remove flip
            volumeCoord = float3(params.slicePosition, outputCoord.x, outputCoord.y);
            break;
            
        case 2: // Coronal (XZ plane at fixed Y) - FIXED: Remove flip
            volumeCoord = float3(outputCoord.x, params.slicePosition, outputCoord.y);
            break;
            
        default:
            volumeCoord = float3(0.5, 0.5, 0.5);
            break;
    }
    
    // Manual interpolation sampling (works without Metal toolchain)
    float ctValue = sampleVolume3D(volumeTexture, volumeCoord);
    
    // Apply CT windowing
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    // Write to output texture
    outputTexture.write(windowedColor, gid);
}

// MARK: - Specialized MPR Shaders

kernel void mprAxialSlice(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float2 texCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    float3 volumeCoord = float3(texCoord.x, texCoord.y, params.slicePosition);
    
    float ctValue = sampleVolume3D(volumeTexture, volumeCoord);
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    outputTexture.write(windowedColor, gid);
}

kernel void mprSagittalSlice(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float2 texCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    // REVERTED: Back to original mapping
    float3 volumeCoord = float3(params.slicePosition, texCoord.x, texCoord.y);
    
    float ctValue = sampleVolume3D(volumeTexture, volumeCoord);
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    outputTexture.write(windowedColor, gid);
}

kernel void mprCoronalSlice(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant MPRParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float2 texCoord = float2(gid) / float2(outputTexture.get_width(), outputTexture.get_height());
    // FIXED: Proper coronal mapping (front view)
    float3 volumeCoord = float3(texCoord.x, params.slicePosition, 1.0 - texCoord.y);
    
    float ctValue = sampleVolume3D(volumeTexture, volumeCoord);
    float4 windowedColor = applyWindowing(ctValue, params.windowCenter, params.windowWidth);
    
    outputTexture.write(windowedColor, gid);
}

// MARK: - Volume Statistics

kernel void computeVolumeHistogram(
    texture3d<short, access::read> volumeTexture [[texture(0)]],
    device atomic_uint* histogram [[buffer(0)]],
    constant uint& binCount [[buffer(1)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= volumeTexture.get_width() ||
        gid.y >= volumeTexture.get_height() ||
        gid.z >= volumeTexture.get_depth()) {
        return;
    }
    
    short voxelValue = volumeTexture.read(gid).r;
    int binIndex = clamp(int(voxelValue + 2048), 0, int(binCount - 1));
    atomic_fetch_add_explicit(&histogram[binIndex], 1, memory_order_relaxed);
}
