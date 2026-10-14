"""Separate bounded single-body transaction; exact geometry and cold impulses."""
from std.memory import Pointer
from std.math import isfinite
from std.collections import Array
from mojo_game import Vec3,Quaternion
from .core import BodyState,component,finite,qfinite,momentum
from .response_kernels import body_profile,kinetic
from .rotating_monotone_toi import rotating_monotone_toi,sweep_pose
from .rotating_concave_toi import rotating_concave_toi
from .rotating_floor_vertex_impact import rotating_floor_vertex_impact

def load_rotating_body(a: Pointer[Float64,MutAnyOrigin]) -> BodyState:
    return BodyState(a[unsafe_offset=1],Vec3(a[unsafe_offset=2],a[unsafe_offset=3],a[unsafe_offset=4]),Vec3(a[unsafe_offset=5],a[unsafe_offset=6],a[unsafe_offset=7]),Quaternion(a[unsafe_offset=8],a[unsafe_offset=9],a[unsafe_offset=10],a[unsafe_offset=11]),Vec3(a[unsafe_offset=12],a[unsafe_offset=13],a[unsafe_offset=14]),Vec3(a[unsafe_offset=15],a[unsafe_offset=16],a[unsafe_offset=17]),Vec3(a[unsafe_offset=18],a[unsafe_offset=19],a[unsafe_offset=20]),Vec3(a[unsafe_offset=21],a[unsafe_offset=22],a[unsafe_offset=23]))

@fieldwise_init
struct RotatingFloorGeometry(ImplicitlyCopyable,Movable):
    var gap: Float64
    var second: Float64
    var vertex: Int
    var speed: Float64

def rotating_geometry(a: Pointer[Float64,MutAnyOrigin],b: BodyState) -> RotatingFloorGeometry:
    var half=Vec3(a[unsafe_offset=24],a[unsafe_offset=25],a[unsafe_offset=26]);var center=Vec3(a[unsafe_offset=27],a[unsafe_offset=28],a[unsafe_offset=29]);var shape=Quaternion(a[unsafe_offset=30],a[unsafe_offset=31],a[unsafe_offset=32],a[unsafe_offset=33]);var floor=a[unsafe_offset=34];var best=Float64(1e30);var second=Float64(1e30);var vertex=8;var speed=Float64(0)
    for i in range(8):
        var corner=Vec3(-half.x if i%2==0 else half.x,-half.y if (i//2)%2==0 else half.y,-half.z if (i//4)%2==0 else half.z);var r=b.orientation.rotate(center+shape.rotate(corner));var gap=b.position.y+r.y-floor
        if gap<best:second=best;best=gap;vertex=i;speed=(b.linear+b.angular.cross(r)).y
        else:second=min(second,gap)
    return RotatingFloorGeometry(best,second,vertex,speed)

def rotating_floor_advance(current: Pointer[Float64,MutAnyOrigin],candidate: Pointer[Float64,MutAnyOrigin],scratch: Pointer[Float64,MutAnyOrigin],result: Pointer[Float64,MutAnyOrigin]):
    for i in range(1,191):candidate[unsafe_offset=i]=current[unsafe_offset=i]
    for i in range(44,95):candidate[unsafe_offset=i]=0
    candidate[unsafe_offset=39]=0
    for i in range(96):scratch[unsafe_offset=i]=current[unsafe_offset=i];result[unsafe_offset=i]=current[unsafe_offset=i]
    var H=current[unsafe_offset=40];var event_limit=current[unsafe_offset=102];var segment_limit=current[unsafe_offset=103]
    if not isfinite(H) or H<=0 or H>1.0/30 or not isfinite(event_limit) or event_limit<0 or event_limit>4 or event_limit!=Float64(Int(event_limit)) or not isfinite(segment_limit) or segment_limit<0 or segment_limit>6 or segment_limit!=Float64(Int(segment_limit)):candidate[unsafe_offset=39]=900;return
    for i in range(96,102):
        var value=current[unsafe_offset=i]
        if not isfinite(value) or value<1 or value>1000000000 or value!=Float64(Int(value)):candidate[unsafe_offset=39]=901;return
    var initial=load_rotating_body(scratch);var gravity=Vec3(current[unsafe_offset=41],current[unsafe_offset=42],current[unsafe_offset=43]);var half=Vec3(scratch[unsafe_offset=24],scratch[unsafe_offset=25],scratch[unsafe_offset=26]);var center=Vec3(scratch[unsafe_offset=27],scratch[unsafe_offset=28],scratch[unsafe_offset=29]);var shape=Quaternion(scratch[unsafe_offset=30],scratch[unsafe_offset=31],scratch[unsafe_offset=32],scratch[unsafe_offset=33]);var qnorm=shape.x*shape.x+shape.y*shape.y+shape.z*shape.z+shape.w*shape.w;var e=scratch[unsafe_offset=36];var order=scratch[unsafe_offset=38]
    if not body_profile(initial) or initial.mass<=0 or not finite(gravity) or not finite(half) or min(half.x,min(half.y,half.z))<.05 or component(half)>10 or not finite(center) or component(center)>10 or not qfinite(shape) or abs(qnorm-1)>1e-10 or not isfinite(scratch[unsafe_offset=34]) or abs(scratch[unsafe_offset=34])>1000 or not isfinite(e) or e<0 or e>1 or not isfinite(order) or order<0 or order>15 or order!=Float64(Int(order)):candidate[unsafe_offset=39]=902;return
    if initial.inertia.x!=initial.inertia.y or initial.inertia.x!=initial.inertia.z or component(initial.torque)!=0 or scratch[unsafe_offset=35]!=0:candidate[unsafe_offset=39]=903;return
    var initialized=current[unsafe_offset=112]==1;var armed=current[unsafe_offset=113]==1;var last_vertex=current[unsafe_offset=114];var episodes=current[unsafe_offset=115];var changed=False
    if (current[unsafe_offset=112]!=0 and current[unsafe_offset=112]!=1) or (current[unsafe_offset=113]!=0 and current[unsafe_offset=113]!=1) or not isfinite(episodes) or episodes<0 or episodes>1000000000 or episodes!=Float64(Int(episodes)):candidate[unsafe_offset=39]=901;return
    if initialized:
        for i in range(6):changed=changed or current[unsafe_offset=96+i]!=current[unsafe_offset=116+i]
        for i in range(13):changed=changed or current[unsafe_offset=5+i]!=current[unsafe_offset=122+i] or current[unsafe_offset=24+i]!=current[unsafe_offset=135+i]
        for i in range(4):changed=changed or current[unsafe_offset=1+i]!=current[unsafe_offset=148+i]
    var entry=rotating_geometry(scratch,initial)
    if entry.gap < -1e-9 or entry.second<=1e-9:candidate[unsafe_offset=39]=904;return
    if entry.gap>1e-9:armed=True
    elif initialized and changed:candidate[unsafe_offset=39]=905;return
    elif not initialized:armed=entry.speed< -1e-9*(1+abs(initial.linear.y)+initial.angular.length())
    scratch[unsafe_offset=37]=0
    var elapsed=Float64(0);var events=0;var zero_events=0;var segments=0;var work=Float64(0);var loss=Float64(0);var impulse=Vec3(0,0,0);var angular_impulse=Vec3(0,0,0)
    for base in range(4):
        var target=H*Float64(base+1)/4
        for segment in range(6):
            if elapsed>=target:break
            candidate[unsafe_offset=44]=elapsed;candidate[unsafe_offset=45]=Float64(events);candidate[unsafe_offset=46]=Float64(zero_events);candidate[unsafe_offset=47]=Float64(segments)
            if segment>=Int(segment_limit):candidate[unsafe_offset=39]=906;return
            var b=load_rotating_body(scratch);var geometry=rotating_geometry(scratch,b);var remaining=target-elapsed;var hit=False
            if geometry.gap<=1e-9 and geometry.speed< -1e-9*(1+abs(b.linear.y)+b.angular.length()):
                if not armed or (elapsed>0):candidate[unsafe_offset=39]=907;return
                hit=True;zero_events+=1
            else:
                scratch[unsafe_offset=40]=remaining
                rotating_monotone_toi(scratch,result)
                if result[unsafe_offset=39]!=0:rotating_concave_toi(scratch,result)
                if result[unsafe_offset=39]!=0:candidate[unsafe_offset=39]=908;candidate[unsafe_offset=57]=result[unsafe_offset=39];return
                var t=result[unsafe_offset=45];hit=result[unsafe_offset=44]==1
                # Do not assign an unresolved terminal crossing to either side
                # of a base boundary, or discard its tiny positive remainder.
                if (hit and remaining-t<=1e-9) or (not hit and result[unsafe_offset=50]<=1e-9 and result[unsafe_offset=68+Int(result[unsafe_offset=49])]<0):candidate[unsafe_offset=39]=916;return
                if t<=0 or t>remaining or elapsed+t<=elapsed:candidate[unsafe_offset=39]=909;return
                if hit and not armed:
                    var middle=sweep_pose(b,gravity+b.force*(1/b.mass),t*.5)
                    if rotating_geometry(scratch,middle).gap<=1e-9:candidate[unsafe_offset=39]=910;return
                    armed=True
                work+=result[unsafe_offset=52]
                for i in range(1,39):scratch[unsafe_offset=i]=result[unsafe_offset=i]
                scratch[unsafe_offset=37]=0
                elapsed=target if t==remaining else elapsed+t;segments+=1
                if not hit:
                    if rotating_geometry(scratch,load_rotating_body(scratch)).gap>1e-9:armed=True
                    continue
            if hit:
                candidate[unsafe_offset=44]=elapsed;candidate[unsafe_offset=45]=Float64(events);candidate[unsafe_offset=47]=Float64(segments)
                if events>=Int(event_limit):candidate[unsafe_offset=39]=911;return
                if not armed:candidate[unsafe_offset=39]=910;return
                scratch[unsafe_offset=37]=1
                rotating_floor_vertex_impact(scratch,result)
                if result[unsafe_offset=39]!=0:candidate[unsafe_offset=39]=912;candidate[unsafe_offset=57]=result[unsafe_offset=39];return
                if result[unsafe_offset=45]<=0:candidate[unsafe_offset=39]=913;return
                var J=Vec3(0,result[unsafe_offset=45],0);var r=Vec3(result[unsafe_offset=69],result[unsafe_offset=70],result[unsafe_offset=71]);impulse=impulse+J;angular_impulse=angular_impulse+r.cross(J);loss+=result[unsafe_offset=50];events+=1;episodes+=1;last_vertex=result[unsafe_offset=40];armed=False
                # At most four event witnesses: time, vertex, incoming speed,
                # frozen restitution target, impulse and physical impact loss.
                var witness=58+(events-1)*6;candidate[unsafe_offset=witness]=elapsed;candidate[unsafe_offset=witness+1]=last_vertex;candidate[unsafe_offset=witness+2]=result[unsafe_offset=43];candidate[unsafe_offset=witness+3]=result[unsafe_offset=44];candidate[unsafe_offset=witness+4]=result[unsafe_offset=45];candidate[unsafe_offset=witness+5]=result[unsafe_offset=50]
                for i in range(1,39):scratch[unsafe_offset=i]=result[unsafe_offset=i]
                scratch[unsafe_offset=37]=0
                if elapsed<H:
                    var post=load_rotating_body(scratch);var post_geometry=rotating_geometry(scratch,post)
                    if post_geometry.speed<=1e-9*(1+abs(post.linear.y)+post.angular.length()):candidate[unsafe_offset=39]=914;return
        if elapsed<target:candidate[unsafe_offset=39]=906;return
    var final=load_rotating_body(scratch);var before=kinetic(initial);var after=kinetic(final);var p_error=((final.linear-initial.linear)*initial.mass-(gravity*initial.mass+initial.force)*H-impulse).length();var L_error=(momentum(final.orientation,final.inertia,final.angular)-momentum(initial.orientation,initial.inertia,initial.angular)-angular_impulse).length();var E_error=abs(after-before-work+loss)
    if elapsed!=H or p_error>1e-10*(1+impulse.length()+((gravity*initial.mass+initial.force)*H).length()) or L_error>1e-10*(1+angular_impulse.length()) or E_error>1e-9*(1+before) or not body_profile(final):candidate[unsafe_offset=39]=915;return
    for i in range(1,39):candidate[unsafe_offset=i]=scratch[unsafe_offset=i]
    for i in range(18,24):candidate[unsafe_offset=i]=0
    candidate[unsafe_offset=37]=current[unsafe_offset=37]
    candidate[unsafe_offset=44]=elapsed;candidate[unsafe_offset=45]=Float64(events);candidate[unsafe_offset=46]=Float64(zero_events);candidate[unsafe_offset=47]=Float64(segments);candidate[unsafe_offset=48]=work;candidate[unsafe_offset=49]=loss;candidate[unsafe_offset=50]=impulse.y;candidate[unsafe_offset=51]=angular_impulse.x;candidate[unsafe_offset=52]=angular_impulse.y;candidate[unsafe_offset=53]=angular_impulse.z;candidate[unsafe_offset=54]=before;candidate[unsafe_offset=55]=after;candidate[unsafe_offset=82]=p_error;candidate[unsafe_offset=83]=L_error;candidate[unsafe_offset=84]=E_error
    candidate[unsafe_offset=112]=1;candidate[unsafe_offset=113]=Float64(Int(armed));candidate[unsafe_offset=114]=last_vertex;candidate[unsafe_offset=115]=episodes
    for i in range(6):candidate[unsafe_offset=116+i]=current[unsafe_offset=96+i]
    for i in range(13):candidate[unsafe_offset=122+i]=candidate[unsafe_offset=5+i];candidate[unsafe_offset=135+i]=current[unsafe_offset=24+i]
    for i in range(4):candidate[unsafe_offset=148+i]=current[unsafe_offset=1+i]

def commit_rotating_advance(current: Pointer[Float64,MutAnyOrigin],candidate: Pointer[Float64,MutAnyOrigin]):
    if candidate[unsafe_offset=39]==0:
        for i in range(1,191):current[unsafe_offset=i]=candidate[unsafe_offset=i]
