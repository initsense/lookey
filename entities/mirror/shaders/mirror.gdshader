// Based on Mirror3D (https://github.com/Norodix/Mirror3D)
// Copyright (c) 2025 Joyless, Norodix — MIT License (see entities/mirror/LICENSE.md)
shader_type spatial;

render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D mirror_texture_linear : source_color, filter_linear;
uniform sampler2D mirror_texture_nearest : source_color, filter_nearest;
uniform bool use_mirror_texture_linear = true;

uniform sampler2D distortion_texture : source_color, filter_linear_mipmap;
uniform float distortion_strength : hint_range(0, 100, 0.01) = 10.0;

// --- Border effect controls ---
uniform vec4 border_color : source_color = vec4(1.0, 0.0, 0.0, 1.0); // border RGBA
uniform float border_thickness : hint_range(0.0, 1.0) = 0.2; // size of border
uniform float smoothness : hint_range(0.001, 3.0) = 1.5; // fade softness

// --- Reflected views (glass seen inside other mirrors) ---
// One view per outer mirror. Slot 0 uses mirror_texture_* and border_color.
// Each slot remembers the outer mirror camera it was rendered for, and the glass
// shows the slot whose camera matches the one drawing it.
uniform bool use_reflected_views = false;
uniform vec3 reflected_observer_0 = vec3(1e9);
uniform vec3 reflected_observer_1 = vec3(1e9);
uniform vec3 reflected_observer_2 = vec3(1e9);
uniform sampler2D reflected_texture_linear_1 : source_color, filter_linear;
uniform sampler2D reflected_texture_nearest_1 : source_color, filter_nearest;
uniform sampler2D reflected_texture_linear_2 : source_color, filter_linear;
uniform sampler2D reflected_texture_nearest_2 : source_color, filter_nearest;
uniform vec4 reflected_border_color_1 : source_color = vec4(1.0);
uniform vec4 reflected_border_color_2 : source_color = vec4(1.0);

int pick_reflected_view(vec3 camera_position) {
    int slot = 0;
    float best = distance(camera_position, reflected_observer_0);
    float d1 = distance(camera_position, reflected_observer_1);
    if (d1 < best) {
        best = d1;
        slot = 1;
    }
    if (distance(camera_position, reflected_observer_2) < best) {
        slot = 2;
    }
    return slot;
}

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

    int slot = use_reflected_views ? pick_reflected_view(CAMERA_POSITION_WORLD) : 0;
    vec4 mirror_sample;
    vec4 frame_color = border_color;
    if (slot == 1) {
        mirror_sample = use_mirror_texture_linear
            ? texture(reflected_texture_linear_1, distorted_uv)
            : texture(reflected_texture_nearest_1, distorted_uv);
        frame_color = reflected_border_color_1;
    } else if (slot == 2) {
        mirror_sample = use_mirror_texture_linear
            ? texture(reflected_texture_linear_2, distorted_uv)
            : texture(reflected_texture_nearest_2, distorted_uv);
        frame_color = reflected_border_color_2;
    } else {
        mirror_sample = use_mirror_texture_linear
            ? texture(mirror_texture_linear, distorted_uv)
            : texture(mirror_texture_nearest, distorted_uv);
    }

    vec4 mirror_color = mirror_sample * color;

    // --- Border calculation ---
    float dist_x = min(UV.x, 1.0 - UV.x);
    float dist_y = min(UV.y, 1.0 - UV.y);
    float dist = min(dist_x, dist_y);

    float edge = 1.0 - smoothstep(0.0, border_thickness, dist);
    float border_alpha = smoothstep(0.0, smoothness, edge);

    // --- Combine mirror + border ---
    vec3 final_rgb = mix(mirror_color.rgb, frame_color.rgb, border_alpha);
    float final_alpha = mix(mirror_color.a, frame_color.a, border_alpha);

    ALBEDO = final_rgb;
    ALPHA  = final_alpha;
}
