"""Explicit static triangle collision, bounded BVH queries and exact distances.

Vertices and queries use Float64 world coordinates. Collision ownership is
independent of draw resources. Capsule sweeps use conservative advancement.
"""
from .math3d import Vec3
from .spatial import Bounds3D
from .mesh import Mesh
from .transform3d import Mat4
from .assetio import BinaryAsset,ASSET_COLLISION
from std.math import isfinite

@fieldwise_init
struct Triangle3D(ImplicitlyCopyable,Movable):
    var a: Vec3
    var b: Vec3
    var c: Vec3
    def bounds(self) -> Bounds3D:
        return Bounds3D(Vec3(min(self.a.x,min(self.b.x,self.c.x)),min(self.a.y,min(self.b.y,self.c.y)),min(self.a.z,min(self.b.z,self.c.z))),Vec3(max(self.a.x,max(self.b.x,self.c.x)),max(self.a.y,max(self.b.y,self.c.y)),max(self.a.z,max(self.b.z,self.c.z))))
    def normal(self) -> Vec3:return (self.b-self.a).cross(self.c-self.a).unit()
    def closest(self,p: Vec3) -> Vec3:
        var ab=self.b-self.a
        var ac=self.c-self.a
        var ap=p-self.a
        var d1=ab.dot(ap)
        var d2=ac.dot(ap)
        if d1<=0 and d2<=0:return self.a
        var bp=p-self.b
        var d3=ab.dot(bp)
        var d4=ac.dot(bp)
        if d3>=0 and d4<=d3:return self.b
        var vc=d1*d4-d3*d2
        if vc<=0 and d1>=0 and d3<=0:return self.a+ab*(d1/(d1-d3))
        var cp=p-self.c
        var d5=ab.dot(cp)
        var d6=ac.dot(cp)
        if d6>=0 and d5<=d6:return self.c
        var vb=d5*d2-d1*d6
        if vb<=0 and d2>=0 and d6<=0:return self.a+ac*(d2/(d2-d6))
        var va=d3*d6-d5*d4
        if va<=0 and d4-d3>=0 and d5-d6>=0:return self.b+(self.c-self.b)*((d4-d3)/((d4-d3)+(d5-d6)))
        var inverse=1/(va+vb+vc)
        return self.a+ab*(vb*inverse)+ac*(vc*inverse)
    def ray(self,p: Vec3,direction: Vec3,maximum: Float64) -> Float64:
        var edge=self.b-self.a
        var second=self.c-self.a
        var cross=direction.cross(second)
        var determinant=edge.dot(cross)
        if abs(determinant)<1e-12:return -1
        var inverse=1/determinant
        var offset=p-self.a
        var u=offset.dot(cross)*inverse
        if u<0 or u>1:return -1
        var q=offset.cross(edge)
        var v=direction.dot(q)*inverse
        if v<0 or u+v>1:return -1
        var t=second.dot(q)*inverse
        return t if t>=0 and t<=maximum else -1

def edge_closest(a: Vec3,b: Vec3,c: Vec3,d: Vec3) -> Tuple[Vec3,Vec3]:
    var first=b-a
    var second=d-c
    var offset=a-c
    var aa=first.dot(first)
    var bb=second.dot(second)
    var s: Float64=0
    var t: Float64=0
    if aa<=1e-20 and bb<=1e-20:return (a,c)
    if aa<=1e-20:t=max(0.0,min(1.0,second.dot(offset)/bb))
    else:
        var dot=first.dot(offset)
        if bb<=1e-20:s=max(0.0,min(1.0,-dot/aa))
        else:
            var between=first.dot(second)
            var tail=second.dot(offset)
            var denominator=aa*bb-between*between
            if denominator>1e-20:s=max(0.0,min(1.0,(between*tail-dot*bb)/denominator))
            t=(between*s+tail)/bb
            if t<0:
                t=0
                s=max(0.0,min(1.0,-dot/aa))
            elif t>1:
                t=1
                s=max(0.0,min(1.0,(between-dot)/aa))
    return (a+first*s,c+second*t)

def triangle_capsule(feet: Vec3,radius: Float64,height: Float64,triangle: Triangle3D) -> Tuple[Float64,Vec3]:
    var a=feet+Vec3(0,radius,0)
    var b=feet+Vec3(0,height-radius,0)
    var closest_a=triangle.closest(a)
    var closest_b=triangle.closest(b)
    var separation=a-closest_a
    var nearest=separation.dot(separation)
    var other=b-closest_b
    if other.dot(other)<nearest:
        nearest=other.dot(other)
        separation=other
    for edge in range(3):
        var first=triangle.a if edge==0 else (triangle.b if edge==1 else triangle.c)
        var second=triangle.b if edge==0 else (triangle.c if edge==1 else triangle.a)
        var points=edge_closest(a,b,first,second)
        var delta=points[0]-points[1]
        if delta.dot(delta)<nearest:
            nearest=delta.dot(delta)
            separation=delta
    if triangle.ray(a,b-a,1)>=0:nearest=0
    if nearest>1e-20:
        var length=separation.length()
        return (length-radius,separation*(1/length))
    var normal=triangle.normal()
    if normal.dot((a+b)*.5-triangle.a)<0:normal=normal*(-1)
    return (-radius,normal)

def overlaps(a: Bounds3D,b: Bounds3D) -> Bool:
    return a.minimum.x<=b.maximum.x and a.maximum.x>=b.minimum.x and a.minimum.y<=b.maximum.y and a.maximum.y>=b.minimum.y and a.minimum.z<=b.maximum.z and a.maximum.z>=b.minimum.z
def union(a: Bounds3D,b: Bounds3D) -> Bounds3D:
    return Bounds3D(Vec3(min(a.minimum.x,b.minimum.x),min(a.minimum.y,b.minimum.y),min(a.minimum.z,b.minimum.z)),Vec3(max(a.maximum.x,b.maximum.x),max(a.maximum.y,b.maximum.y),max(a.maximum.z,b.maximum.z)))
def coordinate(p: Vec3,axis: Int) -> Float64:return p.x if axis==0 else (p.y if axis==1 else p.z)

@fieldwise_init
struct BVHNode(ImplicitlyCopyable,Movable):
    var bounds: Bounds3D
    var left: Int
    var right: Int
    var start: Int
    var count: Int

struct TriangleMesh3D(Copyable,Movable):
    var triangles: List[Triangle3D]
    var order: List[Int]
    var nodes: List[BVHNode]
    var delta: Vec3
    var revision: Int
    def __init__(out self,var triangles: List[Triangle3D],var order: List[Int],var nodes: List[BVHNode]):
        """Internal constructor for topology validated by load()."""
        self.triangles=triangles^
        self.order=order^
        self.nodes=nodes^
        self.delta=Vec3(0,0,0)
        self.revision=0
    def __init__(out self,mesh: Mesh,matrix: Mat4=Mat4()) raises:
        self.triangles=List[Triangle3D]()
        self.order=List[Int]()
        self.nodes=List[BVHNode]()
        self.delta=Vec3(0,0,0)
        self.revision=0
        mesh.validate()
        if len(mesh.indices)>3000000:raise Error("Triangle collision exceeds triangle limit")
        for i in range(0,len(mesh.indices),3):
            var points=List[Vec3]()
            for j in range(3):
                var offset=Int(mesh.indices[i+j])*8
                points.append(matrix.point(Vec3(Float64(mesh.vertices[offset]),Float64(mesh.vertices[offset+1]),Float64(mesh.vertices[offset+2]))))
                if not isfinite(points[j].x) or not isfinite(points[j].y) or not isfinite(points[j].z):raise Error("Non-finite collision transform")
            if (points[1]-points[0]).cross(points[2]-points[0]).length()<1e-12:continue
            self.order.append(len(self.triangles))
            self.triangles.append(Triangle3D(points[0],points[1],points[2]))
        if len(self.triangles)==0:raise Error("Collision mesh has no nondegenerate triangles")
        _=self.build(0,len(self.triangles),0)
    @staticmethod
    def load(path: String,matrix: Mat4=Mat4(),payload_budget: Int=128*1024*1024,file_budget: Int=64*1024*1024) raises -> Self:
        var source=BinaryAsset(path,ASSET_COLLISION,file_budget)
        source.validate_dependencies(path,file_budget,file_budget)
        var triangles=source.count(1000000)
        var nodes=source.count(2000000)
        if triangles<1 or nodes<1:raise Error("Empty cooked collision")
        if triangles*80+nodes*80>payload_budget:raise Error("Cooked collision exceeds payload budget")
        source.require(triangles*40+nodes*64)
        var geometry=List[Triangle3D]()
        for _ in range(triangles):
            var points=List[Vec3]()
            for _ in range(3):
                var x=source.floating(4)
                var y=source.floating(4)
                var z=source.floating(4)
                points.append(Vec3(x,y,z))
            if (points[1]-points[0]).cross(points[2]-points[0]).length()<1e-12:raise Error("Degenerate cooked collision triangle")
            geometry.append(Triangle3D(points[0],points[1],points[2]))
        var order=List[Int]()
        var seen=List[Bool](length=triangles,fill=False)
        for _ in range(triangles):
            var index=source.count(triangles-1)
            if seen[index]:raise Error("Duplicate cooked triangle order")
            seen[index]=True
            order.append(index)
        var tree=List[BVHNode]()
        for i in range(nodes):
            var values=List[Float64]()
            for _ in range(6):values.append(source.floating())
            var bounds=Bounds3D(Vec3(values[0],values[1],values[2]),Vec3(values[3],values[4],values[5]))
            if values[0]>values[3] or values[1]>values[4] or values[2]>values[5]:raise Error("Inverted cooked BVH bounds")
            var left=source.integer()
            var right=source.integer()
            var start=source.integer()
            var count=source.integer()
            if count>0:
                if left!=-1 or right!=-1 or start<0 or start+count>triangles:raise Error("Invalid cooked BVH leaf")
                for j in range(start,start+count):
                    var actual=geometry[order[j]].bounds()
                    if actual.minimum.x<bounds.minimum.x or actual.minimum.y<bounds.minimum.y or actual.minimum.z<bounds.minimum.z or actual.maximum.x>bounds.maximum.x or actual.maximum.y>bounds.maximum.y or actual.maximum.z>bounds.maximum.z:raise Error("Cooked BVH leaf does not enclose triangles")
            elif count!=0 or left<=i or right<=i or left>=nodes or right>=nodes or left==right:raise Error("Invalid cooked BVH branch/cycle")
            tree.append(BVHNode(bounds,left,right,start,count))
        source.finish()
        var parents=List[Int](length=nodes,fill=0)
        var coverage=List[Int](length=triangles,fill=0)
        var depths=List[Int](length=nodes,fill=0)
        for i in range(nodes):
            var node=tree[i]
            if i>0 and parents[i]!=1:raise Error("Disconnected/multiply-parented cooked BVH")
            if depths[i]>32:raise Error("Cooked BVH exceeds traversal depth")
            if node.count:
                for j in range(node.start,node.start+node.count):coverage[j]+=1
            else:
                for child in [node.left,node.right]:
                    parents[child]+=1
                    depths[child]=depths[i]+1
                    var actual=tree[child].bounds
                    if actual.minimum.x<node.bounds.minimum.x or actual.minimum.y<node.bounds.minimum.y or actual.minimum.z<node.bounds.minimum.z or actual.maximum.x>node.bounds.maximum.x or actual.maximum.y>node.bounds.maximum.y or actual.maximum.z>node.bounds.maximum.z:raise Error("Cooked BVH branch does not enclose children")
        for count in coverage:
            if count!=1:raise Error("Cooked BVH does not cover every triangle exactly once")
        var result=Self(geometry^,order^,tree^)
        for i in range(len(result.triangles)):
            var triangle=result.triangles[i]
            result.triangles[i]=Triangle3D(matrix.point(triangle.a),matrix.point(triangle.b),matrix.point(triangle.c))
            if (result.triangles[i].b-result.triangles[i].a).cross(result.triangles[i].c-result.triangles[i].a).length()<1e-12:raise Error("Singular cooked collision transform")
            for point in [result.triangles[i].a,result.triangles[i].b,result.triangles[i].c]:
                if not isfinite(point.x) or not isfinite(point.y) or not isfinite(point.z):raise Error("Non-finite cooked collision transform")
        for i in range(len(result.nodes)):
            result.nodes[i].bounds=result.nodes[i].bounds.transformed(matrix)
            for point in [result.nodes[i].bounds.minimum,result.nodes[i].bounds.maximum]:
                if not isfinite(point.x) or not isfinite(point.y) or not isfinite(point.z):raise Error("Non-finite cooked collision bounds")
        return result^
    def payload_bytes(self) -> Int:
        return len(self.triangles)*80+len(self.nodes)*80
    def build(mut self,start: Int,count: Int,depth: Int) raises -> Int:
        var bounds=self.triangles[self.order[start]].bounds()
        for i in range(start+1,start+count):bounds=union(bounds,self.triangles[self.order[i]].bounds())
        var index=len(self.nodes)
        self.nodes.append(BVHNode(bounds,-1,-1,start,count))
        if count<=8 or depth==32:return index
        var span=bounds.maximum-bounds.minimum
        var axis=0 if span.x>=span.y and span.x>=span.z else (1 if span.y>=span.z else 2)
        var split=coordinate((bounds.minimum+bounds.maximum)*.5,axis)
        var middle=start
        for i in range(start,start+count):
            var triangle=self.triangles[self.order[i]]
            if coordinate((triangle.a+triangle.b+triangle.c)*(1.0/3),axis)<split:
                var previous=self.order[middle]
                self.order[middle]=self.order[i]
                self.order[i]=previous
                middle+=1
        if middle==start or middle==start+count:middle=start+count//2
        var left=self.build(start,middle-start,depth+1)
        var right=self.build(middle,start+count-middle,depth+1)
        self.nodes[index].left=left
        self.nodes[index].right=right
        self.nodes[index].count=0
        return index
    def query(self,bounds: Bounds3D) -> List[Int]:
        var result=List[Int]()
        if len(self.nodes)==0:return result^
        var stack: List[Int]=[0]
        while len(stack)>0:
            var node=self.nodes[stack.pop()]
            if not overlaps(node.bounds,bounds):continue
            if node.count>0:
                for i in range(node.start,node.start+node.count):
                    var triangle=self.order[i]
                    if overlaps(self.triangles[triangle].bounds(),bounds):result.append(triangle)
            else:
                stack.append(node.left)
                stack.append(node.right)
        return result^
    def move(mut self,delta: Vec3):
        for i in range(len(self.triangles)):
            self.triangles[i].a=self.triangles[i].a+delta
            self.triangles[i].b=self.triangles[i].b+delta
            self.triangles[i].c=self.triangles[i].c+delta
        for i in range(len(self.nodes)):
            self.nodes[i].bounds.minimum=self.nodes[i].bounds.minimum+delta
            self.nodes[i].bounds.maximum=self.nodes[i].bounds.maximum+delta
        self.delta=delta
        self.revision+=1
    def ray(self,origin: Vec3,direction: Vec3,maximum: Float64=10000) -> Float64:
        if len(self.nodes)==0:return -1
        var nearest=maximum
        var hit=False
        var stack: List[Int]=[0]
        while len(stack)>0:
            var node=self.nodes[stack.pop()]
            if node.bounds.ray(origin,direction,nearest)<0:continue
            if node.count>0:
                for i in range(node.start,node.start+node.count):
                    var distance=self.triangles[self.order[i]].ray(origin,direction,nearest)
                    if distance>=0:
                        nearest=distance
                        hit=True
            else:
                stack.append(node.left)
                stack.append(node.right)
        return nearest if hit else -1
