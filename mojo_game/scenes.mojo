"""Deferred scene-ID stack. Commit once after updating to avoid mid-step changes.

Games dispatch IDs to their own scene state. A push suspends the old top;
popping reveals it without discarding its game-owned state.
"""
struct SceneStack:
    var stack: List[Int]
    var operation: Int
    var target: Int

    def __init__(out self, initial: Int = 0):
        self.stack = List[Int]()
        self.stack.append(initial)
        self.operation = 0
        self.target = initial

    def current(self) -> Int:
        return self.stack[len(self.stack)-1]

    def push(mut self, scene: Int):
        self.operation = 1
        self.target = scene

    def replace(mut self, scene: Int):
        self.operation = 2
        self.target = scene

    def pop(mut self):
        self.operation = 3

    def commit(mut self) -> Bool:
        var changed = self.operation != 0
        if self.operation == 1: self.stack.append(self.target)
        elif self.operation == 2: self.stack[len(self.stack)-1] = self.target
        elif self.operation == 3:
            if len(self.stack) > 1: _ = self.stack.pop()
            else: changed = False
        self.operation = 0
        return changed
