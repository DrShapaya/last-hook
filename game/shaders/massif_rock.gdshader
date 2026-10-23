shader_type spatial;
render_mode cull_disabled, specular_disabled;

// Low-poly mountain stone. The mesh is piecewise planar over large facets
// (see MassifVisuals); the flat normal is rebuilt from screen derivatives so
// each facet receives one clean sun value, like the art reference.
uniform float aerial_depth : hint_range(0.0,1.0) = 0.0;
uniform float snow_override : hint_range(-1.0,1.0) = -1.0;
// -1 keeps the first location's height bands; 0..1 sets one amount for a
// location with a single profile.
uniform float moss_override : hint_range(-1.0,1.0) = -1.0;
// Fine sand settled on upward faces (desert profiles).
uniform float dust_amount : hint_range(0.0,1.0) = 0.0;
uniform vec3 dust_color : source_color = vec3(0.89,0.73,0.54);
uniform float material_tint : hint_range(0.0,1.5) = 1.0;
uniform float facet_strength : hint_range(0.0,1.0) = 0.86;
uniform float detail_strength : hint_range(0.0,1.0) = 1.0;
uniform vec3 aerial_color : source_color = vec3(0.56,0.70,0.82);
// Painterly form light: the sun casts steep, short shadows, but facets are
// shaded as if lit from a lower upper-left angle so every mass reads round.
uniform vec3 form_light_world = vec3(-0.62,0.62,0.48);
uniform float form_strength : hint_range(0.0,1.0) = 0.85;
uniform float form_shade : hint_range(0.0,1.5) = 0.74;
uniform float form_lit : hint_range(0.0,2.0) = 1.32;
// Floor of the wrapped sun on faces turned away from it: the sky fill.
uniform float shade_floor : hint_range(0.0,1.0) = 0.56;
// Macro light from the real geometry: tops of large forms warm and light,
// undersides and flanks cool, never black. Noise never fakes this volume.
uniform float macro_strength : hint_range(0.0,1.0) = 1.0;
uniform float roughness_value : hint_range(0.0,1.0) = 0.95;
// Bedding of the rock: broad slanted bands, scaled per profile (sandstone
// strong, limestone faint). World space, so it never stretches on a wall.
uniform float strata_scale : hint_range(0.0,2.0) = 0.5;

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
	float weather=noise3(p*vec3(0.17,0.11,0.2));
	float grain=noise3(p*3.1)*0.6+noise3(p*9.0)*0.4;
	// Hairline cracks: thin, sparse and only slightly darker than the facet.
	float crack_field=noise3(p*vec3(0.9,0.42,0.6));
	float crack=1.0-smoothstep(0.0,0.018,abs(crack_field-0.5));
	crack*=smoothstep(0.74,0.86,noise3(p*0.37+vec3(7.0)))*detail_strength;
	float upwards=smoothstep(0.05,0.6,rock_normal.y);
	vec3 stone=COLOR.rgb*(0.96+weather*0.05+(grain-0.5)*0.035*detail_strength);
	stone*=material_tint;
	// Granite speckle of the reference: sparse pale and dark grains a few
	// centimetres across, plus soft weathered blotches a metre across. It
	// reads as stone texture at play distance without breaking the facets.
	float speck=noise3(p*vec3(15.0,15.0,9.0));
	float pale=smoothstep(.70,.80,speck)*smoothstep(.45,.7,noise3(p*5.3+vec3(17.0)));
	float dark=smoothstep(.30,.20,speck)*smoothstep(.4,.7,noise3(p*4.7+vec3(23.0)));
	float speck_gain=mix(.55,1.0,detail_strength);
	stone*=1.0+(pale*.10-dark*.12)*speck_gain;
	stone*=1.0+(noise3(p*1.6+vec3(41.0))-.5)*.10*speck_gain;
	stone*=mix(vec3(1.0),mix(vec3(0.90,0.94,1.0),vec3(1.04,1.02,0.97),smoothstep(-0.7,0.7,rock_normal.y)),macro_strength);
	stone*=1.0-crack*0.06;
	float bedding=noise3(vec3(p.x*0.09,p.y*0.75+p.x*0.22,p.z*0.2));
	stone*=1.0+(bedding-0.5)*0.12*strata_scale;
	// Broad warm and cool patches, a few metres across, so the massif is not
	// one flat grey.
	float patch=noise3(p*0.12+vec3(31.0));
	stone*=mix(vec3(0.95,0.975,1.03),vec3(1.05,1.0,0.94),patch);
	// Faint vertical rain streaks running down from rims and creases.
	float streak=smoothstep(0.62,0.82,noise3(p*vec3(1.1,0.10,0.6)+vec3(3.0)))*smoothstep(0.25,0.7,noise3(p*vec3(0.4,0.25,0.4)));
	stone*=1.0-streak*0.08*detail_strength;
	// Small pale lichen spots on stone that does not face down.
	float lichen=smoothstep(0.86,0.90,noise3(p*vec3(7.0,7.0,3.0)+vec3(11.0)))*smoothstep(0.5,0.8,noise3(p*0.5+vec3(5.0)))*smoothstep(-0.3,0.2,rock_normal.y);
	stone=mix(stone,vec3(0.72,0.72,0.56),lichen*0.20*detail_strength);
	// Sparse moss on gently upward facing stone in the forest band.
	float damp=smoothstep(0.58,0.74,weather)*upwards*detail_strength;
	float forest=moss_override>=0.0?moss_override:1.0-smoothstep(30.0,55.0,p.y);
	stone=mix(stone,vec3(0.50,0.58,0.36),damp*forest*0.22);
	float snow=smoothstep(65.0,95.0,p.y)*upwards*smoothstep(0.40,0.65,weather);
	if (snow_override>=0.0) { snow=snow_override*upwards*smoothstep(0.40,0.65,weather); }
	stone=mix(stone,dust_color,dust_amount*upwards*smoothstep(0.35,0.7,weather)*0.35);
	stone=mix(stone,vec3(0.86,0.90,0.92),snow*0.65);
	ALBEDO=mix(stone,aerial_color,aerial_depth);
	vec3 flat_normal=normalize(cross(dFdx(VERTEX),dFdy(VERTEX)));
	if (dot(flat_normal,VIEW)<0.0) { flat_normal=-flat_normal; }
	vec3 smooth_normal=normalize(NORMAL);
	if (dot(smooth_normal,VIEW)<0.0) { smooth_normal=-smooth_normal; }
	NORMAL=normalize(mix(smooth_normal,flat_normal,facet_strength));
	vec3 form_dir=normalize((VIEW_MATRIX*vec4(normalize(form_light_world),0.0)).xyz);
	float form=dot(NORMAL,form_dir);
	// Facets turned from the form light drop below the base tone and lit ones
	// rise above it, so neighbouring planes separate without washing out.
	ALBEDO*=mix(1.0,mix(form_shade,form_lit,smoothstep(-0.2,0.9,form)),form_strength);
	ROUGHNESS=roughness_value;
}
// Wrapped sun light: faces turned away from the sun stay mid-grey instead
// of dropping to the ambient floor, like the soft shade sides of the
// reference. Shadows still come through ATTENUATION.
void light() {
	float wrapped = mix(shade_floor,1.0,clamp((dot(NORMAL,LIGHT)+1.0)/2.0,0.0,1.0));
	DIFFUSE_LIGHT += LIGHT_COLOR*ATTENUATION*wrapped/PI;
}
