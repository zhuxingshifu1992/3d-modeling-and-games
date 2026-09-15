shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D leaf_diff : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D leaf_alpha : filter_linear_mipmap_anisotropic, repeat_disable;
void fragment() {
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
    vec3 photo = texture(leaf_diff, UV).rgb;
    ALBEDO = photo * COLOR.rgb;
    ALPHA = texture(leaf_alpha, UV).r;
    ALPHA_SCISSOR_THRESHOLD = 0.42;
    ROUGHNESS = 0.91;
    SPECULAR = 0.23;
    BACKLIGHT = photo * 0.14;
}
