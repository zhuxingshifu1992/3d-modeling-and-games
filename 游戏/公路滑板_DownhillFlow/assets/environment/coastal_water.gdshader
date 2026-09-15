shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D grain_texture : filter_linear_mipmap, repeat_enable;
varying vec3 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec2 p = world_position.xz;
    vec2 drift_a = vec2(TIME * 0.0014, TIME * 0.0007);
    vec2 drift_b = vec2(-TIME * 0.0008, TIME * 0.0011);
    // Two rotated, independently advected noise fields avoid periodic wave trains.
    vec2 p0 = p * 0.0033 + drift_a;
    vec2 p1 = mat2(vec2(0.788, 0.616), vec2(-0.616, 0.788)) * p * 0.0097 + drift_b;
    vec2 p2 = p * 0.025 + drift_a * 1.9;
    float epsilon = 0.002;
    vec2 d = vec2(epsilon, 0.0);
    vec2 slope_a = vec2(texture(grain_texture, p0 + d).r - texture(grain_texture, p0 - d).r,
                        texture(grain_texture, p0 + d.yx).r - texture(grain_texture, p0 - d.yx).r);
    vec2 slope_b = vec2(texture(grain_texture, p1 + d).r - texture(grain_texture, p1 - d).r,
                        texture(grain_texture, p1 + d.yx).r - texture(grain_texture, p1 - d.yx).r);
    vec2 slope_c = vec2(texture(grain_texture, p2).r, texture(grain_texture, p2 + vec2(0.39, 0.62)).r) - vec2(0.5);
    float distance_to_camera = length(world_position - CAMERA_POSITION_WORLD);
    float detail_fade = 1.0 - smoothstep(100.0, 750.0, distance_to_camera);
    vec2 slope = slope_a * 0.72 + slope_b * 0.43 + slope_c * detail_fade * 0.07;
    vec3 normal_world = normalize(vec3(slope.x, 1.0, slope.y));
    NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
    float offshore = 1.0 - smoothstep(-1100.0, -240.0, world_position.x);
    ALBEDO = mix(vec3(0.008, 0.060, 0.084), vec3(0.004, 0.022, 0.048), offshore);
    ROUGHNESS = mix(0.28, 0.40, smoothstep(300.0, 4000.0, distance_to_camera));
    SPECULAR = 0.52;
    METALLIC = 0.04;
}
