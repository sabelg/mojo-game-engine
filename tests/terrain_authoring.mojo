"""Terrain seams, collision-height parity, undo and grouped crash recovery."""
from std.ffi import external_call
from std.testing import assert_equal,assert_true,assert_false,assert_raises
from mojo_game import TerrainConfig,TerrainLayer,WorldPartition,WorldEditor,Vec3,SceneNode,Transform3D,Scene3D,WorldStore,CellSnapshot
from mojo_game.terrainlayer import TERRAIN_CELL

def folder(label: String) raises -> String:
    var path="build/terrain-"+label+"-"+String(external_call["SDL_GetPerformanceCounter",UInt64]())
    if external_call["mkdir",Int32](path.as_c_string_span(),Int(493))!=0:raise Error("Cannot create terrain fixture")
    return path^

def main() raises:
    var world=WorldPartition(folder("undo"),cell_size=64)
    var editor=WorldEditor()
    editor.sculpt(world,Vec3(64,0,32),8,4)
    editor.paint(world,Vec3(64,0,32),8,Vec3(.8,.3,.1))
    assert_equal(world.terrain.sample(64,32).height,Float64(4))
    assert_equal(world.terrain.sample(64,32).color.x,Float64(.8))
    var config=TerrainConfig(resolution=32)
    var base=config.height(64,32)
    config.layer=world.terrain.copy()
    assert_true(abs(config.height(64,32)-base-4)<1e-12)
    var left=config.mesh(0,0,0)
    var right=config.mesh(1,0,1)
    var li=(16*33+32)*8
    var ri=(8*17)*8
    for channel in range(1,6):assert_equal(left.vertices[li+channel],right.vertices[ri+channel])
    for channel in range(4):assert_equal(left.colors[(16*33+32)*4+channel],right.colors[8*17*4+channel])
    assert_true(config.layer.has_paint)
    editor.undo(world)
    assert_false(world.terrain.has_paint)
    editor.undo(world)
    assert_equal(len(world.terrain.samples),0)
    editor.redo(world)
    editor.redo(world)
    var directory=world.directory.copy()
    world.close()
    var reopened=WorldPartition(directory)
    reopened.prepare()
    assert_equal(reopened.terrain.sample(64,32).height,Float64(4))
    assert_equal(reopened.terrain.sample(64,32).color.x,Float64(.8))
    assert_true(len(reopened.terrain.samples)>0)
    var snapshot=reopened.terrain.copy()
    var stroke=reopened.terrain.brush(Vec3(64,0,32),8,2)
    reopened.terrain.apply(stroke)
    assert_equal(snapshot.sample(64,32).height,Float64(4))
    assert_equal(reopened.terrain.sample(64,32).height,Float64(6))
    with assert_raises():_=reopened.terrain.brush(Vec3(Float64("nan"),0,0),8,1)
    with assert_raises():_=reopened.terrain.brush(Vec3(0,0,0),129,1)
    for fault in range(1,4):
        var path=folder("recovery")
        var store=WorldStore(path.copy())
        var baseline=List[CellSnapshot]()
        baseline.append(CellSnapshot(TERRAIN_CELL,TERRAIN_CELL,0,TerrainLayer().scene()))
        baseline.append(CellSnapshot(0,0,0,Scene3D()))
        store.commit(baseline)
        var updated=List[CellSnapshot]()
        updated.append(CellSnapshot(TERRAIN_CELL,TERRAIN_CELL,1,snapshot.scene()))
        var objects=Scene3D()
        _=objects.add(SceneNode("edited with terrain",Transform3D(Vec3(1,0,1))))
        updated.append(CellSnapshot(0,0,1,objects^))
        with assert_raises():store.commit(updated,fault)
        store.close()
        var recovered=WorldPartition(path^)
        recovered.prepare()
        var cell=recovered.ensure(0,0)
        assert_equal(recovered.terrain.sample(64,32).height,Float64(0 if fault==1 else 4))
        assert_equal(len(recovered.cells[cell].scene.nodes),0 if fault==1 else 1)
        recovered.close()
    var malformed=snapshot.scene()
    malformed.nodes[1].mesh=0
    with assert_raises():_=TerrainLayer.from_scene(malformed)
    print("Terrain authoring passed: seams/LOD/colors, owned snapshots, undo/redo, save/reopen, grouped fault recovery")
