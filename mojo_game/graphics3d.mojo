"""Owning Vulkan device. All methods must run on its creating thread."""
from std.ffi import external_call
from std.math import floor,isfinite
from . import sdl
from .mesh import Mesh
from .math3d import Vec3
from .transform3d import Mat4, gpu_matrix
from .scene3d import Material
from .font import glyph
from .environment3d import Environment3D
from .input import Input
from .local_lighting3d import LocalLight3D

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

    def shadow_cascades(self,matrices: List[Mat4],splits: List[Float64],forward: Vec3,camera_offset: Vec3=Vec3(0,0,0)) raises:
        """Begin 2/4 cascades in a 4096-square atlas; matrices use draw origin.

        Splits are increasing camera-forward distances. Submit shadow casters
        covering all cascade volumes; begin() and lighting follow as usual.
        shadow_begin() restores the single-map comparison path.
        """
        if (len(matrices)!=2 and len(matrices)!=4) or len(splits)!=len(matrices):raise Error("Directional shadows need two or four matrices and splits")
        var data=List[Float32]()
        var ranges=List[Float32]()
        for matrix in matrices:
            _=matrix.inverse()
            for value in matrix.data:data.append(Float32(value))
        for split in splits:ranges.append(Float32(split))
        check_graphics(external_call["mg_shadow_cascades",Int32](self.handle.value(),data.unsafe_ptr(),ranges.unsafe_ptr(),Int32(len(matrices)),Float32(forward.x),Float32(forward.y),Float32(forward.z),Float32(camera_offset.x),Float32(camera_offset.y),Float32(camera_offset.z)))

    def hdr(self,enabled: Bool=True) raises:
        """Use linear FP16 scene/water, final exposure/filmic/sRGB display, then UI.

        Changing modes recreates targets on the next frame and waits for the GPU.
        Legacy mode remains the default and allocates no HDR target images.
        """
        check_graphics(external_call["mg_hdr",Int32](self.handle.value(),Int32(enabled)))

    def environment(self,environment: Environment3D,enabled: Bool=True) raises:
        """Persistent low-frequency distant lighting; diffuse SH and broad specular.

        Linear radiance replaces hemisphere ambient. Disable for legacy lighting.
        Sharp mirror environment maps require a separate higher-frequency path.
        """
        if len(environment.coefficients)!=9:raise Error("Environment needs nine RGB coefficients")
        var data=List[Float32]()
        for value in environment.coefficients:
            data.append(Float32(value.x));data.append(Float32(value.y));data.append(Float32(value.z))
        check_graphics(external_call["mg_environment",Int32](self.handle.value(),data.unsafe_ptr(),Int32(enabled)))

    def camera_origin(self,offset: Vec3) raises:
        """HDR view/reflection/fog origin relative to the draw origin.

        Call after shadow_begin when the draw origin differs from the eye.
        shadow_cascades supplies this offset; shadow_begin resets it to zero.
        """
        check_graphics(external_call["mg_camera_origin",Int32](self.handle.value(),Float32(offset.x),Float32(offset.y),Float32(offset.z)))

    def shadow_debug(self,enabled: Bool=True):
        """Display atlas depth on submitted color geometry; begin a shadow frame first."""
        external_call["mg_shadow_debug",NoneType](self.handle.value(),Int32(enabled))

    def poll(mut self, preserve_edges: Bool = False, quit_on_escape: Bool = True):
        var now = sdl.ticks()
        self.input.begin(min(0.1, Float64(now-self.last_tick)/1000),preserve_edges)
        self.last_tick = now
        var event = sdl.Event()
        while event.poll():
            var kind = event.kind()
            if kind == sdl.QUIT: self.running = False
            elif kind == sdl.KEYDOWN or kind == sdl.KEYUP:
                self.input.key(event.scancode(), kind == sdl.KEYDOWN, event.repeat())
            elif kind==0x303:
                var text=event.text()
                if self.input.text.byte_length()+text.byte_length()<=4096:self.input.text+=text
            elif kind==0x403:self.input.mouse_wheel+=event.wheel()
            elif kind==sdl.WINDOW_FOCUS_LOST:self.input.lose_focus()
            elif kind==sdl.WINDOW_CLOSE_REQUESTED:self.running=False
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
        if len(mesh.colors)>0 or len(mesh.tangents)>0:
            try:self.mesh_attributes(Int(result),mesh)
            except error:
                self.release(Int(result))
                raise error^
        return Int(result)

    def mesh_attributes(self,handle: Int,mesh: Mesh) raises:
        mesh.validate()
        var colors=mesh.colors.unsafe_ptr()
        var tangents=mesh.tangents.unsafe_ptr()
        var result=external_call["mg_mesh_attributes",Int32](self.handle.value(),Int32(handle),UInt64(Int(colors)) if len(mesh.colors)>0 else UInt64(0),UInt64(Int(tangents)) if len(mesh.tangents)>0 else UInt64(0),Int32(len(mesh.vertices)//2))
        _=colors
        _=tangents
        check_graphics(result)

    def update_mesh(self,handle: Int,mesh: Mesh) raises:
        """Replace vertex data without reallocating a mesh or changing topology."""
        mesh.validate()
        check_graphics(external_call["mg_update_mesh",Int32](self.handle.value(),Int32(handle),mesh.vertices.unsafe_ptr(),Int32(len(mesh.vertices)),mesh.indices.unsafe_ptr(),Int32(len(mesh.indices))))
        self.mesh_attributes(handle,mesh)

    def draw_instances(self,mesh: Int,matrices: List[Mat4],material: Material=Material(),origin: Vec3=Vec3(0,0,0),shadow: Bool=False) raises:
        if len(matrices)==0:return
        if len(matrices)>65535:raise Error("Instance batch exceeds 65535 matrices")
        var data=List[Float32](capacity=len(matrices)*16)
        for matrix in matrices:
            var values=gpu_matrix(matrix,origin)
            for value in values:data.append(value)
        check_graphics(external_call["mg_draw_instances",Int32](self.handle.value(),Int32(mesh),data.unsafe_ptr(),Int32(len(matrices)),Float32(material.color.x),Float32(material.color.y),Float32(material.color.z),Float32(material.roughness),Float32(material.metallic),Float32(material.emission),Int32(material.texture),Int32(shadow)))

    def draw_lod_instances(self,mesh: Int,matrices: List[Mat4],threshold: Float64,far: Bool=False,material: Material=Material(),origin: Vec3=Vec3(0,0,0),shadow: Bool=False) raises:
        """Complementary static LOD coverage; use one threshold for both meshes.

        Near keeps 1-threshold, far keeps threshold. Compatible with vertex
        colors/tangents, foliage/wind and alpha masks; not skeletal/morph draws.
        The pattern is screen-pixel based and has no temporal accumulation.
        """
        if not isfinite(threshold) or threshold<0 or threshold>1:raise Error("LOD threshold must be in 0..1")
        if len(matrices)==0:return
        if len(matrices)>65535:raise Error("Instance batch exceeds 65535 matrices")
        var data=List[Float32](capacity=len(matrices)*16)
        for matrix in matrices:
            var values=gpu_matrix(matrix,origin)
            for value in values:data.append(value)
        check_graphics(external_call["mg_draw_lod_instances",Int32](self.handle.value(),Int32(mesh),data.unsafe_ptr(),Int32(len(matrices)),Float32(material.color.x),Float32(material.color.y),Float32(material.color.z),Float32(material.roughness),Float32(material.metallic),Float32(material.emission),Int32(material.texture),Int32(shadow),Float32(threshold),Int32(far)))

    def allocated_bytes(self) -> UInt64:
        return external_call["mg_allocated_bytes",UInt64](self.handle.value())

    def pool_pages(self) -> Int:
        return Int(external_call["mg_pool_pages",Int32](self.handle.value()))

    def flush_uploads(self) raises:
        """Submit queued mesh copies; slots remain protected by their fences."""
        check_graphics(external_call["mg_flush_uploads",Int32](self.handle.value()))

    def wait_idle(self) raises:
        """Finish submitted GPU work for explicit teardown/readback boundaries."""
        check_graphics(external_call["mg_wait_idle",Int32](self.handle.value()))

    def upload_stat(self,key: Int) -> Float64:
        """0 wait ms; 1 GPU batches; 2 writes; 3 bytes; 4 staging bytes; 5 completed serial."""
        return external_call["mg_upload_stat",Float64](self.handle.value(),Int32(key))

    def frame_stat(self,key: Int) -> UInt64:
        """0 banks, 1 submitted render ID, 2 timed GPU render ID, 3 active bank.

        With two frames, GPU timings refer to the completed bank being reused.
        A zero timed ID means no completed render has been sampled yet.
        """
        return external_call["mg_frame_stat",UInt64](self.handle.value(),Int32(key))

    def gpu_ms(self) -> Float64:
        return external_call["mg_stage_ms",Float64](self.handle.value(),Int32(4))

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

    def texture_releasable(self,texture: Int) raises -> Bool:
        var result=external_call["mg_texture_releasable",Int32](self.handle.value(),Int32(texture))
        check_graphics(result)
        return result!=0

    def release_texture(self,texture: Int) raises:
        """Release a completed texture without active map attachments/queued draws."""
        check_graphics(external_call["mg_release_texture",Int32](self.handle.value(),Int32(texture)))

    def texture_sampling(self,texture: Int,wrap_s: Int=10497,wrap_t: Int=10497,min_filter: Int=9987,mag_filter: Int=9729) raises:
        check_graphics(external_call["mg_texture_sampling",Int32](self.handle.value(),Int32(texture),Int32(wrap_s),Int32(wrap_t),Int32(min_filter),Int32(mag_filter)))

    def texture_alpha(self,texture: Int,mode: Int=1,cutoff: Float64=.5) raises:
        """0 legacy cutout, 1 opaque, 2 mask with an explicit alpha cutoff."""
        check_graphics(external_call["mg_texture_alpha",Int32](self.handle.value(),Int32(texture),Int32(mode),Float32(cutoff)))

    def normal_map(self, albedo: Int, normal: Int) raises:
        check_graphics(external_call["mg_normal_map", Int32](self.handle.value(), Int32(albedo), Int32(normal)))

    def orm_map(self, albedo: Int, packed: Int) raises:
        """Bind linear occlusion/roughness/metallic channels to an albedo."""
        check_graphics(external_call["mg_orm_map", Int32](self.handle.value(), Int32(albedo), Int32(packed)))

    def triplanar(self, albedo: Int, tiles_per_unit: Float64=1) raises:
        """Blend three object-local projections for opaque surfaces; zero restores UVs."""
        check_graphics(external_call["mg_triplanar", Int32](self.handle.value(), Int32(albedo), Float32(tiles_per_unit)))

    def foliage(self, albedo: Int, transmission: Float64=0.6) raises:
        """Two-sided leaf shading with shadowed transmission; zero restores ordinary shading."""
        check_graphics(external_call["mg_foliage", Int32](self.handle.value(), Int32(albedo), Float32(transmission)))

    def slope_tint(self, albedo: Int, enabled: Bool=True) raises:
        """For opaque terrain, apply Material.color on steep slopes and white on level ground."""
        check_graphics(external_call["mg_slope_tint", Int32](self.handle.value(), Int32(albedo), Int32(enabled)))

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

    def draw_skin(self,mesh: Int,palette: List[Float32],matrix: Mat4,material: Material=Material(),origin: Vec3=Vec3(0,0,0),shadow: Bool=False) raises:
        """GPU deformation with copied, bounded frame data from SkinnedMesh.gpu_data.

        Normal/ORM maps work. Triplanar and foliage materials use pose storage
        for other purposes and are rejected on this path.
        """
        var data=gpu_matrix(matrix,origin)
        check_graphics(external_call["mg_draw_skin",Int32](self.handle.value(),Int32(mesh),palette.unsafe_ptr(),Int32(len(palette)),data.unsafe_ptr(),Float32(material.color.x),Float32(material.color.y),Float32(material.color.z),Float32(material.roughness),Float32(material.metallic),Float32(material.emission),Int32(material.texture),Int32(shadow)))

    def can_morph(self, first: Int, next_pose: Int) -> Bool:
        return external_call["mg_can_morph",Int32](self.handle.value(),Int32(first),Int32(next_pose))!=0

    def draw_morph(self, first: Int, next_pose: Int, blend: Float64, matrix: Mat4, material: Material = Material(), origin: Vec3 = Vec3(0,0,0), shadow: Bool=False) raises:
        """Interpolate corresponding mesh vertices in both color and shadow passes."""
        var data=gpu_matrix(matrix,origin)
        check_graphics(external_call["mg_draw_morph",Int32](self.handle.value(),Int32(first),Int32(next_pose),Float32(blend),data.unsafe_ptr(),Float32(material.color.x),Float32(material.color.y),Float32(material.color.z),Float32(material.roughness),Float32(material.metallic),Float32(material.emission),Int32(material.texture),Int32(shadow)))

    def draw_crossfade(self, first: Int, next_pose: Int, target: Int, target_next: Int, blend: Float64, target_blend: Float64, fade: Float64, matrix: Mat4, material: Material = Material(), origin: Vec3 = Vec3(0,0,0), shadow: Bool=False) raises:
        """Blend two interpolated clips with matching vertex/index topology."""
        var data=gpu_matrix(matrix,origin)
        check_graphics(external_call["mg_draw_crossfade",Int32](self.handle.value(),Int32(first),Int32(next_pose),Int32(target),Int32(target_next),Float32(blend),Float32(target_blend),Float32(fade),data.unsafe_ptr(),Float32(material.color.x),Float32(material.color.y),Float32(material.color.z),Float32(material.roughness),Float32(material.metallic),Float32(material.emission),Int32(material.texture),Int32(shadow)))

    def local_lights(self,lights: List[LocalLight3D],origin: Vec3=Vec3(0,0,0)) raises:
        if len(lights)>32:raise Error("Local light count exceeds 32")
        var data=List[Float32]()
        for light in lights:
            var p=light.position-origin
            for value in [p.x,p.y,p.z,light.inner,light.intensity.x,light.intensity.y,light.intensity.z,light.outer,light.direction.x,light.direction.y,light.direction.z,0.0]:
                data.append(Float32(value))
        check_graphics(external_call["mg_local_lights",Int32](self.handle.value(),data.unsafe_ptr(),Int32(len(lights))))

    def lighting(self, upper: Vec3, lower: Vec3, sun: Vec3, haze: Vec3, exposure: Float64=1) raises:
        """Set scene lighting after begin; begin restores the library defaults."""
        var values: List[Float32]=[Float32(upper.x),Float32(upper.y),Float32(upper.z),1,Float32(lower.x),Float32(lower.y),Float32(lower.z),0,Float32(sun.x),Float32(sun.y),Float32(sun.z),Float32(exposure),Float32(haze.x),Float32(haze.y),Float32(haze.z),1]
        check_graphics(external_call["mg_lighting",Int32](self.handle.value(),values.unsafe_ptr()))

    def cinematic(self, camera_height: Float64, mist_height: Float64=0, density: Float64=0.014, falloff: Float64=0.18, strength: Float64=1, vignette: Float64=0.14) raises:
        """World-only height mist, sun haze and grading; begin resets to disabled."""
        check_graphics(external_call["mg_cinematic",Int32](self.handle.value(),Float32(camera_height),Float32(mist_height),Float32(density),Float32(falloff),Float32(strength),Float32(vignette)))

    def wind_material(self, albedo: Int, enabled: Bool=True) raises:
        """Opt a foliage material into object-local wind in both vertex passes."""
        check_graphics(external_call["mg_wind_material",Int32](self.handle.value(),Int32(albedo),Int32(enabled)))

    def wind(self, seconds: Float64, amplitude: Float64=0.12) raises:
        """Set after shadow_begin; next shadow_begin resets to still air. Max 0.25m."""
        var period: Float64=8.975979010256552
        var phase=(seconds-floor(seconds/period)*period)*0.7
        check_graphics(external_call["mg_wind",Int32](self.handle.value(),phase,Float32(amplitude)))

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

    def text_input(self,enabled: Bool=True) raises:
        check_graphics(external_call["mg_text_input",Int32](self.handle.value(),Int32(enabled)))
