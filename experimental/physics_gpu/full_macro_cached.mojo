"""Bounded full-macro experiment; atomic rollback on any failed enclosure or accuracy gate."""
from std.memory import Pointer
from std.math import isfinite,sqrt
from mojo_game import Vec3
from .componentwise_cached import component_matrix,component_enclose
from .event_centered_uncertainty_refined import centered_event_uncertainty
from .event_centered_map import centered_rhs
from .event_uncertainty_reuse import bound_energy
from .single_support_advance import support_rhs,dp_a,dp_b,external_acc,support_arm,kinetic_state,interval_arm
from .opening_window_bounds import opening_bounds,support_row_bounds
from .support_intervals import Bound,Bound3,point,widen,plus,minus,times,divide,square,root,magnitude,norm3,next_up,next_down,fixed3,add3,scale3,cross3
comptime P = Pointer[Float64,MutAnyOrigin]

def opening_dp(x: P,y: P,h: Float64,dest: P,temp: P,slopes: P,stage_max: P,anchor: P,tube: P,report: P) -> Int:
    for stage in range(7):
        for j in range(21):
            var total=Float64(0)
            for k in range(stage):total+=dp_a(stage,k)*slopes[unsafe_offset=k*21+j]
            temp[unsafe_offset=j]=y[unsafe_offset=j]+h*total;stage_max[unsafe_offset=j]=max(stage_max[unsafe_offset=j],abs(temp[unsafe_offset=j]))
            if next_up(abs(temp[unsafe_offset=j]-anchor[unsafe_offset=j]))>tube[unsafe_offset=j]:return 2203
        report[unsafe_offset=300]+=1
        var code=support_rhs(x,temp,slopes+stage*21)
        if code!=0:return code
    for j in range(21):
        var total=Float64(0)
        for k in range(7):total+=dp_b(k)*slopes[unsafe_offset=k*21+j]
        dest[unsafe_offset=j]=y[unsafe_offset=j]+h*total
    return 0

def shared_clock_opening(inputs: P,previous: P,request: P,budget_previous: P,output: P,budget_output: P,scratch: P,status: P,report: P):
    for k in range(192):output[unsafe_offset=k]=previous[unsafe_offset=k]
    for k in range(16384):budget_output[unsafe_offset=k]=budget_previous[unsafe_offset=k];scratch[unsafe_offset=33000+k]=0
    for k in range(256):scratch[unsafe_offset=5200+k]=0
    for k in range(512):report[unsafe_offset=k]=0
    status[unsafe_offset=0]=0;status[unsafe_offset=1]=0
    var h=request[unsafe_offset=15];var cap=request[unsafe_offset=16];var cells=request[unsafe_offset=17]
    if not isfinite(h) or h<=0 or h>1.0/30 or not isfinite(cap) or cap<1 or cap>1008 or cap!=Float64(Int(cap)) or not isfinite(cells) or cells<1 or cells>16 or cells!=Float64(Int(cells)):status[unsafe_offset=0]=2200;return
    if cap<5:status[unsafe_offset=0]=2202;return
    if not isfinite(request[unsafe_offset=9]) or request[unsafe_offset=9]<1 or request[unsafe_offset=9]>256 or request[unsafe_offset=9]!=Float64(Int(request[unsafe_offset=9])) or not isfinite(request[unsafe_offset=10]) or request[unsafe_offset=10]<1 or request[unsafe_offset=10]>64 or request[unsafe_offset=10]!=Float64(Int(request[unsafe_offset=10])):status[unsafe_offset=0]=1600;return
    var private_request=scratch+29200
    for k in range(18):private_request[unsafe_offset=k]=request[unsafe_offset=k]
    private_request[unsafe_offset=9]=min(request[unsafe_offset=9],48.0-cells-11.0);private_request[unsafe_offset=10]=min(request[unsafe_offset=10],23.0-cells)
    var ev=scratch+24576;var old=scratch+24800;var c=scratch+33000
    centered_event_uncertainty(inputs,previous,private_request,budget_previous,ev,old,scratch,status,report)
    report[unsafe_offset=0]=0
    if status[unsafe_offset=0]!=0:return
    for k in range(3072):c[unsafe_offset=k]=old[unsafe_offset=k]
    for k in range(192):c[unsafe_offset=14400+k]=ev[unsafe_offset=k]
    var dt=old[unsafe_offset=127];var tau=ev[unsafe_offset=128];var prefix_rhs=report[unsafe_offset=3];var prefix_evals=report[unsafe_offset=2];var prefix_cells=report[unsafe_offset=1]+1
    var H=request[unsafe_offset=8]
    if h!=ev[unsafe_offset=143] or h!=H or cells!=16:status[unsafe_offset=0]=2200;return
    h=H-tau
    var hlo=(-tau)-(h-H)
    var span=next_up(h+abs(hlo))
    c[unsafe_offset=3354]=hlo;c[unsafe_offset=3355]=H
    report[unsafe_offset=300]=old[unsafe_offset=129];report[unsafe_offset=301]=old[unsafe_offset=129];report[unsafe_offset=302]=0;report[unsafe_offset=303]=0
    if ev[unsafe_offset=98]!=21 or h<=dt or h!=ev[unsafe_offset=141] or prefix_evals+old[unsafe_offset=129]+6>48 or prefix_cells+cells>24:status[unsafe_offset=0]=2201;return
    var y=scratch+28000;var x=scratch+28100;var f=scratch+28200;var tube=scratch+28232;var zero=scratch+28264;var seed=scratch+28300;var rhs=scratch+28332;var E=scratch+28432;var R=scratch+28464;var T=scratch+28496;var L=scratch+28528;var full=scratch+28560;var half=scratch+28592;var dest=scratch+28624;var temp=scratch+28656;var slopes=scratch+28700;var maxima=scratch+28864;var ne=scratch+28900;var nr=scratch+28932;var nt=scratch+28964;var bounds=scratch+29000;var rad=scratch+29032;var anchor=scratch+31000
    for k in range(96):x[unsafe_offset=k]=inputs[unsafe_offset=k]
    x[unsafe_offset=40]=ev[unsafe_offset=131]
    var F=external_acc(inputs)*inputs[unsafe_offset=1];var Fy=plus(point(inputs[unsafe_offset=19]),times(point(inputs[unsafe_offset=43]),point(inputs[unsafe_offset=1])))
    for j in range(22):zero[unsafe_offset=j]=0;seed[unsafe_offset=j]=0
    for j in range(21):
        var i=j if j<13 else 33 if j==13 else 35+j-14 if j<17 else 41 if j==17 else 38+j-18
        y[unsafe_offset=j]=old[unsafe_offset=160+i];E[unsafe_offset=j]=old[unsafe_offset=205+i];R[unsafe_offset=j]=old[unsafe_offset=250+i];T[unsafe_offset=j]=old[unsafe_offset=295+i]
        if j==13:
            y[unsafe_offset=j]=ev[unsafe_offset=133]+ev[unsafe_offset=103]
            T[unsafe_offset=j]=plus(point(T[unsafe_offset=j]),times(point(dt),point(magnitude(Fy)))).hi
            R[unsafe_offset=j]=plus(point(R[unsafe_offset=j]),point(64*2.220446049250313e-16*(1+abs(y[unsafe_offset=j])))).hi
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
    for j in range(21):
        var i=j if j<13 else 33 if j==13 else 35+j-14 if j<17 else 41 if j==17 else 38+j-18
        var direction=Bound(old[unsafe_offset=512+2*i],old[unsafe_offset=513+2*i])
        if j==13:direction=minus(direction,Fy)
        var common=minus(direction,Bound(rhs[unsafe_offset=4*j],rhs[unsafe_offset=4*j+1]))
        T[unsafe_offset=j]=plus(times(point(dt),point(magnitude(common))),point(old[unsafe_offset=602+i])).hi
        c[unsafe_offset=3156+j]=T[unsafe_offset=j];c[unsafe_offset=3177+j]=tube[unsafe_offset=j];c[unsafe_offset=3198+j]=L[unsafe_offset=j];c[unsafe_offset=3220+2*j]=common.lo;c[unsafe_offset=3221+2*j]=common.hi
    for k in range(84):c[unsafe_offset=3264+k]=rhs[unsafe_offset=k]
    c[unsafe_offset=3348]=Lmax;c[unsafe_offset=3349]=h;c[unsafe_offset=3350]=dt;c[unsafe_offset=3351]=tau
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
    for j in range(21):c[unsafe_offset=15600+j]=1e30
    for n in range(16):
        var cell=h/16
        if n==15:
            var basecell=cell;cell+=hlo
            if cell-basecell!=hlo:status[unsafe_offset=0]=2207;return
        var denominator=minus(point(1),times(point(cell),point(Lmax)))
        if denominator.lo<=0:status[unsafe_offset=0]=2203;return
        var local_fraction=divide(point(cell),point(H)).lo

        if n>=Int(cells) or report[unsafe_offset=300]+21>cap or prefix_evals+report[unsafe_offset=301]+Float64(n)+1>48 or prefix_rhs+report[unsafe_offset=300]+21>1008:status[unsafe_offset=0]=2202;return
        var record=c+3456+n*512;record[unsafe_offset=285]=cell
        for j in range(21):record[unsafe_offset=j]=y[unsafe_offset=j];record[unsafe_offset=21+j]=E[unsafe_offset=j];record[unsafe_offset=42+j]=R[unsafe_offset=j];record[unsafe_offset=63+j]=T[unsafe_offset=j];maxima[unsafe_offset=j]=abs(y[unsafe_offset=j])
        code=opening_dp(x,y,cell,full,temp,slopes,maxima,anchor,tube,report)
        if code==0:code=opening_dp(x,y,cell/2,half,temp,slopes,maxima,anchor,tube,report)
        if code==0:code=opening_dp(x,half,cell/2,dest,temp,slopes,maxima,anchor,tube,report)
        report[unsafe_offset=302]+=1
        if code!=0:status[unsafe_offset=0]=Float64(code);return
        var em=Float64(0);var rm=Float64(0);var tm=Float64(0)
        for j in range(21):
            var le=next_up(8*abs(dest[unsafe_offset=j]-full[unsafe_offset=j])/31);var lr=next_up(64*2.220446049250313e-16*(1+max(maxima[unsafe_offset=j],max(abs(full[unsafe_offset=j]),max(abs(half[unsafe_offset=j]),abs(dest[unsafe_offset=j]))))))
            ne[unsafe_offset=j]=plus(point(E[unsafe_offset=j]),point(le)).hi;nr[unsafe_offset=j]=plus(point(R[unsafe_offset=j]),point(lr)).hi;nt[unsafe_offset=j]=T[unsafe_offset=j];record[unsafe_offset=84+j]=le;record[unsafe_offset=105+j]=lr;record[unsafe_offset=126+j]=full[unsafe_offset=j];record[unsafe_offset=147+j]=half[unsafe_offset=j]
        for category in range(3):
            var incoming=ne if category==0 else nr if category==1 else nt;var result=ue if category==0 else ur if category==1 else ut
            code=component_enclose(matrix,incoming,cell,result,compare_temp,12,compare_report,enclosure_cache);report[unsafe_offset=305]+=1;report[unsafe_offset=306]+=12;report[unsafe_offset=307]+=1
            record[unsafe_offset=286+2*category]=compare_report[unsafe_offset=0];record[unsafe_offset=287+2*category]=compare_report[unsafe_offset=1]
            if code!=0:status[unsafe_offset=0]=Float64(code);return
        for j in range(21):
            ne[unsafe_offset=j]=ue[unsafe_offset=j];nr[unsafe_offset=j]=ur[unsafe_offset=j];nt[unsafe_offset=j]=ut[unsafe_offset=j]
            rad[unsafe_offset=j]=plus(plus(point(ne[unsafe_offset=j]),point(nr[unsafe_offset=j])),point(nt[unsafe_offset=j])).hi
            var initial=inputs[unsafe_offset=5+j] if j<3 else inputs[unsafe_offset=12+j-3] if j<6 else inputs[unsafe_offset=8+j-6] if j<10 else inputs[unsafe_offset=15+j-10] if j<13 else Float64(0)
            var B=times(point(1e-10),plus(point(1),point(min(abs(initial),min(abs(anchor[unsafe_offset=j]),abs(dest[unsafe_offset=j])))))).lo
            if j==17:B=next_down(EB-abs(dest[unsafe_offset=j]))
            B=min(B,c[unsafe_offset=15600+j]);c[unsafe_offset=15600+j]=B
            record[unsafe_offset=168+j]=dest[unsafe_offset=j];record[unsafe_offset=189+j]=ne[unsafe_offset=j];record[unsafe_offset=210+j]=nr[unsafe_offset=j];record[unsafe_offset=231+j]=nt[unsafe_offset=j];record[unsafe_offset=252+j]=B
            if B<=0 or ne[unsafe_offset=j]>.5*B or nr[unsafe_offset=j]>.25*B or nt[unsafe_offset=j]>.25*B or rad[unsafe_offset=j]>.75*B or record[unsafe_offset=84+j]>.5*B*local_fraction or record[unsafe_offset=105+j]>.25*B*local_fraction:status[unsafe_offset=0]=2205;status[unsafe_offset=1]=Float64(j);return
            if plus(point(abs(dest[unsafe_offset=j]-anchor[unsafe_offset=j])),point(rad[unsafe_offset=j])).hi>tube[unsafe_offset=j]:status[unsafe_offset=0]=2203;return
        code=opening_bounds(x,y,cell,rad,zero,bounds,Int(ev[unsafe_offset=132]))
        for j in range(5):record[unsafe_offset=280+j]=bounds[unsafe_offset=j]
        if code!=0:status[unsafe_offset=0]=Float64(code);return
        if bounds[unsafe_offset=0]>1e-9-.25*gaproom or bounds[unsafe_offset=1]>1e-9-.25*speedroom:status[unsafe_offset=0]=2205;return
        for j in range(21):y[unsafe_offset=j]=dest[unsafe_offset=j];E[unsafe_offset=j]=ne[unsafe_offset=j];R[unsafe_offset=j]=nr[unsafe_offset=j];T[unsafe_offset=j]=nt[unsafe_offset=j]
        elapsed+=cell;report[unsafe_offset=303]+=1
    if report[unsafe_offset=300]+1>cap or prefix_evals+report[unsafe_offset=301]+report[unsafe_offset=302]+1>48 or prefix_rhs+report[unsafe_offset=300]+1>1008:status[unsafe_offset=0]=2202;return
    code=support_rhs(x,y,f);report[unsafe_offset=300]+=1;report[unsafe_offset=301]+=1
    if code!=0:status[unsafe_offset=0]=Float64(code);return
    # Final physical balances use the original entry and event loss exactly once.
    var p=Vec3(y[unsafe_offset=0],y[unsafe_offset=1],y[unsafe_offset=2]);var v=Vec3(y[unsafe_offset=3],y[unsafe_offset=4],y[unsafe_offset=5]);var w=Vec3(y[unsafe_offset=10],y[unsafe_offset=11],y[unsafe_offset=12]);var p0=Vec3(inputs[unsafe_offset=5],inputs[unsafe_offset=6],inputs[unsafe_offset=7]);var v0=Vec3(inputs[unsafe_offset=12],inputs[unsafe_offset=13],inputs[unsafe_offset=14]);var w0=Vec3(inputs[unsafe_offset=15],inputs[unsafe_offset=16],inputs[unsafe_offset=17]);var m=inputs[unsafe_offset=1];var I=inputs[unsafe_offset=2];var endpoint=H;var J=F*endpoint+Vec3(0,y[unsafe_offset=13],0);var M=Vec3(y[unsafe_offset=14],y[unsafe_offset=15],y[unsafe_offset=16]);var O=Vec3(y[unsafe_offset=18],y[unsafe_offset=19],y[unsafe_offset=20]);var ext=F.dot(p-p0);var delta=kinetic_state(inputs,y)-T0;var loss=ev[unsafe_offset=148];var balance=abs(delta-ext-y[unsafe_offset=17]+loss);var ideal=abs(delta-ext+loss);var pe=((v-v0)*m-J).length();var me=((w-w0)*I-M).length();var oe=((w-w0)*I+p.cross(v*m)-p0.cross(v0*m)-O).length()
    c[unsafe_offset=14000]=balance;c[unsafe_offset=14001]=ideal;c[unsafe_offset=14002]=pe;c[unsafe_offset=14003]=me;c[unsafe_offset=14004]=oe;c[unsafe_offset=14005]=ext;c[unsafe_offset=14006]=delta;c[unsafe_offset=14007]=loss;c[unsafe_offset=14008]=EB
    if balance+abs(y[unsafe_offset=17])>EB or ideal>EB or pe>1e-10*(1+J.length()) or me>1e-10*(1+M.length()) or oe>1e-10*(1+O.length()):status[unsafe_offset=0]=2206;return
    # Enclose cumulative conservation residuals, including immutable event-loss uncertainty.
    var pb=Bound3(widen(y[unsafe_offset=0],rad[unsafe_offset=0]),widen(y[unsafe_offset=1],rad[unsafe_offset=1]),widen(y[unsafe_offset=2],rad[unsafe_offset=2]));var vb=Bound3(widen(y[unsafe_offset=3],rad[unsafe_offset=3]),widen(y[unsafe_offset=4],rad[unsafe_offset=4]),widen(y[unsafe_offset=5],rad[unsafe_offset=5]));var wb=Bound3(widen(y[unsafe_offset=10],rad[unsafe_offset=10]),widen(y[unsafe_offset=11],rad[unsafe_offset=11]),widen(y[unsafe_offset=12],rad[unsafe_offset=12]));var fb=Bound3(plus(point(inputs[unsafe_offset=18]),times(point(m),point(inputs[unsafe_offset=42]))),Fy,plus(point(inputs[unsafe_offset=20]),times(point(m),point(inputs[unsafe_offset=44]))));var displacement=add3(pb,fixed3(-p0.x,-p0.y,-p0.z));var extb=plus(plus(times(fb.x,displacement.x),times(fb.y,displacement.y)),times(fb.z,displacement.z));var initial_energy=bound_energy(m,I,fixed3(v0.x,v0.y,v0.z),fixed3(w0.x,w0.y,w0.z));var delta_bound=minus(bound_energy(m,I,vb,wb),initial_energy);var lossrad=plus(plus(point(old[unsafe_offset=219]),point(old[unsafe_offset=264])),point(old[unsafe_offset=309])).hi;var lossb=widen(loss,lossrad);var workb=widen(y[unsafe_offset=17],rad[unsafe_offset=17]);var idealb=plus(minus(delta_bound,extb),lossb);var balanceb=minus(idealb,workb);var totaljb=add3(scale3(fb,point(H)),Bound3(point(0),widen(y[unsafe_offset=13],rad[unsafe_offset=13]),point(0)));var totalmb=Bound3(widen(y[unsafe_offset=14],rad[unsafe_offset=14]),widen(y[unsafe_offset=15],rad[unsafe_offset=15]),widen(y[unsafe_offset=16],rad[unsafe_offset=16]));var totalob=Bound3(widen(y[unsafe_offset=18],rad[unsafe_offset=18]),widen(y[unsafe_offset=19],rad[unsafe_offset=19]),widen(y[unsafe_offset=20],rad[unsafe_offset=20]));var linear=add3(scale3(add3(vb,fixed3(-v0.x,-v0.y,-v0.z)),point(m)),scale3(totaljb,point(-1)));var angular=add3(scale3(add3(wb,fixed3(-w0.x,-w0.y,-w0.z)),point(I)),scale3(totalmb,point(-1)));var origin_balance=add3(add3(scale3(add3(wb,fixed3(-w0.x,-w0.y,-w0.z)),point(I)),add3(cross3(pb,scale3(vb,point(m))),scale3(cross3(fixed3(p0.x,p0.y,p0.z),scale3(fixed3(v0.x,v0.y,v0.z),point(m))),point(-1)))),scale3(totalob,point(-1)))
    c[unsafe_offset=14176]=balanceb.lo;c[unsafe_offset=14177]=balanceb.hi;c[unsafe_offset=14178]=idealb.lo;c[unsafe_offset=14179]=idealb.hi;c[unsafe_offset=14180]=workb.lo;c[unsafe_offset=14181]=workb.hi;c[unsafe_offset=14182]=norm3(linear).hi;c[unsafe_offset=14183]=norm3(angular).hi;c[unsafe_offset=14184]=norm3(origin_balance).hi
    if plus(point(magnitude(balanceb)),point(magnitude(workb))).hi>EB or magnitude(idealb)>EB or norm3(linear).hi>1e-10*(1+J.length()) or norm3(angular).hi>1e-10*(1+M.length()) or norm3(origin_balance).hi>1e-10*(1+O.length()):status[unsafe_offset=0]=2206;return
    var norm=point(0)
    for j in range(6,10):norm=plus(norm,square(widen(y[unsafe_offset=j],rad[unsafe_offset=j])))
    c[unsafe_offset=14009]=norm.lo;c[unsafe_offset=14010]=norm.hi
    if norm.lo<1-1e-10 or norm.hi>1+1e-10:status[unsafe_offset=0]=2206;return
    code=opening_bounds(x,y,0,rad,zero,bounds,Int(ev[unsafe_offset=132]))
    if code!=0:status[unsafe_offset=0]=Float64(code);return
    if abs(elapsed-h)>8*2.220446049250313e-16*h:status[unsafe_offset=0]=2207;return
    for j in range(21):c[unsafe_offset=14048+j]=y[unsafe_offset=j];c[unsafe_offset=14080+j]=E[unsafe_offset=j];c[unsafe_offset=14112+j]=R[unsafe_offset=j];c[unsafe_offset=14144+j]=T[unsafe_offset=j]
    for k in range(192):output[unsafe_offset=k]=ev[unsafe_offset=k]
    for k in range(3):output[unsafe_offset=5+k]=y[unsafe_offset=k];output[unsafe_offset=12+k]=y[unsafe_offset=3+k];output[unsafe_offset=15+k]=y[unsafe_offset=10+k];output[unsafe_offset=149+k]=J.x if k==0 else J.y if k==1 else J.z;output[unsafe_offset=152+k]=M.x if k==0 else M.y if k==1 else M.z;output[unsafe_offset=155+k]=O.x if k==0 else O.y if k==1 else O.z
    for k in range(4):output[unsafe_offset=8+k]=y[unsafe_offset=6+k]
    for k in range(45,95):output[unsafe_offset=k]=0
    for k in range(8):
        var arm=support_arm(x,y,k);output[unsafe_offset=81+k]=p.y+arm.y-inputs[unsafe_offset=34]
    for k in range(8):output[unsafe_offset=133+k]=y[unsafe_offset=13+k]
    output[unsafe_offset=46]=f[unsafe_offset=13]
    output[unsafe_offset=98]=24;output[unsafe_offset=142]=3;output[unsafe_offset=144]=2201;output[unsafe_offset=147]=ext;output[unsafe_offset=158]=delta;output[unsafe_offset=160]=h;output[unsafe_offset=161]=endpoint;output[unsafe_offset=162]=0;output[unsafe_offset=167]=0;output[unsafe_offset=168]=hlo;output[unsafe_offset=137]=y[unsafe_offset=17]
    var oldarm=support_arm(x,y,Int(ev[unsafe_offset=132]));var newarm=support_arm(x,y,Int(ev[unsafe_offset=131]));output[unsafe_offset=114]=(v+w.cross(oldarm)).y;output[unsafe_offset=115]=(v+w.cross(newarm)).y
    c[unsafe_offset=14011]=report[unsafe_offset=300];c[unsafe_offset=14012]=prefix_rhs+report[unsafe_offset=300];c[unsafe_offset=14013]=prefix_evals+report[unsafe_offset=301]+report[unsafe_offset=302];c[unsafe_offset=14014]=prefix_cells+report[unsafe_offset=303];c[unsafe_offset=14015]=1
    for k in range(5):c[unsafe_offset=15500+k]=report[unsafe_offset=304+k]
    for k in range(16384):budget_output[unsafe_offset=k]=c[unsafe_offset=k]
    report[unsafe_offset=0]=H
