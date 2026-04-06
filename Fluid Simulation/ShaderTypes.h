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
    vector_float2 velocity;
    float density;
    float pressure;
    vector_float3 color;
} Particle;

typedef struct {
    vector_float2 viewportSize;
    float gravity;
    float pointSize;
    uint32_t particleCount;
    float deltaTime;
    vector_float3 particleColor;
    vector_float2 boundingBox;
    int isPaused;
    float collisionDamping;
    int activateCollisions;
    float smoothingRadius;
    
    float pressureMultiplier;
    float targetDensity;
    float densityMultiplier;
} FrameUniforms;

typedef struct {
    int index;
    int cellKey;
} LookoutKey;

typedef enum BufferIndex {
    BufferIndexParticles = 0,
    BufferIndexUniforms = 1,
    BufferIndexLookup = 2,
    BufferIndexStartIndices = 3,
} BufferIndex;

typedef enum TextureIndex {
    TextureIndexRenderTarget = 0
} TextureIndex;

#endif /* ShaderTypes_h */
