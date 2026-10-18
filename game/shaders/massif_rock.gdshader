shader_type spatial;
render_mode cull_disabled;

uniform float aerial_depth : hint_range(0.0,1.0) = 0.0;

varying vec3 rock_position;
varying vec3 rock_normal;

float hash31(vec3 p) {
	p=fract(p*0.1031);
	p+=dot(p,p.yzx+33.33);
	return fract((p.x+p.y)*p.z);
}
float noise3(vec3 p) {
	vec3 i=floor(p);
	vec3 f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash31(i),hash31(i+vec3(1,0,0)),f.x),mix(hash31(i+vec3(0,1,0)),hash31(i+vec3(1,1,0)),f.x),f.y),
		mix(mix(hash31(i+vec3(0,0,1)),hash31(i+vec3(1,0,1)),f.x),mix(hash31(i+vec3(0,1,1)),hash31(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() {
	rock_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	rock_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
	vec3 p=rock_position;
	float weather=noise3(p*vec3(0.21,0.13,0.24));
	float grain=noise3(p*3.8)*0.65+noise3(p*10.1)*0.35;
	float layers=p.y*0.78+p.x*0.19+(weather-0.5)*2.7;
	float seam=1.0-smoothstep(0.015,0.075,abs(fract(layers)-0.5));
	seam*=smoothstep(0.30,0.61,noise3(p*0.56+vec3(13.0)));
	float fissure=1.0-smoothstep(0.0,0.021,abs(noise3(p*vec3(0.65,0.15,0.48))-0.49));
	vec3 stone=COLOR.rgb*(0.87+weather*0.24+(grain-0.5)*0.11);
	stone*=1.0-seam*0.08-fissure*0.055;
	float upwards=smoothstep(0.12,0.65,rock_normal.y);
	float damp=smoothstep(0.49,0.70,weather)*upwards;
	float forest=1.0-smoothstep(30.0,55.0,p.y);
	stone=mix(stone,vec3(0.12,0.19,0.10),damp*forest*0.48);
	float snow=smoothstep(65.0,95.0,p.y)*upwards*smoothstep(0.40,0.65,weather);
	stone=mix(stone,vec3(0.60,0.72,0.77),snow*0.60);
	ALBEDO=mix(stone,vec3(0.19,0.28,0.33),aerial_depth);
	// Surface-gradient bump follows the mesh in view space without UV textures.
	float bump=(grain-0.5)*0.016+(weather-0.5)*0.04-seam*0.006;
	vec3 sigma_x=dFdx(VERTEX);
	vec3 sigma_y=dFdy(VERTEX);
	vec3 r1=cross(sigma_y,NORMAL);
	vec3 r2=cross(NORMAL,sigma_x);
	float determinant=dot(sigma_x,r1);
	vec3 gradient=sign(determinant)*(dFdx(bump)*r1+dFdy(bump)*r2);
	if (abs(determinant)>0.00000001) { NORMAL=normalize(abs(determinant)*NORMAL-gradient); }
	ROUGHNESS=0.94;
}
