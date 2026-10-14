"""Seed preparation and exact private-state retry support; no CPU oracle."""
from std.collections import Array
from std.memory import Pointer
from std.math import sqrt,isfinite
from mojo_game import Vec3
from .shared_operator_math import cached_normal_block_shared
from .shared_operator_cooperative_math import SharedFloat,SharedInt
from .kernels import WORDS

@fieldwise_init
struct TangentSeed(Movable):
    var x: Array[Float64,8]
    var valid: Bool

def prepare_seed(nn: Array[Float64,16],nt: Array[Float64,32],qn: Array[Float64,4],old_x: Array[Float64,8],operators: SharedFloat,valid: Array[Bool,16],count: Int,mu: Float64,tolerance: Float64,n: Vec3,t: Vec3,u: Vec3,sign: Float64,start: Int,mapping: Pointer[Int32,MutAnyOrigin],cache: Pointer[Float64,MutAnyOrigin],diagnostic: Pointer[Int64,MutAnyOrigin]) -> TangentSeed:
    var result=TangentSeed(old_x.copy(),False);var q=qn.copy()
    for i in range(count):
        for j in range(count*2):q[i]+=nt[i*8+j]*old_x[j]
    var pressure=cached_normal_block_shared(nn,q,operators,valid,count,tolerance);diagnostic[unsafe_offset=3]+=1
    if not pressure.valid:return result^
    for i in range(count):
        var index=Int(mapping[unsafe_offset=1+start+i]);var k=1+index*10
        # lambda_n at k+6 is intentionally not used: pressure is current.
        var j=Vec3(cache[unsafe_offset=k+7],cache[unsafe_offset=k+8],cache[unsafe_offset=k+9])*sign;j=j-n*j.dot(n)
        var a=j.dot(t);var b=j.dot(u);var length=sqrt(a*a+b*b);var radius=mu*pressure.impulse[i]
        if not isfinite(length) or not isfinite(radius) or radius<0:return result^
        if length>radius:
            var factor=radius/length;a*=factor;b*=factor;diagnostic[unsafe_offset=4]+=1
        result.x[2*i]=a;result.x[2*i+1]=b
    # Pressure depends on tangent x. Recompute and project once, then require
    # the disk at the final proposed x; no old pressure may authorize a seed.
    q=qn.copy()
    for i in range(count):
        for j in range(count*2):q[i]+=nt[i*8+j]*result.x[j]
    pressure=cached_normal_block_shared(nn,q,operators,valid,count,tolerance);diagnostic[unsafe_offset=3]+=1
    if not pressure.valid:return result^
    for i in range(count):
        var a=result.x[2*i];var b=result.x[2*i+1];var length=sqrt(a*a+b*b);var radius=mu*pressure.impulse[i]
        if not isfinite(length) or not isfinite(radius) or radius<0:return result^
        if length>radius:
            var factor=radius/length;result.x[2*i]*=factor;result.x[2*i+1]*=factor;diagnostic[unsafe_offset=4]+=1
    q=qn.copy()
    for i in range(count):
        for j in range(count*2):q[i]+=nt[i*8+j]*result.x[j]
    pressure=cached_normal_block_shared(nn,q,operators,valid,count,tolerance);diagnostic[unsafe_offset=3]+=1
    if not pressure.valid:return result^
    for i in range(count):
        var radius=mu*pressure.impulse[i];var length=sqrt(result.x[2*i]**2+result.x[2*i+1]**2)
        if not isfinite(radius) or not isfinite(length) or radius<0 or length>radius+1e-12*(1+radius):return result^
    result.valid=True;return result^

def patch_save(shared: SharedFloat,flags: SharedInt,impulses: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],start: Int,count: Int,work: Pointer[Int64,MutAnyOrigin],debug: Pointer[Int64,MutAnyOrigin],saved_f: Pointer[Float64,MutAnyOrigin],saved_i: Pointer[Int64,MutAnyOrigin]):
    for i in range(506):saved_f[unsafe_offset=1+i]=shared[unsafe_offset=i]
    for i in range(count):saved_f[unsafe_offset=507+i]=impulses[unsafe_offset=1+start+i]
    for i in range(count*2):saved_f[unsafe_offset=511+i]=tangent[unsafe_offset=1+start*2+i]
    for i in range(32):saved_i[unsafe_offset=1+i]=Int64(flags[unsafe_offset=i])
    for i in range(16):saved_i[unsafe_offset=33+i]=work[unsafe_offset=i]
    for i in range(18):saved_i[unsafe_offset=49+i]=debug[unsafe_offset=i]

def patch_restore(shared: SharedFloat,flags: SharedInt,impulses: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],start: Int,count: Int,work: Pointer[Int64,MutAnyOrigin],debug: Pointer[Int64,MutAnyOrigin],saved_f: Pointer[Float64,MutAnyOrigin],saved_i: Pointer[Int64,MutAnyOrigin],diagnostic: Pointer[Int64,MutAnyOrigin]):
    diagnostic[unsafe_offset=6]+=1
    for i in range(10):
        if i==8:diagnostic[unsafe_offset=10+i]=max(diagnostic[unsafe_offset=10+i],work[unsafe_offset=i])
        else:diagnostic[unsafe_offset=10+i]+=work[unsafe_offset=i]-saved_i[unsafe_offset=33+i]
    for i in range(18):diagnostic[unsafe_offset=20+i]+=debug[unsafe_offset=i]-saved_i[unsafe_offset=49+i]
    for i in range(506):shared[unsafe_offset=i]=saved_f[unsafe_offset=1+i]
    for i in range(count):impulses[unsafe_offset=1+start+i]=saved_f[unsafe_offset=507+i]
    for i in range(count*2):tangent[unsafe_offset=1+start*2+i]=saved_f[unsafe_offset=511+i]
    for i in range(32):flags[unsafe_offset=i]=Int32(saved_i[unsafe_offset=1+i])
    for i in range(16):work[unsafe_offset=i]=saved_i[unsafe_offset=33+i]
    for i in range(18):debug[unsafe_offset=i]=saved_i[unsafe_offset=49+i]

def seed_begin(consumed: Pointer[Int32,MutAnyOrigin],diagnostic: Pointer[Int64,MutAnyOrigin],retry: Pointer[Int32,MutAnyOrigin]):
    for i in range(16):consumed[unsafe_offset=1+i]=0
    for i in range(1,65):diagnostic[unsafe_offset=i]=0
    retry[unsafe_offset=1]=0

# Float snapshot layout: stats9,normal66,tangent130,history194,metrics1826.
# Int snapshot: summary6,work16,debug18. All guards/tails are restored too.
def whole_save(summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],history: Pointer[Float64,MutAnyOrigin],metrics: Pointer[Float64,MutAnyOrigin],work: Pointer[Int64,MutAnyOrigin],debug: Pointer[Int64,MutAnyOrigin],saved_f: Pointer[Float64,MutAnyOrigin],saved_i: Pointer[Int64,MutAnyOrigin]):
    if summary[unsafe_offset=0]!=0:return
    for i in range(9):saved_f[unsafe_offset=1+i]=stats[unsafe_offset=i]
    for i in range(66):saved_f[unsafe_offset=10+i]=impulses[unsafe_offset=i]
    for i in range(130):saved_f[unsafe_offset=76+i]=tangent[unsafe_offset=i]
    for i in range(194):saved_f[unsafe_offset=206+i]=history[unsafe_offset=i]
    for i in range(1826):saved_f[unsafe_offset=400+i]=metrics[unsafe_offset=i]
    for i in range(6):saved_i[unsafe_offset=1+i]=Int64(summary[unsafe_offset=i])
    for i in range(16):saved_i[unsafe_offset=7+i]=work[unsafe_offset=i]
    for i in range(18):saved_i[unsafe_offset=23+i]=debug[unsafe_offset=i]

def whole_restore_if_needed(candidate: Pointer[Float64,MutAnyOrigin],projected: Pointer[Float64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],stats: Pointer[Float64,MutAnyOrigin],impulses: Pointer[Float64,MutAnyOrigin],tangent: Pointer[Float64,MutAnyOrigin],history: Pointer[Float64,MutAnyOrigin],metrics: Pointer[Float64,MutAnyOrigin],work: Pointer[Int64,MutAnyOrigin],debug: Pointer[Int64,MutAnyOrigin],saved_f: Pointer[Float64,MutAnyOrigin],saved_i: Pointer[Int64,MutAnyOrigin],diagnostic: Pointer[Int64,MutAnyOrigin],retry: Pointer[Int32,MutAnyOrigin]):
    if summary[unsafe_offset=0]==0 or diagnostic[unsafe_offset=9]==0:return
    retry[unsafe_offset=1]=1;diagnostic[unsafe_offset=7]+=1;diagnostic[unsafe_offset=8]=Int64(summary[unsafe_offset=0])
    for i in range(10):
        if i==8:diagnostic[unsafe_offset=10+i]=max(diagnostic[unsafe_offset=10+i],work[unsafe_offset=i])
        else:diagnostic[unsafe_offset=10+i]+=work[unsafe_offset=i]
    for i in range(18):diagnostic[unsafe_offset=20+i]+=debug[unsafe_offset=i]
    for i in range(WORDS):candidate[unsafe_offset=i]=projected[unsafe_offset=i]
    for i in range(9):stats[unsafe_offset=i]=saved_f[unsafe_offset=1+i]
    for i in range(66):impulses[unsafe_offset=i]=saved_f[unsafe_offset=10+i]
    for i in range(130):tangent[unsafe_offset=i]=saved_f[unsafe_offset=76+i]
    for i in range(194):history[unsafe_offset=i]=saved_f[unsafe_offset=206+i]
    for i in range(1826):metrics[unsafe_offset=i]=saved_f[unsafe_offset=400+i]
    for i in range(6):summary[unsafe_offset=i]=Int32(saved_i[unsafe_offset=1+i])
    for i in range(16):work[unsafe_offset=i]=saved_i[unsafe_offset=7+i]
    for i in range(18):debug[unsafe_offset=i]=saved_i[unsafe_offset=23+i]
