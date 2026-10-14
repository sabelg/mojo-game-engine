#version 450
#extension GL_GOOGLE_include_directive : require
layout(location=0) in vec3 worldPosition;
layout(location=1) in vec3 worldNormal;
layout(location=2) in vec2 uv;
layout(location=3) in vec4 shadowPosition;
layout(location=4) in vec3 materialPosition;
layout(location=5) in vec3 materialNormal;
layout(location=6) in vec4 vertexColor;
layout(location=7) in vec4 worldTangent;
layout(location=0) out vec4 color;
struct LocalLight { vec4 positionInner; vec4 intensityOuter; vec4 direction; };
layout(set=0,binding=0) uniform Frame { mat4 viewProjection; mat4 lightMatrix; vec4 sunFog; vec4 sky; vec4 ground; vec4 sunColor; vec4 haze; vec4 atmosphere; vec4 cinema; vec4 wind; vec4 faceCenters[5]; vec4 faceAxis[2]; vec4 faceWeights; mat4 inverseViewProjection; mat4 cascadeMatrices[4]; vec4 cascadeSplits; vec4 cascadeForward; vec4 cascadeEye; vec4 policy; vec4 environment[9]; LocalLight localLights[32]; } frame;
layout(push_constant) uniform Object { mat4 model; vec4 colorRough; vec4 params; vec4 pose; } object;
layout(set=0,binding=1) uniform sampler2D shadowMap;
layout(set=0,binding=2) uniform sampler2D albedoMap;
layout(set=0,binding=3) uniform sampler2D normalMap;
layout(set=0,binding=4) uniform sampler2D ormMap;
layout(set=0,binding=5) uniform sampler2D opaqueDepth;
layout(set=0,binding=6) uniform sampler2D opaqueColor;
#define baseColor object.colorRough.rgb
#define emission object.params.y
#define textured object.params.z
#define sunDirection frame.sunFog.xyz
#define fogDensity frame.sunFog.w
const float PI=3.14159265359;
vec3 cameraEye() { return frame.policy.x>0.0 ? frame.cascadeEye.xyz : vec3(0); }
bool projected() { return (int(object.params.w)&4)!=0; }
vec3 projectionWeights() {
    vec3 weights=pow(abs(normalize(materialNormal)),vec3(4));
    return weights/max(weights.x+weights.y+weights.z,0.0001);
}
vec4 surfaceSample(sampler2D source) {
    if(!projected()) return texture(source,uv);
    vec3 p=materialPosition*object.pose.w, w=projectionWeights();
    return texture(source,p.zy)*w.x+texture(source,p.xz)*w.y+texture(source,p.xy)*w.z;
}
float mapVisibility(vec4 position,vec3 n,vec3 l,int tile) {
    if(abs(position.w)<1e-8) return 1.0;
    vec3 p=position.xyz/position.w*0.5+0.5;
    p.y=1.0-p.y;
    if(p.z>1.0 || p.z<0.0 || any(lessThan(p.xy,vec2(0))) || any(greaterThan(p.xy,vec2(1)))) return 1.0;
    float bias=max(0.0006*(1.0-dot(n,l)),0.00012), sum=0.0, total=0.0;
    vec2 texel=1.0/vec2(textureSize(shadowMap,0));
    vec2 low=vec2(0), high=vec2(1);
    if(tile>=0) {
        low=vec2(tile%2,tile/2)*0.5;
        high=low+vec2(0.5);
        p.xy=low+p.xy*0.5;
    }
    int radius=frame.cinema.x>0.0 ? 2 : 1;
    for(int y=-radius;y<=radius;y++) for(int x=-radius;x<=radius;x++) {
        float weight=frame.cinema.x>0.0 ? float((3-abs(x))*(3-abs(y))) : 1.0;
        vec2 sampleUV=p.xy+vec2(x,y)*texel;
        if(tile>=0) sampleUV=clamp(sampleUV,low+texel*0.5,high-texel*0.5);
        sum += weight*(p.z-bias <= textureLod(shadowMap,sampleUV,0.0).r ? 1.0:0.0);
        total+=weight;
    }
    return sum/total;
}
float visibility(vec3 n,vec3 l) {
    int count=int(frame.cascadeForward.w);
    if(count==0) return mapVisibility(shadowPosition,n,l,-1);
    float depth=dot(worldPosition-frame.cascadeEye.xyz,frame.cascadeForward.xyz);
    if(depth<0.0 || depth>frame.cascadeSplits[count-1]) return 1.0;
    int cascade=0;
    while(cascade<count-1 && depth>frame.cascadeSplits[cascade]) cascade++;
    float first=mapVisibility(frame.cascadeMatrices[cascade]*vec4(worldPosition,1),n,l,cascade);
    if(cascade<count-1) {
        float near=cascade==0 ? 0.0 : frame.cascadeSplits[cascade-1];
        float far=frame.cascadeSplits[cascade];
        float blend=smoothstep(far-(far-near)*0.1,far,depth);
        if(blend>0.0) {
            float next=mapVisibility(frame.cascadeMatrices[cascade+1]*vec4(worldPosition,1),n,l,cascade+1);
            first=mix(first,next,blend);
        }
    }
    return first;
}
vec3 surfaceNormal(vec3 n) {
    if((int(object.params.w)&1)==0) return n;
    if(projected()) {
        vec3 p=materialPosition*object.pose.w, w=projectionWeights();
        vec3 x=texture(normalMap,p.zy).xyz*2.0-1.0;
        vec3 y=texture(normalMap,p.xz).xyz*2.0-1.0;
        vec3 z=texture(normalMap,p.xy).xyz*2.0-1.0;
        // Blend slopes in the same local axes as the albedo/ORM projections.
        // Removing the normal component avoids pushing the result off-surface
        // where two or three projections meet. Downward V matches legacy maps.
        vec3 slope=vec3(0,-x.y,x.x)*w.x+vec3(y.x,0,-y.y)*w.y+vec3(z.x,-z.y,0)*w.z;
        vec3 local=normalize(materialNormal);
        slope-=local*dot(local,slope);
        float strength=(int(object.params.w)&2)!=0 ? 1.0 : 0.45;
        return normalize(mat3(transpose(inverse(object.model)))*(local+slope*strength));
    }
    if((int(object.params.w)&1024)!=0 && dot(worldTangent.xyz,worldTangent.xyz)>1e-10) {
        vec3 t=normalize(worldTangent.xyz-n*dot(n,worldTangent.xyz));
        vec3 b=cross(n,t)*worldTangent.w;
        vec3 detail=texture(normalMap,uv).xyz*2.0-1.0;
        detail.xy*=vec2((int(object.params.w)&2)!=0 ? 1.0 : .45,-((int(object.params.w)&2)!=0 ? 1.0 : .45));
        return normalize(mat3(t,b,n)*normalize(detail));
    }
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
vec3 environmentLight(vec3 d, bool diffuse, float roughness) {
    float basis[9]=float[9](0.2820947918,0.4886025119*d.y,0.4886025119*d.z,0.4886025119*d.x,1.0925484306*d.x*d.y,1.0925484306*d.y*d.z,0.3153915653*(3*d.z*d.z-1),1.0925484306*d.x*d.z,0.5462742153*(d.x*d.x-d.y*d.y));
    vec3 light=vec3(0);
    for(int i=0;i<9;i++) {
        // Broad specular is a low-frequency approximation, not a GGX cubemap.
        float factor=i==0 ? 1.0 : diffuse ? (i<4 ? 2.0/3.0 : .25) : exp(-roughness*roughness*(i<4 ? 2.0 : 6.0));
        light+=frame.environment[i].rgb*basis[i]*factor;
    }
    return max(light,vec3(0));
}
vec3 localIllumination(vec3 n, vec3 v, vec3 albedo, float roughness, float metallic) {
    vec3 result=vec3(0);
    float nv=max(dot(n,v),0.001), a=max(roughness*roughness,0.002), a2=a*a;
    float k=(roughness+1)*(roughness+1)/8;
    vec3 f0=mix(vec3(.04),albedo,metallic);
    for(int i=0;i<int(frame.policy.z);++i) {
        LocalLight light=frame.localLights[i];
        vec3 delta=light.positionInner.xyz-worldPosition;
        float distance2=max(dot(delta,delta),.000001);
        vec3 l=delta*inversesqrt(distance2), h=normalize(v+l);
        float nl=max(dot(n,l),0), nh=max(dot(n,h),0), vh=max(dot(v,h),0);
        if(nl<=0) continue;
        float attenuation=1/distance2;
        if(light.intensityOuter.w>-1) {
            float angle=dot(-l,light.direction.xyz);
            float inner=light.positionInner.w, outer=light.intensityOuter.w;
            attenuation*=inner>outer ? smoothstep(outer,inner,angle) : step(outer,angle);
        }
        float d=nh*nh*(a2-1)+1, D=a2/(PI*d*d);
        float G=nv/(nv*(1-k)+k)*nl/(nl*(1-k)+k);
        vec3 F=f0+(1-f0)*pow(1-vh,5);
        vec3 spec=D*G*F/max(4*nv*nl,.001);
        result+=((1-F)*(1-metallic)*albedo/PI+spec)*nl*light.intensityOuter.rgb*attenuation;
    }
    return result;
}
vec3 depthPosition(vec2 screen, float depth) {
    vec4 p=frame.inverseViewProjection*vec4(screen.x*2.0-1.0,1.0-screen.y*2.0,depth*2.0-1.0,1.0);
    return p.xyz/max(abs(p.w),0.00001)*sign(p.w);
}
vec3 waterReflection(vec3 n, vec3 v) {
    vec3 ray=reflect(-v,n), fallback=frame.policy.x>0.0 ? frame.sky.rgb : pow(clamp(frame.sky.rgb,0.0,1.0),vec3(1.0/2.2));
    float previous=-1.0, distanceAlong=0.25;
    for(int i=0;i<12;i++) {
        distanceAlong*=1.4;
        vec3 samplePosition=worldPosition+ray*distanceAlong;
        vec4 projected=frame.viewProjection*vec4(samplePosition,1.0);
        if(projected.w<=0.0) break;
        vec2 screen=projected.xy/projected.w*vec2(0.5,-0.5)+0.5;
        if(any(lessThan(screen,vec2(0.015)))||any(greaterThan(screen,vec2(0.985)))) break;
        float depth=textureLod(opaqueDepth,screen,0.0).r;
        if(depth>=0.99999) continue;
        vec3 scene=depthPosition(screen,depth);
        float separation=length(samplePosition-cameraEye())-length(scene-cameraEye());
        // A crossing avoids reflecting foreground objects at the ray origin.
        if(previous<0.0 && separation>=0.0 && separation<0.65) {
            float edge=smoothstep(0.015,0.08,min(min(screen.x,screen.y),min(1.0-screen.x,1.0-screen.y)));
            return mix(fallback,textureLod(opaqueColor,screen,0.0).rgb,edge);
        }
        previous=separation;
    }
    return fallback;
}
#include "lod_fade.glsl"
void main() {
    lodCoverage();
    if(frame.cascadeEye.w>0.0) {
        float depth=textureLod(shadowMap,gl_FragCoord.xy/max(frame.cinema.zw,vec2(1)),0.0).r;
        color=vec4(vec3(depth),1);
        return;
    }
    float roughness=object.colorRough.a, metallic=object.params.x, occlusion=1.0;
    if((int(object.params.w)&2)!=0) {
        vec3 orm=surfaceSample(ormMap).rgb;
        occlusion=orm.r;
        roughness=clamp(orm.g,0.045,1.0);
        metallic=orm.b;
    }
    bool slopeTint=(int(object.params.w)&16)!=0;
    vec3 albedo=slopeTint ? vec3(1) : baseColor;
    albedo*=vertexColor.rgb;
    if(textured!=0) { vec4 sampleColor=surfaceSample(albedoMap); if(textured!=2.0 && sampleColor.a*vertexColor.a<(textured>=3.0 ? textured-3.0 : 0.45)) discard; albedo*=sampleColor.rgb; }
    if(slopeTint) {
        float exposed=1.0-smoothstep(0.30,0.70,normalize(materialNormal).y);
        albedo*=mix(vec3(1),baseColor,exposed);
    }
    bool foliage=(int(object.params.w)&8)!=0;
    vec3 geometric=normalize(worldNormal);
    if(foliage && dot(geometric,cameraEye()-worldPosition)<0.0) geometric=-geometric;
    vec3 n=surfaceNormal(geometric), v=normalize(cameraEye()-worldPosition), l=normalize(sunDirection), h=normalize(v+l);
    bool water=(int(object.params.w)&64)!=0;
    float shoreFoam=0.0, waterDepth=20.0;
    if(water) {
        // Small periodic slopes preserve the collision surface and stable origin.
        float phase=frame.wind.x;
        vec2 p=materialPosition.xz;
        vec2 slope=vec2(cos(dot(p,vec2(.75,.28))+phase),sin(dot(p,vec2(-.32,.91))-phase))*0.055;
        n=normalize(n+vec3(slope.x,0,slope.y));
        vec2 screen=gl_FragCoord.xy/max(frame.cinema.zw,vec2(1.0));
        float depth=textureLod(opaqueDepth,screen,0.0).r;
        if(depth<0.99999) waterDepth=clamp(length(depthPosition(screen,depth)-worldPosition),0.0,20.0);
        float ripples=0.5+0.5*sin(dot(p,vec2(2.8,1.7))+phase*1.8);
        shoreFoam=(1.0-smoothstep(0.08,0.65+0.18*ripples,waterDepth))*(0.55+0.35*ripples);
        albedo=mix(vec3(0.08,0.28,0.25),albedo,1.0-exp(-waterDepth*0.35));
        albedo=mix(albedo,vec3(0.72,0.86,0.81),shoreFoam);
        roughness=mix(0.18,0.65,shoreFoam);
    }
    if(frame.cinema.x>0.0) {
        vec3 nx=dFdx(n), ny=dFdy(n);
        roughness=sqrt(clamp(roughness*roughness+min(0.18,0.25*(dot(nx,nx)+dot(ny,ny))),0.002025,1.0));
    }
    float nl=max(dot(n,l),0.0), nv=max(dot(n,v),0.001), nh=max(dot(n,h),0.0), vh=max(dot(v,h),0.0);
    float a=max(roughness*roughness,0.002), a2=a*a, d=nh*nh*(a2-1.0)+1.0;
    float D=a2/(PI*d*d), k=(roughness+1.0)*(roughness+1.0)/8.0;
    float G=nv/(nv*(1.0-k)+k)*nl/(nl*(1.0-k)+k);
    vec3 F0=mix(vec3(0.04),albedo,metallic), F=F0+(1.0-F0)*pow(1.0-vh,5.0);
    vec3 spec=D*G*F/max(4.0*nv*nl,0.001);
    vec3 ambient=albedo*mix(frame.ground.rgb,frame.sky.rgb,n.y*0.5+0.5)*occlusion;
    vec3 rim=albedo*frame.sky.rgb*pow(1.0-nv,3.0)*frame.sky.w*0.18;
    if(frame.policy.y>0.0) {
        vec3 envF=F0+(max(vec3(1.0-roughness),F0)-F0)*pow(1.0-nv,5.0);
        ambient=((1.0-envF)*(1.0-metallic)*albedo*environmentLight(n,true,roughness)+envF*environmentLight(reflect(-v,n),false,roughness))*occlusion;
        rim=vec3(0);
    }
    // Opaque back-facing surfaces receive no directional diffuse/specular term.
    // Skip their shadow lookups; thin leaves still need reverse-side visibility.
    float shadow=(!foliage && nl<=0.0) ? 1.0 : visibility(n,l);
    vec3 radiance=ambient+rim+((1.0-F)*(1.0-metallic)*albedo/PI+spec)*nl*frame.sunColor.rgb*shadow+albedo*emission;
    radiance+=localIllumination(n,v,albedo,roughness,metallic);
    // Thin leaves transmit a restrained amount of light from the reverse side.
    // Reuse shadow visibility so covered leaves cannot glow through occluders.
    if(foliage) radiance+=albedo*(1.0-metallic)*frame.sunColor.rgb*max(dot(-n,l),0.0)*0.22*object.pose.w*shadow;
    vec3 sky=frame.haze.rgb;
    float opticalDepth=length(worldPosition-cameraEye())*fogDensity;
    if(frame.cinema.x>0.0) {
        // Integrate exponential height mist along the camera-to-surface segment.
        // Heights stay absolute even though geometry uses a floating origin.
        float mistDistance=max(length(worldPosition-cameraEye())-6.0,0.0);
        float entry=min(6.0/max(length(worldPosition-cameraEye()),0.001),1.0);
        float startHeight=(frame.atmosphere.x-frame.atmosphere.y+(worldPosition.y-cameraEye().y)*entry)*frame.atmosphere.w;
        float endHeight=(frame.atmosphere.x-frame.atmosphere.y+worldPosition.y-cameraEye().y)*frame.atmosphere.w;
        float startDensity=exp(clamp(-startHeight,-8.0,8.0));
        float endDensity=exp(clamp(-endHeight,-8.0,8.0));
        float delta=endHeight-startHeight;
        float average=abs(delta)<0.01 ? exp(clamp(-(startHeight+endHeight)*0.5,-8.0,8.0)) : (startDensity-endDensity)/delta;
        opticalDepth+=mistDistance*frame.atmosphere.z*max(average,0.0)*frame.cinema.x;
        float sunHaze=pow(max(dot(-v,l),0.0),8.0)*0.35*frame.cinema.x;
        sky=mix(sky,frame.sunColor.rgb*0.24,sunHaze);
    }
    float fog=1.0-exp(-opticalDepth);
    radiance=mix(radiance,sky,fog);
    if(frame.cinema.x>0.0) {
        float luminance=dot(radiance,vec3(0.2126,0.7152,0.0722));
        vec3 grade=mix(vec3(0.94,0.98,1.05),vec3(1.06,1.015,0.95),smoothstep(0.05,1.0,luminance));
        radiance*=mix(vec3(1.0),grade,frame.cinema.x);
    }
    if(frame.policy.x>0.0) {
        if(water) {
            vec2 screen=gl_FragCoord.xy/max(frame.cinema.zw,vec2(1));
            vec3 transmitted=textureLod(opaqueColor,screen+n.xz*0.0015,0).rgb;
            float transparency=0.24*exp(-waterDepth*0.65)*(1.0-shoreFoam);
            radiance=mix(radiance,transmitted,transparency);
            float fresnel=(0.04+0.30*pow(1.0-max(dot(n,v),0.0),5.0))*(1.0-shoreFoam);
            radiance=mix(radiance,waterReflection(n,v),fresnel);
        }
        color=vec4(clamp(radiance,vec3(0),vec3(60000)),1);
        return;
    }
    radiance*=frame.sunColor.w;
    // Filmic highlight roll-off in linear light, followed by display encoding.
    radiance=clamp((radiance*(2.51*radiance+0.03))/(radiance*(2.43*radiance+0.59)+0.14),0.0,1.0);
    vec3 encoded=pow(radiance,vec3(1.0/2.2));
    if(frame.cinema.x>0.0) {
        vec2 screen=(gl_FragCoord.xy/max(frame.cinema.zw,vec2(1.0))-0.5)*1.41421356;
        encoded*=1.0-frame.cinema.y*frame.cinema.x*smoothstep(0.15,1.0,dot(screen,screen));
    }
    if(water) {
        vec2 screen=gl_FragCoord.xy/max(frame.cinema.zw,vec2(1.0));
        vec3 transmitted=textureLod(opaqueColor,screen+n.xz*0.0015,0.0).rgb;
        float transparency=0.24*exp(-waterDepth*0.65)*(1.0-shoreFoam);
        encoded=mix(encoded,transmitted,transparency);
        float fresnel=(0.04+0.30*pow(1.0-max(dot(n,v),0.0),5.0))*(1.0-shoreFoam);
        encoded=mix(encoded,waterReflection(n,v),fresnel);
    }
    color=vec4(encoded,1.0);
}
