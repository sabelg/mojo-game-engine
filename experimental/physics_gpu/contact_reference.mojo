"""Independent CPU history reference over matrix/corner/six-face geometry.

Linear identity search and six-face ambiguity classification; no GPU history
feature, index map, matching or transaction helper is called.
"""
from std.collections import List
from mojo_game.math3d import Vec3
from .collision import PairKey,SphereContact
from .contact_oracle import OracleSphere,oracle_center
from .box_oracle import OracleBox,mixed_frame,box_center,box_axes,scalar
from .contact_history import TrackedContact,ContactFrame

def same_key(a: PairKey,b: PairKey) -> Bool:
    return a.a.slot==b.a.slot and a.b.slot==b.b.slot and a.a.generation==b.a.generation and a.b.generation==b.b.generation and a.a.owner==b.a.owner and a.b.owner==b.b.owner and a.revision_a==b.revision_a and a.revision_b==b.revision_b and a.body_a.slot==b.body_a.slot and a.body_b.slot==b.body_b.slot and a.body_a.generation==b.body_a.generation and a.body_b.generation==b.body_b.generation

def reference_feature(c: SphereContact,spheres: List[OracleSphere],boxes: List[OracleBox]) -> Tuple[UInt64,Bool]:
    var box_index=Int(-1);var sphere_index=Int(-1)
    for i in range(len(boxes)):
        if boxes[i].shape.slot==c.key.a.slot or boxes[i].shape.slot==c.key.b.slot:box_index=i
    if box_index<0:
        var a=Vec3(0,0,0);var b=Vec3(0,0,0)
        for s in spheres:
            if s.shape.slot==c.key.a.slot:a=oracle_center(s)
            if s.shape.slot==c.key.b.slot:b=oracle_center(s)
        var d=b-a;var zero=d.x*d.x+d.y*d.y+d.z*d.z==0
        return UInt64(1 if zero else 0),zero
    for i in range(len(spheres)):
        if spheres[i].shape.slot==c.key.a.slot or spheres[i].shape.slot==c.key.b.slot:sphere_index=i
    var box=boxes[box_index];var delta=oracle_center(spheres[sphere_index])-box_center(box);var axes=box_axes(box)
    var local=Vec3(delta.dot(axes[0]),delta.dot(axes[1]),delta.dot(axes[2]))
    var code=Int(0);var outside=False
    for axis in range(3):
        var coordinate=scalar(local,axis);var half=scalar(box.half_extents,axis);var digit=Int(1)
        if coordinate < -half:digit=0;outside=True
        elif coordinate > half:digit=2;outside=True
        code=code*3+digit
    if outside:return UInt64(10+code),False
    var best=Float64(1e30);var face_index=Int(0);var ties=Int(0)
    for face in range(6):
        var axis=face//2;var sign=Float64(1 if face%2==0 else -1)
        var distance=abs(sign*scalar(box.half_extents,axis)-scalar(local,axis))
        if distance<best:best=distance;face_index=face;ties=1
        elif distance==best:ties+=1
    return UInt64(50+face_index),ties>1

struct ContactReference(Movable):
    var previous: List[TrackedContact]
    var epoch: UInt64
    var next_id: UInt64
    var capacity: Int
    var event_capacity: Int

    def __init__(out self,capacity: Int=256,event_capacity: Int=512):
        self.previous=List[TrackedContact]();self.epoch=0;self.next_id=1;self.capacity=capacity;self.event_capacity=event_capacity

    def update(mut self,spheres: List[OracleSphere],boxes: List[OracleBox]) raises -> ContactFrame:
        var geometry=mixed_frame(spheres,boxes)
        if len(geometry.contacts)>self.capacity:raise Error("reference history capacity")
        if self.epoch==UInt64.MAX:raise Error("reference epoch exhausted")
        var active=List[TrackedContact]();var ended=List[TrackedContact]();var used=List[Bool]()
        for _ in self.previous:used.append(False)
        var next=self.next_id
        for c in geometry.contacts:
            var feature=reference_feature(c,spheres,boxes);var previous=Int(-1)
            if not feature[1]:
                for i in range(len(self.previous)):
                    var old=self.previous[i]
                    if not same_key(old.contact.key,c.key) or old.feature!=feature[0] or old.ambiguous:continue
                    var dot=old.contact.normal.x*c.normal.x+old.contact.normal.y*c.normal.y+old.contact.normal.z*c.normal.z
                    if dot>=.95:previous=i;break
            var identity=next;var age=UInt64(1);var status=UInt64(1)
            if previous>=0:
                if self.previous[previous].age==UInt64.MAX:raise Error("reference age exhausted")
                identity=self.previous[previous].identity;age=self.previous[previous].age+1;status=2;used[previous]=True
            else:
                if next==0:raise Error("reference identity exhausted")
                next=0 if next==UInt64.MAX else next+1
            active.append(TrackedContact(c,identity,age,feature[0],feature[1],status))
        for i in range(len(self.previous)):
            if not used[i]:
                var old=self.previous[i];old.status=3;ended.append(old)
        if len(active)+len(ended)>self.event_capacity:raise Error("reference event capacity")
        self.previous=List[TrackedContact]()
        for c in active:self.previous.append(c)
        self.epoch+=1;self.next_id=next
        return ContactFrame(active^,ended^,self.epoch)
