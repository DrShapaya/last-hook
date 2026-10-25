shader_type canvas_item;
render_mode unshaded;

// Menu backdrop: a calm sky gradient, a soft sun glow and three layered
// ridges, coloured per route. Two palettes blend while the card strip moves,
// so a swipe changes the mood as far as the finger has gone.

uniform float blend : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform float aspect = 0.5625; // screen width / height
uniform vec3 sky_top_a : source_color = vec3(0.31, 0.62, 0.91);
uniform vec3 sky_top_b : source_color = vec3(0.31, 0.62, 0.91);
uniform vec3 sky_low_a : source_color = vec3(0.81, 0.91, 0.97);
uniform vec3 sky_low_b : source_color = vec3(0.81, 0.91, 0.97);
uniform vec3 far_a : source_color = vec3(0.61, 0.77, 0.89);
uniform vec3 far_b : source_color = vec3(0.61, 0.77, 0.89);
uniform vec3 near_a : source_color = vec3(0.27, 0.42, 0.56);
uniform vec3 near_b : source_color = vec3(0.27, 0.42, 0.56);
uniform vec3 glow_a : source_color = vec3(1.0, 0.95, 0.82);
uniform vec3 glow_b : source_color = vec3(1.0, 0.95, 0.82);
// rgb tint, a strength; motes fall (snow) or drift (dust, pollen).
uniform vec4 mote_a = vec4(1.0, 1.0, 0.9, 0.18);
uniform vec4 mote_b = vec4(1.0, 1.0, 0.9, 0.18);
uniform float fall_a = 0.3;
uniform float fall_b = 0.3;

float hash1(float n) {
	return fract(sin(n) * 43758.5453123);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash1(i), hash1(i + 1.0), f);
}

float ridge(float x, float seed) {
	float p = x + seed;
	float n = noise1(p * 1.3) * 0.58 + noise1(p * 3.2) * 0.27 + noise1(p * 7.1) * 0.15;
	return pow(n, 1.25);
}

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Two layers of soft round motes on a jittered grid.
float motes(vec2 uv, float fall) {
	float total = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float density = layer == 0 ? 9.0 : 15.0;
		float speed = (layer == 0 ? 0.035 : 0.022) * (0.4 + fall);
		vec2 grid = vec2(uv.x * aspect, uv.y) * density;
		grid.y -= time * speed * density;
		grid.x += sin(time * 0.3 + uv.y * 6.0 + float(layer)) * 0.25 * (1.0 - fall);
		vec2 cell = floor(grid);
		vec2 local = fract(grid);
		float seed = hash2(cell + float(layer) * 17.0);
		if (seed > 0.6) {
			vec2 centre = vec2(hash2(cell + 3.1), hash2(cell + 7.7)) * 0.7 + 0.15;
			float radius = (layer == 0 ? 0.08 : 0.055) * (0.6 + seed * 0.5);
			float twinkle = 0.7 + 0.3 * sin(time * 1.3 + seed * 40.0);
			total += smoothstep(radius, radius * 0.25, length(local - centre)) * twinkle * (layer == 0 ? 1.0 : 0.6);
		}
	}
	return total;
}

void fragment() {
	float t = smoothstep(0.0, 1.0, blend);
	vec3 sky_top = mix(sky_top_a, sky_top_b, t);
	vec3 sky_low = mix(sky_low_a, sky_low_b, t);
	vec3 far = mix(far_a, far_b, t);
	vec3 near = mix(near_a, near_b, t);
	vec3 glow = mix(glow_a, glow_b, t);
	vec2 uv = UV;
	vec3 col = mix(sky_top, sky_low, smoothstep(0.0, 0.62, uv.y));
	// Sun glow, high on the right.
	vec2 sun = (uv - vec2(0.78, 0.2)) * vec2(aspect, 1.0);
	col = mix(col, glow, exp(-dot(sun, sun) * 14.0) * 0.55);
	// Ridges: far and pale, then nearer and deeper. They drift very slowly.
	float x = uv.x * aspect * 2.2;
	float drift = time * 0.004;
	for (int layer = 0; layer < 3; layer++) {
		float depth = float(layer) / 2.0;
		float base = 0.46 + depth * 0.16;
		float height = 0.17 - depth * 0.04;
		float line = base - ridge(x * (1.0 + depth * 0.6) + drift * (1.0 + depth * 2.0), 11.0 + float(layer) * 37.0) * height;
		float body = smoothstep(line - 0.002, line + 0.004, uv.y);
		vec3 tone = mix(far, near, depth);
		// Valley mist fades each ridge toward the sky at its foot.
		tone = mix(tone, sky_low, (1.0 - depth) * 0.25 * smoothstep(line, line + 0.25, uv.y));
		col = mix(col, tone, body);
	}
	// Deeper valley tone behind the actions keeps the stone buttons crisp.
	col = mix(col, near * 0.82, smoothstep(0.7, 1.05, uv.y) * 0.55);
	vec4 mote = mix(mote_a, mote_b, t);
	col += mote.rgb * mote.a * motes(uv, mix(fall_a, fall_b, t));
	COLOR = vec4(col, 1.0);
}
