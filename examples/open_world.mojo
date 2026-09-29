"""Open-world editor and integration demo. See docs/OPEN_WORLD.md for controls."""
from std.sys import argv
from std.math import sin, cos
from mojo_game import Graphics3D, Vec3, Mat4, Transform3D, Quaternion, Mesh, load_obj, Scene3D, SceneNode, Material, TerrainConfig, WorldStreamer, FlyCamera, SceneEditor, Frustum, Bounds3D, Physics3D, Body3D, FixedClock, Assets3D


def initial_scene(terrain: TerrainConfig) raises -> Scene3D:
    var scene = Scene3D()
    var ground = terrain.height(80,30)
    _ = scene.add(SceneNode("LANDMARK",Transform3D(Vec3(80,ground,30),scale=Vec3(2,2,2)),1,Material(Vec3(0.72,0.46,0.16),0.3,0.7)))
    for i in range(6):
        var angle = Float64(i)*6.283185307/6
        var x = 80+cos(angle)*18
        var z = 30+sin(angle)*18
        _ = scene.add(SceneNode("MONOLITH "+String(i+1),Transform3D(Vec3(x,terrain.height(x,z),z),scale=Vec3(1.2,1.2,1.2)),1,Material(Vec3(0.18,0.3,0.42),0.45,0.35)))
    _ = scene.add(SceneNode("BEACON",Transform3D(Vec3(80,ground+18,30),scale=Vec3(1.5,1.5,1.5)),2,Material(Vec3(0.1,0.8,0.9),0.3,0.25,1.5)))
    return scene^


def hud(device: Graphics3D, scene: Scene3D, editor: SceneEditor, camera: FlyCamera, streamer: WorldStreamer, dt: Float64) raises:
    var width = device.width
    var height = device.height
    device.rect(0,0,Float64(width),64,Vec3(0.035,0.05,0.065),0.96)
    device.rect(20,18,5,27,Vec3(0.18,0.86,0.7))
    device.text("ATLAS",38,20,Vec3(0.92,0.96,1),3)
    device.text("MOJO / OPEN WORLD",158,27,Vec3(0.4,0.6,0.65),2)
    device.text("EDIT WORLD",width-210,26,Vec3(0.3,0.9,0.72),2)
    var panel = max(0,width-292)
    device.rect(Float64(panel),78,280,Float64(max(100,height-136)),Vec3(0.035,0.05,0.065),0.94)
    device.text("SCENE OUTLINER",panel+18,98,Vec3(0.45,0.65,0.7))
    var row = 136
    for i in range(len(scene.nodes)):
        if not scene.valid(i) or row > height-330: continue
        if i == editor.selected: device.rect(Float64(panel+10),Float64(row-6),260,26,Vec3(0.08,0.3,0.27))
        device.text(scene.nodes[i].name,panel+20,row,Vec3(0.8,0.87,0.89),1)
        row += 29
    var top = max(row+20,height-302)
    device.text("INSPECTOR",panel+18,top,Vec3(0.45,0.65,0.7))
    if scene.valid(editor.selected):
        var node = scene.nodes[editor.selected].copy()
        device.text(node.name,panel+18,top+29,Vec3(0.9,0.95,1),1)
        var p = node.transform.position
        device.text("POS "+String(Int(p.x))+" / "+String(Int(p.y))+" / "+String(Int(p.z)),panel+18,top+54,scale=1)
    device.text("TAB SELECT   ARROWS MOVE",panel+18,top+89,scale=1)
    device.text("PGUP/DN HEIGHT  R ROTATE",panel+18,top+109,scale=1)
    device.text("B COPY X DELETE Z/Y UNDO",panel+18,top+129,scale=1)
    device.text("F5 SAVE  F9 LOAD",panel+18,top+149,scale=1)
    device.text("SPACE DROP PHYSICS BALL",panel+18,top+179,scale=1)
    device.text("T TRAVEL 1 BILLION UNITS",panel+18,top+199,scale=1)
    device.rect(0,Float64(height-40),Float64(width),40,Vec3(0.025,0.04,0.05),0.97)
    device.text("CHUNKS "+String(len(streamer.chunks))+"   DRAWS "+String(device.draws())+"   TRI "+String(device.triangles()),18,height-26,Vec3(0.48,0.78,0.68),1)
    device.text("WASD FLY  Q/E HEIGHT  RIGHT DRAG LOOK  SHIFT FAST",18,82,Vec3(0.85,0.92,0.96),1)
    device.text("WORLD X "+String(Int(camera.position.x))+" Z "+String(Int(camera.position.z)),18,105,Vec3(0.85,0.92,0.96),1)
    device.text(editor.status,panel+18,height-26,Vec3(0.5,0.86,0.72),1)
    _ = dt


def main() raises:
    var args = argv()
    var smoke = len(args) > 1 and args[1] == "--smoke"
    var device = Graphics3D("Atlas | Mojo Open World",1280,800,smoke)
    print("Vulkan renderer:",device.driver())
    var cube = Mesh.cube()
    var prop = load_obj("assets/obelisk.obj")
    var sphere = Mesh.sphere()
    var assets = Assets3D()
    _ = assets.add(device,"cube",cube)
    _ = assets.add(device,"obelisk",prop)
    _ = assets.add(device,"sphere",sphere)
    var terrain = TerrainConfig(radius=4,chunks_per_update=4)
    var streamer = WorldStreamer(terrain)
    var scene = initial_scene(terrain)
    var editor = SceneEditor()
    var camera = FlyCamera()
    camera.position.y = terrain.height(80,30)+40
    var clock = FixedClock()
    var physics = Physics3D()
    var frame = 0
    while device.running:
        device.poll()
        if not device.running: break
        var dt = device.input.dt
        if smoke: dt = 1.0/60
        camera.update(device.input,dt)
        editor.update(scene,device.input)
        if device.input.mouse_pressed(1):
            if device.input.mouse_x < device.width-292 and device.input.mouse_y > 64:
                editor.selected = assets.pick(scene,camera.position,camera.screen_ray(device.input.mouse_x,device.input.mouse_y,device.width,device.height))
            else:
                var row = 136
                for i in range(len(scene.nodes)):
                    if not scene.valid(i) or row > device.height-330: continue
                    if device.input.mouse_y >= row-6 and device.input.mouse_y < row+20: editor.selected = i
                    row += 29
        if device.input.pressed(9):
            editor.selected = assets.pick(scene,camera.position,camera.direction())
            editor.status = "RAY PICK"
        if device.input.pressed(44) and len(physics.bodies) < 128:
            var body = Body3D(camera.position+camera.direction()*4,radius=0.8,restitution=0.6)
            body.velocity = camera.direction()*15
            _ = physics.add(body)
        if device.input.pressed(23):
            camera.position.x += 1000000000
            camera.position.z += 1000000000
            camera.position.y = terrain.height(camera.position.x,camera.position.z)+40
            editor.status = "LARGE WORLD TRAVEL"
        if device.input.pressed(62):
            try:
                scene.save("assets/world.scene")
                editor.status = "SCENE SAVED"
            except err:
                editor.status = "SAVE FAILED"
                print(err)
        if device.input.pressed(66):
            try:
                var loaded = Scene3D.load("assets/world.scene")
                for node in loaded.nodes:
                    if node.mesh >= len(assets.handles) or node.material.texture != -1: raise Error("Unsupported scene asset")
                editor.checkpoint(scene)
                scene = loaded^
                editor.status = "SCENE LOADED"
            except err:
                editor.status = "LOAD FAILED"
                print(err)
        for _ in range(clock.advance(dt)): physics.step(clock.step,terrain)
        streamer.update(device,camera.position)
        var aspect = Float64(max(1,device.width))/Float64(max(1,device.height))
        var view_projection = Mat4.perspective(1.04719755,aspect,0.2,1200)*camera.view()
        var sun = Vec3(0.4,0.8,0.3).unit()
        var light = Mat4.orthographic(240,0.1,900)*Mat4.look_at(sun*420,Vec3(0,0,0))
        device.shadow_begin(light)
        streamer.draw(device,camera.position,True,light,True)
        assets.draw(device,scene,camera.position,light,True)
        for body in physics.bodies:
            device.shadow(assets.handles[2],Transform3D(body.position,scale=Vec3(body.radius,body.radius,body.radius)).matrix(),camera.position)
        device.begin(view_projection,sun,0.0018)
        streamer.draw(device,camera.position,False,view_projection,True)
        assets.draw(device,scene,camera.position,view_projection,False)
        for body in physics.bodies:
            device.draw(assets.handles[2],Transform3D(body.position,scale=Vec3(body.radius,body.radius,body.radius)).matrix(),Material(Vec3(0.8,0.2,0.06),0.2,0.55),camera.position)
        hud(device,scene,editor,camera,streamer,dt)
        if smoke and frame == 23:
            device.snapshot("build/open-world.bmp")
        device.present()
        frame += 1
        if smoke and frame == 24: break
    if smoke:
        if len(streamer.chunks) != 81: raise Error("Terrain did not become resident")
        print("Open-world smoke passed:",len(streamer.chunks),"resident chunks;",device.draws(),"draws;",device.triangles(),"triangles")
    streamer.clear(device)
    assets.close(device)
    device.close()
