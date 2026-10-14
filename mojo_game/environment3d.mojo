"""Bounded low-frequency distant lighting in linear RGB, with a Y-up basis.

SH stores radiance, not preconvolved irradiance. Nine terms preserve diffuse
lighting well; this path deliberately cannot reproduce sharp mirror highlights.
"""
from std.math import sin,cos,exp,isfinite
from .math3d import Vec3

def environment_basis(direction: Vec3) -> List[Float64]:
    var x=direction.x
    var y=direction.y
    var z=direction.z
    return [0.28209479177387814,0.4886025119029199*y,0.4886025119029199*z,0.4886025119029199*x,1.0925484305920792*x*y,1.0925484305920792*y*z,0.31539156525252005*(3*z*z-1),1.0925484305920792*x*z,0.5462742152960396*(x*x-y*y)]

struct Environment3D(Copyable,Movable):
    var coefficients: List[Vec3]

    def __init__(out self):
        self.coefficients=List[Vec3](length=9,fill=Vec3(0,0,0))

    @staticmethod
    def constant(radiance: Vec3) raises -> Environment3D:
        for value in [radiance.x,radiance.y,radiance.z]:
            if not isfinite(value) or value<0 or value>60000:raise Error("Environment radiance must be finite within 0..60000")
        var result=Environment3D()
        result.coefficients[0]=radiance*3.544907701811032
        return result^

    @staticmethod
    def hemisphere(sky: Vec3,ground: Vec3) raises -> Environment3D:
        """Exact SH projection of a linear blend between -Y ground and +Y sky."""
        _=Environment3D.constant(sky)
        _=Environment3D.constant(ground)
        var result=Environment3D()
        result.coefficients[0]=(sky+ground)*1.772453850905516
        result.coefficients[1]=(sky-ground)*1.0233267079464885
        return result^

    @staticmethod
    def latlong(pixels: List[Vec3],width: Int,height: Int) raises -> Environment3D:
        """Project a linear HDR panorama; top is +Y, U=0 is +X, U=.25 is +Z.

        Call during loading, not per frame. At most 262144 RGB samples and 2048
        pixels per axis; exact row solid angles avoid pole over-weighting.
        """
        if width<4 or height<2 or width>2048 or height>2048 or width*height>262144 or len(pixels)!=width*height:raise Error("Environment panorama dimensions exceed the bounded projection")
        var result=Environment3D()
        comptime pi=3.141592653589793
        for row in range(height):
            var theta=(Float64(row)+.5)*pi/Float64(height)
            var weight=(cos(Float64(row)*pi/Float64(height))-cos(Float64(row+1)*pi/Float64(height)))*2*pi/Float64(width)
            for column in range(width):
                var pixel=pixels[row*width+column]
                for value in [pixel.x,pixel.y,pixel.z]:
                    if not isfinite(value) or value<0 or value>60000:raise Error("Environment radiance must be finite within 0..60000")
                var phi=(Float64(column)+.5)*2*pi/Float64(width)
                var basis=environment_basis(Vec3(sin(theta)*cos(phi),cos(theta),sin(theta)*sin(phi)))
                for term in range(9):result.coefficients[term]=result.coefficients[term]+pixel*(basis[term]*weight)
        return result^

    def diffuse(self,normal: Vec3) raises -> Vec3:
        if len(self.coefficients)!=9 or not isfinite(normal.length()) or normal.length()<1e-8:raise Error("Environment needs nine coefficients and a finite nonzero direction")
        var basis=environment_basis(normal.unit())
        var value=Vec3(0,0,0)
        for i in range(9):value=value+self.coefficients[i]*(basis[i]*(1.0 if i==0 else 2.0/3.0 if i<4 else .25))
        return Vec3(max(0.0,value.x),max(0.0,value.y),max(0.0,value.z))
