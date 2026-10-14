"""Cooperative component assembly with serial stage admission and coupled RHS."""
from std.memory import Pointer
from max.gpu import thread_idx
from max.gpu.sync import barrier
from .single_support_advance import support_rhs,dp_a,dp_b
from .support_intervals import next_up
comptime P=Pointer[Float64,MutAnyOrigin]
def opening_dp(x: P,y: P,h: Float64,dest: P,temp: P,slopes: P,stage_max: P,anchor: P,tube: P,report: P,work: P) -> Int:
    var lane=Int(thread_idx.x)
    for stage in range(7):
        if lane<21:
            var total=Float64(0)
            for k in range(stage):total+=dp_a(stage,k)*slopes[unsafe_offset=k*21+lane]
            work[unsafe_offset=lane]=y[unsafe_offset=lane]+h*total
        barrier()
        if lane==0:
            work[unsafe_offset=21]=0
            for j in range(21):
                temp[unsafe_offset=j]=work[unsafe_offset=j];stage_max[unsafe_offset=j]=max(stage_max[unsafe_offset=j],abs(temp[unsafe_offset=j]))
                if next_up(abs(temp[unsafe_offset=j]-anchor[unsafe_offset=j]))>tube[unsafe_offset=j]:
                    work[unsafe_offset=21]=2203;break
            if work[unsafe_offset=21]==0:
                report[unsafe_offset=300]+=1
                work[unsafe_offset=21]=Float64(support_rhs(x,temp,slopes+stage*21))
        barrier()
        if work[unsafe_offset=21]!=0:return Int(work[unsafe_offset=21])
    if lane<21:
        var total=Float64(0)
        for k in range(7):total+=dp_b(k)*slopes[unsafe_offset=k*21+lane]
        dest[unsafe_offset=lane]=y[unsafe_offset=lane]+h*total
    barrier()
    return 0
