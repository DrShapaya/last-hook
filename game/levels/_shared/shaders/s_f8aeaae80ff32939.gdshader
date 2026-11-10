shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform float length_units = 10.0;
void fragment(){
	float y = UV.y*length_units;
	float side = abs(UV.x-.5)*2.0;
	float body = 1.0-smoothstep(.55,1.0,side);
	float flow = fract(y*.42-TIME*1.4+sin(UV.x*19.0)*.25);
	float streak = smoothstep(.0,.12,flow)*(1.0-smoothstep(.35,.7,flow));
	float lip = 1.0-smoothstep(.0,.6,y);
	vec3 water = mix(vec3(.42,.68,.88),vec3(.9,.96,1.0),clamp(streak*.65+lip*.8,0.0,1.0));
	float fade = 1.0-smoothstep(length_units*.5,length_units,y);
	ALBEDO = water;
	ALPHA = body*fade*(.72+.25*streak);
}