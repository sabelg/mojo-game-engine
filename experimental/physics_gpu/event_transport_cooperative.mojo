"""Centered conditional event transport with separate carried categories and shared clock."""
from std.memory import Pointer
from max.gpu import thread_idx
from max.gpu.sync import barrier
from std.math import isfinite,sqrt
from .event_uncertainty_refined import event_uncertainty
from .event_centered_map import centered_map,centered_rhs
from .single_support_advance import support_rhs
from .support_intervals import Bound,point,plus,times,magnitude,next_up,next_down,root,square,divide
comptime P = Pointer[Float64,MutAnyOrigin]

def event_prepare(inputs: P,previous: P,request: P,budget_previous: P,output: P,budget_output: P,scratch: P,status: P,report: P):
    for k in range(192):output[unsafe_offset=k]=previous[unsafe_offset=k]
    for k in range(3072):budget_output[unsafe_offset=k]=budget_previous[unsafe_offset=k];scratch[unsafe_offset=16000+k]=0
    for k in range(256):report[unsafe_offset=k]=0
    status[unsafe_offset=0]=0;status[unsafe_offset=1]=0
    var factor=request[unsafe_offset=14]
    if not isfinite(factor) or factor<1 or factor>1e6:status[unsafe_offset=0]=2100;return
    event_uncertainty(inputs,previous,request,budget_previous,scratch+10000,scratch+10200,scratch,status,report)
    report[unsafe_offset=128]=status[unsafe_offset=0]
    if status[unsafe_offset=0]!=2004:return
    status[unsafe_offset=0]=0;status[unsafe_offset=1]=0
    var old=scratch+5200;var c=scratch+16000;var y=scratch+1120;var seed=scratch+10500;var radius=scratch+10532;var zeros=scratch+10564;var f=scratch+10600;var rhs=scratch+10640;var pointmap=scratch+10784;var result=scratch+11000
    var dt=old[unsafe_offset=185];var event=Int(scratch[unsafe_offset=131]);var phase=Int(scratch[unsafe_offset=98]);var tau=scratch[unsafe_offset=128]
    for j in range(22):seed[unsafe_offset=j]=0;zeros[unsafe_offset=j]=0
    for j in range(21):
        c[unsafe_offset=1+j]=old[unsafe_offset=1+j] if factor==1 else next_up(old[unsafe_offset=1+j]*factor);c[unsafe_offset=22+j]=old[unsafe_offset=22+j] if factor==1 else next_up(old[unsafe_offset=22+j]*factor);c[unsafe_offset=85+j]=old[unsafe_offset=43+j];radius[unsafe_offset=j]=next_up(old[unsafe_offset=64+j]*factor)
    var code=support_rhs(inputs,y,f)
    c[unsafe_offset=128]=report[unsafe_offset=3];c[unsafe_offset=129]=1;c[unsafe_offset=127]=dt
    if code!=0:status[unsafe_offset=0]=2101;return
    # A finite Picard enclosure iteration may only enlarge the initial candidate.
    var included=False
    for attempt in range(4):
        centered_rhs(inputs,y,radius,seed,rhs);c[unsafe_offset=129]+=1
        if rhs[unsafe_offset=4*13]<=0:status[unsafe_offset=0]=2101;return
        included=True
        for j in range(21):
            c[unsafe_offset=2700+j]=radius[unsafe_offset=j]
            var bound=Bound(rhs[unsafe_offset=4*j],rhs[unsafe_offset=4*j+1]);var tight=plus(plus(point(c[unsafe_offset=1+j]),point(c[unsafe_offset=22+j])),times(point(dt),point(magnitude(bound)))).hi
            c[unsafe_offset=43+j]=f[unsafe_offset=j];c[unsafe_offset=64+j]=times(point(dt),point(next_up(max(abs(bound.lo-f[unsafe_offset=j]),abs(bound.hi-f[unsafe_offset=j]))))).hi;c[unsafe_offset=106+j]=tight
            if not isfinite(tight):status[unsafe_offset=0]=2102;return
            if tight>radius[unsafe_offset=j]:included=False
        for j in range(84):c[unsafe_offset=2721+j]=rhs[unsafe_offset=j]
        if included:break
        for j in range(21):radius[unsafe_offset=j]=next_up(max(radius[unsafe_offset=j],c[unsafe_offset=106+j]))
    if not included:status[unsafe_offset=0]=2102;return
    for j in range(21):radius[unsafe_offset=j]=c[unsafe_offset=106+j]
    centered_map(inputs,y,zeros,seed,tau,tau,event,phase,pointmap)
    # Point rounding enclosure is charged to noise; the nominal native body is unchanged.
    for i in range(45):
        var center=(pointmap[unsafe_offset=4*i]+pointmap[unsafe_offset=4*i+1])*.5
        if i<3:center=scratch[unsafe_offset=5+i]
        elif i<6:center=scratch[unsafe_offset=12+i-3]
        elif i<10:center=scratch[unsafe_offset=8+i-6]
        elif i<13:center=scratch[unsafe_offset=15+i-10]
        elif i==13:center=scratch[unsafe_offset=103]
        elif i==14:center=scratch[unsafe_offset=104]
        elif i==15:center=scratch[unsafe_offset=46]
        elif i==16:center=scratch[unsafe_offset=48]
        elif i==17:center=scratch[unsafe_offset=114]
        elif i==18:center=scratch[unsafe_offset=115]
        elif i<27:center=scratch[unsafe_offset=81+i-19]
        elif i==28:center=scratch[unsafe_offset=147]
        elif i>=32 and i<=40:center=scratch[unsafe_offset=149+i-32]
        elif i==41:center=scratch[unsafe_offset=137]
        elif i==42:center=scratch[unsafe_offset=53]
        c[unsafe_offset=160+i]=center;var rho=next_up(max(abs(pointmap[unsafe_offset=4*i]-center),abs(pointmap[unsafe_offset=4*i+1]-center)));c[unsafe_offset=250+i]=rho;c[unsafe_offset=647+i]=rho

def event_finish(inputs: P,previous: P,request: P,budget_previous: P,output: P,budget_output: P,scratch: P,status: P,report: P):
    var old=scratch+5200;var c=scratch+16000;var y=scratch+1120;var seed=scratch+10500;var radius=scratch+10532;var zeros=scratch+10564;var f=scratch+10600;var rhs=scratch+10640;var pointmap=scratch+10784;var result=scratch+11000
    var dt=old[unsafe_offset=185];var event=Int(scratch[unsafe_offset=131]);var phase=Int(scratch[unsafe_offset=98]);var tau=scratch[unsafe_offset=128]
    var factor=request[unsafe_offset=14]
    for j in range(21):
        result=scratch+60200+j*202+22
        for i in range(45):
            var lo=result[unsafe_offset=4*i+2];var hi=result[unsafe_offset=4*i+3];var a=max(abs(lo),abs(hi));var k=768+2*(i*21+j);c[unsafe_offset=k]=lo;c[unsafe_offset=k+1]=hi
            c[unsafe_offset=205+i]=plus(point(c[unsafe_offset=205+i]),times(point(a),point(c[unsafe_offset=1+j]))).hi;c[unsafe_offset=250+i]=plus(point(c[unsafe_offset=250+i]),times(point(a),point(c[unsafe_offset=22+j]))).hi;c[unsafe_offset=602+i]=plus(point(c[unsafe_offset=602+i]),times(point(a),point(c[unsafe_offset=64+j]))).hi
    result=scratch+11000
    for j in range(21):seed[unsafe_offset=j]=f[unsafe_offset=j]
    seed[unsafe_offset=21]=1
    centered_map(inputs,y,radius,seed,tau,tau+dt,event,phase,result)
    var T0=.5*(inputs[unsafe_offset=1]*(inputs[unsafe_offset=12]*inputs[unsafe_offset=12]+inputs[unsafe_offset=13]*inputs[unsafe_offset=13]+inputs[unsafe_offset=14]*inputs[unsafe_offset=14])+inputs[unsafe_offset=2]*(inputs[unsafe_offset=15]*inputs[unsafe_offset=15]+inputs[unsafe_offset=16]*inputs[unsafe_offset=16]+inputs[unsafe_offset=17]*inputs[unsafe_offset=17]));var EB=1e-9*(1+T0);var Eroom=next_down(EB-abs(scratch[unsafe_offset=137]));var ratios=scratch+11200
    for k in range(4):ratios[unsafe_offset=k]=0
    var stable=True;var limiting= -1;var maxratio=Float64(0)
    for i in range(45):
        var dir=Bound(result[unsafe_offset=4*i+2],result[unsafe_offset=4*i+3]);c[unsafe_offset=512+2*i]=dir.lo;c[unsafe_offset=513+2*i]=dir.hi
        c[unsafe_offset=295+i]=plus(times(point(dt),point(magnitude(dir))),point(c[unsafe_offset=602+i])).hi
        var E=c[unsafe_offset=205+i];var R=c[unsafe_offset=250+i];var T=c[unsafe_offset=295+i];var center=c[unsafe_offset=160+i];var total=plus(plus(point(E),point(R)),point(T)).hi;c[unsafe_offset=340+i]=next_down(center-total);c[unsafe_offset=385+i]=next_up(center+total)
        var B=1e-10*(1+abs(center))
        if i<13:
            var j=5+i if i<3 else 12+i-3 if i<6 else 8+i-6 if i<10 else 15+i-10
            B=1e-10*(1+min(abs(inputs[unsafe_offset=j]),abs(center)))
        elif i==27:B=1e-10-abs(center-1)
        elif i==28 or i==29 or i==30 or i==31 or i==41:B=Eroom
        elif i>=32 and i<=40:
            var start=32+((i-32)//3)*3;var size=sqrt(c[unsafe_offset=160+start]*c[unsafe_offset=160+start]+c[unsafe_offset=161+start]*c[unsafe_offset=161+start]+c[unsafe_offset=162+start]*c[unsafe_offset=162+start]);B=1e-10*(1+size)
        B=next_down(B)
        c[unsafe_offset=430+i]=B
        if B<=0:stable=False;continue
        var er=divide(point(E),times(point(.5),point(B))).hi;var nr=divide(point(R),times(point(.25),point(B))).hi;var tr=divide(point(T),times(point(.25),point(B))).hi;var joint=divide(point(total),times(point(.75),point(B))).hi;ratios[unsafe_offset=0]=max(ratios[unsafe_offset=0],er);ratios[unsafe_offset=1]=max(ratios[unsafe_offset=1],nr);ratios[unsafe_offset=2]=max(ratios[unsafe_offset=2],tr);ratios[unsafe_offset=3]=max(ratios[unsafe_offset=3],joint)
        var rr=max(max(er,nr),max(tr,joint))
        if rr>maxratio:maxratio=rr;limiting=i
    # Vector gates use Euclidean norms of each transported category and their sum.
    for g in range(3):
        var start=32+3*g;var B=c[unsafe_offset=430+start];var E=point(0);var R=point(0);var T=point(0)
        for k in range(3):E=plus(E,square(point(c[unsafe_offset=205+start+k])));R=plus(R,square(point(c[unsafe_offset=250+start+k])));T=plus(T,square(point(c[unsafe_offset=295+start+k])))
        E=root(E);R=root(R);T=root(T);ratios[unsafe_offset=0]=max(ratios[unsafe_offset=0],divide(E,times(point(.5),point(B))).hi);ratios[unsafe_offset=1]=max(ratios[unsafe_offset=1],divide(R,times(point(.25),point(B))).hi);ratios[unsafe_offset=2]=max(ratios[unsafe_offset=2],divide(T,times(point(.25),point(B))).hi);ratios[unsafe_offset=3]=max(ratios[unsafe_offset=3],divide(plus(plus(E,R),T),times(point(.75),point(B))).hi)
    stable=stable and c[unsafe_offset=340+13]>0 and c[unsafe_offset=385+43]< -1e-9 and max(abs(c[unsafe_offset=340+44]),abs(c[unsafe_offset=385+44]))<=1e-9 and c[unsafe_offset=340+17]>1e-9 and max(abs(c[unsafe_offset=340+18]),abs(c[unsafe_offset=385+18]))<=1e-9 and c[unsafe_offset=340+42]>1e-4
    stable=stable and c[unsafe_offset=340+27]>=1-1e-10 and c[unsafe_offset=385+27]<=1+1e-10
    var qsize=max(abs(c[unsafe_offset=340+16]),abs(c[unsafe_offset=385+16]))
    if phase==21:stable=stable and c[unsafe_offset=385+16]< -1e-9*(1+qsize) and c[unsafe_offset=340+15]>0
    elif phase==22:stable=stable and c[unsafe_offset=340+16]>1e-9*(1+qsize)
    else:stable=False
    for j in range(8):
        if j==Int(inputs[unsafe_offset=40]) or j==event:stable=stable and max(abs(c[unsafe_offset=340+19+j]),abs(c[unsafe_offset=385+19+j]))<=1e-9
        else:stable=stable and c[unsafe_offset=340+19+j]>1e-9
    for i in range(13):
        if i<6 or i>=10:
            var limit=1000 if i<3 else 20 if i<6 else 10
            stable=stable and max(abs(c[unsafe_offset=340+i]),abs(c[unsafe_offset=385+i]))<=Float64(limit)
    var energy_error=max(abs(c[unsafe_offset=340+30]),abs(c[unsafe_offset=385+30]));var ideal_error=max(abs(c[unsafe_offset=340+31]),abs(c[unsafe_offset=385+31]));var work_error=max(abs(c[unsafe_offset=340+41]),abs(c[unsafe_offset=385+41]))
    c[unsafe_offset=0]=1;c[unsafe_offset=134]=Float64(limiting);c[unsafe_offset=135]=1 if stable else 0;c[unsafe_offset=136]=EB;c[unsafe_offset=137]=Eroom;c[unsafe_offset=138]=(energy_error+work_error)/EB;c[unsafe_offset=139]=ideal_error/EB;c[unsafe_offset=140]=23+c[unsafe_offset=129]-1;c[unsafe_offset=141]=factor
    for k in range(4):c[unsafe_offset=130+k]=ratios[unsafe_offset=k];report[unsafe_offset=129+k]=ratios[unsafe_offset=k]
    report[unsafe_offset=133]=1 if stable else 0;report[unsafe_offset=134]=Float64(limiting);report[unsafe_offset=135]=report[unsafe_offset=3]+c[unsafe_offset=129];report[unsafe_offset=136]=0
    if not stable:status[unsafe_offset=0]=2103;return
    if max(max(ratios[unsafe_offset=0],ratios[unsafe_offset=1]),max(ratios[unsafe_offset=2],ratios[unsafe_offset=3]))>1 or next_up(energy_error+work_error)>EB or ideal_error>EB:status[unsafe_offset=0]=2104;return
    for k in range(192):output[unsafe_offset=k]=scratch[unsafe_offset=k]
    for k in range(3072):budget_output[unsafe_offset=k]=c[unsafe_offset=k]
    report[unsafe_offset=136]=1

def centered_event_uncertainty(inputs: P,previous: P,request: P,budget_previous: P,output: P,budget_output: P,scratch: P,status: P,report: P):
    var lane=Int(thread_idx.x)
    if lane==0:event_prepare(inputs,previous,request,budget_previous,output,budget_output,scratch,status,report)
    barrier()
    if status[unsafe_offset=0]!=0:return
    if lane<21:
        var seed=scratch+60200+lane*202;var result=seed+22
        for j in range(22):seed[unsafe_offset=j]=0
        seed[unsafe_offset=lane]=1
        var tau=scratch[unsafe_offset=128];var dt=scratch[unsafe_offset=5200+185]
        centered_map(inputs,scratch+1120,scratch+10532,seed,tau,tau+dt,Int(scratch[unsafe_offset=131]),Int(scratch[unsafe_offset=98]),result)
    barrier()
    if lane==0:event_finish(inputs,previous,request,budget_previous,output,budget_output,scratch,status,report)
    barrier()
