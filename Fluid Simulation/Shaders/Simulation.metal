//
//  Simulation.metal
//  Fluid Simulation
//
//  Created by Max Van den Eynde on 06/04/2026.
//

#include <metal_stdlib>
using namespace metal;

#include "Lib.h"

float2 getGravity(FrameUniforms uniforms) {
    return float2(0.0, -uniforms.gravity);
}

inline void resolveCollisions(thread Particle &p, constant FrameUniforms &uniforms) {
    float radius = uniforms.pointSize * 0.5;
    float2 halfBoundsSize = uniforms.boundingBox * 0.5 - float2(radius);

    if (p.predictedPosition.x > halfBoundsSize.x) {
        p.predictedPosition.x = halfBoundsSize.x;
        if (p.velocity.x > 0.0) {
            p.velocity.x *= -1.0 * uniforms.collisionDamping;
        }
    } else if (p.predictedPosition.x < -halfBoundsSize.x) {
        p.predictedPosition.x = -halfBoundsSize.x;
        if (p.velocity.x < 0.0) {
            p.velocity.x *= -1.0 * uniforms.collisionDamping;
        }
    }

    if (p.predictedPosition.y > halfBoundsSize.y) {
        p.predictedPosition.y = halfBoundsSize.y;
        if (p.velocity.y > 0.0) {
            p.velocity.y *= -1.0 * uniforms.collisionDamping;
        }
    } else if (p.predictedPosition.y < -halfBoundsSize.y) {
        p.predictedPosition.y = -halfBoundsSize.y;
        if (p.velocity.y < 0.0) {
            p.velocity.y *= -1.0 * uniforms.collisionDamping;
        }
    }
}

kernel void calculateDensities(device Particle *particles [[buffer(BufferIndexParticles)]],
                               constant FrameUniforms &uniforms [[buffer(BufferIndexUniforms)]],
                               const device LookoutKey *spatialLookup [[buffer(BufferIndexLookup)]],
                               const device int *startIndices [[buffer(BufferIndexStartIndices)]],
                               uint id [[thread_position_in_grid]]) {
    if (id >= uniforms.particleCount) return;
    Particle p = particles[id];
    
    if (uniforms.isPaused) {
        particles[id] = p;
        return;
    }
    
    p.density = calculateDensity(p.predictedPosition, particles, spatialLookup, startIndices, uniforms) * uniforms.densityMultiplier;
    p.pressure = calculateLambda(id, particles, spatialLookup, startIndices, uniforms, float2(id, p.density));
    
    particles[id] = p;
}

kernel void solveDensityConstraints(device Particle *particles [[buffer(BufferIndexParticles)]],
                                    constant FrameUniforms &uniforms [[buffer(BufferIndexUniforms)]],
                                    const device LookoutKey *spatialLookup [[buffer(BufferIndexLookup)]],
                                    const device int *startIndices [[buffer(BufferIndexStartIndices)]],
                                    device float2 *positionDeltas [[buffer(BufferIndexPositionDeltas)]],
                                    uint id [[thread_position_in_grid]]) {
    if (id >= uniforms.particleCount) return;
    Particle p = particles[id];
    
    if (uniforms.isPaused) {
        positionDeltas[id] = float2(0.0);
        return;
    }

    float2 delta = calculatePositionDelta(id, particles, spatialLookup, startIndices, uniforms, float2(id, p.pressure));
    positionDeltas[id] = delta * uniforms.pressureMultiplier;
}

kernel void applyDensityConstraints(device Particle *particles [[buffer(BufferIndexParticles)]],
                                    constant FrameUniforms &uniforms [[buffer(BufferIndexUniforms)]],
                                    const device float2 *positionDeltas [[buffer(BufferIndexPositionDeltas)]],
                                    uint id [[thread_position_in_grid]]) {
    if (id >= uniforms.particleCount) return;
    Particle p = particles[id];

    if (uniforms.isPaused) {
        particles[id] = p;
        return;
    }

    p.predictedPosition += positionDeltas[id];

    if (uniforms.activateCollisions == 1) {
        resolveCollisions(p, uniforms);
    }

    particles[id] = p;
}

kernel void updateParticles(device Particle *particles [[buffer(BufferIndexParticles)]],
                            constant FrameUniforms &uniforms [[buffer(BufferIndexUniforms)]],
                            uint id [[thread_position_in_grid]]) {
    if (id >= uniforms.particleCount) return;
    Particle p = particles[id];
    p.color = uniforms.particleColor;

    if (uniforms.isPaused) {
        p.predictedPosition = p.position;
        particles[id] = p;
        return;
    }

    float2 velocity = (p.predictedPosition - p.position) / max(uniforms.deltaTime, 0.0001);
    p.velocity = velocity;

    if (uniforms.activateCollisions == 1) {
        resolveCollisions(p, uniforms);
    }

    p.position = p.predictedPosition;
    p.pressure = convertDensityToPressure(p.density, uniforms.targetDensity, uniforms.pressureMultiplier);
    particles[id] = p;
}
