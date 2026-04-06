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

float smoothingKernelDerivative(float radius, float dst) {
    if (dst >= radius) return 0;
    float f = pow(radius, 2) - pow(dst, 2);
    float scale = -24 / (PI * pow(radius, 8));
    return scale * dst * pow(f, 2);
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

float2 calculatePressureForce(uint particleIndex, const device Particle *particles, FrameUniforms uniforms, float2 seed) {
    float2 pressureForce = float2(0.0);
    Particle thisParticle = particles[particleIndex];
    
    for (uint otherIndex = 0; otherIndex < uniforms.particleCount; ++otherIndex) {
        if (particleIndex == otherIndex) continue;
        
        Particle otherParticle = particles[otherIndex];
        float2 offset = otherParticle.position - thisParticle.position;
        float dst = length(offset);
        float2 dir = (dst == 0) ? randomDirection(seed) : offset / dst;
        float slope = smoothingKernelDerivative(uniforms.smoothingRadius, dst);
        // mass = 1
        float density = otherParticle.density;
        pressureForce += otherParticle.pressure * dir * slope * 1 / density;
    }
    
    return pressureForce;
}

float2 randomDirection(float2 seed) {
    float angle = rand(seed) * 2.0 * M_PI_F;
    return float2(cos(angle), sin(angle));
}
