"""Independent trajectory fixtures, actual consecutive frames and impact handoff."""
from std.collections import List
from std.testing import assert_equal,assert_true
from std.sys import argv
from std.memory import Pointer
from max.gpu.host import DeviceContext
from experimental.physics_gpu.rotating_subdivision_toi import rotating_subdivision_toi
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
    assert_true(text.byte_length()<4000000);var rows=text.split("\n");var ctx=DeviceContext();assert_equal(String(ctx.name()),String("NVIDIA GB10"));var input=ctx.enqueue_create_buffer[DType.float64](96);var output=ctx.enqueue_create_buffer[DType.float64](96);input.enqueue_fill(-987654321.25);output.enqueue_fill(-987654321.25);var carried=List[Float64]();var count=0
    with open(args[1]+"-cases.jsonl","w") as file:
        for row in rows:
            var fields=String(row).split("\t")
            if len(fields)==1:continue
            assert_equal(len(fields),196);var kind=Int(String(fields[0]));var variant=Int(String(fields[1]));var order=Int(String(fields[2]));var chain=Int(String(fields[3]));var initial=List[Float64]();var expected=List[Float64]()
            for i in range(96):initial.append(Float64(String(fields[4+i])));expected.append(Float64(String(fields[100+i])))
            if chain==1:
                for i in range(5,18):initial[i]=carried[i]
            with input.map_to_host() as a:
                for i in range(96):a[i]=initial[i]
            ctx.enqueue_function[rotating_subdivision_toi](input,output,grid_dim=1,block_dim=1);ctx.synchronize();var actual=List[Float64]()
            with output.map_to_host() as a:
                for i in range(96):actual.append(Float64(a[i]))
            with input.map_to_host() as a:
                for i in range(96):assert_equal(bits(Float64(a[i])),bits(initial[i]))
            var valid=actual[39]==expected[39];var ratio=Float64(0)
            assert_equal(bits(actual[0]),bits(initial[0]));assert_equal(bits(actual[95]),bits(initial[95]))
            for i in range(1,44):
                if i==39:continue
                if actual[39]!=0 or i<5 or i>14:valid=valid and bits(actual[i])==bits(initial[i])
                if actual[39]==0:ratio=max(ratio,abs(actual[i]-expected[i])/(1e-10*(1+abs(expected[i]))))
            if actual[39]==0:
                for i in range(44,76):ratio=max(ratio,abs(actual[i]-expected[i])/(1e-10*(1+abs(expected[i]))))
                valid=valid and ratio<=1 and actual[55]==0 and actual[44]==expected[44] and actual[49]==expected[49]
            file.write('{"kind":'+String(kind)+',"variant":'+String(variant)+',"order":'+String(order)+',"chain":'+String(chain)+',"input":'+values(initial)+',"expected":'+values(expected)+',"actual":'+values(actual)+',"gate_ratio":'+String(ratio)+',"pass":'+String(Int(valid))+'}\n');assert_true(valid,"STOP: sweep state/geometry/rollback failure");carried=actual.copy();count+=1
    print("ROTATING_SUBDIVISION_REFERENCE_PASS",count)
