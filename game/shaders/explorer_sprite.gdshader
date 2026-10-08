shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform float sprite_size = 1.18;
uniform vec4 pose = vec4(0.0);
uniform float pack_sway = 0.0;
uniform float breath = 0.0;

vec2 rotate_point(vec2 point, vec2 pivot, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	vec2 p = point-pivot;
	return pivot+vec2(p.x*c-p.y*s,p.x*s+p.y*c);
}

void vertex() {
	vec2 p = VERTEX.xy;
	// Continuous smooth masks retain the original seamless drawing.
	float arm = smoothstep(.665,.745,UV.x)*(1.0-smoothstep(.49,.56,UV.y));
	vec2 shoulder = vec2(.166,.005)*sprite_size;
	p = mix(p,rotate_point(p,shoulder,pose.x),arm);
	float leg = smoothstep(.65,.82,UV.y)*smoothstep(.44,.54,UV.x);
	float side = smoothstep(.61,.69,UV.x)*2.0-1.0;
	vec2 hip = vec2((UV.x<.65 ? .55 : .68)-.5,.5-.68)*sprite_size;
	p = mix(p,rotate_point(p,hip,pose.y*side),leg);
	p.y += leg*pose.z*sprite_size*.16;
	float head = (1.0-smoothstep(.40,.48,UV.y))*(1.0-smoothstep(.68,.72,UV.x));
	p = mix(p,rotate_point(p,vec2(.03,.03)*sprite_size,pose.w),head);
	p.y += head*breath;
	float bag = (1.0-smoothstep(.36,.43,UV.x))*smoothstep(.38,.46,UV.y)*(1.0-smoothstep(.73,.78,UV.y));
	p = mix(p,rotate_point(p,vec2(-.10,-.02)*sprite_size,pack_sway),bag);
	VERTEX.xy = p;
}

void fragment() {
	vec4 color = texture(art,UV);
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = .14;
}
