#version 450
layout(location=0) in vec4 vertexColor;
layout(location=1) in vec2 uv;
layout(set=0,binding=2) uniform sampler2D fontAtlas;
layout(location=0) out vec4 color;
void main(){
    color=vertexColor;
    if(uv.x>=0) color.a*=texture(fontAtlas,uv).a;
    else if(uv.x<=-2) {
        float distance=length(vec2((uv.x+3)*2-1,uv.y*2-1));
        float edge=max(fwidth(distance),0.001);
        color.a*=1.0-smoothstep(1.0-edge,1.0,distance);
    }
}
