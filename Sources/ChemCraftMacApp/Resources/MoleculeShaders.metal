#include <metal_stdlib>
using namespace metal;
struct Vertex { float3 position; float4 color; float3 normal; };
struct Instance { float4 origin; float4 x; float4 y; float4 z; float4 color; };
struct Uniforms { float4x4 modelViewProjection; float4x4 normalMatrix; float4 style; };
struct VertexOut { float4 position [[position]]; float4 color; float3 normal; float outline; };
vertex VertexOut atomVertex(uint id [[vertex_id]], uint instanceID [[instance_id]], const device Vertex *vertices [[buffer(0)]], constant Uniforms &u [[buffer(1)]], const device Instance *instances [[buffer(2)]]) {
    VertexOut out;
    Instance instance = instances[instanceID];
    float3 p = vertices[id].position;
    float3 n = vertices[id].normal;
    float3 position = instance.origin.xyz + instance.x.xyz * p.x + instance.y.xyz * p.y + instance.z.xyz * p.z;
    out.position = u.modelViewProjection * float4(position, 1);
    out.color = instance.color;
    out.outline = u.style.x;
    out.normal = (u.normalMatrix * float4(normalize(instance.x.xyz * n.x + instance.y.xyz * n.y + instance.z.xyz * n.z), 0)).xyz;
    return out;
}

// Native adaptation of xyzrender's MIT-licensed Paton HLS gradient.
float3 patonSRGB(float3 c) { return select(c * 12.92, 1.055 * pow(max(c, 0.0), float3(1.0 / 2.4)) - 0.055, c > 0.0031308); }
float3 patonLinear(float3 c) { return select(c / 12.92, pow((c + 0.055) / 1.055, float3(2.4)), c > 0.04045); }
float3 patonHSL(float3 c) {
    float hi = max(c.r, max(c.g, c.b)), lo = min(c.r, min(c.g, c.b));
    float delta = hi - lo, l = (hi + lo) * 0.5;
    if (delta < 0.000001) return float3(0, 0, l);
    float h = hi == c.r ? fmod((c.g - c.b) / delta + 6.0, 6.0) : (hi == c.g ? (c.b - c.r) / delta + 2.0 : (c.r - c.g) / delta + 4.0);
    return float3(h * 60.0, delta / (1.0 - abs(2.0 * l - 1.0)), l);
}
float3 patonRGB(float3 hsl) {
    float c = (1.0 - abs(2.0 * hsl.z - 1.0)) * hsl.y;
    float h = hsl.x / 60.0, x = c * (1.0 - abs(fmod(h, 2.0) - 1.0));
    float3 rgb = h < 1 ? float3(c,x,0) : h < 2 ? float3(x,c,0) : h < 3 ? float3(0,c,x) : h < 4 ? float3(0,x,c) : h < 5 ? float3(x,0,c) : float3(c,0,x);
    return rgb + hsl.z - c * 0.5;
}
float3 patonGradient(float3 linearColor, float3 normal) {
    float3 base = patonSRGB(linearColor), hsl = patonHSL(base);
    float3 hi = hsl, lo = hsl;
    hi.x = fmod(hsl.x + (fmod(60.0 - hsl.x + 540.0, 360.0) - 180.0) * 0.15 + 360.0, 360.0);
    hi.y *= 0.9; hi.z += 0.1 * (1.0 - hi.z);
    lo.x = fmod(hsl.x + (fmod(240.0 - hsl.x + 540.0, 360.0) - 180.0) * 0.15 + 360.0, 360.0);
    lo.y += (1.0 - lo.y) * 0.1; lo.z *= 0.7;
    float2 focal = float2(-0.34, 0.34), d = normal.xy - focal;
    float a = max(dot(d,d), 0.000001), b = 2.0 * dot(focal,d), c = dot(focal,focal) - 1.32 * 1.32;
    float boundary = (-b + sqrt(max(b*b - 4*a*c, 0.0))) / (2*a);
    float t = clamp(1.0 / max(boundary, 0.000001), 0.0, 1.0);
    float3 color = t < 0.4 ? mix(patonRGB(hi), base, t / 0.4) : mix(base, patonRGB(lo), (t - 0.4) / 0.6);
    return patonLinear(color);
}

fragment float4 atomFragment(VertexOut in [[stage_in]]) {
    float3 n = normalize(in.normal);
    if (in.outline > 0.5 && abs(n.z) < (in.outline > 1.5 ? 0.27 : 0.30)) return float4(mix(float3(0.008), float3(1), in.outline > 1.5 ? in.color.a : 0.0), 1);
    // The camera looks along +Z; the front-facing surface normal points -Z.
    float3 light = normalize(float3(-0.45, 0.65, -1.0));
    float diffuse = 0.42 + 0.58 * max(dot(n, light), 0.0);
    float3 halfVector = normalize(light + float3(0, 0, -1));
    float specular = 0.22 * pow(max(dot(n, halfVector), 0.0), 40.0);
    float rim = smoothstep(0.0, 0.30, abs(n.z));
    float3 color = in.outline > 1.5 ? patonGradient(in.color.rgb, n) : in.color.rgb * diffuse + specular;
    if (in.outline < 1.5) color *= mix(0.32, 1.0, rim);
    if (in.outline > 1.5) color = patonLinear(mix(patonSRGB(color), float3(1), in.color.a));
    return float4(color, 1);
}
vertex VertexOut bondVertex(uint id [[vertex_id]], uint instanceID [[instance_id]], const device Vertex *vertices [[buffer(0)]], constant Uniforms &u [[buffer(1)]], const device Instance *instances [[buffer(2)]]) {
    VertexOut out;
    Instance instance = instances[instanceID];
    float3 p = vertices[id].position;
    float3 n = vertices[id].normal;
    float3 position = instance.origin.xyz + instance.x.xyz * p.x + instance.y.xyz * p.y + instance.z.xyz * p.z;
    out.position = u.modelViewProjection * float4(position, 1);
    out.color = instance.color;
    out.outline = u.style.x;
    out.normal = (u.normalMatrix * float4(normalize(instance.x.xyz * n.x + instance.y.xyz * n.y + instance.z.xyz * n.z), 0)).xyz;
    return out;
}

fragment float4 bondFragment(VertexOut in [[stage_in]]) {
    float light = 0.48 + 0.52 * max(dot(normalize(in.normal), normalize(float3(-0.45, 0.65, -1))), 0.0);
    return float4(mix(in.color.rgb * light, float3(1), in.outline > 1.5 ? in.color.a : 0.0), 1);
}
