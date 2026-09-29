#version 450
layout(location=0) in vec2 position;
layout(location=1) in vec4 tint;
layout(location=2) in vec2 texcoord;
layout(push_constant) uniform Screen { vec2 viewport; } screen;
layout(location=0) out vec4 vertexColor;
layout(location=1) out vec2 uv;
void main(){gl_Position=vec4(position/screen.viewport*2.0-1.0,0,1);vertexColor=tint;uv=texcoord;}
