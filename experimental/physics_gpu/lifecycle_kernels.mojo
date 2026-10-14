"""G02 authoritative device registry and ordered transactional commands.

The bounded serial command phase is intentional: lifecycle correctness first,
no scheduling/performance claim. Body integration remains one thread per slot.
"""
from max.gpu import block_idx, block_dim, thread_idx
from std.memory import Pointer
from std.math import isfinite
from .core import BodyState, finite, rotation
from .kernels import CAPACITY, STRIDE, FIELDS, SENTINEL, load, store

comptime CREATE = UInt64(1)
comptime REMOVE = UInt64(2)
comptime UPDATE = UInt64(3)
comptime SET_FORCE = UInt64(4)
comptime ALL_FORCE = UInt64(5)
comptime BAD_COMMAND = Int32(10)
comptime STALE_HANDLE = Int32(11)
comptime HANDLE_RANGE = Int32(12)
comptime WORLD_FULL = Int32(13)
comptime BAD_BODY = Int32(14)
comptime IMMUTABLE_MASS = Int32(15)
comptime WRONG_WORLD = Int32(16)
comptime META_SENTINEL = UInt64.MAX

def initialize_registry(active: Pointer[Int32, MutAnyOrigin], generations: Pointer[UInt64, MutAnyOrigin]):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i<CAPACITY:
        active[unsafe_offset=i+1]=0
        generations[unsafe_offset=i+1]=1

def copy_transaction(current: Pointer[Float64, MutAnyOrigin], scratch: Pointer[Float64, MutAnyOrigin],
                     active: Pointer[Int32, MutAnyOrigin], pending_active: Pointer[Int32, MutAnyOrigin],
                     generations: Pointer[UInt64, MutAnyOrigin], pending_generations: Pointer[UInt64, MutAnyOrigin]):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i>=CAPACITY:return
    for f in range(FIELDS):
        var index=f*STRIDE+i+1
        scratch[unsafe_offset=index]=current[unsafe_offset=index]
    pending_active[unsafe_offset=i+1]=active[unsafe_offset=i+1]
    pending_generations[unsafe_offset=i+1]=generations[unsafe_offset=i+1]

def payload(data: Pointer[Float64, MutAnyOrigin], command: Int) -> BodyState:
    var b=1+command*FIELDS
    return BodyState(data[unsafe_offset=b],
        Vec3(data[unsafe_offset=b+1],data[unsafe_offset=b+2],data[unsafe_offset=b+3]),
        Vec3(data[unsafe_offset=b+4],data[unsafe_offset=b+5],data[unsafe_offset=b+6]),
        Quaternion(data[unsafe_offset=b+7],data[unsafe_offset=b+8],data[unsafe_offset=b+9],data[unsafe_offset=b+10]),
        Vec3(data[unsafe_offset=b+11],data[unsafe_offset=b+12],data[unsafe_offset=b+13]),
        Vec3(data[unsafe_offset=b+14],data[unsafe_offset=b+15],data[unsafe_offset=b+16]),
        Vec3(data[unsafe_offset=b+17],data[unsafe_offset=b+18],data[unsafe_offset=b+19]),
        Vec3(data[unsafe_offset=b+20],data[unsafe_offset=b+21],data[unsafe_offset=b+22]))

from mojo_game.math3d import Vec3
from mojo_game.transform3d import Quaternion

def command_transaction(scratch: Pointer[Float64, MutAnyOrigin],
                        active: Pointer[Int32, MutAnyOrigin], generations: Pointer[UInt64, MutAnyOrigin],
                        namespace: Pointer[UInt64, MutAnyOrigin], headers: Pointer[UInt64, MutAnyOrigin],
                        data: Pointer[Float64, MutAnyOrigin], results: Pointer[UInt64, MutAnyOrigin],
                        summary: Pointer[Int32, MutAnyOrigin], count: Int32):
    if Int(block_idx.x*block_dim.x+thread_idx.x)!=0:return
    summary[unsafe_offset=0]=0
    summary[unsafe_offset=1]=-1
    if count<0 or count>Int32(CAPACITY):
        summary[unsafe_offset=0]=BAD_COMMAND
        return
    for c in range(Int(count)):
        var h=1+c*4
        var op=headers[unsafe_offset=h]
        var target=headers[unsafe_offset=h+1]
        var generation=headers[unsafe_offset=h+2]
        var owner=headers[unsafe_offset=h+3]
        var body=payload(data,c)
        var error=Int32(0)
        var slot=Int(-1)
        if op==CREATE:
            if not body.valid():error=BAD_BODY
            else:
                for i in range(CAPACITY):
                    if active[unsafe_offset=i+1]==0:
                        slot=i
                        break
                if slot<0:error=WORLD_FULL
                else:
                    body.orientation=rotation(body.orientation)
                    store(scratch,slot,body)
                    active[unsafe_offset=slot+1]=1
                    generation=generations[unsafe_offset=slot+1]
        elif op==ALL_FORCE:
            if not finite(body.force) or not finite(body.torque):error=BAD_BODY
            else:
                for i in range(CAPACITY):
                    if active[unsafe_offset=i+1]==1:
                        var existing=load(scratch,i)
                        existing.force=body.force
                        existing.torque=body.torque
                        store(scratch,i,existing)
        elif op==REMOVE or op==UPDATE or op==SET_FORCE:
            if owner!=namespace[unsafe_offset=1]:error=WRONG_WORLD
            elif target>=UInt64(CAPACITY):error=HANDLE_RANGE
            else:
                slot=Int(target)
                if active[unsafe_offset=slot+1]!=1 or generation==0 or generations[unsafe_offset=slot+1]!=generation:
                    error=STALE_HANDLE
                elif op==REMOVE:
                    if generation==UInt64.MAX:
                        # Retire the slot permanently instead of wrapping/ABA.
                        active[unsafe_offset=slot+1]=2
                    else:
                        active[unsafe_offset=slot+1]=0
                        generations[unsafe_offset=slot+1]=generation+1
                    for f in range(FIELDS):scratch[unsafe_offset=f*STRIDE+slot+1]=SENTINEL
                elif op==UPDATE:
                    if not body.valid():error=BAD_BODY
                    else:
                        var old=load(scratch,slot)
                        if body.mass!=old.mass or body.inertia.x!=old.inertia.x or body.inertia.y!=old.inertia.y or body.inertia.z!=old.inertia.z:
                            error=IMMUTABLE_MASS
                        else:
                            body.orientation=rotation(body.orientation)
                            store(scratch,slot,body)
                else:
                    if not finite(body.force) or not finite(body.torque):error=BAD_BODY
                    else:
                        var old=load(scratch,slot)
                        old.force=body.force
                        old.torque=body.torque
                        store(scratch,slot,old)
        else:error=BAD_COMMAND
        if error:
            summary[unsafe_offset=0]=error
            summary[unsafe_offset=1]=Int32(c)
            return
        var r=1+c*3
        results[unsafe_offset=r]=UInt64(slot) if slot>=0 else UInt64.MAX
        results[unsafe_offset=r+1]=generation
        results[unsafe_offset=r+2]=namespace[unsafe_offset=1]

def commit_transaction(current: Pointer[Float64, MutAnyOrigin], scratch: Pointer[Float64, MutAnyOrigin],
                       active: Pointer[Int32, MutAnyOrigin], pending_active: Pointer[Int32, MutAnyOrigin],
                       generations: Pointer[UInt64, MutAnyOrigin], pending_generations: Pointer[UInt64, MutAnyOrigin],
                       summary: Pointer[Int32, MutAnyOrigin]):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i>=CAPACITY or summary[unsafe_offset=0]!=0:return
    for f in range(FIELDS):
        var index=f*STRIDE+i+1
        current[unsafe_offset=index]=scratch[unsafe_offset=index]
    active[unsafe_offset=i+1]=pending_active[unsafe_offset=i+1]
    generations[unsafe_offset=i+1]=pending_generations[unsafe_offset=i+1]

def integrate_live(current: Pointer[Float64, MutAnyOrigin], scratch: Pointer[Float64, MutAnyOrigin],
                   active: Pointer[Int32, MutAnyOrigin], statuses: Pointer[Int32, MutAnyOrigin],
                   dt: Float64, gx: Float64, gy: Float64, gz: Float64, ceiling: Float64):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i>=CAPACITY:return
    statuses[unsafe_offset=i+1]=0
    if not finite(Vec3(gx,gy,gz)):
        statuses[unsafe_offset=i+1]=1
        return
    if not isfinite(dt) or dt<=0 or dt>.25 or not isfinite(ceiling) or ceiling<=0 or ceiling>1.0/30:
        statuses[unsafe_offset=i+1]=2
        return
    if not isfinite(dt/ceiling) or dt/ceiling>32:
        statuses[unsafe_offset=i+1]=3
        return
    if active[unsafe_offset=i+1]!=1:return
    var body=load(current,i)
    statuses[unsafe_offset=i+1]=body.integrate(dt,Vec3(gx,gy,gz),ceiling)
    store(scratch,i,body)

def commit_step(current: Pointer[Float64, MutAnyOrigin], scratch: Pointer[Float64, MutAnyOrigin],
                active: Pointer[Int32, MutAnyOrigin], summary: Pointer[Int32, MutAnyOrigin]):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i>=CAPACITY or active[unsafe_offset=i+1]!=1 or summary[unsafe_offset=0]!=0:return
    for f in range(FIELDS):
        var index=f*STRIDE+i+1
        current[unsafe_offset=index]=scratch[unsafe_offset=index]

def snapshot_registry(current: Pointer[Float64, MutAnyOrigin], active: Pointer[Int32, MutAnyOrigin],
                      generations: Pointer[UInt64, MutAnyOrigin], namespace: Pointer[UInt64, MutAnyOrigin],
                      metadata: Pointer[UInt64, MutAnyOrigin], poses: Pointer[Float64, MutAnyOrigin]):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i>=CAPACITY:return
    var m=1+i*3
    metadata[unsafe_offset=m]=UInt64(active[unsafe_offset=i+1])
    metadata[unsafe_offset=m+1]=generations[unsafe_offset=i+1]
    metadata[unsafe_offset=m+2]=namespace[unsafe_offset=1]
    for f in range(7):
        poses[unsafe_offset=1+i*7+f]=current[unsafe_offset=(4+f)*STRIDE+i+1] if active[unsafe_offset=i+1]==1 else SENTINEL

def diagnostic_copy(current: Pointer[Float64, MutAnyOrigin], diagnostic: Pointer[Float64, MutAnyOrigin]):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i>=CAPACITY:return
    for f in range(FIELDS):diagnostic[unsafe_offset=f*STRIDE+i+1]=current[unsafe_offset=f*STRIDE+i+1]
    if i==0:
        for f in range(FIELDS):
            diagnostic[unsafe_offset=f*STRIDE]=current[unsafe_offset=f*STRIDE]
            diagnostic[unsafe_offset=f*STRIDE+STRIDE-1]=current[unsafe_offset=f*STRIDE+STRIDE-1]

def generation_for_test(generations: Pointer[UInt64, MutAnyOrigin], slot: Int32, generation: UInt64):
    if Int(block_idx.x*block_dim.x+thread_idx.x)!=0:return
    if slot>=0 and slot<Int32(CAPACITY) and generation!=0:
        generations[unsafe_offset=Int(slot)+1]=generation

def storage_stamp(current: Pointer[Float64, MutAnyOrigin], scratch: Pointer[Float64, MutAnyOrigin], addresses: Pointer[UInt64, MutAnyOrigin]):
    if Int(block_idx.x*block_dim.x+thread_idx.x)==0:
        addresses[unsafe_offset=0]=UInt64(Int(current))
        addresses[unsafe_offset=1]=UInt64(Int(scratch))
