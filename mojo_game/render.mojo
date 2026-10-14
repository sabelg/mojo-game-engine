"""Native Mojo software 3D renderer: clipped triangles, depth, lighting and planets."""
from std.math import sqrt, sin, cos, atan2
from mojo_game.math3d import Vec3, Camera, FOCAL, plane
from std.ffi import external_call
from mojo_game import sdl

comptime WIDTH = 1100
comptime HEIGHT = 760

def rgb(r: Float64, g: Float64, b: Float64) -> UInt32:
    return UInt32(0xFF000000) | (UInt32(max(0.0, min(255.0, r))) << 16) | (UInt32(max(0.0, min(255.0, g))) << 8) | UInt32(max(0.0, min(255.0, b)))

def edge(a: Vec3, b: Vec3, x: Float64, y: Float64) -> Float64:
    return (x-a.x)*(b.y-a.y)-(y-a.y)*(b.x-a.x)

def noise(x: Float64, y: Float64) -> Float64:
    var ix=x//1
    var iy=y//1
    var fx=x-ix
    var fy=y-iy
    fx=fx*fx*(3-2*fx)
    fy=fy*fy*(3-2*fy)
    var a=sin(ix*127.1+iy*311.7)*43758.5453
    var b=sin((ix+1)*127.1+iy*311.7)*43758.5453
    var c=sin(ix*127.1+(iy+1)*311.7)*43758.5453
    var d=sin((ix+1)*127.1+(iy+1)*311.7)*43758.5453
    a-=a//1
    b-=b//1
    c-=c//1
    d-=d//1
    return (a*(1-fx)+b*fx)*(1-fy)+(c*(1-fx)+d*fx)*fy

struct Raster:
    var pixels: List[UInt32]
    var depth: List[Float32]
    var planet: List[UInt32]
    var texture: sdl.NullableHandle

    def __init__(out self):
        self.pixels = List[UInt32](length=WIDTH*HEIGHT, fill=0xFF03060C)
        self.depth = List[Float32](length=WIDTH*HEIGHT, fill=0)
        self.texture = None
        self.planet = List[UInt32](length=512*256,fill=0)
        # Cache a continuous spherical material once, outside the frame loop.
        for y in range(256):
            var v=Float64(y)/127.5-1
            var radius=sqrt(max(0.0,1-v*v))
            for x in range(512):
                var u=(Float64(x)+0.5)*6.283185308/512-3.141592654
                var world=Vec3(sin(u)*radius,v,cos(u)*radius)
                var nx=world.x*5+world.z*3+sin(world.y*4)*0.7
                var ny=world.y*9+world.z*2+sin(world.x*3)*0.5
                var terrain=noise(nx,ny)*0.6+noise(nx*2.1,ny*2.1)*0.27+noise(nx*5.3,ny*5.3)*0.13
                var color=Vec3(12,39,65)
                if terrain>0.46:
                    var elevation=max(0.0,min(1.0,(terrain-0.46)*4))
                    color=Vec3(35,65,37)*(1-elevation)+Vec3(93,101,67)*elevation
                var clouds=noise(nx*1.7+14,ny*2.3)*0.65+noise(nx*6.1+30,ny*5.7)*0.35
                var opacity=max(0.0,min(0.83,(clouds-0.48)*2.8))
                color=color*(1-opacity)+Vec3(195,207,214)*opacity
                self.planet[y*512+x]=rgb(color.x,color.y,color.z)

    def attach(mut self, renderer: sdl.Handle) raises:
        self.texture = external_call["SDL_CreateTexture", sdl.NullableHandle](renderer, UInt32(0x16362004), Int32(1), Int32(WIDTH), Int32(HEIGHT))
        if not self.texture: raise Error(sdl.error_message())

    def close(mut self):
        if self.texture:
            external_call["SDL_DestroyTexture", NoneType](self.texture.value())
            self.texture = None

    def __deinit__(deinit self):
        self.close()

    def clear(mut self):
        for i in range(WIDTH*HEIGHT):
            self.pixels[i] = 0xFF03060C
            self.depth[i] = 0

    def present(self, renderer: sdl.Handle):
        if not self.texture: return
        _ = external_call["SDL_UpdateTexture", Bool](self.texture.value(), sdl.NullableHandle(None), self.pixels.unsafe_ptr(), Int32(WIDTH*4))
        _ = external_call["SDL_RenderTexture", Bool](renderer, self.texture.value(), sdl.NullableHandle(None), sdl.NullableHandle(None))

    def dot(mut self, x: Int, y: Int, z: Float64, color: UInt32):
        if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT or z <= 0: return
        var index = y*WIDTH+x
        var reciprocal = Float32(1/z)
        if reciprocal >= self.depth[index]:
            self.depth[index] = reciprocal
            self.pixels[index] = color

    def glow(mut self, camera: Camera, center: Vec3, radius: Float64, color: Vec3):
        var p = camera.relative(center)
        if p.z < 8: return
        var cx = 550+FOCAL*p.x/p.z
        var cy = 380-FOCAL*p.y/p.z
        var r = min(180.0, max(1.5, radius*FOCAL/p.z))
        var x0 = max(0, Int(cx-r))
        var x1 = min(WIDTH-1, Int(cx+r))
        var y0 = max(0, Int(cy-r))
        var y1 = min(HEIGHT-1, Int(cy+r))
        for y in range(y0, y1+1):
            for x in range(x0, x1+1):
                var d = ((Float64(x)-cx)*(Float64(x)-cx)+(Float64(y)-cy)*(Float64(y)-cy))/(r*r)
                if d > 1: continue
                var index = y*WIDTH+x
                if self.depth[index] > Float32(1/(p.z-radius*0.5)): continue
                var alpha = (1-d)*(1-d)*0.55
                var old = self.pixels[index]
                self.pixels[index] = rgb(Float64((old >> 16)&255)+color.x*alpha, Float64((old >> 8)&255)+color.y*alpha, Float64(old&255)+color.z*alpha)

    def line(mut self, camera: Camera, a: Vec3, b: Vec3, color: Vec3, thick: Int = 0):
        from mojo_game.math3d import clip_segment
        var p = camera.relative(a)
        var q = camera.relative(b)
        if not clip_segment(p, q): return
        var x0 = 550+FOCAL*p.x/p.z
        var y0 = 380-FOCAL*p.y/p.z
        var x1 = 550+FOCAL*q.x/q.z
        var y1 = 380-FOCAL*q.y/q.z
        var steps = max(1, Int(max(abs(x1-x0), abs(y1-y0))))
        var c = rgb(color.x, color.y, color.z)
        for i in range(steps+1):
            var t = Float64(i)/Float64(steps)
            var z = 1/((1-t)/p.z+t/q.z)
            var x = Int(x0+(x1-x0)*t)
            var y = Int(y0+(y1-y0)*t)
            for dx in range(-thick, thick+1):
                self.dot(x+dx, y, z*0.999, c)

    def triangle(mut self, camera: Camera, a: Vec3, b: Vec3, c: Vec3, color: Vec3, emissive: Bool = False):
        var normal = (b-a).cross(c-a).unit()
        var light = Vec3(-0.5, 0.75, -0.43).unit()
        # Two-sided materials: wing panels remain visible from below.
        var shade = 0.25+0.75*abs(normal.dot(light))
        if emissive: shade = 1
        var distance = camera.relative((a+b+c)*(1.0/3)).z
        var haze = max(0.0, min(0.2, distance/13000))
        var lit = color*(shade*(1-haze))+Vec3(37, 52, 72)*haze
        var polygon: List[Vec3] = [camera.relative(a), camera.relative(b), camera.relative(c)]
        for side in range(6):
            var clipped = List[Vec3]()
            if len(polygon) == 0: return
            var previous = polygon[len(polygon)-1]
            var dp = plane(previous, side)
            for current in polygon:
                var dc = plane(current, side)
                if (dc >= 0) != (dp >= 0): clipped.append(previous+(current-previous)*(dp/(dp-dc)))
                if dc >= 0: clipped.append(current)
                previous = current
                dp = dc
            polygon = clipped^
        var packed = rgb(lit.x, lit.y, lit.z)
        for i in range(1, len(polygon)-1):
            self.raster_triangle(polygon[0], polygon[i], polygon[i+1], packed)

    def raster_triangle(mut self, a: Vec3, b: Vec3, c: Vec3, color: UInt32):
        var p = Vec3(550+FOCAL*a.x/a.z, 380-FOCAL*a.y/a.z, 1/a.z)
        var q = Vec3(550+FOCAL*b.x/b.z, 380-FOCAL*b.y/b.z, 1/b.z)
        var r = Vec3(550+FOCAL*c.x/c.z, 380-FOCAL*c.y/c.z, 1/c.z)
        var area = edge(p, q, r.x, r.y)
        if abs(area) < 0.0001: return
        var x0 = max(0, Int(min(p.x, min(q.x, r.x))))
        var x1 = min(WIDTH-1, Int(max(p.x, max(q.x, r.x)))+1)
        var y0 = max(0, Int(min(p.y, min(q.y, r.y))))
        var y1 = min(HEIGHT-1, Int(max(p.y, max(q.y, r.y)))+1)
        for y in range(y0, y1+1):
            for x in range(x0, x1+1):
                var xx = Float64(x)+0.5
                var yy = Float64(y)+0.5
                var w0 = edge(q, r, xx, yy)/area
                var w1 = edge(r, p, xx, yy)/area
                var w2 = 1-w0-w1
                if w0 < 0 or w1 < 0 or w2 < 0: continue
                var z = Float32(w0*p.z+w1*q.z+w2*r.z)
                var index = y*WIDTH+x
                if z >= self.depth[index]:
                    self.depth[index] = z
                    self.pixels[index] = color

    def sphere(mut self, camera: Camera, center: Vec3, radius: Float64, material: Int, base: Vec3):
        var p = camera.relative(center)
        if p.z+radius <= 8: return
        # Conservative projected bound also supports a camera near the surface.
        var near = max(8.0, p.z-radius)
        var cx = 550+FOCAL*p.x/max(8.0, p.z)
        var cy = 380-FOCAL*p.y/max(8.0, p.z)
        var rr = min(2200.0, FOCAL*radius/near*(1+abs(p.x)/max(8.0,p.z)+abs(p.y)/max(8.0,p.z)))
        var x0 = max(0, Int(cx-rr))
        var x1 = min(WIDTH-1, Int(cx+rr))
        var y0 = max(0, Int(cy-rr))
        var y1 = min(HEIGHT-1, Int(cy+rr))
        var constant = p.dot(p)-radius*radius
        var light = Vec3(-0.55, 0.65, -0.5).unit()
        for y in range(y0, y1+1):
            for x in range(x0, x1+1):
                var ray = Vec3((Float64(x)+0.5-550)/FOCAL, -(Float64(y)+0.5-380)/FOCAL, 1)
                var aa = ray.dot(ray)
                var bb = ray.dot(p)
                var disc = bb*bb-aa*constant
                if disc < 0: continue
                var z = (bb-sqrt(disc))/aa
                if z < 8: continue
                var index = y*WIDTH+x
                if Float32(1/z) < self.depth[index]: continue
                var normal = (ray*z-p)*(1/radius)
                var world = camera.right_axis*normal.x+camera.up_axis*normal.y+camera.forward_axis*normal.z
                var shade = 0.12+0.88*max(0.0, world.dot(light))
                var color = base
                if material == 1:
                    var u = atan2(world.x,world.z)
                    var tx = max(0,min(511,Int((u+3.141592654)*512/6.283185308)))
                    var ty = max(0,min(255,Int((world.y+1)*127.5)))
                    var texel = self.planet[ty*512+tx]
                    color = Vec3(Float64((texel>>16)&255),Float64((texel>>8)&255),Float64(texel&255))
                    var rim = max(0.0, 1-abs(normal.dot(ray.unit())))
                    color = color*shade+Vec3(35, 110, 190)*(rim*rim*0.45)
                elif material == 2 or material == 3:
                    var u = atan2(world.x, world.z)*14
                    var v = world.y*28
                    var fu = u-u//1
                    var fv = v-v//1
                    if material == 2:
                        # Missing plating and a recessed superlaser dish aperture.
                        if world.x > 0.2 and world.y < 0.1 and Int((u//1)+(v//1))%3 != 0: continue
                        if world.z < -0.5 and (world.x*radius-65)*(world.x*radius-65)+(world.y*radius-78)*(world.y*radius-78) < 54*54: continue
                    var plate = 0.8+0.15*sin((u//1)*17+(v//1)*11)
                    if fu < 0.045 or fv < 0.07: plate *= 0.38
                    if abs(world.y) < 0.018: plate *= 0.22
                    color = color*(shade*plate)
                else:
                    color = color*shade
                self.depth[index] = Float32(1/z)
                self.pixels[index] = rgb(color.x, color.y, color.z)
