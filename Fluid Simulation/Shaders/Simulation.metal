//
//  Simulation.metal
//  Fluid Simulation
//
//  Created by Max Van den Eynde on 06/04/2026.
//

#include <metal_stdlib>
using namespace metal;

#include "../ShaderTypes.h"

kernel void updateParticles(device Particle *particles [[buffer(BufferIndexParticles)]],
                            constant FrameUniforms &uniforms [[buffer(BufferIndexUniforms)]],
                            uint id [[thread_position_in_grid]]) {
    if (id >= uniforms.particleCount) return;
    Particle p = particles[id];
    p.color = uniforms.particleColor;
    
    particles[id] = p;
}
