shader_type canvas_item;

// Cheap 9-tap gaussian blur of the screen behind the menu, with a slight
// darkening so the menu panel reads clearly.

uniform float strength : hint_range(0.0, 8.0) = 2.5;
uniform float darken : hint_range(0.0, 1.0) = 0.25;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE * strength;
	vec4 sum = texture(screen_tex, SCREEN_UV) * 0.227027;
	sum += texture(screen_tex, SCREEN_UV + vec2( 1.3846153846, 0.0) * ps) * 0.3162162162;
	sum += texture(screen_tex, SCREEN_UV + vec2(-1.3846153846, 0.0) * ps) * 0.3162162162;
	sum += texture(screen_tex, SCREEN_UV + vec2( 3.2307692308, 0.0) * ps) * 0.0702702703;
	sum += texture(screen_tex, SCREEN_UV + vec2(-3.2307692308, 0.0) * ps) * 0.0702702703;
	sum += texture(screen_tex, SCREEN_UV + vec2(0.0,  1.3846153846) * ps) * 0.3162162162;
	sum += texture(screen_tex, SCREEN_UV + vec2(0.0, -1.3846153846) * ps) * 0.3162162162;
	sum += texture(screen_tex, SCREEN_UV + vec2(0.0,  3.2307692308) * ps) * 0.0702702703;
	sum += texture(screen_tex, SCREEN_UV + vec2(0.0, -3.2307692308) * ps) * 0.0702702703;
	COLOR = vec4(mix(sum.rgb, vec3(0.02, 0.03, 0.05), darken), 1.0);
}
