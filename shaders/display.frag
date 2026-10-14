#version 450
layout(location=0) in vec2 uv;
layout(location=0) out vec4 color;
layout(set=0,binding=0) uniform Frame { mat4 viewProjection; mat4 lightMatrix; vec4 sunFog; vec4 sky; vec4 ground; vec4 sunColor; vec4 haze; vec4 atmosphere; vec4 cinema; vec4 wind; vec4 faceCenters[5]; vec4 faceAxis[2]; vec4 faceWeights; mat4 inverseViewProjection; mat4 cascadeMatrices[4]; vec4 cascadeSplits; vec4 cascadeForward; vec4 cascadeEye; vec4 policy; vec4 environment[9]; } frame;
layout(set=0,binding=8) uniform sampler2D linearScene;
vec3 srgb(vec3 x) {
    return mix(12.92*x,1.055*pow(x,vec3(1.0/2.4))-0.055,greaterThan(x,vec3(0.0031308)));
}
void main() {
    vec3 light=max(textureLod(linearScene,uv,0).rgb,vec3(0));
    // Debug depth is a display value, bypass exposure and filmic mapping.
    if(frame.cascadeEye.w>0.0) { color=vec4(light,1); return; }
    light*=frame.sunColor.w;
    vec3 mapped=clamp((light*(2.51*light+0.03))/(light*(2.43*light+0.59)+0.14),0.0,1.0);
    vec3 encoded=srgb(mapped);
    if(frame.cinema.x>0.0) {
        vec2 screen=(uv-0.5)*1.41421356;
        encoded*=1.0-frame.cinema.y*frame.cinema.x*smoothstep(0.15,1.0,dot(screen,screen));
    }
    color=vec4(encoded,1);
}
