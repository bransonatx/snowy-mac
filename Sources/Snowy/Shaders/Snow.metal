#include <metal_stdlib>
using namespace metal;

struct FrameUniforms { float2 viewport; float time; float padding; };
struct SnowVertex { float2 position; float2 material; };
struct ParticleInstance { float2 position; float radius; float opacity; };
struct DriftOut { float4 position [[position]]; float2 material; float2 point; };
struct FlakeOut { float4 position [[position]]; float2 uv; float opacity; };

float4 project(float2 point, constant FrameUniforms &frame) {
    return float4(point.x / frame.viewport.x * 2 - 1, 1 - point.y / frame.viewport.y * 2, 0, 1);
}

vertex DriftOut driftVertex(uint id [[vertex_id]], const device SnowVertex *vertices [[buffer(0)]],
                            constant FrameUniforms &frame [[buffer(1)]]) {
    SnowVertex v = vertices[id];
    return { project(v.position, frame), v.material, v.position };
}

fragment half4 driftFragment(DriftOut in [[stage_in]]) {
    float shade = smoothstep(0.0, 1.0, in.material.x);
    float grain = fract(52.9829189 * fract(dot(in.point, float2(0.06711056, 0.00583715))));
    half3 color = mix(half3(0.76, 0.84, 0.93), half3(0.99, 0.995, 1.0), half(shade));
    color += half((grain - 0.5) * 0.012);
    half alpha = half(in.material.y);
    return half4(color * alpha, alpha);
}

vertex FlakeOut flakeVertex(uint id [[vertex_id]], uint instance [[instance_id]],
                            const device ParticleInstance *particles [[buffer(0)]],
                            constant FrameUniforms &frame [[buffer(1)]]) {
    const float2 corners[6] = { {-1,-1}, {1,-1}, {-1,1}, {1,-1}, {1,1}, {-1,1} };
    ParticleInstance p = particles[instance];
    float2 uv = corners[id];
    return { project(p.position + uv * (p.radius + 0.6), frame), uv, p.opacity };
}

fragment half4 flakeFragment(FlakeOut in [[stage_in]]) {
    float distance = length(in.uv);
    half alpha = half((1 - smoothstep(0.30, 1.0, distance)) * in.opacity);
    return half4(half3(0.96, 0.98, 1.0) * alpha, alpha);
}

// ---- Fall: leaves ---------------------------------------------------------------------------

struct LeafInstance { float2 position; float size; float angle; float look; float opacity; float shade; float flip; };
struct LeafOut {
    float4 position [[position]];
    float2 uv;
    float2 shadow [[flat]];
    float look [[flat]];
    float opacity [[flat]];
    float shade [[flat]];
};

// The fill under a pile only closes the gaps between leaves; it fades out toward the top so
// the leaves themselves make the ragged outline.
fragment half4 litterFragment(DriftOut in [[stage_in]]) {
    float shade = in.material.x;
    half3 color = mix(half3(0.17, 0.09, 0.04), half3(0.30, 0.16, 0.06), half(shade));
    half alpha = half(in.material.y * (1 - smoothstep(0.35, 0.95, shade)) * 0.9);
    return half4(color * alpha, alpha);
}

vertex LeafOut leafVertex(uint id [[vertex_id]], uint instance [[instance_id]],
                          const device LeafInstance *leaves [[buffer(0)]],
                          constant FrameUniforms &frame [[buffer(1)]]) {
    const float2 corners[6] = { {-1,-1}, {1,-1}, {-1,1}, {1,-1}, {1,1}, {-1,1} };
    LeafInstance leaf = leaves[instance];
    // Leaf space: y runs along the midrib, tip at -1 and stem at +1. The quad leaves room
    // for the stem and the drop shadow.
    float2 uv = corners[id] * 1.35;
    float c = cos(leaf.angle), s = sin(leaf.angle);
    float2 local = float2(uv.x * leaf.flip, uv.y) * leaf.size;
    float2 point = leaf.position + float2(local.x * c - local.y * s, local.x * s + local.y * c);
    // The shadow falls down and to the right on screen whichever way the leaf is turned.
    const float2 light = float2(0.10, 0.17);
    float2 shadow = float2((light.x * c + light.y * s) / leaf.flip, -light.x * s + light.y * c);
    return { project(point, frame), uv, shadow, leaf.look, leaf.opacity, leaf.shade };
}

// Negative inside the leaf. Not a true distance, but smooth enough to antialias.
static float leafShape(float2 p, float kind) {
    float t = clamp(p.y, -1.0, 1.0);
    float body = pow(max(0.0, 1.0 - t * t), 0.72);
    float d;
    if (kind < 0.5) {
        // Pointed oval, a little wider toward the stem.
        d = abs(p.x) - 0.50 * body * (1.0 + 0.22 * t);
    } else if (kind < 1.5) {
        // Oak: a long blade with rounded lobes down each side.
        d = abs(p.x) - 0.40 * body * (1.0 + 0.34 * sin(t * 9.0 + 1.2)) * (1.0 + 0.15 * t);
    } else {
        // Maple: five points fanned around the stem end.
        float2 q = float2(p.x, p.y - 0.18);
        float angle = atan2(q.x, -q.y);
        float lobe = pow(abs(cos(angle * 2.5)), 1.6);
        float reach = (0.36 + 0.60 * lobe) * (abs(angle) > 2.0 ? 0.62 : 1.0);
        d = length(q) - reach;
    }
    d = max(d, abs(p.y) - 1.0);
    // Stem.
    float stem = max(abs(p.x) - 0.045, abs(p.y - 1.08) - 0.2);
    return min(d, stem);
}

static half3 leafColor(float t) {
    const half3 stops[5] = {
        half3(0.40, 0.23, 0.10),   // brown
        half3(0.66, 0.15, 0.07),   // red
        half3(0.90, 0.41, 0.08),   // orange
        half3(0.96, 0.67, 0.12),   // amber
        half3(0.74, 0.72, 0.20)    // yellow-green
    };
    float scaled = clamp(t, 0.0, 0.999) * 4.0;
    int index = int(scaled);
    return mix(stops[index], stops[index + 1], half(scaled - float(index)));
}

fragment half4 leafFragment(LeafOut in [[stage_in]]) {
    float kind = floor(in.look);
    float d = leafShape(in.uv, kind);
    float edge = max(0.03, fwidth(d));
    float cover = 1.0 - smoothstep(-edge, edge, d);
    float cast = (1.0 - smoothstep(-0.12, 0.14, leafShape(in.uv - in.shadow, kind))) * 0.30;
    half3 color = leafColor(fract(in.look));
    // One half catches more light, the midrib and the rim are darker.
    color *= half(in.uv.x > 0.0 ? 1.07 : 0.90);
    color *= half(1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.07, abs(in.uv.x))));
    color *= half(1.0 - 0.28 * smoothstep(-0.20, 0.0, d));
    color *= half(in.shade);
    half alpha = half(cover);
    half under = half(cast) * (1 - alpha);
    half opacity = half(in.opacity);
    return half4(color * alpha * opacity, (alpha + under) * opacity);
}
