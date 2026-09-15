shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D asphalt_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_arm : filter_linear_mipmap_anisotropic, repeat_enable;
void fragment() {
    // Source tile is a photographed 3 m square; road UV.x spans 9.6 metres.
    vec2 p = vec2(UV.x * 3.2, UV.y / 3.0);
    vec3 photo = texture(asphalt_diff, p).rgb;
    vec3 arm = texture(asphalt_arm, p).rgb;
    float wheel_wear = exp(-pow((UV.x - 0.26) * 10.0, 2.0))
                     + exp(-pow((UV.x - 0.74) * 10.0, 2.0));
    ALBEDO = photo * (0.56 - wheel_wear * 0.035);
    NORMAL_MAP = texture(asphalt_nor, p).rgb;
    NORMAL_MAP_DEPTH = 0.62;
    ROUGHNESS = clamp(arm.g + 0.09 - wheel_wear * 0.035, 0.72, 0.98);
    AO = 0.6 + arm.r * 0.4;
    SPECULAR = 0.28;
}
