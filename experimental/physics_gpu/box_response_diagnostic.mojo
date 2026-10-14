"""Finite explicit96 three-box response diagnostic; no general stack promise."""
from std.collections import List
from std.testing import assert_equal,assert_true
from mojo_game import Vec3
from experimental.physics_gpu.box_response import GpuBoxResponse
from experimental.physics_gpu.box_response_reference import CpuBoxResponse
from experimental.physics_gpu.box_oracle import OracleBox
from experimental.physics_gpu.test_box_response import add_box_response,states,total_kinetic,potential

def main() raises:
    var response=GpuBoxResponse(velocity_budget=96);var models=List[OracleBox]();models.append(add_box_response(response,Vec3(0,-.25,0),Vec3(5,.25,5),0))
    for i in range(3):models.append(add_box_response(response,Vec3(0,.5+Float64(i)-1e-5*Float64(i+1),0)))
    var cpu=CpuBoxResponse(96);var dt=Float64(1)/30;var g=Vec3(0,-9.81,0);var work=Float64(0);var dissipation=Float64(0)
    for frame in range(12):
        assert_equal(response.detection.world.bodies.step(dt,g),Int32(0))
        for i in range(len(models)):_=models[i].body.integrate(dt,g)
        var before_kinetic=total_kinetic(models);var before_potential=potential(models,g)
        var expected=cpu.solve(models,dt,0,0,96,64);var report=response.resolve(dt,velocity_iterations=96,position_iterations=64);states(response,expected.models);models=expected.models.copy()
        work+=potential(models,g)-before_potential;dissipation+=before_kinetic-total_kinetic(models)
        assert_equal(report.patches,Int32(3));assert_equal(report.points,Int32(12));assert_true(report.maximum_depth<=1e-5+1e-9)
        print("box_response_diagnostic",frame,"policy",96,"sweeps",report.velocity_sweeps,"residual",report.normal_residual,"depth",report.maximum_depth,"energy",total_kinetic(models))
    print("BOX_RESPONSE_DEMO",12,"projection_work",work,"normal_dissipation",dissipation,"CPU_replay",True,"baseline64_30Hz_failure_retained",True)
    response.close()
