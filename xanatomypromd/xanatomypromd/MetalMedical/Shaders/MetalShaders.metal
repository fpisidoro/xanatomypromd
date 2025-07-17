#include <metal_stdlib>
using namespace metal;

// MARK: - CT Windowing Shader Parameters

struct WindowingParams {
    float windowCenter;
    float windowWidth;
};

// MARK: - CT Windowing Compute Shader
// Converts raw 16-bit CT pixel values to windowed 8-bit display values
// Executes in parallel across thousands of GPU cores for real-time performance

kernel void ctWindowing(
    texture2d<int, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant WindowingParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    // Read signed 16-bit CT pixel value (already in Hounsfield Units range)
    int rawPixel = inputTexture.read(gid).r;
    float ctValue = float(rawPixel);
    
    // Apply CT windowing formula
    // Standard radiology windowing: map [center - width/2, center + width/2] to [0, 1]
    float windowMin = params.windowCenter - (params.windowWidth * 0.5);
    
    // Clamp and normalize to [0, 1] range
    float normalizedValue = (ctValue - windowMin) / params.windowWidth;
    normalizedValue = clamp(normalizedValue, 0.0, 1.0);
    
    // Output as RGBA with grayscale value
    float4 outputColor = float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
    
    outputTexture.write(outputColor, gid);
}

// MARK: - Advanced CT Windowing with LUT
// More sophisticated windowing with lookup table support for complex mappings

kernel void ctWindowingLUT(
    texture2d<uint, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant WindowingParams& params [[buffer(0)]],
    constant float* lookupTable [[buffer(1)]],
    constant uint& lutSize [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    uint rawPixel = inputTexture.read(gid).r;
    
    // Use lookup table for more complex windowing curves
    uint lutIndex = min(rawPixel, lutSize - 1);
    float windowedValue = lookupTable[lutIndex];
    
    // Apply additional windowing parameters
    float windowMin = params.windowCenter - (params.windowWidth * 0.5);
    
    // Secondary windowing on LUT result
    float finalValue = (windowedValue - windowMin) / params.windowWidth;
    finalValue = clamp(finalValue, 0.0, 1.0);
    
    float4 outputColor = float4(finalValue, finalValue, finalValue, 1.0);
    outputTexture.write(outputColor, gid);
}

// MARK: - Pseudocolor CT Windowing
// Apply false color mapping for enhanced visualization

kernel void ctWindowingPseudocolor(
    texture2d<uint, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant WindowingParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    uint rawPixel = inputTexture.read(gid).r;
    float ctValue = float(rawPixel) - 32768.0;
    
    // Apply windowing
    float windowMin = params.windowCenter - (params.windowWidth * 0.5);
    float normalizedValue = (ctValue - windowMin) / params.windowWidth;
    normalizedValue = clamp(normalizedValue, 0.0, 1.0);
    
    // Apply pseudocolor mapping (hot colormap)
    float4 outputColor;
    if (normalizedValue < 0.33) {
        // Black to red
        outputColor = float4(normalizedValue * 3.0, 0.0, 0.0, 1.0);
    } else if (normalizedValue < 0.66) {
        // Red to yellow
        float t = (normalizedValue - 0.33) * 3.0;
        outputColor = float4(1.0, t, 0.0, 1.0);
    } else {
        // Yellow to white
        float t = (normalizedValue - 0.66) * 3.0;
        outputColor = float4(1.0, 1.0, t, 1.0);
    }
    
    outputTexture.write(outputColor, gid);
}

// MARK: - Multi-Planar Reconstruction Helper
// Trilinear interpolation for MPR slice generation

float trilinearInterpolation(
    texture3d<float, access::read> volumeTexture,
    float3 position
) {
    // Get texture dimensions
    uint width = volumeTexture.get_width();
    uint height = volumeTexture.get_height();
    uint depth = volumeTexture.get_depth();
    
    // Convert normalized position to texture coordinates
    float3 texCoord = position * float3(width - 1, height - 1, depth - 1);
    
    // Get integer and fractional parts
    uint3 coord0 = uint3(floor(texCoord));
    uint3 coord1 = min(coord0 + 1, uint3(width - 1, height - 1, depth - 1));
    float3 frac = texCoord - float3(coord0);
    
    // Sample 8 neighboring voxels
    float v000 = volumeTexture.read(uint3(coord0.x, coord0.y, coord0.z)).r;
    float v001 = volumeTexture.read(uint3(coord0.x, coord0.y, coord1.z)).r;
    float v010 = volumeTexture.read(uint3(coord0.x, coord1.y, coord0.z)).r;
    float v011 = volumeTexture.read(uint3(coord0.x, coord1.y, coord1.z)).r;
    float v100 = volumeTexture.read(uint3(coord1.x, coord0.y, coord0.z)).r;
    float v101 = volumeTexture.read(uint3(coord1.x, coord0.y, coord1.z)).r;
    float v110 = volumeTexture.read(uint3(coord1.x, coord1.y, coord0.z)).r;
    float v111 = volumeTexture.read(uint3(coord1.x, coord1.y, coord1.z)).r;
    
    // Trilinear interpolation
    float v00 = mix(v000, v100, frac.x);
    float v01 = mix(v001, v101, frac.x);
    float v10 = mix(v010, v110, frac.x);
    float v11 = mix(v011, v111, frac.x);
    
    float v0 = mix(v00, v10, frac.y);
    float v1 = mix(v01, v11, frac.y);
    
    return mix(v0, v1, frac.z);
}

// MARK: - MPR Slice Generation
// Generate arbitrary slice through 3D volume for multi-planar reconstruction

kernel void generateMPRSlice(
    texture3d<float, access::read> volumeTexture [[texture(0)]],
    texture2d<float, access::write> outputSlice [[texture(1)]],
    constant float4x4& transformMatrix [[buffer(0)]],
    constant WindowingParams& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputSlice.get_width() || gid.y >= outputSlice.get_height()) {
        return;
    }
    
    // Convert pixel coordinates to normalized slice coordinates
    float2 sliceCoord = (float2(gid) + 0.5) / float2(outputSlice.get_width(), outputSlice.get_height());
    
    // Transform slice coordinates to volume space
    float4 volumePos = transformMatrix * float4(sliceCoord.x, sliceCoord.y, 0.0, 1.0);
    float3 volumeCoord = volumePos.xyz / volumePos.w;
    
    // Check bounds
    if (any(volumeCoord < 0.0) || any(volumeCoord > 1.0)) {
        outputSlice.write(float4(0.0, 0.0, 0.0, 1.0), gid);
        return;
    }
    
    // Sample volume with trilinear interpolation
    float sampledValue = trilinearInterpolation(volumeTexture, volumeCoord);
    
    // Apply windowing
    float windowMin = params.windowCenter - (params.windowWidth * 0.5);
    float normalizedValue = (sampledValue - windowMin) / params.windowWidth;
    normalizedValue = clamp(normalizedValue, 0.0, 1.0);
    
    float4 outputColor = float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
    outputSlice.write(outputColor, gid);
}

// MARK: - Performance Optimized Windowing
// Single-pass windowing optimized for real-time interaction

kernel void fastCTWindowing(
    texture2d<uint, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant WindowingParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    // Read and convert in single operation
    uint rawPixel = inputTexture.read(gid).r;
    float ctValue = float(rawPixel) - 32768.0;
    
    // Fast windowing without intermediate floating point
    float windowMin = params.windowCenter - (params.windowWidth * 0.5);
    float normalizedValue = (ctValue - windowMin) / params.windowWidth;
    normalizedValue = clamp(normalizedValue, 0.0, 1.0);
    
    // Output as grayscale RGBA
    float4 outputColor = float4(normalizedValue, normalizedValue, normalizedValue, 1.0);
    outputTexture.write(outputColor, gid);
}
