layout(set=0,binding=7,std430) readonly buffer SkinData { float skinData[]; };
mat4 skinMatrix(int start) {
    return mat4(vec4(skinData[start],skinData[start+1],skinData[start+2],skinData[start+3]),
                vec4(skinData[start+4],skinData[start+5],skinData[start+6],skinData[start+7]),
                vec4(skinData[start+8],skinData[start+9],skinData[start+10],skinData[start+11]),
                vec4(skinData[start+12],skinData[start+13],skinData[start+14],skinData[start+15]));
}
vec4 vertexColorValue() {
    if((int(object.params.w)&512)==0) return vec4(1);
    int start=int(object.pose.x)+gl_VertexIndex*4;
    return vec4(skinData[start],skinData[start+1],skinData[start+2],skinData[start+3]);
}
vec4 vertexTangentValue() {
    if((int(object.params.w)&1024)==0) return vec4(0);
    int start=int(object.pose.y)+gl_VertexIndex*4;
    vec4 result=vec4(skinData[start],skinData[start+1],skinData[start+2],skinData[start+3]);
    if((int(object.params.w)&256)!=0) {
        int block=int(object.pose.w), joints=int(skinData[block]);
        int influences=block+1+joints*32+gl_VertexIndex*8;
        vec3 direction=vec3(0);
        for(int i=0;i<4;++i) {
            int joint=int(skinData[influences+i*2]); float weight=skinData[influences+i*2+1];
            if(weight!=0) direction+=(skinMatrix(block+1+joint*32)*vec4(result.xyz,0)).xyz*weight;
        }
        result.xyz=normalize(direction);
    }
    return result;
}
void skinVertex(inout vec3 p,inout vec3 n) {
    if((int(object.params.w)&256)==0) return;
    int block=int(object.pose.w), joints=int(skinData[block]);
    int influences=block+1+joints*32+gl_VertexIndex*8;
    vec3 result=vec3(0), normalResult=vec3(0); float total=0;
    for(int i=0;i<4;++i) {
        int joint=int(skinData[influences+i*2]); float weight=skinData[influences+i*2+1];
        if(weight==0) continue;
        int palette=block+1+joint*32;
        result+=(skinMatrix(palette)*vec4(p,1)).xyz*weight;
        normalResult+=(skinMatrix(palette+16)*vec4(n,0)).xyz*weight;
        total+=weight;
    }
    p=result/total;
    n=normalize(normalResult);
}
