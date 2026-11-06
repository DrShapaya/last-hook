shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
void fragment(){
	float low = 1.0-smoothstep(0.0,1.0,1.0-UV.y);
	float sides = smoothstep(0.0,.12,UV.x)*smoothstep(1.0,.88,UV.x);
	ALBEDO = vec3(.86,.93,.95);
	ALPHA = low*low*sides*.5;
}