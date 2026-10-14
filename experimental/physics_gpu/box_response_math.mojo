"""Bounded footprint reduction and PSD normal patch blocks; no body commits."""
from std.collections import Array
from std.math import sqrt,isfinite
from mojo_game import Vec3
from .box_box_kernels import Patch,EPS
from .friction_kernels import tangent_axes

@fieldwise_init
struct ReducedPatch(Movable):
    var indices: Array[Int,4]
    var count: Int

def cross2(a: Vec3,b: Vec3,c: Vec3) -> Float64:
    return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)

def reduce_patch(p: Patch,n: Vec3,resolution: Float64) -> ReducedPatch:
    var basis=tangent_axes(n,1,0);var uv=Array[Vec3,9](fill=Vec3(0,0,0));var order=Array[Int,9](fill=0)
    var count=Int(p.count)
    for i in range(count):
        var midpoint=(p.a[i]+p.b[i])*.5;uv[i]=Vec3(midpoint.dot(basis[0]),midpoint.dot(basis[1]),0);order[i]=i
    for i in range(count):
        for j in range(i+1,count):
            var a=uv[order[i]];var b=uv[order[j]]
            if b.x<a.x or (b.x==a.x and b.y<a.y):var old=order[i];order[i]=order[j];order[j]=old
    var hull=Array[Int,18](fill=0);var used=0
    for leg in range(2):
        var base=used
        for k in range(count):
            var index=order[k] if leg==0 else order[count-1-k]
            while used>=base+2:
                var a=uv[hull[used-2]];var b=uv[hull[used-1]];var c=uv[index]
                var band=resolution*(1+abs(b.x-a.x)+abs(b.y-a.y)+abs(c.x-a.x)+abs(c.y-a.y))
                if cross2(a,b,c)>band:break
                used-=1
            hull[used]=index;used+=1
        if used>0:used-=1
    var result=ReducedPatch(Array[Int,4](fill=0),0)
    if count==1:result.count=1;return result^
    if used<=2:
        var greatest=Float64(-1);var first=0;var second=0
        for i in range(count):
            for j in range(i+1,count):
                var d=uv[i]-uv[j];var distance=d.dot(d)
                if distance>greatest:greatest=distance;first=i;second=j
        result.indices[0]=first;result.indices[1]=second;result.count=1 if greatest<=resolution*resolution else 2
    elif used==3:
        result.count=3
        for i in range(3):result.indices[i]=hull[i]
    else:
        result.count=4;var greatest=Float64(-1)
        for i in range(used):
            for j in range(i+1,used):
                for k in range(j+1,used):
                    for l in range(k+1,used):
                        var a=uv[hull[i]];var b=uv[hull[j]];var c=uv[hull[k]];var d=uv[hull[l]]
                        var area=abs(cross2(a,b,c)+cross2(a,c,d))
                        if area>greatest+64*EPS*(1+abs(greatest)):
                            greatest=area;result.indices[0]=hull[i];result.indices[1]=hull[j];result.indices[2]=hull[k];result.indices[3]=hull[l]
    # Input points already have canonical midpoint order. Restore that order
    # after geometry-based selection, so solver sweeps do not depend on hull leg.
    for i in range(result.count):
        for j in range(i+1,result.count):
            if result.indices[j]<result.indices[i]:var old=result.indices[i];result.indices[i]=result.indices[j];result.indices[j]=old
    return result^

@fieldwise_init
struct BlockSolution(Movable):
    var impulse: Array[Float64,4]
    var valid: Bool

def pseudoinverse(k: Array[Float64,16],q: Array[Float64,4],mask: Int) -> BlockSolution:
    var a=Array[Float64,16](fill=0);var vectors=Array[Float64,16](fill=0);var scale=Float64(0)
    for i in range(4):
        vectors[i*4+i]=1
        for j in range(4):
            if (mask&(1<<i))!=0 and (mask&(1<<j))!=0:scale=max(scale,abs(k[i*4+j]))
    var result=BlockSolution(Array[Float64,4](fill=0),True)
    if scale==0:return result^
    for i in range(4):
        for j in range(4):
            if (mask&(1<<i))!=0 and (mask&(1<<j))!=0:a[i*4+j]=k[i*4+j]/scale
    # Symmetric Jacobi rotations, fixed 4x4 storage. No diagonal regularization.
    for _ in range(96):
        var off=Float64(0);var p=0;var r=1
        for i in range(4):
            for j in range(i+1,4):
                if abs(a[i*4+j])>off:off=abs(a[i*4+j]);p=i;r=j
        if off<=32*EPS:break
        var apq=a[p*4+r];var tau=(a[r*4+r]-a[p*4+p])/(2*apq)
        var t=(1.0 if tau>=0 else -1.0)/(abs(tau)+sqrt(1+tau*tau));var c=1/sqrt(1+t*t);var s=t*c
        a[p*4+p]-=t*apq;a[r*4+r]+=t*apq;a[p*4+r]=0;a[r*4+p]=0
        for i in range(4):
            if i!=p and i!=r:
                var x=a[i*4+p];var y=a[i*4+r];a[i*4+p]=c*x-s*y;a[p*4+i]=a[i*4+p];a[i*4+r]=s*x+c*y;a[r*4+i]=a[i*4+r]
            var x=vectors[i*4+p];var y=vectors[i*4+r];vectors[i*4+p]=c*x-s*y;vectors[i*4+r]=s*x+c*y
    var largest=Float64(0)
    for j in range(4):largest=max(largest,abs(a[j*4+j]))
    for j in range(4):
        var eigen=a[j*4+j]
        if eigen < -256*EPS*largest:result.valid=False;return result^
        if eigen<=256*EPS*largest:continue
        var projection=Float64(0)
        for i in range(4):projection-=vectors[i*4+j]*(q[i]/scale)
        projection/=eigen
        for i in range(4):result.impulse[i]+=vectors[i*4+j]*projection
    return result^

def normal_block(k: Array[Float64,16],q: Array[Float64,4],count: Int,tolerance: Float64) -> BlockSolution:
    var best=BlockSolution(Array[Float64,4](fill=0),False);var minimum=Float64(1e300)
    for mask in range(1<<count):
        var trial=pseudoinverse(k,q,mask)
        if not trial.valid:continue
        var scale=Float64(1)
        for i in range(count):scale=max(scale,abs(trial.impulse[i]))
        var valid=True;var norm=Float64(0)
        for i in range(count):
            if not isfinite(trial.impulse[i]) or trial.impulse[i]<-128*EPS*scale or trial.impulse[i]>1e4:valid=False
            trial.impulse[i]=max(0.0,trial.impulse[i]);norm+=trial.impulse[i]*trial.impulse[i]
        for i in range(count):
            var residual=q[i]
            for j in range(count):residual+=k[i*4+j]*trial.impulse[j]
            if not isfinite(residual) or (abs(residual)>tolerance if trial.impulse[i]>0 else residual < -tolerance):valid=False
        if valid and norm<minimum:best=trial^;minimum=norm
    return best^

@fieldwise_init
struct MaskOperators(Movable):
    var values: Array[Float64,256]
    var valid: Array[Bool,16]

def mask_operators(k: Array[Float64,16],count: Int) -> MaskOperators:
    var result=MaskOperators(Array[Float64,256](fill=0),Array[Bool,16](fill=True))
    for mask in range(1<<count):
        for col in range(count):
            var q=Array[Float64,4](fill=0);q[col]=-1
            var inverse=pseudoinverse(k,q,mask)
            if not inverse.valid:result.valid[mask]=False
            for row in range(count):result.values[mask*16+row*4+col]=inverse.impulse[row]
    return result^

def cached_normal_block(k: Array[Float64,16],q: Array[Float64,4],operators: Array[Float64,256],valid_masks: Array[Bool,16],count: Int,tolerance: Float64) -> BlockSolution:
    var best=BlockSolution(Array[Float64,4](fill=0),False);var minimum=Float64(1e300)
    for mask in range(1<<count):
        if not valid_masks[mask]:continue
        var trial=BlockSolution(Array[Float64,4](fill=0),True);var scale=Float64(1)
        for i in range(count):
            for j in range(count):trial.impulse[i]-=operators[mask*16+i*4+j]*q[j]
            scale=max(scale,abs(trial.impulse[i]))
        var valid=True;var norm=Float64(0)
        for i in range(count):
            if not isfinite(trial.impulse[i]) or trial.impulse[i]<-128*EPS*scale or trial.impulse[i]>1e4:valid=False
            trial.impulse[i]=max(0.0,trial.impulse[i]);norm+=trial.impulse[i]*trial.impulse[i]
        for i in range(count):
            var residual=q[i]
            for j in range(count):residual+=k[i*4+j]*trial.impulse[j]
            if not isfinite(residual) or (abs(residual)>tolerance if trial.impulse[i]>0 else residual < -tolerance):valid=False
        if valid and norm<minimum:best=trial^;minimum=norm
    return best^
