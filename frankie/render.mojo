"""Vulkan rendering of converted original meshes and baked animation poses."""
from std.ffi import external_call
from std.math import sin,cos,exp,tan
from mojo_game import Graphics3D, Vec3, Mat4, Transform3D, Quaternion, Material, Mesh
from .level import read_text,vector,Entity
from .game import Game, TITLE, PLAYING, PAUSED, VICTORY, HELP, CREDITS
from .presentation import Presentation

struct Part(ImplicitlyCopyable, Movable):
    var mesh: Int
    var texture: Int
    var color: Vec3
    var roughness: Float64
    var metallic: Float64
    var emission: Float64
    var casts_shadow: Bool
    def __init__(out self,mesh: Int,texture: Int,color: Vec3,roughness: Float64,metallic: Float64,emission: Float64,casts_shadow: Bool):
        self.mesh=mesh
        self.texture=texture
        self.color=color
        self.roughness=roughness
        self.metallic=metallic
        self.emission=emission
        self.casts_shadow=casts_shadow

struct Renderer:
    var asset_root: String
    var polished: Bool
    var feedback: Presentation
    var meshes: Dict[String,List[Part]]
    var textures: Dict[String,Int]
    var materials: Dict[String,String]
    var yaw: Float64
    var pitch: Float64
    var distance: Float64
    var eye: Vec3
    var sphere: Int
    var selection: Int
    var menu: Int
    var animation_key: String
    var animation_time: Float64
    def __init__(out self,device: Graphics3D,asset_root: String="assets/yofrankie/") raises:
        self.asset_root=asset_root
        self.polished=asset_root!="assets/yofrankie/"
        self.feedback=Presentation()
        if self.polished:device.font(device.texture("assets/ui/frankie-font.bmp"))
        self.meshes=Dict[String,List[Part]]()
        self.textures=Dict[String,Int]()
        self.materials=Dict[String,String]()
        for line in read_text(self.asset_root+"materials.tsv").split("\n"):
            var fields=String(line).split("\t")
            if len(fields)==5 or len(fields)==6:self.materials[String(fields[0])]=String(line)
        self.yaw=0
        self.pitch=0.29 if self.polished else 0.4145
        self.distance=3.8 if self.polished else 5.0
        self.eye=Vec3(0,0,0)
        var sphere=Mesh.sphere(12,8)
        self.sphere=device.upload(sphere)
        self.selection=0
        self.menu=0
        self.animation_key=""
        self.animation_time=0
    def parts(mut self,device: Graphics3D,key: String) raises:
        if key in self.meshes:return
        var parts=List[Part]()
        for line in read_text(self.asset_root+key+".parts").split("\n"):
            var f=String(line).split("\t")
            if len(f)<2:continue
            var path=self.asset_root+String(f[0])
            var handle=external_call["yf_mesh",Int32](device.handle.value(),path.as_c_string_span())
            if handle<0:raise Error("Failed to load mesh: "+path)
            var name=String(f[1])
            var texture=-1
            var roughness: Float64=0.86
            var metallic: Float64=0
            var emission: Float64=0
            if name!="-":
                if name not in self.textures:self.textures[name]=device.texture(self.asset_root+name)
                texture=self.textures[name]
                if name in self.materials:
                    var config=self.materials[name].split("\t")
                    roughness=Float64(String(config[2]))
                    metallic=Float64(String(config[3]))
                    emission=Float64(String(config[4]))
                    var normal=String(config[1])
                    if normal!="-":
                        var normal_key="normal:"+normal
                        if normal_key not in self.textures:self.textures[normal_key]=device.normal_texture(self.asset_root+normal)
                        # Each albedo uses a consistent normal map across all scene batches.
                        var bound_key="bound:"+name
                        if bound_key not in self.textures:
                            device.normal_map(texture,self.textures[normal_key])
                            self.textures[bound_key]=texture
                    if len(config)==6 and String(config[5])!="-":
                        var orm=String(config[5])
                        var orm_key="orm:"+orm
                        if orm_key not in self.textures:self.textures[orm_key]=device.normal_texture(self.asset_root+orm)
                        var orm_bound="orm-bound:"+name
                        if orm_bound not in self.textures:
                            device.orm_map(texture,self.textures[orm_key])
                            self.textures[orm_bound]=texture
            var color=vector(String(f[2]))
            var casts_shadow=not (name.startswith("cloud") or name.startswith("sky") or name.startswith("fx_") or name.startswith("water"))
            if texture<0 and abs(color.x-0.08)<0.001 and abs(color.z-0.42)<0.001:
                roughness=0.16
                casts_shadow=False
            parts.append(Part(Int(handle),texture,color,roughness,metallic,emission,casts_shadow))
        self.meshes[key]=parts^
    def load(mut self,device: Graphics3D,game: Game) raises:
        # Scene changes release all mesh handles; textures are shared and bounded.
        for entry in self.meshes.items():
            for part in entry.value:device.release(part.mesh)
        self.meshes.clear()
        self.parts(device,game.level.key)
        for entity in game.level.entities:
            self.parts(device,entity.prefab)
            if entity.prefab=="ram" or entity.prefab=="rat" or entity.prefab=="sheep_cute":
                for action in ["idle","run","hurt"]:
                    for frame in range(8):self.parts(device,entity.prefab+"_"+action+"_"+String(frame))
        for action in ["idle","run","jump","double","glide","fall","kick","whip","carry","throw","hurt","ledge"]:
            for i in range(12):self.parts(device,"frankie_"+action+"_"+String(i))
        self.feedback.reset(game)
        self.eye=game.position+Vec3(sin(self.yaw)*self.distance,(0.65+tan(self.pitch)*self.distance) if self.polished else 2.85,cos(self.yaw)*self.distance)
    def enemy_key(self,e: Entity,time: Float64) -> String:
        if e.prefab!="ram" and e.prefab!="rat" and e.prefab!="sheep_cute":return e.prefab.copy()
        var action=String("idle")
        if e.stun>0:action="hurt"
        elif e.velocity.length()>0.2:action="run"
        var rate: Float64=1 if action=="idle" else 15
        return e.prefab+"_"+action+"_"+String(Int((time+abs(e.home.x))*rate)%8)
    def object(self,device: Graphics3D,key: String,model: Mat4,origin: Vec3,shadow: Bool=False,next_key: String="",blend: Float64=0) raises:
        if key not in self.meshes:return
        for i in range(len(self.meshes[key])):
            var p=self.meshes[key][i]
            if shadow and not p.casts_shadow:continue
            if blend>0 and next_key in self.meshes and i<len(self.meshes[next_key]):
                var next_part=self.meshes[next_key][i]
                if next_part.texture==p.texture and device.can_morph(p.mesh,next_part.mesh):
                    device.draw_morph(p.mesh,next_part.mesh,blend,model,Material(p.color,p.roughness,p.metallic,p.emission,p.texture),origin,shadow)
                    continue
            if shadow:
                if p.casts_shadow:device.shadow_material(p.mesh,model,p.texture,origin)
            else:device.draw(p.mesh,model,Material(p.color,p.roughness,p.metallic,p.emission,p.texture),origin)

    def enemy(self,device: Graphics3D,e: Entity,time: Float64,model: Mat4,origin: Vec3,shadow: Bool=False) raises:
        var key=self.enemy_key(e,time)
        if e.prefab!="ram" and e.prefab!="rat" and e.prefab!="sheep_cute":
            self.object(device,key,model,origin,shadow)
            return
        var rate: Float64=15 if e.stun>0 or e.velocity.length()>0.2 else 1
        var phase=(time+abs(e.home.x))*rate
        self.object(device,key,model,origin,shadow,self.enemy_key(e,time+1/rate),phase-Float64(Int(phase)))

    def frame(mut self,device: Graphics3D,game: Game,dt: Float64,alpha: Float64=1) raises:
        if self.polished:self.feedback.update(game,dt)
        var position=game.position
        if game.mode==PLAYING and (game.position-game.previous).length()<1:
            position=game.previous+(game.position-game.previous)*min(1.0,max(0.0,alpha))
        var focus=position+Vec3(0,0.65,0)
        if self.polished:focus=focus+Vec3(game.velocity.x,0,game.velocity.z)*0.08
        var desired=focus+Vec3(sin(self.yaw)*self.distance,tan(self.pitch)*self.distance,cos(self.yaw)*self.distance)
        self.eye=self.eye+(desired-self.eye)*(1-exp(-max(0.0,dt)*10))
        self.eye=game.level.camera(focus,self.eye)
        var origin=self.eye
        if self.polished:origin=origin+Vec3(sin(game.time*83),cos(game.time*97),0)*(self.feedback.impact*0.025)
        var view=Mat4.look_at(Vec3(0,0,0),focus-origin)
        var proj=Mat4.perspective(0.9,Float64(device.width)/Float64(device.height),0.08,350)
        var center=focus-origin
        var light=Mat4.orthographic(28,1,140)*Mat4.look_at(center+Vec3(24,55,30),center)
        device.shadow_begin(light)
        var identity=Mat4()
        self.object(device,game.level.key,identity,origin,True)
        var clip=game.animation()
        if clip!=self.animation_key:
            self.animation_key=clip.copy()
            self.animation_time=0
        if game.mode==PLAYING:self.animation_time+=dt
        var duration: Float64=8.96 if clip=="idle" else 0.633
        var phase=self.animation_time/duration*12
        var pose=Int(phase)%12
        var blend=phase-Float64(Int(phase))
        if clip=="glide":pose=6
        if clip=="glide":blend=0
        var animation="frankie_"+clip+"_"+String(pose)
        var next_animation="frankie_"+clip+"_"+String((pose+1)%12)
        var player_scale=self.feedback.scale(game)*1.25 if self.polished else Vec3(1,1,1)
        var player=Transform3D(position+Vec3(0,0.27*player_scale.y+0.01,0),Quaternion.axis_angle(Vec3(0,1,0),self.feedback.facing if self.polished else game.facing),player_scale).matrix()
        self.object(device,animation,player,origin,True,next_animation,blend)
        for e in game.level.entities:
            if e.active and (e.position-game.position).length()<45 and (e.kind=="ram" or e.kind=="rat" or e.kind=="sheep"):
                self.enemy(device,e,game.time,Transform3D(e.position+Vec3(0,0.3,0),Quaternion.axis_angle(Vec3(0,1,0),e.angle),e.scale).matrix(),origin,True)
        device.begin(proj*view,Vec3(24,55,30),0.006 if self.polished else 0.0025)
        if self.polished:
            if game.level.key=="level_underworld__Game":
                device.lighting(Vec3(0.34,0.48,0.8),Vec3(0.16,0.12,0.25),Vec3(2.7,1.9,1.4),Vec3(0.16,0.23,0.4))
            elif game.level.name=="lavaland" or game.level.blend=="minilevel_lava_Falls":
                device.lighting(Vec3(0.6,0.43,0.6),Vec3(0.32,0.13,0.065),Vec3(3.6,2.5,1.6),Vec3(0.55,0.24,0.16))
            else:
                device.lighting(Vec3(0.48,0.62,0.81),Vec3(0.19,0.25,0.13),Vec3(3.5,3.1,2.5),Vec3(0.36,0.67,0.84))
        self.object(device,game.level.key,identity,origin)
        for e in game.level.entities:
            if not e.active or (e.position-game.position).length()>100:continue
            var position=e.position
            if e.kind=="ram" or e.kind=="rat" or e.kind=="sheep":position.y+=0.3
            var angle=e.angle
            if e.kind=="acorn" or e.kind=="bone" or e.kind=="apricot" or e.kind=="boost":
                angle+=game.time
                position.y+=sin(game.time*3+position.x)*0.06
            self.enemy(device,e,game.time,Transform3D(position,Quaternion.axis_angle(Vec3(0,1,0),angle),e.scale).matrix(),origin)
        if game.invincible<=0 or Int(game.time*12)%2==0:self.object(device,animation,player,origin,False,next_animation,blend)
        if self.polished:
            for p in self.feedback.particles:
                var radius=p.size*min(1.0,p.life/p.duration*3)
                device.draw(self.sphere,Transform3D(p.position,scale=Vec3(radius,radius,radius)).matrix(),Material(p.color,0.75,emission=0.12),origin)
        for p in game.projectiles:
            if p.life>0:device.draw(self.sphere,Transform3D(p.position,scale=Vec3(0.08,0.08,0.08)).matrix(),Material(Vec3(0.6,0.3,0.09)),origin)
        if game.level.blend.startswith("level_selector"):
            for t in game.level.triggers:
                if t.kind=="portal":device.draw(self.sphere,Transform3D((t.low+t.high)*0.5,scale=Vec3(0.35,0.8,0.35)).matrix(),Material(Vec3(0.2,0.8,0.55),emission=0.8),origin)
        self.hud(device,game)
    def hud(self,d: Graphics3D,g: Game) raises:
        var scale=max(0.5,min(Float64(d.width)/1280,Float64(d.height)/800))
        d.overlay_scale(scale)
        var w=Int(Float64(d.width)/scale)
        var h=Int(Float64(d.height)/scale)
        var cream=Vec3(1,0.94,0.77)
        var gold=Vec3(0.95,0.69,0.24)
        var dark=Vec3(0.04,0.07,0.055)
        if g.mode==PLAYING and self.polished:
            var paper=Vec3(0.98,0.97,0.87)
            var ink=Vec3(0.08,0.19,0.16)
            var green=Vec3(0.18,0.62,0.32)
            d.pill(30,33,300,68,ink)
            d.pill(28,28,300,68,paper)
            d.circle(63,62,24,Vec3(0.94,0.61,0.14))
            d.text("F",54,48,ink,3)
            d.text("FRANKIE",99,42,ink,1)
            for i in range(13):
                d.circle(Float64(105+i*16),72,5.8,green if i<g.health else Vec3(0.78,0.79,0.68))
            d.pill(Float64(w-270),33,240,68,ink)
            d.pill(Float64(w-272),28,240,68,paper)
            d.text("ACORNS",w-248,42,ink,1)
            d.text(String(g.acorns),w-246,61,Vec3(0.78,0.38,0.025),3)
            d.rect(Float64(w-151),43,1,39,Vec3(0.78,0.79,0.68))
            d.text("BONES",w-127,42,ink,1)
            d.text(String(g.bones),w-125,61,ink,3)
            var bounce=sin(self.feedback.pickup*3.14159265)*5
            d.pill(Float64(w//2-106),32-bounce,212,46,paper)
            d.circle(Float64(w//2-78),55-bounce,12,Vec3(0.98,0.7,0.12))
            d.text("FOUND "+String(g.collected),w//2-55,45-Int(bounce),ink,2)
            var names: List[String]=["HOME ISLAND","LAVA HOLLOW","LIGHTHOUSE COAST","THE GREAT NUT","ISLAND CROSSROADS","HIDDEN TRAILS","UNDERWORLD","MEADOW ARENA","LAVA FALLS","RATPACK RIDGE","WOODLAND TRAIL","THE ARENA"]
            d.pill(28,Float64(h-110),282,48,ink)
            d.text(names[g.scene_index],49,h-96,paper,2)
            if g.time<12:
                d.pill(28,Float64(h-52),Float64(w-56),32,paper)
                d.text("WASD Move   SPACE Jump / Glide   E Tail whip   F Throw   C Carry   ESC Pause",46,h-43,ink,1)
            if g.notice_time>0 and g.time>1.5:
                d.pill(Float64(w//2-300),112,600,36,ink)
                d.text(g.notice,w//2-280,123,paper,1)
            if g.boosted>0:
                d.pill(28,110,220,34,Vec3(0.98,0.7,0.12))
                d.text("SPEED BOOST "+String(Int(g.boosted)),48,120,ink,1)
            return
        if g.mode==PLAYING:
            d.rect(20,20,310,72,dark,0.85)
            d.text("FRANKIE",34,32,gold,2)
            for i in range(13):d.rect(Float64(34+i*21),57,17,13,Vec3(0.9,0.25,0.14) if i<g.health else Vec3(0.19,0.21,0.17))
            d.rect(Float64(w-246),20,226,72,dark,0.85)
            d.text("ACORNS "+String(g.acorns)+"  BONES "+String(g.bones),w-230,34,cream,1)
            d.text("FOUND "+String(g.collected),w-230,62,gold,2)
            d.rect(20,Float64(h-48),Float64(w-40),28,dark,0.8)
            d.text("WASD MOVE   SPACE JUMP / GLIDE   E TAIL WHIP   F THROW   C CARRY   ESC PAUSE",34,h-39,cream,1)
            if g.notice_time>0:d.text(g.notice,34,110,cream,1)
            if g.boosted>0:d.text("SPEED BOOST "+String(Int(g.boosted)),34,135,gold,2)
            return
        d.rect(0,0,Float64(w),Float64(h),dark,0.64)
        d.rect(38,38,Float64(min(w-76,730)),Float64(h-76),dark,0.91)
        d.rect(38,38,5,Float64(h-76),gold)
        d.text("YO FRANKIE",68,68,cream,5)
        d.text("A FURRY VENDETTA / ISLAND ADVENTURE" if self.polished else "A FURRY VENDETTA / VULKAN PORT",70,119,gold,1)
        if g.mode==TITLE and self.menu==0:
            d.text("RETURN TO THE ORIGINAL ISLANDS",70,170,cream,2)
            var options: List[String]=["PLAY / CONTINUE","ORIGINAL SCENES","CONTROLS","CREDITS","QUIT"]
            for i in range(len(options)):
                if self.selection==i:d.rect(60,Float64(222+i*51),440,38,Vec3(0.22,0.3,0.15))
                d.text(options[i],78,234+i*51,gold if self.selection==i else cream,2)
            d.text("ARROWS SELECT   ENTER CONFIRM",70,h-118,cream,1)
        elif g.mode==TITLE:
            d.text("ORIGINAL SCENES",70,164,gold,2)
            for i in range(len(g.entries)):
                var f=g.entries[i].split("\t")
                if self.selection==i:d.rect(60,Float64(194+i*27),650,24,Vec3(0.22,0.3,0.15))
                d.text(String(i+1)+"  "+String(f[1]).upper()+" / "+String(f[2]).upper(),76,201+i*27,cream,1)
            d.text("ENTER PLAY   ESC BACK",70,h-104,gold,1)
        elif g.mode==PAUSED:
            d.text("PAUSED",70,182,gold,3)
            d.text("ESC / ENTER   RESUME",70,256,cream,2)
            d.text("R             RESTART SCENE",70,304,cream,2)
            d.text("TAB           MAIN MENU",70,352,cream,2)
            d.text("M AUDIO / F11 FULLSCREEN",70,400,cream,2)
        elif g.mode==HELP:
            var lines: List[String]=["WASD / ARROWS    MOVE","SPACE           JUMP / DOUBLE JUMP","HOLD SPACE      GLIDE AFTER DOUBLE JUMP","E               TAIL WHIP","F               THROW AMMO / CARRIED SHEEP","C               PICK UP A NEARBY SHEEP","Q / R           ORBIT CAMERA","RIGHT DRAG      ORBIT / TILT CAMERA","PAGE UP / DOWN  CAMERA DISTANCE","ESC             PAUSE","APRICOTS HEAL. ACORNS AND BONES ARE AMMO.","FIND THE ORIGINAL PORTALS TO TRAVEL."]
            for i in range(len(lines)):d.text(lines[i],70,185+i*29,cream,1)
            d.text("ESC / ENTER BACK",70,h-106,gold,1)
        elif g.mode==CREDITS:
            var lines: List[String]=["YOFRANKIE 2008 BLENDER FOUNDATION","WWW.BLENDER.ORG / APRICOT.BLENDER.ORG","ORIGINAL ART, LEVELS AND AUDIO: CC BY 3.0","ORIGINAL GAMEPLAY SCRIPTS: GPL 2 OR LATER","CAMPBELL BARTON / CHRISTOPHER PLUSH","PABLO VAZQUEZ / MORAES JUNIOR","CLAIRE FITCH / THE APRICOT TEAM","MOJO GAMEPLAY AND VULKAN RENDERER PORT","SEE docs/YO_FRANKIE.md FOR PORT STATUS"]
            for i in range(len(lines)):d.text(lines[i],70,195+i*31,cream,1)
            d.text("ESC / ENTER BACK",70,h-106,gold,1)
        else:
            d.text("YOU MADE IT",70,195,gold,4)
            d.text("THE ORIGINAL ISLAND END PORTAL REACHED",70,263,cream,1)
            d.text("COLLECTED "+String(g.collected),70,311,cream,2)
            d.text("ENTER TO RETURN TO THE MENU",70,381,gold,1)
        d.text("YOFRANKIE 2008 BLENDER FOUNDATION / CC BY 3.0",70,h-74,Vec3(0.55,0.65,0.5),1)
