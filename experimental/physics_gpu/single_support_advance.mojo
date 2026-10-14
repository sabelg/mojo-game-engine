"""Empirically controlled fixed-active DP5 advance; exact whole-owner rollback."""
from std.memory import Pointer
from std.math import isfinite,sqrt
from mojo_game import Vec3,Quaternion
from .core import component,finite
from .single_contact_handoff import single_contact_handoff
from .single_point_reaction import single_point_reaction
from .support_intervals import Bound,Bound3,point,widen,plus,minus,times,divide,square,root,magnitude,fixed3,add3,scale3,cross3,norm3,rotate3,next_up

comptime P = Pointer[Float64,MutAnyOrigin]
comptime DIM = 21

def local_corner(x: P,i: Int) -> Vec3:
    var half=Vec3(x[unsafe_offset=24],x[unsafe_offset=25],x[unsafe_offset=26]);var shape=Quaternion(x[unsafe_offset=30],x[unsafe_offset=31],x[unsafe_offset=32],x[unsafe_offset=33]);var center=Vec3(x[unsafe_offset=27],x[unsafe_offset=28],x[unsafe_offset=29])
    return center+shape.rotate(Vec3(-half.x if i%2==0 else half.x,-half.y if (i//2)%2==0 else half.y,-half.z if (i//4)%2==0 else half.z))
def support_arm(x: P,y: P,i: Int) -> Vec3:
    return Quaternion(y[unsafe_offset=6],y[unsafe_offset=7],y[unsafe_offset=8],y[unsafe_offset=9]).rotate(local_corner(x,i))
def external_acc(x: P) -> Vec3:
    return Vec3(x[unsafe_offset=18]/x[unsafe_offset=1]+x[unsafe_offset=42],x[unsafe_offset=19]/x[unsafe_offset=1]+x[unsafe_offset=43],x[unsafe_offset=20]/x[unsafe_offset=1]+x[unsafe_offset=44])
def support_rhs(x: P,y: P,d: P) -> Int:
    for k in range(DIM):
        if not isfinite(y[unsafe_offset=k]):return 1503
    var p=Vec3(y[unsafe_offset=0],y[unsafe_offset=1],y[unsafe_offset=2]);var v=Vec3(y[unsafe_offset=3],y[unsafe_offset=4],y[unsafe_offset=5]);var w=Vec3(y[unsafe_offset=10],y[unsafe_offset=11],y[unsafe_offset=12]);var qv=Vec3(y[unsafe_offset=6],y[unsafe_offset=7],y[unsafe_offset=8]);var qw=y[unsafe_offset=9];var qnorm=qv.dot(qv)+qw*qw
    if component(p)>1000 or component(v)>20 or component(w)>10 or qnorm<.25 or qnorm>4:return 1503
    var r=support_arm(x,y,Int(x[unsafe_offset=40]));var ae=external_acc(x);var mass=x[unsafe_offset=1];var inertia=x[unsafe_offset=2];var K=1/mass+(r.x*r.x+r.z*r.z)/inertia;var free=ae.y+w.cross(w.cross(r)).y;var N=-free/K
    if not isfinite(N) or N<=0:return 1504
    var force=Vec3(0,N,0);var torque=r.cross(force);var alpha=torque*(1/inertia);var a=ae+force*(1/mass);var qdot=(w*qw+w.cross(qv))*.5;var origin=p.cross(ae*mass)+(p+r).cross(force)
    if not finite(a) or not finite(alpha) or component(a)>1000 or component(alpha)>1000:return 1503
    for k in range(3):
        d[unsafe_offset=k]=v.x if k==0 else v.y if k==1 else v.z;d[unsafe_offset=3+k]=a.x if k==0 else a.y if k==1 else a.z;d[unsafe_offset=6+k]=qdot.x if k==0 else qdot.y if k==1 else qdot.z;d[unsafe_offset=10+k]=alpha.x if k==0 else alpha.y if k==1 else alpha.z;d[unsafe_offset=14+k]=torque.x if k==0 else torque.y if k==1 else torque.z;d[unsafe_offset=18+k]=origin.x if k==0 else origin.y if k==1 else origin.z
    d[unsafe_offset=9]=-.5*w.dot(qv);d[unsafe_offset=13]=N;d[unsafe_offset=17]=N*(v+w.cross(r)).y
    return 0

def dp_a(stage: Int,k: Int) -> Float64:
    if stage==1:return .2 if k==0 else 0.0
    if stage==2:return 3.0/40 if k==0 else 9.0/40 if k==1 else 0.0
    if stage==3:return 44.0/45 if k==0 else -56.0/15 if k==1 else 32.0/9 if k==2 else 0.0
    if stage==4:return 19372.0/6561 if k==0 else -25360.0/2187 if k==1 else 64448.0/6561 if k==2 else -212.0/729 if k==3 else 0.0
    if stage==5:return 9017.0/3168 if k==0 else -355.0/33 if k==1 else 46732.0/5247 if k==2 else 49.0/176 if k==3 else -5103.0/18656 if k==4 else 0.0
    if stage==6:return dp_b(k)
    return 0.0

def dp_b(k: Int) -> Float64:
    return 35.0/384 if k==0 else 500.0/1113 if k==2 else 125.0/192 if k==3 else -2187.0/6784 if k==4 else 11.0/84 if k==5 else 0.0

def dp_step(x: P,y: P,h: Float64,dest: P,temp: P,slopes: P,report: P,stage_max: P) -> Int:
    for stage in range(7):
        for j in range(DIM):
            var total=Float64(0)
            for k in range(stage):total+=dp_a(stage,k)*slopes[unsafe_offset=k*DIM+j]
            temp[unsafe_offset=j]=y[unsafe_offset=j]+h*total;stage_max[unsafe_offset=j]=max(stage_max[unsafe_offset=j],abs(temp[unsafe_offset=j]))
        var code=support_rhs(x,temp,slopes+stage*DIM);report[unsafe_offset=3]+=1
        if code!=0:return code
    for j in range(DIM):
        var total=Float64(0)
        for k in range(7):total+=dp_b(k)*slopes[unsafe_offset=k*DIM+j]
        dest[unsafe_offset=j]=y[unsafe_offset=j]+h*total
    return 0

def scalar_checkpoint(x: P,y: P,temporary: P,result: P) -> Int:
    for i in range(96):temporary[unsafe_offset=i]=x[unsafe_offset=i]
    for i in range(3):temporary[unsafe_offset=5+i]=y[unsafe_offset=i];temporary[unsafe_offset=12+i]=y[unsafe_offset=3+i];temporary[unsafe_offset=15+i]=y[unsafe_offset=10+i]
    for i in range(4):temporary[unsafe_offset=8+i]=y[unsafe_offset=6+i]
    single_point_reaction(temporary,result)
    return Int(result[unsafe_offset=39])

def interval_local(x: P,i: Int) -> Bound3:
    var corner=fixed3(-x[unsafe_offset=24] if i%2==0 else x[unsafe_offset=24],-x[unsafe_offset=25] if (i//2)%2==0 else x[unsafe_offset=25],-x[unsafe_offset=26] if (i//4)%2==0 else x[unsafe_offset=26])
    return add3(fixed3(x[unsafe_offset=27],x[unsafe_offset=28],x[unsafe_offset=29]),rotate3(point(x[unsafe_offset=30]),point(x[unsafe_offset=31]),point(x[unsafe_offset=32]),point(x[unsafe_offset=33]),corner))
def interval_arm(x: P,y: P,e: P,r: P,i: Int) -> Bound3:
    return rotate3(widen(y[unsafe_offset=6],e[unsafe_offset=6]+r[unsafe_offset=6]),widen(y[unsafe_offset=7],e[unsafe_offset=7]+r[unsafe_offset=7]),widen(y[unsafe_offset=8],e[unsafe_offset=8]+r[unsafe_offset=8]),widen(y[unsafe_offset=9],e[unsafe_offset=9]+r[unsafe_offset=9]),interval_local(x,i))

def support_bounds(x: P,y: P,h: Float64,e: P,r: P,bounds: P,neutral: Bool=False) -> Int:
    var selected=Int(x[unsafe_offset=40]);var arm=interval_arm(x,y,e,r,selected);var vy=widen(y[unsafe_offset=4],e[unsafe_offset=4]+r[unsafe_offset=4]);var py=widen(y[unsafe_offset=1],e[unsafe_offset=1]+r[unsafe_offset=1]);var w=Bound3(widen(y[unsafe_offset=10],e[unsafe_offset=10]+r[unsafe_offset=10]),widen(y[unsafe_offset=11],e[unsafe_offset=11]+r[unsafe_offset=11]),widen(y[unsafe_offset=12],e[unsafe_offset=12]+r[unsafe_offset=12]));var gap=minus(plus(py,arm.y),point(x[unsafe_offset=34]));var vn=plus(vy,cross3(w,arm).y)
    var drift=plus(gap,times(Bound(0,h),vn));bounds[unsafe_offset=0]=magnitude(drift);bounds[unsafe_offset=1]=magnitude(vn)
    if not isfinite(drift.lo) or not isfinite(drift.hi) or magnitude(drift)>1e-9 or magnitude(vn)>1e-9:return 1502
    var ae=plus(divide(point(x[unsafe_offset=19]),point(x[unsafe_offset=1])),point(x[unsafe_offset=43]));var rs=norm3(interval_local(x,selected)).hi;var w0=norm3(w).hi;var W=min(sqrt(300.0),next_up(w0+max(1.0,w0*.5)));var W2=times(point(W),point(W));var nmax=times(point(x[unsafe_offset=1]),plus(point(magnitude(ae)),times(W2,point(rs))));var alpha=divide(times(point(rs),nmax),point(x[unsafe_offset=2]));var q=plus(ae,cross3(w,cross3(w,arm)).y)
    var qdot=times(point(rs),plus(times(point(2*W),alpha),times(W2,point(W))));var qupper=plus(q,times(point(h),qdot)).hi
    bounds[unsafe_offset=2]=qupper;bounds[unsafe_offset=3]=1e30
    if not neutral and (plus(point(w0),times(point(h),alpha)).hi>W or qupper>=0):return 1504
    var aevec=external_acc(x)
    for axis in range(3):
        var ak=magnitude(plus(divide(point(x[unsafe_offset=18+axis]),point(x[unsafe_offset=1])),point(x[unsafe_offset=42+axis])))
        var av=plus(point(ak),divide(nmax,point(x[unsafe_offset=1]))) if axis==1 and not neutral else point(ak)
        var vbound=plus(point(abs(y[unsafe_offset=3+axis])+e[unsafe_offset=3+axis]+r[unsafe_offset=3+axis]),times(point(h),av)).hi
        var pbound=plus(plus(point(abs(y[unsafe_offset=axis])+e[unsafe_offset=axis]+r[unsafe_offset=axis]),times(point(h),point(abs(y[unsafe_offset=3+axis])+e[unsafe_offset=3+axis]+r[unsafe_offset=3+axis]))),times(times(point(.5),square(point(h))),av)).hi
        var wbound=plus(point(abs(y[unsafe_offset=10+axis])+e[unsafe_offset=10+axis]+r[unsafe_offset=10+axis]),times(point(h),alpha)).hi if not neutral else Float64(0)
        if vbound>20 or pbound>1000 or wbound>10 or av.hi>1000 or (not neutral and alpha.hi>1000):return 1503
    for j in range(8):
        if j==selected:continue
        var a=interval_arm(x,y,e,r,j);var g=minus(plus(py,a.y),point(x[unsafe_offset=34]));var speed=plus(vy,cross3(w,a).y);var radius=norm3(interval_local(x,j)).hi;var accel=plus(plus(point(magnitude(ae)),divide(nmax,point(x[unsafe_offset=1]))),plus(times(alpha,point(radius)),times(W2,point(radius))));var end=minus(plus(g,times(speed,point(h))),times(times(point(.5),square(point(h))),accel));var low=min(g.lo,end.lo) if not neutral else g.lo
        bounds[unsafe_offset=3]=min(bounds[unsafe_offset=3],low)
        if not isfinite(low) or low<=1e-9:return 1504
    return 0

def kinetic_state(x: P,y: P) -> Float64:
    var v=Vec3(y[unsafe_offset=3],y[unsafe_offset=4],y[unsafe_offset=5]);var w=Vec3(y[unsafe_offset=10],y[unsafe_offset=11],y[unsafe_offset=12]);return .5*(x[unsafe_offset=1]*v.dot(v)+x[unsafe_offset=2]*w.dot(w))

def single_support_advance(inputs: P,previous: P,request: P,output: P,scratch: P,status: P,report: P):
    for i in range(128):output[unsafe_offset=i]=previous[unsafe_offset=i]
    for i in range(32):report[unsafe_offset=i]=0
    report[unsafe_offset=13]=1e30;report[unsafe_offset=14]=-1e30;report[unsafe_offset=29]=1e30;status[unsafe_offset=0]=0;status[unsafe_offset=1]=0
    var H=request[unsafe_offset=8];var ac=request[unsafe_offset=9];var tc=request[unsafe_offset=10]
    if not isfinite(H) or H<=0 or H>1.0/30 or ac<1 or ac>6 or tc<1 or tc>12 or not isfinite(ac) or not isfinite(tc) or ac!=Float64(Int(ac)) or tc!=Float64(Int(tc)):status[unsafe_offset=0]=1500;return
    single_contact_handoff(inputs,previous,request,scratch+512,scratch,status)
    if status[unsafe_offset=0]!=0:return
    var phase=scratch[unsafe_offset=610];var neutral=phase==14
    if phase!=11 and not neutral:status[unsafe_offset=0]=1501;return
    var y=scratch+736;var entry=scratch+768;var full=scratch+800;var half=scratch+832;var half2=scratch+864;var temp=scratch+896;var slopes=scratch+928;var err=scratch+1088;var noise=scratch+1120;var trialerr=scratch+1152;var trialnoise=scratch+1184;var stack=scratch+1216;var physical=scratch+1248;var query=scratch+1344;var bounds=scratch+1472;var ec=scratch+1504;var nc=scratch+1536;var tec=scratch+1568;var tnc=scratch+1600;var budgets=scratch+1632;var tb=scratch+1664;var stage_max=scratch+1696
    for i in range(DIM):y[unsafe_offset=i]=0;err[unsafe_offset=i]=0;noise[unsafe_offset=i]=0;ec[unsafe_offset=i]=0;nc[unsafe_offset=i]=0;budgets[unsafe_offset=i]=1e30
    for i in range(3):y[unsafe_offset=i]=inputs[unsafe_offset=5+i];y[unsafe_offset=3+i]=inputs[unsafe_offset=12+i];y[unsafe_offset=10+i]=inputs[unsafe_offset=15+i]
    for i in range(4):y[unsafe_offset=6+i]=inputs[unsafe_offset=8+i]
    for i in range(DIM):entry[unsafe_offset=i]=y[unsafe_offset=i]
    var initial_code=support_bounds(inputs,y,H,err,noise,bounds,True)
    # Initial drift admission only; reaction/inactive-event bounds use trial h below.
    if initial_code==1502:status[unsafe_offset=0]=1502;return
    var gaproom=1e-9-bounds[unsafe_offset=0];var speedroom=1e-9-bounds[unsafe_offset=1]
    report[unsafe_offset=6]=gaproom;report[unsafe_offset=8]=speedroom
    var T0=kinetic_state(inputs,entry);var EB=1e-9*(1+T0);var elapsed=Float64(0)
    if neutral:
        var ae=external_acc(inputs)
        for k in range(3):
            var a=ae.x if k==0 else ae.y if k==1 else ae.z
            y[unsafe_offset=k]=entry[unsafe_offset=k]+entry[unsafe_offset=3+k]*H+.5*a*H*H;y[unsafe_offset=3+k]=entry[unsafe_offset=3+k]+a*H
        # Total origin moment under constant force: integral x(t) cross m*a_e.
        var integrated=Vec3(entry[unsafe_offset=0],entry[unsafe_offset=1],entry[unsafe_offset=2])*H+Vec3(entry[unsafe_offset=3],entry[unsafe_offset=4],entry[unsafe_offset=5])*(.5*H*H);var origin=integrated.cross(ae*inputs[unsafe_offset=1])
        y[unsafe_offset=18]=origin.x;y[unsafe_offset=19]=origin.y;y[unsafe_offset=20]=origin.z
        var c=scalar_checkpoint(inputs,y,physical,query)
        if c!=0:status[unsafe_offset=0]=1505;status[unsafe_offset=1]=Float64(c);return
        c=support_bounds(inputs,entry,H,err,noise,bounds,True)
        if c!=0:status[unsafe_offset=0]=Float64(c);return
        report[unsafe_offset=27]=1;report[unsafe_offset=1]=1;elapsed=H
    else:
        for base in range(4):
            var accepted=0;var attempts=0;var depth=1;stack[unsafe_offset=0]=H/4
            while depth>0:
                if attempts>=Int(tc) or accepted>=Int(ac):status[unsafe_offset=0]=1506;return
                depth-=1;var h=stack[unsafe_offset=depth];attempts+=1;report[unsafe_offset=2]+=1
                for j in range(DIM):stage_max[unsafe_offset=j]=abs(y[unsafe_offset=j])
                var code=dp_step(inputs,y,h,full,temp,slopes,report,stage_max)
                if code==0:code=dp_step(inputs,y,h/2,half,temp,slopes,report,stage_max)
                if code==0:code=dp_step(inputs,half,h/2,half2,temp,slopes,report,stage_max)
                var localratio=Float64(0)
                if code==0:
                    for j in range(DIM):
                        var delta=8*abs(half2[unsafe_offset=j]-full[unsafe_offset=j])/31;var floor=64*2.220446049250313e-16*(1+max(stage_max[unsafe_offset=j],max(abs(full[unsafe_offset=j]),max(abs(half[unsafe_offset=j]),abs(half2[unsafe_offset=j])))))
                        var de=delta-ec[unsafe_offset=j];var dn=floor-nc[unsafe_offset=j];trialerr[unsafe_offset=j]=err[unsafe_offset=j]+de;trialnoise[unsafe_offset=j]=noise[unsafe_offset=j]+dn;tec[unsafe_offset=j]=(trialerr[unsafe_offset=j]-err[unsafe_offset=j])-de;tnc[unsafe_offset=j]=(trialnoise[unsafe_offset=j]-noise[unsafe_offset=j])-dn
                        var budget=1e-10*(1+min(abs(entry[unsafe_offset=j]),abs(half2[unsafe_offset=j])))
                        if j==17:budget=EB-abs(half2[unsafe_offset=17])
                        budget=min(budget,budgets[unsafe_offset=j]);tb[unsafe_offset=j]=budget
                        if budget<=0 or delta>.5*budget*h/H or floor>.25*budget*h/H or trialerr[unsafe_offset=j]>.5*budget or trialnoise[unsafe_offset=j]>.25*budget:code=1507
                        localratio=max(localratio,(trialerr[unsafe_offset=j]+trialnoise[unsafe_offset=j])/budget)
                    if code==0:
                        var c=scalar_checkpoint(inputs,half,physical,query)
                        if c!=0:code=1505
                    if code==0:
                        var c=scalar_checkpoint(inputs,half2,physical,query)
                        if c!=0:code=1505
                    if code==0:code=support_bounds(inputs,y,h,trialerr,trialnoise,bounds)
                    if code==0 and (bounds[unsafe_offset=0]>1e-9-.25*gaproom or bounds[unsafe_offset=1]>1e-9-.25*speedroom):code=1507
                if code!=0:
                    report[unsafe_offset=28]=Float64(code)
                    if depth+2>16 or h/2<=0 or elapsed+h/2==elapsed:status[unsafe_offset=0]=1506;return
                    stack[unsafe_offset=depth]=h/2;stack[unsafe_offset=depth+1]=h/2;depth+=2
                    continue
                for j in range(DIM):y[unsafe_offset=j]=half2[unsafe_offset=j];err[unsafe_offset=j]=trialerr[unsafe_offset=j];noise[unsafe_offset=j]=trialnoise[unsafe_offset=j];ec[unsafe_offset=j]=tec[unsafe_offset=j];nc[unsafe_offset=j]=tnc[unsafe_offset=j];budgets[unsafe_offset=j]=tb[unsafe_offset=j]
                var norm0=Float64(0);var normhalf=Float64(0);var normend=Float64(0)
                for k in range(6,10):norm0+=entry[unsafe_offset=k]*entry[unsafe_offset=k];normhalf+=half[unsafe_offset=k]*half[unsafe_offset=k];normend+=half2[unsafe_offset=k]*half2[unsafe_offset=k]
                report[unsafe_offset=31]=max(report[unsafe_offset=31],max(abs(normhalf-norm0),abs(normend-norm0)))
                report[unsafe_offset=12]=max(report[unsafe_offset=12],max(abs(normhalf-1),abs(normend-1)))
                accepted+=1;report[unsafe_offset=1]+=1;elapsed+=h;report[unsafe_offset=10]=max(report[unsafe_offset=10],bounds[unsafe_offset=0]);report[unsafe_offset=11]=max(report[unsafe_offset=11],bounds[unsafe_offset=1]);report[unsafe_offset=13]=min(report[unsafe_offset=13],bounds[unsafe_offset=3]);report[unsafe_offset=14]=max(report[unsafe_offset=14],bounds[unsafe_offset=2]);report[unsafe_offset=25]=max(report[unsafe_offset=25],localratio);report[unsafe_offset=29]=min(report[unsafe_offset=29],h)
    for j in range(DIM):report[unsafe_offset=4]=max(report[unsafe_offset=4],err[unsafe_offset=j]);report[unsafe_offset=5]=max(report[unsafe_offset=5],noise[unsafe_offset=j])
    var checkpoint=scalar_checkpoint(inputs,y,physical,query)
    if checkpoint!=0:status[unsafe_offset=0]=1505;status[unsafe_offset=1]=Float64(checkpoint);return
    var p=Vec3(y[unsafe_offset=0],y[unsafe_offset=1],y[unsafe_offset=2]);var p0=Vec3(entry[unsafe_offset=0],entry[unsafe_offset=1],entry[unsafe_offset=2]);var v=Vec3(y[unsafe_offset=3],y[unsafe_offset=4],y[unsafe_offset=5]);var v0=Vec3(entry[unsafe_offset=3],entry[unsafe_offset=4],entry[unsafe_offset=5]);var w=Vec3(y[unsafe_offset=10],y[unsafe_offset=11],y[unsafe_offset=12]);var w0=Vec3(entry[unsafe_offset=10],entry[unsafe_offset=11],entry[unsafe_offset=12]);var mass=inputs[unsafe_offset=1];var inertia=inputs[unsafe_offset=2];var external=external_acc(inputs)*mass;var J=Vec3(0,y[unsafe_offset=13],0);var M=Vec3(y[unsafe_offset=14],y[unsafe_offset=15],y[unsafe_offset=16]);var O=Vec3(y[unsafe_offset=18],y[unsafe_offset=19],y[unsafe_offset=20]);var work=external.dot(p-p0);var dT=kinetic_state(inputs,y)-T0;var E=abs(dT-work-y[unsafe_offset=17]);var ideal=abs(dT-work);var momentum=((v-v0)*mass-external*H-J).length();var angular=((w-w0)*inertia-M).length();var origin=((w-w0)*inertia+p.cross(v*mass)-p0.cross(v0*mass)-O).length()
    var qnorm=Float64(0)
    for j in range(6,10):qnorm+=y[unsafe_offset=j]*y[unsafe_offset=j]
    report[unsafe_offset=12]=max(report[unsafe_offset=12],abs(qnorm-1));report[unsafe_offset=7]=O.x;report[unsafe_offset=9]=O.y;report[unsafe_offset=30]=O.z;report[unsafe_offset=15]=E;report[unsafe_offset=16]=ideal;report[unsafe_offset=17]=momentum;report[unsafe_offset=18]=angular;report[unsafe_offset=19]=origin;report[unsafe_offset=20]=y[unsafe_offset=17];report[unsafe_offset=21]=y[unsafe_offset=13];report[unsafe_offset=26]=query[unsafe_offset=46]
    for k in range(3):report[unsafe_offset=22+k]=y[unsafe_offset=14+k]
    if E>EB or ideal>EB or abs(y[unsafe_offset=17])+err[unsafe_offset=17]+noise[unsafe_offset=17]>.75*EB or momentum>1e-10*(1+(external*H+J).length()) or angular>1e-10*(1+M.length()) or origin>1e-10*(1+O.length()) or abs(qnorm-1)>1e-10:status[unsafe_offset=0]=1508;return
    # Committed elapsed time is exactly the requested H; no epsilon remainder drop.
    if abs(elapsed-H)>8*2.220446049250313e-16*H:status[unsafe_offset=0]=1509;return
    for i in range(128):output[unsafe_offset=i]=scratch[unsafe_offset=512+i]
    for k in range(3):output[unsafe_offset=5+k]=y[unsafe_offset=k];output[unsafe_offset=12+k]=y[unsafe_offset=3+k];output[unsafe_offset=15+k]=y[unsafe_offset=10+k]
    for k in range(4):output[unsafe_offset=8+k]=y[unsafe_offset=6+k]
    for k in range(18,24):output[unsafe_offset=k]=0
    for k in range(45,95):output[unsafe_offset=k]=0
    output[unsafe_offset=98]=17 if neutral else 16
    report[unsafe_offset=0]=H
