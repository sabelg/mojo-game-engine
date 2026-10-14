from std.ffi import external_call
from std.testing import assert_equal,assert_true
from mojo_game import Graphics3D,Mesh,Mat4,Vec3,Vec2,Material,Transform3D,AuthoredCamera3D,Assets3D,Scene3D,PreviewPlayback,AuthoredCameraTrack3D
from mojo_game.durableio import read_bounded

def main() raises:
    var actual=AuthoredCamera3D.load("build/usd-m03-render-actual.atlascameras")
    var expected=AuthoredCamera3D.load("build/usd-m03-render-expected.atlascameras")
    assert_equal(len(actual),4)
    var device=Graphics3D("M03 authored lens regression",360,240,True)
    var cube=device.upload(Mesh.cube())
    for i in range(4):
        for mode in range(2):
            var camera=actual[i].copy() if mode==0 else expected[i].copy()
            for _ in range(3):
                device.shadow_begin(Mat4())
                device.begin(camera.view_projection(),fog=0)
                device.draw(cube,Transform3D(scale=Vec3(.8,.8,.8)).matrix(),Material(Vec3(.6,.3,.1)))
                device.snapshot("build/usd-m03-render-"+String(i)+"-"+String(mode)+".bmp")
            assert_equal(device.validation_errors(),0)
    var tracks=AuthoredCameraTrack3D.load("build/usd-fractional-camera.atlascameratracks")
    assert_true(abs(tracks[0].sample(1.25/24).projection.data[0]-130.0/36)<1e-5)
    assert_true(abs(tracks[0].sample(3.5/24).projection.data[0]-110.0/36)<1e-5)
    var prefix=String("build/usd-fractional-cooked/preview")
    var assets=Assets3D()
    assets.load_manifest(device,prefix+"-assets.atlasb")
    var scene=Scene3D.load(prefix+"-scene.sceneb")
    var player=PreviewPlayback.load(prefix,scene,assets)
    assert_equal(len(player.skins),1)
    assert_equal(len(player.weights),1)
    assert_true(abs(player.duration-5.0/24)<1e-6)
    var asset=player.skin_assets[0]
    var mesh_node = -1
    for i in range(len(scene.nodes)):
        if scene.valid(i) and assets.node_mesh(scene,i)==asset:mesh_node=i
    assert_true(mesh_node>=0)
    var rows=read_bounded("build/usd-fractional-reference.tsv",16384).split("\n")
    assert_equal(String(rows[0]),"ATLAS_USD_FRACTIONAL_POSE_1")
    var view=Mat4.perspective(1,1.5,.1,100)*Mat4.look_at(Vec3(2,1,8),Vec3(2,.5,0))
    for i in range(1,len(rows)):
        var fields=String(rows[i]).split("\t")
        if len(fields)==1:continue
        assert_equal(len(fields),18)
        var time=Float64(String(fields[0]))
        var matrix=Mat4()
        for j in range(16):matrix.data[j]=Float64(String(fields[j+1]))
        var weight=Float64(String(fields[17]))
        var overrides=player.apply(device,assets,time)
        var model=scene.world_matrix(mesh_node,overrides)
        var source=player.skins[0].mesh.copy()
        var reference=Mesh()
        for vertex in range(len(source.vertices)//8):
            var at=vertex*8
            var point=matrix.point(Vec3(Float64(source.vertices[at]),.5*weight,Float64(source.vertices[at+2])))
            var normal=matrix.normal(Vec3(0,-1,0)).unit()
            _=reference.vertex(point,normal,Vec2(Float64(source.vertices[at+6]),Float64(source.vertices[at+7])))
        reference.indices=source.indices.copy()
        var skin_pose=player.clip.sample(player.skeletons[0],time,False)
        var deformed=player.skins[0].deform(player.skeletons[0],skin_pose)
        for vertex in range(len(deformed.vertices)//8):
            var at=vertex*8
            var point=model.point(Vec3(Float64(deformed.vertices[at]),Float64(deformed.vertices[at+1]),Float64(deformed.vertices[at+2])))
            var expected=Vec3(Float64(reference.vertices[at]),Float64(reference.vertices[at+1]),Float64(reference.vertices[at+2]))
            assert_true((point-expected).length()<.0002)
        var center=matrix.point(Vec3(.33,.5*weight,.33))
        var facing=matrix.normal(Vec3(0,-1,0)).unit()
        view=Mat4.perspective(1,1.5,.1,100)*Mat4.look_at(center+facing*4+Vec3(0,0,5),center)
        var handle=device.upload(reference)
        for mode in range(2):
            for _ in range(3):
                device.shadow_begin(Mat4())
                device.begin(view,fog=0)
                device.draw(assets.handles[asset] if mode==0 else handle,model if mode==0 else Mat4(),Material(Vec3(.6,.3,.1)))
                device.snapshot("build/usd-m03-skin-"+String(i-1)+"-"+String(mode)+".bmp")
            assert_equal(device.validation_errors(),0)
        device.release(handle)
    assets.close(device)
    var large_prefix=String("build/usd-m03-workload/accepted/preview")
    var large_assets=Assets3D()
    large_assets.load_manifest(device,large_prefix+"-assets.atlasb")
    var large_scene=Scene3D.load(large_prefix+"-scene.sceneb")
    var large_player=PreviewPlayback.load(large_prefix,large_scene,large_assets)
    assert_equal(len(large_player.skins),1)
    assert_true(32<=len(large_player.skeletons[0].joints)<=64)
    assert_true(len(large_player.skins[0].mesh.vertices)//8>=10000)
    assert_equal(len(large_player.skins[0].mesh.morphs),2)
    var large_asset=large_player.skin_assets[0]
    var large_node = -1
    for i in range(len(large_scene.nodes)):
        if large_scene.valid(i) and large_assets.node_mesh(large_scene,i)==large_asset:large_node=i
    assert_true(large_node>=0)
    var counter=external_call["SDL_GetPerformanceCounter",UInt64]()
    var frequency=external_call["SDL_GetPerformanceFrequency",UInt64]()
    var first=large_assets.bounds[large_asset].copy()
    for sample in range(4):
        var seconds=Float64(sample)/3 if sample<3 else 0.0
        var overrides=large_player.apply(device,large_assets,seconds)
        if sample==0:first=large_assets.bounds[large_asset].copy()
        if sample==2:assert_true((large_assets.bounds[large_asset].minimum-first.minimum).length()>.01)
        if sample==3:assert_true((large_assets.bounds[large_asset].minimum-first.minimum).length()<1e-6)
        var model=large_scene.world_matrix(large_node,overrides)
        var large_view=Mat4.perspective(1,1.5,.1,100)*Mat4.look_at(Vec3(3,-5,7),Vec3(0,0,0))
        for _ in range(3):
            device.shadow_begin(Mat4())
            device.begin(large_view,fog=0)
            device.draw(large_assets.handles[large_asset],model,Material(Vec3(.6,.3,.1)))
            device.snapshot("build/usd-m03-workload-"+String(sample)+".bmp")
    var elapsed=Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-counter)/Float64(frequency)
    assert_true(elapsed<15)
    large_assets.close(device)
    assert_equal(device.validation_errors(),0)
    print("M03 representative upload/deform/draw/capture seconds",elapsed)
    print("M03 authored animation rendering passed: four lens samples and seven fractional skin/morph poses against independent USD references")
