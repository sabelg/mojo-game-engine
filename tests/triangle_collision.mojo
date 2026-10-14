"""Imported static geometry: true triangle contact, high-speed sweeps and BVH."""
from std.ffi import external_call
from std.testing import assert_true,assert_equal,assert_raises
from mojo_game import Vec3,Mat4,Mesh,Transform3D,TriangleMesh3D,CollisionWorld3D,CharacterController3D,Bounds3D,CollisionStreamer3D,WorldPartition,WorldCell,Scene3D,SceneNode,Assets3D
from mojo_game.triangle3d import Triangle3D,triangle_capsule

def floor_mesh() -> Mesh:
    var mesh=Mesh()
    mesh.triangle(Vec3(-10,0,-10),Vec3(10,0,10),Vec3(10,0,-10))
    mesh.triangle(Vec3(-10,0,-10),Vec3(-10,0,10),Vec3(10,0,10))
    return mesh^
def main() raises:
    var world=CollisionWorld3D()
    var floor=world.add_mesh(floor_mesh())
    var wall=Mesh()
    wall.triangle(Vec3(2,0,-10),Vec3(2,10,10),Vec3(2,10,-10))
    wall.triangle(Vec3(2,0,-10),Vec3(2,0,10),Vec3(2,10,10))
    _=world.add_mesh(wall)
    var player=CharacterController3D()
    player.step(world,Vec3(0,0,0),.01)
    assert_true(player.grounded)
    player.step(world,Vec3(1000,0,0),.1)
    assert_true(player.position.x<1.66)
    assert_true(player.grounded)
    var before=player.position
    world.move(floor,Vec3(.2,.1,0))
    player.step(world,Vec3(0,0,0),.01)
    assert_true(player.position.x>=before.x)
    assert_true(abs(player.position.y-.1)<.001)
    var sphere=Mesh.sphere(64,32)
    var bvh=TriangleMesh3D(sphere)
    assert_true(len(bvh.nodes)>1)
    var candidates=bvh.query(Bounds3D(Vec3(-.1,.9,-.1),Vec3(.1,1.1,.1)))
    assert_true(len(candidates)>0 and len(candidates)<len(bvh.triangles)//10)
    assert_true(abs(bvh.ray(Vec3(0,3,0),Vec3(0,-1,0))-2)<1e-6)
    var cooked=TriangleMesh3D.load("build/atlas-cook-test/cooked/fixture-node-1-primitive-0.atlascollisionb")
    assert_true(abs(cooked.ray(Vec3(.25,.25,3),Vec3(0,0,-1))-3)<1e-6)
    for name in ["order","bounds","cycle","uncovered","trailing"]:
        with assert_raises():_=TriangleMesh3D.load("build/atlas-cook-test/bad-collision/"+name+".atlascollisionb")
    with assert_raises():_=TriangleMesh3D.load("build/atlas-cook-test/cooked/fixture-node-1-primitive-0.atlascollisionb",payload_budget=1)
    var far=TriangleMesh3D(floor_mesh(),Transform3D(Vec3(1000000000,0,1000000000)).matrix())
    assert_true(abs(far.ray(Vec3(1000000000,3,1000000000),Vec3(0,-1,0))-3)<1e-6)
    var ramp=Mesh()
    ramp.triangle(Vec3(-5,0,-5),Vec3(5,2,5),Vec3(5,2,-5))
    ramp.triangle(Vec3(-5,0,-5),Vec3(-5,0,5),Vec3(5,2,5))
    var slope=CollisionWorld3D()
    _=slope.add_mesh(ramp)
    var walker=CharacterController3D(Vec3(-3,.4,0))
    for _ in range(120):walker.step(slope,Vec3(1,0,0),.025)
    assert_true(walker.position.x>-.2 and walker.position.y>.97 and walker.grounded)
    world.remove_mesh(floor)
    assert_true(not world.support_exists(floor))
    with assert_raises():world.remove_mesh(floor)
    var old=floor
    var replaced=world.add_mesh(floor_mesh())
    assert_true(replaced!=old)
    assert_true(not world.support_exists(old))
    var assets=Assets3D()
    assets.keys.append("fixture/node/mesh/primitive/0")
    assets.handles.append(0)
    assets.index[assets.keys[0]]=0
    assets.collision_paths[assets.keys[0]]="build/atlas-cook-test/cooked/fixture-node-1-primitive-0.atlascollisionb"
    var scene=Scene3D()
    _=scene.add(SceneNode("imported",asset_key=assets.keys[0]))
    var partition=WorldPartition("build")
    partition.cells.append(WorldCell(0,0,scene^))
    var streaming=CollisionStreamer3D()
    var streamed=CollisionWorld3D()
    for i in range(100):
        partition.cells[0].scene.nodes[0].transform.position.x=Float64(i)
        partition.mark_dirty(0,0)
        assert_true(not streaming.ready(partition,assets,0,0))
        streaming.update(partition,assets,streamed)
        assert_true(streaming.ready(partition,assets,0,0))
        assert_true(streaming.resident_bytes(streamed)<=streaming.byte_budget)
    assert_true(len(streamed.meshes)<=2)
    assets.revision+=1
    assert_true(not streaming.ready(partition,assets,0,0))
    streaming.update(partition,assets,streamed)
    assert_true(streaming.ready(partition,assets,0,0))
    partition.cells.clear()
    streaming.update(partition,assets,streamed)
    assert_equal(streaming.resident_bytes(streamed),0)
    for collider in streamed.meshes:assert_equal(len(collider.triangles),0)
    var async_scene=Scene3D()
    _=async_scene.add(SceneNode("worker imported",asset_key=assets.keys[0]))
    partition.cells.append(WorldCell(0,0,async_scene^))
    var worker=CollisionStreamer3D(asynchronous=True)
    for generation in range(10):
        partition.cells[0].scene.nodes[0].transform.position.x=Float64(generation)
        partition.mark_dirty(0,0)
        for _ in range(2000):
            worker.update(partition,assets,streamed)
            if worker.ready(partition,assets,0,0):break
            external_call["SDL_Delay",NoneType](UInt32(1))
        assert_true(worker.ready(partition,assets,0,0))
        assert_true(worker.queue.peak_bytes()<=64*1024*1024)
    var retained=worker.cells[0].handles[0]
    assets.collision_paths[assets.keys[0]]="build/atlas-cook-test/bad-collision/bounds.atlascollisionb"
    assets.revision+=1
    var rejected=False
    for _ in range(2000):
        try:worker.update(partition,assets,streamed)
        except:
            rejected=True
            break
        external_call["SDL_Delay",NoneType](UInt32(1))
    assert_true(rejected)
    assert_true(streamed.support_exists(retained))
    worker.clear(streamed)
    print("Triangle collision passed: thin walls, ramps, moving support, spatial BVH and billion-unit rays")
