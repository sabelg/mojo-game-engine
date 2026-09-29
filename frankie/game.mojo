"""GPL-2.0-or-later. Gameplay port referencing original frankie_scripts.
Original: YoFrankie! (c) 2008 Blender Foundation. See third_party/yofrankie.
"""
from std.math import sin, cos, atan2
from mojo_game import Vec3
from .level import Level, Trigger, read_text
from .save import Progress
comptime TITLE=0
comptime PLAYING=1
comptime PAUSED=2
comptime VICTORY=3
comptime HELP=4
comptime CREDITS=5

struct Controls(ImplicitlyCopyable, Movable):
    var x: Float64
    var z: Float64
    var jump: Bool
    var held_jump: Bool
    var attack: Bool
    var throw_item: Bool
    var carry: Bool
    def __init__(out self,x: Float64=0,z: Float64=0,jump: Bool=False,held_jump: Bool=False,attack: Bool=False,throw_item: Bool=False,carry: Bool=False):
        self.x=x
        self.z=z
        self.jump=jump
        self.held_jump=held_jump
        self.attack=attack
        self.throw_item=throw_item
        self.carry=carry

struct Projectile(ImplicitlyCopyable, Movable):
    var position: Vec3
    var velocity: Vec3
    var life: Float64
    def __init__(out self,p: Vec3,v: Vec3):
        self.position=p
        self.velocity=v
        self.life=3

struct Game(Copyable, Movable):
    var level: Level
    var entries: List[String]
    var progress: Progress
    var scene_index: Int
    var mode: Int
    var position: Vec3
    var previous: Vec3
    var velocity: Vec3
    var facing: Float64
    var grounded: Bool
    var jumps: Int
    var coyote: Float64
    var buffer: Float64
    var invincible: Float64
    var action: Float64
    var action_kind: String
    var health: Int
    var acorns: Int
    var bones: Int
    var collected: Int
    var boosted: Float64
    var carrying: Int
    var time: Float64
    var sound: Int
    var pending: Int
    var destination: String
    var portal_cooldown: Float64
    var projectiles: List[Projectile]
    var notice: String
    var notice_time: Float64
    var save_dirty: Bool
    def __init__(out self) raises:
        self.level=Level()
        self.entries=List[String]()
        for line in read_text("assets/yofrankie/levels.tsv").split("\n"):
            if line.byte_length()>0:self.entries.append(String(line))
        self.progress=Progress()
        self.scene_index=0
        self.mode=TITLE
        self.position=Vec3(0,0,0)
        self.previous=self.position
        self.velocity=Vec3(0,0,0)
        self.facing=0
        self.grounded=False
        self.jumps=0
        self.coyote=0
        self.buffer=0
        self.invincible=0
        self.action=0
        self.action_kind="idle"
        self.health=13
        self.acorns=0
        self.bones=0
        self.collected=0
        self.boosted=0
        self.carrying=-1
        self.time=0
        self.sound=-1
        self.pending=-1
        self.destination=""
        self.portal_cooldown=2
        self.projectiles=List[Projectile]()
        self.notice=""
        self.notice_time=0
        self.save_dirty=False
    def message(mut self,var text: String):
        self.notice=text^
        self.notice_time=4
    def start(mut self,index: Int,reset: Bool=True) raises:
        if index<0 or index>=len(self.entries):raise Error("Unknown original scene")
        var entry=self.entries[index].copy()
        self.level.load(entry)
        self.scene_index=index
        self.position=self.level.spawn
        if self.destination.byte_length()>0 and self.destination in self.level.markers:self.position=self.level.markers[self.destination]
        self.destination=""
        self.previous=self.position
        self.velocity=Vec3(0,0,0)
        self.health=13 if reset else max(1,self.health)
        if reset:
            self.acorns=0
            self.bones=0
            self.collected=0
        self.grounded=False
        self.jumps=0
        self.carrying=-1
        self.projectiles.clear()
        self.pending=-1
        self.portal_cooldown=2
        self.invincible=1
        self.mode=PLAYING
        self.progress.unlocked=index
        self.save_dirty=True
        self.message("EXPLORE - FOLLOW THE ORIGINAL PORTALS")
        # Original selector scripts place portals in a circle of radius seven.
        if self.level.blend=="level_selector" or self.level.blend=="level_selector_other":
            var mini=self.level.blend=="level_selector_other"
            var targets=List[Int]()
            for i in range(len(self.entries)):
                var f=self.entries[i].split("\t")
                var b=String(f[1])
                if (mini and b.startswith("minilevel_")) or (not mini and (b=="level_1_home" or b=="level_lighthouse" or b=="level_nut" or b=="level_underworld" or b=="level_selector_other")):
                    if i==1:continue
                    targets.append(i)
            for n in range(len(targets)):
                var angle=Float64(n)*6.283185307/Float64(len(targets))
                var center=Vec3(0,0,0)
                if "dyn_warp_placer" in self.level.markers:center=self.level.markers["dyn_warp_placer"]
                var p=center+Vec3(cos(angle)*7,0,sin(angle)*7)
                p.y=self.level.floor_at(p,500)
                var fields=self.entries[targets[n]].split("\t")
                self.level.triggers.append(Trigger("portal",p-Vec3(0.5,0,0.5),p+Vec3(0.5,1.5,0.5),String(fields[1]),String(fields[2]),""))
    def hurt(mut self,amount: Int,respawn: Bool=False):
        if self.invincible>0 and not respawn:return
        self.health=max(0,self.health-amount)
        self.invincible=1.2
        self.sound=4
        self.action_kind="hurt"
        self.action=0.45
        if self.health==0 or respawn:
            self.position=self.level.spawn
            self.previous=self.position
            self.velocity=Vec3(0,0,0)
            self.carrying=-1
            self.health=13 if self.health==0 else self.health
            self.invincible=2
            self.sound=5
            self.message("BACK AT THE START - TRY AGAIN")
    def step(mut self,c: Controls,dt: Float64) raises:
        if self.mode!=PLAYING:return
        self.previous=self.position
        self.time+=dt
        self.sound=-1
        self.action=max(0.0,self.action-dt)
        self.invincible=max(0.0,self.invincible-dt)
        self.portal_cooldown=max(0.0,self.portal_cooldown-dt)
        self.notice_time=max(0.0,self.notice_time-dt)
        self.boosted=max(0.0,self.boosted-dt)
        self.coyote=0.1 if self.grounded else max(0.0,self.coyote-dt)
        self.buffer=0.12 if c.jump else max(0.0,self.buffer-dt)
        var direction=Vec3(c.x,0,c.z)
        if direction.length()>1:direction=direction.unit()
        var speed: Float64=6 if self.boosted>0 else 3
        var gliding=not self.grounded and self.jumps>=2 and c.held_jump and self.velocity.y<0
        if gliding:speed=7
        var blend=min(1.0,dt*(20.0 if self.grounded else 5.0))
        self.velocity.x+=(direction.x*speed-self.velocity.x)*blend
        self.velocity.z+=(direction.z*speed-self.velocity.z)*blend
        if direction.length()>0.05:self.facing=atan2(-direction.x,-direction.z)
        if self.buffer>0 and (self.coyote>0 or self.jumps<2):
            self.velocity.y=5.8 if self.jumps==0 else 5.2
            self.jumps=1 if self.coyote>0 else self.jumps+1
            self.grounded=False
            self.coyote=0
            self.buffer=0
            self.sound=0
        self.velocity.y-=15*dt
        if gliding:self.velocity.y=max(self.velocity.y,-1.2)
        var next_pos=self.position+self.velocity*dt
        next_pos=self.level.walls(next_pos)
        var ground=self.level.floor_at(next_pos,max(self.position.y+0.18,next_pos.y+0.03))
        self.grounded=False
        if self.velocity.y<=0 and next_pos.y<=ground+0.03 and self.position.y>=ground-0.2:
            next_pos.y=ground+0.005
            self.velocity.y=0
            self.grounded=True
            self.jumps=0
        self.position=next_pos
        if self.position.y<self.level.spawn.y-60:self.hurt(3,True)
        if c.carry and self.carrying<0:
            for i in range(len(self.level.entities)):
                if self.level.entities[i].active and self.level.entities[i].kind=="sheep" and (self.level.entities[i].position-self.position).length()<1.1:
                    self.carrying=i
                    self.message("SHEEP CAUGHT - THROW WITH F")
                    break
        if c.throw_item and self.action<=0:
            var forward=Vec3(-sin(self.facing),0,-cos(self.facing))
            if self.carrying>=0:
                self.level.entities[self.carrying].velocity=forward*7+Vec3(0,4,0)
                self.level.entities[self.carrying].stun=2
                self.carrying=-1
                self.action=0.4
                self.action_kind="throw"
                self.sound=6
            elif self.acorns+self.bones>0:
                if self.bones>0:self.bones-=1
                else:self.acorns-=1
                self.projectiles.append(Projectile(self.position+Vec3(0,0.6,0)+forward*0.45,forward*10+Vec3(0,2,0)))
                self.action=0.3
                self.action_kind="throw"
                self.sound=6
        if c.attack and self.action<=0:
            self.action=0.35
            self.action_kind="whip"
            self.sound=3
            for i in range(len(self.level.entities)):
                var p=self.level.entities[i].position
                if self.level.entities[i].active and (p-self.position).length()<1.2 and (self.level.entities[i].kind=="rat" or self.level.entities[i].kind=="sheep" or self.level.entities[i].kind=="ram"):
                    self.level.entities[i].health-=1
                    self.level.entities[i].stun=1.5
                    self.level.entities[i].velocity=(p-self.position).unit()*4+Vec3(0,3,0)
        for i in range(len(self.level.entities)):
            if not self.level.entities[i].active:continue
            var kind=self.level.entities[i].kind.copy()
            var p=self.level.entities[i].position
            if kind=="spring":
                var delta=self.position-p
                if delta.x*delta.x+delta.z*delta.z<0.45 and delta.y>= -0.15 and delta.y<0.75 and self.velocity.y<=0:
                    self.velocity.y=10
                    self.jumps=1
                    self.grounded=False
                    self.sound=0
                continue
            if kind=="acorn" or kind=="bone" or kind=="apricot" or kind=="boost":
                if (p-self.position-Vec3(0,0.3,0)).length()<0.65 and self.carrying<0 and self.invincible<=0:
                    self.level.entities[i].active=False
                    self.collected+=1
                    if kind=="acorn":self.acorns+=1
                    elif kind=="bone":self.bones+=1
                    elif kind=="apricot":self.health=min(13,self.health+2)
                    else:self.boosted=10
                    self.sound=2 if kind=="apricot" else 1
                    self.progress.best_score=max(self.progress.best_score,self.collected)
                    self.save_dirty=True
                continue
            if self.level.entities[i].health<=0:
                self.level.entities[i].active=False
                continue
            if i==self.carrying:
                self.level.entities[i].position=self.position+Vec3(0,1,0)
                continue
            var stun=max(0.0,self.level.entities[i].stun-dt)
            self.level.entities[i].stun=stun
            var movement=self.level.entities[i].velocity
            if stun>0:
                movement.y-=15*dt
            else:
                var delta=self.position-p
                delta.y=0
                var distance=delta.length()
                if kind=="rat" and distance<5:movement=delta.unit()*1.7
                elif kind=="ram" and distance<6:movement=delta.unit()*2.5
                elif kind=="sheep" and distance<2:movement=delta.unit()*(-1.5)
                else:
                    var home=self.level.entities[i].home
                    var target=home+Vec3(sin(self.time*0.4+Float64(i))*1.5,0,cos(self.time*0.4+Float64(i))*1.5)
                    target.y=p.y
                    movement=(target-p).unit()*0.55
            var moved=p+movement*dt
            var floor=self.level.floor_at(moved,p.y+0.25)
            if floor>p.y-0.8 and moved.y<=floor+0.1:
                moved.y=floor
                movement.y=0
            elif stun<=0:
                moved=p
                movement=Vec3(0,0,0)
            self.level.entities[i].position=moved
            self.level.entities[i].velocity=movement
            if movement.x*movement.x+movement.z*movement.z>0.01:self.level.entities[i].angle=atan2(-movement.x,-movement.z)
            if stun<=0 and (moved-self.position).length()<0.55 and (kind=="ram" or kind=="rat"):self.hurt(1)
        for i in range(len(self.projectiles)):
            if self.projectiles[i].life<=0:continue
            self.projectiles[i].life-=dt
            self.projectiles[i].velocity.y-=9*dt
            self.projectiles[i].position=self.projectiles[i].position+self.projectiles[i].velocity*dt
            var p=self.projectiles[i].position
            if p.y<self.level.floor_at(p,p.y+0.1):self.projectiles[i].life=0
            for j in range(len(self.level.entities)):
                if self.level.entities[j].active and (self.level.entities[j].kind=="rat" or self.level.entities[j].kind=="ram" or self.level.entities[j].kind=="sheep") and (self.level.entities[j].position+Vec3(0,0.3,0)-p).length()<0.6:
                    self.level.entities[j].health-=2
                    self.level.entities[j].stun=1
                    self.projectiles[i].life=0
                    break
        if self.level.dangerous(self.position):self.hurt(3,True)
        var live=List[Projectile]()
        for shot in self.projectiles:
            if shot.life>0:live.append(shot)
        self.projectiles=live^
        for i in range(len(self.level.triggers)):
            if not self.level.triggers[i].contains(self.position,0.15):continue
            if self.level.triggers[i].kind=="hazard":continue
            if self.portal_cooldown>0:continue
            var blend_name=self.level.triggers[i].blend.copy()
            var scene_name=self.level.triggers[i].scene.copy()
            var target=self.level.triggers[i].target.copy()
            if blend_name=="ending":
                self.mode=VICTORY
                self.progress.completions+=1
                self.save_dirty=True
                self.sound=7
                break
            if blend_name.byte_length()==0 and scene_name.byte_length()==0:
                if target in self.level.markers:
                    self.position=self.level.markers[target]
                    self.velocity=Vec3(0,0,0)
                    self.portal_cooldown=2
                continue
            var found=False
            for j in range(len(self.entries)):
                var f=self.entries[j].split("\t")
                if (blend_name.byte_length()==0 and f[1]==self.level.blend or f[1]==blend_name) and (scene_name.byte_length()==0 or f[2]==scene_name):
                    self.pending=j
                    self.destination=target.copy()
                    found=True
                    break
            if not found:
                self.message("ORIGINAL PORTAL DESTINATION IS MISSING")
                self.portal_cooldown=3
    def animation(self) -> String:
        if self.action>0:return self.action_kind.copy()
        if self.carrying>=0:return "carry"
        if not self.grounded:
            if self.velocity.y<0 and self.jumps>=2 and self.velocity.y>= -1.3:return "glide"
            if self.velocity.y<0:return "fall"
            return "double" if self.jumps>=2 else "jump"
        if abs(self.velocity.x)+abs(self.velocity.z)>0.3:return "run"
        return "idle"
