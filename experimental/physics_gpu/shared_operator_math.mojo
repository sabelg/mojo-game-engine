"""Shared placement of original mask operator values; arithmetic unchanged."""
from std.collections import Array
from std.memory import Pointer,AddressSpace
from std.math import isfinite
from .box_box_kernels import EPS
from .box_response_math import BlockSolution
comptime SharedOperator=Pointer[Float64,MutUntrackedOrigin,address_space=AddressSpace.SHARED]

def cached_normal_block_shared(k: Array[Float64,16],q: Array[Float64,4],operators: SharedOperator,valid_masks: Array[Bool,16],count: Int,tolerance: Float64) -> BlockSolution:
    var best=BlockSolution(Array[Float64,4](fill=0),False);var minimum=Float64(1e300)
    for mask in range(1<<count):
        if not valid_masks[mask]:continue
        var trial=BlockSolution(Array[Float64,4](fill=0),True);var scale=Float64(1)
        for i in range(count):
            for j in range(count):trial.impulse[i]-=operators[unsafe_offset=113+mask*16+i*4+j]*q[j]
            scale=max(scale,abs(trial.impulse[i]))
        var valid=True;var norm=Float64(0)
        for i in range(count):
            if not isfinite(trial.impulse[i]) or trial.impulse[i]<-128*EPS*scale or trial.impulse[i]>1e4:valid=False
            trial.impulse[i]=max(0.0,trial.impulse[i]);norm+=trial.impulse[i]*trial.impulse[i]
        for i in range(count):
            var residual=q[i]
            for j in range(count):residual+=k[i*4+j]*trial.impulse[j]
            if not isfinite(residual) or (abs(residual)>tolerance if trial.impulse[i]>0 else residual < -tolerance):valid=False
        if valid and norm<minimum:best=trial^;minimum=norm
    return best^
