#version 450
layout(location=0) in vec3 position;
layout(location=2) in vec2 texcoord;
layout(location=3) in vec3 nextPosition;
layout(location=0) out vec2 uv;
layout(set=0,binding=0) uniform Frame { mat4 viewProjection; mat4 lightMatrix; vec4 sunFog; vec4 sky; vec4 ground; vec4 sunColor; vec4 haze; } frame;
layout(push_constant) uniform Object { mat4 model; vec4 colorRough; vec4 params; vec4 pose; } object;
void main(){
    uv=texcoord;
    gl_Position=frame.lightMatrix*object.model*vec4(mix(position,nextPosition,object.pose.x),1.0);
    gl_Position.y=-gl_Position.y;
    gl_Position.z=(gl_Position.z+gl_Position.w)*0.5;
}
