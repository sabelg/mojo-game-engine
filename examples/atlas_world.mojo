"""Atlas partition editor. Asset browser, axis gizmos, drag placement and delta undo."""
from std.sys import argv
from std.ffi import external_call
from std.math import isfinite
from mojo_game.durableio import exists,read_bounded,atomic_write
from mojo_game import Graphics3D,Vec3,Vec2,Mat4,Transform3D,Quaternion,Mesh,SceneNode,Material,TerrainConfig,WorldStreamer,WorldPartition,WorldEditor,FlyCamera,Assets3D,CharacterController3D,CollisionWorld3D,CollisionStreamer3D,Bounds3D,StreamScheduler,Project3D,ProjectOperation,Scene3D
from mojo_game import DirectionalShadows3D,Environment3D,TransformPreview3D
from std.math import exp
from std.collections import Dict

def screen(matrix: Mat4,p: Vec3,width: Int,height: Int) -> Optional[Vec2]:
    var w=matrix.data[3]*p.x+matrix.data[7]*p.y+matrix.data[11]*p.z+matrix.data[15]
    if w<=0.0001:return None
    var xy=matrix.point(p)
    return Vec2((xy.x/w+1)*Float64(width)*0.5,(1-xy.y/w)*Float64(height)*0.5)
def axis_line(device: Graphics3D,a: Vec2,b: Vec2,color: Vec3) raises:
    var steps=max(1,Int((b-a).length()/3))
    for i in range(steps+1):
        var p=a+(b-a)*(Float64(i)/Float64(steps))
        device.rect(p.x-1,p.y-1,3,3,color)
def ground_point(camera: FlyCamera,direction: Vec3,terrain: TerrainConfig) -> Vec3:
    var previous=camera.position
    for i in range(1,501):
        var current=camera.position+direction*Float64(i)
        if current.y<=terrain.height(current.x,current.z):
            var low=previous
            var high=current
            for _ in range(12):
                var middle=(low+high)*0.5
                if middle.y>terrain.height(middle.x,middle.z):low=middle
                else:high=middle
            return high
        previous=current
    return camera.position+direction*25

def property_text(node: SceneNode,kind: Int) -> String:
    var transform=node.transform
    if kind==0:return String(transform.position.x)+","+String(transform.position.y)+","+String(transform.position.z)
    if kind==1:return String(Float32(transform.scale.x))+","+String(Float32(transform.scale.y))+","+String(Float32(transform.scale.z))
    if kind==2:return String(Float32(transform.rotation.x))+","+String(Float32(transform.rotation.y))+","+String(Float32(transform.rotation.z))+","+String(Float32(transform.rotation.w))
    var material=node.material
    return String(Float32(material.color.x))+","+String(Float32(material.color.y))+","+String(Float32(material.color.z))+","+String(Float32(material.roughness))+","+String(Float32(material.metallic))+","+String(Float32(material.emission))

def main() raises:
    var args=argv()
    var smoke=False
    var play_only=False
    var smoke_play=False
    var smoke_usd_export=False
    var usd_export_started=False
    var usd_export_done=False
    var usd_export_destination=String()
    var shadow_quality=4
    var hdr=True
    var project=String("build/atlas-world-project")
    var manifest=String()
    var sdk=String(".")
    for i in range(1,len(args)):
        if args[i]=="--smoke":smoke=True
        elif args[i]=="--smoke-usd-export":
            smoke=True
            smoke_usd_export=True
        elif args[i]=="--legacy-lighting":hdr=False
        elif args[i]=="--play-only":play_only=True
        elif args[i]=="--smoke-play":
            smoke=True
            smoke_play=True
        elif args[i]=="--project" and i+1<len(args):project=String(args[i+1])
        elif args[i]=="--sdk" and i+1<len(args):sdk=String(args[i+1])
        elif args[i]=="--shadow-cascades" and i+1<len(args):shadow_quality=Int(String(args[i+1]))
        elif args[i]=="--assets" and i+1<len(args):manifest=String(args[i+1])
    if shadow_quality!=0 and shadow_quality!=2 and shadow_quality!=4:raise Error("--shadow-cascades must be 0, 2 or 4")
    var shadows=DirectionalShadows3D(count=2 if shadow_quality==2 else 4,distance=256)
    _=external_call["mkdir",Int32](project.as_c_string_span(),Int(493))
    var settings=Project3D()
    if exists(project+"/atlas.project"):settings=Project3D.load(project)
    else:settings.save(project)
    var operation=ProjectOperation()
    var operation_kind=0
    var play_destination=String()
    var operation_report=project+"/.atlas-operation.txt"
    var text_mode=0
    var property_kind=0
    var property_value=String()
    var search=String()
    var import_source=String()
    var import_id=String("content")
    var import_stage=0
    var dock_right=False
    if exists(project+"/.atlas-editor.layout"):dock_right=read_bounded(project+"/.atlas-editor.layout",64)=="RIGHT\n"
    var scheduler=StreamScheduler(workers=4)
    var world=WorldPartition(project,cell_size=settings.cell_size,radius=1,budget=4,asynchronous=True,scheduler=scheduler.copy())
    world.prepare()
    var editor=WorldEditor()
    var device=Graphics3D("Atlas | World editor",1280,800,smoke)
    device.hdr(hdr)
    device.environment(Environment3D.hemisphere(Vec3(.22,.29,.36),Vec3(.08,.09,.12)),hdr)
    var assets=Assets3D()
    _=assets.add(device,"atlas/cube",Mesh.cube())
    _=assets.add(device,"atlas/sphere",Mesh.sphere())
    for path in settings.manifests:assets.load_manifest(device,project+"/"+path)
    if manifest.byte_length()>0:assets.load_manifest(device,manifest)
    var terrain=TerrainConfig(seed=settings.seed,radius=3,resolution=16,chunks_per_update=4)
    terrain.layer=world.terrain.copy()
    var streamer=WorldStreamer(terrain,asynchronous=True,scheduler=scheduler.copy(),transition_seconds=.2)
    var ground=Optional[TerrainConfig](terrain.copy())
    var camera=FlyCamera(Vec3(80,terrain.height(80,30)+30,90))
    var collision=CollisionWorld3D()
    var collision_stream=CollisionStreamer3D(asynchronous=True,scheduler=scheduler.copy())
    var character=CharacterController3D(Vec3(80,terrain.height(80,30),30))
    var walk=play_only
    var terrain_mode=0
    var brush_radius: Float64=8
    var brush_color=Vec3(.42,.23,.11)
    var transform_mode=0
    var local_mode=False
    var snap: Float64=0
    var prefab=Scene3D()
    if exists(project+"/prefab.scene"):prefab=Scene3D.load(project+"/prefab.scene")
    var hierarchy_offset=0
    var browser_offset=0
    var drag_asset=-1
    var drag_axis=-1
    var drag=TransformPreview3D()
    var drag_amount: Float64=0
    var drag_direction=Vec3(1,0,0)
    var drag_rotation_axis=Vec3(1,0,0)
    var initialized=False
    var play_seen=False
    var frame=0
    var directions: List[Vec3]=[Vec3(1,0,0),Vec3(0,1,0),Vec3(0,0,1)]
    var colors: List[Vec3]=[Vec3(1,.2,.15),Vec3(.2,1,.35),Vec3(.3,.55,1)]
    print("Atlas editor:",device.driver())
    while device.running:
        device.poll(quit_on_escape=text_mode==0)
        if not device.running:break
        if smoke_usd_export and initialized and not usd_export_started:device.input.presses[69]=True
        if smoke_play and frame==5:device.input.presses[63]=True
        if smoke_play and operation_kind==4 and exists(play_destination+"/.atlas-play-frame"):
            play_seen=True
            device.input.presses[63]=True
        for code in [29,28,27,5,66,61,64,63,30,31,32,15,10,79,80,75,78,81,82,21,46,45,24,25,11,19]:
            if device.input.pressed(code):
                drag_axis=-1
                drag=TransformPreview3D()
        if device.input.focus_lost:
            drag_axis=-1
            drag_asset=-1
        if operation_kind==4 and device.input.pressed(63):
            operation.close()
            device.input.presses[63]=False
            var command: List[String]=["python3",sdk+"/scripts/atlas-project.py","cleanup-play","--project",project.copy(),"--destination",play_destination.copy(),"--report",operation_report.copy()]
            operation.start(command^)
            operation_kind=5
            editor.status="STOPPING ISOLATED PLAY"
        if operation.pid>0:
            var completed_kind=operation_kind
            if operation.poll():
                if completed_kind==4:
                    var command: List[String]=["python3",sdk+"/scripts/atlas-project.py","cleanup-play","--project",project.copy(),"--destination",play_destination.copy(),"--report",operation_report.copy()]
                    operation.start(command^)
                    operation_kind=5
                    editor.status="PLAY ENDED; REMOVING SIMULATION COPY"
                elif operation.exit_code==0 and completed_kind==3:
                    var command: List[String]=["bash",play_destination+"/run.sh"]
                    if smoke:command.append("--smoke")
                    operation.start(command^)
                    operation_kind=4
                    editor.status="PLAYING AN ISOLATED WORLD COPY; F6 STOP"
                else:
                    operation_kind=0
                    if completed_kind==7:
                        usd_export_done=operation.exit_code==0 and exists(usd_export_destination+"/scene.usda")
                        if smoke_usd_export and not usd_export_done:raise Error("USD editor export failed; see "+operation_report)
                    if completed_kind==6:editor.status="USD AUTHORING EXIT "+String(operation.exit_code)+"; EXPORTS IN "+project+"/usd"
                    elif exists(operation_report):editor.status=read_bounded(operation_report,8192)
                    else:editor.status="PROJECT OPERATION EXIT "+String(operation.exit_code)
                    if operation.exit_code==0 and completed_kind==1:
                        settings=Project3D.load(project)
                        for path in settings.manifests:assets.reload_manifest(device,project+"/"+path,Scene3D())
            else:device.input.lose_focus()
        if device.input.pressed(59):
            dock_right=not dock_right
            atomic_write(project+"/.atlas-editor.layout","RIGHT\n" if dock_right else "LEFT\n")
        if device.input.pressed(60):text_mode=1
        if device.input.pressed(64):
            text_mode=2
            import_stage=0
            import_source=String()
        if device.input.pressed(61):
            var cell=world.find(editor.x,editor.z)
            if cell>=0 and world.cells[cell].scene.valid(editor.selected):
                text_mode=3
                property_kind=0
                property_value=property_text(world.cells[cell].scene.nodes[editor.selected],property_kind)
            else:editor.status="SELECT AN OBJECT TO EDIT PROPERTIES"
        if device.input.pressed(68) and operation.pid==0:
            text_mode=4
            import_stage=0
        if text_mode==3 and device.input.pressed(43):
            property_kind=(property_kind+1)%4
            var cell=world.find(editor.x,editor.z)
            if cell>=0:property_value=property_text(world.cells[cell].scene.nodes[editor.selected],property_kind)
        if text_mode>0:
            var value=search.copy() if text_mode==1 else (property_value.copy() if text_mode==3 else (import_source.copy() if import_stage==0 else import_id.copy()))
            if value.byte_length()+device.input.text.byte_length()<=4096:value+=device.input.text
            if device.input.pressed(42) and value.byte_length()>0:
                var end=value.byte_length()-1
                var bytes=value.as_c_string_span().ptr().unsafe_bitcast[UInt8]()
                while end>0 and (bytes[unsafe_offset=end]&UInt8(192))==UInt8(128):end-=1
                var trimmed=String(value[byte=:end])
                value=trimmed^
            if text_mode==1:search=value^
            elif text_mode==3:property_value=value^
            elif import_stage==0:import_source=value^
            else:import_id=value^
            if device.input.pressed(41):text_mode=0
            elif device.input.pressed(40):
                if text_mode==2 and import_stage==0:import_stage=1
                else:
                    if text_mode==3:
                        try:
                            var fields=property_value.split(",")
                            if len(fields)!=(4 if property_kind==2 else (6 if property_kind==3 else 3)):raise Error("PROPERTY VALUES NEED COMMA SEPARATORS")
                            var values=List[Float64]()
                            for field in fields:
                                var number=Float64(String(field))
                                if not isfinite(number):raise Error("PROPERTY VALUES MUST BE FINITE")
                                values.append(number)
                            var cell=world.find(editor.x,editor.z)
                            if cell<0 or not world.cells[cell].scene.valid(editor.selected):raise Error("SELECT A RESIDENT OBJECT")
                            var transform=world.cells[cell].scene.nodes[editor.selected].transform
                            if property_kind==0:transform.position=Vec3(values[0],values[1],values[2])
                            elif property_kind==1:transform.scale=Vec3(values[0],values[1],values[2])
                            elif property_kind==2:transform.rotation=Quaternion(values[0],values[1],values[2],values[3]).normalized()
                            if property_kind<3:editor.transform(world,transform)
                            else:editor.material(world,Material(Vec3(values[0],values[1],values[2]),values[3],values[4],values[5]))
                        except error:editor.status=String(error)
                    if text_mode==4:
                        world.save()
                        var command: List[String]=[sdk+"/build/atlas-usd-editor","--source",import_source.copy(),"--output",project+"/usd","--sdk",sdk.copy()]
                        try:
                            operation.start(command^)
                            operation_kind=6
                            editor.status="USD AUTHORING WINDOW OPEN"
                        except error:editor.status=String(error)
                    if text_mode==2:
                        world.save()
                        var command: List[String]=["python3",sdk+"/scripts/atlas-project.py","import","--project",project.copy(),"--source",import_source.copy(),"--id",import_id.copy(),"--report",operation_report.copy()]
                        try:
                            operation.start(command^)
                            operation_kind=1
                            editor.status="IMPORTING CONTENT"
                        except error:editor.status=String(error)
                    text_mode=0
            device.input.lose_focus()
        if device.input.pressed(65):
            settings=Project3D.load(project)
            for path in settings.manifests:assets.reload_manifest(device,project+"/"+path,Scene3D())
            editor.status="PROJECT ASSETS RELOADED"
        if device.input.pressed(67):
            world.save()
            var destination=project+"/exports/world-"+String(external_call["SDL_GetPerformanceCounter",UInt64]())
            var command: List[String]=["python3",sdk+"/scripts/atlas-project.py","export","--project",project.copy(),"--destination",destination.copy(),"--sdk",sdk.copy(),"--editor-snapshot","--report",operation_report.copy()]
            try:
                operation.start(command^)
                operation_kind=2
                editor.status="EXPORTING WORLD TO "+destination
            except error:editor.status=String(error)
        if device.input.pressed(69) and operation_kind==0:
            world.save()
            usd_export_destination=project+"/exports/usd-cell-"+String(external_call["SDL_GetPerformanceCounter",UInt64]())
            var source="cell_"+String(editor.x)+"_"+String(editor.z)+".scene"
            var command: List[String]=["python3",sdk+"/scripts/atlas-project.py","usd-export","--project",project.copy(),"--source",source.copy(),"--destination",usd_export_destination.copy(),"--editor-snapshot","--report",operation_report.copy()]
            try:
                operation.start(command^)
                operation_kind=7
                usd_export_started=True
                editor.status="EXPORTING SELECTED CELL TO USD"
            except error:editor.status=String(error)
        if device.input.pressed(63) and operation_kind==0:
            world.save()
            play_destination=project+"/play/world-"+String(external_call["SDL_GetPerformanceCounter",UInt64]())
            var command: List[String]=["python3",sdk+"/scripts/atlas-project.py","export","--project",project.copy(),"--destination",play_destination.copy(),"--sdk",sdk.copy(),"--play-copy","--editor-snapshot","--report",operation_report.copy()]
            try:
                operation.start(command^)
                operation_kind=3
                editor.status="PREPARING ISOLATED PLAY WORLD"
            except error:editor.status=String(error)
        var visible=List[Int]()
        for i in range(len(assets.keys)):
            if search.byte_length()==0 or search in assets.keys[i]:visible.append(i)
        browser_offset=min(browser_offset,max(0,len(visible)-15))
        var panel_x=max(240,device.width-240) if dock_right else 0
        var inspector_x=0 if dock_right else max(240,device.width-240)
        var browser_hover=device.input.mouse_x>=panel_x and device.input.mouse_x<panel_x+240
        var inspector_hover=device.input.mouse_x>=inspector_x and device.input.mouse_x<inspector_x+240
        var dt=1.0/60 if smoke else device.input.dt
        world.update(camera.position)
        if streamer.revision!=world.terrain_revision:
            terrain.layer=world.terrain.copy()
            ground=Optional[TerrainConfig](terrain.copy())
            streamer.set_layer(world.terrain,world.terrain_revision)
        collision_stream.update(world,assets,collision)
        var collision_ready=True
        if inspector_hover:hierarchy_offset=max(0,hierarchy_offset-device.input.mouse_wheel)
        if browser_hover:
            browser_offset=max(0,min(max(0,len(visible)-15),browser_offset-device.input.mouse_wheel))
        if device.input.pressed(6):walk=not walk
        if device.input.pressed(11):terrain_mode=0 if terrain_mode==1 else 1
        if device.input.pressed(19):terrain_mode=0 if terrain_mode==2 else 2
        if terrain_mode>0:brush_radius=max(Float64(2),min(Float64(64),brush_radius+Float64(device.input.mouse_wheel)*2))
        if walk:
            collision.boxes.clear()
            for cell in world.cells:
                var transforms=cell.scene.world_matrices()
                for i in range(len(cell.scene.nodes)):
                    if cell.scene.valid(i) and cell.scene.nodes[i].asset_key=="atlas/cube":
                        var mesh=assets.node_mesh(cell.scene,i)
                        _=collision.add(assets.bounds[mesh].transformed(transforms[i]))
            var desired=Vec3(device.input.axis(4,7)*5,0,-device.input.axis(22,26)*5)
            var destination=character.position+desired*dt
            for corner in range(4):
                var x=Int((destination.x+(character.radius if corner&1 else -character.radius))//world.cell_size)
                var z=Int((destination.z+(character.radius if corner&2 else -character.radius))//world.cell_size)
                if not collision_stream.ready(world,assets,x,z):collision_ready=False
            if collision_ready:character.step(collision,desired,max(0.0001,dt),device.input.pressed(44),terrain=ground)
            camera.position=character.position+Vec3(0,4,8)
        else:camera.update(device.input,dt)
        world.update(camera.position)
        streamer.update(device,camera.position,min(Float64(1),dt))
        var gameplay_input=device.input.copy()
        if play_only:device.input.lose_focus()
        if not play_only and operation_kind==0 and not initialized and world.find(0,0)>=0:
            initialized=True
            var cell=world.find(0,0)
            if len(world.cells[cell].scene.nodes)==0:
                editor.place(world,SceneNode("LANDMARK",Transform3D(Vec3(80,terrain.height(80,30)+1,30),scale=Vec3(2,2,2)),asset_key="atlas/cube"))
        if device.input.pressed(29):editor.undo(world)
        if device.input.pressed(28):editor.redo(world)
        if device.input.pressed(27):
            try:editor.delete_selection(world)
            except error:editor.status=String(error)
        if device.input.pressed(62):
            for cell in world.cells:world.request_save(cell.x,cell.z)
            editor.status=String("SAVE QUEUED")
        if device.input.pressed(66):
            world.save()
            world.cells.clear()
            editor.selected=-1
            editor.undo_stack.clear()
            editor.redo_stack.clear()
            editor.status=String("RELOADING WORLD")
        if device.input.pressed(23):
            camera.position.x+=1000000000
            camera.position.z+=1000000000
            camera.position.y=terrain.height(camera.position.x,camera.position.z)+30
            if walk:
                character.position=Vec3(camera.position.x,terrain.height(camera.position.x,camera.position.z),camera.position.z)
                character.velocity=Vec3(0,0,0)
                character.grounded=False
                character.support=-1
        if device.input.pressed(30):transform_mode=0
        if device.input.pressed(31):transform_mode=1
        if device.input.pressed(32):transform_mode=2
        if device.input.pressed(15):local_mode=not local_mode
        if device.input.pressed(10):snap=0 if snap>0 else 1
        var projection=Mat4.perspective(1.04719755,Float64(max(1,device.width))/Float64(max(1,device.height)),0.2,1200)*camera.view()
        var ray=camera.screen_ray(device.input.mouse_x,device.input.mouse_y,device.width,device.height)
        var selected_cell=world.find(editor.x,editor.z)
        if device.input.mouse_pressed(1):
            drag_axis=-1
            if browser_hover and device.input.mouse_y>=110:
                var row=browser_offset+(device.input.mouse_y-110)//32
                if row>=0 and row<len(visible):drag_asset=visible[row]
            elif inspector_hover and device.input.mouse_y>=110 and device.input.mouse_y<374:
                var row=hierarchy_offset+(device.input.mouse_y-110)//22
                var index=0
                for cell in world.cells:
                    for node in range(len(cell.scene.nodes)):
                        if not cell.scene.valid(node):continue
                        if index==row:
                            editor.x=cell.x
                            editor.z=cell.z
                            editor.selected=node
                        index+=1
            elif device.input.mouse_y>96 and terrain_mode>0 and not walk:
                var point=ground_point(camera,ray,terrain)
                if terrain_mode==1:editor.sculpt(world,point,brush_radius,Float64(-2 if device.input.down(225) else 2))
                else:editor.paint(world,point,brush_radius,brush_color)
            elif device.input.mouse_y>64:
                if selected_cell>=0 and world.cells[selected_cell].scene.valid(editor.selected):
                    var position=world.cells[selected_cell].scene.world_matrix(editor.selected).point(Vec3(0,0,0))
                    for axis in range(3):
                        var direction=world.cells[selected_cell].scene.world_matrix(editor.selected).direction(directions[axis]).unit() if local_mode else directions[axis]
                        var point=screen(projection,position+direction*4-camera.position,device.width,device.height)
                        if point and (point.value()-Vec2(Float64(device.input.mouse_x),Float64(device.input.mouse_y))).length()<14:
                            drag_axis=axis
                            drag_direction=direction
                            drag_rotation_axis=directions[axis] if local_mode else direction
                            drag_amount=0
                            try:drag=editor.preview(world)
                            except error:
                                drag_axis=-1
                                editor.status=String(error)
                if drag_axis<0:
                    var best: Float64=10000
                    for cell in world.cells:
                        var picked=assets.pick(cell.scene,camera.position,ray,best)
                        if picked>=0:
                            var mesh=assets.node_mesh(cell.scene,picked)
                            var distance=assets.bounds[mesh].transformed(cell.scene.world_matrix(picked)).ray(camera.position,ray,best)
                            best=distance
                            editor.x=cell.x
                            editor.z=cell.z
                            editor.selected=picked
        if device.input.mouse_pressed(1) and drag_axis<0 and terrain_mode==0 and editor.selected>=0:
            editor.select(world,editor.x,editor.z,editor.selected,device.input.down(224))
        selected_cell=world.find(editor.x,editor.z)
        if drag_axis>=0 and device.input.mouse_down(1) and selected_cell>=0:
            # Render-only overrides; release commits one grouped command.
            drag_amount+=Float64(device.input.mouse_dx-device.input.mouse_dy)*.1
            try:
                drag.validate(world)
                if transform_mode==0:drag.update(delta=drag_direction*drag_amount,snap=snap)
                elif transform_mode==1:drag.update(axis=drag_rotation_axis,angle=drag_amount*.1,local=local_mode)
                else:
                    var multiplier=max(Float64(.1),min(Float64(10),exp(min(Float64(20),max(Float64(-20),drag_amount*.1)))))
                    drag.update(scale=Vec3(multiplier if drag_axis==0 else 1,multiplier if drag_axis==1 else 1,multiplier if drag_axis==2 else 1))
            except error:
                drag_axis=-1
                editor.status=String(error)
        if device.input.mouse_released(1):
            if drag_asset>=0 and not browser_hover and not inspector_hover:
                var position=ground_point(camera,ray,terrain)
                editor.place(world,SceneNode(assets.keys[drag_asset],Transform3D(position),asset_key=assets.keys[drag_asset]))
            if drag_axis>=0:
                try:editor.commit_preview(world,drag)
                except error:editor.status=String(error)
            drag_asset=-1
            drag_axis=-1
        selected_cell=world.find(editor.x,editor.z)
        if selected_cell>=0 and world.cells[selected_cell].scene.valid(editor.selected):
            var transform=world.cells[selected_cell].scene.nodes[editor.selected].transform
            var delta=Vec3(Float64(Int(device.input.pressed(79))-Int(device.input.pressed(80))),Float64(Int(device.input.pressed(75))-Int(device.input.pressed(78))),Float64(Int(device.input.pressed(81))-Int(device.input.pressed(82))))
            var changed=delta.length()>0
            transform.position=transform.position+delta
            if device.input.pressed(21):
                transform.rotation=Quaternion.axis_angle(Vec3(0,1,0),.261799)*transform.rotation
                changed=True
            if device.input.pressed(46) or device.input.pressed(45):
                transform.scale=transform.scale*(1.1 if device.input.pressed(46) else 1/1.1)
                changed=True
            if changed:editor.adjust_selection(world,delta,angle=Float64(.261799) if device.input.pressed(21) else Float64(0),factor=(1.1 if device.input.pressed(46) else (Float64(1/1.1) if device.input.pressed(45) else Float64(1))),local=local_mode,snap=snap)
            if device.input.pressed(5):
                try:editor.duplicate_selection(world)
                except error:editor.status=String(error)
        if device.input.pressed(24) and editor.selected>=0:
            prefab=editor.prefab(world)
            prefab.save(project+"/prefab.scene")
            editor.status="PREFAB SAVED; V PLACE"
        if device.input.pressed(25) and len(prefab.nodes)>0:editor.instantiate(world,prefab,ground_point(camera,ray,terrain))
        if drag_axis>=0:
            try:drag.validate(world)
            except error:
                drag_axis=-1
                editor.status=String(error)
        var sun=Vec3(.4,.8,.3).unit()
        var light=Mat4.orthographic(240,.1,900)*Mat4.look_at(sun*420,Vec3(0,0,0))
        if shadow_quality==0:device.shadow_begin(light)
        else:
            shadows.prepare(projection,.2,1200,sun,camera.direction(),world_origin=camera.position)
            device.shadow_cascades(shadows.matrices,shadows.splits,camera.direction())
            light=shadows.cull_matrix
        streamer.draw(device,camera.position,True,light,True)
        for i in range(len(world.cells)):
            var overrides=Dict[Int,Transform3D]()
            if drag_axis>=0:overrides=drag.overrides(world.cells[i].x,world.cells[i].z)
            if len(overrides)>0:assets.draw(device,world.cells[i].scene,camera.position,light,True,overrides=overrides)
            else:assets.draw_cached(device,world.cells[i].scene,world.cells[i].render_cache,world.cells[i].revision,camera.position,light,True)
        device.begin(projection,sun)
        streamer.draw(device,camera.position,False,projection,True)
        for i in range(len(world.cells)):
            var overrides=Dict[Int,Transform3D]()
            if drag_axis>=0:overrides=drag.overrides(world.cells[i].x,world.cells[i].z)
            if len(overrides)>0:assets.draw(device,world.cells[i].scene,camera.position,projection,overrides=overrides)
            else:assets.draw_cached(device,world.cells[i].scene,world.cells[i].render_cache,world.cells[i].revision,camera.position,projection)
        if not play_only:
            device.rect(0,0,Float64(device.width),64,Vec3(.035,.05,.065))
            device.text("ATLAS WORLD",20,22,scale=3)
            device.rect(Float64(panel_x),64,240,Float64(device.height-64),Vec3(.035,.05,.065),.95)
            device.text("ASSET BROWSER",panel_x+16,82,scale=2)
            for i in range(min(max(0,len(visible)-browser_offset),15)):
                var asset_index=visible[browser_offset+i]
                if asset_index==drag_asset:device.rect(Float64(panel_x+8),Float64(108+i*32),220,30,Vec3(.08,.3,.27))
                device.text(assets.keys[asset_index],panel_x+16,120+i*32,scale=1)
            device.text("DRAG AN ASSET INTO WORLD",panel_x+16,device.height-160,scale=1)
            device.text("F3 SEARCH F7 IMPORT F8 RELOAD",panel_x+16,device.height-138,scale=1)
            device.text("Z/Y UNDO F5 SAVE F10 EXPORT",panel_x+16,device.height-116,scale=1)
            device.text("H SCULPT  P PAINT  SHIFT LOWER  WHEEL SIZE  |  ARROWS MOVE R ROTATE +/- SCALE",256,82,scale=1)
            if terrain_mode>0:
                device.text((String("SCULPT") if terrain_mode==1 else String("PAINT"))+" BRUSH "+String(brush_radius),256,128,Vec3(1,.8,.3),scale=1)
                var brush_point=screen(projection,ground_point(camera,ray,terrain)-camera.position,device.width,device.height)
                if brush_point:device.circle(brush_point.value().x,brush_point.value().y,8,Vec3(1,.8,.3))
            selected_cell=world.find(editor.x,editor.z)
            if selected_cell>=0 and world.cells[selected_cell].scene.valid(editor.selected):
                var matrix=world.cells[selected_cell].scene.world_matrix(editor.selected)
                if drag_axis>=0:matrix=world.cells[selected_cell].scene.world_matrix(editor.selected,drag.overrides(editor.x,editor.z))
                var position=matrix.point(Vec3(0,0,0))
                var center=screen(projection,position-camera.position,device.width,device.height)
                if center:
                    for axis in range(3):
                        var direction=matrix.direction(directions[axis]).unit() if local_mode else directions[axis]
                        var endpoint=screen(projection,position+direction*4-camera.position,device.width,device.height)
                        if endpoint:
                            axis_line(device,center.value(),endpoint.value(),colors[axis])
                            device.circle(endpoint.value().x,endpoint.value().y,7,colors[axis])
                device.text(world.cells[selected_cell].scene.nodes[editor.selected].name,256,105,scale=1)
            device.rect(Float64(inspector_x),64,240,Float64(max(0,device.height-64)),Vec3(.035,.05,.065),.95)
            device.text("HIERARCHY / PROPERTIES",inspector_x+12,82,scale=1)
            var row=0
            for cell in world.cells:
                for node in range(len(cell.scene.nodes)):
                    if not cell.scene.valid(node):continue
                    if row>=hierarchy_offset and row<hierarchy_offset+12:
                        device.text((String(" > ") if cell.x==editor.x and cell.z==editor.z and node==editor.selected else String("   "))+cell.scene.nodes[node].name,inspector_x+8,110+(row-hierarchy_offset)*22,scale=1)
                    row+=1
            hierarchy_offset=min(hierarchy_offset,max(0,row-12))
            if selected_cell>=0 and world.cells[selected_cell].scene.valid(editor.selected):
                device.text("F4 EDIT / TAB FIELD",inspector_x+12,410,scale=1)
                device.text(property_text(world.cells[selected_cell].scene.nodes[editor.selected],0),inspector_x+12,432,scale=1)
                device.text("SCALE",inspector_x+12,456,scale=1)
                device.text(property_text(world.cells[selected_cell].scene.nodes[editor.selected],1),inspector_x+12,478,scale=1)
            device.text("F11 USD  F12 EXPORT CELL",inspector_x+12,device.height-90,scale=1)
            device.text("RECOVERIES "+String(world.store.recoveries),inspector_x+12,device.height-68,scale=1)
            if text_mode>0:
                device.rect(248,152,Float64(max(320,device.width-510)),112,Vec3(.06,.12,.16),.98)
                device.text("ASSET SEARCH" if text_mode==1 else (("POSITION X,Y,Z" if property_kind==0 else ("SCALE X,Y,Z" if property_kind==1 else ("ROTATION QUAT X,Y,Z,W" if property_kind==2 else "COLOR RGB,ROUGHNESS,METALLIC,EMISSION"))) if text_mode==3 else ("USD SOURCE PATH" if text_mode==4 else ("IMPORT SOURCE PATH" if import_stage==0 else "IMPORT ASSET ID"))),264,170,scale=1)
                device.text(search if text_mode==1 else (property_value if text_mode==3 else (import_source if import_stage==0 else import_id)),264,200,scale=1)
                device.text("ENTER ACCEPT  ESC CANCEL",264,236,scale=1)
            device.text("CELLS "+String(len(world.cells))+" CHUNKS "+String(len(streamer.chunks))+" DRAWS "+String(device.draws()),256,device.height-42,scale=1)
            device.text(editor.status,256,device.height-22,scale=1)
            if walk and not collision_ready:device.text("LOADING WORLD COLLISION",256,128,Vec3(1,.8,.3),scale=1)
            if smoke and frame==59:device.snapshot("build/atlas-world.bmp")
        if play_only:
            device.text("ATLAS PLAY | WASD MOVE SPACE JUMP ESC QUIT",20,20,scale=1)
            device.input=gameplay_input^
        device.present()
        frame+=1
        if play_only and smoke and frame==1:atomic_write(project+"/.atlas-play-frame","FRAME_PRESENTED\n")
        if smoke:
            external_call["SDL_Delay",NoneType](UInt32(2))
            if (not smoke_play and not smoke_usd_export and frame==60) or (smoke_play and play_seen and operation_kind==0) or (smoke_usd_export and usd_export_done):break
            if frame>=600:raise Error("Isolated play smoke did not finish")
    if smoke_usd_export and not usd_export_done:raise Error("USD editor export did not complete")
    if smoke_play and not play_seen:raise Error("Isolated play did not present a frame")
    operation.close()
    if play_destination.byte_length()>0:
        var command: List[String]=["python3",sdk+"/scripts/atlas-project.py","cleanup-play","--project",project.copy(),"--destination",play_destination.copy()]
        operation.start(command^)
        while not operation.poll():external_call["SDL_Delay",NoneType](UInt32(1))
    world.save()
    streamer.clear(device)
    collision_stream.clear(collision)
    assets.close(device)
    if device.validation_errors()!=0:raise Error("Atlas editor Vulkan validation failed")
    print("Atlas editor closed; chunks uploaded:",streamer.uploads,"peak worker reservations:",streamer.queue.peak_bytes())
