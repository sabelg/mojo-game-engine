#version 450
#extension GL_GOOGLE_include_directive : require
layout(location=0) in vec3 position;
layout(location=9) in mat4 instanceModel;
layout(location=2) in vec2 texcoord;
layout(location=3) in vec3 nextPosition;
layout(location=5) in vec3 targetPosition;
layout(location=7) in vec3 targetNextPosition;
layout(location=0) out vec2 uv;
layout(location=1) out float vertexAlpha;
layout(set=0,binding=0) uniform Frame { mat4 viewProjection; mat4 lightMatrix; vec4 sunFog; vec4 sky; vec4 ground; vec4 sunColor; vec4 haze; vec4 atmosphere; vec4 cinema; vec4 wind; vec4 faceCenters[5]; vec4 faceAxis[2]; vec4 faceWeights; mat4 inverseViewProjection; } frame;
layout(push_constant) uniform Object { mat4 model; vec4 colorRough; vec4 params; vec4 pose; } object;
#include "foliage_wind.glsl"
#include "hero_face.glsl"
#include "skinning.glsl"
void main(){
    uv=faceUV();
    vec3 p=mix(mix(position,nextPosition,object.pose.x),mix(targetPosition,targetNextPosition,object.pose.y),object.pose.z);
    if((int(object.params.w)&18176)!=0) p=position;
    vertexAlpha=vertexColorValue().a;
    vec3 unusedNormal=vec3(0,1,0);
    skinVertex(p,unusedNormal);
    gl_Position=frame.viewProjection*(object.model*instanceModel)*vec4(windPosition(facePosition(p)),1.0);
    gl_Position.y=-gl_Position.y;
    gl_Position.z=(gl_Position.z+gl_Position.w)*0.5;
}
