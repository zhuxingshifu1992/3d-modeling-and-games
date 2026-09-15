shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D rock_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec3 n = normalize(world_normal);
    vec3 w = pow(abs(n), vec3(4.0));
    w /= max(dot(w, vec3(1.0)), 0.00001);
    vec3 p = world_position / 3.8;
    vec3 rock = texture(rock_diff, p.zy).rgb * w.x
              + texture(rock_diff, p.xz).rgb * w.y
              + texture(rock_diff, p.xy).rgb * w.z;
    vec3 arm = texture(rock_arm, p.zy).rgb * w.x
             + texture(rock_arm, p.xz).rgb * w.y
             + texture(rock_arm, p.xy).rgb * w.z;
    vec2 nx = texture(rock_nor, p.zy).xy * 2.0 - 1.0;
    vec2 ny = texture(rock_nor, p.xz).xy * 2.0 - 1.0;
    vec2 nz = texture(rock_nor, p.xy).xy * 2.0 - 1.0;
    vec3 bump = vec3(0.0, nx.y, nx.x) * w.x
              + vec3(ny.x, 0.0, ny.y) * w.y
              + vec3(nz.x, nz.y, 0.0) * w.z;
    // The grass/rock landscape photograph spans 15 m rather than a tiny lawn tile.
    vec2 ground_uv = world_position.xz / 15.0;
    vec3 ground = texture(ground_diff, ground_uv).rgb;
    vec2 ground_bump = texture(ground_nor, ground_uv).xy * 2.0 - 1.0;
    float cover = COLOR.r * smoothstep(0.13, 0.49, n.y);
    // Photographic colour provides cracks and mineral grains at metric scale.
    float mineral = dot(rock, vec3(0.2126, 0.7152, 0.0722));
    vec3 coastal_rock = mix(rock, vec3(mineral), 0.86) * vec3(1.15, 1.13, 1.0);
    // Match living coastal vegetation while preserving the photographed stones.
    float vegetation = smoothstep(0.015, 0.16, ground.g - ground.b);
    vec3 living_ground = mix(ground, ground * vec3(0.44, 0.94, 0.62), vegetation);
    ALBEDO = mix(coastal_rock, living_ground * 0.86, cover);
    ALBEDO = mix(ALBEDO, coastal_rock * 0.78, COLOR.g * 0.7);
    vec3 shaded_n = normalize(n + mix(bump, vec3(ground_bump.x, 0.0, ground_bump.y), cover) * 0.7);
    NORMAL = normalize((VIEW_MATRIX * vec4(shaded_n, 0.0)).xyz);
    ROUGHNESS = clamp(mix(arm.g, 0.98, cover), 0.72, 1.0);
    AO = mix(arm.r, 1.0, cover) * 0.35 + 0.65;
    AO_LIGHT_AFFECT = 0.3;
    SPECULAR = 0.27;
}
