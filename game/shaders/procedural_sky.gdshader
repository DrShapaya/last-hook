shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, fog_disabled;

// Procedural sky behind the climb: a gradient dome with a sun aura, high
// cirrus, two layers of cumulus and three distant mountain ranges that always
// stand on the bottom of the frame. As the climber gains height the ranges
// sink and a sea of clouds rises below, so altitude is felt, never shown as
// shapes floating in the air. Pixels hidden behind the rock are rejected by
// the depth test before this runs.

uniform vec3 top_color : source_color = vec3(0.18, 0.44, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.80, 0.95);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.55, 0.66, 0.80);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.74);
uniform vec3 range_far : source_color = vec3(0.56, 0.70, 0.84);
uniform vec3 range_mid : source_color = vec3(0.37, 0.53, 0.68);
uniform vec3 range_near : source_color = vec3(0.23, 0.37, 0.43);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.3;

uniform vec2 sun_pos = vec2(0.28, 0.82);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.46;
uniform float sky_time = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform float aspect = 1.0;
// Climbed height in world units and the camera's sideways position.
uniform float altitude = 0.0;
uniform float view_x = 0.0;
uniform float sky_seed = 0.0;

// Integer hashing of the noise lattice. The classic fract(sin(n) * big)
// and fract(p * big) hashes lose their precision on phone GPUs: the noise
// cells then break into hard-edged shards across the clouds. Integer
// arithmetic is exact on every device.
uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float hash_unit(uint x) {
	return float(hash_u(x) >> 8u) * (1.0 / 16777216.0);
}

float hash1(float n) {
	return hash_unit(uint(int(floor(n)) + 1048576));
}

float noise1(highp float x) {
	highp float i = floor(x);
	highp float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash1(i), hash1(i + 1.0), f);
}

// Ridged noise: sharp crests and soft valleys, like eroded ranges. The
// broad form alone (two octaves) decides which flank faces the sun, so the
// shading follows whole slopes instead of every small notch.
float ridge_octaves(highp float x, int octaves) {
	float v = 0.0;
	float a = 0.6;
	for (int i = 0; i < octaves; i++) {
		float n = 1.0 - abs(noise1(x) * 2.0 - 1.0);
		v += a * n * n;
		x = x * 2.13 + 13.1;
		a *= 0.38;
	}
	return v;
}

float ridge(float x) {
	return ridge_octaves(x, 4);
}

float hash2(vec2 p) {
	ivec2 q = ivec2(floor(p)) + ivec2(1048576);
	return hash_unit(uint(q.x) * 1597334677u ^ hash_u(uint(q.y)));
}

float noise2d(highp vec2 p) {
	highp vec2 i = floor(p);
	highp vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(highp vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * noise2d(p);
		p = rot * p * 2.04 + vec2(1.7, 0.9);
		a *= 0.5;
	}
	return v;
}

// One cumulus layer: rgb colour, a coverage. Billows come from a warped fbm;
// undersides darken and the edge facing the sun catches light.
vec4 cumulus(vec2 uv, float coverage, vec2 sky_coords) {
	vec2 warp = vec2(noise2d(uv * 1.7 + vec2(0.0, sky_time * 0.004)), noise2d(uv * 1.7 + vec2(4.3, 1.7))) * 0.34;
	float shape = fbm(uv + warp);
	float threshold = 0.72 - coverage * 0.42;
	float density = smoothstep(threshold, threshold + 0.22, shape);
	if (density < 0.002) {
		return vec4(0.0);
	}
	// Density a little lower down: high means a thick body above, so shade.
	float below = fbm(uv + warp + vec2(0.0, -0.09));
	float underside = clamp((below - shape) * 3.0 + 0.5, 0.0, 1.0);
	vec2 to_sun = normalize(sun_pos - sky_coords);
	float toward = noise2d((uv + warp - to_sun * 0.06) * 2.0);
	float rim = clamp(density - toward * 0.9, 0.0, 1.0);
	float light = clamp(0.35 + density * 0.55 - underside * 0.35 + rim * 0.9, 0.0, 1.0);
	vec3 tone = mix(cloud_shadow, cloud_lit, light);
	tone += sun_color * pow(rim, 2.0) * 0.5;
	return vec4(tone, density);
}

// A range layer: returns colour and coverage (1 below the crest line, so the
// range always continues down to the bottom of the frame).
vec4 range_layer(float x, float y, float base, float amplitude, vec3 tone, float snow, vec3 haze) {
	float crest = ridge(x);
	float line = base - crest * amplitude;
	float cover = smoothstep(line - 0.0015, line + 0.0015, y);
	if (cover <= 0.0) {
		return vec4(0.0);
	}
	// The flank facing the sun (from the left) is lit, the other shaded;
	// crests are a touch lighter than the feet of the range.
	// Sampling the form further out the deeper the pixel lies below the crest
	// slants the light/shade boundary like a real flank, never a vertical cut.
	float depth = y - line;
	float fx = x + depth * 2.4;
	float slope = ridge_octaves(fx + 0.12, 2) - ridge_octaves(fx - 0.12, 2);
	float lit = smoothstep(0.09, -0.09, slope + depth * 0.25);
	vec3 col = tone * mix(0.84, 1.12, lit) * mix(1.06, 0.94, smoothstep(line, line + 0.2, y));
	// Snow on the high crests, thinning down the flanks.
	float snow_line = 1.0 - snow * 0.55;
	float snow_depth = (crest - snow_line) * amplitude * 0.9;
	if (snow > 0.0 && crest > snow_line && y - line < snow_depth) {
		vec3 white = mix(vec3(0.74, 0.80, 0.88), vec3(0.96, 0.97, 0.99), lit);
		col = mix(col, white, smoothstep(snow_depth, snow_depth * 0.6, y - line));
	}
	// Valley mist rises from the foot of each range.
	col = mix(col, haze, smoothstep(line + 0.03, line + 0.24, y) * 0.55);
	return vec4(col, cover);
}

void fragment() {
	float y = UV.y;
	float height = clamp(1.0 - y, 0.0, 1.0);
	vec3 sky = mix(horizon_color, top_color, pow(height, 0.75));
	vec2 sky_coords = vec2((UV.x - 0.5) * aspect + 0.5, height);
	float sun_dist = distance(sky_coords, sun_pos);
	sky += sun_color * exp(-sun_dist * 3.8) * 0.38;

	// High cirrus wisps.
	// Cloud space is measured in view heights: several billows fit across a
	// narrow phone screen as well as a wide one.
	vec2 view = vec2(UV.x * aspect, height);
	vec2 cirrus_uv = view * vec2(5.0, 9.0) + vec2(sky_time * 0.01, 0.0) + cloud_offset * 0.2;
	float cirrus = smoothstep(0.55, 0.8, fbm(cirrus_uv)) * 0.35 * smoothstep(0.35, 0.8, height);
	sky = mix(sky, mix(cloud_shadow, cloud_lit, 0.85), cirrus);

	// Far cumulus, small and slow, behind the ranges.
	vec2 far_uv = view * vec2(6.5, 9.5) + vec2(sky_time * 0.012, 0.0) + cloud_offset * 0.3;
	vec4 far_cloud = cumulus(far_uv, cloud_coverage * 0.8, sky_coords);
	sky = mix(sky, mix(far_cloud.rgb, horizon_color, 0.25), far_cloud.a * smoothstep(0.08, 0.3, height));

	// Ranges sink as the climb gains height (near ones faster), and pan a
	// little with the camera. 0.0 altitude: the near range fills the lower
	// third; far above the route only the far crests remain.
	float rise = clamp(altitude / 120.0, 0.0, 1.6);
	float ax = (UV.x - 0.5) * aspect;
	vec3 haze = mix(horizon_color, cloud_lit, 0.25);
	vec4 far_range = range_layer(ax * 3.2 + view_x * 0.01 + sky_seed, y, 0.74 + rise * 0.16, 0.2, mix(range_far, horizon_color, 0.35), snow_amount, haze);
	sky = mix(sky, far_range.rgb, far_range.a);

	// Near cumulus drift in front of the far range.
	vec2 near_uv = view * vec2(3.6, 5.2) + vec2(sky_time * 0.02, 0.0) + cloud_offset * 0.6;
	vec4 near_cloud = cumulus(near_uv, cloud_coverage, sky_coords);
	sky = mix(sky, near_cloud.rgb, near_cloud.a * smoothstep(0.06, 0.35, height));

	vec4 mid_range = range_layer(ax * 2.3 + view_x * 0.02 + sky_seed * 1.7 + 40.0, y, 0.84 + rise * 0.3, 0.17, range_mid, snow_amount * 0.7, haze);
	sky = mix(sky, mid_range.rgb, mid_range.a);
	vec4 near_range = range_layer(ax * 1.6 + view_x * 0.035 + sky_seed * 2.3 + 90.0, y, 0.95 + rise * 0.5, 0.15, range_near, snow_amount * 0.35, haze);
	sky = mix(sky, near_range.rgb, near_range.a);

	// A sea of clouds rises over the sunk valleys once the climb is high.
	float sea_top = 1.08 - smoothstep(0.15, 1.0, rise) * 0.3;
	float sea_edge = sea_top - fbm(vec2(UV.x * aspect * 3.0 + sky_time * 0.01 + view_x * 0.02, 0.5)) * 0.07;
	float sea = smoothstep(sea_edge - 0.01, sea_edge + 0.03, y);
	if (sea > 0.0) {
		float puff = fbm(vec2(UV.x * aspect * 4.0 + sky_time * 0.008, y * 7.0));
		vec3 sea_tone = mix(cloud_lit, cloud_shadow, clamp((y - sea_edge) * 2.5 + (0.5 - puff) * 0.4, 0.0, 0.7));
		sky = mix(sky, sea_tone, sea);
	}

	// Soft haze along the very bottom.
	sky = mix(sky, horizon_color * 1.04, pow(clamp(y, 0.0, 1.0), 6.0) * 0.3);
	ALBEDO = sky;
}
