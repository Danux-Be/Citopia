shader_type canvas_item;

// Frosted-glass blur of the screen behind the menu: 12 samples spread on a
// disk (golden-angle spiral) average into a very soft, artefact-free haze.

uniform float strength : hint_range(0.0, 3.0) = 2.5;
uniform float darken : hint_range(0.0, 1.0) = 0.16;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

vec2 disk_offset(float i, float n, float radius) {
	float a = i * 2.39996322973; // golden angle
	float r = radius * sqrt((i + 0.5) / n);
	return vec2(cos(a), sin(a)) * r;
}

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE * strength;
	vec3 sum = texture(screen_tex, SCREEN_UV).rgb * 0.5;
	for (int i = 0; i < 12; i++) {
		sum += texture(screen_tex, SCREEN_UV + disk_offset(float(i), 12.0, 4.0) * ps).rgb / 12.0 * 0.5;
	}
	COLOR = vec4(mix(sum, vec3(0.03, 0.04, 0.06), darken), 1.0);
}
