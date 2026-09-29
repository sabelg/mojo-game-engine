"""Original Yo Frankie scenes, placements, portals and triangle collision."""
from std.math import floor
from mojo_game import Vec3

def vector(text: String) raises -> Vec3:
    var f = text.split()
    if len(f) != 3: raise Error("Expected xyz")
    return Vec3(Float64(String(f[0])),Float64(String(f[1])),Float64(String(f[2])))

def read_text(path: String) raises -> String:
    with open(path,"r") as file: return file.read()

struct Triangle(ImplicitlyCopyable, Movable):
    var a: Vec3
    var b: Vec3
    var c: Vec3
    var normal: Vec3
    def __init__(out self, a: Vec3,b: Vec3,c: Vec3):
        self.a=a
        self.b=b
        self.c=c
        self.normal=(b-a).cross(c-a).unit()
    def height(self,x: Float64,z: Float64) -> Float64:
        var ab=self.b-self.a
        var ac=self.c-self.a
        var det=ab.x*ac.z-ab.z*ac.x
        if abs(det)<0.0000001: return -10000
        var u=((x-self.a.x)*ac.z-(z-self.a.z)*ac.x)/det
        var v=(ab.x*(z-self.a.z)-ab.z*(x-self.a.x))/det
        if u < -0.001 or v < -0.001 or u+v > 1.001: return -10000
        return self.a.y+u*ab.y+v*ac.y
    def closest(self,p: Vec3) -> Vec3:
        var ab=self.b-self.a
        var ac=self.c-self.a
        var ap=p-self.a
        var d1=ab.dot(ap)
        var d2=ac.dot(ap)
        if d1<=0 and d2<=0: return self.a
        var bp=p-self.b
        var d3=ab.dot(bp)
        var d4=ac.dot(bp)
        if d3>=0 and d4<=d3: return self.b
        var vc=d1*d4-d3*d2
        if vc<=0 and d1>=0 and d3<=0: return self.a+ab*(d1/(d1-d3))
        var cp=p-self.c
        var d5=ab.dot(cp)
        var d6=ac.dot(cp)
        if d6>=0 and d5<=d6: return self.c
        var vb=d5*d2-d1*d6
        if vb<=0 and d2>=0 and d6<=0: return self.a+ac*(d2/(d2-d6))
        var va=d3*d6-d5*d4
        if va<=0 and d4-d3>=0 and d5-d6>=0: return self.b+(self.c-self.b)*((d4-d3)/((d4-d3)+(d5-d6)))
        var denominator=va+vb+vc
        if abs(denominator)<0.00000001:return self.a
        return self.a+ab*(vb/denominator)+ac*(vc/denominator)

struct Entity(Copyable, Movable):
    var kind: String
    var prefab: String
    var position: Vec3
    var home: Vec3
    var velocity: Vec3
    var scale: Vec3
    var angle: Float64
    var health: Int
    var active: Bool
    var stun: Float64
    def __init__(out self,var kind: String,var prefab: String,position: Vec3,angle: Float64,scale: Vec3):
        self.kind=kind^
        self.prefab=prefab^
        self.position=position
        self.home=position
        self.velocity=Vec3(0,0,0)
        self.angle=angle
        self.scale=Vec3(scale.x,scale.z,scale.y)
        self.health=4 if self.kind=="sheep" or self.kind=="ram" else 2
        self.active=True
        self.stun=0

struct Trigger(Copyable, Movable):
    var kind: String
    var low: Vec3
    var high: Vec3
    var blend: String
    var scene: String
    var target: String
    def __init__(out self,var kind: String,low: Vec3,high: Vec3,var blend: String,var scene: String,var target: String):
        self.kind=kind^
        self.low=low
        self.high=high
        self.blend=blend^
        self.scene=scene^
        self.target=target^
    def contains(self,p: Vec3,margin: Float64=0) -> Bool:
        return p.x>=self.low.x-margin and p.x<=self.high.x+margin and p.z>=self.low.z-margin and p.z<=self.high.z+margin and p.y>=self.low.y-0.3 and p.y<=self.high.y+0.45

struct Level(Copyable, Movable):
    var key: String
    var blend: String
    var name: String
    var spawn: Vec3
    var triangles: List[Triangle]
    var hazards: List[Triangle]
    var cells: Dict[Int,List[Int]]
    var entities: List[Entity]
    var triggers: List[Trigger]
    var markers: Dict[String,Vec3]
    def __init__(out self):
        self.key=""
        self.blend=""
        self.name=""
        self.spawn=Vec3(0,0,0)
        self.triangles=List[Triangle]()
        self.hazards=List[Triangle]()
        self.cells=Dict[Int,List[Int]]()
        self.entities=List[Entity]()
        self.triggers=List[Trigger]()
        self.markers=Dict[String,Vec3]()
    @staticmethod
    def cell(x: Float64,z: Float64) -> Int:
        return Int(floor(x/4))*100000+Int(floor(z/4))
    def load(mut self,entry: String) raises:
        self=Self()
        var f=entry.split("\t")
        if len(f)!=4:raise Error("Invalid scene entry")
        self.key=String(f[0])
        self.blend=String(f[1])
        self.name=String(f[2])
        self.spawn=vector(String(f[3]))
        var base="assets/yofrankie/"+self.key
        for line in read_text(base+".collision").split("\n"):
            var n=String(line).split()
            if len(n)==0:continue
            if len(n)!=9:raise Error("Invalid collision triangle")
            var tri=Triangle(Vec3(Float64(String(n[0])),Float64(String(n[1])),Float64(String(n[2]))),Vec3(Float64(String(n[3])),Float64(String(n[4])),Float64(String(n[5]))),Vec3(Float64(String(n[6])),Float64(String(n[7])),Float64(String(n[8]))))
            if tri.normal.length()<0.5:continue
            var idx=len(self.triangles)
            self.triangles.append(tri)
            var x0=Int(floor(min(tri.a.x,min(tri.b.x,tri.c.x))/4))
            var x1=Int(floor(max(tri.a.x,max(tri.b.x,tri.c.x))/4))
            var z0=Int(floor(min(tri.a.z,min(tri.b.z,tri.c.z))/4))
            var z1=Int(floor(max(tri.a.z,max(tri.b.z,tri.c.z))/4))
            if x1-x0>1000 or z1-z0>1000:raise Error("Collision triangle exceeds world limits")
            for x in range(x0,x1+1):
                for z in range(z0,z1+1):
                    var k=x*100000+z
                    if k not in self.cells:self.cells[k]=List[Int]()
                    self.cells[k].append(idx)
        for line in read_text(base+".hazards").split("\n"):
            var n=String(line).split()
            if len(n)==0:continue
            if len(n)!=9:raise Error("Invalid hazard triangle")
            self.hazards.append(Triangle(Vec3(Float64(String(n[0])),Float64(String(n[1])),Float64(String(n[2]))),Vec3(Float64(String(n[3])),Float64(String(n[4])),Float64(String(n[5]))),Vec3(Float64(String(n[6])),Float64(String(n[7])),Float64(String(n[8])))))
        for line in read_text(base+".entities").split("\n"):
            var n=String(line).split("\t")
            if len(n)<2:continue
            if len(n)!=5:raise Error("Invalid entity")
            self.entities.append(Entity(String(n[0]),String(n[1]),vector(String(n[2])),Float64(String(n[3])),vector(String(n[4]))))
        for line in read_text(base+".triggers").split("\n"):
            var n=String(line).split("\t")
            if len(n)<2:continue
            if len(n)!=6:raise Error("Invalid trigger")
            self.triggers.append(Trigger(String(n[0]),vector(String(n[1])),vector(String(n[2])),String(n[3]),String(n[4]),String(n[5])))
        for line in read_text(base+".markers").split("\n"):
            var n=String(line).split("\t")
            if len(n)==2:self.markers[String(n[0])]=vector(String(n[1]))
    def floor_at(self,p: Vec3,ceiling: Float64) raises -> Float64:
        var k=Self.cell(p.x,p.z)
        var best: Float64=-10000
        if k not in self.cells:return best
        for i in self.cells[k]:
            var tri=self.triangles[i]
            if abs(tri.normal.y)<0.45:continue
            var h=tri.height(p.x,p.z)
            if h<=ceiling and h>best:best=h
        return best
    def walls(self,p: Vec3) raises -> Vec3:
        var result=p
        for dx in range(-1,2):
            for dz in range(-1,2):
                var k=Self.cell(p.x,p.z)+dx*100000+dz
                if k not in self.cells:continue
                for i in self.cells[k]:
                    var tri=self.triangles[i]
                    if abs(tri.normal.y)>0.65:continue
                    for j in range(2):
                        var center=result+Vec3(0,0.3+Float64(j)*0.4,0)
                        var delta=center-tri.closest(center)
                        var d=delta.length()
                        if d>0.00001 and d<0.24:result=result+delta*((0.24-d)/d)
        return result
    def dangerous(self,p: Vec3) -> Bool:
        for tri in self.hazards:
            if (tri.closest(p+Vec3(0,0.18,0))-p-Vec3(0,0.18,0)).length()<0.22:return True
        return False
    def camera(self,start: Vec3,end: Vec3) -> Vec3:
        var ray=end-start
        var fraction: Float64=1
        for tri in self.triangles:
            var ab=tri.b-tri.a
            var ac=tri.c-tri.a
            var h=ray.cross(ac)
            var det=ab.dot(h)
            if abs(det)<0.000001:continue
            var s=start-tri.a
            var u=s.dot(h)/det
            if u<0 or u>1:continue
            var q=s.cross(ab)
            var v=ray.dot(q)/det
            if v<0 or u+v>1:continue
            var t=ac.dot(q)/det
            if t>0.02 and t<fraction:fraction=max(0.05,t-0.04)
        return start+ray*fraction
