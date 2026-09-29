"""Yo Frankie Vulkan port. Run from the repository root."""
from std.sys import argv
from std.math import sin,cos
from std.ffi import external_call
from mojo_game import Graphics3D, FixedClock, Vec3
from frankie.game import Game,Controls,TITLE,PLAYING,PAUSED,HELP,CREDITS,VICTORY
from frankie.render import Renderer
from frankie.save import Progress
from frankie.level import Entity

def test_key(scan: Int, pressed: Int) raises:
    if external_call["yf_test_key",Int32](Int32(scan),Int32(pressed))!=1:raise Error("SDL rejected test input")

def main() raises:
    var args=argv()
    var smoke=False
    var capture=False
    var tour=False
    var window_test=False
    var title_test=False
    var action_test=False
    var windowed=False
    var realistic=False
    var benchmark=False
    var benchmark_quick=False
    var width=1920
    var height=1080
    var explicit_resolution=False
    for arg in args:
        if arg=="--benchmark" or arg=="--benchmark-quick":
            benchmark=True
            benchmark_quick=arg=="--benchmark-quick"
            smoke=True
            realistic=True
        if arg=="--action-test":
            smoke=True
            action_test=True
            realistic=True
        if arg=="--realistic" or arg=="--polished":realistic=True
        if arg=="--windowed":windowed=True
        if arg=="--capture":
            smoke=True
            capture=True
        if arg=="--720p":
            width=1280
            height=720
            explicit_resolution=True
        if arg=="--1080p":
            width=1920
            height=1080
            explicit_resolution=True
        if arg=="--1440p":
            width=2560
            height=1440
            explicit_resolution=True
        if arg=="--4k":
            width=3840
            height=2160
            explicit_resolution=True
        if arg=="--smoke":smoke=True
        if arg=="--window-test":window_test=True
        if arg=="--title":
            smoke=True
            title_test=True
        if arg=="--tour":
            smoke=True
            tour=True
    if (smoke or window_test) and not benchmark and not explicit_resolution:
        width=1280
        height=800
    var d=Graphics3D("Yo Frankie | A Furry Vendetta | Vulkan",width,height,smoke,not smoke and not windowed)
    print("Yo Frankie Vulkan:",d.driver())
    var g=Game()
    try:g.progress=Progress.load("saves/yofrankie.save")
    except err:print("Save could not be read:",err)
    var load_started=external_call["SDL_GetPerformanceCounter",UInt64]()
    var timer_frequency=Float64(external_call["SDL_GetPerformanceFrequency",UInt64]())
    g.start(0 if smoke or window_test else min(g.progress.unlocked,len(g.entries)-1))
    if capture:
        for _ in range(60):g.step(Controls(),1.0/60)
    g.mode=PLAYING if (smoke and not title_test) or window_test else TITLE
    var test_pickup= -1
    if action_test:
        test_pickup=len(g.level.entities)
        g.level.entities.append(Entity("acorn","acorn_001",g.position+Vec3(0,30,0),0,Vec3(1,1,1)))
    var renderer=Renderer(d,"assets/yofrankie-realistic/" if realistic else "assets/yofrankie/")
    renderer.load(d,g)
    if benchmark:
        print("BENCH_LOAD",g.level.key,Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-load_started)*1000/timer_frequency)
        print("BENCH_RESOLUTION",d.width,d.height)
    var audio=external_call["yf_audio_open",Int32]() if not smoke else Int32(-1)
    if window_test and (audio<0 or external_call["yf_audio_loaded",Int32]()!=12):raise Error("Audio regression failed")
    if audio>=0:
        external_call["yf_audio_mute",NoneType](Int32(g.progress.muted))
        print("Audio enabled; loaded sounds:",external_call["yf_audio_loaded",Int32]())
    elif not smoke:
        print("Audio unavailable: check the default output device")
        g.message("AUDIO DEVICE UNAVAILABLE")
    var music=-1
    var clock=FixedClock()
    var frames=0
    var scene_frames=0
    var warmup=3 if benchmark_quick else 30
    var measured=6 if benchmark_quick else 180
    while d.running:
        var frame_started=external_call["SDL_GetPerformanceCounter",UInt64]()
        if benchmark:renderer.yaw=Float64(max(0,scene_frames-warmup))*6.283185307/Float64(measured)
        if window_test:
            # Allow compositor transitions to settle before checking applied state.
            external_call["SDL_Delay",NoneType](UInt32(50))
            if frames==10 and not windowed:test_key(68,1)
            if frames==11 and not windowed:test_key(68,0)
            if frames==5:test_key(26,1)
            if frames==20:test_key(44,1)
            if frames==21:test_key(44,0)
            if frames==30:d.resize(1024,640)
            if frames==40:test_key(26,0)
            if frames==45:test_key(41,1)
            if frames==46:test_key(41,0)
            if frames==50:test_key(40,1)
            if frames==51:test_key(40,0)
        d.poll(True,False)
        var input=d.input.copy()
        if window_test and not windowed and frames==5 and not d.is_fullscreen():raise Error("Fullscreen was not activated")
        if input.pressed(68):
            d.fullscreen(not d.is_fullscreen())
            d.input.clear_edges()
        if window_test and frames==15 and d.is_fullscreen():raise Error("F11 did not leave fullscreen")
        var initial_mode=g.mode
        var escape=input.pressed(41)
        var enter=input.pressed(40)
        if input.pressed(16):
            g.progress.muted=not g.progress.muted
            g.save_dirty=True
            external_call["yf_audio_mute",NoneType](Int32(g.progress.muted))
        if g.mode==PLAYING and (escape or input.focus_lost):g.mode=PAUSED
        elif g.mode==PAUSED:
            if escape or enter:g.mode=PLAYING
            elif input.pressed(21):
                g.start(g.scene_index)
                renderer.load(d,g)
            elif input.pressed(43):
                g.mode=TITLE
                renderer.menu=0
                renderer.selection=0
        elif g.mode==TITLE:
            var count=len(g.entries) if renderer.menu==1 else 5
            if input.pressed(81) or input.pressed(22):renderer.selection=(renderer.selection+1)%count
            if input.pressed(82) or input.pressed(26):renderer.selection=(renderer.selection+count-1)%count
            if escape:
                renderer.menu=0
                renderer.selection=0
            if input.mouse_presses & 1:
                var top=194 if renderer.menu==1 else 222
                var stride=27 if renderer.menu==1 else 51
                var ui_scale=max(0.5,min(Float64(d.width)/1280,Float64(d.height)/800))
                var mx=Int(Float64(input.mouse_x)/ui_scale)
                var my=Int(Float64(input.mouse_y)/ui_scale)
                var selected=(my-top)//stride
                if mx>=60 and mx<710 and my>=top and selected<count:
                    renderer.selection=selected
                    enter=True
            if enter:
                if renderer.menu==1:
                    g.start(renderer.selection)
                    renderer.load(d,g)
                    renderer.menu=0
                    renderer.selection=0
                elif renderer.selection==0:g.mode=PLAYING
                elif renderer.selection==1:
                    renderer.menu=1
                    renderer.selection=g.scene_index
                elif renderer.selection==2:g.mode=HELP
                elif renderer.selection==3:g.mode=CREDITS
                else:d.running=False
        elif escape or enter:
            g.mode=TITLE
            renderer.menu=0
            renderer.selection=0
        if window_test and frames==46 and g.mode!=PAUSED:raise Error("Escape did not pause the game")
        var dt=1.0/60 if smoke or window_test else max(0.001,input.dt)
        if g.mode==PLAYING:
            renderer.yaw+=Float64(input.axis(20,21))*dt*1.7
            renderer.distance=min(7.0,max(2.5,renderer.distance+Float64(input.axis(75,78))*dt*2))
            if input.mouse_buttons & 4:
                renderer.yaw-=Float64(input.mouse_dx)*0.006
                renderer.pitch=min(0.85,max(0.08,renderer.pitch+Float64(input.mouse_dy)*0.004))
        if action_test and frames==30:
            g.invincible=0
            g.level.entities[test_pickup].position=g.position+Vec3(0,0.3,0)
        if action_test and frames==35:
            g.invincible=0
            g.hurt(1)
        var steps=clock.advance(dt)
        for tick in range(steps):
            var x=Float64(input.axis(4,7)+input.axis(80,79))
            var z=Float64(input.axis(26,22)+input.axis(82,81))
            var control=Controls(x*cos(renderer.yaw)+z*sin(renderer.yaw),z*cos(renderer.yaw)-x*sin(renderer.yaw),tick==0 and input.pressed(44),input.down(44),tick==0 and input.pressed(8),tick==0 and input.pressed(9),tick==0 and input.pressed(6))
            if smoke:control=Controls()
            if action_test:control=Controls(x=0.2,z=-0.4,jump=(frames==5 or frames==15) and tick==0,held_jump=True,attack=frames==25 and tick==0)
            g.step(control,clock.step)
            if g.sound>=0 and audio>=0:external_call["yf_audio_play",NoneType](Int32(g.sound),Int32(0))
            if g.pending>=0:break
        # Menu edges are consumed even when the accumulator has no fixed step.
        if steps>0 or g.mode!=PLAYING or initial_mode!=PLAYING:d.input.clear_edges()
        if g.pending>=0:
            var pending=g.pending
            g.start(pending,False)
            renderer.load(d,g)

        var next_music=11 if g.mode==TITLE or g.mode==HELP or g.mode==CREDITS else (9 if g.level.blend=="level_underworld" else 10)
        if audio>=0 and next_music!=music:
            external_call["yf_audio_play",NoneType](Int32(next_music),Int32(1))
            music=next_music
        if g.save_dirty and not smoke and not window_test:
            try:g.progress.save("saves/yofrankie.save")
            except err:
                print("Cannot save progress:",err)
                g.message("PROGRESS COULD NOT BE SAVED")
            g.save_dirty=False
        renderer.frame(d,g,dt,clock.alpha())
        if action_test and frames==31 and (g.collected<1 or renderer.feedback.pickup<=0 or len(renderer.feedback.particles)==0):raise Error("Pickup feedback regression")
        if action_test and frames==36 and renderer.feedback.impact<=0:raise Error("Damage feedback regression")
        if not benchmark and (smoke or window_test) and (frames==59 or tour or capture):
            var prefix="build/yofrankie-realistic-" if realistic else "build/yofrankie-"
            var screenshot=prefix+"capture-"+String(d.width)+"x"+String(d.height)+".bmp" if capture else prefix+String(g.scene_index)+".bmp"
            if action_test:screenshot=prefix+"action.bmp"
            d.snapshot(screenshot)
            print("Scene",g.level.key,"triangles",d.triangles(),"position",g.position.x,g.position.y,g.position.z)
        d.present()
        if d.validation_errors()>0:raise Error("Vulkan validation failed")
        if benchmark:
            if scene_frames>=warmup:
                print("BENCH_FRAME",g.level.key,Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-frame_started)*1000/timer_frequency,d.triangles())
            scene_frames+=1
            if scene_frames>=warmup+measured:
                if g.scene_index+1>=len(g.entries):break
                load_started=external_call["SDL_GetPerformanceCounter",UInt64]()
                g.start(g.scene_index+1)
                renderer.load(d,g)
                print("BENCH_LOAD",g.level.key,Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-load_started)*1000/timer_frequency)
                scene_frames=0
            continue
        frames+=1
        if smoke or window_test:
            if tour:
                if g.scene_index+1>=len(g.entries):break
                g.start(g.scene_index+1)
                renderer.load(d,g)
            elif frames>=(1 if capture else 60):break
        if d.validation_errors()>0:raise Error("Vulkan validation failed")
    if window_test and (g.position-g.level.spawn).length()<0.5:raise Error("Keyboard movement was not received")
    if window_test and g.mode!=PLAYING:raise Error("Window/input regression failed")
    if window_test and windowed and (d.width!=1024 or d.height!=640):raise Error("Window resize regression failed")
    external_call["yf_audio_close",NoneType]()
    print("Yo Frankie closed; Vulkan validation errors:",d.validation_errors())
