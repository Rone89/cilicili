#include <metal_stdlib>
using namespace metal;

struct DanmakuGlyphInstance {
    float4 motion; // startX, y, media start time, points / media second
    float4 geometry; // width, height, media end time, reserved
    float4 uv;
    float4 color;
};
struct DanmakuVertex {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float4 uvBounds [[flat]];
};
struct DanmakuStageUniforms {
    float4 transform; // scale, translation x/y
    float4 videoViewport; // origin x/y, width/height in points
};

vertex DanmakuVertex danmakuGlyphVertex(uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]], const device DanmakuGlyphInstance *instances [[buffer(0)]],
    constant float4 &frame [[buffer(1)]]) {
    const float2 corners[6] = {float2(0,0), float2(1,0), float2(0,1),
                              float2(0,1), float2(1,0), float2(1,1)};
    DanmakuGlyphInstance i = instances[instanceID];
    float2 corner = corners[vertexID];
    float age = max(0.0f, frame.z - i.motion.z);
    float2 point = float2(i.motion.x - age * i.motion.w, i.motion.y) + corner * i.geometry.xy;
    DanmakuVertex out;
    out.position = float4(point.x / frame.x * 2 - 1, 1 - point.y / frame.y * 2, 0, 1);
    out.uv = i.uv.xy + corner * i.uv.zw;
    out.color = i.color;
    out.uvBounds = i.uv;
    if (frame.z < i.motion.z || frame.z >= i.geometry.z) out.color.a = 0;
    return out;
}

vertex DanmakuVertex danmakuGlyphStageVertex(uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]], const device DanmakuGlyphInstance *instances [[buffer(0)]],
    constant float4 &frame [[buffer(1)]],
    constant DanmakuStageUniforms &stage [[buffer(2)]]) {
    const float2 corners[6] = {float2(0,0), float2(1,0), float2(0,1),
                              float2(0,1), float2(1,0), float2(1,1)};
    DanmakuGlyphInstance i = instances[instanceID];
    float2 corner = corners[vertexID];
    float age = max(0.0f, frame.z - i.motion.z);
    float2 logicalPoint = float2(i.motion.x - age * i.motion.w, i.motion.y) + corner * i.geometry.xy;
    float2 point = logicalPoint * stage.transform.x + stage.transform.yz + stage.videoViewport.xy;
    DanmakuVertex out;
    out.position = float4(point.x / frame.x * 2 - 1, 1 - point.y / frame.y * 2, 0, 1);
    out.uv = i.uv.xy + corner * i.uv.zw;
    out.color = i.color;
    out.uvBounds = i.uv;
    if (frame.z < i.motion.z || frame.z >= i.geometry.z) out.color.a = 0;
    return out;
}

fragment float4 danmakuGlyphFragment(DanmakuVertex in [[stage_in]],
    texture2d<float> atlas [[texture(0)]], sampler glyphSampler [[sampler(0)]]) {
    float2 pixel = 1.0f / float2(atlas.get_width(), atlas.get_height());
    float2 low = in.uvBounds.xy + pixel * 0.5f;
    float2 high = in.uvBounds.xy + in.uvBounds.zw - pixel * 0.5f;
    float fill = atlas.sample(glyphSampler, clamp(in.uv, low, high)).r;
    float outline = fill;
    for (int y = -1; y <= 1; ++y)
        for (int x = -1; x <= 1; ++x)
            outline = max(outline, atlas.sample(glyphSampler, clamp(in.uv + float2(x,y)*pixel, low, high)).r);
    // Premultiplied alpha: a black one-pixel outline behind the colored glyph.
    return float4(in.color.rgb * fill * in.color.a, outline * in.color.a);
}
