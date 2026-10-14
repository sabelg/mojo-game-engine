/* Object-local facial controls, independent of body clip interpolation. */
int faceTag(){return (int(object.params.w)&128)!=0?int(floor(texcoord.x)):0;}
vec3 faceAxis(){vec3 a=frame.faceAxis[0].xyz;return dot(a,a)>1e-8?normalize(a):vec3(1,0,0);}
float faceAngle(int tag){return tag==10||tag==11?frame.faceWeights.x:tag==14?frame.faceWeights.z:0.0;}
vec3 faceRotate(vec3 p,float angle){vec3 a=faceAxis();return p*cos(angle)+cross(a,p)*sin(angle)+a*dot(a,p)*(1.0-cos(angle));}
vec3 facePosition(vec3 p){int tag=faceTag();if(tag<10||tag>14)return p;int index=tag-10;vec3 pivot=frame.faceCenters[index].xyz;p=pivot+faceRotate(p-pivot,faceAngle(tag));if(tag==12||tag==13)p+=frame.faceAxis[1].xyz*frame.faceWeights.y;return p;}
vec3 faceNormal(vec3 n){return faceRotate(n,faceAngle(faceTag()));}
vec2 faceUV(){return texcoord-vec2(float(faceTag()),0);}
