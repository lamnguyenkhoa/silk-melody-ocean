shader_type canvas_item;
// Radial vignette, port of URP's Vignette (non-rounded, black, centre (0.5, 0.5)).
// Unity: PPVolumeController animates `intensity` (base 0.3 in Global Volume Profile).
uniform float intensity : hint_range(0.0, 1.0) = 0.3;
// URP stores smoothness * 5; Global Volume Profile smoothness is the default 0.2.
uniform float smoothness : hint_range(0.01, 5.0) = 1.0;

void fragment() {
	vec2 dist = abs(UV - vec2(0.5)) * intensity * 3.0;
	float factor = pow(clamp(1.0 - dot(dist, dist), 0.0, 1.0), smoothness);
	COLOR = vec4(0.0, 0.0, 0.0, 1.0 - factor);
}
