"""Independent fixtures, point ordering, byte-exact rejection/replay and rank probes."""
from std.collections import List
from std.testing import assert_equal,assert_true
from std.sys import argv
from std.memory import Pointer
from max.gpu.host import DeviceContext
from experimental.physics_gpu.two_point_inelastic import two_point_inelastic,solve_normal_pair

def bits(value: Float64) -> UInt64:
    var stored=value;return Pointer[UInt64,MutAnyOrigin](unsafe_from_address=Int(Pointer(to=stored)))[]
def values(a: List[Float64]) -> String:
    var s=String("[")
    for i in range(len(a)):
        if i>0:s+=","
        s+=String(a[i])
    return s+"]"
def pair_probe(a: Pointer[Float64,MutAnyOrigin],b: Pointer[Float64,MutAnyOrigin]):
    var s=solve_normal_pair(a[unsafe_offset=1],a[unsafe_offset=2],a[unsafe_offset=3],a[unsafe_offset=4],a[unsafe_offset=5]);b[unsafe_offset=1]=Float64(s.code);b[unsafe_offset=2]=s.a;b[unsafe_offset=3]=s.b;b[unsafe_offset=4]=Float64(s.mask);b[unsafe_offset=5]=s.relative_determinant

def main() raises:
    var args=argv();assert_equal(len(args),4);var ctx=DeviceContext();assert_equal(String(ctx.name()),String("NVIDIA GB10"));var input=ctx.enqueue_create_buffer[DType.float64](96);var output=ctx.enqueue_create_buffer[DType.float64](96);input.enqueue_fill(-987654321.25);output.enqueue_fill(-987654321.25);var text=String("")
    with open(args[2],"r") as f:text=f.read()
    var count=0
    with open(args[1]+"-cases.jsonl","w") as file:
        for row in text.split("\n"):
            var fields=String(row).split("\t")
            if len(fields)==1:continue
            assert_equal(len(fields),196);var x=List[Float64]();var y=List[Float64]()
            for i in range(96):x.append(Float64(String(fields[4+i])));y.append(Float64(String(fields[100+i])))
            with input.map_to_host() as a:
                for i in range(96):a[i]=x[i]
            ctx.enqueue_function[two_point_inelastic](input,output,grid_dim=1,block_dim=1);ctx.synchronize();var actual=List[Float64]()
            with output.map_to_host() as a:
                for i in range(96):actual.append(Float64(a[i]))
            with input.map_to_host() as a:
                for i in range(96):assert_equal(bits(Float64(a[i])),bits(x[i]))
            var valid=actual[39]==y[39];var ratio=Float64(0)
            for i in range(96):
                if i==0 or i==95 or i==40 or i==41 or (i>=1 and i<=38 and (actual[39]!=0 or i<12 or i>17)):valid=valid and bits(actual[i])==bits(x[i])
                if actual[39]==0 and i>=1 and i<=38:ratio=max(ratio,abs(actual[i]-y[i])/(1e-10*(1+abs(y[i]))))
            if actual[39]==0:
                for i in range(44,55):ratio=max(ratio,abs(actual[i]-y[i])/(1e-10*(1+abs(y[i]))))
                for i in range(56,59):ratio=max(ratio,abs(actual[i]-y[i])/(1e-9*(1+abs(y[i]))))
                valid=valid and ratio<=1 and actual[44]>=0 and actual[45]>=0 and actual[55]<=actual[54] and actual[59]<=actual[93]
                if actual[44]==0 and actual[45]==0:
                    for i in range(1,39):valid=valid and bits(actual[i])==bits(x[i])
            file.write('{"case":'+String(fields[0])+',"variant":'+String(fields[1])+',"order":'+String(fields[2])+',"swap":'+String(fields[3])+',"input":'+values(x)+',"actual":'+values(actual)+',"expected":'+values(y)+',"gate_ratio":'+String(ratio)+',"pass":'+String(Int(valid))+'}\n');assert_true(valid,"STOP: two-point physical/reference/atomicity gate");count+=1
            if actual[39]!=0:
                ctx.enqueue_function[two_point_inelastic](input,output,grid_dim=1,block_dim=1);ctx.synchronize();var replay=List[Float64]()
                with output.map_to_host() as a:
                    for i in range(96):replay.append(Float64(a[i]));assert_equal(bits(Float64(a[i])),bits(actual[i]))
                file.write('{"case":'+String(fields[0])+',"order":'+String(fields[2])+',"swap":'+String(fields[3])+',"replay":1,"actual":'+values(replay)+',"pass":1}\n')
    with open(args[3],"r") as f:text=f.read()
    with open(args[1]+"-algebra.jsonl","w") as file:
        for row in text.split("\n"):
            var fields=String(row).split("\t")
            if len(fields)==1:continue
            assert_equal(len(fields),9)
            with input.map_to_host() as a:
                for i in range(1,6):a[i]=Float64(String(fields[i]))
            ctx.enqueue_function[pair_probe](input,output,grid_dim=1,block_dim=1);ctx.synchronize();var actual=List[Float64]()
            with output.map_to_host() as a:
                for i in range(1,6):actual.append(Float64(a[i]))
            var valid=actual[0]==Float64(String(fields[6]))
            for i in range(2):valid=valid and abs(actual[i+1]-Float64(String(fields[7+i])))<=1e-10*(1+abs(Float64(String(fields[7+i]))))
            ctx.enqueue_function[pair_probe](input,output,grid_dim=1,block_dim=1);ctx.synchronize()
            with output.map_to_host() as a:
                for i in range(1,6):valid=valid and bits(Float64(a[i]))==bits(actual[i-1])
            file.write('{"case":'+String(fields[0])+',"actual":'+values(actual)+',"exact_replay":1,"pass":'+String(Int(valid))+'}\n');assert_true(valid,"STOP: algebra rank/complementarity probe")
    print("TWO_POINT_ISOLATED_PASS",count)
