//
//  Implementations.metal
//  Fluid Simulation
//
//  Created by Max Van den Eynde on 06/04/2026.
//

#include <metal_stdlib>
using namespace metal;

#include "Lib.h"

float smoothingKernel(float radius, float dst) {
    float volume = PI * pow(radius, 8) / 4;
    float value = max(0.0, pow(radius, 2) - pow(dst, 2));
    return pow(value, 3) / volume;
}

float calculateDensity(float2 point, const device Particle *particles, FrameUniforms uniforms) {
    float density = 0;
    float mass = 1;
    
    for (uint i = 0; i < uniforms.particleCount; ++i) {
        Particle p = particles[i];
        float dst = length(p.position - point);
        float influence = smoothingKernel(uniforms.smoothingRadius, dst);
        density += mass * influence;
    }
    
    return density;
}

float convertDensityToPressure(float density, float targetDensity, float pressureMultiplier) {
    float densityError = density - targetDensity;
    float pressure = densityError * pressureMultiplier;
    return pressure;
}
