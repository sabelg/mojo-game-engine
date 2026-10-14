// Complementary deterministic coverage in color, shadow and opaque-depth passes.
// The threshold is shared by a near/far pair; it consumes no temporal history.
void lodCoverage() {
    int flags=int(object.params.w);
    if((flags&16384)==0) return;
    uvec2 pixel=uvec2(gl_FragCoord.xy);
    uint seed=pixel.x+4099u*pixel.y;
    seed^=seed>>16; seed*=0x7feb352du;
    seed^=seed>>15; seed*=0x846ca68bu; seed^=seed>>16;
    float noise=float(seed&65535u)/65536.0;
    bool nearPixel=noise>=object.pose.z;
    if(nearPixel==((flags&32768)!=0)) discard;
}
