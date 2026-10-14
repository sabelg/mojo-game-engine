"""Separate temporal friction owner kernel; qualified block reused verbatim."""
from std.collections import Array
from std.memory import Pointer
from std.math import sqrt,isfinite
from mojo_game import Vec3
from .core import BodyState,component,finite
from .kernels import WORDS,CAPACITY,load,store,SENTINEL
from .response_kernels import body_profile
from .shape_kernels import SHAPES,BOX,mi,vi
from .temporal_patch_floor_kernels import floor_toi,corner,point_speed,inspect,shape_identity,commit_temporal,certified_face
from .frozen_floor_friction_block import frozen_floor_friction

from .temporal_floor_friction_kernels import correct_friction

def correct_unilateral(mut b: BodyState,half: Vec3,floor_y: Float64,mut lambda_n: Array[Float64,4],mut tangent: Array[Vec3,4],target: Float64,sweeps: Int,summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],mu: Float64,order: Int32,inputs: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin]):
    if summary[unsafe_offset=0]!=0:return
    var cold=True
    for i in range(4):cold=cold and lambda_n[i]==0 and tangent[i].x==0 and tangent[i].y==0 and tangent[i].z==0
    if cold and target==0 and b.linear.y>=0 and body_profile(b) and certified_face(b,half,floor_y):
        var residual=Float64(0)
        for i in range(4):residual=max(residual,max(0.0,-point_speed(b,corner(b,half,i))))
        if residual<=1e-9*(1+abs(b.linear.y)):
            # Zero-radius disks and zero wrench satisfy the unchanged gates.
            # Keep real v/omega; do not turn opening motion into a closed row.
            stats[unsafe_offset=3]=residual;stats[unsafe_offset=40]=0;stats[unsafe_offset=41]=0;stats[unsafe_offset=45]+=1
            return
    correct_friction(b,half,floor_y,lambda_n,tangent,target,sweeps,summary,stats,mu,order,inputs,output)

def unilateral_temporal_floor_friction(current: Pointer[Float64,MutAnyOrigin],candidate: Pointer[Float64,MutAnyOrigin],active: Pointer[Int32,MutAnyOrigin],generations: Pointer[UInt64,MutAnyOrigin],namespace: Pointer[UInt64,MutAnyOrigin],meta: Pointer[UInt64,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],group: Pointer[Float64,MutAnyOrigin],episode: Pointer[UInt64,MutAnyOrigin],pending: Pointer[UInt64,MutAnyOrigin],last: Pointer[Float64,MutAnyOrigin],pending_last: Pointer[Float64,MutAnyOrigin],block_input: Pointer[Float64,MutAnyOrigin],block_output: Pointer[Float64,MutAnyOrigin],dt: Float64,gx: Float64,gy: Float64,gz: Float64,e: Float64,mu: Float64,order: Int32,stop_budget: Int32,segment_budget: Int32):
    for i in range(6):summary[unsafe_offset=i]=0
    summary[unsafe_offset=4]=-1;summary[unsafe_offset=5]=-1
    for i in range(1,63):stats[unsafe_offset=i]=0
    for i in range(1,13):group[unsafe_offset=i]=0
    for i in range(WORDS):candidate[unsafe_offset=i]=current[unsafe_offset=i]
    for i in range(1,15):pending[unsafe_offset=i]=0
    var gravity=Vec3(gx,gy,gz)
    if dt!=1.0/30 or not finite(gravity) or not isfinite(e) or e<0 or e>1 or not isfinite(mu) or mu<0 or mu>2 or order<0 or order>=24 or stop_budget<0 or stop_budget>4 or segment_budget<0 or segment_budget>6:summary[unsafe_offset=0]=300;return
    var dynamic=-1;var floor=-1;var nd=0;var nf=0
    for i in range(CAPACITY):
        if active[unsafe_offset=i+1]!=1:continue
        var state=load(current,i)
        if not body_profile(state):summary[unsafe_offset=0]=302;return
        if state.mass>0:dynamic=i;nd+=1
        else:floor=i;nf+=1
    if nd!=1 or nf>1:summary[unsafe_offset=0]=301;return
    summary[unsafe_offset=4]=Int32(dynamic);summary[unsafe_offset=5]=Int32(floor)
    var ds=-1;var fs=-1;var shape_count=0
    for s in range(SHAPES):
        if mi(meta,0,s)!=1:continue
        shape_count+=1
        var body=Int(mi(meta,3,s))
        if mi(meta,6,s)!=BOX or body<0 or body>=CAPACITY or active[unsafe_offset=body+1]!=1 or mi(meta,4,s)!=generations[unsafe_offset=body+1] or mi(meta,5,s)!=namespace[unsafe_offset=1] or not shape_identity(values,s):summary[unsafe_offset=0]=301;return
        if body==dynamic:ds=s
        elif body==floor:fs=s
        else:summary[unsafe_offset=0]=301;return
        for axis in range(4,7):
            if vi(values,axis,s)<.05 or vi(values,axis,s)>10:summary[unsafe_offset=0]=301;return
    if ds<0 or shape_count!=(2 if floor>=0 else 1) or (floor>=0 and fs<0):summary[unsafe_offset=0]=301;return
    var b=load(current,dynamic);var force=b.force;var torque=b.torque;var accel=gravity+force*(1/b.mass)
    var half=Vec3(vi(values,4,ds),vi(values,5,ds),vi(values,6,ds));var floor_y=Float64(0);var touching=False
    var key=Array[UInt64,11](fill=0)
    if floor>=0:
        var f=load(current,floor);var q=b.orientation;var fq=f.orientation
        if abs(q.x)>5e-11 or abs(q.y)>5e-11 or abs(q.z)>5e-11 or abs(q.w-1)>1e-10 or b.angular.length()>1e-10 or component(torque)!=0 or fq.x!=0 or fq.y!=0 or fq.z!=0 or fq.w!=1 or component(f.force)!=0 or component(f.torque)!=0:summary[unsafe_offset=0]=301;return
        if accel.y>0:summary[unsafe_offset=0]=510;return
        floor_y=f.position.y+vi(values,5,fs)
        var vt=Vec3(b.linear.x,0,b.linear.z);var at=Vec3(accel.x,0,accel.z)
        if vt.length()>1e-10 and abs(vt.x*at.z-vt.z*at.x)>1e-12*(1+vt.length()*at.length()):summary[unsafe_offset=0]=511;return
        var gap=b.position.y-half.y-floor_y
        if gap < -1e-9:summary[unsafe_offset=0]=303;return
        # Conservative finite-floor coverage for the entire macro duration.
        var dx=abs(b.linear.x)*dt+.5*abs(accel.x)*dt*dt;var dz=abs(b.linear.z)*dt+.5*abs(accel.z)*dt*dt
        if abs(b.position.x-f.position.x)+half.x+dx>vi(values,4,fs) or abs(b.position.z-f.position.z)+half.z+dz>vi(values,6,fs):summary[unsafe_offset=0]=304;return
        var sa=min(ds,fs);var sb=max(ds,fs)
        # The complete key is constructed directly, with no stale ordinal key.
        for field in range(5):
            key[field]=mi(meta,field+1,sa);key[field+5]=mi(meta,field+1,sb)
        key[0]=UInt64(sa);key[1]=mi(meta,1,sa);key[2]=mi(meta,2,sa);key[3]=mi(meta,3,sa);key[4]=mi(meta,4,sa)
        key[5]=UInt64(sb);key[6]=mi(meta,1,sb);key[7]=mi(meta,2,sb);key[8]=mi(meta,3,sb);key[9]=mi(meta,4,sb);key[10]=namespace[unsafe_offset=1]
        var same=episode[unsafe_offset=1]==1
        for i in range(11):same=same and episode[unsafe_offset=3+i]==key[i]
        for field in range(17):same=same and last[unsafe_offset=1+field]==current[unsafe_offset=field*258+dynamic+1] and last[unsafe_offset=24+field]==current[unsafe_offset=field*258+floor+1]
        touching=same and episode[unsafe_offset=2]==1 and gap<=1e-9
        if gap<=1e-9 and b.linear.y==0:touching=True
    stats[unsafe_offset=13]=floor_y;stats[unsafe_offset=14]=b.position.y;stats[unsafe_offset=15]=accel.y
    var lambda_n=Array[Float64,4](fill=0);var tangent=Array[Vec3,4](fill=Vec3(0,0,0));var last_group=False;var last_target=Float64(0)
    for interval in range(4):
        var remaining=Float64(1.0/120)
        for segment in range(Int(segment_budget)):
            if remaining<=0:break
            if floor<0:
                b.force=force;b.torque=torque
                var status=b.integrate(remaining,gravity,remaining)
                if status!=0:summary[unsafe_offset=0]=302;break
                stats[unsafe_offset=1]+=remaining;remaining=0;last_group=False;break
            var gap=Float64(1e30);var min_speed=Float64(1e30)
            for i in range(4):gap=min(gap,corner(b,half,i).y-floor_y);min_speed=min(min_speed,point_speed(b,corner(b,half,i)))
            if gap>1e-9:touching=False
            # A remembered contact is not proof of a compressive current load.
            # Opening rows at zero acceleration have an admissible zero impulse.
            var normal_tol=1e-9*(1+abs(b.linear.y))
            var unloaded=accel.y==0 and b.linear.y>=0 and min_speed>=-normal_tol
            var force_supported=accel.y<0 and b.linear.y>=0 and b.linear.y<=1e-10 and b.linear.y+accel.y*(remaining*.5)<0 and certified_face(b,half,floor_y)
            if force_supported:
                touching=True
                if b.linear.y>0:stats[unsafe_offset=44]+=1
            elif unloaded or b.linear.y>0:
                touching=False;last_group=False
                lambda_n=Array[Float64,4](fill=0);tangent=Array[Vec3,4](fill=Vec3(0,0,0))
                stats[unsafe_offset=40]=0;stats[unsafe_offset=41]=0
                if unloaded:stats[unsafe_offset=43]+=1
            if touching and min_speed<=1e-9:
                var v=Vec3(b.linear.x,0,b.linear.z);var at=Vec3(accel.x,0,accel.z);var speed=v.length();var force_speed=at.length();var drag=mu*(-accel.y);var class_tol=1e-12*(1+force_speed+drag);var step=remaining;var stopped=False
                if speed>1e-10:
                    if abs(v.x*at.z-v.z*at.x)>1e-12*(1+speed*force_speed):summary[unsafe_offset=0]=511;break
                    var direction=v*(1/speed);var along=at.dot(direction);var decel=drag-along
                    if decel>0:
                        var root=speed/decel;var time_tol=64*2.220446049250313e-16*(1+remaining)
                        if root<=remaining+time_tol:
                            if -along>drag+class_tol:summary[unsafe_offset=0]=512;break
                            step=remaining if abs(root-remaining)<=time_tol else root;stopped=True
                elif force_speed>drag+class_tol:
                    stats[unsafe_offset=36]+=1
                    if stats[unsafe_offset=36]>4:summary[unsafe_offset=0]=516;break
                if step<=0:summary[unsafe_offset=0]=515;break
                b.linear=b.linear+accel*(step*.5)
                lambda_n=Array[Float64,4](fill=0);tangent=Array[Vec3,4](fill=Vec3(0,0,0));correct_unilateral(b,half,floor_y,lambda_n,tangent,0,2,summary,stats,mu,order,block_input,block_output)
                if summary[unsafe_offset=0]!=0:break
                b.force=Vec3(0,0,0);b.torque=Vec3(0,0,0)
                var status=b.integrate(step,Vec3(0,0,0),step)
                if status!=0:summary[unsafe_offset=0]=302;break
                b.linear=b.linear+accel*(step*.5)
                lambda_n=Array[Float64,4](fill=0);tangent=Array[Vec3,4](fill=Vec3(0,0,0));correct_unilateral(b,half,floor_y,lambda_n,tangent,0,2,summary,stats,mu,order,block_input,block_output)
                last_group=True;last_target=0;stats[unsafe_offset=1]+=step;remaining-=step
                inspect(b,half,floor_y,last_target,lambda_n,stats)
                if stats[unsafe_offset=2]>1e-5+1e-9:summary[unsafe_offset=0]=307;break
                if summary[unsafe_offset=0]!=0:break
                if stopped:
                    stats[unsafe_offset=35]+=1;stats[unsafe_offset=37]=stats[unsafe_offset=1]
                    if stats[unsafe_offset=35]>Float64(stop_budget):summary[unsafe_offset=0]=513;break
                    if sqrt(b.linear.x*b.linear.x+b.linear.z*b.linear.z)>1e-10:summary[unsafe_offset=0]=514;break
                continue
            # Analytic impact certificate requires the actual segment-entry
            # physical state to have fixed orientation; never hide induced spin.
            if component(b.angular)>1e-12:summary[unsafe_offset=0]=306;break
            var event=floor_toi(gap,b.linear.y,accel.y,remaining)
            if not event.valid:summary[unsafe_offset=0]=305;break
            var step=event.time if event.found else remaining
            if step>0:
                b.force=force;b.torque=torque
                var status=b.integrate(step,gravity,step)
                if status!=0:summary[unsafe_offset=0]=302;break
                stats[unsafe_offset=1]+=step;remaining-=step
            if not event.found:
                # Validate real endpoint geometry without inventing a normal load.
                var near_residual=Float64(0)
                for i in range(4):
                    var p=corner(b,half,i);var ending_gap=p.y-floor_y
                    stats[unsafe_offset=2]=max(stats[unsafe_offset=2],max(0.0,-ending_gap))
                    if ending_gap < -1e-9:summary[unsafe_offset=0]=521;break
                    if ending_gap<=0:near_residual=max(near_residual,max(0.0,-point_speed(b,p)))
                if near_residual>1e-9*(1+abs(b.linear.y)):summary[unsafe_offset=0]=522
                stats[unsafe_offset=3]=near_residual;last_group=False;break
            summary[unsafe_offset=2]+=1
            if summary[unsafe_offset=2]>4:summary[unsafe_offset=0]=305;break
            var actual_gap=b.position.y-half.y-floor_y
            stats[unsafe_offset=12]=max(stats[unsafe_offset=12],abs(actual_gap));stats[unsafe_offset=9]=b.linear.y;stats[unsafe_offset=11]=stats[unsafe_offset=1]
            if abs(actual_gap)>1e-9:summary[unsafe_offset=0]=305;break
            var target=-e*b.linear.y if b.linear.y<-.2 else 0.0
            lambda_n=Array[Float64,4](fill=0);tangent=Array[Vec3,4](fill=Vec3(0,0,0));correct_unilateral(b,half,floor_y,lambda_n,tangent,target,2,summary,stats,mu,order,block_input,block_output)
            stats[unsafe_offset=10]=b.linear.y;stats[unsafe_offset=17]=component(b.angular)
            inspect(b,half,floor_y,target,lambda_n,stats)
            touching=target==0;last_group=True;last_target=target
            # Physical incoming/outgoing restitution and symmetry are strict
            # gates before another event segment can be certified.
            if stats[unsafe_offset=3]>1e-9*(1+abs(stats[unsafe_offset=9])):summary[unsafe_offset=0]=308;break
            if component(b.angular)>1e-10:summary[unsafe_offset=0]=306;break
        summary[unsafe_offset=1]=Int32(interval+1);stats[unsafe_offset=28]=Float64(interval+1)
        if summary[unsafe_offset=0]!=0:break
        if remaining>0:summary[unsafe_offset=0]=517;break
    if floor>=0 and last_group and summary[unsafe_offset=0]==0:
        # Retain the final end group's pressure. Negative deltas may undo its
        # excess; accumulated pressure remains nonnegative. No group reset.
        correct_unilateral(b,half,floor_y,lambda_n,tangent,last_target,4,summary,stats,mu,order,block_input,block_output)
        inspect(b,half,floor_y,last_target,lambda_n,stats)
        if stats[unsafe_offset=3]>1e-9*(1+abs(stats[unsafe_offset=18])):summary[unsafe_offset=0]=308
        if stats[unsafe_offset=2]>1e-5+1e-9:summary[unsafe_offset=0]=307
    if floor>=0 and (b.angular.length()>1e-4 or stats[unsafe_offset=5]>1e-5):summary[unsafe_offset=0]=306
    if not body_profile(b):summary[unsafe_offset=0]=302
    for i in range(4):group[unsafe_offset=1+i*3]=lambda_n[i];group[unsafe_offset=2+i*3]=tangent[i].x;group[unsafe_offset=3+i*3]=tangent[i].z
    b.force=force;b.torque=torque;store(candidate,dynamic,b)
    if summary[unsafe_offset=0]!=0:return
    b.force=Vec3(0,0,0);b.torque=Vec3(0,0,0);store(candidate,dynamic,b)
    pending[unsafe_offset=1]=1;pending[unsafe_offset=2]=UInt64(1 if floor>=0 and b.position.y-half.y-floor_y<=1e-9 and b.linear.y<=1e-9 else 0)
    for i in range(11):pending[unsafe_offset=3+i]=key[i]
    for field in range(23):
        pending_last[unsafe_offset=1+field]=candidate[unsafe_offset=field*258+dynamic+1]
        pending_last[unsafe_offset=24+field]=candidate[unsafe_offset=field*258+floor+1] if floor>=0 else 0

