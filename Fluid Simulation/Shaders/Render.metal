#include <metal_stdlib>
using namespace metal;

#include "Lib.h"

inline bool circle(float2 center, float2 pixel, float radius) {
    float2 d = pixel - center;
    float dist = length(d);
    return dist < radius;
}

inline bool rectOutline(float2 origin, float2 size, float2 pixel, float w) {
    float2 minP = origin;
       float2 maxP = origin + size;

       bool inside =
           pixel.x >= minP.x && pixel.x < maxP.x &&
           pixel.y >= minP.y && pixel.y < maxP.y;

       bool border =
           inside && (
               pixel.x < minP.x + w ||
               pixel.x >= maxP.x - w ||
               pixel.y < minP.y + w ||
               pixel.y >= maxP.y - w
           );

       return border;
}

float2 worldToPixel(float2 world, float2 viewportSize) {
    float2 center = viewportSize * 0.5;

    return float2(
        center.x + world.x,
        center.y - world.y
    );
}

float2 pixelToWorld(float2 pixel, float2 viewportSize) {
    float2 center = viewportSize * 0.5;

    return float2(
        pixel.x - center.x,
        center.y - pixel.y
    );
}

float3 colorPressure(float normalizedPressure) {
    float3 low = float3(0.08, 0.16, 0.38);
    float3 mid = float3(0.18, 0.9, 1.0);
    float3 high = float3(1.0, 0.45, 0.1);

    if (normalizedPressure < 0.0) {
        return mix(mid, low, saturate(-normalizedPressure));
    }

    return mix(mid, high, saturate(normalizedPressure));
}

kernel void renderParticlesToTexture(const device Particle *particles [[buffer(BufferIndexParticles)]],
                                     constant FrameUniforms &uniforms [[buffer(BufferIndexUniforms)]],
                                     texture2d<float, access::write> outputTexture [[texture(TextureIndexRenderTarget)]],
                                     uint2 gid [[thread_position_in_grid]]) {
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();

    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // Density color
    float2 pixel = float2(gid) + 0.5;
    float radius = uniforms.pointSize * 0.5;
    
    float3 color = float3(0.0, 0.0, 0.0);
    
    float2 viewportSize = float2(width, height);
    float2 worldPoint = pixelToWorld(pixel, viewportSize);
    
    float density = calculateDensity(worldPoint, particles, uniforms);
    float targetDensity = max(uniforms.targetDensity, 1e-5);
    float densityRatio = density / targetDensity;
    float signedPressure = (densityRatio - 1.0) * max(uniforms.pressureMultiplier, 1.0) * 0.25;
    color = colorPressure(tanh(signedPressure));
    
    
    // Draw Particles
    for (uint i = 0; i < uniforms.particleCount; ++i) {
        float2 center = worldToPixel(particles[i].position, viewportSize);
        
        if (circle(center, pixel, radius)) {
            color = particles[i].color;
        }
    }
    
    if (uniforms.activateCollisions == 1) {
        // Draw borders
        float borderWidth = 3.0;
        float2 rectSize = uniforms.boundingBox;
        float2 rectOrigin = float2(width, height) * 0.5 - rectSize * 0.5;
        
        if (rectOutline(rectOrigin, rectSize, pixel, borderWidth)) {
            color = float3(1.0, 1.0, 1.0);
        }
    }
    
    outputTexture.write(float4(color, 1.0), gid);
}

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

vertex FullscreenOut renderVertex(uint vid [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    float2 uvs[3] = {
        float2(0.0, 1.0),
        float2(2.0, 1.0),
        float2(0.0, -1.0)
    };

    FullscreenOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

fragment float4 renderFragment(FullscreenOut in [[stage_in]],
                               texture2d<float> renderedTexture [[texture(TextureIndexRenderTarget)]]) {
    constexpr sampler textureSampler(address::clamp_to_edge, filter::linear);
    return renderedTexture.sample(textureSampler, in.uv);
}
