"""Owning Vulkan device. All methods must run on its creating thread."""
from std.ffi import external_call
from . import sdl
from .mesh import Mesh
from .math3d import Vec3
from .transform3d import Mat4, gpu_matrix
from .scene3d import Material
from .font import glyph
from .input import Input

def graphics_error() -> String:
    return String(unsafe_from_utf8_ptr=external_call["mg_error", sdl.Handle]())

def check_graphics(result: Int32) raises:
    if result < 0: raise Error(graphics_error())

struct Graphics3D:
    var handle: sdl.NullableHandle
    var input: Input
    var running: Bool
    var last_tick: UInt64
    var width: Int
    var height: Int

    def __init__(out self, var title: String = "Mojo World", width: Int = 1280, height: Int = 800, hidden: Bool = False, fullscreen: Bool = False) raises:
        self.handle = None
        self.input = Input()
        self.running = True
        self.last_tick = 0
        self.width = width
        self.height = height
        self.handle = external_call["mg_open_mode", sdl.NullableHandle](title.as_c_string_span(), Int32(width), Int32(height), Int32(hidden), Int32(fullscreen))
        if not self.handle: raise Error(graphics_error())
        self.last_tick = sdl.ticks()

    def close(mut self):
        if self.handle:
            external_call["mg_close", NoneType](self.handle.value())
            self.handle = None
        self.running = False

    def __deinit__(deinit self):
        self.close()

    def driver(self) -> String:
        return String(unsafe_from_utf8_ptr=external_call["mg_driver", sdl.Handle](self.handle.value()))

    def poll(mut self, preserve_edges: Bool = False, quit_on_escape: Bool = True):
        var now = sdl.ticks()
        self.input.begin(min(0.1, Float64(now-self.last_tick)/1000),preserve_edges)
        self.last_tick = now
        var event = sdl.Event()
        while event.poll():
            var kind = event.kind()
            if kind == sdl.QUIT: self.running = False
            elif kind == sdl.KEYDOWN or kind == sdl.KEYUP:
                self.input.key(event.scancode(), kind == sdl.KEYDOWN, event.byte(13) != 0)
            elif kind == sdl.WINDOWEVENT and event.byte(12) == 13: self.input.lose_focus()
        var mx = Int32(0)
        var my = Int32(0)
        var buttons = external_call["mg_mouse", UInt32](self.handle.value(),Pointer(to=mx),Pointer(to=my))
        if self.input.focus_lost: buttons = 0
        self.input.mouse_state(Int(mx),Int(my),buttons)
        if quit_on_escape and self.input.pressed(41): self.running = False
        self.width = Int(external_call["mg_width", Int32](self.handle.value()))
        self.height = Int(external_call["mg_height", Int32](self.handle.value()))

    def upload(self, mesh: Mesh) raises -> Int:
        mesh.validate()
        var result = external_call["mg_mesh", Int32](self.handle.value(), mesh.vertices.unsafe_ptr(), Int32(len(mesh.vertices)), mesh.indices.unsafe_ptr(), Int32(len(mesh.indices)))
        check_graphics(result)
        return Int(result)

    def release(self, mesh: Int) raises:
        check_graphics(external_call["mg_release_mesh", Int32](self.handle.value(), Int32(mesh)))

    def texture(self, var path: String) raises -> Int:
        var result = external_call["mg_texture", Int32](self.handle.value(), path.as_c_string_span())
        check_graphics(result)
        return Int(result)

    def normal_texture(self, var path: String) raises -> Int:
        var result = external_call["mg_texture_data", Int32](self.handle.value(), path.as_c_string_span(), Int32(1))
        check_graphics(result)
        return Int(result)

    def normal_map(self, albedo: Int, normal: Int) raises:
        check_graphics(external_call["mg_normal_map", Int32](self.handle.value(), Int32(albedo), Int32(normal)))

    def orm_map(self, albedo: Int, packed: Int) raises:
        """Bind linear occlusion/roughness/metallic channels to an albedo."""
        check_graphics(external_call["mg_orm_map", Int32](self.handle.value(), Int32(albedo), Int32(packed)))

    def shadow_material(self, mesh: Int, matrix: Mat4, texture: Int, origin: Vec3 = Vec3(0,0,0)) raises:
        var data = gpu_matrix(matrix, origin)
        check_graphics(external_call["mg_shadow_material", Int32](self.handle.value(), Int32(mesh), data.unsafe_ptr(), Int32(texture)))

    def shadow_begin(self, light: Mat4):
        var data = gpu_matrix(light)
        external_call["mg_shadow_begin", NoneType](self.handle.value(), data.unsafe_ptr())

    def shadow(self, mesh: Int, matrix: Mat4, origin: Vec3 = Vec3(0, 0, 0)) raises:
        var data = gpu_matrix(matrix, origin)
        check_graphics(external_call["mg_shadow_draw", Int32](self.handle.value(), Int32(mesh), data.unsafe_ptr()))

    def begin(self, view_projection: Mat4, sun: Vec3 = Vec3(0.4, 0.8, 0.3), fog: Float64 = 0.002):
        var data = gpu_matrix(view_projection)
        external_call["mg_begin", NoneType](self.handle.value(), data.unsafe_ptr(), Float32(sun.x), Float32(sun.y), Float32(sun.z), Float32(fog))

    def draw(self, mesh: Int, matrix: Mat4, material: Material = Material(), origin: Vec3 = Vec3(0, 0, 0)) raises:
        var data = gpu_matrix(matrix, origin)
        check_graphics(external_call["mg_draw", Int32](self.handle.value(), Int32(mesh), data.unsafe_ptr(), Float32(material.color.x), Float32(material.color.y), Float32(material.color.z), Float32(material.roughness), Float32(material.metallic), Float32(material.emission), Int32(material.texture)))

    def can_morph(self, first: Int, next_pose: Int) -> Bool:
        return external_call["mg_can_morph",Int32](self.handle.value(),Int32(first),Int32(next_pose))!=0

    def draw_morph(self, first: Int, next_pose: Int, blend: Float64, matrix: Mat4, material: Material = Material(), origin: Vec3 = Vec3(0,0,0), shadow: Bool=False) raises:
        """Interpolate corresponding mesh vertices in both color and shadow passes."""
        var data=gpu_matrix(matrix,origin)
        check_graphics(external_call["mg_draw_morph",Int32](self.handle.value(),Int32(first),Int32(next_pose),Float32(blend),data.unsafe_ptr(),Float32(material.color.x),Float32(material.color.y),Float32(material.color.z),Float32(material.roughness),Float32(material.metallic),Float32(material.emission),Int32(material.texture),Int32(shadow)))

    def lighting(self, upper: Vec3, lower: Vec3, sun: Vec3, haze: Vec3, exposure: Float64=1) raises:
        """Set scene lighting after begin; begin restores the library defaults."""
        var values: List[Float32]=[Float32(upper.x),Float32(upper.y),Float32(upper.z),1,Float32(lower.x),Float32(lower.y),Float32(lower.z),0,Float32(sun.x),Float32(sun.y),Float32(sun.z),Float32(exposure),Float32(haze.x),Float32(haze.y),Float32(haze.z),1]
        check_graphics(external_call["mg_lighting",Int32](self.handle.value(),values.unsafe_ptr()))

    def overlay_scale(self, scale: Float64):
        external_call["mg_ui_scale",NoneType](self.handle.value(),Float32(scale))

    def rect(self, x: Float64, y: Float64, width: Float64, height: Float64, color: Vec3, alpha: Float64 = 1) raises:
        check_graphics(external_call["mg_rect", Int32](self.handle.value(), Float32(x), Float32(y), Float32(width), Float32(height), Float32(color.x), Float32(color.y), Float32(color.z), Float32(alpha)))

    def circle(self,x: Float64,y: Float64,radius: Float64,color: Vec3,alpha: Float64=1) raises:
        check_graphics(external_call["mg_circle",Int32](self.handle.value(),Float32(x),Float32(y),Float32(radius),Float32(color.x),Float32(color.y),Float32(color.z),Float32(alpha)))

    def pill(self,x: Float64,y: Float64,width: Float64,height: Float64,color: Vec3) raises:
        var radius=height*0.5
        self.rect(x+radius,y,max(0.0,width-height),height,color)
        self.circle(x+radius,y+radius,radius,color)
        self.circle(x+width-radius,y+radius,radius,color)

    def text(self, message: String, x: Int, y: Int, color: Vec3 = Vec3(0.8, 0.9, 1), scale: Int = 2) raises:
        var native_message=message.copy()
        var rendered=external_call["mg_text",Int32](self.handle.value(),native_message.as_c_string_span(),Float32(x),Float32(y),Float32(color.x),Float32(color.y),Float32(color.z),Int32(scale))
        check_graphics(rendered)
        if rendered>0:return
        var left = x
        for cp in message.codepoints():
            var bits = glyph(Int(cp))
            for row in range(7):
                for col in range(5):
                    if (bits >> UInt64((6-row)*5+4-col)) & 1:
                        self.rect(Float64(left+col*scale), Float64(y+row*scale), Float64(scale), Float64(scale), color)
            left += 6*scale

    def font(self, texture: Int) raises:
        """Use a 16 by 6 atlas of ASCII 32..127, with smooth alpha glyphs."""
        check_graphics(external_call["mg_font",Int32](self.handle.value(),Int32(texture)))

    def snapshot(self, var path: String) raises:
        check_graphics(external_call["mg_snapshot", Int32](self.handle.value(), path.as_c_string_span()))

    def present(self) raises:
        check_graphics(external_call["mg_present", Int32](self.handle.value()))

    def draws(self) -> Int:
        return Int(external_call["mg_draws", Int32](self.handle.value()))

    def triangles(self) -> Int:
        return Int(external_call["mg_triangles", Int32](self.handle.value()))

    def resize(mut self, width: Int, height: Int) raises:
        check_graphics(external_call["mg_resize",Int32](self.handle.value(),Int32(width),Int32(height)))
        self.width = width
        self.height = height

    def validation_errors(self) -> Int:
        return Int(external_call["mg_validation_errors",Int32](self.handle.value()))

    def fullscreen(mut self, enabled: Bool) raises:
        check_graphics(external_call["mg_fullscreen",Int32](self.handle.value(),Int32(enabled)))
        self.width = Int(external_call["mg_width",Int32](self.handle.value()))
        self.height = Int(external_call["mg_height",Int32](self.handle.value()))

    def is_fullscreen(self) -> Bool:
        return external_call["mg_is_fullscreen",Int32](self.handle.value()) != 0
