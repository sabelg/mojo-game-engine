"""View a cooked USD scene with authored camera and light animation.

Run after cooking a source containing at least one camera. Arguments:
  --prefix /path/to/cooked/asset-id [--camera 0] [--smoke]
The viewport follows the camera aperture aspect. This sample does not evaluate
skeletal clips, area lights or arbitrary MaterialX graphs.
"""
from std.sys import argv
from mojo_game import Graphics3D,Assets3D,Scene3D,Vec3,Mat4,AuthoredCamera3D,AuthoredLighting3D,AuthoredCameraTrack3D,AuthoredLightTrack3D,LocalLight3D,VisibilityTrack
from mojo_game.durableio import exists

def main() raises:
    var args=argv()
    var prefix=String("build/usd-camera-cooked/camera")
    var camera_index=0
    var smoke=False
    for i in range(1,len(args)):
        if args[i]=="--prefix" and i+1<len(args):prefix=String(args[i+1])
        elif args[i]=="--camera" and i+1<len(args):camera_index=Int(String(args[i+1]))
        elif args[i]=="--smoke":smoke=True
    var cameras=AuthoredCamera3D.load(prefix+"-cameras.atlascameras")
    if camera_index<0 or camera_index>=len(cameras):raise Error("Camera index outside cooked camera collection")
    var camera=cameras[camera_index].copy()
    var aspect=abs(camera.projection.data[5]/camera.projection.data[0])
    var width=960
    var height=Int(Float64(width)/aspect)
    if height<64 or height>4096:raise Error("Camera aspect exceeds viewer dimensions")
    var light=AuthoredLighting3D()
    if exists(prefix+"-lights.atlaslights"):light=AuthoredLighting3D.load(prefix+"-lights.atlaslights")
    var device=Graphics3D("Atlas | USD scene",width,height,smoke)
    var assets=Assets3D()
    assets.load_manifest(device,prefix+"-assets.atlasb")
    var scene=Scene3D.load(prefix+"-scene.sceneb")
    var origin=camera.position()
    var view=camera.view_projection(origin)
    var tracks=List[AuthoredCameraTrack3D]()
    if exists(prefix+"-camera-tracks.atlascameratracks"):
        tracks=AuthoredCameraTrack3D.load(prefix+"-camera-tracks.atlascameratracks")
    var light_tracks=List[AuthoredLightTrack3D]()
    if exists(prefix+"-light-tracks.atlaslighttracks"):
        light_tracks=AuthoredLightTrack3D.load(prefix+"-light-tracks.atlaslighttracks")
    var local_lights=List[LocalLight3D]()
    if exists(prefix+"-local-lights.atlaslocallights"):
        local_lights=LocalLight3D.load(prefix+"-local-lights.atlaslocallights")
    var visibility=List[VisibilityTrack]()
    if exists(prefix+"-visibility.atlasvisibility"):visibility=VisibilityTrack.load(prefix+"-visibility.atlasvisibility")
    var elapsed: Float64=0
    var frame=0
    while device.running:
        device.poll()
        elapsed+=1.0/60 if smoke else device.input.dt
        for track in tracks:
            if track.identity==camera.identity:
                camera=track.sample(elapsed)
                origin=camera.position()
                view=camera.view_projection(origin)
        # This inspection viewer deliberately has no shadow pass geometry.
        device.shadow_begin(Mat4())
        var animated_light=AuthoredLightTrack3D.evaluate(light_tracks,light,elapsed)
        animated_light.begin(device,view,exposure=camera.exposure)
        device.local_lights(local_lights,origin)
        assets.draw(device,scene,origin,view,hidden=VisibilityTrack.hidden(visibility,elapsed))
        if smoke and frame==3:device.snapshot("build/usd-scene.bmp")
        device.present()
        frame+=1
        if smoke and frame==4:break
    if device.validation_errors()!=0:raise Error("USD viewer Vulkan validation failed")
    print("USD viewer passed:",device.driver(),"camera",camera.identity,"frames",frame)
