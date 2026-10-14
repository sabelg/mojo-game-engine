"""One unchanged failed cold shared-friction step, complete private diagnostics."""
from std.collections import List
from std.sys import argv
from std.testing import assert_equal,assert_raises
from mojo_game import Vec3
from experimental.physics_gpu.box_response import GpuBoxResponse
from experimental.physics_gpu.test_box_interactions import inputs,json_values,bits_equal,json_models,snapshot

def main() raises:
    var args=argv();var output=args[1];var gpu=GpuBoxResponse(velocity_budget=96);var models=inputs(gpu,3,17,0)
    assert_equal(gpu.detection.world.bodies.step(1.0/30,Vec3(0,-9.81,0)),Int32(0));var entry=gpu.detection.world.bodies.raw()
    with assert_raises():_=gpu.resolve(1.0/30,coefficient=.2,velocity_iterations=96,position_iterations=64)
    assert_equal(gpu.last_error,Int32(114));bits_equal(entry,gpu.detection.world.bodies.raw())
    var data=String('{"original_error":114,"body_rollback":true,"entry_bodies":')+json_models(snapshot(entry,models))
    with gpu._candidate.map_to_host() as buf:
        var values=List[Float64]()
        for i in range(len(buf)):values.append(Float64(buf[i]))
        data+=',"candidate_bodies":'+json_models(snapshot(values,models))
    with gpu._projected.map_to_host() as buf:
        var values=List[Float64]()
        for i in range(len(buf)):values.append(Float64(buf[i]))
        data+=',"projected_bodies":'+json_models(snapshot(values,models))
    with gpu._geometry.map_to_host() as buf:
        var values=List[Float64]()
        for i in range(81):values.append(Float64(buf[i]))
        data+=',"geometry":'+json_values(values)
    with gpu._headers.map_to_host() as buf:
        var values=List[Float64]()
        for i in range(89):values.append(Float64(buf[i]))
        data+=',"headers":'+json_values(values)
    with gpu._spans.map_to_host() as buf:
        var values=List[Float64]()
        for i in range(5):values.append(Float64(buf[i]))
        data+=',"spans":'+json_values(values)
    with gpu._grams.map_to_host() as buf:
        var values=List[Float64]()
        for i in range(33):values.append(Float64(buf[i]))
        data+=',"normal_grams":'+json_values(values)
    with gpu._impulses.map_to_host() as buf:
        var values=List[Float64]()
        for i in range(9):values.append(Float64(buf[i]))
        data+=',"normal_impulses":'+json_values(values)
    with gpu._tangent.map_to_host() as buf:
        var values=List[Float64]()
        for i in range(17):values.append(Float64(buf[i]))
        data+=',"tangent_impulses":'+json_values(values)
    with gpu._stats.map_to_host() as buf:
        var values=List[Float64]()
        for i in range(9):values.append(Float64(buf[i]))
        data+=',"stats":'+json_values(values)
    with gpu._residuals.map_to_host() as buf:
        var values=List[Float64]()
        for i in range(193):values.append(Float64(buf[i]))
        data+=',"history":'+json_values(values)
    with open(output,"w") as file:file.write(data+'}\n')
    print("UNCHANGED_SHARED_FRICTION_DIAGNOSTIC",96,"error",gpu.last_error,"rollback",True);gpu.close()
