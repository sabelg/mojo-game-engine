"""G03c bounded device contact feature/matching and atomic history publication."""
from max.gpu import block_idx,block_dim,thread_idx
from std.memory import Pointer
from mojo_game.math3d import Vec3
from .shape_kernels import SHAPES,PAIRS,BOUNDS_FIELDS,BOX,mi,POISON

comptime WORDS=16
comptime GEOMETRY=10
comptime NEW=UInt64(1)
comptime PERSISTENT=UInt64(2)
comptime ENDED=UInt64(3)
comptime HISTORY_FULL=Int32(43)
comptime EVENTS_FULL=Int32(44)
comptime ID_FULL=Int32(45)
comptime AGE_FULL=Int32(46)
comptime EPOCH_FULL=Int32(47)
comptime NORMAL_GATE=Float64(.95)

def initialize_history(state: Pointer[UInt64,MutAnyOrigin]):
    state[unsafe_offset=1]=0;state[unsafe_offset=2]=0;state[unsafe_offset=3]=1

def contact_features(meta: Pointer[UInt64,MutAnyOrigin],bounds: Pointer[Float64,MutAnyOrigin],headers: Pointer[UInt64,MutAnyOrigin],
                     features: Pointer[UInt64,MutAnyOrigin],count: Int32):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i>=Int(count):return
    var h=1+i*11;var a=Int(headers[unsafe_offset=h]);var b=Int(headers[unsafe_offset=h+5])
    var feature=UInt64(0);var ambiguous=UInt64(0)
    if mi(meta,6,a)!=BOX and mi(meta,6,b)!=BOX:
        var aa=1+a*BOUNDS_FIELDS;var bb=1+b*BOUNDS_FIELDS
        var d=Vec3(bounds[unsafe_offset=bb]-bounds[unsafe_offset=aa],bounds[unsafe_offset=bb+1]-bounds[unsafe_offset=aa+1],bounds[unsafe_offset=bb+2]-bounds[unsafe_offset=aa+2])
        if d.dot(d)==0:feature=1;ambiguous=1
    else:
        var box=a if mi(meta,6,a)==BOX else b;var sphere=b if box==a else a
        var s=1+sphere*BOUNDS_FIELDS;var k=1+box*BOUNDS_FIELDS
        var d=Vec3(bounds[unsafe_offset=s]-bounds[unsafe_offset=k],bounds[unsafe_offset=s+1]-bounds[unsafe_offset=k+1],bounds[unsafe_offset=s+2]-bounds[unsafe_offset=k+2])
        var x=Vec3(bounds[unsafe_offset=k+13],bounds[unsafe_offset=k+14],bounds[unsafe_offset=k+15])
        var y=Vec3(bounds[unsafe_offset=k+16],bounds[unsafe_offset=k+17],bounds[unsafe_offset=k+18])
        var z=Vec3(bounds[unsafe_offset=k+19],bounds[unsafe_offset=k+20],bounds[unsafe_offset=k+21])
        var u=Vec3(d.dot(x),d.dot(y),d.dot(z))
        var half=Vec3(bounds[unsafe_offset=k+10],bounds[unsafe_offset=k+11],bounds[unsafe_offset=k+12])
        var cx=0 if u.x < -half.x else 2 if u.x > half.x else 1
        var cy=0 if u.y < -half.y else 2 if u.y > half.y else 1
        var cz=0 if u.z < -half.z else 2 if u.z > half.z else 1
        if cx!=1 or cy!=1 or cz!=1:feature=UInt64(10+cx*9+cy*3+cz)
        else:
            var clearance=half.x-abs(u.x);var axis=Int(0);var coordinate=u.x
            if half.y-abs(u.y)<clearance:clearance=half.y-abs(u.y);axis=1;coordinate=u.y
            if half.z-abs(u.z)<clearance:clearance=half.z-abs(u.z);axis=2;coordinate=u.z
            var ties=Int(0)
            if half.x-abs(u.x)==clearance:ties+=1
            if half.y-abs(u.y)==clearance:ties+=1
            if half.z-abs(u.z)==clearance:ties+=1
            feature=UInt64(50+axis*2+(0 if coordinate>=0 else 1))
            ambiguous=UInt64(1 if ties>1 or coordinate==0 else 0)
    features[unsafe_offset=1+i*2]=feature;features[unsafe_offset=2+i*2]=ambiguous

def pair_index(a: Int,b: Int) -> Int:
    return a*(2*SHAPES-a-1)//2+b-a-1

def history_transaction(headers: Pointer[UInt64,MutAnyOrigin],geometry: Pointer[Float64,MutAnyOrigin],features: Pointer[UInt64,MutAnyOrigin],
                        current: Pointer[UInt64,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],
                        pending: Pointer[UInt64,MutAnyOrigin],pending_values: Pointer[Float64,MutAnyOrigin],
                        events: Pointer[UInt64,MutAnyOrigin],event_values: Pointer[Float64,MutAnyOrigin],
                        state: Pointer[UInt64,MutAnyOrigin],index_map: Pointer[Int32,MutAnyOrigin],matched: Pointer[Int32,MutAnyOrigin],summary: Pointer[Int32,MutAnyOrigin],
                        count: Int32,capacity: Int32,event_capacity: Int32):
    summary[unsafe_offset=0]=0
    for i in range(1,5):summary[unsafe_offset=i]=0
    if count<0 or count>capacity or state[unsafe_offset=1]>UInt64(capacity):summary[unsafe_offset=0]=HISTORY_FULL;return
    if state[unsafe_offset=2]==UInt64.MAX:summary[unsafe_offset=0]=EPOCH_FULL;return
    var old=Int(state[unsafe_offset=1]);var next_id=state[unsafe_offset=3]
    for i in range(PAIRS):index_map[unsafe_offset=i+1]=-1
    for i in range(old):
        matched[unsafe_offset=i+1]=0;var h=1+i*WORDS
        var a=Int(current[unsafe_offset=h]);var b=Int(current[unsafe_offset=h+5])
        index_map[unsafe_offset=1+pair_index(a,b)]=Int32(i)
    var new_count=Int(0);var persistent_count=Int(0)
    for i in range(Int(count)):
        var h=1+i*11;var p=1+i*WORDS;var g=1+i*GEOMETRY
        var a=Int(headers[unsafe_offset=h]);var b=Int(headers[unsafe_offset=h+5])
        var previous=Int(index_map[unsafe_offset=1+pair_index(a,b)])
        var keep=previous>=0;var feature=features[unsafe_offset=1+i*2];var ambiguous=features[unsafe_offset=2+i*2]
        var q=1+max(previous,0)*WORDS;var v=1+max(previous,0)*GEOMETRY
        if keep:
            for f in range(11):
                if current[unsafe_offset=q+f]!=headers[unsafe_offset=h+f]:keep=False
            if current[unsafe_offset=q+13]!=feature or current[unsafe_offset=q+14]!=0 or ambiguous!=0:keep=False
            var dot=values[unsafe_offset=v]*geometry[unsafe_offset=g]+values[unsafe_offset=v+1]*geometry[unsafe_offset=g+1]+values[unsafe_offset=v+2]*geometry[unsafe_offset=g+2]
            if dot<NORMAL_GATE:keep=False
        var identity=UInt64(0);var age=UInt64(1);var status=NEW
        if keep:
            if current[unsafe_offset=q+12]==UInt64.MAX:summary[unsafe_offset=0]=AGE_FULL;return
            identity=current[unsafe_offset=q+11];age=current[unsafe_offset=q+12]+1;status=PERSISTENT
            matched[unsafe_offset=previous+1]=1;persistent_count+=1
        else:
            if next_id==0:summary[unsafe_offset=0]=ID_FULL;return
            identity=next_id;next_id=0 if next_id==UInt64.MAX else next_id+1;new_count+=1
        for f in range(11):pending[unsafe_offset=p+f]=headers[unsafe_offset=h+f]
        pending[unsafe_offset=p+11]=identity;pending[unsafe_offset=p+12]=age
        pending[unsafe_offset=p+13]=feature;pending[unsafe_offset=p+14]=ambiguous;pending[unsafe_offset=p+15]=status
        for f in range(GEOMETRY):pending_values[unsafe_offset=g+f]=geometry[unsafe_offset=g+f]
    var ended=Int(0)
    for i in range(old):
        if matched[unsafe_offset=i+1]==0:ended+=1
    if Int(count)+ended>Int(event_capacity):summary[unsafe_offset=0]=EVENTS_FULL;return
    # No current cache/state mutation occurred above. Event staging is private
    # until success; all capacity/counter failures reject the entire publication.
    for i in range(Int(count)):
        for f in range(WORDS):events[unsafe_offset=1+i*WORDS+f]=pending[unsafe_offset=1+i*WORDS+f]
        for f in range(GEOMETRY):event_values[unsafe_offset=1+i*GEOMETRY+f]=pending_values[unsafe_offset=1+i*GEOMETRY+f]
    var output=Int(count)
    for i in range(old):
        if matched[unsafe_offset=i+1]!=0:continue
        for f in range(WORDS):events[unsafe_offset=1+output*WORDS+f]=current[unsafe_offset=1+i*WORDS+f]
        events[unsafe_offset=1+output*WORDS+15]=ENDED
        for f in range(GEOMETRY):event_values[unsafe_offset=1+output*GEOMETRY+f]=values[unsafe_offset=1+i*GEOMETRY+f]
        output+=1
    for i in range(Int(capacity)):
        for f in range(WORDS):current[unsafe_offset=1+i*WORDS+f]=pending[unsafe_offset=1+i*WORDS+f] if i<Int(count) else UInt64.MAX
        for f in range(GEOMETRY):values[unsafe_offset=1+i*GEOMETRY+f]=pending_values[unsafe_offset=1+i*GEOMETRY+f] if i<Int(count) else POISON
    state[unsafe_offset=1]=UInt64(count);state[unsafe_offset=2]+=1;state[unsafe_offset=3]=next_id
    summary[unsafe_offset=1]=Int32(new_count);summary[unsafe_offset=2]=Int32(persistent_count)
    summary[unsafe_offset=3]=Int32(ended);summary[unsafe_offset=4]=count

def history_snapshot(current: Pointer[UInt64,MutAnyOrigin],values: Pointer[Float64,MutAnyOrigin],state: Pointer[UInt64,MutAnyOrigin],
                     out_words: Pointer[UInt64,MutAnyOrigin],out_values: Pointer[Float64,MutAnyOrigin],out_state: Pointer[UInt64,MutAnyOrigin],capacity: Int32):
    for i in range(Int(capacity)*WORDS+2):out_words[unsafe_offset=i]=current[unsafe_offset=i]
    for i in range(Int(capacity)*GEOMETRY+2):out_values[unsafe_offset=i]=values[unsafe_offset=i]
    for i in range(5):out_state[unsafe_offset=i]=state[unsafe_offset=i]
