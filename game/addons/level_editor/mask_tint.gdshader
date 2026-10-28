shader_type canvas_item;

// A greyscale mask shown as a tinted, translucent layer: the mask value is
// the coverage, the tint its colour.

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float opacity = 0.6;

void fragment() {
	float amount = texture(TEXTURE, UV).r;
	COLOR = vec4(tint.rgb, amount * opacity * tint.a);
}
