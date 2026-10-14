#version 450
#extension GL_GOOGLE_include_directive : require
layout(location=0) in vec3 position;
layout(location=9) in mat4 instanceModel;
layout(location=1) in vec3 normal;
layout(location=2) in vec2 texcoord;
layout(location=3) in vec3 nextPosition;
layout(location=5) in vec3 targetPosition;
layout(location=7) in vec3 targetNextPosition;
layout(location=4) in vec3 nextNormal;
layout(location=6) in vec3 targetNormal;
layout(location=8) in vec3 targetNextNormal;
layout(set=0,binding=0) uniform Frame { mat4 viewProjection; mat4 lightMatrix; vec4 sunFog; vec4 sky; vec4 ground; vec4 sunColor; vec4 haze; vec4 atmosphere; vec4 cinema; vec4 wind; vec4 faceCenters[5]; vec4 faceAxis[2]; vec4 faceWeights; mat4 inverseViewProjection; } frame;
layout(push_constant) uniform Object { mat4 model; vec4 colorRough; vec4 params; vec4 pose; } object;
layout(location=0) out vec3 worldPosition;
layout(location=1) out vec3 worldNormal;
layout(location=2) out vec2 uv;
layout(location=3) out vec4 shadowPosition;
layout(location=4) out vec3 materialPosition;
layout(location=5) out vec3 materialNormal;
layout(location=6) out vec4 vertexColor;
layout(location=7) out vec4 worldTangent;
#include "foliage_wind.glsl"
#include "hero_face.glsl"
#include "skinning.glsl"
void main() {
    materialPosition=mix(mix(position,nextPosition,object.pose.x),mix(targetPosition,targetNextPosition,object.pose.y),object.pose.z);
    if((int(object.params.w)&18176)!=0) materialPosition=position;
    vertexColor=vertexColorValue();
    vec3 skinNormal=normal;
    skinVertex(materialPosition,skinNormal);
    materialPosition=facePosition(materialPosition);
    vec3 animated=windPosition(materialPosition);
    if((int(object.params.w)&64)!=0) {
        animated.y+=0.018*sin(dot(materialPosition.xz,vec2(.75,.28))+frame.wind.x)
                  +0.012*sin(dot(materialPosition.xz,vec2(-.32,.91))-frame.wind.x);
    }
    vec4 p=(object.model*instanceModel)*vec4(animated,1.0);
    worldPosition=p.xyz;
    vec3 blended=mix(mix(normal,nextNormal,object.pose.x),mix(targetNormal,targetNextNormal,object.pose.y),object.pose.z);
    if((int(object.params.w)&18176)!=0) blended=normal;
    if((int(object.params.w)&256)!=0) blended=skinNormal;
    if(dot(blended,blended)<1e-8) blended=normal;
    blended=faceNormal(blended);
    blended=windNormal(materialPosition,blended);
    materialNormal=normalize(blended);
    worldNormal=mat3(transpose(inverse(object.model*instanceModel)))*normalize(blended);
    vec4 tangent=vertexTangentValue();
    worldTangent=vec4(mat3(object.model*instanceModel)*tangent.xyz,tangent.w*sign(determinant(mat3(object.model*instanceModel))));
    uv=faceUV();
    shadowPosition=frame.lightMatrix*p;
    gl_Position=frame.viewProjection*p;
    gl_Position.y=-gl_Position.y;
    gl_Position.z=(gl_Position.z+gl_Position.w)*0.5;
}
