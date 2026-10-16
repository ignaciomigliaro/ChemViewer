#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position;
    float4 color;
    float pointSize;
};

struct Uniforms {
    float4x4 modelViewProjection;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
};

vertex VertexOut atomVertex(
    uint vertexID [[vertex_id]],
    const device Vertex *vertices [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]])
{
    VertexOut out;
    out.position = uniforms.modelViewProjection * float4(vertices[vertexID].position, 1.0);
    out.color = vertices[vertexID].color;
    out.pointSize = vertices[vertexID].pointSize;
    return out;
}

fragment float4 atomFragment(VertexOut in [[stage_in]], float2 point [[point_coord]])
{
    float2 p = point * 2.0 - 1.0;
    float radius2 = dot(p, p);
    if (radius2 > 1.0) discard_fragment();
    float z = sqrt(max(0.0, 1.0 - radius2));
    float3 normal = normalize(float3(p.x, -p.y, z));
    float3 light = normalize(float3(-0.35, 0.5, 1.0));
    float diffuse = 0.28 + 0.72 * max(dot(normal, light), 0.0);
    float specular = pow(max(dot(reflect(-light, normal), float3(0, 0, 1)), 0.0), 24.0) * 0.35;
    return float4(in.color.rgb * diffuse + specular, in.color.a);
}

vertex VertexOut bondVertex(
    uint vertexID [[vertex_id]],
    const device Vertex *vertices [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]])
{
    VertexOut out;
    out.position = uniforms.modelViewProjection * float4(vertices[vertexID].position, 1.0);
    out.color = vertices[vertexID].color;
    out.pointSize = 1.0;
    return out;
}

fragment float4 bondFragment(VertexOut in [[stage_in]])
{
    return in.color;
}
