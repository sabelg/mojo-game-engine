"""G05b conservative island sleep/wake state. GPU-only classification and events."""
from std.memory import Pointer
from std.math import isfinite,sqrt
from max.gpu import block_idx,block_dim,thread_idx
from mojo_game import Vec3
from .kernels import CAPACITY,STRIDE,FIELDS,load
from .shape_kernels import SHAPES,SHAPE_STRIDE,META_FIELDS,PAIRS,PAIR_HEADER,mi
from .island_kernels import MEMBER_WORDS,ISLAND_CONTACT_WORDS,NO_ISLAND
from .response_kernels import SLOP,POS_TOL,body_profile
from .core import component,finite
from .lifecycle_kernels import CREATE,ALL_FORCE

comptime SLEEP_WORDS=7
comptime SLEEP_CONFIG=Int32(90)
comptime SLEEP_COUNTER=Int32(91)
comptime SLEEP_HANDLE=Int32(92)
comptime SLEEP_METADATA=Int32(93)
comptime SUPPORT_DOT=Float64(1-1e-12)

def initialize_sleep(state: Pointer[UInt64,MutAnyOrigin],publication: Pointer[UInt64,MutAnyOrigin]):
    for i in range(CAPACITY):
        for f in range(SLEEP_WORDS):state[unsafe_offset=1+i*SLEEP_WORDS+f]=0
        state[unsafe_offset=1+i*SLEEP_WORDS+3]=NO_ISLAND
    for i in range(1,7):publication[unsafe_offset=i]=0

def mark_body_commands(headers: Pointer[UInt64,MutAnyOrigin],results: Pointer[UInt64,MutAnyOrigin],requests: Pointer[Int32,MutAnyOrigin],count: Int32):
    if Int(block_idx.x*block_dim.x+thread_idx.x)!=0:return
    for i in range(Int(count)):
        var h=1+i*4;var opcode=headers[unsafe_offset=h]
        if opcode==ALL_FORCE:
            for slot in range(CAPACITY):requests[unsafe_offset=slot+1]=1
        else:
            var slot=results[unsafe_offset=1+i*3] if opcode==CREATE else headers[unsafe_offset=h+1]
            if slot<UInt64(CAPACITY):requests[unsafe_offset=Int(slot)+1]=1

def wake_packet(headers: Pointer[UInt64,MutAnyOrigin],active: Pointer[Int32,MutAnyOrigin],generations: Pointer[UInt64,MutAnyOrigin],namespace: Pointer[UInt64,MutAnyOrigin],
                current: Pointer[Float64,MutAnyOrigin],requests: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],count: Int32):
    summary[unsafe_offset=0]=0
    if count<0 or count>Int32(CAPACITY):summary[unsafe_offset=0]=SLEEP_HANDLE;return
    for i in range(Int(count)):
        var h=1+i*3;var slot=headers[unsafe_offset=h]
        if slot>=UInt64(CAPACITY) or headers[unsafe_offset=h+2]!=namespace[unsafe_offset=1] or active[unsafe_offset=Int(slot)+1]!=1 or headers[unsafe_offset=h+1]==0 or headers[unsafe_offset=h+1]!=generations[unsafe_offset=Int(slot)+1]:
            summary[unsafe_offset=0]=SLEEP_HANDLE;return
    for i in range(Int(count)):
        var slot=Int(headers[unsafe_offset=1+i*3])
        if load(current,slot).mass>0:requests[unsafe_offset=slot+1]=1

def seed(old: Pointer[UInt64,MutAnyOrigin],members: Pointer[UInt64,MutAnyOrigin],old_wake: Pointer[Int32,MutAnyOrigin],new_wake: Pointer[Int32,MutAnyOrigin],slot: Int):
    if slot<0 or slot>=CAPACITY:return
    var s=1+slot*SLEEP_WORDS;var m=1+slot*MEMBER_WORDS
    if old[unsafe_offset=s]==1 and old[unsafe_offset=s+2]==1 and old[unsafe_offset=s+3]<UInt64(CAPACITY):old_wake[unsafe_offset=Int(old[unsafe_offset=s+3])+1]=1
    if members[unsafe_offset=m]==1 and members[unsafe_offset=m+2]==1 and members[unsafe_offset=m+3]<UInt64(CAPACITY):new_wake[unsafe_offset=Int(members[unsafe_offset=m+3])+1]=1

def evaluate_sleep(current: Pointer[Float64,MutAnyOrigin],members: Pointer[UInt64,MutAnyOrigin],contacts: Pointer[UInt64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],meta: Pointer[UInt64,MutAnyOrigin],
                   old: Pointer[UInt64,MutAnyOrigin],clock: Pointer[Float64,MutAnyOrigin],observed: Pointer[Float64,MutAnyOrigin],anchor: Pointer[Float64,MutAnyOrigin],old_contacts: Pointer[UInt64,MutAnyOrigin],old_shapes: Pointer[UInt64,MutAnyOrigin],configuration: Pointer[Float64,MutAnyOrigin],publication: Pointer[UInt64,MutAnyOrigin],
                   pending: Pointer[UInt64,MutAnyOrigin],pending_clock: Pointer[Float64,MutAnyOrigin],requests: Pointer[Int32,MutAnyOrigin],step_wake: Pointer[Int32,MutAnyOrigin],old_wake: Pointer[Int32,MutAnyOrigin],new_wake: Pointer[Int32,MutAnyOrigin],eligible: Pointer[Int32,MutAnyOrigin],supported: Pointer[Int32,MutAnyOrigin],sources: Pointer[Int32,MutAnyOrigin],old_map: Pointer[Int32,MutAnyOrigin],new_map: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],
                   count: Int32,capacity: Int32,phase: Int32,dt: Float64,sleep_after: Float64,gx: Float64,gy: Float64,gz: Float64,e: Float64,mu: Float64,vi: Int32,pi: Int32,ceiling: Float64):
    if Int(block_idx.x*block_dim.x+thread_idx.x)!=0:return
    for i in range(6):summary[unsafe_offset=i]=0
    if not isfinite(dt) or dt<1.0/240 or dt>1.0/30 or not isfinite(sleep_after) or sleep_after<0 or sleep_after>10 or not finite(Vec3(gx,gy,gz)) or not isfinite(e) or e<0 or e>1 or not isfinite(mu) or mu<0 or mu>2 or vi<1 or vi>64 or pi<1 or pi>64 or not isfinite(ceiling) or ceiling<=0 or ceiling>1.0/30 or dt/ceiling>32:
        summary[unsafe_offset=0]=SLEEP_CONFIG;return
    if publication[unsafe_offset=1]==UInt64.MAX:summary[unsafe_offset=0]=SLEEP_COUNTER;return
    if count<0 or count>capacity or publication[unsafe_offset=2]>UInt64(capacity):summary[unsafe_offset=0]=SLEEP_METADATA;return
    var global_change=configuration[unsafe_offset=1]!=gx or configuration[unsafe_offset=2]!=gy or configuration[unsafe_offset=3]!=gz or configuration[unsafe_offset=4]!=e or configuration[unsafe_offset=5]!=mu or configuration[unsafe_offset=6]!=Float64(vi) or configuration[unsafe_offset=7]!=Float64(pi)
    var zero_gravity=gx==0 and gy==0 and gz==0
    var direction=Vec3(0,0,0)
    if not zero_gravity:
        var scale=max(abs(gx),max(abs(gy),abs(gz)));var v=Vec3(-gx/scale,-gy/scale,-gz/scale)
        direction=v*(1/sqrt(v.x*v.x+v.y*v.y+v.z*v.z))
    for i in range(CAPACITY):
        old_wake[unsafe_offset=i+1]=0;new_wake[unsafe_offset=i+1]=0;eligible[unsafe_offset=i+1]=1;supported[unsafe_offset=i+1]=0;sources[unsafe_offset=i+1]=0
        var s=1+i*SLEEP_WORDS;var m=1+i*MEMBER_WORDS
        if old[unsafe_offset=s]>2 or old[unsafe_offset=s+2]>1 or old[unsafe_offset=s+5]>1 or not isfinite(clock[unsafe_offset=i+1]) or clock[unsafe_offset=i+1]<0 or clock[unsafe_offset=i+1]>sleep_after or not isfinite(clock[unsafe_offset=STRIDE+i+1]) or abs(clock[unsafe_offset=STRIDE+i+1])>4*Float64(2.220446049250313e-16)*(1+clock[unsafe_offset=i+1]) or requests[unsafe_offset=i+1]<0 or requests[unsafe_offset=i+1]>1:summary[unsafe_offset=0]=SLEEP_METADATA;return
        if old[unsafe_offset=s]==1 and old[unsafe_offset=s+2]==1:
            var root=old[unsafe_offset=s+3]
            if root>=UInt64(CAPACITY) or old[unsafe_offset=s+1]==0 or old[unsafe_offset=s+4]==0 or old[unsafe_offset=s+6]==0:
                summary[unsafe_offset=0]=SLEEP_METADATA;return
        if members[unsafe_offset=m]==1:
            var b=load(current,i)
            if not body_profile(b):summary[unsafe_offset=0]=SLEEP_METADATA;return
            supported[unsafe_offset=i+1]=1 if b.mass==0 or zero_gravity else 0
        var changed=requests[unsafe_offset=i+1]!=0 or (phase==1 and step_wake[unsafe_offset=i+1]!=0) or members[unsafe_offset=m]!=old[unsafe_offset=s] or members[unsafe_offset=m+1]!=old[unsafe_offset=s+1] or members[unsafe_offset=m+3]!=old[unsafe_offset=s+3] or members[unsafe_offset=m+4]!=old[unsafe_offset=s+4]
        if members[unsafe_offset=m]==1:
            if global_change:changed=True
            for f in range(FIELDS):
                var value=current[unsafe_offset=f*STRIDE+i+1];var previous=observed[unsafe_offset=f*STRIDE+i+1]
                if value==previous:continue
                var same_sleeping_identity=old[unsafe_offset=s]==1 and old[unsafe_offset=s+1]==members[unsafe_offset=m+1] and old[unsafe_offset=s+5]==1
                if phase==1 and f>=4 and f<=10 and not same_sleeping_identity:
                    var reference=anchor[unsafe_offset=(f-4)*STRIDE+i+1] if clock[unsafe_offset=i+1]>0 else previous
                    var bound=8*Float64(2.220446049250313e-16)*max(1.0,max(abs(value),abs(reference)))
                    if abs(value-reference)<=bound:continue
                changed=True
        if changed:sources[unsafe_offset=i+1]=1;seed(old,members,old_wake,new_wake,i)
    # Explicit shape changes also wake uncontacted bodies; old attachments are
    # retained independently so detach/reuse cannot lose the previous island.
    for s in range(SHAPES):
        var changed=False
        for f in range(META_FIELDS):
            if mi(meta,f,s)!=mi(old_shapes,f,s):changed=True
        if changed:
            if mi(meta,0,s)==1:
                var slot=Int(mi(meta,3,s));sources[unsafe_offset=slot+1]=1;seed(old,members,old_wake,new_wake,slot)
            if mi(old_shapes,0,s)==1:
                var slot=Int(mi(old_shapes,3,s))
                if slot<0 or slot>=CAPACITY:summary[unsafe_offset=0]=SLEEP_METADATA;return
                sources[unsafe_offset=slot+1]=1;seed(old,members,old_wake,new_wake,slot)
    for p in range(PAIRS):old_map[unsafe_offset=p+1]=-1;new_map[unsafe_offset=p+1]=-1
    for which in [0,1]:
        var length=Int(publication[unsafe_offset=2]) if which==0 else Int(count)
        for i in range(length):
            var h=1+i*ISLAND_CONTACT_WORDS
            var a=old_contacts[unsafe_offset=h] if which==0 else contacts[unsafe_offset=h]
            var b=old_contacts[unsafe_offset=h+5] if which==0 else contacts[unsafe_offset=h+5]
            if a>=UInt64(SHAPES) or b>=UInt64(SHAPES) or a>=b:summary[unsafe_offset=0]=SLEEP_METADATA;return
            var p=Int(a)*(2*SHAPES-Int(a)-1)//2+Int(b)-Int(a)-1
            if which==0:old_map[unsafe_offset=p+1]=Int32(i)
            else:new_map[unsafe_offset=p+1]=Int32(i)
    for p in range(PAIRS):
        var previous=Int(old_map[unsafe_offset=p+1]);var next=Int(new_map[unsafe_offset=p+1]);var changed=(previous<0)!=(next<0)
        if previous>=0 and next>=0:
            for f in range(PAIR_HEADER):
                if old_contacts[unsafe_offset=1+previous*ISLAND_CONTACT_WORDS+f]!=contacts[unsafe_offset=1+next*ISLAND_CONTACT_WORDS+f]:changed=True
        if changed:
            if previous>=0:
                var h=1+previous*ISLAND_CONTACT_WORDS;seed(old,members,old_wake,new_wake,Int(old_contacts[unsafe_offset=h+3]));seed(old,members,old_wake,new_wake,Int(old_contacts[unsafe_offset=h+8]))
            if next>=0:
                var h=1+next*ISLAND_CONTACT_WORDS;seed(old,members,old_wake,new_wake,Int(contacts[unsafe_offset=h+3]));seed(old,members,old_wake,new_wake,Int(contacts[unsafe_offset=h+8]))
    # Fixed edits wake incident partners; fixed roots never join propagation.
    for which in [0,1]:
        var length=Int(publication[unsafe_offset=2]) if which==0 else Int(count)
        for i in range(length):
            var h=1+i*ISLAND_CONTACT_WORDS
            var a=Int(old_contacts[unsafe_offset=h+3]) if which==0 else Int(contacts[unsafe_offset=h+3])
            var b=Int(old_contacts[unsafe_offset=h+8]) if which==0 else Int(contacts[unsafe_offset=h+8])
            if a<0 or a>=CAPACITY or b<0 or b>=CAPACITY:summary[unsafe_offset=0]=SLEEP_METADATA;return
            if sources[unsafe_offset=a+1]!=0:seed(old,members,old_wake,new_wake,b)
            if sources[unsafe_offset=b+1]!=0:seed(old,members,old_wake,new_wake,a)
    for i in range(CAPACITY):
        var s=1+i*SLEEP_WORDS
        if old[unsafe_offset=s]==1 and old[unsafe_offset=s+2]==1 and old_wake[unsafe_offset=Int(old[unsafe_offset=s+3])+1]!=0:seed(old,members,old_wake,new_wake,i)
    # Vertical-support reachability is distinct from dynamic connectivity: fixed
    # supports seed upward reaction paths, but never bridge component wake flags.
    for _ in range(CAPACITY):
        var changed=False
        for c in range(Int(count)):
            var h=1+c*PAIR_HEADER;var a=Int(headers[unsafe_offset=h+3]);var b=Int(headers[unsafe_offset=h+8]);var g=1+c*10
            if geometry[unsafe_offset=g+3] < -SLOP-POS_TOL:continue
            var n=Vec3(geometry[unsafe_offset=g],geometry[unsafe_offset=g+1],geometry[unsafe_offset=g+2]);var projection=n.dot(direction)
            if supported[unsafe_offset=a+1]!=0 and supported[unsafe_offset=b+1]==0 and projection>=SUPPORT_DOT:supported[unsafe_offset=b+1]=1;changed=True
            if supported[unsafe_offset=b+1]!=0 and supported[unsafe_offset=a+1]==0 and -projection>=SUPPORT_DOT:supported[unsafe_offset=a+1]=1;changed=True
        if not changed:break
    for i in range(CAPACITY):
        var m=1+i*MEMBER_WORDS
        if members[unsafe_offset=m]!=1 or members[unsafe_offset=m+2]!=1:continue
        var r=Int(members[unsafe_offset=m+3]);var b=load(current,i)
        if component(b.linear)!=0 or component(b.angular)!=0 or component(b.force)!=0 or component(b.torque)!=0 or supported[unsafe_offset=i+1]==0:eligible[unsafe_offset=r+1]=0
    var dynamic_count=Int(0);var asleep_count=Int(0);var entered=Int(0);var woke=Int(0)
    for i in range(CAPACITY):
        var m=1+i*MEMBER_WORDS;var s=1+i*SLEEP_WORDS;var flag=UInt64(0);var dwell=Float64(0);var compensation=Float64(0)
        for f in range(5):pending[unsafe_offset=s+f]=members[unsafe_offset=m+f]
        pending[unsafe_offset=s+6]=members[unsafe_offset=m+5]
        if members[unsafe_offset=m]==1 and members[unsafe_offset=m+2]==1:
            dynamic_count+=1;var r=Int(members[unsafe_offset=m+3]);var calm=eligible[unsafe_offset=r+1]!=0 and new_wake[unsafe_offset=r+1]==0
            var prior=old[unsafe_offset=s]==1 and old[unsafe_offset=s+1]==members[unsafe_offset=m+1] and old[unsafe_offset=s+5]==1
            if phase==0:
                step_wake[unsafe_offset=i+1]=0 if calm else 1
                flag=1 if calm and prior else 0
            elif calm:
                dwell=clock[unsafe_offset=i+1];compensation=clock[unsafe_offset=STRIDE+i+1]
                if prior:dwell=sleep_after;compensation=0;flag=1
                else:
                    var increment=dt-compensation;var next=dwell+increment;compensation=(next-dwell)-increment;dwell=next
                    if dwell>=sleep_after:dwell=sleep_after;compensation=0;flag=1
            if phase==1:
                if prior and flag==0:woke+=1
                if not prior and flag==1:entered+=1
            asleep_count+=Int(flag)
        elif phase==0:step_wake[unsafe_offset=i+1]=0
        pending[unsafe_offset=s+5]=flag;pending_clock[unsafe_offset=i+1]=dwell;pending_clock[unsafe_offset=STRIDE+i+1]=compensation
    if publication[unsafe_offset=5]>UInt64.MAX-UInt64(entered) or publication[unsafe_offset=6]>UInt64.MAX-UInt64(woke):summary[unsafe_offset=0]=SLEEP_COUNTER;return
    summary[unsafe_offset=1]=1 if dynamic_count>0 and asleep_count==dynamic_count else 0
    summary[unsafe_offset=2]=Int32(asleep_count);summary[unsafe_offset=3]=Int32(dynamic_count-asleep_count);summary[unsafe_offset=4]=Int32(entered);summary[unsafe_offset=5]=Int32(woke)

def commit_sleep(current: Pointer[Float64,MutAnyOrigin],meta: Pointer[UInt64,MutAnyOrigin],contacts: Pointer[UInt64,MutAnyOrigin],
                 pending: Pointer[UInt64,MutAnyOrigin],pending_clock: Pointer[Float64,MutAnyOrigin],state: Pointer[UInt64,MutAnyOrigin],clock: Pointer[Float64,MutAnyOrigin],observed: Pointer[Float64,MutAnyOrigin],anchor: Pointer[Float64,MutAnyOrigin],old_shapes: Pointer[UInt64,MutAnyOrigin],old_contacts: Pointer[UInt64,MutAnyOrigin],configuration: Pointer[Float64,MutAnyOrigin],publication: Pointer[UInt64,MutAnyOrigin],requests: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],count: Int32,capacity: Int32,gx: Float64,gy: Float64,gz: Float64,e: Float64,mu: Float64,vi: Int32,pi: Int32):
    if Int(block_idx.x*block_dim.x+thread_idx.x)!=0 or summary[unsafe_offset=0]!=0:return
    for i in range(1,CAPACITY*SLEEP_WORDS+1):state[unsafe_offset=i]=pending[unsafe_offset=i]
    for i in range(CAPACITY):
        for f in range(4,11):
            if pending_clock[unsafe_offset=i+1]==0:anchor[unsafe_offset=(f-4)*STRIDE+i+1]=current[unsafe_offset=f*STRIDE+i+1]
            elif clock[unsafe_offset=i+1]==0:anchor[unsafe_offset=(f-4)*STRIDE+i+1]=observed[unsafe_offset=f*STRIDE+i+1]
        clock[unsafe_offset=i+1]=pending_clock[unsafe_offset=i+1];clock[unsafe_offset=STRIDE+i+1]=pending_clock[unsafe_offset=STRIDE+i+1]
        requests[unsafe_offset=i+1]=0
        for f in range(FIELDS):observed[unsafe_offset=f*STRIDE+i+1]=current[unsafe_offset=f*STRIDE+i+1]
    for s in range(SHAPES):
        for f in range(META_FIELDS):old_shapes[unsafe_offset=f*SHAPE_STRIDE+s+1]=mi(meta,f,s)
    for i in range(1,Int(capacity)*ISLAND_CONTACT_WORDS+1):old_contacts[unsafe_offset=i]=contacts[unsafe_offset=i]
    configuration[unsafe_offset=1]=gx;configuration[unsafe_offset=2]=gy;configuration[unsafe_offset=3]=gz
    configuration[unsafe_offset=4]=e;configuration[unsafe_offset=5]=mu;configuration[unsafe_offset=6]=Float64(vi);configuration[unsafe_offset=7]=Float64(pi)
    publication[unsafe_offset=1]+=1;publication[unsafe_offset=2]=UInt64(count)
    publication[unsafe_offset=3]=UInt64(summary[unsafe_offset=2]);publication[unsafe_offset=4]=UInt64(summary[unsafe_offset=3])
    publication[unsafe_offset=5]+=UInt64(summary[unsafe_offset=4]);publication[unsafe_offset=6]+=UInt64(summary[unsafe_offset=5])

def zero_clocks(clock: Pointer[Float64,MutAnyOrigin],pending: Pointer[Float64,MutAnyOrigin]):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i>=CAPACITY:return
    clock[unsafe_offset=i+1]=0;clock[unsafe_offset=STRIDE+i+1]=0
    pending[unsafe_offset=i+1]=0;pending[unsafe_offset=STRIDE+i+1]=0
