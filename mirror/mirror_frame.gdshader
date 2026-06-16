shader_type spatial;

render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec4 border_color : source_color = vec4(1.0, 0.0, 0.0, 1.0); // border color (RGBA)
uniform float border_thickness : hint_range(0.0, 0.5) = 0.1; // size of colored edge
uniform float smoothness : hint_range(0.001, 1.0) = 1.0; // softness of fade

void fragment() {
    // UV goes from (0,0) bottom-left to (1,1) top-right
    float dist_x = min(UV.x, 1.0 - UV.x);
    float dist_y = min(UV.y, 1.0 - UV.y);
    float dist = min(dist_x, dist_y);

    // Border intensity: 1 at edge, 0 past border_thickness
    float edge = 1.0 - smoothstep(0.0, border_thickness, dist);

    // Soft fade inside
    float alpha = smoothstep(0.0, smoothness, edge);

    ALBEDO = border_color.rgb;
    ALPHA = border_color.a * alpha;
}
