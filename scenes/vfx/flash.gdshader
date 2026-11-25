shader_type canvas_item;
// White-flash material shared by the player and enemies.
// Unity: Player.flashMat / Enemy.flashMat swapped onto the SpriteRenderer. Here a single uniform
// blends the (modulated) sprite colour towards white; alpha is kept.
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), flash);
}
