shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, fog_disabled;

// Procedural sky behind the climb, in the low-poly look of the rock: a gradient
// dome, two layers of separate faceted clouds and three faceted mountain ranges
// standing on the bottom of the frame. The ranges sink out of the frame one by
// one as the climber gains height, so altitude is felt, never shown as shapes
// floating in the air. Pixels hidden behind the rock are rejected by the depth
// test before this runs.

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
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.4;
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

uint hash_cell(ivec2 cell, uint seed) {
	ivec2 q = cell + ivec2(1048576);
	return hash_u(uint(q.x) * 1597334677u ^ hash_u(uint(q.y) ^ seed));
}

// Unsmoothed noise is a broken line: everything built on it has straight
// edges and sharp corners, the outline of a low-poly model.
float line1(highp float x) {
	highp float i = floor(x);
	return mix(hash1(i), hash1(i + 1.0), x - i);
}

// Ridged broken line: sharp crests and straight flanks.
float ridge_octaves(highp float x, int octaves) {
	float v = 0.0;
	float a = 0.6;
	for (int i = 0; i < octaves; i++) {
		v += a * (1.0 - abs(line1(x) * 2.0 - 1.0));
		x = x * 2.13 + 13.1;
		a *= 0.42;
	}
	return v;
}

float cross2(vec2 a, vec2 b, vec2 p) {
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

bool in_triangle(vec2 p, vec2 a, vec2 b, vec2 c) {
	return cross2(a, b, p) >= 0.0 && cross2(b, c, p) >= 0.0 && cross2(c, a, p) >= 0.0;
}

// The triangle of a jittered mesh that holds p: xy its centroid, z a random
// value of its own. Shading from these alone gives a flat fill per triangle.
// Vertices move less than half a cell, so the two rows and columns of quads
// round p always hold its triangle.
vec3 facet(highp vec2 p, uint seed) {
	ivec2 near = ivec2(floor(p + 0.5));
	vec2 v[9];
	uint bits[9];
	for (int j = 0; j < 3; j++) {
		for (int i = 0; i < 3; i++) {
			ivec2 cell = near + ivec2(i - 1, j - 1);
			uint h = hash_cell(cell, seed);
			int index = j * 3 + i;
			bits[index] = h;
			v[index] = vec2(cell) + (vec2(float(h & 1023u), float((h >> 10u) & 1023u)) / 1023.0 - 0.5) * 0.6;
		}
	}
	for (int j = 0; j < 2; j++) {
		for (int i = 0; i < 2; i++) {
			int index = j * 3 + i;
			vec2 a = v[index];
			vec2 b = v[index + 1];
			vec2 c = v[index + 3];
			vec2 d = v[index + 4];
			uint h = bits[index];
			float first = float((h >> 22u) & 31u) / 31.0;
			float second = float(h >> 27u) / 31.0;
			if (((h >> 20u) & 1u) == 0u) {
				if (in_triangle(p, a, b, c)) { return vec3((a + b + c) / 3.0, first); }
				if (in_triangle(p, b, d, c)) { return vec3((b + d + c) / 3.0, second); }
			} else {
				if (in_triangle(p, a, b, d)) { return vec3((a + b + d) / 3.0, first); }
				if (in_triangle(p, a, d, c)) { return vec3((a + d + c) / 3.0, second); }
			}
		}
	}
	return vec3(p, 0.5);
}

// One layer of separate clouds: rgb colour, a coverage. Each cloud sits in a
// cell of its row and reaches at most one cell sideways: a heap of straight
// slopes above a shallow broken underside. Facets are lit from above and from
// the side of the sun.
vec4 cloud_layer(vec2 pos, vec2 cell, float coverage, uint seed, vec3 lit, vec3 shadow) {
	float row = floor(pos.y / cell.y);
	uint row_hash = hash_u(uint(int(row) + 1048576) ^ seed);
	vec2 g = vec2(pos.x / cell.x + float(row_hash & 255u) / 255.0, pos.y / cell.y);
	float column = floor(g.x);
	vec4 result = vec4(0.0);
	for (int offset = -1; offset <= 1; offset++) {
		float id = column + float(offset);
		uint h = hash_cell(ivec2(int(id), int(row)), seed);
		if (float(h & 255u) / 255.0 > coverage) {
			continue;
		}
		float width = 0.36 + float((h >> 8u) & 63u) / 63.0 * 0.42;
		float tall = 0.24 + float((h >> 14u) & 31u) / 31.0 * 0.07;
		float x_shift = float((h >> 19u) & 31u) / 31.0 - 0.5;
		float y_shift = float((h >> 24u) & 31u) / 31.0 - 0.5;
		vec2 q = (g - vec2(id + 0.5 + x_shift * 0.3, row + 0.5 + y_shift * 0.2)) / vec2(width, tall);
		if (abs(q.x) >= 1.0 || abs(q.y) >= 1.4) {
			continue;
		}
		float shape = float(h >> 8u) * 0.00013;
		float side = 1.0 - abs(q.x);
		float top = min(side * 3.2, 1.0) * (0.3 + 0.62 * line1(q.x * 2.6 + shape) + 0.26 * line1(q.x * 6.3 + shape * 1.7));
		float bottom = -min(side * 3.6, 1.0) * (0.14 + 0.26 * line1(q.x * 3.7 + shape * 2.3));
		float edge = 0.0016 / (tall * cell.y);
		float cover = min(smoothstep(-edge, edge, top - q.y), smoothstep(-edge, edge, q.y - bottom));
		if (cover <= 0.0) {
			continue;
		}
		// Facets stay the same shape on screen for any cloud size: about five
		// across a large cloud, three across a small one.
		vec2 size = vec2(width, tall) * cell;
		float mesh = 0.012 + size.y * 0.42;
		vec3 tri = facet(q * size / mesh + vec2(shape, 0.0), seed + 7u);
		vec2 center = (tri.xy - vec2(shape, 0.0)) * mesh / size;
		float light = 0.46 + center.y * 0.72 - center.x * 0.24 + (tri.z - 0.5) * 0.5;
		vec3 tone = mix(shadow, lit, smoothstep(0.08, 0.86, light));
		result = vec4(mix(result.rgb, tone, cover), max(result.a, cover));
	}
	return result;
}

float crest_line(float x, float base, float amplitude) {
	return base - ridge_octaves(x, 3) * amplitude;
}

// Paints a range over col where it covers the pixel (1 below the crest line,
// so the range always continues down to the bottom of the frame).
vec3 range_layer(vec3 col, float lx, float y, float line, float scale, float base, float amplitude, float sink, vec2 tri_size, uint seed, vec3 tone, float snow, vec3 haze) {
	float cover = smoothstep(line - 0.0015, line + 0.0015, y);
	if (cover <= 0.0) {
		return col;
	}
	// Facets hang on the range, so they sink with it.
	vec3 tri = facet(vec2(lx, y - sink) / tri_size, seed);
	float cx = tri.x * tri_size.x;
	float cy = tri.y * tri_size.y + sink;
	float crest = ridge_octaves(cx * scale, 3);
	float depth = cy - (base - crest * amplitude);
	// The flank facing the sun (from the left) is lit, the other shaded.
	float fx = cx * scale + depth * 2.4;
	float slope = ridge_octaves(fx + 0.12, 2) - ridge_octaves(fx - 0.12, 2);
	float lit = smoothstep(0.1, -0.1, slope + (tri.z - 0.5) * 0.16);
	vec3 shade = tone * mix(0.82, 1.16, lit) * (0.95 + tri.z * 0.1);
	// Snow on the high crests, broken along the facets.
	float snow_line = 1.0 - snow * 0.55;
	float snow_depth = (crest - snow_line) * amplitude * 0.9;
	if (snow > 0.0 && depth < snow_depth + (tri.z - 0.5) * 0.03) {
		shade = mix(vec3(0.74, 0.80, 0.88), vec3(0.96, 0.97, 0.99), lit);
	}
	// Valley mist rises from the foot of each range.
	shade = mix(shade, haze, smoothstep(0.05, 0.32, y - line) * 0.28);
	return mix(col, shade, cover);
}

void fragment() {
	float y = UV.y;
	float height = clamp(1.0 - y, 0.0, 1.0);
	vec3 sky = mix(horizon_color, top_color, pow(height, 0.8));
	vec2 sky_coords = vec2((UV.x - 0.5) * aspect + 0.5, height);
	sky += sun_color * exp(-distance(sky_coords, sun_pos) * 4.5) * 0.1;
	uint seed = uint(int(sky_seed * 100.0));

	// Ranges sink as the climb gains height, the nearest first; each pans a
	// little with the camera. At the foot of the climb they stand on the bottom
	// of the frame; about halfway up the last crest has left it.
	float rise = max(altitude, 0.0) / 74.0;
	float ax = (UV.x - 0.5) * aspect;
	vec3 haze = mix(horizon_color, cloud_lit, 0.2);
	float far_sink = rise * 0.5;
	float mid_sink = rise * 0.55;
	float near_sink = rise * 0.6;
	float far_x = ax + view_x * 0.003 + sky_seed;
	float mid_x = ax + view_x * 0.008 + sky_seed * 1.7 + 40.0;
	float near_x = ax + view_x * 0.022 + sky_seed * 2.3 + 90.0;
	float mid_line = crest_line(mid_x * 2.3, 0.84 + mid_sink, 0.2);
	float near_line = crest_line(near_x * 1.6, 0.95 + near_sink, 0.17);

	// What lies fully behind the nearer ranges is not worked out at all.
	if (y < mid_line + 0.002 && y < near_line + 0.002) {
		// Clouds rise past slower than the rock, the far ones slowest.
		vec2 view = vec2(UV.x * aspect, -y);
		vec2 far_pos = view + vec2(cloud_offset.x * 0.3 + sky_time * 0.0014, -altitude * 0.009);
		vec4 far_cloud = cloud_layer(far_pos, vec2(0.2, 0.17), cloud_coverage * 1.1, seed + 11u, mix(cloud_lit, horizon_color, 0.3), mix(cloud_shadow, horizon_color, 0.45));
		sky = mix(sky, far_cloud.rgb, far_cloud.a);

		float far_line = crest_line(far_x * 3.2, 0.74 + far_sink, 0.24);
		sky = range_layer(sky, far_x, y, far_line, 3.2, 0.74 + far_sink, 0.24, far_sink, vec2(0.05, 0.036), seed + 23u, mix(range_far, horizon_color, 0.15), snow_amount, haze);

		vec2 near_pos = view + vec2(cloud_offset.x * 0.6 + sky_time * 0.003, -altitude * 0.018);
		vec4 near_cloud = cloud_layer(near_pos, vec2(0.36, 0.3), cloud_coverage, seed + 31u, cloud_lit, cloud_shadow);
		sky = mix(sky, near_cloud.rgb, near_cloud.a);
	}
	if (y < near_line + 0.002) {
		sky = range_layer(sky, mid_x, y, mid_line, 2.3, 0.84 + mid_sink, 0.2, mid_sink, vec2(0.075, 0.05), seed + 41u, range_mid, snow_amount * 0.7, haze);
	}
	sky = range_layer(sky, near_x, y, near_line, 1.6, 0.95 + near_sink, 0.17, near_sink, vec2(0.11, 0.07), seed + 53u, range_near, snow_amount * 0.35, haze);
	ALBEDO = sky;
}
