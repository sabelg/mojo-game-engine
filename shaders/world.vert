#version 450
layout(location=0) in vec3 position;
layout(location=1) in vec3 normal;
layout(location=2) in vec2 texcoord;
layout(location=3) in vec3 nextPosition;
layout(location=4) in vec3 nextNormal;
layout(set=0,binding=0) uniform Frame { mat4 viewProjection; mat4 lightMatrix; vec4 sunFog; vec4 sky; vec4 ground; vec4 sunColor; vec4 haze; } frame;
layout(push_constant) uniform Object { mat4 model; vec4 colorRough; vec4 params; vec4 pose; } object;
layout(location=0) out vec3 worldPosition;
layout(location=1) out vec3 worldNormal;
layout(location=2) out vec2 uv;
layout(location=3) out vec4 shadowPosition;
void main() {
    vec4 p=object.model*vec4(mix(position,nextPosition,object.pose.x),1.0);
    worldPosition=p.xyz;
    vec3 blended=mix(normal,nextNormal,object.pose.x);
    if(dot(blended,blended)<1e-8) blended=normal;
    worldNormal=mat3(transpose(inverse(object.model)))*normalize(blended);
    uv=texcoord;
    shadowPosition=frame.lightMatrix*p;
    gl_Position=frame.viewProjection*p;
    gl_Position.y=-gl_Position.y;
    gl_Position.z=(gl_Position.z+gl_Position.w)*0.5;
}
