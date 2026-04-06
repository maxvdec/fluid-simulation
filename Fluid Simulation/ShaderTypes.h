//
//  ShaderTypes.h
//  Fluid Simulation
//
//  Created by Max Van den Eynde on 06/04/2026.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
#else
#include <simd/simd.h>
#endif

typedef struct {
    vector_float2 position;
    vector_float3 color;
} Particle;

typedef struct {
    vector_float2 viewportSize;
    float gravity;
    float pointSize;
    uint32_t particleCount;
    float deltaTime;
    vector_float3 particleColor;
} FrameUniforms;

typedef enum BufferIndex {
    BufferIndexParticles = 0,
    BufferIndexUniforms = 1
} BufferIndex;

typedef enum TextureIndex {
    TextureIndexRenderTarget = 0
} TextureIndex;

#endif /* ShaderTypes_h */
