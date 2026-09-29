#version 450
layout(location=0) in vec2 uv;
layout(set=0,binding=2) uniform sampler2D albedoMap;
layout(push_constant) uniform Object { mat4 model; vec4 colorRough; vec4 params; vec4 pose; } object;
void main(){ if(object.params.z!=0 && texture(albedoMap,uv).a<0.45) discard; }
