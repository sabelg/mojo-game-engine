"""Repeatable dense scenes and paced travel/teleport/save soaks, with stage metrics."""
from std.sys import argv
from std.ffi import external_call
from mojo_game import Graphics3D,Mesh,Mat4,Transform3D,Vec3,Material,WorldStreamer,TerrainConfig,WorldPartition,WorldEditor,SceneNode,StreamScheduler
from mojo_game import DirectionalShadows3D,Environment3D

def start_shadows(device: Graphics3D,mut shadows: DirectionalShadows3D,projection: Mat4,origin: Vec3,count: Int,legacy: Mat4) raises -> Mat4:
    if count==0:
        device.shadow_begin(legacy)
        device.camera_origin(Vec3(0,22,16))
        return legacy
    var eye=Vec3(0,22,16)
    var forward=(Vec3(0,0,-35)-eye).unit()
    shadows.prepare(projection,.1,200,Vec3(.4,.8,.3).unit(),forward,eye,origin)
    device.shadow_cascades(shadows.matrices,shadows.splits,forward,eye)
    return shadows.cull_matrix

def rss_kib() raises -> Int:
    with open("/proc/self/status","r") as file:
        var lines=file.read().split("\n")
        for line in lines:
            if line.startswith("VmRSS:"):return Int(String(String(line).split()[1]))
    return -1

def main() raises:
    var args=argv()
    var streaming=False
    var instanced=False
    var soak=False
    var visible=False
    var frames=0
    var warmup=10
    var seconds=Float64(0)
    var pacing=0
    var width=1280
    var height=720
    var shadow_quality=0
    var hdr=False
    var i=1
    while i<len(args):
        var arg=args[i]
        if arg=="--instanced":instanced=True
        elif arg=="--hdr":hdr=True
        elif arg=="--streaming":streaming=True
        elif arg=="--windowed":visible=True
        elif arg=="--soak":
            soak=True
            streaming=True
        elif arg=="--frames":
            i+=1
            frames=Int(args[i])
        elif arg=="--seconds":
            i+=1
            seconds=Float64(args[i])
        elif arg=="--pacing-ms":
            i+=1
            pacing=Int(args[i])
        elif arg=="--warmup":
            i+=1
            warmup=Int(args[i])
        elif arg=="--shadow-cascades":
            i+=1
            shadow_quality=Int(args[i])
        elif arg=="--1080p":
            width=1920
            height=1080
        else:raise Error("Unknown benchmark option")
        i+=1
    if frames==0:frames=1000000000 if seconds>0 else (610 if streaming else 100)
    if frames<=warmup or warmup<0 or seconds<0 or pacing<0:raise Error("Invalid benchmark duration")
    if shadow_quality!=0 and shadow_quality!=2 and shadow_quality!=4:raise Error("Shadow cascades must be 0, 2 or 4")
    var shadows=DirectionalShadows3D(count=2 if shadow_quality==2 else 4,distance=200)
    var device=Graphics3D("Atlas benchmark",width,height,not visible)
    device.hdr(hdr)
    if hdr:device.environment(Environment3D.hemisphere(Vec3(.22,.29,.36),Vec3(.08,.09,.12)))
    var terrain=TerrainConfig(radius=4,resolution=32,chunks_per_update=4)
    var scheduler=StreamScheduler(workers=4)
    var stream=WorldStreamer(terrain,asynchronous=True,scheduler=scheduler.copy())
    var directory=String("build/atlas-soak-world-")+String(external_call["SDL_GetPerformanceCounter",UInt64]())
    var world=WorldPartition(directory,radius=1,asynchronous=True,scheduler=scheduler.copy())
    var editor=WorldEditor()
    if soak:
        if external_call["mkdir",Int32](directory.as_c_string_span(),Int(493))!=0:raise Error("Cannot create soak world")
        editor.place(world,SceneNode("soak",Transform3D(Vec3(0,0,0))))
    var mesh=Mesh.cube()
    var handle=device.upload(mesh)
    var transforms=List[Mat4]()
    for z in range(32):
        for x in range(32):transforms.append(Transform3D(Vec3(Float64(x-16)*2,0,-Float64(z)*2-8)).matrix())
    var projection=Mat4.perspective(1.04719755,Float64(width)/Float64(height),0.1,200)*Mat4.look_at(Vec3(0,22,16),Vec3(0,0,-35))
    var light=Mat4.orthographic(90,0.1,300)*Mat4.look_at(Vec3(50,90,40),Vec3(0,0,-35))
    print("device\t"+device.driver())
    print("shadows\t"+String(shadow_quality)+"\t200\t"+String(4096 if shadow_quality==0 else 2048))
    print("color_pipeline\t"+String("hdr-sh" if hdr else "legacy"))
    print("config\t"+String(width)+"\t"+String(height)+"\t"+String(warmup)+"\t"+String(frames)+"\t"+String(seconds)+"\t"+String(pacing))
    print("columns\thost_ms\tgpu_ms\tdraws\ttriangles\tstream_ms\tsubmit_ms\trender_ms\tacquire_ms\tblit_ms\tpresent_ms\tframe_wait_ms\tqueue_depth\treserved_bytes\tallocated_bytes\tpool_pages\tupload_wait_ms\tupload_batches\tupload_bytes\trender_id\tgpu_render_id\tframe_banks")
    var frequency=external_call["SDL_GetPerformanceFrequency",UInt64]()
    var started=external_call["SDL_GetPerformanceCounter",UInt64]()
    var measured=0
    var memory_peak=0
    for frame in range(frames):
        var began=external_call["SDL_GetPerformanceCounter",UInt64]()
        var upload_wait=device.upload_stat(0)
        var upload_batches=device.upload_stat(1)
        var upload_bytes=device.upload_stat(3)
        var stream_ms=Float64(0)
        if visible:
            device.poll()
            if not device.running:break
        if streaming:
            var x=Float64(frame)*2+(1000000000.0 if frame>=300 else 0.0)
            if soak:x=Float64(frame%1200)*2+(1000000000.0 if (frame//1200)%2 else 0.0)
            var origin=Vec3(x,terrain.height(x,0)+25,0)
            stream.update(device,origin)
            if soak:
                if frame%120==0:
                    editor.place(world,SceneNode("revision",Transform3D(Vec3(Float64(frame%1200),0,0))))
                    editor.delete(world)
                    # Exercise authoring/save I/O without retaining command snapshots forever.
                    editor.undo_stack.clear()
                    editor.redo_stack.clear()
                    editor.selected=-1
                    for cell in range(len(world.cells)):
                        _=world.cells[cell].scene.compact()
                        world.mark_dirty(world.cells[cell].x,world.cells[cell].z)
                world.update(origin)
                if frame%120==0:
                    for cell in world.cells:world.request_save(cell.x,cell.z)
            stream_ms=Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-began)*1000/Float64(frequency)
            var cull=start_shadows(device,shadows,projection,origin,shadow_quality,light)
            stream.draw(device,origin,True,cull,True)
            device.begin(projection)
            stream.draw(device,origin,False,projection,True)
        else:
            _=start_shadows(device,shadows,projection,Vec3(0,0,0),shadow_quality,light)
            if instanced:device.draw_instances(handle,transforms,shadow=True)
            else:
                for model in transforms:device.shadow(handle,model)
            device.begin(projection)
            if instanced:device.draw_instances(handle,transforms)
            else:
                for model in transforms:device.draw(handle,model,Material())
        var submitted=external_call["SDL_GetPerformanceCounter",UInt64]()
        if warmup>0 and frame==warmup-1:device.snapshot("build/atlas-benchmark-scene.bmp")
        device.present()
        var elapsed=Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-began)*1000/Float64(frequency)
        if frame>=warmup:
            measured+=1
            var gpu=external_call["mg_stage_ms",Float64](device.handle.value(),Int32(4))
            var stats=stream.queue.stats()
            var row=String("frame\t")+String(elapsed)+"\t"+String(gpu)+"\t"+String(device.draws())+"\t"+String(device.triangles())+"\t"+String(stream_ms)+"\t"+String(Float64(submitted-began)*1000/Float64(frequency)-stream_ms)
            for stage in range(4):row+="\t"+String(external_call["mg_stage_ms",Float64](device.handle.value(),Int32(stage)))
            row+="\t"+String(external_call["mg_detail_ms",Float64](device.handle.value(),Int32(0)))+"\t"+String(stats.queued+stats.ready+stats.busy)+"\t"+String(stats.reserved_bytes)+"\t"+String(device.allocated_bytes())+"\t"+String(device.pool_pages())
            row+="\t"+String(device.upload_stat(0)-upload_wait)+"\t"+String(device.upload_stat(1)-upload_batches)+"\t"+String(device.upload_stat(3)-upload_bytes)
            row+="\t"+String(device.frame_stat(1))+"\t"+String(device.frame_stat(2))+"\t"+String(device.frame_stat(0))
            print(row)
            if frame%120==0:
                var rss=rss_kib()
                memory_peak=max(memory_peak,rss)
                print("memory\t"+String(frame)+"\t"+String(rss)+"\t"+String(device.allocated_bytes()))
        if pacing>0:external_call["SDL_Delay",NoneType](UInt32(pacing))
        if seconds>0 and Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-started)/Float64(frequency)>=seconds:break
    if streaming:
        print("streaming\t"+String(stream.uploads)+"\t"+String(stream.evictions)+"\t"+String(len(stream.chunks))+"\t"+String(stream.queue.peak_bytes())+"\t"+String(device.allocated_bytes()))
        stream.clear(device)
        var stats=stream.queue.stats()
        if stats.queued+stats.ready+stats.busy!=0:raise Error("Worker retained jobs after close")
        print("jobs\t"+String(stats.accepted)+"\t"+String(stats.rejected)+"\t"+String(stats.completed)+"\t"+String(stats.cancelled)+"\t"+String(stats.errors)+"\t"+String(stats.work_ms))
    if soak:
        world.save()
        print("saves\t"+String(world.store.commits)+"\t"+String(world.store.recoveries))
    print("measured\t"+String(measured)+"\t"+String(Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-started)/Float64(frequency))+"\t"+String(memory_peak))
    print("validation\t"+String(device.validation_errors()))
    device.release(handle)
