"""Independent Decimal reference fixtures, atomic state and episode checks."""
from std.collections import List
from std.testing import assert_equal,assert_true
from std.sys import argv
from std.memory import Pointer
from max.gpu.host import DeviceContext
from experimental.physics_gpu.rotating_floor_vertex_impact import rotating_floor_vertex_impact

def bits(value: Float64) -> UInt64:
    var stored=value;return Pointer[UInt64,MutAnyOrigin](unsafe_from_address=Int(Pointer(to=stored)))[]
def values(a: List[Float64]) -> String:
    var s=String("[")
    for i in range(len(a)):
        if i>0:s+=","
        s+=String(a[i])
    return s+"]"
def main() raises:
    var args=argv();assert_equal(len(args),3);var text=String("")
    with open(args[2],"r") as f:text=f.read()
    assert_true(text.byte_length()<4000000);var rows=text.split("\n");var ctx=DeviceContext();assert_equal(String(ctx.name()),String("NVIDIA GB10"));var input=ctx.enqueue_create_buffer[DType.float64](96);var output=ctx.enqueue_create_buffer[DType.float64](96);input.enqueue_fill(-987654321.25);output.enqueue_fill(-987654321.25);var count=0;var chains=0
    with open(args[1]+"-cases.jsonl","w") as file:
        for row in rows:
            var fields=String(row).split("\t")
            if len(fields)==1:continue
            assert_equal(len(fields),195);var kind=Int(String(fields[0]));var variant=Int(String(fields[1]));var order=Int(String(fields[2]));var initial=List[Float64]();var expected=List[Float64]()
            for i in range(96):initial.append(Float64(String(fields[3+i])));expected.append(Float64(String(fields[99+i])))
            with input.map_to_host() as a:
                for i in range(96):a[i]=initial[i]
            ctx.enqueue_function[rotating_floor_vertex_impact](input,output,grid_dim=1,block_dim=1);ctx.synchronize();var actual=List[Float64]()
            with output.map_to_host() as a:
                for i in range(96):actual.append(Float64(a[i]))
            with input.map_to_host() as a:
                for i in range(96):assert_equal(bits(Float64(a[i])),bits(initial[i]))
            assert_equal(bits(actual[0]),bits(initial[0]));assert_equal(bits(actual[95]),bits(initial[95]));var valid=actual[39]==expected[39];var ratio=Float64(0);var diagnostic_ratio=Float64(0)
            for i in range(1,39):
                if actual[39]!=0 or i<12 or i>17:valid=valid and bits(actual[i])==bits(initial[i])
                ratio=max(ratio,abs(actual[i]-expected[i])/(1e-10*(1+abs(expected[i]))))
            if actual[39]==0:
                valid=valid and ratio<=1 and actual[40]==expected[40] and actual[55]==expected[55] and actual[47]<=actual[54] and actual[49]<=actual[48]+1e-9*(1+actual[48]) and actual[93]<=1e-9*(1+actual[48]) and actual[45]>=0 and abs(actual[41])<=1e-9 and actual[42]>1e-9
                for i in range(40,95):diagnostic_ratio=max(diagnostic_ratio,abs(actual[i]-expected[i])/(1e-10*(1+abs(expected[i]))))
                valid=valid and diagnostic_ratio<=1
                if actual[45]==0:
                    for i in range(1,39):valid=valid and bits(actual[i])==bits(initial[i])
            file.write('{"kind":'+String(kind)+',"variant":'+String(variant)+',"order":'+String(order)+',"input":'+values(initial)+',"expected":'+values(expected)+',"actual":'+values(actual)+',"state_gate_ratio":'+String(ratio)+',"diagnostic_gate_ratio":'+String(diagnostic_ratio)+',"physical_pass":'+String(Int(valid))+'}\n');assert_true(valid,"STOP: first substantive rotating vertex physical/rollback failure");count+=1
            if kind<=2 and order==0:
                var continuation=initial.copy()
                for i in range(1,24):continuation[i]=actual[i]
                continuation[37]=0
                with input.map_to_host() as a:
                    for i in range(96):a[i]=continuation[i]
                ctx.enqueue_function[rotating_floor_vertex_impact](input,output,grid_dim=1,block_dim=1);ctx.synchronize();var next=List[Float64]()
                with output.map_to_host() as a:
                    for i in range(96):next.append(Float64(a[i]))
                with input.map_to_host() as a:
                    for i in range(96):assert_equal(bits(Float64(a[i])),bits(continuation[i]))
                var chain_valid=next[39]==0 and next[44]==0 and next[55]==0 and next[45]<=1e-10*(1+actual[45]) and next[47]<=next[54] and next[49]<=actual[49]+1e-9*(1+actual[49])
                assert_equal(bits(next[0]),bits(initial[0]));assert_equal(bits(next[95]),bits(initial[95]))
                for i in range(1,39):
                    if i<12 or i>17:chain_valid=chain_valid and bits(next[i])==bits(continuation[i])
                if kind>0:
                    for i in range(1,39):chain_valid=chain_valid and bits(next[i])==bits(continuation[i])
                file.write('{"kind":'+String(kind)+',"variant":'+String(variant)+',"order":'+String(order)+',"chain":1,"input":'+values(continuation)+',"actual":'+values(next)+',"physical_pass":'+String(Int(chain_valid))+'}\n');assert_true(chain_valid,"STOP: restitution applied twice or continuing-contact invariant failed");chains+=1
    print("ROTATING_VERTEX_REFERENCE_AND_ATOMIC_PASS",count,chains)
