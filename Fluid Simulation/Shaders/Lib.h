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
float2 calculatePressureForce(uint particleIndex, const device Particle *particles, FrameUniforms uniforms);

#endif /* Lib_h */
