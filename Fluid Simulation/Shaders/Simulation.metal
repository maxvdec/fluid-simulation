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

    if (p.position.x > halfBoundsSize.x) {
        p.position.x = halfBoundsSize.x;
        p.velocity.x *= -1.0 * uniforms.collisionDamping;
    } else if (p.position.x < -halfBoundsSize.x) {
        p.position.x = -halfBoundsSize.x;
        p.velocity.x *= -1.0 * uniforms.collisionDamping;
    }

    if (p.position.y > halfBoundsSize.y) {
        p.position.y = halfBoundsSize.y;
        p.velocity.y *= -1.0 * uniforms.collisionDamping;
    } else if (p.position.y < -halfBoundsSize.y) {
        p.position.y = -halfBoundsSize.y;
        p.velocity.y *= -1.0 * uniforms.collisionDamping;
    }
}

kernel void updateParticles(device Particle *particles [[buffer(BufferIndexParticles)]],
                            constant FrameUniforms &uniforms [[buffer(BufferIndexUniforms)]],
                            uint id [[thread_position_in_grid]]) {
    if (id >= uniforms.particleCount) return;
    Particle p = particles[id];
    p.color = uniforms.particleColor;
    
    if (uniforms.isPaused) {
        particles[id] = p;
        return;
    }
    
    p.density = calculateDensity(p.position, particles, uniforms) * uniforms.densityMultiplier;
    p.pressure = convertDensityToPressure(p.density, uniforms.targetDensity, uniforms.pressureMultiplier);
    
    p.velocity += getGravity(uniforms) * uniforms.deltaTime;
    p.position += p.velocity * uniforms.deltaTime;
    
    if (uniforms.activateCollisions == 1) {
        resolveCollisions(p, uniforms);
    }
    
    particles[id] = p;
}
