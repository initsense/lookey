shader_type spatial;

render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D mirror_texture_linear : source_color, filter_linear_mipmap;
uniform sampler2D mirror_texture_nearest : source_color, filter_nearest_mipmap;
uniform bool use_mirror_texture_linear = true;

uniform sampler2D distortion_texture : source_color, filter_linear_mipmap;
uniform float distortion_strength : hint_range(0, 100, 0.01) = 10.0;

// --- Border effect controls ---
uniform vec4 border_color : source_color = vec4(1.0, 0.0, 0.0, 1.0); // border RGBA
uniform float border_thickness : hint_range(0.0, 1.0) = 0.2; // size of border
uniform float smoothness : hint_range(0.001, 3.0) = 1.5; // fade softness

void vertex() {
    // Flip mirror horizontally
    UV.x = 1.0 - UV.x;
}

void fragment() {
    // Get correct UV for both sides
    vec2 uv = FRONT_FACING ? UV : vec2(1.0 - UV.x, UV.y);

    // --- Mirror sampling ---
    float distortion_offset = texture(distortion_texture, uv).r;
    distortion_offset = (distortion_offset * 2.0) - 1.0;
    vec2 distorted_uv = uv + (distortion_offset * distortion_strength / VIEWPORT_SIZE);

    vec4 mirror_sample = use_mirror_texture_linear
        ? texture(mirror_texture_linear, distorted_uv)
        : texture(mirror_texture_nearest, distorted_uv);

    vec4 mirror_color = mirror_sample * color;

    // --- Border calculation ---
    float dist_x = min(UV.x, 1.0 - UV.x);
    float dist_y = min(UV.y, 1.0 - UV.y);
    float dist = min(dist_x, dist_y);

    float edge = 1.0 - smoothstep(0.0, border_thickness, dist);
    float border_alpha = smoothstep(0.0, smoothness, edge);

    // --- Combine mirror + border ---
    vec3 final_rgb = mix(mirror_color.rgb, border_color.rgb, border_alpha);
    float final_alpha = mix(mirror_color.a, border_color.a, border_alpha);

    ALBEDO = final_rgb;
    ALPHA  = final_alpha;
}
