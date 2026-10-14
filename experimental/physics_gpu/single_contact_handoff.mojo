"""Separate unique-contact extension around the frozen bounded floor handoff."""
from std.memory import Pointer
from std.math import isfinite
from .floor_handoff import floor_handoff
from .single_point_reaction import single_point_reaction

def single_contact_handoff(inputs: Pointer[Float64,MutAnyOrigin],previous: Pointer[Float64,MutAnyOrigin],request: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin],scratch: Pointer[Float64,MutAnyOrigin],status: Pointer[Float64,MutAnyOrigin]):
    for i in range(128):output[unsafe_offset=i]=previous[unsafe_offset=i]
    status[unsafe_offset=0]=0;status[unsafe_offset=1]=0
    for i in range(6):
        var key=request[unsafe_offset=2+i]
        if not isfinite(key) or key<1 or key>1e9 or key!=Float64(Int(key)) or (previous[unsafe_offset=96]!=0 and key!=previous[unsafe_offset=106+i]):status[unsafe_offset=0]=1413;return
    floor_handoff(inputs,previous,request,scratch+288,scratch,status)
    if status[unsafe_offset=0]!=0:return
    if scratch[unsafe_offset=386]==6 and scratch[unsafe_offset=393]==1:
        single_point_reaction(inputs,scratch+416)
        var code=scratch[unsafe_offset=455];var phase=Float64(0)
        if code==1403:
            if scratch[unsafe_offset=495]>1e-9:phase=13
            else:status[unsafe_offset=0]=1410;status[unsafe_offset=1]=code;return
        elif code!=0:status[unsafe_offset=0]=1412;status[unsafe_offset=1]=code;return
        else:
            var N=scratch[unsafe_offset=462];var q=scratch[unsafe_offset=464];var tol=scratch[unsafe_offset=472]
            if N>0 and q < -tol:phase=11
            elif N==0 and q>tol:phase=12
            elif N==0 and q==0 and inputs[unsafe_offset=13]==0 and inputs[unsafe_offset=15]==0 and inputs[unsafe_offset=16]==0 and inputs[unsafe_offset=17]==0 and inputs[unsafe_offset=19]==0 and inputs[unsafe_offset=43]==0:phase=14
            else:status[unsafe_offset=0]=1411;return
            for i in range(45,95):scratch[unsafe_offset=288+i]=scratch[unsafe_offset=416+i]
        scratch[unsafe_offset=386]=phase
    for i in range(128):output[unsafe_offset=i]=scratch[unsafe_offset=288+i]
    for i in range(6):output[unsafe_offset=106+i]=request[unsafe_offset=2+i]
