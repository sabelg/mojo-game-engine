"""Procedural transformed triangle, quad, box, cylinder and ring primitives."""
from std.math import sin, cos
from mojo_game.math3d import Vec3, Camera, forward, right, up, FOCAL
from mojo_game.window import Window, Color, Point
comptime Display = Window

def projected(p: Vec3) -> Point:
    return Point(550+FOCAL*p.x/p.z, 380-FOCAL*p.y/p.z)


def rotate(p: Vec3, yaw: Float64, pitch: Float64) -> Vec3:
    return right(yaw)*p.x+up(yaw, pitch)*p.y+forward(yaw, pitch)*p.z


def segment(mut ui: Display, camera: Camera, a: Vec3, b: Vec3, c: Color):
    ui.raster.line(camera, a, b, Vec3(Float64(c.r), Float64(c.g), Float64(c.b)), 1)


def tri(mut ui: Display, camera: Camera, center: Vec3, yaw: Float64, pitch: Float64, a: Vec3, b: Vec3, c: Vec3, color: Vec3, emissive: Bool = False):
    ui.raster.triangle(camera, center+rotate(a,yaw,pitch), center+rotate(b,yaw,pitch), center+rotate(c,yaw,pitch), color, emissive)


def quad(mut ui: Display, camera: Camera, center: Vec3, yaw: Float64, pitch: Float64, a: Vec3, b: Vec3, c: Vec3, d: Vec3, color: Vec3, emissive: Bool = False):
    tri(ui,camera,center,yaw,pitch,a,b,c,color,emissive)
    tri(ui,camera,center,yaw,pitch,a,c,d,color,emissive)


def box3(mut ui: Display, camera: Camera, center: Vec3, yaw: Float64, pitch: Float64, lo: Vec3, hi: Vec3, color: Vec3):
    var p: List[Vec3] = [Vec3(lo.x,lo.y,lo.z),Vec3(hi.x,lo.y,lo.z),Vec3(hi.x,hi.y,lo.z),Vec3(lo.x,hi.y,lo.z),Vec3(lo.x,lo.y,hi.z),Vec3(hi.x,lo.y,hi.z),Vec3(hi.x,hi.y,hi.z),Vec3(lo.x,hi.y,hi.z)]
    var faces: List[Int] = [0,1,2,3, 4,7,6,5, 0,4,5,1, 3,2,6,7, 0,3,7,4, 1,5,6,2]
    for i in range(0,len(faces),4): quad(ui,camera,center,yaw,pitch,p[faces[i]],p[faces[i+1]],p[faces[i+2]],p[faces[i+3]],color)


def cylinder(mut ui: Display, camera: Camera, center: Vec3, yaw: Float64, pitch: Float64, x: Float64, y: Float64, z0: Float64, z1: Float64, radius: Float64, color: Vec3):
    for i in range(10):
        var a=Float64(i)*6.283185307/10
        var b=Float64(i+1)*6.283185307/10
        var p=Vec3(x+cos(a)*radius,y+sin(a)*radius,z0)
        var q=Vec3(x+cos(b)*radius,y+sin(b)*radius,z0)
        var r=Vec3(q.x,q.y,z1)
        var s=Vec3(p.x,p.y,z1)
        quad(ui,camera,center,yaw,pitch,p,q,r,s,color)
        tri(ui,camera,center,yaw,pitch,Vec3(x,y,z0),q,p,color*0.55)
        tri(ui,camera,center,yaw,pitch,Vec3(x,y,z1),s,r,color)


def ring(mut ui: Display, camera: Camera, center: Vec3, radius: Float64, color: Color, axis: Int = 0):
    for i in range(64):
        var a=Float64(i)*6.283185307/64
        var b=Float64(i+1)*6.283185307/64
        var p=Vec3(cos(a)*radius,sin(a)*radius,0)
        var q=Vec3(cos(b)*radius,sin(b)*radius,0)
        if axis==1:
            p=Vec3(p.x,0,p.y)
            q=Vec3(q.x,0,q.y)
        elif axis==2:
            p=Vec3(0,p.x,p.y)
            q=Vec3(0,q.x,q.y)
        segment(ui,camera,center+p,center+q,color)


