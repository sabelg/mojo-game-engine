"""Bounded visual feedback; never changes collision or gameplay state."""
from std.math import sin, cos, atan2, exp
from mojo_game import Vec3
from .game import Game, PLAYING

struct Particle(ImplicitlyCopyable, Movable):
    var position: Vec3
    var velocity: Vec3
    var color: Vec3
    var life: Float64
    var duration: Float64
    var size: Float64
    def __init__(out self,position: Vec3,velocity: Vec3,color: Vec3,life: Float64,size: Float64):
        self.position=position
        self.velocity=velocity
        self.color=color
        self.life=life
        self.duration=life
        self.size=size

struct Presentation:
    var particles: List[Particle]
    var was_grounded: Bool
    var last_velocity: Float64
    var last_health: Int
    var last_collected: Int
    var last_action: Float64
    var footstep: Float64
    var landing: Float64
    var pickup: Float64
    var impact: Float64
    var facing: Float64
    def __init__(out self):
        self.particles=List[Particle]()
        self.was_grounded=False
        self.last_velocity=0
        self.last_health=13
        self.last_collected=0
        self.last_action=0
        self.footstep=0
        self.landing=0
        self.pickup=0
        self.impact=0
        self.facing=0
    def reset(mut self,g: Game):
        self.particles.clear()
        self.was_grounded=g.grounded
        self.last_velocity=g.velocity.y
        self.last_health=g.health
        self.last_collected=g.collected
        self.last_action=g.action
        self.footstep=0
        self.landing=0
        self.pickup=0
        self.impact=0
        self.facing=g.facing
    def burst(mut self,p: Vec3,color: Vec3,count: Int,energy: Float64):
        for i in range(count):
            if len(self.particles)>=96:break
            var angle=Float64(i)*2.39996323
            var speed=energy*(0.4+Float64(i%5)*0.12)
            self.particles.append(Particle(p,Vec3(cos(angle)*speed,energy*(0.5+Float64(i%3)*0.2),sin(angle)*speed),color,0.3+Float64(i%5)*0.07,0.025+Float64(i%3)*0.012))
    def update(mut self,g: Game,dt: Float64):
        if g.mode!=PLAYING:return
        var delta=max(0.0,min(dt,0.1))
        self.landing=max(0.0,self.landing-delta*5)
        self.pickup=max(0.0,self.pickup-delta*2)
        self.impact=max(0.0,self.impact-delta*5)
        var angle=atan2(sin(g.facing-self.facing),cos(g.facing-self.facing))
        self.facing+=angle*(1-exp(-delta*18))
        var live=List[Particle]()
        for p in self.particles:
            var particle=p
            particle.life-=delta
            particle.velocity.y-=delta*5
            particle.position=particle.position+particle.velocity*delta
            if particle.life>0:live.append(particle)
        self.particles=live^
        if g.grounded and not self.was_grounded and self.last_velocity< -1:
            self.landing=1
            self.burst(g.position+Vec3(0,0.05,0),Vec3(0.75,0.65,0.39),12,0.7)
        if not g.grounded and self.was_grounded and g.velocity.y>1:
            self.burst(g.position+Vec3(0,0.04,0),Vec3(0.83,0.76,0.53),8,0.6)
        if g.collected>self.last_collected:
            self.pickup=1
            self.burst(g.position+Vec3(0,0.7,0),Vec3(1,0.65,0.08),18,1.8)
        if g.health<self.last_health:
            self.impact=1
            self.burst(g.position+Vec3(0,0.6,0),Vec3(1,0.28,0.08),12,1.6)
        if g.action>self.last_action+0.01 and g.action_kind=="whip":
            self.burst(g.position+Vec3(0,0.4,0),Vec3(0.95,0.78,0.27),10,1.6)
        self.footstep+=delta
        if g.grounded and g.velocity.x*g.velocity.x+g.velocity.z*g.velocity.z>1 and self.footstep>0.16:
            self.footstep=0
            self.burst(g.position+Vec3(0,0.02,0),Vec3(0.66,0.66,0.38),3,0.3)
        self.was_grounded=g.grounded
        self.last_velocity=g.velocity.y
        self.last_health=g.health
        self.last_collected=g.collected
        self.last_action=g.action

    def scale(self,g: Game) -> Vec3:
        var squash=sin(self.landing*3.14159265)*0.14
        var stretch=min(0.08,max(-0.04,g.velocity.y*0.012)) if not g.grounded else 0.0
        return Vec3(1+squash*0.5-stretch*0.3,1-squash+stretch,1+squash*0.5-stretch*0.3)
