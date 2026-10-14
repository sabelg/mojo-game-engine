#version 450
#extension GL_GOOGLE_include_directive : require
layout(location=0) in vec2 uv;
layout(location=1) in float vertexAlpha;
layout(set=0,binding=2) uniform sampler2D albedoMap;
layout(push_constant) uniform Object { mat4 model; vec4 colorRough; vec4 params; vec4 pose; } object;
#include "lod_fade.glsl"
void main(){ lodCoverage(); if(object.params.z!=0 && object.params.z!=2.0 && texture(albedoMap,uv).a*vertexAlpha<(object.params.z>=3.0 ? object.params.z-3.0 : 0.45)) discard; }
