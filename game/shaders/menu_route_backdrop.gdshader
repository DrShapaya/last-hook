shader_type canvas_item;
render_mode unshaded;

// Menu backdrop: the route's mountains in the game's own low-poly manner.
// A sky with a sun and thin high cloud, then four ranges from far to near.
// Each range is faceted (its crest is straight segments), every slope has a
// sunlit and a shaded face, far peaks carry snow, and haze lies between the
// ranges. Two palettes blend while the card strip moves, so a swipe changes
// the mood as far as the finger has gone. One pass, a few dozen cheap
// operations a pixel: fine on phones. A small dither keeps the long sky
// gradient free of bands on 8-bit screens.

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
// How much of the far peaks is under snow (0 in the desert).
uniform float snow_a = 0.4;
uniform float snow_b = 0.4;
// rgb tint, a strength; motes fall (snow) or drift (dust, pollen).
uniform vec4 mote_a = vec4(1.0, 1.0, 0.9, 0.18);
uniform vec4 mote_b = vec4(1.0, 1.0, 0.9, 0.18);
uniform float fall_a = 0.3;
uniform float fall_b = 0.3;

float hash1(float n) {
	return fract(sin(n) * 43758.5453123);
}

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Straight segments between random heights: a faceted crest.
float facet(float x, float seed) {
	float i = floor(x);
	return mix(hash1(i * 1.37 + seed), hash1((i + 1.0) * 1.37 + seed), fract(x));
}

// A range's crest height (0..1) at x: big faces with smaller ones on them.
float crest(float x, float seed) {
	float h = facet(x, seed) * 0.62 + facet(x * 2.3 + 4.1, seed + 9.0) * 0.27 + facet(x * 5.2 + 1.7, seed + 21.0) * 0.11;
	// Peaks a little sharper than the valleys.
	return h * h * (2.2 - 1.2 * h);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
	           mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
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
	float snow = mix(snow_a, snow_b, t);
	vec2 uv = UV;
	// One screen pixel in UV height, for clean edges at any resolution.
	float px = max(fwidth(uv.y), 0.0005);

	// --- Sky: deep at the top, pale and warm at the horizon.
	vec3 col = mix(sky_top, sky_low, smoothstep(0.0, 0.58, uv.y));
	vec2 sun = (uv - vec2(0.76, 0.17)) * vec2(aspect, 1.0);
	float sun_d = length(sun);
	col = mix(col, glow, exp(-sun_d * sun_d * 16.0) * 0.5);
	col = mix(col, mix(glow, vec3(1.0), 0.5), smoothstep(0.034, 0.028, sun_d) * 0.85);
	// Thin high cloud: long soft streaks, slowly drifting.
	vec2 cloud_uv = vec2(uv.x * aspect * 2.4 + time * 0.004, uv.y * 11.0);
	float cloud = value_noise(cloud_uv) * 0.6 + value_noise(cloud_uv * vec2(2.3, 1.7) + 3.0) * 0.4;
	cloud = smoothstep(0.56, 0.82, cloud) * smoothstep(0.06, 0.16, uv.y) * smoothstep(0.42, 0.24, uv.y);
	col = mix(col, mix(vec3(1.0), glow, 0.35), cloud * 0.42);

	// --- Ranges, far to near.
	float x = uv.x * aspect;
	float drift = time * 0.0035;
	for (int layer = 0; layer < 4; layer++) {
		float depth = float(layer) / 3.0;
		float base = 0.43 + depth * 0.25;
		float height = 0.2 - depth * 0.07;
		float scale = 4.2 + depth * 3.0;
		float seed = 11.0 + float(layer) * 37.0;
		float sx = x * scale + drift * (1.0 + depth * 2.5);
		float h = crest(sx, seed);
		float line = base - h * height;
		float body = smoothstep(line - px, line + px, uv.y);
		if (body <= 0.0) continue;
		// Faces: a slope facing the sun (on the right) is lit, one facing away
		// is shaded. The slope is read up the face along a diagonal, so the
		// edge between two faces runs down from each peak at an angle, as on
		// a faceted rock, not straight down the screen.
		float below = (uv.y - line) / height;
		float lean = below * 0.9;
		float e = 0.01;
		float slope = crest(sx + lean + e, seed) - crest(sx + lean - e, seed);
		float lit = smoothstep(0.004, -0.004, slope);
		vec3 tone = mix(far, near, depth);
		vec3 shaded = tone * (0.8 - 0.05 * depth);
		vec3 sunny = tone * 1.1 + vec3(0.035, 0.03, 0.0);
		// The faces show most near the crest and melt into one tone below.
		float contrast = exp(-below * 2.2);
		vec3 face = mix(tone, mix(shaded, sunny, lit), contrast);
		// Snow on the far, high peaks: under the crest, ragged at its foot.
		float snow_depth = snow * (1.0 - depth) * max(0.0, h - 0.45) * 0.42;
		snow_depth *= 0.65 + 0.35 * facet(sx * 7.0, seed + 5.0);
		float on_snow = (1.0 - smoothstep(line + snow_depth - px, line + snow_depth + px, uv.y)) * step(0.001, snow_depth);
		vec3 snow_col = mix(vec3(0.80, 0.86, 0.95), vec3(0.98, 0.98, 0.96), lit);
		face = mix(face, snow_col, on_snow);
		// Haze: farther ranges sink into the sky's colour, and every range
		// fades into mist toward its foot.
		face = mix(face, sky_low, (1.0 - depth) * 0.42);
		face = mix(face, sky_low, smoothstep(line + 0.02, line + 0.3, uv.y) * (0.5 - depth * 0.35));
		// A thin lit rim along the crest on the sunny faces.
		float rim = (1.0 - smoothstep(line, line + px * 3.0, uv.y)) * lit * (0.35 - depth * 0.2);
		face = mix(face, glow, rim);
		col = mix(col, face, body);
	}
	// A deeper valley tone behind the actions keeps the stone buttons crisp.
	col = mix(col, near * 0.8, smoothstep(0.74, 1.05, uv.y) * 0.5);
	vec4 mote = mix(mote_a, mote_b, t);
	col += mote.rgb * mote.a * motes(uv, mix(fall_a, fall_b, t));
	// Dither against banding.
	col += (hash2(FRAGCOORD.xy) - 0.5) / 255.0;
	COLOR = vec4(col, 1.0);
}
