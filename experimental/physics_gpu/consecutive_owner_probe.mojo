"""Experimental second-macro probe from a provenance-verified qualified owner. No event replay."""
from std.memory import Pointer
from max.gpu import thread_idx
from max.gpu.sync import barrier
from std.math import isfinite,sqrt
from mojo_game import Vec3
from .dp_stage_cooperative import opening_dp
from .componentwise_cooperative import component_matrix,component_enclose
from .event_transport_cooperative import centered_event_uncertainty
from .event_centered_map import centered_rhs
from .event_uncertainty_reuse import bound_energy
from .single_support_advance import support_rhs,dp_a,dp_b,external_acc,support_arm,kinetic_state,interval_arm
from .opening_geometry_reuse import opening_bounds,support_row_bounds
from .support_intervals import Bound,Bound3,point,widen,plus,minus,times,divide,square,root,magnitude,norm3,next_up,next_down,fixed3,add3,scale3,cross3
comptime P = Pointer[Float64,MutAnyOrigin]

from .full_macro_dp_cooperative import cell_before,cell_errors,cell_after,finish
from .floor_handoff import handoff_bits

def owner_admission(inputs: P,previous: P,request: P,budget_previous: P,output: P,budget_output: P,scratch: P,status: P,report: P):
    for k in range(192):output[unsafe_offset=k]=previous[unsafe_offset=k];scratch[unsafe_offset=24576+k]=previous[unsafe_offset=k]
    for k in range(16384):budget_output[unsafe_offset=k]=budget_previous[unsafe_offset=k];scratch[unsafe_offset=33000+k]=budget_previous[unsafe_offset=k]
    for k in range(3072):scratch[unsafe_offset=24800+k]=budget_previous[unsafe_offset=k]
    for k in range(512):report[unsafe_offset=k]=0
    status[unsafe_offset=0]=2400;status[unsafe_offset=1]=0
    for k in range(96):
        if not isfinite(inputs[unsafe_offset=k]):return
    for k in range(192):
        if not isfinite(previous[unsafe_offset=k]):return
    for k in range(16384):
        if not isfinite(budget_previous[unsafe_offset=k]):return
    if previous[unsafe_offset=98]!=24 or previous[unsafe_offset=142]!=3 or previous[unsafe_offset=144]!=2201 or budget_previous[unsafe_offset=14015]!=1:return
    if previous[unsafe_offset=161]!=request[unsafe_offset=8] or previous[unsafe_offset=167]!=0 or previous[unsafe_offset=162]!=0:return
    if inputs[unsafe_offset=1]<=0 or inputs[unsafe_offset=2]<=0 or inputs[unsafe_offset=2]!=inputs[unsafe_offset=3] or inputs[unsafe_offset=2]!=inputs[unsafe_offset=4]:return
    for k in range(21,24):
        if inputs[unsafe_offset=k]!=0:return
    if inputs[unsafe_offset=35]!=0 or inputs[unsafe_offset=36]!=0:return
    for k in range(96):
        if (k<5 or (k>=18 and k<45 and k!=41)) and handoff_bits(inputs[unsafe_offset=k])!=handoff_bits(previous[unsafe_offset=k]):return
    var active=previous[unsafe_offset=131];var released=previous[unsafe_offset=132]
    if active<0 or active>7 or active!=Float64(Int(active)) or released<0 or released>7 or released!=Float64(Int(released)) or active==released:return
    if previous[unsafe_offset=41]!=active or previous[unsafe_offset=113]!=active or previous[unsafe_offset=112]!=released or previous[unsafe_offset=99]!=1:return
    for k in range(21):
        var idx=5+k if k<3 else 12+k-3 if k<6 else 8+k-6 if k<10 else 15+k-10 if k<13 else 133+k-13
        if handoff_bits(previous[unsafe_offset=idx])!=handoff_bits(budget_previous[unsafe_offset=14048+k]):return
        var E=budget_previous[unsafe_offset=14080+k];var R=budget_previous[unsafe_offset=14112+k];var T=budget_previous[unsafe_offset=14144+k];var B=budget_previous[unsafe_offset=15600+k]
        if E<0 or R<0 or T<0 or B<=0 or E>.5*B or R>.25*B or T>.25*B or E+R+T>.75*B:return
    if previous[unsafe_offset=148]!=budget_previous[unsafe_offset=14007] or previous[unsafe_offset=104]!=previous[unsafe_offset=148]:return
    var h=request[unsafe_offset=15];var H=previous[unsafe_offset=161]+h;var low=(previous[unsafe_offset=161]-(H-h))+(h-(H-previous[unsafe_offset=161]))
    # This prerequisite accepts exact two-macro clocks only; never drops a low word.
    if not isfinite(h) or h<=0 or h>1.0/30 or h!=previous[unsafe_offset=161] or low!=0 or request[unsafe_offset=17]!=16:return
    var cap=request[unsafe_offset=16]
    if not isfinite(cap) or cap<1 or cap>1008 or cap!=Float64(Int(cap)):return
    status[unsafe_offset=0]=0

def prepare(inputs: P,previous: P,request: P,budget_previous: P,output: P,budget_output: P,scratch: P,status: P,report: P):
    var h=request[unsafe_offset=15];var cap=request[unsafe_offset=16];var cells=request[unsafe_offset=17]
    var ev=scratch+24576;var old=scratch+24800;var c=scratch+33000
    report[unsafe_offset=0]=0
    if status[unsafe_offset=0]!=0:return
    var dt=Float64(0);var tau=previous[unsafe_offset=161];var prefix_rhs=Float64(0);var prefix_evals=Float64(0);var prefix_cells=Float64(0)
    var H=tau+h;var hlo=Float64(0);var span=next_up(h)
    c[unsafe_offset=3354]=hlo;c[unsafe_offset=3355]=H
    report[unsafe_offset=300]=0;report[unsafe_offset=301]=0;report[unsafe_offset=302]=0;report[unsafe_offset=303]=0
    var y=scratch+28000;var x=scratch+28100;var f=scratch+28200;var tube=scratch+28232;var zero=scratch+28264;var seed=scratch+28300;var rhs=scratch+28332;var E=scratch+28432;var R=scratch+28464;var T=scratch+28496;var L=scratch+28528;var full=scratch+28560;var half=scratch+28592;var dest=scratch+28624;var temp=scratch+28656;var slopes=scratch+28700;var maxima=scratch+28864;var ne=scratch+28900;var nr=scratch+28932;var nt=scratch+28964;var bounds=scratch+29000;var rad=scratch+29032;var anchor=scratch+31000
    for k in range(96):x[unsafe_offset=k]=inputs[unsafe_offset=k]
    x[unsafe_offset=40]=ev[unsafe_offset=131]
    var F=external_acc(inputs)*inputs[unsafe_offset=1];var Fy=plus(point(inputs[unsafe_offset=19]),times(point(inputs[unsafe_offset=43]),point(inputs[unsafe_offset=1])))
    for j in range(22):zero[unsafe_offset=j]=0;seed[unsafe_offset=j]=0
    for j in range(21):
        y[unsafe_offset=j]=budget_previous[unsafe_offset=14048+j];E[unsafe_offset=j]=budget_previous[unsafe_offset=14080+j];R[unsafe_offset=j]=budget_previous[unsafe_offset=14112+j];T[unsafe_offset=j]=budget_previous[unsafe_offset=14144+j]
        anchor[unsafe_offset=j]=y[unsafe_offset=j];c[unsafe_offset=3072+j]=y[unsafe_offset=j]
        c[unsafe_offset=3093+j]=E[unsafe_offset=j];c[unsafe_offset=3114+j]=R[unsafe_offset=j];c[unsafe_offset=3135+j]=T[unsafe_offset=j]
    if report[unsafe_offset=300]+1>cap:status[unsafe_offset=0]=2202;return
    var code=support_rhs(x,y,f);report[unsafe_offset=300]+=1;report[unsafe_offset=301]+=1
    if code!=0:status[unsafe_offset=0]=Float64(code);return
    for j in range(21):
        var initial=plus(plus(point(E[unsafe_offset=j]),point(R[unsafe_offset=j])),point(T[unsafe_offset=j])).hi
        tube[unsafe_offset=j]=plus(point(initial),times(plus(point(span),point(dt)),point(next_up(2*abs(f[unsafe_offset=j])+1)))).hi
    var included=False
    for attempt in range(4):
        if report[unsafe_offset=300]+21*cells>=cap or prefix_evals+report[unsafe_offset=301]+cells+1>48:status[unsafe_offset=0]=2202;return
        centered_rhs(x,y,tube,seed,rhs);report[unsafe_offset=300]+=1;report[unsafe_offset=301]+=1
        if rhs[unsafe_offset=52]<=0:status[unsafe_offset=0]=2203;return
        included=True
        for j in range(21):
            var initial=plus(plus(point(E[unsafe_offset=j]),point(R[unsafe_offset=j])),point(T[unsafe_offset=j]));var needed=plus(initial,times(plus(point(span),point(dt)),point(magnitude(Bound(rhs[unsafe_offset=4*j],rhs[unsafe_offset=4*j+1]))))).hi
            rad[unsafe_offset=j]=needed
            if needed>tube[unsafe_offset=j]:included=False
        if included:break
        for j in range(21):tube[unsafe_offset=j]=next_up(max(tube[unsafe_offset=j],rad[unsafe_offset=j]))
    if not included:status[unsafe_offset=0]=2203;return
    _ = support_row_bounds(x,y,tube,zero,rhs[unsafe_offset=53],L)
    var Lmax=Float64(0)
    for j in range(13):Lmax=max(Lmax,L[unsafe_offset=j])
    # Root uncertainty was already mapped to the first fixed endpoint. Carry it unchanged;
    # do not replay the event or reapply the shared-clock cancellation.
    for j in range(21):c[unsafe_offset=3156+j]=T[unsafe_offset=j];c[unsafe_offset=3177+j]=tube[unsafe_offset=j];c[unsafe_offset=3198+j]=L[unsafe_offset=j]
    for k in range(84):c[unsafe_offset=3264+k]=rhs[unsafe_offset=k]
    c[unsafe_offset=3348]=Lmax;c[unsafe_offset=3349]=h;c[unsafe_offset=3350]=budget_previous[unsafe_offset=3350];c[unsafe_offset=3351]=budget_previous[unsafe_offset=3351]
    var matrix=c+15000;var ue=scratch+29400;var ur=scratch+29432;var ut=scratch+29464;var compare_temp=scratch+29500;var compare_report=scratch+29532
    if report[unsafe_offset=300]+1>cap or prefix_rhs+report[unsafe_offset=300]+1>1008 or prefix_evals+report[unsafe_offset=301]+1>48:status[unsafe_offset=0]=2202;return
    code=component_matrix(x,y,tube,matrix,seed);report[unsafe_offset=300]+=1;report[unsafe_offset=301]+=1;report[unsafe_offset=304]=1;report[unsafe_offset=308]=5
    if code!=0:status[unsafe_offset=0]=Float64(code);return
    for j in range(21):rad[unsafe_offset=j]=plus(plus(point(E[unsafe_offset=j]),point(R[unsafe_offset=j])),point(T[unsafe_offset=j])).hi
    code=opening_bounds(x,y,0,rad,zero,bounds,Int(ev[unsafe_offset=132]))
    if code!=0:status[unsafe_offset=0]=Float64(code);return
    var reserved_gap=plus(point(bounds[unsafe_offset=0]),times(point(span),point(bounds[unsafe_offset=1]))).hi
    if reserved_gap>=1e-9:status[unsafe_offset=0]=2205;return
    var gaproom=1e-9-reserved_gap;var speedroom=1e-9-bounds[unsafe_offset=1];c[unsafe_offset=3352]=gaproom;c[unsafe_offset=3353]=speedroom
    var T0=.5*(inputs[unsafe_offset=1]*(inputs[unsafe_offset=12]*inputs[unsafe_offset=12]+inputs[unsafe_offset=13]*inputs[unsafe_offset=13]+inputs[unsafe_offset=14]*inputs[unsafe_offset=14])+inputs[unsafe_offset=2]*(inputs[unsafe_offset=15]*inputs[unsafe_offset=15]+inputs[unsafe_offset=16]*inputs[unsafe_offset=16]+inputs[unsafe_offset=17]*inputs[unsafe_offset=17]));var EB=1e-9*(1+T0);var elapsed=Float64(0)
    var enclosure_cache=compare_report+2;enclosure_cache[unsafe_offset=0]=0;enclosure_cache[unsafe_offset=1]=0
    # Smallest historical allowances remain in the copied certificate, without reset.
    scratch[unsafe_offset=60000]=h
    scratch[unsafe_offset=60001]=cap
    scratch[unsafe_offset=60002]=cells
    scratch[unsafe_offset=60003]=dt
    scratch[unsafe_offset=60004]=tau
    scratch[unsafe_offset=60005]=prefix_rhs
    scratch[unsafe_offset=60006]=prefix_evals
    scratch[unsafe_offset=60007]=prefix_cells
    scratch[unsafe_offset=60008]=H
    scratch[unsafe_offset=60009]=hlo
    scratch[unsafe_offset=60010]=span
    scratch[unsafe_offset=60011]=Lmax
    scratch[unsafe_offset=60012]=gaproom
    scratch[unsafe_offset=60013]=speedroom
    scratch[unsafe_offset=60014]=T0
    scratch[unsafe_offset=60015]=EB
    scratch[unsafe_offset=60016]=elapsed
    scratch[unsafe_offset=60017]=F.x;scratch[unsafe_offset=60018]=F.y;scratch[unsafe_offset=60019]=F.z;scratch[unsafe_offset=60020]=Fy.lo;scratch[unsafe_offset=60021]=Fy.hi

def continue_owner(inputs: P,previous: P,request: P,budget_previous: P,output: P,budget_output: P,scratch: P,status: P,report: P):
    var lane=Int(thread_idx.x)
    if lane==0:owner_admission(inputs,previous,request,budget_previous,output,budget_output,scratch,status,report)
    barrier()
    if status[unsafe_offset=0]!=0:return
    if lane==0:prepare(inputs,previous,request,budget_previous,output,budget_output,scratch,status,report)
    barrier()
    if status[unsafe_offset=0]!=0:return
    for n in range(16):
        if lane==0:cell_before(inputs,previous,request,budget_previous,output,budget_output,scratch,status,report,n)
        barrier()
        if status[unsafe_offset=0]!=0:return
        var cell=scratch[unsafe_offset=60024]
        var dp_code=opening_dp(scratch+28100,scratch+28000,cell,scratch+28560,scratch+28656,scratch+28700,scratch+28864,scratch+31000,scratch+28232,report,scratch+64500)
        if dp_code==0:dp_code=opening_dp(scratch+28100,scratch+28000,cell/2,scratch+28592,scratch+28656,scratch+28700,scratch+28864,scratch+31000,scratch+28232,report,scratch+64500)
        if dp_code==0:dp_code=opening_dp(scratch+28100,scratch+28592,cell/2,scratch+28624,scratch+28656,scratch+28700,scratch+28864,scratch+31000,scratch+28232,report,scratch+64500)
        if lane==0:cell_errors(inputs,previous,request,budget_previous,output,budget_output,scratch,status,report,n,dp_code)
        barrier()
        if status[unsafe_offset=0]!=0:return
        for category in range(3):
            var incoming=scratch+28900 if category==0 else scratch+28932 if category==1 else scratch+28964
            var result=scratch+29400 if category==0 else scratch+29432 if category==1 else scratch+29464
            var code=component_enclose(scratch+48000,incoming,scratch[unsafe_offset=60024],result,scratch+29500,12,scratch+29532,scratch+29534,scratch+60100)
            if lane==0:
                report[unsafe_offset=305]+=1;report[unsafe_offset=306]+=12;report[unsafe_offset=307]+=1
                scratch[unsafe_offset=33000+3456+n*512+286+2*category]=scratch[unsafe_offset=29532];scratch[unsafe_offset=33000+3456+n*512+287+2*category]=scratch[unsafe_offset=29533]
                if code!=0:status[unsafe_offset=0]=Float64(code)
            barrier()
            if status[unsafe_offset=0]!=0:return
        if lane==0:cell_after(inputs,previous,request,budget_previous,output,budget_output,scratch,status,report,n)
        barrier()
        if status[unsafe_offset=0]!=0:return
    if lane==0:finish(inputs,previous,request,budget_previous,output,budget_output,scratch,status,report)
    barrier()
    if lane==0 and status[unsafe_offset=0]==0:
        # New macro work is separately reported; trajectory totals are cumulative.
        for k in range(3):budget_output[unsafe_offset=15700+k]=budget_previous[unsafe_offset=14012+k]+budget_output[unsafe_offset=14012+k]
        budget_output[unsafe_offset=15703]=2;output[unsafe_offset=98]=25;output[unsafe_offset=144]=2401
    barrier()
