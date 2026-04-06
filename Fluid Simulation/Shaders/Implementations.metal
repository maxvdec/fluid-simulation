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
    radius = max(radius, 0.0001);
    if (dst >= radius) return 0;
    
    float volume = PI * pow(radius, 4) / 6;
    return (radius - dst) * (radius - dst) / volume;
}

float smoothingKernelDerivative(float radius, float dst) {
    radius = max(radius, 0.0001);
    if (dst >= radius) return 0;
    
    float scale = 12 / (PI * pow(radius, 4));
    return (dst - radius) * scale;
}

float2 smoothingKernelGradient(float2 offset, float radius, float2 seed) {
    float dst = length(offset);
    if (dst >= radius) return float2(0.0);

    float2 dir = (dst <= 0.0001) ? randomDirection(seed) : offset / dst;
    return smoothingKernelDerivative(radius, dst) * dir;
}

float calculateDensity(float2 point,
                       const device Particle *particles,
                       const device LookoutKey *spatialLookup,
                       const device int *startIndices,
                       FrameUniforms uniforms) {
    float density = 0;
    float mass = 1;

    float cellSize = max(uniforms.smoothingRadius, 0.0001);
    int centerX = int(floor(point.x / cellSize));
    int centerY = int(floor(point.y / cellSize));

    for (int offsetY = -1; offsetY <= 1; ++offsetY) {
        for (int offsetX = -1; offsetX <= 1; ++offsetX) {
            int hash = hashCell(centerX + offsetX, centerY + offsetY);
            int key = keyFromHash(hash, uniforms.particleCount);
            int startIndex = startIndices[key];
            if (startIndex < 0) continue;

            for (int lookupIndex = startIndex; lookupIndex < int(uniforms.particleCount); ++lookupIndex) {
                LookoutKey entry = spatialLookup[lookupIndex];
                if (entry.cellKey != key) break;

                Particle p = particles[entry.index];
                float dst = length(p.predictedPosition - point);
                float influence = smoothingKernel(cellSize, dst);
                density += mass * influence;
            }
        }
    }
    
    return density;
}

float convertDensityToPressure(float density, float targetDensity, float pressureMultiplier) {
    float safeTargetDensity = max(targetDensity, 0.0001);
    float compression = density / safeTargetDensity - 1.0;
    return compression * pressureMultiplier;
}

float calculateLambda(uint particleIndex,
                      const device Particle *particles,
                      const device LookoutKey *spatialLookup,
                      const device int *startIndices,
                      FrameUniforms uniforms,
                      float2 seed) {
    Particle thisParticle = particles[particleIndex];
    float safeTargetDensity = max(uniforms.targetDensity, 0.0001);
    float density = thisParticle.density;
    float constraint = density / safeTargetDensity - 1.0;

    float cellSize = max(uniforms.smoothingRadius, 0.0001);
    int centerX = int(floor(thisParticle.predictedPosition.x / cellSize));
    int centerY = int(floor(thisParticle.predictedPosition.y / cellSize));
    float2 gradientI = float2(0.0);
    float sumGradientSquares = 0.0;

    for (int offsetY = -1; offsetY <= 1; ++offsetY) {
        for (int offsetX = -1; offsetX <= 1; ++offsetX) {
            int hash = hashCell(centerX + offsetX, centerY + offsetY);
            int key = keyFromHash(hash, uniforms.particleCount);
            int startIndex = startIndices[key];
            if (startIndex < 0) continue;

            for (int lookupIndex = startIndex; lookupIndex < int(uniforms.particleCount); ++lookupIndex) {
                LookoutKey entry = spatialLookup[lookupIndex];
                if (entry.cellKey != key) break;

                uint otherIndex = uint(entry.index);
                if (particleIndex == otherIndex) continue;

                Particle otherParticle = particles[otherIndex];
                float2 gradientJ = smoothingKernelGradient(
                    thisParticle.predictedPosition - otherParticle.predictedPosition,
                    cellSize,
                    seed + float2(otherIndex, 0.0)
                ) / safeTargetDensity;
                sumGradientSquares += dot(gradientJ, gradientJ);
                gradientI += gradientJ;
            }
        }
    }

    sumGradientSquares += dot(gradientI, gradientI);
    return -constraint / (sumGradientSquares + uniforms.constraintRelaxation);
}

float artificialPressure(float distance, FrameUniforms uniforms) {
    float safeRadius = max(uniforms.smoothingRadius, 0.0001);
    float dq = safeRadius * 0.3;
    float denominator = max(smoothingKernel(safeRadius, dq), 0.0001);
    float ratio = smoothingKernel(safeRadius, distance) / denominator;
    return -uniforms.artificialPressureStrength * pow(ratio, 4.0);
}

float2 calculatePositionDelta(uint particleIndex,
                              const device Particle *particles,
                              const device LookoutKey *spatialLookup,
                              const device int *startIndices,
                              FrameUniforms uniforms,
                              float2 seed) {
    Particle thisParticle = particles[particleIndex];
    float safeTargetDensity = max(uniforms.targetDensity, 0.0001);
    float lambda = thisParticle.pressure;
    float2 delta = float2(0.0);

    float cellSize = max(uniforms.smoothingRadius, 0.0001);
    int centerX = int(floor(thisParticle.predictedPosition.x / cellSize));
    int centerY = int(floor(thisParticle.predictedPosition.y / cellSize));

    for (int offsetY = -1; offsetY <= 1; ++offsetY) {
        for (int offsetX = -1; offsetX <= 1; ++offsetX) {
            int hash = hashCell(centerX + offsetX, centerY + offsetY);
            int key = keyFromHash(hash, uniforms.particleCount);
            int startIndex = startIndices[key];
            if (startIndex < 0) continue;

            for (int lookupIndex = startIndex; lookupIndex < int(uniforms.particleCount); ++lookupIndex) {
                LookoutKey entry = spatialLookup[lookupIndex];
                if (entry.cellKey != key) break;

                uint otherIndex = uint(entry.index);
                if (particleIndex == otherIndex) continue;

                Particle otherParticle = particles[otherIndex];
                float2 offset = thisParticle.predictedPosition - otherParticle.predictedPosition;
                float distance = length(offset);
                float2 gradient = smoothingKernelGradient(
                    offset,
                    cellSize,
                    seed + float2(otherIndex, 1.0)
                );
                float correction = lambda + otherParticle.pressure + artificialPressure(distance, uniforms);
                delta += correction * gradient;
            }
        }
    }

    return delta / safeTargetDensity;
}

float2 randomDirection(float2 seed) {
    float angle = rand(seed) * 2.0 * M_PI_F;
    return float2(cos(angle), sin(angle));
}
