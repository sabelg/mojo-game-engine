"""Independent full-step fixtures and public owner lifecycle/rollback tests."""
from std.collections import List
from std.testing import assert_equal,assert_true
from std.sys import argv
from std.memory import Pointer
from experimental.physics_gpu.rotating_floor_owner import GpuRotatingFloorAdvance

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
    assert_true(text.byte_length()<4000000);var rows=text.split("\n");var empty=List[Float64]()
    for i in range(104):empty.append(0)
    var owner=GpuRotatingFloorAdvance(empty);var carried=List[Float64]();var count=0;var replay_count=0
    with open(args[1]+"-cases.jsonl","w") as file:
        for row in rows:
            var fields=String(row).split("\t")
            if len(fields)==1:continue
            assert_equal(len(fields),389);var kind=Int(String(fields[0]));var variant=Int(String(fields[1]));var frame=Int(String(fields[2]));var mode=Int(String(fields[3]));var expected_code=Int(String(fields[4]));var payload=List[Float64]();var expected=List[Float64]()
            for i in range(104):payload.append(Float64(String(fields[5+i])))
            for i in range(192):expected.append(Float64(String(fields[197+i])))
            if mode==1:
                for i in range(5,18):payload[i]=carried[i]
            if mode==0:owner._fresh(payload)
            else:owner.update(payload)
            var before=owner.snapshot();var code=owner.advance();var actual=owner.snapshot();var diagnostic=owner.report();var valid=code==expected_code;var ratio=Float64(0)
            for i in range(192):
                if code!=0:valid=valid and bits(actual[i])==bits(before[i])
                elif i!=39:ratio=max(ratio,abs(actual[i]-expected[i])/(1e-10*(1+abs(expected[i]))))
            if code==0:
                valid=valid and ratio<=1 and actual[44]==payload[40] and actual[45]==expected[45] and actual[46]==expected[46] and actual[115]==expected[115]
                for i in range(18,24):valid=valid and actual[i]==0
            valid=valid and bits(actual[0])==bits(before[0]) and bits(actual[95])==bits(before[95]) and bits(actual[191])==bits(before[191])
            file.write('{"kind":'+String(kind)+',"variant":'+String(variant)+',"frame":'+String(frame)+',"mode":'+String(mode)+',"code":'+String(code)+',"input":'+values(before)+',"expected":'+values(expected)+',"actual":'+values(actual)+',"diagnostic":'+values(diagnostic)+',"gate_ratio":'+String(ratio)+',"pass":'+String(Int(valid))+'}\n');assert_true(valid,"STOP: rotating advance independent state or whole-macro rollback failure");count+=1
            if code!=0:
                var replay_code=owner.advance();var replay=owner.snapshot();var replay_diagnostic=owner.report();var same=replay_code==code
                for i in range(192):same=same and bits(replay[i])==bits(before[i]) and bits(replay_diagnostic[i])==bits(diagnostic[i])
                file.write('{"kind":'+String(kind)+',"variant":'+String(variant)+',"frame":'+String(frame)+',"replay":1,"code":'+String(replay_code)+',"input":'+values(before)+',"actual":'+values(replay)+',"diagnostic":'+values(replay_diagnostic)+',"pass":'+String(Int(same))+'}\n');assert_true(same,"STOP: failed advance replay changed state/history/diagnostics");replay_count+=1
            carried=actual.copy()
    owner.close();print("ROTATING_ADVANCE_PASS",count,replay_count)
