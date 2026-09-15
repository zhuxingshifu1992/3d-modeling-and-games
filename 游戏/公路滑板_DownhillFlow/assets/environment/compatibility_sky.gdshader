shader_type sky;
// The compatibility renderer writes the sky directly to an sRGB framebuffer.
// Apply a display curve to the radiance photograph before it clips to solid blue.
uniform sampler2D panorama : filter_linear;
void sky() {
	vec3 radiance = max(texture(panorama, SKY_COORDS).rgb * 0.75, vec3(0.0));
	COLOR = pow(radiance / (radiance + vec3(1.0)), vec3(1.0 / 2.2));
}
