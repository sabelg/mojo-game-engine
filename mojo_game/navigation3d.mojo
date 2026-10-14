"""Bounded single-layer ground navigation tiles built from loaded collision.

Tiles must be rebuilt when collision changes and removed on cell eviction. A
route only traverses resident tiles, with capsule clearance on every edge.
"""
from std.collections import Dict
from std.math import floor,isfinite
from .math3d import Vec3
from .character3d import CollisionWorld3D

@fieldwise_init
struct NavigationTile3D(Copyable,Movable):
    var x: Int
    var z: Int
    var points: List[Vec3]
    var walkable: List[Bool]

struct Navigation3D:
    var tiles: List[NavigationTile3D]
    var size: Float64
    var resolution: Int
    var tile_budget: Int
    var radius: Float64
    var height: Float64
    var max_step: Float64
    var slope: Float64
    def __init__(out self,cell_size: Float64=1,resolution: Int=16,tile_budget: Int=32,radius: Float64=.3,height: Float64=1.8) raises:
        if not isfinite(cell_size) or cell_size<radius*2 or resolution<1 or resolution>32 or tile_budget<1 or tile_budget>128 or radius<=0 or height<radius*2:raise Error("Invalid navigation budgets")
        self.tiles=List[NavigationTile3D]()
        self.size=cell_size
        self.resolution=resolution
        self.tile_budget=tile_budget
        self.radius=radius
        self.height=height
        self.max_step=.35
        self.slope=.7
    def remove(mut self,x: Int,z: Int):
        for i in range(len(self.tiles)):
            if self.tiles[i].x==x and self.tiles[i].z==z:
                self.tiles[i]=self.tiles[len(self.tiles)-1].copy()
                _=self.tiles.pop()
                return
    def build(mut self,world: CollisionWorld3D,x: Int,z: Int,top: Float64=100,bottom: Float64=-100) raises:
        if not isfinite(top) or not isfinite(bottom) or top<=bottom or top-bottom>10000:raise Error("Invalid navigation probe range")
        var found=-1
        for i in range(len(self.tiles)):
            if self.tiles[i].x==x and self.tiles[i].z==z:found=i
        if found<0 and len(self.tiles)>=self.tile_budget:raise Error("Navigation tile budget exceeded")
        var points=List[Vec3]()
        var walkable=List[Bool]()
        for row in range(self.resolution):
            for column in range(self.resolution):
                var p=Vec3((Float64(x*self.resolution+column)+.5)*self.size,top,(Float64(z*self.resolution+row)+.5)*self.size)
                var hit=world.sweep(p,Vec3(0,bottom-top,0),self.radius,self.height)
                var good=False
                if hit:
                    p.y=top+(bottom-top)*hit.value().fraction+.0001
                    good=hit.value().normal.y>=self.slope and (world.recover(p,self.radius,self.height)-p).length()<.001
                points.append(p)
                walkable.append(good)
        var tile=NavigationTile3D(x,z,points^,walkable^)
        if found<0:self.tiles.append(tile^)
        else:self.tiles[found]=tile^
    def point(self,x: Int,z: Int) -> Optional[Vec3]:
        var tx=Int(floor(Float64(x)/Float64(self.resolution)))
        var tz=Int(floor(Float64(z)/Float64(self.resolution)))
        for tile in self.tiles:
            if tile.x==tx and tile.z==tz:
                var index=(z-tz*self.resolution)*self.resolution+x-tx*self.resolution
                if tile.walkable[index]:return tile.points[index]
                break
        return None
    def edge(self,world: CollisionWorld3D,a: Vec3,b: Vec3) -> Bool:
        if abs(b.y-a.y)>self.max_step:return False
        var up=max(0.0,b.y-a.y)+.001
        var raised=a+Vec3(0,up,0)
        if world.sweep(a,Vec3(0,up,0),self.radius,self.height):return False
        if world.sweep(raised,Vec3(b.x-a.x,0,b.z-a.z),self.radius,self.height):return False
        var down=world.sweep(Vec3(b.x,raised.y,b.z),Vec3(0,b.y-raised.y,0),self.radius,self.height)
        return not down or down.value().normal.y>=self.slope and down.value().fraction>=.999
    def path(self,world: CollisionWorld3D,start: Vec3,target: Vec3,expansion_budget: Int=2048) raises -> List[Vec3]:
        if expansion_budget<1 or expansion_budget>8192:raise Error("Invalid navigation search budget")
        for point in [start,target]:
            if not isfinite(point.x) or not isfinite(point.y) or not isfinite(point.z):raise Error("Non-finite navigation endpoint")
        var sx=Int(floor(start.x/self.size))
        var sz=Int(floor(start.z/self.size))
        var gx=Int(floor(target.x/self.size))
        var gz=Int(floor(target.z/self.size))
        var begin=self.point(sx,sz)
        var goal=self.point(gx,gz)
        if not begin or not goal or abs(begin.value().y-start.y)>self.max_step or abs(goal.value().y-target.y)>self.max_step:return List[Vec3]()
        if not self.edge(world,start,begin.value()) or not self.edge(world,goal.value(),target):return List[Vec3]()
        var points=List[Vec3]()
        var xs=List[Int]()
        var zs=List[Int]()
        var costs=List[Float64]()
        var parents=List[Int]()
        var closed=List[Bool]()
        var open=List[Int]()
        var index=Dict[String,Int]()
        points.append(begin.value());xs.append(sx);zs.append(sz);costs.append(0);parents.append(-1);closed.append(False);open.append(0)
        index[String(sx)+":"+String(sz)]=0
        var expanded=0
        while len(open)>0 and expanded<expansion_budget:
            var best=0
            var score=Float64(1e100)
            for i in range(len(open)):
                var slot=open[i]
                var candidate=costs[slot]+(points[slot]-goal.value()).length()
                if candidate<score:score=candidate;best=i
            var current=open[best]
            open[best]=open[len(open)-1];_=open.pop()
            if closed[current]:continue
            closed[current]=True;expanded+=1
            if xs[current]==gx and zs[current]==gz:
                var backwards=List[Vec3]()
                var cursor=current
                while cursor>=0:
                    backwards.append(points[cursor]);cursor=parents[cursor]
                var route=List[Vec3]()
                for i in range(len(backwards)-1,-1,-1):route.append(backwards[i])
                if (route[len(route)-1]-target).length()>1e-8:route.append(target)
                return route^
            for direction in range(4):
                var nx=xs[current]+(1 if direction==0 else (-1 if direction==1 else 0))
                var nz=zs[current]+(1 if direction==2 else (-1 if direction==3 else 0))
                var next=self.point(nx,nz)
                if not next or not self.edge(world,points[current],next.value()):continue
                var key=String(nx)+":"+String(nz)
                var slot=index.get(key,-1)
                var cost=costs[current]+(next.value()-points[current]).length()
                if slot<0:
                    if len(points)>=expansion_budget*4:continue
                    slot=len(points);index[key]=slot
                    points.append(next.value());xs.append(nx);zs.append(nz);costs.append(cost);parents.append(current);closed.append(False);open.append(slot)
                elif not closed[slot] and cost<costs[slot]:
                    costs[slot]=cost;parents[slot]=current
        return List[Vec3]()

struct PathFollower3D:
    var route: List[Vec3]
    var next: Int
    def __init__(out self):
        self.route=List[Vec3]()
        self.next=0
    def follow(mut self,position: Vec3,speed: Float64,dt: Float64) raises -> Vec3:
        if not isfinite(speed) or speed<0 or dt<=0 or dt>.25 or not isfinite(dt):raise Error("Invalid path follower step")
        while self.next<len(self.route):
            var delta=self.route[self.next]-position
            delta.y=0
            if delta.length()<.05:self.next+=1;continue
            return delta.unit()*min(speed,delta.length()/dt)
        return Vec3(0,0,0)
