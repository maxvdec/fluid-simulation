//
//  Lib.h
//  Fluid Simulation
//
//  Created by Max Van den Eynde on 06/04/2026.
//

#ifndef Lib_h
#define Lib_h

#include "../ShaderTypes.h"

#include <metal_stdlib>
using namespace metal;

constant float PI = 3.14159265358979323846;

inline int hashCell(int x, int y) {
    return (x * 15823) + (y * 973733);
}

inline int keyFromHash(int hash, uint particleCount) {
    int count = max(int(particleCount), 1);
    int key = hash % count;
    return key >= 0 ? key : key + count;
}

float smoothingKernel(float radius, float dst);
float smoothingKernelDerivative(float radius, float dst);
float calculateDensity(float2 point,
                       const device Particle *particles,
                       const device LookoutKey *spatialLookup,
                       const device int *startIndices,
                       FrameUniforms uniforms);
float2 smoothingKernelGradient(float2 offset, float radius, float2 seed);
float convertDensityToPressure(float density, float targetDensity, float pressureMultiplier);
float calculateLambda(uint particleIndex,
                      const device Particle *particles,
                      const device LookoutKey *spatialLookup,
                      const device int *startIndices,
                      FrameUniforms uniforms,
                      float2 seed);
float2 calculatePositionDelta(uint particleIndex,
                              const device Particle *particles,
                              const device LookoutKey *spatialLookup,
                              const device int *startIndices,
                              FrameUniforms uniforms,
                              float2 seed);
float artificialPressure(float distance, FrameUniforms uniforms);

inline float rand(float2 co) {
    return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
}

float2 randomDirection(float2 seed);

#endif /* Lib_h */
