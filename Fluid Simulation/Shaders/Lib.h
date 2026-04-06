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

float smoothingKernel(float radius, float dst);
float smoothingKernelDerivative(float radius, float dst);
float calculateDensity(float2 point, const device Particle *particles, FrameUniforms uniforms);
float convertDensityToPressure(float density, float targetDensity, float pressureMultiplier);
float2 calculatePressureForce(uint particleIndex, const device Particle *particles, FrameUniforms uniforms, float2 seed);

inline float rand(float2 co) {
    return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
}

float2 randomDirection(float2 seed);

#endif /* Lib_h */
