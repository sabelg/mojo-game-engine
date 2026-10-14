"""Frozen block physical qualification; independent12-row CPU metric/reference."""
from std.collections import List,Array
from std.testing import assert_equal,assert_true
from std.sys import argv
from std.math import sqrt
from max.gpu.host import DeviceContext
from mojo_game import Vec3,Quaternion,RigidBody3D,MassProperties3D
from experimental.physics_gpu.frozen_floor_friction_block import frozen_floor_friction
from experimental.physics_gpu.lifecycle import body_state,state_words
from experimental.physics_gpu.box_response_reference import reference_block
from experimental.physics_gpu.friction_reference import spectral_min
from experimental.physics_gpu.test_box_interactions import json_values
from experimental.physics_gpu.box_box import float_bits

def scalar_cross(a: Vec3,b: Vec3) -> Vec3:return Vec3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)
def dot(a: Vec3,b: Vec3) -> Float64:return a.x*b.x+a.y*b.y+a.z*b.z
def norm(a: Vec3) -> Float64:return sqrt(dot(a,a))
def energy(m: Float64,I: Vec3,v: Vec3,w: Vec3) -> Float64:return .5*(m*dot(v,v)+I.x*w.x*w.x+I.y*w.y*w.y+I.z*w.z*w.z)

def main() raises:
    var args=argv();assert_equal(len(args),3);var variant=Int(args[2]);assert_true(variant>=0 and variant<4);var m=Float64(2);var I=Vec3(4.0/3,4.0/3,4.0/3);var half=Vec3(.5,.5,.5)
    if variant==1:m=.1;I=Vec3(.01,.02,.025);half=Vec3(.25,.5,.75)
    if variant==2:m=100;I=Vec3(10,100,100);half=Vec3(.75,.5,.25)
    if variant==3:I=Vec3(.2,.3,.4)
    var ctx=DeviceContext();assert_equal(String(ctx.name()),String("NVIDIA GB10"));var input=ctx.enqueue_create_buffer[DType.float64](64);var output=ctx.enqueue_create_buffer[DType.float64](64);input.enqueue_fill(-987654321.25);output.enqueue_fill(-987654321.25)
    with open(args[1]+"-cases.jsonl","w") as out_file:
        for kind in range(26):
            for order in range(24):
                for basis in range(3):
                    var c=Float64(1) if basis==0 else sqrt(Float64(.5)) if basis==1 else Float64(0);var s=Float64(0) if basis==0 else sqrt(Float64(.5)) if basis==1 else Float64(1);var mu=Float64(.2);var beta=Float64(0);var vf=Vec3(.3,-.1,.05);var wf=Vec3(0,0,0)
                    if kind==0:mu=0
                    if kind==1:vf.z=0
                    if kind==2:vf.z=.4
                    if kind==3:vf=Vec3(.005,-.1,.002)
                    if kind==4:vf=Vec3(.012,-.1,0)
                    if kind==5:vf=Vec3(.02,-.1,0)
                    if kind==6:vf=Vec3(.03,-.1,0)
                    if kind==7 or kind==24:vf=Vec3(.3,-1,.4);beta=.5 if kind==7 else 1.0
                    if kind==8 or kind==9:mu=half.x/half.y*(1.0 if kind==8 else 1.1);vf=Vec3(10,-.1,0)
                    if kind==10:mu=.6*sqrt(half.x*half.x+half.z*half.z)/half.y;vf=Vec3(half.x,0,half.z)*(10/sqrt(half.x*half.x+half.z*half.z));vf.y=-.1
                    if kind==11:vf=Vec3(.3,-1e-12,.4)
                    if kind==12:vf=Vec3(.3,0,.4)
                    if kind>=13 and kind<=15:vf=Vec3(.3,-.1,0)
                    if kind==16:wf=Vec3(.1,0,0)
                    if kind==20:vf.y=.1
                    if kind==21:mu=-.2
                    if kind==22:beta=.2
                    if kind==23:c=2;s=0
                    if kind==25:vf=Vec3(.02,-.1,0)
                    var b=RigidBody3D(MassProperties3D(m,I),position=Vec3(0,half.y,0));b.linear_velocity=vf;b.angular_velocity=wf;var r=Array[Vec3,4](fill=Vec3(0,0,0));var old=Array[Vec3,4](fill=Vec3(0,0,0));var seedN=Float64(0);var seedT=Vec3(0,0,0);var N=m*(beta-vf.y)
                    if kind>=13 and kind<=15 or kind==25:
                        seedN=N*(3.0 if kind==13 else .5 if kind==25 else 1.0);seedT=Vec3(mu*seedN*(1.0 if kind==14 else -1.0),0,0)
                    var oldJ=Vec3(0,0,0);var oldTau=Vec3(0,0,0)
                    for i in range(4):
                        r[i]=Vec3(-half.x if i<2 else half.x,-half.y,-half.z if i%2==0 else half.z)
                        if seedN>0:
                            var pressure=seedN/4*(1-r[i].x*half.y*seedT.x/(seedN*half.x*half.x)-r[i].z*half.y*seedT.z/(seedN*half.z*half.z));old[i]=Vec3(pressure/seedN*seedT.x,pressure,pressure/seedN*seedT.z)
                        oldJ=oldJ+old[i];oldTau=oldTau+scalar_cross(r[i],old[i])
                    b.linear_velocity=b.linear_velocity+oldJ*(1/m);b.angular_velocity=b.angular_velocity+Vec3(oldTau.x/I.x,oldTau.y/I.y,oldTau.z/I.z)
                    if kind==17:b.torque=Vec3(0,0,.1)
                    if kind==18:b.orientation=Quaternion.axis_angle(Vec3(1,0,0),.001)
                    if kind==19:b.position.y+=.0001
                    var initial=state_words(body_state(b));var in_values=List[Float64]()
                    with input.map_to_host() as a:
                        for i in range(23):a[i+1]=initial[i]
                        for i in range(4):a[24+i*3]=old[i].y;a[25+i*3]=old[i].x;a[26+i*3]=old[i].z
                        a[37]=half.x;a[38]=half.y;a[39]=half.z;a[40]=mu;a[41]=beta;a[42]=c;a[43]=s;a[44]=Float64(order)
                        for i in range(64):in_values.append(Float64(a[i]))
                    ctx.enqueue_function[frozen_floor_friction](input,output,grid_dim=1,block_dim=1);ctx.synchronize();var av=List[Float64]()
                    with output.map_to_host() as a:
                        assert_equal(Float64(a[0]),Float64(-987654321.25));assert_equal(Float64(a[63]),Float64(-987654321.25))
                        for i in range(64):av.append(Float64(a[i]))
                    with input.map_to_host() as a:
                        for i in range(64):assert_equal(float_bits(Float64(a[i])),float_bits(in_values[i]))
                    var rejected=kind==8 or kind==9 or kind==10 or (kind>=16 and kind<=23);var code=Int(av[36]);var valid=(code!=0) if rejected else code==0;var nr=Float64(0);var tr=Float64(0);var cone=Float64(0);var ratio=Float64(0);var momentum_error=Float64(0);var angular_error=Float64(0);var energy_error=Float64(0);var p_ratio=Float64(0)
                    if rejected:
                        for i in range(1,36):valid=valid and float_bits(av[i])==float_bits(in_values[i])
                    elif code==0:
                        var dirs: Array[Vec3,3]=[Vec3(0,1,0),Vec3(-s,0,-c),Vec3(-c,0,s)];var G=Array[Float64,144](fill=0);var impulse=Array[Float64,12](fill=0);var qfree=Array[Float64,12](fill=0);var J=Vec3(0,0,0);var tau=Vec3(0,0,0);var new=Array[Vec3,4](fill=Vec3(0,0,0))
                        for i in range(4):
                            new[i]=Vec3(av[25+i*3],av[24+i*3],av[26+i*3]);J=J+new[i];tau=tau+scalar_cross(r[i],new[i])
                            for d in range(3):impulse[3*i+d]=dot(new[i],dirs[d]);qfree[3*i+d]=dot(vf+scalar_cross(wf,r[i]),dirs[d])-(beta if d==0 else 0.0)
                        for i in range(12):
                            var ri=scalar_cross(r[i//3],dirs[i%3])
                            for j in range(12):
                                var rj=scalar_cross(r[j//3],dirs[j%3]);G[i*12+j]=dot(dirs[i%3],dirs[j%3])/m+ri.x*rj.x/I.x+ri.y*rj.y/I.y+ri.z*rj.z/I.z
                        var velocity=Array[Float64,12](fill=0);var nn=Array[Float64,16](fill=0);var qn=Array[Float64,4](fill=0)
                        for i in range(12):
                            velocity[i]=qfree[i]
                            for j in range(12):velocity[i]+=G[i*12+j]*impulse[j]
                        for i in range(4):
                            var ix=3*i+1;var iz=ix+1;var p=impulse[3*i];nr=max(nr,abs(velocity[3*i]) if p>0 else max(0.0,-velocity[3*i]));var k=Vec3(G[ix*12+ix],G[ix*12+iz],G[iz*12+iz]);var x=impulse[ix];var z=impulse[iz];var optimum=spectral_min(k,Vec3(velocity[ix]-k.x*x-k.y*z,velocity[iz]-k.y*x-k.z*z,0),mu*p);var dx=x-optimum.x;var dz=z-optimum.y;tr=max(tr,sqrt((k.x*dx+k.y*dz)**2+(k.y*dx+k.z*dz)**2));cone=max(cone,max(0.0,sqrt(x*x+z*z)-mu*p));valid=valid and p>=0 and sqrt(x*x+z*z)<=mu*p+1e-12*(1+mu*p)
                            qn[i]=qfree[3*i]
                            for j in range(4):
                                nn[i*4+j]=G[(3*i)*12+3*j];qn[i]+=G[(3*i)*12+3*j+1]*impulse[3*j+1]+G[(3*i)*12+3*j+2]*impulse[3*j+2]
                        var p_ref=reference_block(nn,qn,4)
                        for i in range(4):p_ratio=max(p_ratio,abs(p_ref[i]-impulse[3*i])/(1e-10*(1+abs(p_ref[i]))))
                        var v=Vec3(av[12],av[13],av[14]);var w=Vec3(av[15],av[16],av[17]);var dj=J-oldJ;var dtau=tau-oldTau;momentum_error=norm((v-b.linear_velocity)*m-dj);angular_error=norm(Vec3(I.x*(w.x-b.angular_velocity.x),I.y*(w.y-b.angular_velocity.y),I.z*(w.z-b.angular_velocity.z))-dtau)
                        var E0=energy(m,I,b.linear_velocity,b.angular_velocity);var Ef=energy(m,I,v,w);var Ef0=energy(m,I,vf,wf);var delta_expected=dot(b.linear_velocity,dj)+dot(b.angular_velocity,dtau)+.5*(dot(dj,dj)/m+dtau.x*dtau.x/I.x+dtau.y*dtau.y/I.y+dtau.z*dtau.z/I.z);energy_error=abs(Ef-E0-delta_expected)
                        var tangential=Vec3(vf.x,0,vf.z);var expectedT=Vec3(0,0,0)
                        if norm(tangential)>0:expectedT=tangential*(-min(m*norm(tangential),mu*N)/norm(tangential))
                        var expected=initial.copy();expected[11]=vf.x+expectedT.x/m;expected[12]=beta;expected[13]=vf.z+expectedT.z/m;expected[14]=wf.x;expected[15]=wf.y;expected[16]=wf.z
                        for i in range(23):ratio=max(ratio,abs(av[i+1]-expected[i])/(1e-10*(1+abs(expected[i]))))
                        valid=valid and ratio<=1 and p_ratio<=1 and nr<=1e-9*(1+abs(vf.y)) and tr<=1e-9*(1+norm(tangential)) and momentum_error<=1e-10*(1+norm(dj)) and angular_error<=1e-10*(1+norm(dtau)) and norm(tau)<=1e-10*(1+norm(J)) and energy_error<=1e-9*(1+E0) and Ef<=E0+1e-9*(1+E0) and Ef<=Ef0+1e-9*(1+Ef0)
                        if kind==13:valid=valid and av[49]>0
                        if kind==15:valid=valid and norm(v-b.linear_velocity)<=1e-10 and norm(w-b.angular_velocity)<=1e-10
                    out_file.write('{"variant":'+String(variant)+',"kind":'+String(kind)+',"order":'+String(order)+',"basis":'+String(basis)+',"expected_reject":'+String(Int(rejected))+',"code":'+String(code)+',"mass":'+String(m)+',"inertia":'+json_values([I.x,I.y,I.z])+',"half":'+json_values([half.x,half.y,half.z])+',"mu":'+String(mu)+',"beta":'+String(beta)+',"free_velocity":'+json_values([vf.x,vf.y,vf.z])+',"input":'+json_values(in_values)+',"output":'+json_values(av)+',"CPU_normal_residual":'+String(nr)+',"CPU_disk_residual":'+String(tr)+',"cone_excess":'+String(cone)+',"state_ratio":'+String(ratio)+',"normal_minimum_norm_ratio":'+String(p_ratio)+',"momentum_error":'+String(momentum_error)+',"angular_error":'+String(angular_error)+',"energy_identity_error":'+String(energy_error)+',"physical_pass":'+String(Int(valid))+'}\n')
                    assert_true(valid,"STOP: cheap friction block physical counterexample; no tuning")
    print("FROZEN_FLOOR_FRICTION_FULL12ROW_CPU_PHYSICAL_PASS",variant,1872)
