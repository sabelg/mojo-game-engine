"""Sequential GPU handoff transactions with rollback and independent reference gates."""
from std.collections import List
from std.testing import assert_equal,assert_true
from std.sys import argv
from max.gpu.host import DeviceContext
from experimental.physics_gpu.floor_handoff import floor_handoff,handoff_bits

def values(a: List[Float64]) -> String:
    var s=String("[")
    for i in range(len(a)):
        if i>0:s+=","
        s+=String(a[i])
    return s+"]"
def main() raises:
    var args=argv();assert_equal(len(args),3);var ctx=DeviceContext();assert_equal(String(ctx.name()),String("NVIDIA GB10"));var input=ctx.enqueue_create_buffer[DType.float64](96);var prior=ctx.enqueue_create_buffer[DType.float64](128);var output=ctx.enqueue_create_buffer[DType.float64](128);var scratch=ctx.enqueue_create_buffer[DType.float64](288);var req=ctx.enqueue_create_buffer[DType.float64](2);var status=ctx.enqueue_create_buffer[DType.float64](2);var text=String("")
    with open(args[2],"r") as f:text=f.read()
    var previous=List[Float64]()
    for i in range(128):previous.append(0)
    var count=0
    with open(args[1]+"-cases.jsonl","w") as file:
        for row in text.split("\n"):
            var fields=String(row).split("\t")
            if len(fields)==1:continue
            assert_equal(len(fields),230)
            if String(fields[0])=="1":
                for i in range(128):previous[i]=0
            var x=List[Float64]();var expected=List[Float64]()
            for i in range(96):x.append(previous[i] if String(fields[1])=="1" else Float64(String(fields[6+i])))
            for i in range(128):expected.append(Float64(String(fields[102+i])))
            with input.map_to_host() as a:
                for i in range(96):a[i]=x[i]
            with prior.map_to_host() as a:
                for i in range(128):a[i]=previous[i]
            with req.map_to_host() as a:a[0]=Float64(String(fields[2]));a[1]=Float64(String(fields[3]))
            ctx.enqueue_function[floor_handoff](input,prior,req,output,scratch,status,grid_dim=1,block_dim=1);ctx.synchronize()
            var actual=List[Float64]();var code=Float64(0);var sub=Float64(0)
            with output.map_to_host() as a:
                for i in range(128):actual.append(Float64(a[i]))
            with status.map_to_host() as a:code=Float64(a[0]);sub=Float64(a[1])
            var valid=code==Float64(String(fields[4])) and sub==Float64(String(fields[5]));var ratio=Float64(0)
            with input.map_to_host() as a:
                for i in range(96):valid=valid and handoff_bits(Float64(a[i]))==handoff_bits(x[i])
            with prior.map_to_host() as a:
                for i in range(128):valid=valid and handoff_bits(Float64(a[i]))==handoff_bits(previous[i])
            if code!=0:
                for i in range(128):valid=valid and handoff_bits(actual[i])==handoff_bits(previous[i])
            else:
                for i in range(128):
                    if i!=45:ratio=max(ratio,abs(actual[i]-expected[i])/(1e-10*(1+abs(expected[i]))))
                valid=valid and ratio<=1
                for i in range(1,45):
                    if i!=39 and (i<12 or i>=18 or actual[99]==previous[99]):valid=valid and handoff_bits(actual[i])==handoff_bits(x[i])
                valid=valid and actual[96]==previous[96]+1
            file.write('{"case":'+String(count)+',"input":'+values(x)+',"previous":'+values(previous)+',"actual":'+values(actual)+',"code":'+String(code)+',"inner":'+String(sub)+',"ratio":'+String(ratio)+',"pass":'+String(Int(valid))+'}\n');assert_true(valid,"STOP: handoff reference/rollback/immutability gate")
            if code!=0:
                ctx.enqueue_function[floor_handoff](input,prior,req,output,scratch,status,grid_dim=1,block_dim=1);ctx.synchronize()
                with output.map_to_host() as a:
                    for i in range(128):assert_equal(handoff_bits(Float64(a[i])),handoff_bits(previous[i]))
                with status.map_to_host() as a:assert_equal(Float64(a[0]),code);assert_equal(Float64(a[1]),sub)
                file.write('{"case":'+String(count)+',"replay":1,"pass":1}\n')
            previous=actual^;count+=1
    print("FLOOR_HANDOFF_PASS",count)
