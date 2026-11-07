shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_add;
void fragment(){
	float rise = 1.0-UV.y;
	float body = smoothstep(0.0,.25,rise)*(1.0-smoothstep(.55,1.0,rise))*smoothstep(0.0,.15,UV.x)*smoothstep(1.0,.85,UV.x);
	float waver = sin(rise*26.0-TIME*2.6+sin(UV.x*11.0+TIME*1.3)*1.6);
	float bands = smoothstep(.55,1.0,waver)*(.6+.4*sin(UV.x*7.0-TIME*.9));
	ALBEDO = vec3(1.0,.9,.7)*bands*body*.07;
}