"""Generation-checked entity identities and typed sparse component storage.

Use one store per component type and World. Component access always validates
against the World, so destroyed/recycled entities cannot expose stale data.
"""
@fieldwise_init
struct Entity(ImplicitlyCopyable, Movable):
    var index: Int
    var generation: Int

struct World:
    var generations: List[Int]
    var alive: List[Bool]
    var free: List[Int]
    var count: Int

    def __init__(out self):
        self.generations = List[Int]()
        self.alive = List[Bool]()
        self.free = List[Int]()
        self.count = 0

    def create(mut self) -> Entity:
        var index = len(self.alive)
        if len(self.free) > 0:
            index = self.free.pop()
            self.alive[index] = True
        else:
            self.alive.append(True)
            self.generations.append(0)
        self.count += 1
        return Entity(index, self.generations[index])

    def valid(self, entity: Entity) -> Bool:
        return entity.index >= 0 and entity.index < len(self.alive) and self.alive[entity.index] and self.generations[entity.index] == entity.generation

    def destroy(mut self, entity: Entity) -> Bool:
        if not self.valid(entity): return False
        self.alive[entity.index] = False
        self.generations[entity.index] += 1
        self.free.append(entity.index)
        self.count -= 1
        return True

    def entities(self) -> List[Entity]:
        var result = List[Entity]()
        for i in range(len(self.alive)):
            if self.alive[i]: result.append(Entity(i, self.generations[i]))
        return result^

struct ComponentStore[T: Copyable & Deinitable]:
    var values: List[Optional[Self.T]]
    var generations: List[Int]

    def __init__(out self):
        self.values = List[Optional[Self.T]]()
        self.generations = List[Int]()

    def has(self, world: World, entity: Entity) -> Bool:
        return world.valid(entity) and entity.index < len(self.values) and self.generations[entity.index] == entity.generation and Bool(self.values[entity.index])

    def set(mut self, world: World, entity: Entity, var value: Self.T) raises:
        if not world.valid(entity): raise Error("Invalid entity")
        while len(self.values) <= entity.index:
            self.values.append(None)
            self.generations.append(-1)
        self.values[entity.index] = value^
        self.generations[entity.index] = entity.generation

    def get(self, world: World, entity: Entity) raises -> Self.T:
        if not self.has(world, entity): raise Error("Missing component or invalid entity")
        return self.values[entity.index].value().copy()

    def remove(mut self, world: World, entity: Entity) -> Bool:
        if not self.has(world, entity): return False
        self.values[entity.index] = None
        return True

    def collect(mut self, world: World):
        """Release components retained after their entity was destroyed."""
        for i in range(len(self.values)):
            if not world.valid(Entity(i, self.generations[i])):
                self.values[i] = None
