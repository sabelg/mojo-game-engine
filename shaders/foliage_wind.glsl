// Object-local coordinates keep the wind stable when the floating origin moves.
// Both vertex passes include this definition; all LODs sample the same field.
const vec3 windDirection=vec3(0.8,0.12,0.6);
float windOffset(vec3 p) {
    return frame.wind.y*(0.75*sin(dot(p,vec3(0.23,0.07,0.17))+frame.wind.x)
                       +0.25*sin(dot(p,vec3(0.71,0.19,0.53))+3.0*frame.wind.x));
}
vec3 windPosition(vec3 p) {
    if((int(object.params.w)&32)==0 || frame.wind.y==0.0) return p;
    return p+windDirection*windOffset(p);
}
vec3 windNormal(vec3 p,vec3 n) {
    if((int(object.params.w)&32)==0 || frame.wind.y==0.0) return n;
    vec3 gradient=frame.wind.y*(0.75*cos(dot(p,vec3(0.23,0.07,0.17))+frame.wind.x)*vec3(0.23,0.07,0.17)
                              +0.25*cos(dot(p,vec3(0.71,0.19,0.53))+3.0*frame.wind.x)*vec3(0.71,0.19,0.53));
    // Exact inverse-transpose of I + windDirection * gradient^T.
    return normalize(n-gradient*dot(windDirection,n)/(1.0+dot(gradient,windDirection)));
}
