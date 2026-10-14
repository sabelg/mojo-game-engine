"""Isolated continuous reaction fixtures; immutable body/episode and atomic outputs."""
from std.collections import List
from std.testing import assert_equal,assert_true
from std.sys import argv
from std.memory import Pointer
from max.gpu.host import DeviceContext
from experimental.physics_gpu.single_point_reaction import single_point_reaction

def bits(value: Float64) -> UInt64:
    var stored=value;return Pointer[UInt64,MutAnyOrigin](unsafe_from_address=Int(Pointer(to=stored)))[]
def values(a: List[Float64]) -> String:
    var s=String("[")
    for i in range(len(a)):
        if i>0:s+=","
        s+=String(a[i])
    return s+"]"
def main() raises:
    var args=argv();assert_equal(len(args),3);var ctx=DeviceContext();assert_equal(String(ctx.name()),String("NVIDIA GB10"));var input=ctx.enqueue_create_buffer[DType.float64](96);var output=ctx.enqueue_create_buffer[DType.float64](96);input.enqueue_fill(-987654321.25);output.enqueue_fill(-987654321.25);var text=String("")
    with open(args[2],"r") as f:text=f.read()
    var count=0
    with open(args[1]+"-cases.jsonl","w") as file:
        for row in text.split("\n"):
            var fields=String(row).split("\t")
            if len(fields)==1:continue
            assert_equal(len(fields),197);var x=List[Float64]();var y=List[Float64]()
            for i in range(96):x.append(Float64(String(fields[5+i])));y.append(Float64(String(fields[101+i])))
            with input.map_to_host() as a:
                for i in range(96):a[i]=x[i]
            ctx.enqueue_function[single_point_reaction](input,output,grid_dim=1,block_dim=1);ctx.synchronize();var actual=List[Float64]()
            with output.map_to_host() as a:
                for i in range(96):actual.append(Float64(a[i]))
            with input.map_to_host() as a:
                for i in range(96):assert_equal(bits(Float64(a[i])),bits(x[i]))
            var valid=actual[39]==y[39];var ratio=Float64(0)
            for i in range(45):
                if i!=39:valid=valid and bits(actual[i])==bits(x[i])
            valid=valid and bits(actual[95])==bits(x[95])
            if actual[39]==0:
                for i in range(46,95):ratio=max(ratio,abs(actual[i]-y[i])/(1e-10*(1+abs(y[i]))))
                valid=valid and ratio<=1 and actual[46]>=0 and actual[47]>=0 and actual[57]<=actual[56]
            else:
                for i in range(45,79):valid=valid and bits(actual[i])==bits(Float64(0))
            file.write('{"case":'+String(fields[0])+',"variant":'+String(fields[1])+',"order":'+String(fields[2])+',"swap":'+String(fields[3])+',"episode":'+String(fields[4])+',"input":'+values(x)+',"actual":'+values(actual)+',"expected":'+values(y)+',"gate_ratio":'+String(ratio)+',"pass":'+String(Int(valid))+'}\n');assert_true(valid,"STOP: reaction reference/body immutability/atomic output gate");count+=1
            if actual[39]!=0:
                ctx.enqueue_function[single_point_reaction](input,output,grid_dim=1,block_dim=1);ctx.synchronize();var replay=List[Float64]()
                with output.map_to_host() as a:
                    for i in range(96):replay.append(Float64(a[i]));assert_equal(bits(Float64(a[i])),bits(actual[i]))
                file.write('{"case":'+String(fields[0])+',"order":'+String(fields[2])+',"swap":'+String(fields[3])+',"episode":'+String(fields[4])+',"replay":1,"actual":'+values(replay)+',"pass":1}\n')
    print("SINGLE_POINT_REACTION_PASS",count)
