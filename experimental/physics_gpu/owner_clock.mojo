"""Checked error-free two-word time addition. Reject a nonzero third residual."""
from std.memory import Pointer
from std.math import isfinite
comptime P=Pointer[Float64,MutAnyOrigin]
def two_sum(a: Float64,b: Float64) -> Tuple[Float64,Float64]:
    var s=a+b;var v=s-a;var e=(a-(s-v))+(b-v)
    return s,e

def clock_add(hi: Float64,lo: Float64,step: Float64,result: P) -> Int:
    if not isfinite(hi) or not isfinite(lo) or not isfinite(step) or step<=0:return 2502
    var normalized=two_sum(hi,lo)
    if normalized[0]!=hi or normalized[1]!=lo:return 2502
    var a=two_sum(hi,step);var b=two_sum(lo,a[1]);var c=two_sum(a[0],b[0]);var d=two_sum(c[1],b[1])
    if d[1]!=0:return 2502
    var out=two_sum(c[0],d[0])
    if not isfinite(out[0]) or not isfinite(out[1]):return 2502
    result[unsafe_offset=0]=out[0];result[unsafe_offset=1]=out[1]
    return 0
