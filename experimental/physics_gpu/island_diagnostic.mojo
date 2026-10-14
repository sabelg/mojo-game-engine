"""Finite actual GPU edit/split/rejoin/reuse diagnostic; no physics solver change."""
from std.collections import List
from std.testing import assert_equal
from mojo_game import Vec3
from experimental.physics_gpu.islands import GpuContactIslands
from experimental.physics_gpu.lifecycle import BodyCommand
from experimental.physics_gpu.test_islands import Node,add,move,oracle

def show(mut islands: GpuContactIslands,nodes: List[Node],stage: String,expected: Int32) raises:
    var f=islands.update();oracle(nodes,f);assert_equal(f.report.islands,expected)
    print("island_diagnostic",stage,"epoch",f.report.epoch,"islands",f.report.islands,"bodies",f.report.live_bodies,"contacts",f.report.contacts)
    for m in f.members:
        if m.dynamic:print("dynamic_member",m.body.slot,"generation",m.body.generation,"root",m.root.slot,"root_generation",m.root.generation)

def main() raises:
    var islands=GpuContactIslands();var nodes=List[Node]()
    _=add(islands,nodes,Vec3(0,-.1,0),False,2,Vec3(10,.1,10))
    _=add(islands,nodes,Vec3(-3,.45,0));_=add(islands,nodes,Vec3(-2.1,.45,0));_=add(islands,nodes,Vec3(3,.45,0))
    show(islands,nodes,"initial_shared_fixed_floor",2)
    move(islands,nodes,2,Vec3(0,.45,0));show(islands,nodes,"split_without_static_bridge",3)
    move(islands,nodes,2,Vec3(-2.1,.45,0));show(islands,nodes,"rejoined",2)
    var old=nodes[1].handle;_=islands.world.bodies.submit([BodyCommand.remove(old)]);nodes[1].live=False
    show(islands,nodes,"root_removed",2)
    var replacement=add(islands,nodes,Vec3(-3,.45,0));assert_equal(nodes[replacement].handle.slot,old.slot)
    show(islands,nodes,"root_slot_reused_new_generation",2)
    islands.close();print("G05a diagnostic actual GPU edits/labels match independent CPU oracle; no response/sleep scheduling")
