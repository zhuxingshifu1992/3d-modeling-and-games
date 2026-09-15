shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D landscape_photo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grain_texture : filter_linear_mipmap, repeat_enable;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec3 terrain_photo = texture(landscape_photo, world_position.xz / 190.0).rgb;
    float macro = texture(grain_texture, world_position.xz * 0.0007).r;
    float luminosity = dot(terrain_photo, vec3(0.2126, 0.7152, 0.0722));
    float upland = smoothstep(35.0, 250.0, world_position.y + macro * 75.0);
    vec3 forest = vec3(0.034, 0.10, 0.060);
    vec3 meadow = vec3(0.09, 0.145, 0.078);
    ALBEDO = mix(forest, meadow, upland) * (0.72 + luminosity * 1.7 + macro * 0.25);
    NORMAL = normalize((VIEW_MATRIX * vec4(normalize(world_normal), 0.0)).xyz);
    ROUGHNESS = 1.0;
    SPECULAR = 0.12;
}
