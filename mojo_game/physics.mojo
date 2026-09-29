"""Small-world 2D AABB physics: semi-implicit Euler and frictionless impulses.

All pairs are checked (O(n²)). Sensors report contacts without response.
Static bodies have inverse_mass=0. No continuous collision detection.
"""
from .math2d import Vec2, AABB
from .ecs import Entity, World, ComponentStore

struct Body2D(ImplicitlyCopyable, Movable):
    var position: Vec2
    var velocity: Vec2
    var half: Vec2
    var inverse_mass: Float64
    var restitution: Float64
    var sensor: Bool

    def __init__(out self, position: Vec2, half: Vec2, mass: Float64 = 1, restitution: Float64 = 0, sensor: Bool = False) raises:
        if half.x < 0 or half.y < 0 or mass < 0 or restitution < 0 or restitution > 1:
            raise Error("Invalid body dimensions, mass, or restitution")
        self.position = position
        self.velocity = Vec2(0, 0)
        self.half = half
        self.inverse_mass = 1/mass if mass > 0 else 0
        self.restitution = restitution
        self.sensor = sensor

    def bounds(self) -> AABB:
        return AABB(self.position, self.half)

@fieldwise_init
struct Contact(ImplicitlyCopyable, Movable):
    var a: Entity
    var b: Entity
    var normal: Vec2
    var depth: Float64

struct Physics2D:
    var gravity: Vec2
    var contacts: List[Contact]

    def __init__(out self, gravity: Vec2 = Vec2(0, 980)):
        self.gravity = gravity
        self.contacts = List[Contact]()

    def step(mut self, world: World, mut bodies: ComponentStore[Body2D], dt: Float64) raises:
        self.contacts.clear()
        if dt <= 0: return
        var entities = world.entities()
        for entity in entities:
            if not bodies.has(world, entity): continue
            var body = bodies.get(world, entity)
            if body.inverse_mass > 0:
                body.velocity = body.velocity+self.gravity*dt
                body.position = body.position+body.velocity*dt
                bodies.set(world, entity, body)
        for i in range(len(entities)):
            var a_id = entities[i]
            if not bodies.has(world, a_id): continue
            for j in range(i+1, len(entities)):
                var b_id = entities[j]
                if not bodies.has(world, b_id): continue
                var a = bodies.get(world, a_id)
                var b = bodies.get(world, b_id)
                if not a.bounds().overlaps(b.bounds()): continue
                var delta = b.position-a.position
                var px = a.half.x+b.half.x-abs(delta.x)
                var py = a.half.y+b.half.y-abs(delta.y)
                var normal = Vec2(0, 1.0 if delta.y >= 0 else -1.0)
                var depth = py
                if px < py:
                    normal = Vec2(1.0 if delta.x >= 0 else -1.0, 0)
                    depth = px
                self.contacts.append(Contact(a_id, b_id, normal, depth))
                var total = a.inverse_mass+b.inverse_mass
                if a.sensor or b.sensor or total == 0: continue
                a.position = a.position-normal*(depth*a.inverse_mass/total)
                b.position = b.position+normal*(depth*b.inverse_mass/total)
                var speed = (b.velocity-a.velocity).dot(normal)
                if speed < 0:
                    var impulse = -(1+min(a.restitution, b.restitution))*speed/total
                    a.velocity = a.velocity-normal*(impulse*a.inverse_mass)
                    b.velocity = b.velocity+normal*(impulse*b.inverse_mass)
                bodies.set(world, a_id, a)
                bodies.set(world, b_id, b)
