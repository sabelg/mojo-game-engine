"""Spatial visibility parity, revision invalidation and actual rendered output."""
from mojo_game import Assets3D,SceneDrawCache,Scene3D,SceneNode,Graphics3D,Mesh,Material,Transform3D,Quaternion,Mat4,Vec3,WorldPartition
from std.testing import assert_equal,assert_true,assert_false,assert_raises
from std.ffi import external_call

def same(a: List[Int],b: List[Int]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(a[i],b[i])

def main() raises:
    var device=Graphics3D("Atlas spatial visibility",320,240,True)
    var assets=Assets3D()
    var mesh=assets.add(device,"cube",Mesh.cube())
    var scene=Scene3D()
    # Spatially distant dense content must be rejected by branches rather than
    # testing thousands of individual bounds. Mixed parents exercise evaluation.
    for i in range(4096):
        var position=Vec3(500+Float64(i%64)*3,Float64((i//64)%8)*3,-100-Float64(i//512)*3)
        if i<64:position=Vec3(Float64(i%8-4)*1.5,Float64(i//8-4)*1.5,-16)
        var parent=-1
        if i==20:
            parent=5
            position=Vec3(.2,.1,-.3)
        var material=Material(Vec3(.2+Float64(i%3)*.2,.5,.3),.3,.1)
        scene.nodes.append(SceneNode(String(i),Transform3D(position,Quaternion.axis_angle(Vec3(0,1,0),Float64(i%7)*.1),Vec3(.35,.5,.3)),mesh,material,parent,asset_key="cube",persistent_id="visibility:"+String(i)))
    var cache=SceneDrawCache()
    assets.prepare_scene(scene,cache,0)
    assert_equal(cache.builds,1)
    assert_equal(len(cache.items),4096)
    var projection=Mat4.perspective(1,320.0/240,.1,100)
    var hierarchical=cache.visible(projection)
    var branch_tests=cache.branch_tests
    var item_tests=cache.item_tests
    var linear=cache.visible(projection,hierarchical=False)
    same(hierarchical,linear)
    assert_true(len(linear)>32)
    assert_true(branch_tests+item_tests<4096//4)
    var narrow=Mat4.perspective(.3,320.0/240,.1,100)
    var partial=cache.visible(narrow)
    assert_true(cache.item_tests>0)
    same(partial,cache.visible(narrow,hierarchical=False))
    var light=Mat4.orthographic(30,.1,100)*Mat4.look_at(Vec3(0,0,20),Vec3(0,0,-15))
    same(cache.visible(light),cache.visible(light,hierarchical=False))
    for i in range(12):
        var view=projection*Mat4.look_at(Vec3(Float64(i)*20,4,5),Vec3(Float64(i)*20,0,-50))
        same(cache.visible(view),cache.visible(view,hierarchical=False))
    for mode in range(2):
        device.shadow_begin(light)
        if mode==0:assets.draw(device,scene,Vec3(0,0,0),light,True)
        else:assets.draw_cached(device,scene,cache,0,Vec3(0,0,0),light,True)
        device.begin(projection)
        if mode==0:assets.draw(device,scene,Vec3(0,0,0),projection)
        else:assets.draw_cached(device,scene,cache,0,Vec3(0,0,0),projection)
        assert_true(device.draws()>0)
        device.snapshot("build/atlas-visibility-linear.bmp" if mode==0 else "build/atlas-visibility-hierarchical.bmp")
        device.present()
    assert_equal(cache.builds,1)
    var wide=Mat4.orthographic(1800,.1,1500)*Mat4.look_at(Vec3(350,0,500),Vec3(350,0,-100))
    assert_equal(len(cache.visible(wide)),4096)
    for workload in range(2):
        var view=projection if workload==0 else wide
        for mode in range(2):
            var started=external_call["SDL_GetPerformanceCounter",UInt64]()
            var selected=0
            for _ in range(256):selected+=len(cache.visible(view,hierarchical=mode==1))
            var elapsed=Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-started)/Float64(external_call["SDL_GetPerformanceFrequency",UInt64]())*1000
            print("Visibility query measurement: workload",workload,"hierarchical",mode,"queries 256 selected",selected,"elapsed ms",elapsed)
    scene.nodes[0].transform.position.x=600
    assets.prepare_scene(scene,cache,1)
    assert_equal(cache.builds,2)
    assert_true(cache.items[0].bounds.minimum.x>599)
    assets.replace_mesh(device,"cube",Mesh.sphere(8,8))
    assets.prepare_scene(scene,cache,1)
    assert_equal(cache.builds,3)
    cache.invalidate()
    assets.prepare_scene(scene,cache,1)
    assert_equal(cache.builds,4)
    var far=Vec3(1000000000,0,1000000000)
    var before=cache.visible(projection)
    for i in range(len(scene.nodes)):
        if scene.nodes[i].parent<0:scene.nodes[i].transform.position=scene.nodes[i].transform.position+far
    assets.prepare_scene(scene,cache,2)
    same(before,cache.visible(projection,far))
    same(cache.visible(projection,far),cache.visible(projection,far,False))
    var saved_builds=cache.builds
    scene.nodes[0].asset_key="missing"
    with assert_raises():assets.prepare_scene(scene,cache,3)
    assert_equal(cache.builds,saved_builds)
    scene.nodes[0].asset_key="cube"
    var directory=String("build/atlas-visibility-world-")+String(external_call["SDL_GetPerformanceCounter",UInt64]())
    assert_equal(external_call["mkdir",Int32](directory.as_c_string_span(),Int(493)),0)
    var world=WorldPartition(directory,radius=0)
    var resident=world.ensure(0,0)
    world.cells[resident].scene=scene.copy()
    world.mark_dirty(0,0)
    assets.prepare_scene(world.cells[resident].scene,world.cells[resident].render_cache,world.cells[resident].revision)
    for _ in range(20):world.update(Vec3(1,0,1))
    assert_equal(world.cells[0].render_cache.builds,1)
    assert_equal(len(world.cells[0].render_cache.items),4096)
    world.update(Vec3(257,0,1))
    assert_equal(len(world.cells),1)
    assert_equal(world.cells[0].x,1)
    assert_false(world.cells[0].render_cache.ready)
    world.close()
    assert_equal(device.validation_errors(),0)
    print("Scene visibility passed:",device.driver(),"4096 nodes, stable pass order, edit/reload invalidation, retained cell caches and billion-unit parity; near-view branch/item tests",branch_tests,item_tests)
    assets.close(device)
