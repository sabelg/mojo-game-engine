"""Collect the gold squares. WASD/arrows move, R restarts, P pauses."""
from std.sys import argv
from mojo_game import Engine, Game, Input, Window, Color, World, Entity, ComponentStore, Vec2, Body2D, Physics2D, SynthAudio, SceneStack

struct Collector(Game):
    var world: World
    var bodies: ComponentStore[Body2D]
    var physics: Physics2D
    var player: Entity
    var audio: SynthAudio
    var scenes: SceneStack
    var score: Int
    var automated: Bool
    var ticks: Int

    def __init__(out self, automated: Bool = False) raises:
        self.world = World()
        self.bodies = ComponentStore[Body2D]()
        self.physics = Physics2D(Vec2(0, 0))
        self.audio = SynthAudio(not automated)
        self.scenes = SceneStack()
        self.score = 0
        self.automated = automated
        self.ticks = 0
        self.player = self.world.create()
        self.bodies.set(self.world, self.player, Body2D(Vec2(100, 380), Vec2(16, 16)))
        for i in range(8):
            var orb = self.world.create()
            self.bodies.set(self.world, orb, Body2D(Vec2(200+Float64(i)*100, 380), Vec2(12, 12), mass=0, sensor=True))
        self.wall(Vec2(550, 95), Vec2(540, 5))
        self.wall(Vec2(550, 690), Vec2(540, 5))
        self.wall(Vec2(15, 395), Vec2(5, 300))
        self.wall(Vec2(1085, 395), Vec2(5, 300))

    def wall(mut self, position: Vec2, half: Vec2) raises:
        var entity = self.world.create()
        self.bodies.set(self.world, entity, Body2D(position, half, mass=0))

    def update(mut self, input: Input, dt: Float64) raises:
        if input.pressed(21):
            var entities = self.world.entities()
            for entity in entities:
                if self.bodies.get(self.world, entity).sensor:
                    _ = self.world.destroy(entity)
            self.bodies.collect(self.world)
            for i in range(8):
                var orb = self.world.create()
                self.bodies.set(self.world, orb, Body2D(Vec2(200+Float64(i)*100, 380), Vec2(12, 12), mass=0, sensor=True))
            var reset = self.bodies.get(self.world, self.player)
            reset.position = Vec2(100, 380)
            self.bodies.set(self.world, self.player, reset)
            self.score = 0
            self.scenes.replace(0)
            _ = self.scenes.commit()
        if self.scenes.current() == 1: return
        var body = self.bodies.get(self.world, self.player)
        var direction = Vec2(input.axis(4, 7)+input.axis(80, 79), input.axis(26, 22)+input.axis(82, 81))
        if self.automated: direction = Vec2(1, 0)
        body.velocity = direction.unit()*300
        self.bodies.set(self.world, self.player, body)
        self.physics.step(self.world, self.bodies, dt)
        for contact in self.physics.contacts:
            var target = contact.b
            if contact.b.index == self.player.index: target = contact.a
            elif contact.a.index != self.player.index: continue
            if not self.bodies.has(self.world, target): continue
            if self.bodies.get(self.world, target).sensor:
                _ = self.world.destroy(target)
                self.score += 1
                self.audio.trigger_laser()
        self.bodies.collect(self.world)
        self.audio.update(0, False, True, input.pressed(16))
        self.ticks += 1
        if self.score == 8:
            self.scenes.replace(1)
            _ = self.scenes.commit()

    def draw(self, mut window: Window, alpha: Float64) raises:
        _ = alpha
        window.text("ORBIT COLLECTOR", 550, 25, Color(120, 220, 255), 4, True)
        window.text("WASD / ARROWS   P PAUSE   R RESTART   ESC QUIT", 550, 65, Color(170, 180, 200), 2, True)
        var entities = self.world.entities()
        for entity in entities:
            var body = self.bodies.get(self.world, entity)
            var color = Color(40, 70, 100)
            if body.sensor: color = Color(255, 200, 50)
            elif entity.index == self.player.index: color = Color(80, 230, 220)
            window.box(Int(body.position.x-body.half.x), Int(body.position.y-body.half.y), Int(body.half.x*2), Int(body.half.y*2), color)
        window.text("SCORE "+String(self.score)+" / 8", 550, 720, Color(255, 220, 120), 3, True)
        if self.scenes.current() == 1:
            window.text("ALL COLLECTED!  R TO RESTART", 550, 280, Color(255, 220, 120), 3, True)
        if window.paused:
            window.text("PAUSED - P TO RESUME", 550, 330, Color(255, 255, 255), 3, True)

def main() raises:
    var args = argv()
    var smoke = len(args) > 1 and args[1] == "--smoke"
    var game = Collector(smoke)
    if smoke:
        var input = Input()
        for _ in range(240): game.update(input, 1.0/60)
        if game.score != 8: raise Error("Automated collector failed")
        var window = Window(offscreen=True, fullscreen=False)
        window.begin()
        game.draw(window, 0)
        window.present()
        window.close()
        print("Collector smoke passed: 8 collectibles, victory scene, rendered frame")
    else:
        var engine = Engine("Orbit Collector")
        engine.run(game)
