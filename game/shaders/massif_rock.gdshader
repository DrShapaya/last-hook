shader_type spatial;
render_mode cull_disabled;

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
// Volume at the outline: the rock darkens towards its edge, most on the
// side away from the form light, so it reads as a mass rounding off
// backwards, never as a cut-out plane. A location's face carries how near
// the outline each vertex lies in its colour's alpha (1 well inside, 0 on
// the edge; see RockSurface); rim_shade darkens by it. limb_shade darkens
// any facet by how far it turns from the viewer.
uniform float rim_shade : hint_range(0.0,1.0) = 0.5;
uniform float limb_shade : hint_range(0.0,1.0) = 0.0;
uniform float roughness_value : hint_range(0.0,1.0) = 0.95;
// Bedding of the rock: broad slanted bands, scaled per profile (sandstone
// strong, limestone faint). World space, so it never stretches on a wall.
uniform float strata_scale : hint_range(0.0,2.0) = 0.5;
uniform float strata_contrast : hint_range(0.0,1.0) = 0.12;
uniform float strata_fine : hint_range(0.0,1.0) = 0.0;
// Worn grain of the stone, a tile laid across every facet at its own offset.
uniform sampler2D grain_texture : repeat_enable, filter_linear_mipmap;
uniform float grain_strength : hint_range(0.0,1.0) = 0.0;
// 1 on the ultra preset: the sun models the rock, with fine relief and a
// highlight, and the painted form light drops to a supporting role. A global, so the
// baked materials keep working without a rebake.
global uniform float light_quality;

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
	stone*=1.0+(bedding-0.5)*strata_contrast*strata_scale;
	if(strata_fine>0.0){
		// Fine wavy bedding drawn across the sandstone as on desertClose.png:
		// thin dark lines over the large planes, unevenly spaced, each fading
		// in and out along its length, and a faint change of tone per layer.
		float wave=noise3(vec3(p.x*0.11,p.y*0.16,p.z*0.2))*2.4+noise3(vec3(p.x*0.45,p.y*0.3,7.0))*0.35;
		float layer=(p.y+wave)*1.35+noise3(vec3(p.x*0.03,p.y*0.08,3.0))*1.5;
		// A groove: a dark line with a pale lip just above it.
		float aa=fwidth(layer)*1.2;
		float rise=fract(layer);
		float line=1.0-smoothstep(0.035,0.035+aa,min(rise,1.0-rise));
		float lip=smoothstep(0.05,0.05+aa,rise)*(1.0-smoothstep(0.12,0.12+aa,rise));
		float shown=smoothstep(0.3,0.55,noise3(vec3(p.x*0.16,floor(layer)*2.7,p.z*0.1)));
		float tone=hash31(vec3(floor(layer),3.0,5.0))-0.5;
		stone*=1.0-strata_fine*0.8*line*shown+strata_fine*0.45*lip*shown+strata_fine*0.3*tone;
	}
	if(grain_strength>0.0){
		vec2 facet_uv=p.xy+rock_normal.xy*3.0;
		float grain_tile=texture(grain_texture,facet_uv*0.13).r*0.6+texture(grain_texture,facet_uv.yx*0.37+vec2(0.3)).r*0.4;
		stone*=1.0+(grain_tile-0.5)*2.0*grain_strength;
	}
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
	// A facet faces the camera's axis, never the per-pixel VIEW: at the
	// silhouette a facet is nearly edge-on, and a test against VIEW flipped
	// it between lit and shaded as the camera scrolled. The camera never
	// turns, so the axis keeps every facet on one side.
	vec3 flat_normal=normalize(cross(dFdx(VERTEX),dFdy(VERTEX)));
	if (flat_normal.z<0.0) { flat_normal=-flat_normal; }
	vec3 smooth_normal=normalize(NORMAL);
	if (smooth_normal.z<0.0) { smooth_normal=-smooth_normal; }
	NORMAL=normalize(mix(smooth_normal,flat_normal,facet_strength));
	vec3 form_dir=normalize((VIEW_MATRIX*vec4(normalize(form_light_world),0.0)).xyz);
	float form=dot(NORMAL,form_dir);
	// Facets turned from the form light drop below the base tone and lit ones
	// rise above it, so neighbouring planes separate without washing out.
	ALBEDO*=mix(1.0,mix(form_shade,form_lit,smoothstep(-0.2,0.9,form)),form_strength*mix(1.0,0.6,light_quality));
	float shade_side=mix(0.45,1.0,1.0-smoothstep(-0.35,0.75,form));
	float rim=1.0-COLOR.a;
	float limb=1.0-smoothstep(0.1,0.85,clamp(NORMAL.z,0.0,1.0));
	ALBEDO*=(1.0-rim_shade*rim*rim*shade_side)*(1.0-limb_shade*limb*shade_side);
	ROUGHNESS=roughness_value;
	// Dark stone (the inside of a cave, deep cracks) takes no sheen: on
	// ultra it turned the black of the caves grey.
	SPECULAR=0.5*light_quality*smoothstep(0.06,0.25,dot(ALBEDO,vec3(0.3,0.59,0.11)));
	if(light_quality>0.5){
		// Depth: the rolled edge of a location's face, set far back, takes a
		// little of the sky's haze. Caves keep their dark (vertex alpha 1).
		float recess=smoothstep(-1.5,-7.5,rock_position.z)*(1.0-COLOR.a);
		ALBEDO=mix(ALBEDO,aerial_color,recess*0.18);
		// Warm light bounced off the sunlit benches into the undersides, so a
		// shaded overhang glows faintly instead of going flat.
		float under=smoothstep(-0.05,-0.75,rock_normal.y);
		EMISSION=ALBEDO*vec3(0.20,0.12,0.05)*under;
	}
	if(light_quality>0.5){
		// Surface gradient of the stone's height, so its relief catches the real
		// sun. Only low frequencies: derivatives come in 2x2 pixel blocks, and
		// fine grain turns into a checker pattern.
		float height=noise3(p*1.6+vec3(41.0))*1.5+bedding*0.5;
		vec3 dpx=dFdx(VERTEX);
		vec3 dpy=dFdy(VERTEX);
		vec3 r1=cross(dpy,NORMAL);
		vec3 r2=cross(NORMAL,dpx);
		float det=dot(dpx,r1);
		vec3 gradient=sign(det)*(dFdx(height)*r1+dFdy(height)*r2);
		// The area of an orthographic pixel is tiny: never divide by it bare.
		NORMAL=normalize(NORMAL-0.05*gradient/max(abs(det),1e-6));
	}
}
// Wrapped sun light: faces turned away from the sun stay mid-grey instead
// of dropping to the ambient floor, like the soft shade sides of the
// reference. Shadows still come through ATTENUATION.
void light() {
	float wrapped = mix(shade_floor,1.0,clamp((dot(NORMAL,LIGHT)+1.0)/2.0,0.0,1.0));
	float direct = clamp((dot(NORMAL,LIGHT)+0.3)/1.3,0.0,1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR*ATTENUATION*mix(wrapped,direct,light_quality)/PI;
	if(light_quality>0.5){
		float gloss = mix(48.0,6.0,ROUGHNESS);
		SPECULAR_LIGHT += LIGHT_COLOR*ATTENUATION*pow(clamp(dot(NORMAL,normalize(LIGHT+VIEW)),0.0,1.0),gloss)*(1.0-ROUGHNESS*0.8)*0.3;
	}
}
