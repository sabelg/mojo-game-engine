"""Grouped selection transforms and independently identified prefab instances."""
from std.ffi import external_call
from std.testing import assert_equal,assert_true,assert_false,assert_raises
from mojo_game import WorldPartition,WorldEditor,SceneNode,Transform3D,Vec3,Quaternion,Material

def main() raises:
    var folder="build/editor-commands-"+String(external_call["SDL_GetPerformanceCounter",UInt64]())
    _=external_call["mkdir",Int32](folder.as_c_string_span(),Int(493))
    var world=WorldPartition(folder,cell_size=64)
    var editor=WorldEditor()
    editor.place(world,SceneNode("first",Transform3D(Vec3(63,0,0))))
    var first=editor.selected
    var first_id=world.cells[world.find(0,0)].scene.nodes[first].persistent_id.copy()
    editor.place(world,SceneNode("second",Transform3D(Vec3(62,0,0))))
    var second=editor.selected
    editor.select(world,0,0,first)
    editor.select(world,0,0,second,True)
    var history=len(editor.undo_stack)
    editor.adjust_selection(world,Vec3(3,0,0),snap=1)
    assert_equal(len(editor.undo_stack),history+1)
    assert_equal(len(editor.selection),2)
    assert_equal(editor.x,1)
    assert_equal(world.cells[world.find(1,0)].scene.nodes[editor.selection[0].node].persistent_id,first_id)
    editor.undo(world)
    assert_true(world.cells[world.find(0,0)].scene.nodes[first].active)
    assert_equal(world.cells[world.find(0,0)].scene.nodes[first].transform.position.x,Float64(63))
    editor.redo(world)
    assert_false(world.cells[world.find(0,0)].scene.nodes[first].active)
    editor.begin_group()
    editor.sculpt(world,Vec3(64,0,0),8,2)
    editor.sculpt(world,Vec3(64,0,0),8,3)
    editor.finish_group()
    assert_equal(world.terrain.sample(64,0).height,Float64(5))
    editor.undo(world)
    assert_equal(world.terrain.sample(64,0).height,Float64(0))
    editor.redo(world)
    assert_equal(world.terrain.sample(64,0).height,Float64(5))
    var prefab=editor.prefab(world)
    var template_id=prefab.nodes[0].persistent_id.copy()
    editor.instantiate(world,prefab,Vec3(128,0,2))
    var placed=editor.selected
    var clone_id=world.cells[world.find(2,0)].scene.nodes[placed].persistent_id.copy()
    assert_true(clone_id!=template_id)
    editor.undo(world)
    assert_false(world.cells[world.find(2,0)].scene.nodes[placed].active)
    editor.redo(world)
    assert_equal(world.cells[world.find(2,0)].scene.nodes[placed].persistent_id,clone_id)
    editor.material(world,Material(Vec3(.9,.2,.3),roughness=.2))
    assert_equal(world.cells[world.find(2,0)].scene.nodes[placed].material.color.x,Float64(.9))
    editor.undo(world)
    assert_true(world.cells[world.find(2,0)].scene.nodes[placed].material.color.x!=.9)
    editor.select(world,2,0,placed)
    var transform=world.cells[world.find(2,0)].scene.nodes[placed].transform
    transform.rotation=Quaternion.axis_angle(Vec3(0,1,0),1.57079632679)
    editor.transform(world,transform)
    editor.adjust_selection(world,Vec3(1,0,0),local=True)
    var moved=world.cells[world.find(editor.x,editor.z)].scene.nodes[editor.selected].transform.position
    assert_true(abs(moved.x-128)<1e-6 and abs(moved.z-1)<1e-6)
    editor.select(world,editor.x,editor.z,editor.selected)
    var primary=editor.selection[0]
    var original=world.cells[world.find(primary.x,primary.z)].scene.nodes[primary.node].transform.position
    # The first selected object moves across a cell before the second fails.
    # Rollback must restore both the object and the primary selection address.
    from mojo_game.worldeditor import ObjectSelection
    editor.selection.append(ObjectSelection(999,999,0))
    history=len(editor.undo_stack)
    with assert_raises():editor.adjust_selection(world,Vec3(100,0,0))
    assert_equal(editor.x,primary.x)
    assert_equal(editor.z,primary.z)
    assert_equal(editor.selected,primary.node)
    assert_equal(len(editor.undo_stack),history)
    assert_equal(world.cells[world.find(primary.x,primary.z)].scene.nodes[primary.node].transform.position.x,original.x)
    assert_false(editor.grouping)
    world.close()
    print("Editor commands passed: grouped cross-cell multi-selection, terrain group undo ordering, prefab identity/undo, properties and local transforms")
