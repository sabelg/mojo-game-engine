"""Predeclared first seed qualification; records evidence before strict gates."""
from std.collections import List,Array
from std.sys import argv
from std.testing import assert_equal,assert_true
from mojo_game import Vec3,Quaternion
from experimental.physics_gpu.warm_plumbing_response import GpuWarmPlumbingBoxResponse
from experimental.physics_gpu.warm_seed_response import GpuWarmSeedBoxResponse
from experimental.physics_gpu.test_warm_plumbing_helpers import add_box_warm_plumbing
from experimental.physics_gpu.test_warm_seed_helpers import add_box_warm_seed
from experimental.physics_gpu.box_oracle import OracleBox
from experimental.physics_gpu.coupled_box_reference import CpuCoupledBoxResponse
from experimental.physics_gpu.test_box_interactions import snapshot,json_models,json_values,bits_equal
from experimental.physics_gpu.lifecycle import state_words,body_state
from experimental.physics_gpu.box_box import float_bits

def ratio(actual: List[OracleBox],expected: List[OracleBox]) -> Float64:
    var maximum=Float64(0)
    for i in range(len(actual)):
        var a=state_words(body_state(actual[i].body));var b=state_words(body_state(expected[i].body))
        for j in range(23):maximum=max(maximum,abs(a[j]-b[j])/(1e-10*(1+abs(b[j]))))
    return maximum

def int_values[N: Int](a: Array[Int64,N]) -> String:
    var out=String("[")
    for i in range(N):
        if i>0:out+="," 
        out+=String(a[i])
    return out+"]"

def main() raises:
    var args=argv();assert_equal(len(args),3);var mode=args[1];var prefix=args[2]
    assert_true(mode=="pair" or mode=="trajectory")
    var cold=GpuWarmPlumbingBoxResponse(velocity_budget=96);var warm=GpuWarmSeedBoxResponse(velocity_budget=96)
    var qa=Quaternion.axis_angle(Vec3(1,2,3),.2);var qb=Quaternion.axis_angle(Vec3(-2,1,3),.55)
    var n=qa.rotate(Vec3(1,0,0)).cross(qb.rotate(Vec3(1,0,0)));n=n*(1/n.length())
    var half=Vec3(.8,.1,.1);var ra=.1*(abs(n.dot(qa.rotate(Vec3(0,1,0))))+abs(n.dot(qa.rotate(Vec3(0,0,1)))))
    var rb=.1*(abs(n.dot(qb.rotate(Vec3(0,1,0))))+abs(n.dot(qb.rotate(Vec3(0,0,1)))))
    var ca=add_box_warm_plumbing(cold,Vec3(0,0,0),half,0,orientation=qa);var cb=add_box_warm_plumbing(cold,n*(ra+rb-1e-5),half,orientation=qb)
    var wa=add_box_warm_seed(warm,Vec3(0,0,0),half,0,orientation=qa);var wb=add_box_warm_seed(warm,n*(ra+rb-1e-5),half,orientation=qb)
    var cm: List[OracleBox]=[ca,cb];var wm: List[OracleBox]=[wa,wb];var cpu_models=cm.copy();var cpu=CpuCoupledBoxResponse(96)
    var accepted=0;var seeds=Int64(0);var maximum=Float64(0);var failed=False
    with open(prefix+"-frames.jsonl","w") as out:
        for frame in range(2 if mode=="pair" else 8):
            assert_equal(cold.detection.world.bodies.step(1.0/60,n*(-9.81)),Int32(0));assert_equal(warm.detection.world.bodies.step(1.0/60,n*(-9.81)),Int32(0))
            var ce=cold.detection.world.bodies.raw();var we=warm.detection.world.bodies.raw()
            if mode=="pair":bits_equal(ce,we)
            var entry=snapshot(we,wm)
            if mode=="pair":cpu_models=snapshot(ce,cm)
            else:
                for i in range(len(cpu_models)):_=cpu_models[i].body.integrate(1.0/60,n*(-9.81))
            var expected=cpu.solve(cpu_models,1.0/60,0,.2,96,64)
            var cr=cold.resolve(1.0/60,coefficient=.2,velocity_iterations=96,position_iterations=64)
            var wr=warm.resolve(1.0/60,coefficient=.2,velocity_iterations=96,position_iterations=64)
            var actual=snapshot(warm.detection.world.bodies.raw(),wm);var cold_actual=snapshot(cold.detection.world.bodies.raw(),cm)
            var r=ratio(actual,expected.models);var rc=ratio(cold_actual,expected.models);var rp=ratio(actual,cold_actual)
            var diag=warm.seed_report();var cache=warm.cache_report();var cw=cold.work_report();var ww=warm.work_report();seeds+=diag[1]
            var miss_exact=True
            if diag[1]==0:
                var ac=warm.detection.world.bodies.raw();var cc=cold.detection.world.bodies.raw()
                for i in range(len(ac)):
                    if float_bits(ac[i])!=float_bits(cc[i]):miss_exact=False
                for i in range(10):
                    if cw[i]!=ww[i]:miss_exact=False
            var normal_limit=Float64(0);var tangent_limit=Float64(0)
            with warm._stats.map_to_host() as stat:normal_limit=Float64(stat[5]);tangent_limit=Float64(stat[6])
            var gates=wr.normal_residual<=normal_limit and wr.tangent_residual<=tangent_limit and wr.kinetic_after<=wr.kinetic_before+1e-9*(1+wr.kinetic_before)
            out.write('{"mode":"'+mode+'","frame":'+String(frame)+',"warm_cpu_ratio":'+String(r)+',"cold_cpu_ratio":'+String(rc)+',"warm_cold_ratio":'+String(rp)+',"seed_diagnostics":'+int_values(diag)+',"cache_diagnostics":'+int_values(cache)+',"cold_work":'+int_values(cw)+',"warm_work":'+int_values(ww)+',"miss_exact":'+String(Int(miss_exact))+',"runtime_gates":'+String(Int(gates))+',"entry":'+json_models(entry)+',"cold":'+json_models(cold_actual)+',"warm":'+json_models(actual)+',"CPU":'+json_models(expected.models)+',"history":'+json_values(warm.residual_history())+'}\n')
            print("FIRST_SEED",mode,frame,"warm_CPU_ratio",r,"cold_CPU_ratio",rc,"warm_cold_ratio",rp,"seeds",diag[1],"patch_retry",diag[5],"whole_retry",diag[6],"miss_exact",miss_exact)
            maximum=max(maximum,r)
            if r>1 or rc>1 or (mode=="pair" and rp>1) or not gates or not miss_exact:failed=True;break
            accepted+=1;cpu_models=expected.models.copy()
    cold.close();warm.close()
    with open(prefix+"-result.json","w") as result:result.write('{"mode":"'+mode+'","accepted_frames":'+String(accepted)+',"seed_uses":'+String(seeds)+',"maximum_warm_CPU_ratio":'+String(maximum)+',"failed":'+String(Int(failed))+'}\n')
    assert_true(not failed,"Predeclared first physical/exact gate failed; stop candidate")
    assert_true(seeds>0,"Fixture must exercise an accepted seed")
    print("FIRST_SEED_PASS",mode,accepted)
