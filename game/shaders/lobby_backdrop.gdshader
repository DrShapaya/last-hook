shader_type canvas_item;
render_mode unshaded;

// Atmospheric, painterly background for the Lobby and Menus of Last Hook.
// Replaces primitive stepped rectangles and jagged triangles with continuous
// multi-layered alpine horizons, valley mist, soft drifting clouds and sun glow.

uniform bool veil = false;
uniform float veil_opacity : hint_range(0.0, 1.0) = 0.92;
uniform float time = 0.0;
uniform float aspect = 0.5625; // default 9:16 portrait

uniform vec3 sky_top : source_color = vec3(0.22, 0.48, 0.78);
uniform vec3 sky_horizon : source_color = vec3(0.72, 0.86, 0.96);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.82);

uniform vec3 far_mountain : source_color = vec3(0.60, 0.76, 0.90);
uniform vec3 mid_mountain : source_color = vec3(0.42, 0.59, 0.75);
uniform vec3 near_mountain : source_color = vec3(0.26, 0.41, 0.55);
uniform vec3 valley_mist : source_color = vec3(0.80, 0.90, 0.97);

uniform vec3 veil_slate : source_color = vec3(0.11, 0.16, 0.21);

// Fast 1D noise for natural mountain silhouettes
float hash1(float n) {
	return fract(sin(n) * 43758.5453123);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash1(i), hash1(i + 1.0), f);
}

float mountain_height(float x, float seed_val) {
	float p = x + seed_val;
	float n = noise1(p * 1.4) * 0.55;
	n += noise1(p * 3.1) * 0.28;
	n += noise1(p * 6.8) * 0.12;
	n += noise1(p * 14.5) * 0.05;
	// Sharpen mountain peaks slightly for majestic alpine crests
	return pow(n, 1.2);
}

// Simple 2D noise for subtle drifting clouds
float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
	           mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float cloud_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise2(p);
		p = p * 2.05 + vec2(1.7, 0.9);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;

	if (veil) {
		// Elegant frosted slate veil over paused runs
		vec2 center_dist = (uv - vec2(0.5, 0.5)) * vec2(1.0, 1.0 / aspect);
		float vignette = length(center_dist) * 0.5;
		vec3 v_col = mix(veil_slate, veil_slate * 0.72, clamp(vignette, 0.0, 1.0));
		COLOR = vec4(v_col, veil_opacity);
	} else {
		// Smooth non-linear sky gradient
		vec3 color = mix(sky_top, sky_horizon, pow(uv.y, 0.85));

		// Warm sun aura in the upper region
		vec2 sun_coord = vec2(0.24, 0.28);
		float sun_dist = distance(vec2(uv.x * aspect, uv.y), vec2(sun_coord.x * aspect, sun_coord.y));
		float sun_glow = exp(-sun_dist * 3.2);
		color += sun_color * sun_glow * 0.42;

		// Soft drifting cloud wisps in the upper sky
		vec2 cloud_uv = vec2(uv.x * aspect * 2.0 + time * 0.008, uv.y * 1.8);
		float clouds = cloud_fbm(cloud_uv);
		float cloud_alpha = smoothstep(0.48, 0.78, clouds) * smoothstep(0.7, 0.15, uv.y) * 0.35;
		color = mix(color, mix(vec3(0.92, 0.96, 1.0), sun_color, sun_glow * 0.8), cloud_alpha);

		// Aspect-adjusted coordinate for horizontal mountain silhouettes
		float x_coord = uv.x * aspect * 3.5;
		float aa = 0.003; // Anti-aliasing width

		// --- LAYER 1: Far Mountain Peaks (highest, most atmospheric haze) ---
		float h1 = 0.50 - mountain_height(x_coord * 0.8, 12.3) * 0.18;
		float mask1 = smoothstep(h1 - aa, h1 + aa, uv.y);
		if (mask1 > 0.0) {
			// Shading: crest has rim light, base melts into valley mist
			float depth_in_layer = clamp((uv.y - h1) / 0.25, 0.0, 1.0);
			vec3 layer1_col = mix(far_mountain * 1.08, valley_mist, depth_in_layer * 0.75);
			color = mix(color, layer1_col, mask1);
		}

		// --- LAYER 2: Mid-Range Ridge (richer tone, distinct crags) ---
		float h2 = 0.64 - mountain_height(x_coord * 1.15, 45.7) * 0.22;
		float mask2 = smoothstep(h2 - aa, h2 + aa, uv.y);
		if (mask2 > 0.0) {
			float depth_in_layer = clamp((uv.y - h2) / 0.22, 0.0, 1.0);
			// Subtle sunward side lighting
			float slope = mountain_height(x_coord * 1.15 + 0.015, 45.7) - mountain_height(x_coord * 1.15 - 0.015, 45.7);
			vec3 lit_mid = mix(mid_mountain, mid_mountain * 1.15, clamp(-slope * 6.0, 0.0, 1.0));
			vec3 layer2_col = mix(lit_mid, valley_mist * 0.95, depth_in_layer * 0.65);
			color = mix(color, layer2_col, mask2);
		}

		// --- LAYER 3: Foreground Crest (deep, solid mountain base) ---
		float h3 = 0.78 - mountain_height(x_coord * 1.5, 89.1) * 0.16;
		float mask3 = smoothstep(h3 - aa, h3 + aa, uv.y);
		if (mask3 > 0.0) {
			float depth_in_layer = clamp((uv.y - h3) / 0.25, 0.0, 1.0);
			vec3 layer3_col = mix(near_mountain, near_mountain * 0.82, depth_in_layer * 0.6);
			color = mix(color, layer3_col, mask3);
		}

		COLOR = vec4(color, 1.0);
	}
}
