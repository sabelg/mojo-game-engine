"""3D sphere dynamics, ray queries and terrain contact.

Semi-implicit integration with bounded substeps. Sphere pairs use a sweep on X
for broad phase and frictionless impulses. No rotational dynamics.
"""
from .math3d import Vec3
from .world3d import TerrainConfig

struct Body3D(ImplicitlyCopyable, Movable):
    var position: Vec3
    var velocity: Vec3
    var radius: Float64
    var inverse_mass: Float64
    var restitution: Float64
    var active: Bool
    var sensor: Bool

    def __init__(out self, position: Vec3, radius: Float64 = 0.5, mass: Float64 = 1, restitution: Float64 = 0.2, sensor: Bool = False) raises:
        if radius <= 0 or mass < 0 or restitution < 0 or restitution > 1: raise Error("Invalid sphere body")
        self.position = position
        self.velocity = Vec3(0,0,0)
        self.radius = radius
        self.inverse_mass = 1/mass if mass > 0 else 0
        self.restitution = restitution
        self.active = True
        self.sensor = sensor

@fieldwise_init
struct Hit3D(ImplicitlyCopyable, Movable):
    var body: Int
    var distance: Float64
    var position: Vec3
    var normal: Vec3

@fieldwise_init
struct Contact3D(ImplicitlyCopyable, Movable):
    var a: Int
    var b: Int
    var normal: Vec3
    var penetration: Float64

struct Physics3D:
    var bodies: List[Body3D]
    var contacts: List[Contact3D]
    var gravity: Vec3
    var pair_tests: Int

    def __init__(out self, gravity: Vec3 = Vec3(0,-9.81,0)):
        self.bodies = List[Body3D]()
        self.contacts = List[Contact3D]()
        self.gravity = gravity
        self.pair_tests = 0

    def add(mut self, body: Body3D) -> Int:
        self.bodies.append(body)
        return len(self.bodies)-1

    def step(mut self, dt: Float64, terrain: TerrainConfig) raises:
        if dt <= 0 or dt > 0.25: raise Error("Physics dt must be in (0, 0.25]")
        var steps = max(1,Int(dt/0.008)+1)
        var h = dt/Float64(steps)
        self.contacts.clear()
        self.pair_tests = 0
        for substep in range(steps):
            for i in range(len(self.bodies)):
                var body = self.bodies[i]
                if not body.active or body.inverse_mass == 0: continue
                body.velocity = body.velocity+self.gravity*h
                body.position = body.position+body.velocity*h
                var ground = terrain.height(body.position.x,body.position.z)+body.radius
                if body.position.y < ground and not body.sensor:
                    var normal = terrain.normal(body.position.x,body.position.z)
                    body.position.y = ground
                    var speed = body.velocity.dot(normal)
                    if speed < 0: body.velocity = body.velocity-normal*((1+body.restitution)*speed)
                self.bodies[i] = body
            var order = List[Int]()
            for i in range(len(self.bodies)):
                if self.bodies[i].active: order.append(i)
            # Insertion sort suits coherent small active physics islands.
            for i in range(1,len(order)):
                var j = i
                while j > 0 and self.bodies[order[j]].position.x-self.bodies[order[j]].radius < self.bodies[order[j-1]].position.x-self.bodies[order[j-1]].radius:
                    var swap = order[j]
                    order[j] = order[j-1]
                    order[j-1] = swap
                    j -= 1
            var pairs = List[Int]()
            for oi in range(len(order)):
                var i = order[oi]
                for oj in range(oi+1,len(order)):
                    var j = order[oj]
                    if self.bodies[j].position.x-self.bodies[j].radius > self.bodies[i].position.x+self.bodies[i].radius: break
                    pairs.append(i)
                    pairs.append(j)
            # Build candidates before impulses change the sorted body positions.
            for pair in range(0,len(pairs),2):
                var i = pairs[pair]
                var j = pairs[pair+1]
                var a = self.bodies[i]
                var b = self.bodies[j]
                self.pair_tests += 1
                var delta = b.position-a.position
                var distance = delta.length()
                var depth = a.radius+b.radius-distance
                if depth < 0: continue
                var normal = Vec3(1,0,0)
                if distance > 1e-9: normal = delta*(1/distance)
                if substep == steps-1: self.contacts.append(Contact3D(i,j,normal,depth))
                var total = a.inverse_mass+b.inverse_mass
                if total == 0 or a.sensor or b.sensor: continue
                a.position = a.position-normal*(depth*a.inverse_mass/total)
                b.position = b.position+normal*(depth*b.inverse_mass/total)
                var speed = (b.velocity-a.velocity).dot(normal)
                if speed < 0:
                    var impulse = -(1+min(a.restitution,b.restitution))*speed/total
                    a.velocity = a.velocity-normal*(impulse*a.inverse_mass)
                    b.velocity = b.velocity+normal*(impulse*b.inverse_mass)
                self.bodies[i] = a
                self.bodies[j] = b

    def raycast(self, origin: Vec3, direction: Vec3, maximum: Float64 = 10000) -> Optional[Hit3D]:
        from std.math import sqrt
        var d = direction.unit()
        if d.length() < 0.5 or maximum < 0: return None
        var closest = maximum
        var hit: Optional[Hit3D] = None
        for i in range(len(self.bodies)):
            var body = self.bodies[i]
            if not body.active: continue
            var offset = origin-body.position
            var b = offset.dot(d)
            var c = offset.dot(offset)-body.radius*body.radius
            var discriminant = b*b-c
            if discriminant < 0: continue
            var distance = -b-sqrt(discriminant)
            if distance < 0: distance = -b+sqrt(discriminant)
            if distance < 0 or distance > closest: continue
            closest = distance
            var point = origin+d*distance
            hit = Hit3D(i,distance,point,(point-body.position).unit())
        return hit
