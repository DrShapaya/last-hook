shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength = .0035;
void fragment(){
	float rise = 1.0-UV.y;
	float body = smoothstep(0.0,.25,rise)*(1.0-smoothstep(.55,1.0,rise))*smoothstep(0.0,.12,UV.x)*smoothstep(1.0,.88,UV.x);
	vec2 wobble = vec2(sin(rise*38.0-TIME*3.1+UV.x*9.0),cos(UV.x*27.0+rise*12.0-TIME*2.2))*strength*body;
	ALBEDO = texture(screen,SCREEN_UV+wobble).rgb;
	ALPHA = body;
}