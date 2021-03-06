//
//  Shaders.metal
//  MetalProjectStage-1
//
//  Created by Xcode Developer on 6/2/21.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;

matrix_float4x4 matrix4x4_translation(float tx, float ty, float tz)
{
    return (matrix_float4x4) {{
        { 1,   0,  0,  0 },
        { 0,   1,  0,  0 },
        { 0,   0,  1,  0 },
        { tx, ty, tz,  1 }
    }};
}

static matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis)
{
    axis = normalize(axis);
    float ct = cos(radians);
    float st = sin(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;
    
    return (matrix_float4x4) {{
        { ct + x * x * ci,     y * x * ci + z * st, z * x * ci - y * st, 0},
        { x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0},
        { x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0},
        {                   0,                   0,                   0, 1}
    }};
}

matrix_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ)
{
    float ys = 1 / tan(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);
    
    return (matrix_float4x4) {{
        { xs,   0,          0,  0 },
        {  0,  ys,          0,  0 },
        {  0,   0,         zs, -1 },
        {  0,   0, nearZ * zs,  0 }
    }};
}

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                               constant PerFrameDynamicUniforms &perFrameDynamicUniforms  [[ buffer(BufferIndexPerFrameDynamicUniforms) ]])
{
    vector_float3 rotationAxis = {1, 1, 0};
    matrix_float4x4 modelMatrix = matrix4x4_rotation(perFrameDynamicUniforms.rotation, rotationAxis);
    matrix_float4x4 viewMatrix = matrix4x4_translation(0.0, 0.0, -8.0);
    matrix_float4x4 modelViewMatrix = viewMatrix * modelMatrix;
    
    ColorInOut out;

    float4 position = float4(in.position, 1.0);
    
    out.position = uniforms.projectionMatrix * modelViewMatrix * position;
    out.texCoord = in.texCoord;

    return out;
}

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               texture2d<half, access::sample> colorMap [[ texture(0) ]],
                               sampler samplr [[sampler(0)]])
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    half4 colorSample   = colorMap.sample(samplr , in.texCoord.xy);

    return float4(colorSample);
}

//// Rec. 709 luma values for grayscale image conversion
//constant half3 kRec709Luma = half3(0.2126, 0.7152, 0.0722);
//
//// Grayscale compute kernel
//kernel void
//grayscaleKernel(texture2d<half, access::read>  inTexture  [[texture(0)]],
//                texture2d<half, access::write> outTexture [[texture(1)]],
//                uint2                          gid        [[thread_position_in_grid]])
//{
//    // Check if the pixel is within the bounds of the output texture
//    if((gid.x >= outTexture.get_width()) || (gid.y >= outTexture.get_height()))
//    {
//        // Return early if the pixel is out of bounds
//        return;
//    }
//
//    half4 inColor  = inTexture.read(gid);
//    half  gray     = dot(inColor.rgb, kRec709Luma);
//    outTexture.write(half4(gray, gray, gray, 1.0), gid);
//}
