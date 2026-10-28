shader_type canvas_item;
render_mode unshaded;

// Level start: the menu's slate closes over the screen and opens as a soft
// iris round the climber, with a thin gold rim riding its edge.

uniform vec2 size = vec2(540.0, 960.0);
uniform vec2 center = vec2(270.0, 600.0);
uniform float radius = 0.0;
uniform float feather = 18.0;
uniform vec4 tint : source_color = vec4(0.14, 0.196, 0.239, 1.0);
uniform vec4 rim : source_color = vec4(1.0, 0.82, 0.42, 1.0);
uniform float rim_strength = 1.0;

void fragment() {
	float d = distance(UV * size, center);
	float cover = smoothstep(radius - feather, radius + feather, d);
	// The rim fades in with the opening and thins as it grows.
	float ring = exp(-pow((d - radius - feather * 0.6) / max(2.0, feather * 0.35), 2.0)) * rim_strength;
	vec3 color = mix(tint.rgb, rim.rgb, clamp(ring, 0.0, 1.0));
	COLOR = vec4(color, clamp(cover * tint.a + ring * rim.a * (1.0 - cover), 0.0, 1.0));
}
