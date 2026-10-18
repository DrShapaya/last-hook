shader_type canvas_item;
render_mode unshaded;

// Everything is synthesized here; no sky or cloud image assets.
uniform vec3 seed_offset = vec3(12.0,23.0,34.0);
uniform vec2 cloud_offset = vec2(0.0);
uniform vec2 ridge_offset = vec2(0.0);
uniform float sky_time = 0.0;
uniform float aspect = 1.0;

float hash31(vec3 p) {
 p = fract(p * 0.1031);
 p += dot(p,p.yzx + 33.33);
 return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
 vec3 i = floor(p);
 vec3 f = fract(p);
 f = f * f * (3.0 - 2.0 * f);
 return mix(mix(mix(hash31(i),hash31(i+vec3(1,0,0)),f.x),
  mix(hash31(i+vec3(0,1,0)),hash31(i+vec3(1,1,0)),f.x),f.y),
  mix(mix(hash31(i+vec3(0,0,1)),hash31(i+vec3(1,0,1)),f.x),
  mix(hash31(i+vec3(0,1,1)),hash31(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float cloud_density(vec3 p) {
 vec2 spacing = vec2(3.4,2.8);
 vec2 cell = floor(p.xy / spacing);
 float shape = -10.0;
 for (int y=-1; y<=1; y++) {
  for (int x=-1; x<=1; x++) {
   vec2 id = cell+vec2(float(x),float(y));
   float r = hash31(vec3(id,seed_offset.x));
   vec2 center = (id+0.5)*spacing+vec2(r-0.5,hash31(vec3(id,seed_offset.y))-0.5)*1.8;
   vec3 q = p-vec3(center,0.0);
   if (dot(q.xy,q.xy)<5.8 && r>0.16) {
    float scale = 0.80+r*0.45;
    q /= scale;
    q.x *= r>0.5 ? 1.0 : -1.0;
    // A broad flat base and asymmetric upper lobes form a cumulus bank.
    float lobe = hash31(vec3(id,seed_offset.z));
    float bank = 1.0-length(q/vec3(1.15,0.42,0.72));
    bank = max(bank,0.65+lobe*0.24-length((q-vec3(-0.42,0.33+lobe*0.18,-0.10))/vec3(0.90,1.0,0.88)));
    bank = max(bank,0.56+(1.0-lobe)*0.19-length((q-vec3(0.35,0.30,0.12))/vec3(1.0,0.85,0.90)));
    bank = max(bank,0.37+lobe*0.19-length(q-vec3(-0.86-lobe*0.12,0.02,0.08)));
    bank = max(bank,0.32+(1.0-lobe)*0.17-length(q-vec3(0.86,-0.03,-0.06)));
    shape = max(shape,bank*scale);
   }
  }
 }
 if (shape < -0.3) { return 0.0; }
 vec3 detail_pos = p*3.8+seed_offset+vec3(sky_time*0.006,0.0,sky_time*0.009);
 float detail = (noise3(detail_pos)-0.5)*0.22;
 detail += (noise3(detail_pos*2.7)-0.5)*0.085;
 detail += (noise3(detail_pos*7.1)-0.5)*0.03;
 float body = max(0.0,shape+detail);
 return smoothstep(0.0,0.055,body)*(0.6+min(body*6.0,3.5));
}
float ridge_height(float x,float depth) {
 vec3 p = vec3(x*(0.13+depth*0.025),depth*13.7,seed_offset.x);
 float peaks = pow(1.0-abs(noise3(p)*2.0-1.0),1.5);
 return peaks*2.0+noise3(p*2.9)*1.45+noise3(p*8.3)*0.45;
}
void fragment() {
 vec2 p = (UV-0.5) * vec2(24.0*aspect,-24.0);
 float height = smoothstep(-12.0,12.0,p.y);
 vec3 sky = mix(vec3(0.73,0.86,0.89),vec3(0.14,0.39,0.66),height);
 vec2 sun_delta = (p-vec2(-8.5,8.0))*vec2(0.8,1.0);
 float glow = exp(-dot(sun_delta,sun_delta)*0.009);
 sky = mix(sky,vec3(0.96,0.88,0.69),glow*0.29);
 vec3 wisp_pos = vec3((p.x+cloud_offset.x*0.45-sky_time*0.018)*0.16,p.y*0.85,seed_offset.z+77.0);
 float wisps = noise3(wisp_pos)*0.75+noise3(wisp_pos*2.8)*0.25;
 sky = mix(sky,vec3(0.92,0.94,0.94),smoothstep(0.58,0.76,wisps)*0.22);

 // Orthographic volume integration, front to back, with Beer absorption.
 // Samples toward the sun brighten cloud edges and shade their interiors.
 vec2 field = (p+cloud_offset-vec2(sky_time*0.055,0.0))*vec2(0.19,0.25);
 vec3 accumulated = vec3(0.0);
 float transmission = 1.0;
 for (int step_index=0; step_index<20; step_index++) {
  float z = -1.9+(float(step_index)+0.5)*0.19;
  vec3 sample_pos = vec3(field,z);
  float density = cloud_density(sample_pos);
  if (density>0.015) {
   float sun_density = cloud_density(sample_pos+vec3(-0.12,0.17,-0.05))*0.45;
   sun_density += cloud_density(sample_pos+vec3(-0.30,0.42,-0.12))*0.35;
   sun_density += cloud_density(sample_pos+vec3(-0.60,0.84,-0.24))*0.20;
   float illumination = 0.16+0.84*exp(-sun_density*0.90);
   vec3 shade = mix(vec3(0.43,0.57,0.75),vec3(1.0,0.98,0.92),illumination);
   shade = mix(shade,sky,0.10+(z+1.9)*0.025);
   float opacity = 1.0-exp(-density*0.19*2.6);
   accumulated += transmission*opacity*shade;
   transmission *= 1.0-opacity;
  }
  if (transmission<0.025) { break; }
 }
 sky = accumulated+sky*transmission;

 // Continuous ridge silhouettes and atmospheric perspective.
 for (int layer=0; layer<3; layer++) {
  float depth = float(layer);
  float x = p.x+ridge_offset.x*(1.0+depth*0.6)+depth*28.0;
  float top = -8.4-depth*1.3+ridge_height(x,depth)-ridge_offset.y;
  float silhouette = 1.0-smoothstep(top-0.04,top+0.04,p.y);
  vec3 ridge = mix(vec3(0.55,0.71,0.78),vec3(0.34,0.51,0.61),depth*0.5);
  float slope = (ridge_height(x+0.12,depth)-ridge_height(x-0.12,depth))/0.24;
  float face_light = clamp(-slope*0.15,-0.10,0.10)*(0.5+depth*0.25)*exp(-abs(p.y-top)*0.85);
  ridge += vec3(face_light*0.65,face_light*0.85,face_light);
  float strata = noise3(vec3(x*0.7,p.y*0.6,depth*4.0));
  ridge += (strata-0.5)*0.035;
  float snow_line = top-0.25-strata*0.32;
  float snow = smoothstep(snow_line-0.12,snow_line+0.12,p.y)*smoothstep(-6.8,-4.5,top);
  ridge = mix(ridge,vec3(0.78,0.85,0.86),snow*0.38);
  float haze = exp(-abs(p.y-top)*0.5)*0.20;
  ridge = mix(ridge,vec3(0.77,0.85,0.84),haze);
  sky = mix(sky,ridge,silhouette);
 }
 COLOR = vec4(sky,1.0);
}
