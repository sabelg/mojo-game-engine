"""Isolated empirical supported-motion root query. No impact or remainder advance."""
from std.memory import Pointer
from std.math import isfinite,sqrt
from mojo_game import Vec3,Quaternion
from .single_contact_handoff import single_contact_handoff
from .single_support_advance import DIM,local_corner,dp_step,support_rhs,support_arm,interval_local,interval_arm,external_acc,kinetic_state
from .support_intervals import Bound,Bound3,point,widen,plus,minus,times,divide,square,magnitude,fixed3,cross3,norm3,next_up
comptime P = Pointer[Float64,MutAnyOrigin]

def pivot_rotation(q: Quaternion,w: Vec3,h: Float64) -> Quaternion:
    var speed=w.length()
    if speed==0:return q
    # |half angle| <= sqrt(300)/60 < .289. Taylor remainder below 1e-24.
    var angle=speed*h*.5;var z=angle*angle;var st=angle;var ct=Float64(1);var sine=st;var cosine=ct
    for k in range(1,9):
        st*= -z/Float64((2*k)*(2*k+1));ct*= -z/Float64((2*k-1)*(2*k));sine+=st;cosine+=ct
    var axis=w*(1/speed)
    return Quaternion(axis.x*sine,axis.y*sine,axis.z*sine,cosine)*q

def event_geometry(x: P,y: P,e: P,r: P,j: Int) -> Tuple[Bound,Bound]:
    var arm=interval_arm(x,y,e,r,j);var w=Bound3(widen(y[unsafe_offset=10],e[unsafe_offset=10]+r[unsafe_offset=10]),widen(y[unsafe_offset=11],e[unsafe_offset=11]+r[unsafe_offset=11]),widen(y[unsafe_offset=12],e[unsafe_offset=12]+r[unsafe_offset=12]))
    return minus(plus(widen(y[unsafe_offset=1],e[unsafe_offset=1]+r[unsafe_offset=1]),arm.y),point(x[unsafe_offset=34])),plus(widen(y[unsafe_offset=4],e[unsafe_offset=4]+r[unsafe_offset=4]),cross3(w,arm).y)

def event_bounds(x: P,y: P,h: Float64,e: P,r: P,b: P) -> Int:
    var selected=Int(x[unsafe_offset=40]);var arm=interval_arm(x,y,e,r,selected);var w=Bound3(widen(y[unsafe_offset=10],e[unsafe_offset=10]+r[unsafe_offset=10]),widen(y[unsafe_offset=11],e[unsafe_offset=11]+r[unsafe_offset=11]),widen(y[unsafe_offset=12],e[unsafe_offset=12]+r[unsafe_offset=12]));var ae=plus(divide(point(x[unsafe_offset=19]),point(x[unsafe_offset=1])),point(x[unsafe_offset=43]));var rs=norm3(interval_local(x,selected)).hi;var w0=norm3(w).hi;var W=min(sqrt(300.0),next_up(w0+max(1.0,w0*.5)));var W2=times(point(W),point(W));var N=times(point(x[unsafe_offset=1]),plus(point(magnitude(ae)),times(W2,point(rs))));var alpha=divide(times(point(rs),N),point(x[unsafe_offset=2]));var q=plus(ae,cross3(w,cross3(w,arm)).y);var qdot=times(point(rs),plus(times(point(2*W),alpha),times(W2,point(W))));var qupper=plus(q,times(point(h),qdot)).hi
    b[unsafe_offset=0]=qupper;b[unsafe_offset=1]=N.hi;b[unsafe_offset=2]=alpha.hi;b[unsafe_offset=3]=W;b[unsafe_offset=4]=magnitude(ae)+N.hi/x[unsafe_offset=1];b[unsafe_offset=5]=rs
    if not isfinite(qupper) or qupper>=0 or plus(point(w0),times(point(h),alpha)).hi>W:return 1604
    var g,vn=event_geometry(x,y,e,r,selected);b[unsafe_offset=6]=magnitude(plus(g,times(Bound(0,h),vn)));b[unsafe_offset=7]=magnitude(vn)
    if b[unsafe_offset=6]>1e-9 or b[unsafe_offset=7]>1e-9:return 1602
    for axis in range(3):
        var ak=magnitude(plus(divide(point(x[unsafe_offset=18+axis]),point(x[unsafe_offset=1])),point(x[unsafe_offset=42+axis])))
        var acceleration=plus(point(ak),divide(N,point(x[unsafe_offset=1]))) if axis==1 else point(ak)
        var velocity=magnitude(widen(y[unsafe_offset=3+axis],e[unsafe_offset=3+axis]+r[unsafe_offset=3+axis]))
        var vb=plus(point(velocity),times(point(h),acceleration)).hi
        var pb=plus(plus(point(magnitude(widen(y[unsafe_offset=axis],e[unsafe_offset=axis]+r[unsafe_offset=axis]))),times(point(h),point(velocity))),times(times(point(.5),square(point(h))),acceleration)).hi
        var wb=plus(point(magnitude(widen(y[unsafe_offset=10+axis],e[unsafe_offset=10+axis]+r[unsafe_offset=10+axis]))),times(point(h),alpha)).hi
        if vb>20 or pb>1000 or wb>10 or acceleration.hi>1000 or alpha.hi>1000:return 1603
    for j in range(8):
        var gap,speed=event_geometry(x,y,e,r,j);var radius=norm3(interval_local(x,j)).hi;var accel=plus(plus(point(magnitude(ae)),divide(N,point(x[unsafe_offset=1]))),plus(times(alpha,point(radius)),times(W2,point(radius))));var end=minus(plus(gap,times(speed,point(h))),times(times(point(.5),square(point(h))),accel))
        b[unsafe_offset=8+j]=min(gap.lo,end.lo);b[unsafe_offset=16+j]=plus(speed,times(point(h),accel)).hi;b[unsafe_offset=24+j]=minus(speed,times(point(h),accel)).lo;b[unsafe_offset=32+j]=gap.lo;b[unsafe_offset=40+j]=gap.hi
    return 0

def event_checkpoint(x: P,y: P,d: P,report: P) -> Int:
    var code=support_rhs(x,y,d);report[unsafe_offset=3]+=1
    if code!=0:return 1603
    var arm=support_arm(x,y,Int(x[unsafe_offset=40]));var w=Vec3(y[unsafe_offset=10],y[unsafe_offset=11],y[unsafe_offset=12]);var gap=y[unsafe_offset=1]+arm.y-x[unsafe_offset=34];var speed=y[unsafe_offset=4]+w.cross(arm).y;var norm=Float64(0)
    for j in range(6,10):norm+=y[unsafe_offset=j]*y[unsafe_offset=j]
    report[unsafe_offset=8]=min(report[unsafe_offset=8],(d[unsafe_offset=4]-external_acc(x).y)*x[unsafe_offset=1]);report[unsafe_offset=9]=max(report[unsafe_offset=9],abs(norm-1))
    if abs(gap)>1e-9 or abs(speed)>1e-9 or abs(norm-1)>1e-10:return 1602
    return 0

def event_trial(x: P,y: P,h: Float64,e: P,n: P,full: P,half: P,dest: P,temp: P,slopes: P,te: P,tn: P,stage: P,report: P) -> Int:
    report[unsafe_offset=2]+=1
    var corner=local_corner(x,Int(x[unsafe_offset=40]))
    if corner.x==0 and corner.y==0 and corner.z==0:
        # Exact zero-lever-arm support: constant omega, balanced normal force.
        # Caller always supplies original entry and absolute time, never a projected state.
        var acc=external_acc(x);var a=Vec3(acc.x,0,acc.z);var w=Vec3(y[unsafe_offset=10],y[unsafe_offset=11],y[unsafe_offset=12]);var v=Vec3(y[unsafe_offset=3],y[unsafe_offset=4],y[unsafe_offset=5]);var pos=Vec3(y[unsafe_offset=0],y[unsafe_offset=1],y[unsafe_offset=2]);var N= -x[unsafe_offset=1]*acc.y
        if N<=0:return 1604
        var q=pivot_rotation(Quaternion(y[unsafe_offset=6],y[unsafe_offset=7],y[unsafe_offset=8],y[unsafe_offset=9]),w,h);var pn=pos+v*h+a*(.5*h*h);var vn=v+a*h;var moment=(pos*h+v*(.5*h*h)).cross(a*x[unsafe_offset=1])
        for j in range(DIM):dest[unsafe_offset=j]=y[unsafe_offset=j]
        for j in range(3):dest[unsafe_offset=j]=pn.x if j==0 else pn.y if j==1 else pn.z;dest[unsafe_offset=3+j]=vn.x if j==0 else vn.y if j==1 else vn.z;dest[unsafe_offset=18+j]=moment.x if j==0 else moment.y if j==1 else moment.z
        dest[unsafe_offset=6]=q.x;dest[unsafe_offset=7]=q.y;dest[unsafe_offset=8]=q.z;dest[unsafe_offset=9]=q.w;dest[unsafe_offset=13]=N*h;dest[unsafe_offset=17]=N*v.y*h
        for j in range(DIM):te[unsafe_offset=j]=0;tn[unsafe_offset=j]=64*2.220446049250313e-16*(1+max(abs(y[unsafe_offset=j]),abs(dest[unsafe_offset=j])))
        report[unsafe_offset=27]+=1
        return event_checkpoint(x,dest,temp,report)
    for j in range(DIM):stage[unsafe_offset=j]=abs(y[unsafe_offset=j])
    var c=dp_step(x,y,h,full,temp,slopes,report,stage)
    if c==0:c=dp_step(x,y,h/2,half,temp,slopes,report,stage)
    if c==0:c=dp_step(x,half,h/2,dest,temp,slopes,report,stage)
    if c!=0:return 1603
    var EB=1e-9*(1+kinetic_state(x,y))
    for j in range(DIM):
        var delta=8*abs(dest[unsafe_offset=j]-full[unsafe_offset=j])/31;var floor=64*2.220446049250313e-16*(1+stage[unsafe_offset=j]);te[unsafe_offset=j]=next_up(e[unsafe_offset=j]+delta);tn[unsafe_offset=j]=next_up(n[unsafe_offset=j]+floor);var budget=1e-10*(1+min(abs(y[unsafe_offset=j]),abs(dest[unsafe_offset=j])))
        if j==17:budget=EB-abs(dest[unsafe_offset=17])
        if budget<=0 or te[unsafe_offset=j]>.5*budget or tn[unsafe_offset=j]>.25*budget:return 1607
    c=event_checkpoint(x,half,temp,report)
    if c==0:c=event_checkpoint(x,dest,temp,report)
    return c

def root_budget(x: P,y: P,dt: Float64,b: P,e: P,n: P,report: P) -> Bool:
    var acc=external_acc(x);var Vnorm=Vec3(y[unsafe_offset=3],y[unsafe_offset=4],y[unsafe_offset=5]).length();var A=acc.length()+b[unsafe_offset=1]/x[unsafe_offset=1];var radius=b[unsafe_offset=5];var N=b[unsafe_offset=1];var W=b[unsafe_offset=3];var alpha=b[unsafe_offset=2];var arm=support_arm(x,y,Int(x[unsafe_offset=40]));var ok=True
    for j in range(DIM):
        var rate=Vnorm+A*dt if j<3 else A if j<6 else W if j<10 else alpha if j<13 else N if j==13 else radius*N if j<17 else N*1e-9
        if j>=18:
            # Componentwise bound on x cross m*a_external + (x+r) cross N*n.
            var axis=j-18;var u=(axis+1)%3;var v=(axis+2)%3
            var pu=abs(y[unsafe_offset=u])+e[unsafe_offset=u]+n[unsafe_offset=u]+Vnorm*dt+.5*A*dt*dt;var pv=abs(y[unsafe_offset=v])+e[unsafe_offset=v]+n[unsafe_offset=v]+Vnorm*dt+.5*A*dt*dt
            var au=abs(acc.x if u==0 else acc.y if u==1 else acc.z);var av=abs(acc.x if v==0 else acc.y if v==1 else acc.z)
            rate=x[unsafe_offset=1]*(pu*av+pv*au)
            if axis!=1:
                var c=2 if axis==0 else 0;var rc=arm.z if c==2 else arm.x;var ra=interval_arm(x,y,e,n,Int(x[unsafe_offset=40]));var rb=ra.z if c==2 else ra.x;var pc=magnitude(plus(widen(y[unsafe_offset=c],e[unsafe_offset=c]+n[unsafe_offset=c]),rb))+Vnorm*dt+radius*W*dt+.5*A*dt*dt
                rate+=pc*N
        var budget=1e-10*(1+abs(y[unsafe_offset=j]))
        if j==17:budget=1e-9*(1+kinetic_state(x,y))-abs(y[unsafe_offset=17])
        var ratio=max(dt*(1+rate)/(.25*budget),(e[unsafe_offset=j]+n[unsafe_offset=j]+dt*rate)/(.75*budget))
        if ratio>report[unsafe_offset=17]:report[unsafe_offset=17]=ratio;report[unsafe_offset=26]=Float64(j)
        if ratio>1:ok=False
    return ok and dt<=1e-10

def supported_event_locator(inputs: P,previous: P,request: P,output: P,scratch: P,status: P,report: P):
    for i in range(192):output[unsafe_offset=i]=previous[unsafe_offset=i]
    for i in range(32):report[unsafe_offset=i]=0
    report[unsafe_offset=5]=-1;report[unsafe_offset=8]=1e30;report[unsafe_offset=24]=1e30;report[unsafe_offset=25]=-1e30;report[unsafe_offset=30]=1e30;status[unsafe_offset=0]=0;status[unsafe_offset=1]=0
    var H=request[unsafe_offset=8];var cap=request[unsafe_offset=9];var ac=request[unsafe_offset=10]
    if not isfinite(H) or H<=0 or H>1.0/30 or not isfinite(cap) or cap<1 or cap>256 or cap!=Float64(Int(cap)) or not isfinite(ac) or ac<1 or ac>64 or ac!=Float64(Int(ac)):status[unsafe_offset=0]=1600;return
    single_contact_handoff(inputs,previous,request,scratch+512,scratch,status)
    if status[unsafe_offset=0]!=0:return
    if scratch[unsafe_offset=610]!=11:status[unsafe_offset=0]=1601;return
    var y=scratch+736;var entry=scratch+768;var full=scratch+800;var half=scratch+832;var dest=scratch+864;var temp=scratch+896;var slopes=scratch+928;var err=scratch+1088;var noise=scratch+1120;var te=scratch+1152;var tn=scratch+1184;var stack=scratch+1216;var bounds=scratch+1504;var stage=scratch+1568;var anchor=scratch+1600;var ae=scratch+1632;var an=scratch+1664;var left=scratch+1696;var le=scratch+1760;var ln=scratch+1792
    for j in range(DIM):y[unsafe_offset=j]=0;err[unsafe_offset=j]=0;noise[unsafe_offset=j]=0
    for j in range(3):y[unsafe_offset=j]=inputs[unsafe_offset=5+j];y[unsafe_offset=3+j]=inputs[unsafe_offset=12+j];y[unsafe_offset=10+j]=inputs[unsafe_offset=15+j]
    for j in range(4):y[unsafe_offset=6+j]=inputs[unsafe_offset=8+j]
    for j in range(DIM):entry[unsafe_offset=j]=y[unsafe_offset=j]
    var elapsed=Float64(0);var depth=1;stack[unsafe_offset=0]=H;var selected=Int(inputs[unsafe_offset=40]);var event= -1;var bracket_hi=H;var corner=local_corner(inputs,selected);var pivot=corner.x==0 and corner.y==0 and corner.z==0
    while depth>0:
        if report[unsafe_offset=2]>=cap or report[unsafe_offset=1]>=ac:status[unsafe_offset=0]=1606;return
        depth-=1;var h=stack[unsafe_offset=depth];var code=event_trial(inputs,entry if pivot else y,elapsed+h if pivot else h,err,noise,full,half,dest,temp,slopes,te,tn,stage,report)
        if code==0:
            # An analytic recomputation may have a smaller roundoff radius than entry.
            # Enclose both endpoints when bounding the whole intervening cell.
            for j in range(DIM):scratch[unsafe_offset=2112+j]=max(err[unsafe_offset=j],te[unsafe_offset=j]);scratch[unsafe_offset=2144+j]=max(noise[unsafe_offset=j],tn[unsafe_offset=j])
            code=event_bounds(inputs,y,h,scratch+2112,scratch+2144,bounds)
        var clear=code==0;var candidate= -1;var number=0
        if code==0:
            for j in range(8):
                if j==selected:continue
                var g,s=event_geometry(inputs,dest,te,tn,j);bounds[unsafe_offset=48+j]=g.lo;bounds[unsafe_offset=56+j]=g.hi
                if bounds[unsafe_offset=8+j]<=1e-9:
                    clear=False;number+=1;candidate=j
            report[unsafe_offset=19]=max(report[unsafe_offset=19],Float64(number))
        if clear:
            for j in range(DIM):y[unsafe_offset=j]=dest[unsafe_offset=j];err[unsafe_offset=j]=te[unsafe_offset=j];noise[unsafe_offset=j]=tn[unsafe_offset=j]
            elapsed+=h;report[unsafe_offset=1]+=1;report[unsafe_offset=29]=elapsed;report[unsafe_offset=30]=min(report[unsafe_offset=30],h);report[unsafe_offset=25]=max(report[unsafe_offset=25],bounds[unsafe_offset=0])
            for j in range(8):
                if j!=selected:report[unsafe_offset=24]=min(report[unsafe_offset=24],bounds[unsafe_offset=8+j])
            continue
        if code==0 and number==1 and bounds[unsafe_offset=32+candidate]>0 and bounds[unsafe_offset=56+candidate]<0 and bounds[unsafe_offset=16+candidate]< -1e-9:
            event=candidate;var lo=Float64(0);var hi=h
            for j in range(DIM):anchor[unsafe_offset=j]=y[unsafe_offset=j];ae[unsafe_offset=j]=err[unsafe_offset=j];an[unsafe_offset=j]=noise[unsafe_offset=j];left[unsafe_offset=j]=y[unsafe_offset=j];le[unsafe_offset=j]=err[unsafe_offset=j];ln[unsafe_offset=j]=noise[unsafe_offset=j]
            var found=False
            for iteration in range(48):
                var g,s=event_geometry(inputs,left,le,ln,event)
                report[unsafe_offset=6]=elapsed+lo;report[unsafe_offset=7]=elapsed+hi;report[unsafe_offset=20]=g.lo;report[unsafe_offset=21]=g.hi;report[unsafe_offset=17]=0
                if g.lo>0 and g.hi<=1e-9 and root_budget(inputs,left,hi-lo,bounds,le,ln,report):found=True;break
                if report[unsafe_offset=2]>=cap:status[unsafe_offset=0]=1606;return
                # Reuse the certified left point's gap/speed only as a probe proposal.
                # Every candidate is reintegrated and must pass unchanged interval signs.
                var mid=(lo+hi)*.5
                if s.hi<0:
                    var proposal=lo-((g.lo+g.hi)*.5)/((s.lo+s.hi)*.5)
                    var lower=lo+.1*(hi-lo);var upper=hi-.1*(hi-lo)
                    if isfinite(proposal):mid=max(lower,min(upper,proposal))
                if mid==lo or mid==hi:status[unsafe_offset=0]=1607;return
                code=event_trial(inputs,entry if pivot else anchor,elapsed+mid if pivot else mid,ae,an,full,half,dest,temp,slopes,te,tn,stage,report);report[unsafe_offset=4]+=1
                if code!=0:report[unsafe_offset=18]=Float64(code);status[unsafe_offset=0]=Float64(code);return
                var gm,vm=event_geometry(inputs,dest,te,tn,event)
                if gm.lo>0:
                    lo=mid
                    for j in range(DIM):left[unsafe_offset=j]=dest[unsafe_offset=j];le[unsafe_offset=j]=te[unsafe_offset=j];ln[unsafe_offset=j]=tn[unsafe_offset=j]
                elif gm.hi<0:hi=mid
                else:
                    # Sign is uncertain, so do not assign this probe to either side.
                    # Monotone derivative enclosure contracts only the root upper bound.
                    var acceleration=divide(minus(point(bounds[unsafe_offset=16+event]),point(bounds[unsafe_offset=24+event])),point(2*h)).hi;var radius=times(point(acceleration),point(max(mid-lo,hi-mid))).hi;var derivative=plus(vm,Bound(-radius,radius))
                    if derivative.hi>=0:status[unsafe_offset=0]=1607;return
                    var shift=divide(Bound(-gm.hi,-gm.lo),derivative);var upper=min(hi,plus(point(mid),shift).hi)
                    if upper<=lo or upper>=hi:status[unsafe_offset=0]=1607;return
                    hi=upper;report[unsafe_offset=31]+=1
            if not found:status[unsafe_offset=0]=1606;return
            bracket_hi=elapsed+hi;elapsed+=lo
            for j in range(DIM):y[unsafe_offset=j]=left[unsafe_offset=j];err[unsafe_offset=j]=le[unsafe_offset=j];noise[unsafe_offset=j]=ln[unsafe_offset=j]
            var ge,ve=event_geometry(inputs,y,err,noise,event);report[unsafe_offset=20]=ge.lo;report[unsafe_offset=21]=ge.hi;report[unsafe_offset=22]=bounds[unsafe_offset=16+event];report[unsafe_offset=23]=1;break
        report[unsafe_offset=18]=Float64(code if code!=0 else 1605)
        if depth+2>48 or h/2<=0 or elapsed+h/2==elapsed:status[unsafe_offset=0]=1605;return
        stack[unsafe_offset=depth]=h/2;stack[unsafe_offset=depth+1]=h/2;depth+=2
    if event<0:
        if abs(elapsed-H)>8*2.220446049250313e-16*H:status[unsafe_offset=0]=1608;return
        elapsed=H;bracket_hi=H
    var p=Vec3(y[unsafe_offset=0],y[unsafe_offset=1],y[unsafe_offset=2]);var p0=Vec3(entry[unsafe_offset=0],entry[unsafe_offset=1],entry[unsafe_offset=2]);var v=Vec3(y[unsafe_offset=3],y[unsafe_offset=4],y[unsafe_offset=5]);var v0=Vec3(entry[unsafe_offset=3],entry[unsafe_offset=4],entry[unsafe_offset=5]);var w=Vec3(y[unsafe_offset=10],y[unsafe_offset=11],y[unsafe_offset=12]);var w0=Vec3(entry[unsafe_offset=10],entry[unsafe_offset=11],entry[unsafe_offset=12]);var mass=inputs[unsafe_offset=1];var inertia=inputs[unsafe_offset=2];var ext=external_acc(inputs)*mass;var J=Vec3(0,y[unsafe_offset=13],0);var M=Vec3(y[unsafe_offset=14],y[unsafe_offset=15],y[unsafe_offset=16]);var O=Vec3(y[unsafe_offset=18],y[unsafe_offset=19],y[unsafe_offset=20]);var T0=kinetic_state(inputs,entry);var EB=1e-9*(1+T0);var ideal=kinetic_state(inputs,y)-T0-ext.dot(p-p0);var E=abs(ideal-y[unsafe_offset=17]);var pe=((v-v0)*mass-ext*elapsed-J).length();var me=((w-w0)*inertia-M).length();var oe=((w-w0)*inertia+p.cross(v*mass)-p0.cross(v0*mass)-O).length()
    for j in range(DIM):
        var budget=1e-10*(1+min(abs(entry[unsafe_offset=j]),abs(y[unsafe_offset=j])))
        if j==17:budget=EB-abs(y[unsafe_offset=17])
        if budget<=0 or err[unsafe_offset=j]>.5*budget or noise[unsafe_offset=j]>.25*budget:status[unsafe_offset=0]=1607;return
    report[unsafe_offset=10]=E;report[unsafe_offset=11]=abs(ideal);report[unsafe_offset=12]=pe;report[unsafe_offset=13]=me;report[unsafe_offset=14]=oe
    if E>EB or abs(ideal)>EB or abs(y[unsafe_offset=17])+err[unsafe_offset=17]+noise[unsafe_offset=17]>.75*EB or pe>1e-10*(1+(ext*elapsed+J).length()) or me>1e-10*(1+M.length()) or oe>1e-10*(1+O.length()):status[unsafe_offset=0]=1609;return
    for j in range(8):
        var g,s=event_geometry(inputs,y,err,noise,j)
        if j==selected:
            if magnitude(g)>1e-9 or magnitude(s)>1e-9:status[unsafe_offset=0]=1602;return
        elif j==event:
            if g.lo<=0 or g.hi>1e-9 or s.hi>= -1e-9:status[unsafe_offset=0]=1607;return
        elif g.lo<=1e-9:status[unsafe_offset=0]=1605;return
    for j in range(DIM):report[unsafe_offset=15]=max(report[unsafe_offset=15],err[unsafe_offset=j]);report[unsafe_offset=16]=max(report[unsafe_offset=16],noise[unsafe_offset=j])
    for j in range(128):output[unsafe_offset=j]=scratch[unsafe_offset=512+j]
    # This query applies no impact; retain all prior impact/history words.
    for j in range(99,106):output[unsafe_offset=j]=previous[unsafe_offset=j]
    for j in range(3):output[unsafe_offset=5+j]=y[unsafe_offset=j];output[unsafe_offset=12+j]=y[unsafe_offset=3+j];output[unsafe_offset=15+j]=y[unsafe_offset=10+j]
    for j in range(4):output[unsafe_offset=8+j]=y[unsafe_offset=6+j]
    for j in range(45,95):output[unsafe_offset=j]=0
    output[unsafe_offset=41]=Float64(event);output[unsafe_offset=98]=18 if event>=0 else 19
    output[unsafe_offset=128]=elapsed;output[unsafe_offset=129]=elapsed;output[unsafe_offset=130]=bracket_hi;output[unsafe_offset=131]=Float64(event);output[unsafe_offset=132]=Float64(selected)
    for j in range(8):output[unsafe_offset=133+j]=y[unsafe_offset=13+j]
    output[unsafe_offset=141]=H-elapsed;output[unsafe_offset=142]=1 if event>=0 else 0
    report[unsafe_offset=0]=elapsed;report[unsafe_offset=5]=Float64(event);report[unsafe_offset=6]=elapsed;report[unsafe_offset=7]=bracket_hi;report[unsafe_offset=28]=y[unsafe_offset=17]
