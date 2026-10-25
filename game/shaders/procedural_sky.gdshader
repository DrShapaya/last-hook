shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, fog_disabled;

// High-performance procedural sky & cloud shader for Last Hook.
// Single-pass, branchless 2D FBM with silver lining and dual cloud layers.
// Fully compatible with GL Compatibility (GLES3), mobile GPUs, and desktop.

uniform vec3 top_color : source_color = vec3(0.18, 0.44, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.80, 0.95);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.55, 0.66, 0.80);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.74);

uniform vec2 sun_pos = vec2(0.28, 0.82);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.46;
uniform float sky_time = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform float aspect = 1.0;

// High-speed analytical 2D hash
float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Smooth 2D value noise
float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 4-octave Fractional Brownian Motion with rotation
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	// 2D rotation matrix to avoid grid artifacts
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * noise2d(p);
		p = rot * p * 2.04 + vec2(1.7, 0.9);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	// UV.y is 0 at top, 1 at horizon
	float height = clamp(1.0 - UV.y, 0.0, 1.0);

	// Natural non-linear sky dome gradient
	vec3 sky = mix(horizon_color, top_color, pow(height, 0.75));

	// Atmospheric sun aura / golden haze
	vec2 sky_coords = vec2((UV.x - 0.5) * aspect + 0.5, height);
	float sun_dist = distance(sky_coords, sun_pos);
	float sun_glow = exp(-sun_dist * 3.8);
	sky += sun_color * sun_glow * 0.38;

	// High-altitude delicate cirrus wisps
	vec2 cirrus_uv = vec2(UV.x * aspect * 2.2, height * 1.5) + vec2(sky_time * 0.005, 0.0) + cloud_offset * 0.04;
	float cirrus_fbm = fbm(cirrus_uv * 2.0);
	float cirrus = smoothstep(0.55, 0.82, cirrus_fbm) * 0.32 * smoothstep(0.15, 0.7, height);
	sky = mix(sky, mix(cloud_shadow, cloud_lit, 0.85), cirrus);

	// Mid-altitude fluffy cumulus clouds
	// Warp domain for organic, billowing shapes
	vec2 cloud_uv = vec2(UV.x * aspect * 1.6, height * 1.1) + vec2(sky_time * 0.012, 0.0) + cloud_offset * 0.12;
	vec2 warp = vec2(
		noise2d(cloud_uv * 1.8 + vec2(0.0, sky_time * 0.004)),
		noise2d(cloud_uv * 1.8 + vec2(4.3, 1.7))
	) * 0.32;

	float cloud_noise = fbm(cloud_uv + warp);

	// Horizon mask: fade clouds gracefully near the bottom horizon
	float horizon_fade = smoothstep(0.06, 0.35, height);

	// Soft cloud coverage and thickness
	float coverage_threshold = 1.0 - cloud_coverage * 0.85;
	float cloud_density_val = smoothstep(coverage_threshold, coverage_threshold + 0.36, cloud_noise) * horizon_fade;

	if (cloud_density_val > 0.001) {
		// Silver lining: sample noise towards the sun direction
		vec2 sun_dir = normalize(sun_pos - sky_coords);
		float sun_sample = fbm(cloud_uv + warp - sun_dir * 0.07);
		float rim = clamp(cloud_density_val - sun_sample, 0.0, 1.0);

		// Inner volume shading (soft self-shadowing)
		float core = pow(cloud_density_val, 0.7);
		vec3 cloud_tone = mix(cloud_shadow, cloud_lit, clamp(core * 0.8 + rim * 1.6, 0.0, 1.0));

		// Golden edge illumination when facing sun
		cloud_tone += sun_color * pow(rim, 2.0) * 0.65;

		// Composite clouds over the sky dome
		sky = mix(sky, cloud_tone, cloud_density_val);
	}

	// Warm horizon mist at the very bottom
	float horizon_haze = pow(1.0 - height, 4.0) * 0.65;
	sky = mix(sky, horizon_color * 1.06, horizon_haze);

	ALBEDO = sky;
}
