from std.testing import assert_equal,assert_true,assert_false,assert_raises
from mojo_game import Vec3
from frankie.level import Level,Triangle,Entity,Trigger
from frankie.game import Game,Controls,PLAYING,PAUSED,VICTORY
from frankie.save import Progress
from frankie.presentation import Presentation

def arena() raises -> Game:
    var g=Game()
    g.mode=PLAYING
    g.level.spawn=Vec3(0,0,0)
    g.level.triangles.append(Triangle(Vec3(-20,0,-20),Vec3(20,0,20),Vec3(20,0,-20)))
    g.level.triangles.append(Triangle(Vec3(-20,0,-20),Vec3(-20,0,20),Vec3(20,0,20)))
    for x in range(-5,6):
        for z in range(-5,6):g.level.cells[x*100000+z]=[0,1]
    return g^

def main() raises:
    var feedback_game=arena()
    feedback_game.velocity.y= -4
    var feedback=Presentation()
    feedback.reset(feedback_game)
    feedback_game.grounded=True
    feedback_game.velocity.y=0
    feedback.update(feedback_game,1.0/60)
    assert_equal(feedback.landing,1.0)
    assert_equal(len(feedback.particles),12)
    feedback_game.collected=1
    feedback.update(feedback_game,1.0/60)
    assert_equal(feedback.pickup,1.0)
    for _ in range(10):feedback.burst(Vec3(0,0,0),Vec3(1,1,1),30,1)
    assert_equal(len(feedback.particles),96)
    feedback_game.mode=PAUSED
    var life=feedback.particles[0].life
    feedback.update(feedback_game,0.1)
    assert_equal(feedback.particles[0].life,life)
    feedback_game.mode=PLAYING
    for _ in range(60):feedback.update(feedback_game,1.0/60)
    assert_equal(len(feedback.particles),0)
    feedback.reset(feedback_game)
    assert_equal(feedback.landing,0.0)
    var g=arena()
    g.level.entities.append(Entity("acorn","acorn_001",Vec3(0,0,-2),0,Vec3(1,1,1)))
    for _ in range(60):g.step(Controls(z=-1),1.0/60)
    assert_true(g.position.z < -2.5)
    assert_true(g.grounded)
    assert_equal(g.acorns,1)
    assert_equal(g.collected,1)
    var position=g.position
    g.mode=PAUSED
    g.step(Controls(x=1,jump=True),1.0/60)
    assert_equal(g.position.x,position.x)
    assert_equal(g.position.y,position.y)
    g.mode=PLAYING
    g.step(Controls(jump=True),1.0/60)
    assert_true(g.velocity.y>5)
    assert_equal(g.jumps,1)
    for _ in range(18):g.step(Controls(),1.0/60)
    var first_height=g.position.y
    g.step(Controls(jump=True),1.0/60)
    assert_equal(g.jumps,2)
    for _ in range(30):g.step(Controls(held_jump=True),1.0/60)
    assert_true(g.position.y>first_height)
    assert_true(g.velocity.y>= -1.21)
    for _ in range(180):g.step(Controls(),1.0/60)
    assert_true(g.grounded)
    g.health=5
    var p=g.position
    g.level.entities.append(Entity("apricot","apricot_001",p,0,Vec3(1,1,1)))
    g.step(Controls(),1.0/60)
    assert_equal(g.health,7)
    g.hurt(1)
    g.hurt(1)
    assert_equal(g.health,6)
    g.step(Controls(throw_item=True),1.0/60)
    # Hurt animation prevents throwing until it finishes.
    for _ in range(40):g.step(Controls(),1.0/60)
    g.step(Controls(throw_item=True),1.0/60)
    assert_equal(g.acorns,0)
    assert_equal(len(g.projectiles),1)
    var sheep=Entity("sheep","sheep_cute",g.position+Vec3(0.4,0,0),0,Vec3(1,1,1))
    g.level.entities.append(sheep^)
    g.step(Controls(carry=True),1.0/60)
    assert_true(g.carrying>=0)
    for _ in range(30):g.step(Controls(),1.0/60)
    g.step(Controls(throw_item=True),1.0/60)
    assert_equal(g.carrying,-1)
    assert_true(g.level.entities[len(g.level.entities)-1].stun>0)
    # Swept movement must stop at a wall, and hazards use surface distance.
    var wall=arena()
    wall.level.triangles.append(Triangle(Vec3(-3,0,-1),Vec3(3,3,-1),Vec3(3,0,-1)))
    wall.level.triangles.append(Triangle(Vec3(-3,0,-1),Vec3(-3,3,-1),Vec3(3,3,-1)))
    for x in range(-1,1):
        wall.level.cells[x*100000-1].append(2)
        wall.level.cells[x*100000-1].append(3)
    for _ in range(90):wall.step(Controls(z=-1),1.0/60)
    assert_true(wall.position.z> -0.8)
    wall.level.hazards.append(Triangle(Vec3(-2,0,-2),Vec3(2,0,-2),Vec3(2,0,2)))
    assert_false(wall.level.dangerous(Vec3(0,3,0)))
    assert_true(wall.level.dangerous(Vec3(1,0,0)))
    var spring=arena()
    spring.level.entities.append(Entity("spring","springbox_001",Vec3(0,0,0),0,Vec3(1,1,1)))
    spring.step(Controls(),1.0/60)
    assert_equal(spring.velocity.y,10.0)
    assert_false(spring.grounded)
    var saved=Progress()
    saved.unlocked=11
    saved.best_score=23
    saved.muted=True
    saved.save("build/frankie-test.save")
    var loaded=Progress.load("build/frankie-test.save")
    assert_equal(loaded.unlocked,11)
    assert_equal(loaded.best_score,23)
    assert_true(loaded.muted)
    with assert_raises():_ = Progress.decode("YO_FRANKIE_VK_1\n-1\n0\n0\n0\n")
    with assert_raises():_ = Progress.decode("YO_FRANKIE_VK_1\n0\n0\n0\n5\n")
    # Real scene integration: settle at every original spawn, no non-finite/fall-through.
    var world=Game()
    assert_equal(len(world.entries),12)
    for scene in range(len(world.entries)):
        world.start(scene)
        for _ in range(120):world.step(Controls(),1.0/60)
        assert_true(world.position.y>world.level.spawn.y-15)
        assert_equal(world.health,13)
        assert_true(world.grounded)
        print("Spawn simulation:",world.level.key,world.position.y,"grounded",world.grounded)
    world.start(0)
    var portal=-1
    for i in range(len(world.level.triggers)):
        if world.level.triggers[i].scene=="lavaland":portal=i
    assert_true(portal>=0)
    world.position=(world.level.triggers[portal].low+world.level.triggers[portal].high)*0.5
    world.portal_cooldown=0
    world.step(Controls(),1.0/60)
    assert_equal(world.pending,1)
    var next=world.pending
    world.start(next,False)
    assert_equal(world.level.name,"lavaland")
    assert_true(world.destination.byte_length()==0)
    world.start(0)
    for t in world.level.triggers:
        if t.blend=="ending":world.position=(t.low+t.high)*0.5
    world.portal_cooldown=0
    world.step(Controls(),1.0/60)
    assert_equal(world.mode,VICTORY)
    print("Yo Frankie gameplay, save and original-scene tests passed")
