"""Owned, revision-driven scene submission data with bounded spatial culling.

A cache belongs to one scene. Callers must change scene_revision after any node
mutation, or invalidate() for temporary edits. Asset revisions also invalidate it.
No scene pointers or GPU handles are retained. Bounds stay in double precision.
"""
from .math3d import Vec3
from .transform3d import Mat4
from .scene3d import Material
from .spatial import Bounds3D,Frustum
from std.math import isfinite

@fieldwise_init
struct SceneDrawItem(ImplicitlyCopyable,Movable):
    var node: Int
    var mesh: Int
    var matrix: Mat4
    var material: Material
    var bounds: Bounds3D
    var batch: Int

@fieldwise_init
struct VisibilityBranch(ImplicitlyCopyable,Movable):
    var bounds: Bounds3D
    var left: Int
    var right: Int
    var start: Int
    var count: Int

def joined(a: Bounds3D,b: Bounds3D) -> Bounds3D:
    return Bounds3D(Vec3(min(a.minimum.x,b.minimum.x),min(a.minimum.y,b.minimum.y),min(a.minimum.z,b.minimum.z)),Vec3(max(a.maximum.x,b.maximum.x),max(a.maximum.y,b.maximum.y),max(a.maximum.z,b.maximum.z)))

def component(point: Vec3,axis: Int) -> Float64:
    return point.x if axis==0 else (point.y if axis==1 else point.z)

def ordered(var values: List[Int]) -> List[Int]:
    # Bottom-up merge preserves source submission order in O(v log v).
    var scratch=List[Int]()
    for _ in values:scratch.append(0)
    var width=1
    while width<len(values):
        for start in range(0,len(values),width*2):
            var middle=min(start+width,len(values))
            var end=min(start+width*2,len(values))
            var first=start
            var second=middle
            for i in range(start,end):
                if first<middle and (second>=end or values[first]<=values[second]):
                    scratch[i]=values[first]
                    first+=1
                else:
                    scratch[i]=values[second]
                    second+=1
        var previous=values^
        values=scratch^
        scratch=previous^
        width*=2
    return values^

struct SceneDrawCache(Copyable,Movable):
    var items: List[SceneDrawItem]
    var order: List[Int]
    var branches: List[VisibilityBranch]
    var scene_revision: Int
    var asset_revision: UInt64
    var node_count: Int
    var ready: Bool
    var builds: Int
    var branch_tests: Int
    var item_tests: Int

    def __init__(out self):
        self.items=List[SceneDrawItem]()
        self.order=List[Int]()
        self.branches=List[VisibilityBranch]()
        self.scene_revision=-1
        self.asset_revision=0
        self.node_count=0
        self.ready=False
        self.builds=0
        self.branch_tests=0
        self.item_tests=0

    def invalidate(mut self):self.ready=False

    def matches(self,revision: Int,assets: UInt64,nodes: Int) -> Bool:
        return self.ready and self.scene_revision==revision and self.asset_revision==assets and self.node_count==nodes

    def build(mut self) raises:
        if len(self.items)>100000:raise Error("Scene visibility exceeds node budget")
        self.order.clear()
        self.branches.clear()
        for i in range(len(self.items)):
            for point in [self.items[i].bounds.minimum,self.items[i].bounds.maximum]:
                if not isfinite(point.x) or not isfinite(point.y) or not isfinite(point.z):raise Error("Non-finite scene visibility bound")
            self.order.append(i)
        if len(self.items)>0:_=self.split(0,len(self.items),0)

    def split(mut self,start: Int,count: Int,depth: Int) raises -> Int:
        var bounds=self.items[self.order[start]].bounds
        for i in range(start+1,start+count):bounds=joined(bounds,self.items[self.order[i]].bounds)
        var index=len(self.branches)
        self.branches.append(VisibilityBranch(bounds,-1,-1,start,count))
        if count<=8 or depth>=32:return index
        var span=bounds.maximum-bounds.minimum
        var axis=0 if span.x>=span.y and span.x>=span.z else (1 if span.y>=span.z else 2)
        var midpoint=component(bounds.minimum*.5+bounds.maximum*.5,axis)
        var middle=start
        for i in range(start,start+count):
            var box=self.items[self.order[i]].bounds
            if component(box.minimum*.5+box.maximum*.5,axis)<midpoint:
                var value=self.order[middle]
                self.order[middle]=self.order[i]
                self.order[i]=value
                middle+=1
        if middle==start or middle==start+count:middle=start+count//2
        var left=self.split(start,middle-start,depth+1)
        var right=self.split(middle,start+count-middle,depth+1)
        self.branches[index].left=left
        self.branches[index].right=right
        return index

    def visible(mut self,projection: Mat4,origin: Vec3=Vec3(0,0,0),hierarchical: Bool=True) -> List[Int]:
        self.branch_tests=0
        self.item_tests=0
        var result=List[Int]()
        var frustum=Frustum(projection)
        if not hierarchical:
            for i in range(len(self.items)):
                self.item_tests+=1
                if frustum.visible(self.items[i].bounds,origin):result.append(i)
            return result^
        if len(self.branches)==0:return result^
        var stack: List[Int]=[0]
        while len(stack)>0:
            var branch=self.branches[stack.pop()]
            self.branch_tests+=1
            var relation=frustum.relation(branch.bounds,origin)
            if relation<0:continue
            if relation==1:
                # The entire scene is visible: source indices already have the
                # required order, so avoid sorting the spatial permutation.
                if branch.count==len(self.items):
                    for i in range(len(self.items)):result.append(i)
                    return result^
                for i in range(branch.start,branch.start+branch.count):result.append(self.order[i])
            elif branch.left>=0:
                stack.append(branch.right)
                stack.append(branch.left)
            else:
                for i in range(branch.start,branch.start+branch.count):
                    var item=self.order[i]
                    self.item_tests+=1
                    if frustum.visible(self.items[item].bounds,origin):result.append(item)
        return ordered(result^)
