"""Swept upright capsules against boxes, moving platforms and procedural terrain.

Position is the capsule's feet. Scene colliders are explicitly authored; render
meshes do not automatically become collision. Box sweeps use capsule distance,
not a ray-only approximation. Terrain contact uses bounded spatial sampling.
"""
from .math3d import Vec3
from .spatial import Bounds3D
from .terrain import TerrainConfig
from std.math import sqrt,isfinite,cos
from .mesh import Mesh
from .transform3d import Mat4,Quaternion
from .triangle3d import TriangleMesh3D,Triangle3D,BVHNode,triangle_capsule

struct CollisionBox(ImplicitlyCopyable,Movable):
    var bounds: Bounds3D
    var delta: Vec3
    var revision: Int
    def __init__(out self,bounds: Bounds3D):
        self.bounds=bounds
        self.delta=Vec3(0,0,0)
        self.revision=0
@fieldwise_init
struct CapsuleHit(ImplicitlyCopyable,Movable):
    var fraction: Float64
    var normal: Vec3
    var collider: Int

def capsule_distance(feet: Vec3,radius: Float64,height: Float64,box: Bounds3D) -> Tuple[Float64,Vec3]:
    var low=feet.y+radius
    var high=feet.y+height-radius
    var segment_y=max(low,min(high,(box.minimum.y+box.maximum.y)*0.5))
    if low>box.maximum.y:segment_y=low
    elif high<box.minimum.y:segment_y=high
    var point=Vec3(feet.x,segment_y,feet.z)
    var closest=Vec3(max(box.minimum.x,min(box.maximum.x,point.x)),max(box.minimum.y,min(box.maximum.y,point.y)),max(box.minimum.z,min(box.maximum.z,point.z)))
    var delta=point-closest
    var distance=delta.length()
    if distance>1e-12:return (distance-radius,delta*(1/distance))
    var depths: List[Float64]=[feet.x+radius-box.minimum.x,box.maximum.x-feet.x+radius,feet.y+height-box.minimum.y,box.maximum.y-feet.y,feet.z+radius-box.minimum.z,box.maximum.z-feet.z+radius]
    var normals: List[Vec3]=[Vec3(-1,0,0),Vec3(1,0,0),Vec3(0,-1,0),Vec3(0,1,0),Vec3(0,0,-1),Vec3(0,0,1)]
    var smallest=0
    for i in range(1,6):
        if depths[i]<depths[smallest]:smallest=i
    return (-depths[smallest],normals[smallest])

struct CollisionWorld3D:
    var boxes: List[CollisionBox]
    var meshes: List[TriangleMesh3D]
    var mesh_enabled: List[Bool]
    var mesh_generations: List[Int]
    def __init__(out self):
        self.boxes=List[CollisionBox]()
        self.meshes=List[TriangleMesh3D]()
        self.mesh_enabled=List[Bool]()
        self.mesh_generations=List[Int]()
    def add_mesh(mut self,mesh: Mesh,matrix: Mat4=Mat4()) raises -> Int:
        return self.add_collider(TriangleMesh3D(mesh,matrix))
    def mesh_id(self,index: Int) -> Int:
        return -2-index-(self.mesh_generations[index]<<20)
    def add_collider(mut self,var collider: TriangleMesh3D) raises -> Int:
        if len(collider.nodes)==0:raise Error("Cannot register empty triangle collider")
        for i in range(len(self.meshes)):
            if not self.mesh_enabled[i]:
                self.meshes[i]=collider^
                self.mesh_enabled[i]=True
                return self.mesh_id(i)
        if len(self.meshes)>=1048576:raise Error("Triangle collider handle limit exceeded")
        self.meshes.append(collider^)
        self.mesh_enabled.append(True)
        self.mesh_generations.append(0)
        return self.mesh_id(len(self.meshes)-1)
    def remove_mesh(mut self,collider: Int) raises:
        if not self.support_exists(collider) or collider>=0:raise Error("Invalid triangle collider")
        var index=(-collider-2)&1048575
        self.mesh_enabled[index]=False
        self.mesh_generations[index]+=1
        self.meshes[index]=TriangleMesh3D(List[Triangle3D](),List[Int](),List[BVHNode]())
    def support_exists(self,collider: Int) -> Bool:
        if collider>=0:return collider<len(self.boxes)
        if collider==-1:return False
        var encoded=-collider-2
        var index=encoded&1048575
        return index<len(self.meshes) and self.mesh_enabled[index] and self.mesh_generations[index]==(encoded>>20)
    def support_revision(self,collider: Int) -> Int:
        if not self.support_exists(collider):return -1
        return self.boxes[collider].revision if collider>=0 else self.meshes[(-collider-2)&1048575].revision
    def support_delta(self,collider: Int) -> Vec3:
        if not self.support_exists(collider):return Vec3(0,0,0)
        return self.boxes[collider].delta if collider>=0 else self.meshes[(-collider-2)&1048575].delta
    def add(mut self,bounds: Bounds3D) raises -> Int:
        if bounds.minimum.x>=bounds.maximum.x or bounds.minimum.y>=bounds.maximum.y or bounds.minimum.z>=bounds.maximum.z:raise Error("Invalid collision box")
        self.boxes.append(CollisionBox(bounds))
        return len(self.boxes)-1
    def move(mut self,index: Int,delta: Vec3) raises:
        if index<=-2:
            if not self.support_exists(index):raise Error("Invalid moving triangle platform")
            self.meshes[(-index-2)&1048575].move(delta)
            return
        if index<0 or index>=len(self.boxes):raise Error("Invalid moving platform")
        self.boxes[index].bounds.minimum=self.boxes[index].bounds.minimum+delta
        self.boxes[index].bounds.maximum=self.boxes[index].bounds.maximum+delta
        self.boxes[index].delta=delta
        self.boxes[index].revision+=1
    def sweep(self,feet: Vec3,motion: Vec3,radius: Float64,height: Float64) -> Optional[CapsuleHit]:
        var nearest: Float64=1.000001
        var result=Optional[CapsuleHit](None)
        for i in range(len(self.boxes)):
            var t: Float64=0
            for _ in range(32):
                var distance=capsule_distance(feet+motion*t,radius,height,self.boxes[i].bounds)
                var approach=-motion.dot(distance[1])
                if distance[0]<=0.00001:
                    if approach>1e-10 and t<nearest:
                        nearest=t
                        result=CapsuleHit(t,distance[1],i)
                    break
                if approach<=1e-12:break
                t+=distance[0]/approach
                if t>1 or t>=nearest:break
        var end=feet+motion
        var bounds=Bounds3D(Vec3(min(feet.x,end.x)-radius,min(feet.y,end.y),min(feet.z,end.z)-radius),Vec3(max(feet.x,end.x)+radius,max(feet.y,end.y)+height,max(feet.z,end.z)+radius))
        for i in range(len(self.meshes)):
            if not self.mesh_enabled[i]:continue
            var candidates=self.meshes[i].query(bounds)
            for index in candidates:
                var t: Float64=0
                for _ in range(64):
                    var distance=triangle_capsule(feet+motion*t,radius,height,self.meshes[i].triangles[index])
                    var approach=-motion.dot(distance[1])
                    if distance[0]<=0.00001:
                        if approach>1e-10 and t<nearest:
                            nearest=t
                            result=CapsuleHit(t,distance[1],self.mesh_id(i))
                        break
                    if approach<=1e-12:break
                    t+=distance[0]/approach
                    if t>1 or t>=nearest:break
        return result
    def recover(self,position: Vec3,radius: Float64,height: Float64) -> Vec3:
        var feet=position
        for _ in range(8):
            var moved=False
            for box in self.boxes:
                var distance=capsule_distance(feet,radius,height,box.bounds)
                if distance[0]<-0.00001:
                    feet=feet+distance[1]*(-distance[0]+0.0001)
                    moved=True
            var bounds=Bounds3D(feet-Vec3(radius,0,radius),feet+Vec3(radius,height,radius))
            for i in range(len(self.meshes)):
                if not self.mesh_enabled[i]:continue
                for index in self.meshes[i].query(bounds):
                    var distance=triangle_capsule(feet,radius,height,self.meshes[i].triangles[index])
                    if distance[0]<-0.00001:
                        feet=feet+distance[1]*(-distance[0]+0.0001)
                        moved=True
            if not moved:break
        return feet

struct CharacterController3D:
    var position: Vec3
    var velocity: Vec3
    var radius: Float64
    var height: Float64
    var step_height: Float64
    var slope_cos: Float64
    var grounded: Bool
    var support: Int
    var support_revision: Int
    var gravity: Float64
    def __init__(out self,position: Vec3=Vec3(0,0,0),radius: Float64=0.35,height: Float64=1.8,step_height: Float64=0.3,max_slope: Float64=0.7853981634) raises:
        if not isfinite(radius) or not isfinite(height) or radius<=0 or height<radius*2 or step_height<0 or max_slope<=0 or max_slope>=1.570796:raise Error("Invalid capsule controller")
        self.position=position
        self.velocity=Vec3(0,0,0)
        self.radius=radius
        self.height=height
        self.step_height=step_height
        self.slope_cos=cos(max_slope)
        self.grounded=False
        self.support=-1
        self.support_revision=-1
        self.gravity=9.81
    def slide(mut self,world: CollisionWorld3D,motion: Vec3):
        var remaining=motion
        for _ in range(5):
            if remaining.length()<1e-8:break
            var hit=world.sweep(self.position,remaining,self.radius,self.height)
            if not hit:
                self.position=self.position+remaining
                break
            var contact=hit.value()
            self.position=self.position+remaining*max(0.0,contact.fraction-0.00001)
            remaining=remaining*(1-contact.fraction)
            var into=remaining.dot(contact.normal)
            if into<0:remaining=remaining-contact.normal*into
            var velocity_into=self.velocity.dot(contact.normal)
            if velocity_into<0:self.velocity=self.velocity-contact.normal*velocity_into
            if contact.normal.y>=self.slope_cos:
                self.grounded=True
                self.support=contact.collider
                self.support_revision=world.support_revision(contact.collider)
    def step(mut self,world: CollisionWorld3D,desired: Vec3,dt: Float64,jump: Bool=False,jump_speed: Float64=5,terrain: Optional[TerrainConfig]=None) raises:
        if not isfinite(dt) or dt<=0 or dt>0.25:raise Error("Character timestep must be in (0,0.25]")
        if not isfinite(desired.x) or not isfinite(desired.y) or not isfinite(desired.z):raise Error("Non-finite movement")
        if world.support_exists(self.support) and self.support_revision!=world.support_revision(self.support):
            self.slide(world,world.support_delta(self.support))
            self.support_revision=world.support_revision(self.support)
        self.position=world.recover(self.position,self.radius,self.height)
        var was_grounded=self.grounded
        self.grounded=False
        self.support=-1
        self.velocity.x=desired.x
        self.velocity.z=desired.z
        if jump and was_grounded:self.velocity.y=jump_speed
        else:self.velocity.y-=self.gravity*dt
        var horizontal=Vec3(desired.x*dt,0,desired.z*dt)
        var obstruction=world.sweep(self.position,horizontal,self.radius,self.height)
        var stepped=False
        if was_grounded and not jump and obstruction and abs(obstruction.value().normal.y)<0.5 and self.step_height>0:
            var up=Vec3(0,self.step_height+0.001,0)
            var raised=self.position+up
            if not world.sweep(self.position,up,self.radius,self.height) and not world.sweep(raised,horizontal,self.radius,self.height):
                var down=Vec3(0,-self.step_height-0.08,0)
                var floor=world.sweep(raised+horizontal,down,self.radius,self.height)
                if floor and floor.value().normal.y>=self.slope_cos:
                    self.position=raised+horizontal+down*floor.value().fraction
                    self.grounded=True
                    self.support=floor.value().collider
                    self.support_revision=world.support_revision(self.support)
                    self.velocity.y=0
                    stepped=True
        if not stepped:
            if terrain:
                # Sampling distance, rather than only timestep, bounds terrain crossing.
                var samples=max(1,Int(horizontal.length()/(self.radius*0.5))+1)
                if samples>256:raise Error("Terrain movement exceeds spatial sweep budget")
                for _ in range(samples):
                    self.slide(world,self.velocity*(dt/Float64(samples)))
                    var floor=terrain.value().height(self.position.x,self.position.z)
                    var normal=terrain.value().normal(self.position.x,self.position.z)
                    if self.position.y<=floor+0.06 and self.velocity.y<=0:
                        self.position.y=max(self.position.y,floor)
                        if normal.y>=self.slope_cos:
                            self.grounded=True
                            self.velocity.y=0
                        else:
                            var into=self.velocity.dot(normal)
                            if into<0:self.velocity=self.velocity-normal*into
            else:self.slide(world,self.velocity*dt)
        if not jump and self.velocity.y<=0:
            var ground=world.sweep(self.position,Vec3(0,-0.08,0),self.radius,self.height)
            if ground and ground.value().normal.y>=self.slope_cos:
                self.position=self.position+Vec3(0,-0.08*ground.value().fraction,0)
                self.grounded=True
                self.support=ground.value().collider
                self.support_revision=world.support_revision(self.support)
                self.velocity.y=0
    def step_root_motion(mut self,world: CollisionWorld3D,delta: Vec3,rotation: Quaternion,dt: Float64,jump: Bool=False) raises:
        """Consume local animation X/Z translation through the capsule solver.

        Gravity/jumping continue to own vertical displacement. The solver can
        shorten blocked motion; root motion cannot push the body through walls.
        """
        if not isfinite(dt) or dt<=0 or dt>.25:raise Error("Invalid root-motion timestep")
        self.step(world,rotation.rotate(delta)*(1/dt),dt,jump)
