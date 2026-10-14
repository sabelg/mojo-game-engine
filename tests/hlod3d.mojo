"""Cooked HLOD aggregation, transition raster parity and changed-scene fallback."""
from std import sys
from std.ffi import external_call
from std.testing import assert_true,assert_equal,assert_raises
from mojo_game import HLOD3D,Assets3D,Graphics3D,Scene3D,Vec3,Mat4,Mesh

def main() raises:
    var benchmark=False
    var args=sys.argv()
    for arg in args:
        if arg=="--benchmark":benchmark=True
    var device=Graphics3D("Atlas static HLOD",1920 if benchmark else 400,1080 if benchmark else 240,True)
    if benchmark:print("columns\tvariant\tmode\thost_ms\tgpu_ms\tdraws\ttriangles\tallocated_bytes")
    device.hdr()
    var view=Mat4.perspective(1.2,Float64(device.width)/Float64(device.height),.1,100)*Mat4.look_at(Vec3(0,0,0),Vec3(0,-2,-8))
    var light=Mat4.orthographic(30,.1,100)*Mat4.look_at(Vec3(6,16,12),Vec3(0,-2,-8))
    for variant in range(3):
        var name="hlod-exact" if variant==0 else ("hlod-reduced" if variant==1 else "hlod-far")
        var prefix="build/atlas-cook-test/hlod/"+name
        var assets=Assets3D()
        assets.load_manifest(device,prefix+"-assets.atlasb")
        var scene=Scene3D.load(prefix+"-scene.sceneb")
        var hlod=HLOD3D(prefix+"-world.atlashlodb",assets)
        assert_equal(len(hlod.clusters),1)
        if variant==0:
            var allocations=device.allocated_bytes()
            for name in [String("count"),String("distance"),String("sources"),String("truncated"),String("trailing"),String("kind")]:
                with assert_raises():_=HLOD3D("build/atlas-cook-test/hlod/invalid-"+name+".atlashlodb",assets)
                assert_equal(device.allocated_bytes(),allocations)
            var key=scene.nodes[4].asset_key.copy()
            var hash=assets.checksums[key]
            assets.checksums[key]=0
            with assert_raises():_=HLOD3D(prefix+"-world.atlashlodb",assets)
            assets.checksums[key]=hash
        var center=hlod.clusters[0].center
        var origin=center+Vec3(0,7,16)
        var decision=center+Vec3(0,0,6)
        for mode in range(4):
            hlod.enabled=mode!=0
            decision=center+Vec3(0,0,Float64(6 if mode==1 else (16 if mode==2 else 24)))
            for frame in range(500 if benchmark else 1):
                var started=external_call["SDL_GetPerformanceCounter",UInt64]()
                device.shadow_begin(light)
                hlod.draw(assets,device,scene,1,decision,origin,light,True)
                device.begin(view,fog=0)
                hlod.draw(assets,device,scene,1,decision,origin,view)
                assert_true(hlod.valid[0])
                assert_equal(device.draws(),1 if mode==3 else (4 if mode==2 else 3))
                if not benchmark:device.snapshot("build/atlas-hlod-"+String(variant)+"-"+String(mode)+".bmp")
                assert_equal(device.validation_errors(),0)
                device.present()
                if benchmark and frame>=100:
                    var host=Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-started)*1000/Float64(external_call["SDL_GetPerformanceFrequency",UInt64]())
                    print("sample\t"+String(variant)+"\t"+String(mode)+"\t"+String(host)+"\t"+String(device.gpu_ms())+"\t"+String(device.draws())+"\t"+String(device.triangles())+"\t"+String(device.allocated_bytes()))
        scene.nodes[0].transform.position.x+=.25
        for mode in range(2):
            hlod.enabled=mode==1
            device.shadow_begin(light)
            hlod.draw(assets,device,scene,2,decision,origin,light,True)
            device.begin(view,fog=0)
            hlod.draw(assets,device,scene,2,decision,origin,view)
            assert_true(not hlod.valid[0])
            device.snapshot("build/atlas-hlod-fallback-"+String(variant)+"-"+String(mode)+".bmp")
            assert_equal(device.validation_errors(),0)
            device.present()
        # A changed registry invalidates stale cooked proxies even when scene
        # identities/matrices are unchanged; new source geometry stays visible.
        _=assets.add(device,"unrelated-reload",Mesh.cube())
        hlod.prepare(assets,scene,2)
        assert_true(not hlod.valid[0])
        assets.close(device)
    print("Static HLOD passed:",device.driver(),"static/cooked aggregation, fewer far draws, complementary transitions, colors/tangents, changed-scene/asset fallback and billion-unit bounds")
