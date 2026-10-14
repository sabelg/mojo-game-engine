"""G05a GPU connected components and atomic bounded publication.

Serial min-root union is intentionally a correctness baseline. Fixed bodies are
anchors, never vertices connecting dynamic components. No solver/sleep changes.
"""
from max.gpu import block_idx,block_dim,thread_idx
from std.memory import Pointer
from .kernels import CAPACITY,load
from .shape_kernels import SHAPES,PAIRS,PAIR_HEADER,mi

comptime MEMBER_WORDS=6
comptime ISLAND_CONTACT_WORDS=PAIR_HEADER+2
comptime NO_ISLAND=UInt64.MAX
comptime ISLAND_BAD_BODY=Int32(80)
comptime ISLAND_BAD_COUNT=Int32(81)
comptime ISLAND_STALE_KEY=Int32(82)
comptime ISLAND_FULL=Int32(83)
comptime ISLAND_EPOCH_FULL=Int32(84)
comptime ISLAND_BAD_TOPOLOGY=Int32(85)

def initialize_islands(state: Pointer[UInt64,MutAnyOrigin]):
    for i in range(1,5):state[unsafe_offset=i]=0

def root(parent: Pointer[Int32,MutAnyOrigin],slot: Int) -> Int:
    # Every link is strictly decreasing, bounded by CAPACITY, initialized here.
    var cursor=slot
    for _ in range(CAPACITY):
        var next=Int(parent[unsafe_offset=cursor+1])
        if next==cursor:return cursor
        cursor=next
    return -1

def construct_islands(current: Pointer[Float64,MutAnyOrigin],active: Pointer[Int32,MutAnyOrigin],
                      generations: Pointer[UInt64,MutAnyOrigin],namespace: Pointer[UInt64,MutAnyOrigin],
                      meta: Pointer[UInt64,MutAnyOrigin],statuses: Pointer[Int32,MutAnyOrigin],
                      flags: Pointer[Int32,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],
                      parent: Pointer[Int32,MutAnyOrigin],seen: Pointer[Int32,MutAnyOrigin],
                      pending_members: Pointer[UInt64,MutAnyOrigin],pending_contacts: Pointer[UInt64,MutAnyOrigin],
                      members: Pointer[UInt64,MutAnyOrigin],contacts: Pointer[UInt64,MutAnyOrigin],
                      state: Pointer[UInt64,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],
                      count: Int32,contact_capacity: Int32,island_limit: Int32):
    if Int(block_idx.x*block_dim.x+thread_idx.x)!=0:return
    summary[unsafe_offset=0]=0;summary[unsafe_offset=1]=-1
    if count<0 or count>contact_capacity or contact_capacity<0 or contact_capacity>Int32(PAIRS) or island_limit<0 or island_limit>Int32(CAPACITY):
        summary[unsafe_offset=0]=ISLAND_BAD_COUNT;return
    if state[unsafe_offset=1]==UInt64.MAX:
        summary[unsafe_offset=0]=ISLAND_EPOCH_FULL;return
    if namespace[unsafe_offset=1]==0:
        summary[unsafe_offset=0]=ISLAND_BAD_BODY;return
    var live=Int(0)
    for i in range(CAPACITY):
        var status=active[unsafe_offset=i+1];var generation=generations[unsafe_offset=i+1]
        parent[unsafe_offset=i+1]=-1
        if status<0 or status>2 or generation==0:
            summary[unsafe_offset=0]=ISLAND_BAD_BODY;summary[unsafe_offset=1]=Int32(i);return
        if status==1:
            var body=load(current,i)
            if not body.valid():
                summary[unsafe_offset=0]=ISLAND_BAD_BODY;summary[unsafe_offset=1]=Int32(i);return
            live+=1
            if body.mass>0:parent[unsafe_offset=i+1]=Int32(i)
    for s in range(SHAPES):
        if statuses[unsafe_offset=s+1]!=0:
            summary[unsafe_offset=0]=statuses[unsafe_offset=s+1];summary[unsafe_offset=1]=Int32(s);return
    var actual_count=Int(0)
    for p in range(PAIRS):
        seen[unsafe_offset=p+1]=-1
        var flag=flags[unsafe_offset=p+1]
        if flag!=0 and flag!=1:summary[unsafe_offset=0]=ISLAND_BAD_TOPOLOGY;return
        actual_count+=Int(flag)
    if actual_count!=Int(count):summary[unsafe_offset=0]=ISLAND_BAD_TOPOLOGY;return
    # Validate exact identities and completeness before deriving any union.
    for c in range(Int(count)):
        var h=1+c*PAIR_HEADER;var a=headers[unsafe_offset=h];var b=headers[unsafe_offset=h+5]
        if a>=UInt64(SHAPES) or b>=UInt64(SHAPES) or a>=b:
            summary[unsafe_offset=0]=ISLAND_STALE_KEY;summary[unsafe_offset=1]=Int32(c);return
        var aa=Int(a);var bb=Int(b);var p=aa*(2*SHAPES-aa-1)//2+bb-aa-1
        if seen[unsafe_offset=p+1]!=-1 or flags[unsafe_offset=p+1]!=1:
            summary[unsafe_offset=0]=ISLAND_BAD_TOPOLOGY;summary[unsafe_offset=1]=Int32(c);return
        for offset in [0,5]:
            var s=aa if offset==0 else bb
            var body=headers[unsafe_offset=h+offset+3]
            if mi(meta,0,s)!=1 or mi(meta,5,s)!=namespace[unsafe_offset=1] or headers[unsafe_offset=h+10]!=namespace[unsafe_offset=1] or body>=UInt64(CAPACITY):
                summary[unsafe_offset=0]=ISLAND_STALE_KEY;summary[unsafe_offset=1]=Int32(c);return
            for f in range(1,5):
                if headers[unsafe_offset=h+offset+f]!=mi(meta,f,s):
                    summary[unsafe_offset=0]=ISLAND_STALE_KEY;summary[unsafe_offset=1]=Int32(c);return
            if active[unsafe_offset=Int(body)+1]!=1 or generations[unsafe_offset=Int(body)+1]!=headers[unsafe_offset=h+offset+4]:
                summary[unsafe_offset=0]=ISLAND_STALE_KEY;summary[unsafe_offset=1]=Int32(c);return
        if headers[unsafe_offset=h+3]==headers[unsafe_offset=h+8]:
            summary[unsafe_offset=0]=ISLAND_STALE_KEY;return
        seen[unsafe_offset=p+1]=Int32(c)
    for c in range(Int(count)):
        var h=1+c*PAIR_HEADER;var a=Int(headers[unsafe_offset=h+3]);var b=Int(headers[unsafe_offset=h+8])
        if parent[unsafe_offset=a+1]>=0 and parent[unsafe_offset=b+1]>=0:
            var ra=root(parent,a);var rb=root(parent,b)
            parent[unsafe_offset=max(ra,rb)+1]=Int32(min(ra,rb))
    var islands=Int(0)
    for i in range(CAPACITY):
        var label=NO_ISLAND;var root_generation=UInt64(0);var dynamic=UInt64(0)
        if parent[unsafe_offset=i+1]>=0:
            var rr=root(parent,i);label=UInt64(rr);root_generation=generations[unsafe_offset=rr+1];dynamic=1
            if rr==i:islands+=1
        var m=1+i*MEMBER_WORDS
        pending_members[unsafe_offset=m]=UInt64(active[unsafe_offset=i+1])
        pending_members[unsafe_offset=m+1]=generations[unsafe_offset=i+1]
        pending_members[unsafe_offset=m+2]=dynamic;pending_members[unsafe_offset=m+3]=label
        pending_members[unsafe_offset=m+4]=root_generation;pending_members[unsafe_offset=m+5]=namespace[unsafe_offset=1]
    if islands>Int(island_limit):summary[unsafe_offset=0]=ISLAND_FULL;return
    # Canonical shape-key order is independent of input record/union order.
    var out_index=Int(0)
    for p in range(PAIRS):
        var c=Int(seen[unsafe_offset=p+1])
        if c<0:continue
        var h=1+c*PAIR_HEADER;var out=1+out_index*ISLAND_CONTACT_WORDS
        for f in range(PAIR_HEADER):pending_contacts[unsafe_offset=out+f]=headers[unsafe_offset=h+f]
        var a=Int(headers[unsafe_offset=h+3]);var b=Int(headers[unsafe_offset=h+8])
        var dynamic=a if parent[unsafe_offset=a+1]>=0 else b
        var label=NO_ISLAND;var generation=UInt64(0)
        if parent[unsafe_offset=dynamic+1]>=0:
            var rr=root(parent,dynamic);label=UInt64(rr);generation=generations[unsafe_offset=rr+1]
        pending_contacts[unsafe_offset=out+PAIR_HEADER]=label;pending_contacts[unsafe_offset=out+PAIR_HEADER+1]=generation
        out_index+=1
    for i in range(1,CAPACITY*MEMBER_WORDS+1):members[unsafe_offset=i]=pending_members[unsafe_offset=i]
    for i in range(1,Int(contact_capacity)*ISLAND_CONTACT_WORDS+1):
        contacts[unsafe_offset=i]=pending_contacts[unsafe_offset=i] if i<=Int(count)*ISLAND_CONTACT_WORDS else UInt64.MAX
    state[unsafe_offset=1]+=1;state[unsafe_offset=2]=UInt64(islands)
    state[unsafe_offset=3]=UInt64(live);state[unsafe_offset=4]=UInt64(count)
