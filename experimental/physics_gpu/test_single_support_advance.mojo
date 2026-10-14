"""One fixed-active macro per fixture; native independent reference/rollback gates."""
from std.collections import List
from std.testing import assert_equal,assert_true
from std.sys import argv
from max.gpu.host import DeviceContext
from experimental.physics_gpu.floor_handoff import handoff_bits
from experimental.physics_gpu.single_support_advance import single_support_advance

def values(a: List[Float64]) -> String:
    var s=String("[")
    for i in range(len(a)):
        if i>0:s+=","
        s+=String(a[i])
    return s+"]"
def main() raises:
    var args=argv();assert_equal(len(args),3);var ctx=DeviceContext();assert_equal(String(ctx.name()),String("NVIDIA GB10"));var input=ctx.enqueue_create_buffer[DType.float64](96);var prior=ctx.enqueue_create_buffer[DType.float64](128);var output=ctx.enqueue_create_buffer[DType.float64](128);var scratch=ctx.enqueue_create_buffer[DType.float64](1728);var req=ctx.enqueue_create_buffer[DType.float64](11);var status=ctx.enqueue_create_buffer[DType.float64](2);var report=ctx.enqueue_create_buffer[DType.float64](32);var text=String("")
    with open(args[2],"r") as f:text=f.read()
    var count=0
    with open(args[1]+"-cases.jsonl","w") as file:
        for row in text.split("\n"):
            var fields=String(row).split("\t")
            if len(fields)==1:continue
            assert_equal(len(fields),269)
            var x=List[Float64]();var before=List[Float64]();var request=List[Float64]();var expected=List[Float64]()
            for i in range(96):x.append(Float64(String(fields[2+i])))
            for i in range(128):before.append(Float64(String(fields[98+i])))
            for i in range(11):request.append(Float64(String(fields[226+i])))
            for i in range(32):expected.append(Float64(String(fields[237+i])))
            with input.map_to_host() as a:
                for i in range(96):a[i]=x[i]
            with prior.map_to_host() as a:
                for i in range(128):a[i]=before[i]
            with req.map_to_host() as a:
                for i in range(11):a[i]=request[i]
            ctx.enqueue_function[single_support_advance](input,prior,req,output,scratch,status,report,grid_dim=1,block_dim=1);ctx.synchronize()
            var actual=List[Float64]();var diag=List[Float64]();var code=Float64(0);var sub=Float64(0)
            with output.map_to_host() as a:
                for i in range(128):actual.append(Float64(a[i]))
            with report.map_to_host() as a:
                for i in range(32):diag.append(Float64(a[i]))
            with status.map_to_host() as a:code=Float64(a[0]);sub=Float64(a[1])
            var valid=code==Float64(String(fields[1]));var ratio=Float64(0)
            with input.map_to_host() as a:
                for i in range(96):valid=valid and handoff_bits(Float64(a[i]))==handoff_bits(x[i])
            with prior.map_to_host() as a:
                for i in range(128):valid=valid and handoff_bits(Float64(a[i]))==handoff_bits(before[i])
            if code!=0:
                for i in range(128):valid=valid and handoff_bits(actual[i])==handoff_bits(before[i])
            else:
                for i in range(13):ratio=max(ratio,abs(actual[5+i]-expected[i])/(1e-10*(1+abs(expected[i]))))
                for i in range(5):ratio=max(ratio,abs(diag[20+i]-expected[13+i])/(1e-10*(1+abs(expected[13+i]))))
                valid=valid and ratio<=1 and diag[0]==request[8] and actual[96]==before[96]+1 and actual[99]==before[99]
                for i in range(18,24):valid=valid and actual[i]==0
                for i in range(100,104):valid=valid and actual[i]==before[i]
                for i in range(1,45):
                    if i<5 or (i>=24 and i!=39):valid=valid and handoff_bits(actual[i])==handoff_bits(x[i])
            file.write('{"case":'+String(count)+',"input":'+values(x)+',"previous":'+values(before)+',"request":'+values(request)+',"actual":'+values(actual)+',"report":'+values(diag)+',"code":'+String(code)+',"inner":'+String(sub)+',"ratio":'+String(ratio)+',"pass":'+String(Int(valid))+'}\n');assert_true(valid,"STOP: support reference/admission/whole-macro rollback gate")
            if code!=0:
                ctx.enqueue_function[single_support_advance](input,prior,req,output,scratch,status,report,grid_dim=1,block_dim=1);ctx.synchronize()
                with output.map_to_host() as a:
                    for i in range(128):assert_equal(handoff_bits(Float64(a[i])),handoff_bits(before[i]))
                with status.map_to_host() as a:assert_equal(Float64(a[0]),code);assert_equal(Float64(a[1]),sub)
                file.write('{"case":'+String(count)+',"replay":1,"pass":1}\n')
            count+=1
    print("SINGLE_SUPPORT_ADVANCE_PASS",count)
