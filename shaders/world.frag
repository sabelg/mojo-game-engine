#version 450
layout(location=0) in vec3 worldPosition;
layout(location=1) in vec3 worldNormal;
layout(location=2) in vec2 uv;
layout(location=3) in vec4 shadowPosition;
layout(location=0) out vec4 color;
layout(set=0,binding=0) uniform Frame { mat4 viewProjection; mat4 lightMatrix; vec4 sunFog; vec4 sky; vec4 ground; vec4 sunColor; vec4 haze; } frame;
layout(push_constant) uniform Object { mat4 model; vec4 colorRough; vec4 params; vec4 pose; } object;
layout(set=0,binding=1) uniform sampler2D shadowMap;
layout(set=0,binding=2) uniform sampler2D albedoMap;
layout(set=0,binding=3) uniform sampler2D normalMap;
layout(set=0,binding=4) uniform sampler2D ormMap;
#define baseColor object.colorRough.rgb
#define emission object.params.y
#define textured object.params.z
#define sunDirection frame.sunFog.xyz
#define fogDensity frame.sunFog.w
const float PI=3.14159265359;
float visibility(vec3 n, vec3 l) {
    vec3 p=shadowPosition.xyz/shadowPosition.w*0.5+0.5;
    p.y=1.0-p.y;
    if(p.z>1.0 || p.z<0.0 || any(lessThan(p.xy,vec2(0))) || any(greaterThan(p.xy,vec2(1)))) return 1.0;
    float bias=max(0.0006*(1.0-dot(n,l)),0.00012), sum=0.0;
    vec2 texel=1.0/vec2(textureSize(shadowMap,0));
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++)
        sum += p.z-bias <= texture(shadowMap,p.xy+vec2(x,y)*texel).r ? 1.0:0.0;
    return sum/9.0;
}
vec3 surfaceNormal(vec3 n) {
    if((int(object.params.w)&1)==0) return n;
    vec3 dp1=dFdx(worldPosition), dp2=dFdy(worldPosition);
    vec2 duv1=dFdx(uv), duv2=dFdy(uv);
    vec3 p2=cross(dp2,n), p1=cross(n,dp1);
    vec3 t=p2*duv1.x+p1*duv2.x, b=p2*duv1.y+p1*duv2.y;
    float scale=max(dot(t,t),dot(b,b));
    if(scale<1e-12) return n;
    vec3 detail=texture(normalMap,uv).xyz*2.0-1.0;
    // Exported UVs use downward V; original Blender normal maps use upward V.
    float strength=(int(object.params.w)&2)!=0 ? 1.0 : 0.45;
    detail.xy*=vec2(strength,-strength);
    return normalize(mat3(t*inversesqrt(scale),b*inversesqrt(scale),n)*normalize(detail));
}
void main() {
    float roughness=object.colorRough.a, metallic=object.params.x, occlusion=1.0;
    if((int(object.params.w)&2)!=0) {
        vec3 orm=texture(ormMap,uv).rgb;
        occlusion=orm.r;
        roughness=clamp(orm.g,0.045,1.0);
        metallic=orm.b;
    }
    vec3 albedo=baseColor;
    if(textured!=0) { vec4 sampleColor=texture(albedoMap,uv); if(sampleColor.a<0.45) discard; albedo*=sampleColor.rgb; }
    vec3 n=surfaceNormal(normalize(worldNormal)), v=normalize(-worldPosition), l=normalize(sunDirection), h=normalize(v+l);
    float nl=max(dot(n,l),0.0), nv=max(dot(n,v),0.001), nh=max(dot(n,h),0.0), vh=max(dot(v,h),0.0);
    float a=max(roughness*roughness,0.002), a2=a*a, d=nh*nh*(a2-1.0)+1.0;
    float D=a2/(PI*d*d), k=(roughness+1.0)*(roughness+1.0)/8.0;
    float G=nv/(nv*(1.0-k)+k)*nl/(nl*(1.0-k)+k);
    vec3 F0=mix(vec3(0.04),albedo,metallic), F=F0+(1.0-F0)*pow(1.0-vh,5.0);
    vec3 spec=D*G*F/max(4.0*nv*nl,0.001);
    vec3 ambient=albedo*mix(frame.ground.rgb,frame.sky.rgb,n.y*0.5+0.5)*occlusion;
    vec3 rim=albedo*frame.sky.rgb*pow(1.0-nv,3.0)*frame.sky.w*0.18;
    vec3 radiance=ambient+rim+((1.0-F)*(1.0-metallic)*albedo/PI+spec)*nl*frame.sunColor.rgb*visibility(n,l)+albedo*emission;
    vec3 sky=frame.haze.rgb;
    float fog=1.0-exp(-length(worldPosition)*fogDensity);
    radiance=mix(radiance,sky,fog);
    radiance*=frame.sunColor.w;
    // Filmic highlight roll-off in linear light, followed by display encoding.
    radiance=clamp((radiance*(2.51*radiance+0.03))/(radiance*(2.43*radiance+0.59)+0.14),0.0,1.0);
    color=vec4(pow(radiance,vec3(1.0/2.2)),1.0);
}
