"""Isolated arbitrary-pose frictionless unique-vertex impulse; no advance owner."""
from std.collections import Array
from std.memory import Pointer
from std.math import isfinite,sqrt
from mojo_game import Vec3,Quaternion
from .core import BodyState,finite,component,qfinite,momentum
from .response_kernels import inv_inertia,kinetic,body_profile

def rotating_floor_vertex_impact(inputs: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin]):
    # Public state/descriptor payload publishes only after all gates; canaries0/95.
    for i in range(1,95):output[unsafe_offset=i]=inputs[unsafe_offset=i] if i<=38 else 0.0
    var b=BodyState(inputs[unsafe_offset=1],Vec3(inputs[unsafe_offset=2],inputs[unsafe_offset=3],inputs[unsafe_offset=4]),Vec3(inputs[unsafe_offset=5],inputs[unsafe_offset=6],inputs[unsafe_offset=7]),Quaternion(inputs[unsafe_offset=8],inputs[unsafe_offset=9],inputs[unsafe_offset=10],inputs[unsafe_offset=11]),Vec3(inputs[unsafe_offset=12],inputs[unsafe_offset=13],inputs[unsafe_offset=14]),Vec3(inputs[unsafe_offset=15],inputs[unsafe_offset=16],inputs[unsafe_offset=17]),Vec3(inputs[unsafe_offset=18],inputs[unsafe_offset=19],inputs[unsafe_offset=20]),Vec3(inputs[unsafe_offset=21],inputs[unsafe_offset=22],inputs[unsafe_offset=23]))
    if not body_profile(b) or b.mass<=0:output[unsafe_offset=39]=600;return
    var half=Vec3(inputs[unsafe_offset=24],inputs[unsafe_offset=25],inputs[unsafe_offset=26]);var center=Vec3(inputs[unsafe_offset=27],inputs[unsafe_offset=28],inputs[unsafe_offset=29]);var shape=Quaternion(inputs[unsafe_offset=30],inputs[unsafe_offset=31],inputs[unsafe_offset=32],inputs[unsafe_offset=33]);var floor_y=inputs[unsafe_offset=34];var shape_norm=shape.x*shape.x+shape.y*shape.y+shape.z*shape.z+shape.w*shape.w
    if not finite(half) or min(half.x,min(half.y,half.z))<.05 or component(half)>10 or not finite(center) or component(center)>10 or not qfinite(shape) or abs(shape_norm-1)>1e-10 or not isfinite(floor_y) or abs(floor_y)>1000:output[unsafe_offset=39]=601;return
    var mu=inputs[unsafe_offset=35];var e=inputs[unsafe_offset=36];var episode=inputs[unsafe_offset=37];var enumeration=inputs[unsafe_offset=38]
    if mu!=0 or not isfinite(e) or e<0 or e>1 or (episode!=0 and episode!=1) or not isfinite(enumeration) or enumeration<0 or enumeration>15 or enumeration!=Float64(Int(enumeration)):output[unsafe_offset=39]=602;return
    var arms=Array[Vec3,8](fill=Vec3(0,0,0));var gaps=Array[Float64,8](fill=0);var speeds=Array[Float64,8](fill=0);var best=Float64(1e30);var selected=8
    for visit in range(8):
        var i=(visit+Int(enumeration)%8)%8 if enumeration<8 else (7-visit+Int(enumeration)%8)%8
        var local=Vec3(-half.x if i%2==0 else half.x,-half.y if (i//2)%2==0 else half.y,-half.z if (i//4)%2==0 else half.z)
        arms[i]=b.orientation.rotate(center+shape.rotate(local));var p=b.position+arms[i];gaps[i]=p.y-floor_y;speeds[i]=(b.linear+b.angular.cross(arms[i])).y
        output[unsafe_offset=75+i]=gaps[i];output[unsafe_offset=83+i]=speeds[i]
        if gaps[i]<best or (gaps[i]==best and i<selected):best=gaps[i];selected=i
    output[unsafe_offset=40]=Float64(selected);output[unsafe_offset=41]=best
    if selected>=8 or not isfinite(best) or abs(best)>1e-9:output[unsafe_offset=39]=603;return
    var second=Float64(1e30)
    for i in range(8):
        if i!=selected:second=min(second,gaps[i])
    output[unsafe_offset=42]=second
    if second<=1e-9:output[unsafe_offset=39]=604;return
    var r=arms[selected];var p=b.position+r;var axes: Array[Vec3,3]=[Vec3(1,0,0),Vec3(0,1,0),Vec3(0,0,1)];var K=Array[Float64,9](fill=0)
    for i in range(3):
        for j in range(3):
            K[i*3+j]=(1/b.mass if i==j else 0.0)+r.cross(axes[i]).dot(inv_inertia(b,r.cross(axes[j])))
            output[unsafe_offset=60+i*3+j]=K[i*3+j]
    var determinant=K[0]*(K[4]*K[8]-K[5]*K[7])-K[1]*(K[3]*K[8]-K[5]*K[6])+K[2]*(K[3]*K[7]-K[4]*K[6]);output[unsafe_offset=59]=determinant
    if not isfinite(determinant) or determinant<=0 or K[0]<=0 or K[4]<=0 or K[8]<=0:output[unsafe_offset=39]=605;return
    var incoming=speeds[selected];var beta=-e*incoming if episode==1 and incoming<-.2 else 0.0;var impulse=(beta-incoming)/K[4] if incoming<0 else 0.0;var effective=e if episode==1 and incoming<-.2 else 0.0
    output[unsafe_offset=43]=incoming;output[unsafe_offset=44]=beta;output[unsafe_offset=45]=impulse;output[unsafe_offset=46]=K[4];output[unsafe_offset=56]=effective
    output[unsafe_offset=69]=r.x;output[unsafe_offset=70]=r.y;output[unsafe_offset=71]=r.z;output[unsafe_offset=72]=p.x;output[unsafe_offset=73]=p.y;output[unsafe_offset=74]=p.z
    var J=Vec3(0,impulse,0);var tau=r.cross(J);var trial=b
    # Zero impulse leaves even signed-zero bits unchanged. No angular clamp.
    if impulse>0:trial.linear=b.linear+J*(1/b.mass);trial.angular=b.angular+inv_inertia(b,tau)
    var vn=(trial.linear+trial.angular.cross(r)).y;var residual=abs(vn-beta) if impulse>0 else max(0.0,-vn);var tolerance=1e-9*(1+abs(incoming));var before=kinetic(b);var after=kinetic(trial);var loss=.5*(1-effective*effective)*incoming*incoming/K[4] if impulse>0 else 0.0
    var dp=(trial.linear-b.linear)*b.mass;var dL=momentum(trial.orientation,trial.inertia,trial.angular)-momentum(b.orientation,b.inertia,b.angular);var perr=(dp-J).length();var Lerr=(dL-tau).length();var origin_err=(dL+b.position.cross(dp)-p.cross(J)).length();var energy_error=abs(after-before+loss)
    output[unsafe_offset=47]=residual;output[unsafe_offset=48]=before;output[unsafe_offset=49]=after;output[unsafe_offset=50]=loss;output[unsafe_offset=51]=perr;output[unsafe_offset=52]=Lerr;output[unsafe_offset=53]=origin_err;output[unsafe_offset=54]=tolerance;output[unsafe_offset=57]=b.angular.length();output[unsafe_offset=58]=trial.angular.length();output[unsafe_offset=91]=b.orientation.x*b.orientation.x+b.orientation.y*b.orientation.y+b.orientation.z*b.orientation.z+b.orientation.w*b.orientation.w;output[unsafe_offset=92]=shape_norm;output[unsafe_offset=93]=energy_error;output[unsafe_offset=94]=vn
    if not body_profile(trial):output[unsafe_offset=39]=606;return
    if not isfinite(impulse) or impulse<0 or residual>tolerance or after>before+1e-9*(1+before) or energy_error>1e-9*(1+before) or perr>1e-10*(1+J.length()) or Lerr>1e-10*(1+tau.length()) or origin_err>1e-10*(1+p.cross(J).length()):output[unsafe_offset=39]=607;return
    if impulse>0:
        output[unsafe_offset=12]=trial.linear.x;output[unsafe_offset=13]=trial.linear.y;output[unsafe_offset=14]=trial.linear.z;output[unsafe_offset=15]=trial.angular.x;output[unsafe_offset=16]=trial.angular.y;output[unsafe_offset=17]=trial.angular.z
        output[unsafe_offset=55]=episode
