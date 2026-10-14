"""Native USD hierarchy, layers and variants panels, backed by a persistent stage."""
from std.sys import argv
from std.ffi import external_call
from std.math import sin,cos,exp,isfinite
from std.collections import Dict
from mojo_game import Graphics3D,Vec3,Mat4,ProjectOperation,Assets3D,Scene3D,VisibilityTrack,PreviewPlayback,AuthoredCamera3D,AuthoredCameraTrack3D,AuthoredLighting3D,AuthoredLightTrack3D,LocalLight3D,Transform3D,Environment3D
from mojo_game.durableio import exists,read_bounded,atomic_write,object_id

struct CurvePanel:
    var rows: List[String]
    var properties: List[String]
    var selected: Int
    var path: String
    var revision: Int
    var time: Float64
    var requested: String
    var pending: Bool
    var editing: Bool
    var entry: String
    var message: String
    var edit_kind: Int
    var interpolation_index: Int
    def __init__(out self):
        self.rows=List[String]()
        self.properties=List[String]()
        self.selected=0
        self.path=String()
        self.revision = -1
        self.time=0
        self.requested=String()
        self.pending=False
        self.editing=False
        self.entry=String()
        self.message=String()
        self.edit_kind=0
        self.interpolation_index=0

    def spline_selected(self) -> Bool:
        if len(self.properties)==0:return False
        var property=self.properties[self.selected].split("\t")
        for row in self.rows:
            var fields=row.split("\t")
            if len(fields)==3 and String(fields[0])=="spline" and String(fields[1])==String(property[1]):return String(fields[2])=="1"
        return False

    def update(mut self,work: String,device: Graphics3D,path: String,time: Float64,revision: Int,available: Bool) raises -> String:
        if self.pending and available:
            self.pending=False
            if exists(work+"/curves.tsv"):
                self.rows.clear();self.properties.clear()
                var lines=read_bounded(work+"/curves.tsv",8*1024*1024).split("\n")
                if len(lines)==0 or String(lines[0])!="ATLAS_USD_CURVES_2":raise Error("Invalid curve panel data")
                for line in lines:
                    var f=String(line).split("\t")
                    if len(f)<2:continue
                    if String(f[0])=="path":self.path=String(f[1])
                    elif String(f[0])=="revision":self.revision=Int(String(f[1]))
                    elif String(f[0])=="time":self.time=Float64(String(f[1]))
                    elif String(f[0])=="property" and len(f)==8 and String(f[3])=="1":self.properties.append(String(line))
                    self.rows.append(String(line))
                self.selected=min(self.selected,max(0,len(self.properties)-1))
        var current=self.path==path and self.time==time and self.revision==revision
        if self.editing:
            if not current or device.input.pressed(41):
                self.editing=False
                device.text_input(False)
                return String()
            for i in range(device.input.text.byte_length()):
                var c=String(device.input.text[byte=i])
                if c in "0123456789.eE+-," and self.entry.byte_length()<256:self.entry+=c
            if device.input.pressed(42) and self.entry.byte_length()>0:
                var shortened=String(self.entry[byte=:self.entry.byte_length()-1])
                self.entry=shortened^
            if device.input.pressed(40) and available:
                try:
                    var fields=self.properties[self.selected].split("\t")
                    if self.edit_kind>=3 and self.edit_kind<=5:
                        var parts=self.entry.split(",")
                        var expected=4 if self.edit_kind==5 else 2
                        if len(parts)!=expected:raise Error("Wrong input count")
                        var numbers=String()
                        for part in parts:
                            var number=Float64(String(part))
                            if not isfinite(number):raise Error("Expected finite value")
                            numbers+="\t"+String(number)
                        self.editing=False;self.requested=String()
                        device.text_input(False)
                        if self.edit_kind==5:return "bake_curve\t"+path+"\t"+String(fields[5])+numbers
                        return "set_tangent\t"+path+"\t"+String(fields[5])+"\t"+String(time)+"\t"+(String("out") if self.edit_kind==3 else String("in"))+numbers
                    var value=Float64(self.entry)
                    if not isfinite(value):raise Error("Expected finite value")
                    self.editing=False
                    self.requested=String()
                    device.text_input(False)
                    if self.edit_kind==6:return "convert_frame_rate\t"+String(value)
                    if self.edit_kind==1 or self.edit_kind==2:
                        var op=String("move_key") if self.edit_kind==1 else String("copy_key")
                        if self.spline_selected():op="move_spline_key" if self.edit_kind==1 else "copy_spline_key"
                        return op+"\t"+path+"\t"+String(fields[5])+"\t"+String(time)+"\t"+String(value)
                    if self.spline_selected():return "set_spline_value\t"+path+"\t"+String(fields[5])+"\t"+String(value)+"\t"+String(time)
                    return "set_channel\t"+path+"\t"+String(fields[5])+"\t"+String(fields[6])+"\t"+String(value)+"\t"+String(time)
                except:
                    self.message="ENTER FINITE NUMBERS; COMMA SEPARATES FIELDS"
            return String()
        if current and len(self.properties)>0:
            if device.input.pressed(8):self.selected=(self.selected+1)%len(self.properties)
            if available and device.input.pressed(18):
                var modes: List[String]=["held","linear","bezier"]
                var fields=self.properties[self.selected].split("\t")
                var mode=modes[self.interpolation_index].copy()
                self.interpolation_index=(self.interpolation_index+1)%3;self.requested=String()
                return "set_interpolation\t"+path+"\t"+String(fields[5])+"\t"+mode
            if available and (device.input.pressed(40) or device.input.pressed(16) or device.input.pressed(25) or device.input.pressed(7) or device.input.pressed(9) or device.input.pressed(58) or device.input.pressed(59)):
                self.edit_kind=1 if device.input.pressed(16) else (2 if device.input.pressed(25) else 0)
                if device.input.pressed(7):self.edit_kind=3
                elif device.input.pressed(9):self.edit_kind=4
                elif device.input.pressed(59):self.edit_kind=5
                elif device.input.pressed(58):self.edit_kind=6
                self.entry=String();self.message=String();self.editing=True
                device.text_input(True)
            if device.input.pressed(76) and available:
                var fields=self.properties[self.selected].split("\t")
                self.requested=String()
                return (String("delete_spline_key") if self.spline_selected() else String("delete_key"))+"\t"+path+"\t"+String(fields[5])+"\t"+String(time)
        var request=path+"\t"+String(time)+"\t"+String(revision)
        if available and not self.editing and not current and self.requested!=request:
            if self.path!=path:self.selected=0
            self.requested=request
            self.pending=True
            return "curves\t"+path+"\t"+String(time)
        return String()

    def draw(self,device: Graphics3D) raises:
        device.text("E CHANNEL / ENTER VALUE / M MOVE / V COPY",800,592,scale=1)
        if len(self.properties)==0:
            device.text("NO EDITABLE NUMERIC CHANNELS",800,614,scale=1)
            for row in self.rows:
                var fields=row.split("\t")
                if len(fields)>=3 and String(fields[0])=="read_only":
                    var reason=String(fields[2])
                    device.text("READ ONLY: "+String(reason[byte=:min(45,reason.byte_length())]),800,636,scale=1)
                    break
            return
        var fields=self.properties[self.selected].split("\t")
        var name=String(fields[1])
        device.text(name+" = "+String(fields[2])+"  KEYS "+String(fields[4]),800,614,scale=1)
        if self.editing:
            var prompt=String("VALUE: ")
            if self.edit_kind==1 or self.edit_kind==2:prompt="DEST TIME: "
            elif self.edit_kind==3 or self.edit_kind==4:prompt="SLOPE,WIDTH: "
            elif self.edit_kind==5:prompt="START,END,STEP,ERROR: "
            elif self.edit_kind==6:prompt="NEW RATE: "
            device.text(prompt+self.entry+"_",800,643,scale=1)
            device.text(self.message,800,670,scale=1)
            return
        var times=List[Float64]()
        var values=List[Float64]()
        var local=List[Bool]()
        for row in self.rows:
            var f=row.split("\t")
            if len(f)==5 and String(f[0])=="key" and String(f[1])==name:
                times.append(Float64(String(f[2])));values.append(Float64(String(f[3])));local.append(String(f[4])=="1")
        if len(times)==0:return
        var low=values[0]
        var high=low
        for value in values:low=min(low,value);high=max(high,value)
        var first=times[0]
        var last=times[len(times)-1]
        var span=max(1.0,last-first)
        var magnitude=max(.001,max(abs(high),abs(low)))
        var height=max(.001,high/magnitude-low/magnitude)
        var index=0
        for x in range(420):
            var t=first+Float64(x)/419*span
            while index+1<len(times) and times[index+1]<t:index+=1
            var next=min(index+1,len(times)-1)
            var weight: Float64=0
            if times[next]>times[index]:weight=max(0.0,min(1.0,(t-times[index])/(times[next]-times[index])))
            var v=values[index]/magnitude*(1-weight)+values[next]/magnitude*weight
            device.rect(800+Float64(x),690-(v-low/magnitude)/height*45,1,1,Vec3(.3,.65,.8))
        for i in range(len(times)):
            device.rect(798+(times[i]-first)/span*419,688-(values[i]/magnitude-low/magnitude)/height*45,5,5,Vec3(1,.6,.2) if local[i] else Vec3(.6,.7,.8))
        device.rect(800+max(0.0,min(1.0,(self.time-first)/span))*419,640,1,55,Vec3(1,1,1))
        device.text("KEY GUIDES | DELETE/MOVE/COPY WHOLE KEY",800,700,scale=1)
        device.text("O H/L/BEZIER | D/F TANGENT OUT/IN",800,722,scale=1)
        device.text("F1 RATE (OWNED) | F2 BAKE (EXPLICIT)",800,740,scale=1)

def main() raises:
    var args=argv()
    var source=String()
    var workspace=String()
    var output=String("build/usd-edits")
    var sdk=String(".")
    var smoke=False
    var viewport_smoke=False
    var playback_smoke=False
    var keys_smoke=False
    var layers_smoke=False
    var workspace_smoke=False
    var source_smoke=False
    var typed_smoke=False
    for i in range(1,len(args)):
        if args[i]=="--source" and i+1<len(args):source=String(args[i+1])
        elif args[i]=="--workspace" and i+1<len(args):workspace=String(args[i+1])
        elif args[i]=="--output" and i+1<len(args):output=String(args[i+1])
        elif args[i]=="--sdk" and i+1<len(args):sdk=String(args[i+1])
        elif args[i]=="--smoke":smoke=True
        elif args[i]=="--smoke-viewport":smoke=True;viewport_smoke=True
        elif args[i]=="--smoke-playback":smoke=True;viewport_smoke=True;playback_smoke=True
        elif args[i]=="--smoke-layers":smoke=True;viewport_smoke=True;layers_smoke=True
        elif args[i]=="--smoke-keys":smoke=True;viewport_smoke=True;keys_smoke=True
        elif args[i]=="--smoke-workspace":smoke=True;workspace_smoke=True
        elif args[i]=="--smoke-source":smoke=True;source_smoke=True
        elif args[i]=="--smoke-channels":smoke=True;typed_smoke=True
    if source.byte_length()==0 and workspace.byte_length()==0:raise Error("USD editor needs --source or --workspace")
    var work=String("/tmp/atlas-usd-editor-")+object_id()
    if external_call["mkdir",Int32](work.as_c_string_span(),Int(448))!=0:raise Error("Cannot create owned USD editor directory")
    var worker=ProjectOperation()
    var viewport=not smoke or viewport_smoke
    var worker_args: List[String]=["python3",sdk+"/scripts/usd-editor-bridge.py","--work",work.copy(),"--output",output.copy()]
    if source.byte_length()>0:worker_args.append("--source");worker_args.append(source.copy())
    if workspace.byte_length()>0:worker_args.append("--workspace");worker_args.append(workspace.copy())
    if viewport:worker_args.append("--preview")
    worker.start(worker_args^)
    var device=Graphics3D("Atlas | USD layers and variants",1280,800,smoke)
    var lines=List[String]()
    var paths=List[String]()
    var types=List[String]()
    var selected=0
    var variant_index=0
    var sequence=0
    var ack=0
    var status=String("OPENING USD STAGE")
    var identity_issues=0
    var frames=0
    var ready=False
    var source_revision=0
    var display_revision = -1
    var preview_serial = -1
    var preview_status=String("PREVIEW STARTING")
    var assets=Assets3D()
    var scene=Scene3D()
    var hidden=List[VisibilityTrack]()
    var target=Vec3(0,0,0)
    var radius: Float64=1
    var distance: Float64=4
    var yaw: Float64=.45
    var pitch: Float64=.45
    var capture_before=False
    var playback=PreviewPlayback()
    var cameras=List[AuthoredCamera3D]()
    var camera_tracks=List[AuthoredCameraTrack3D]()
    var lighting=AuthoredLighting3D()
    var light_tracks=List[AuthoredLightTrack3D]()
    var local_lights=List[LocalLight3D]()
    var authored_camera=True
    var authored_lighting=True
    var has_lighting=False
    var camera_index=0
    var playing=False
    var clock: Float64=0
    var duration: Float64=0
    var rate: Float64=24
    var playback_capture=0
    var curve_panel=CurvePanel()
    var source_start: Float64=0
    var author_rate: Float64=24
    var edit_target=String("session")
    var workspace_dirty=True
    var edit_layers=List[String]()
    var source_conflicts=0
    var edit_context=String()
    while device.running:
        var typing=curve_panel.editing
        device.poll(quit_on_escape=not typing)
        if worker.poll():
            if worker.exit_code!=0:raise Error("USD stage service failed")
            break
        if frames%4==0 and exists(work+"/state.tsv"):
            var text=read_bounded(work+"/state.tsv",4*1024*1024)
            var rows=text.split("\n")
            if len(rows)==0 or String(rows[0])!="ATLAS_USD_EDITOR_1":raise Error("Invalid USD panel state")
            edit_layers.clear()
            paths.clear()
            types.clear()
            lines.clear()
            for row in rows:
                var line=String(row)
                var f=line.split("\t")
                if len(f)>=2:
                    if String(f[0])=="prim" and len(f)>=3:
                        paths.append(String(f[1]));types.append(String(f[2]))
                    elif String(f[0])=="status":status=String(f[1])
                    elif String(f[0])=="ack":ack=Int(String(f[1]))
                    elif String(f[0])=="revision":source_revision=Int(String(f[1]))
                    elif String(f[0])=="edit_target":edit_target=String(f[1])
                    elif String(f[0])=="unsaved_changes":workspace_dirty=String(f[1])=="1"
                    elif String(f[0])=="layer" and len(f)>=4 and String(f[2])=="1":edit_layers.append(String(f[1]))
                    elif String(f[0])=="start":source_start=Float64(String(f[1]))
                    elif String(f[0])=="author_rate":author_rate=Float64(String(f[1]))
                    elif String(f[0])=="identity_issues":identity_issues=Int(String(f[1]))
                    elif String(f[0])=="source_conflicts":source_conflicts=Int(String(f[1]))
                    elif String(f[0])=="edit_context":edit_context=String(f[1])
                    lines.append(line^)
            selected=min(selected,max(0,len(paths)-1))
            ready=True
        if viewport and frames%4==0 and exists(work+"/preview.tsv"):
            var fields=read_bounded(work+"/preview.tsv",4096).strip().split("\t")
            if len(fields)>=2:
                preview_status=String(fields[0])+" REV "+String(fields[1])
                if String(fields[0])=="ERROR" and len(fields)>=4:
                    preview_status+=" "+String(fields[3])
                    if viewport_smoke:raise Error(preview_status)
                if String(fields[0])=="READY" and len(fields)>=4 and Int(String(fields[1]))==source_revision and Int(String(fields[3]))!=preview_serial:
                    var candidate=Assets3D()
                    try:
                        var prefix=String(fields[2])
                        var next_scene=Scene3D.load(prefix+"-scene.sceneb")
                        candidate.load_manifest(device,prefix+"-assets.atlasb")
                        candidate.validate(next_scene)
                        var next_hidden=List[VisibilityTrack]()
                        if exists(prefix+"-visibility.atlasvisibility"):next_hidden=VisibilityTrack.load(prefix+"-visibility.atlasvisibility")
                        var next_playback=PreviewPlayback.load(prefix,next_scene,candidate)
                        var initial_pose=next_playback.apply(device,candidate,0)
                        var next_cameras=List[AuthoredCamera3D]()
                        var next_camera_tracks=List[AuthoredCameraTrack3D]()
                        var next_lighting=AuthoredLighting3D()
                        var next_light_tracks=List[AuthoredLightTrack3D]()
                        var next_local=List[LocalLight3D]()
                        if exists(prefix+"-cameras.atlascameras"):next_cameras=AuthoredCamera3D.load(prefix+"-cameras.atlascameras")
                        if exists(prefix+"-camera-tracks.atlascameratracks"):next_camera_tracks=AuthoredCameraTrack3D.load(prefix+"-camera-tracks.atlascameratracks")
                        var next_has_lighting=exists(prefix+"-lights.atlaslights") or exists(prefix+"-local-lights.atlaslocallights")
                        if exists(prefix+"-lights.atlaslights"):next_lighting=AuthoredLighting3D.load(prefix+"-lights.atlaslights")
                        if exists(prefix+"-light-tracks.atlaslighttracks"):next_light_tracks=AuthoredLightTrack3D.load(prefix+"-light-tracks.atlaslighttracks")
                        if exists(prefix+"-local-lights.atlaslocallights"):next_local=LocalLight3D.load(prefix+"-local-lights.atlaslocallights")
                        var timing=read_bounded(prefix+"-timing.atlastiming",4096).split("\n")
                        if len(timing)<3 or String(timing[0])!="ATLAS_PREVIEW_TIME_1":raise Error("Invalid preview timing")
                        var next_duration=Float64(String(timing[1]))
                        var next_rate=Float64(String(timing[2]))
                        if not isfinite(next_duration) or next_duration<0 or not isfinite(next_rate) or next_rate<=0:raise Error("Invalid preview clock")
                        var low=Vec3(0,0,0)
                        var high=low
                        var first=True
                        for i in range(len(next_scene.nodes)):
                            if not next_scene.valid(i):continue
                            var mesh=candidate.node_mesh(next_scene,i)
                            if mesh<0:continue
                            var bound=candidate.bounds[mesh].transformed(next_scene.world_matrix(i,initial_pose))
                            if first:low=bound.minimum;high=bound.maximum;first=False
                            else:
                                low=Vec3(min(low.x,bound.minimum.x),min(low.y,bound.minimum.y),min(low.z,bound.minimum.z))
                                high=Vec3(max(high.x,bound.maximum.x),max(high.y,bound.maximum.y),max(high.z,bound.maximum.z))
                        if display_revision<0:
                            target=(low+high)*.5
                            radius=max(.1,(high-low).length()*.5)
                            distance=radius*3.5
                        assets.close(device)
                        assets=candidate^
                        scene=next_scene^
                        hidden=next_hidden^
                        playback=next_playback^
                        cameras=next_cameras^
                        camera_tracks=next_camera_tracks^
                        lighting=next_lighting
                        light_tracks=next_light_tracks^
                        local_lights=next_local^
                        has_lighting=next_has_lighting
                        camera_index=min(camera_index,max(0,len(cameras)-1))
                        duration=next_duration
                        rate=next_rate
                        clock=min(clock,duration)
                        display_revision=source_revision
                    except error:
                        candidate.close(device)
                        preview_status="UPLOAD ERROR: PREVIOUS VIEW RETAINED"
                        if viewport_smoke:raise error^
                    preview_serial=Int(String(fields[3]))
                    atomic_write(work+"/preview-ack.txt",String(preview_serial)+"\n")
        if viewport and device.input.mouse_x>350 and device.input.mouse_y>110 and device.input.mouse_y<560:
            if device.input.mouse_down(3):
                yaw+=Float64(device.input.mouse_dx)*.008
                pitch=max(-1.4,min(1.4,pitch+Float64(device.input.mouse_dy)*.008))
            distance=max(radius*.05,min(radius*100,distance*exp(-Float64(device.input.mouse_wheel)*.12)))
        if not typing:
            if device.input.pressed(44):playing=not playing
            if device.input.pressed(74):clock=0;playing=False
            if device.input.pressed(47):clock=max(0.0,clock-1/rate);playing=False
            if device.input.pressed(48):clock=min(duration,clock+1/rate);playing=False
            if device.input.pressed(14):authored_camera=not authored_camera
            if device.input.pressed(13):authored_lighting=not authored_lighting
            if device.input.pressed(17) and len(cameras)>0:camera_index=(camera_index+1)%len(cameras)
            if playing and display_revision>=0:
                clock=min(duration,clock+min(.1,max(0.0,device.input.dt)))
                if clock>=duration:playing=False
            if playback_smoke:clock=0 if playback_capture==0 else duration
            if device.input.pressed(82):selected=max(0,selected-1);variant_index=0
            if device.input.pressed(81):selected=min(max(0,len(paths)-1),selected+1);variant_index=0
        var variants=List[String]()
        if len(paths)>0:
            for line in lines:
                var f=line.split("\t")
                if len(f)>=5 and String(f[0])=="variant" and String(f[1])==paths[selected]:variants.append(line.copy())
        if device.input.pressed(43) and len(variants)>0:variant_index=(variant_index+1)%len(variants)
        var command=String()
        if ready and ack==sequence and not typing:
            if device.input.pressed(29):command="undo"
            elif device.input.pressed(28):command="redo"
            elif device.input.pressed(21):command="reload"
            elif device.input.pressed(12):command="assign_ids"
            elif device.input.pressed(6):command="repair_ids"
            elif device.input.pressed(22):command="save_workspace"
            elif device.input.pressed(63):command="save"
            elif device.input.pressed(66):command="open_workspace"
            elif device.input.pressed(26):command="begin_source_editing"
            elif device.input.pressed(10) and len(paths)>0:command="cycle_source_target\t"+paths[selected]
            elif device.input.pressed(64):command="resolve_sources\tkeep_working"
            elif device.input.pressed(65):command="resolve_sources\treload"
            elif device.input.pressed(19):command="package"
            elif device.input.pressed(5):command="create_layer\tLayer-"+String(sequence+1)
            elif device.input.pressed(23) and len(edit_layers)>0:
                var current=0
                for i in range(len(edit_layers)):
                    if edit_layers[i]==edit_target:current=i
                command="select_layer\t"+edit_layers[(current+1)%len(edit_layers)]
            elif device.input.pressed(27):command="clear_layer"
            elif device.input.pressed(15) and len(paths)>0:command="load\t"+paths[selected]
            elif device.input.pressed(24) and len(paths)>0:command="unload\t"+paths[selected]
            elif (device.input.pressed(79) or device.input.pressed(80)) and len(variants)>0:
                variant_index=min(variant_index,len(variants)-1)
                var f=variants[variant_index].split("\t")
                var choice=0
                for i in range(4,len(f)):
                    if String(f[i])==String(f[3]):choice=i-4
                var count=len(f)-4
                choice=(choice+(1 if device.input.pressed(79) else count-1))%count
                command="variant\t"+String(f[1])+"\t"+String(f[2])+"\t"+String(f[4+choice])
            if smoke and not viewport_smoke and sequence==0:command="assign_ids"
            elif smoke and not viewport_smoke and sequence==1:command="undo"
            elif smoke and not viewport_smoke and sequence==2:command="redo"
            elif smoke and not viewport_smoke and sequence==3:command="save"
            if workspace_smoke:
                if sequence==0:command="create_layer\tAnimation"
                elif sequence==1:command="create_layer\tShot"
                elif sequence==2:command="select_layer\tAnimation"
                elif sequence==3:command="save_workspace"
                elif sequence==4:command="open_workspace"
            if source_smoke:
                if sequence==0:command="begin_source_editing"
                elif sequence==1:command="cycle_source_target\t/Shot"
                elif sequence==2:command="set_key\t/Shot\tfocalLength\t77\t3"
                elif sequence==3:command="repair_ids"
                elif sequence==4:command="save_workspace"
                elif sequence==5:command="open_workspace"
            if typed_smoke:
                for i in range(len(paths)):
                    if paths[i]=="/Dolly":selected=i
                clock=1.25/rate
                if sequence==0:command="curves\t/Dolly\t1.25";curve_panel.pending=True
                elif sequence==1:command="set_channel\t/Dolly\txformOp:translate\t0\t5.25\t1.25"
                elif sequence==2:command="copy_key\t/Dolly\txformOp:translate\t1.25\t2.75"
                elif sequence==3:command="move_key\t/Dolly\txformOp:translate\t2.75\t3.5"
                elif sequence==4:command="curves\t/Dolly\t3.5";curve_panel.pending=True
                elif sequence==5:command="save_workspace"
            if viewport_smoke and not playback_smoke and not keys_smoke and not layers_smoke and sequence==0 and display_revision==source_revision:
                command="variant\t/World/Placed\tsize\tsmall"
                capture_before=True
        var curve_command=String()
        if ready and len(paths)>0 and ((not smoke and not playing) or keys_smoke or typed_smoke):
            curve_command=curve_panel.update(work,device,paths[selected],source_start+clock*author_rate,source_revision,ack==sequence and command.byte_length()==0)
        if not smoke and curve_command.byte_length()>0:command=curve_command
        if keys_smoke and ready and ack==sequence:
            for i in range(len(paths)):
                if paths[i]=="/Shot":selected=i
            clock=2/rate
            for i in range(len(curve_panel.properties)):
                var fields=curve_panel.properties[i].split("\t")
                if String(fields[1])=="focalLength":curve_panel.selected=i
            if sequence==0 or sequence==2 or sequence==5:
                command="curves\t/Shot\t3"
                curve_panel.pending=True
            elif sequence==1:command="set_key\t/Shot\tfocalLength\t55\t3"
            elif sequence==3:command="delete_key\t/Shot\tfocalLength\t3"
            elif sequence==4:command="undo"
            elif sequence==6:command="save"
        if layers_smoke and ready and ack==sequence:
            if sequence==0:command="create_layer\tAnimation"
            elif sequence==1:command="set_key\t/Shot\tfocalLength\t55\t3"
            elif sequence==2:command="create_layer\tShot"
            elif sequence==3:command="set_key\t/Shot\tfocalLength\t65\t3"
            elif sequence==4:command="select_layer\tAnimation"
            elif sequence==5:command="clear_layer"
            elif sequence==6:command="undo"
            elif sequence==7:command="select_layer\tShot"
            elif sequence==8:command="clear_layer"
            elif sequence==9:command="save"
        if command.byte_length()>0:
            sequence+=1
            atomic_write(work+"/request.tsv",String(sequence)+"\t"+command+"\n")
        device.shadow_begin(Mat4())
        var eye=Vec3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
        var view=Mat4.perspective(1.04719755,Float64(max(1,device.width))/Float64(max(1,device.height)),max(.001,radius*.001),max(100.0,radius*200))*Mat4.look_at(eye,Vec3(0,0,0))
        var render_origin=target
        var exposure: Float64=1
        var bar_x: Float64=0
        var bar_y: Float64=0
        if viewport and authored_camera and len(cameras)>0:
            var camera=cameras[camera_index].copy()
            for track in camera_tracks:
                if track.identity==camera.identity:camera=track.sample(clock)
            var aspect=abs(camera.projection.data[5]/camera.projection.data[0])
            var screen_aspect=Float64(device.width)/Float64(device.height)
            if screen_aspect>aspect:
                camera.projection.data[0]*=aspect/screen_aspect
                bar_x=Float64(device.width)*(1-aspect/screen_aspect)*.5
            else:
                camera.projection.data[5]*=screen_aspect/aspect
                bar_y=Float64(device.height)*(1-screen_aspect/aspect)*.5
            render_origin=camera.position()
            view=camera.view_projection(render_origin)
            eye=Vec3(0,0,0)
            exposure=camera.exposure
        if viewport and authored_lighting and has_lighting:
            var light=AuthoredLightTrack3D.evaluate(light_tracks,lighting,clock)
            light.begin(device,view,eye,exposure=exposure)
            device.local_lights(local_lights,render_origin)
        else:
            device.environment(Environment3D.constant(Vec3(0,0,0)))
            device.local_lights(List[LocalLight3D](),render_origin)
            device.begin(view if viewport else Mat4(),Vec3(.4,1,.8),fog=0)
            device.camera_origin(eye)
            device.lighting(Vec3(.16,.16,.16),Vec3(.12,.12,.12),Vec3(.8,.8,.8),Vec3(.025,.035,.05),exposure)
        if viewport and display_revision>=0:
            var overrides=playback.apply(device,assets,clock)
            assets.draw(device,scene,render_origin,view,overrides=overrides,hidden=VisibilityTrack.hidden(hidden,clock))
        if bar_x>0:
            device.rect(0,0,bar_x,Float64(device.height),Vec3(0,0,0))
            device.rect(Float64(device.width)-bar_x,0,bar_x,Float64(device.height),Vec3(0,0,0))
        if bar_y>0:
            device.rect(0,0,Float64(device.width),bar_y,Vec3(0,0,0))
            device.rect(0,Float64(device.height)-bar_y,Float64(device.width),bar_y,Vec3(0,0,0))
        device.text("USD AUTHORING",20,20,scale=2)
        device.text("UP/DOWN PRIM  TAB VARIANT  LEFT/RIGHT CHOICE",20,56,scale=1)
        device.text("S WORKSPACE SAVE / F9 REOPEN / F6 USD DELIVERY / P USDZ / Z UNDO / Y REDO",20,78,scale=1)
        device.text("W SOURCE COPIES / G SOURCE MAPPING / F7 KEEP COPIES / F8 RELOAD SOURCES",20,96,scale=1)
        if viewport:
            device.rect(16,112,326,600,Vec3(.035,.06,.085))
            device.text("PRIMS",28,124,scale=1)
            var start=max(0,selected-8)
            for i in range(start,min(len(paths),start+16)):
                if i==selected:device.rect(22,Float64(151+(i-start)*22),314,22,Vec3(.12,.25,.32))
                device.text(paths[i]+"  "+types[i],28,156+(i-start)*22,scale=1)
            device.text("B NEW / T TARGET / X CLEAR",28,524,scale=1)
            device.text("TARGET: "+edit_target,28,546,scale=1)
            var layer=0
            for line in lines:
                var f=line.split("\t")
                if len(f)>=2 and String(f[0])=="layer" and layer<5:
                    device.text((String("> ") if len(f)>=4 and String(f[3])=="1" else String("  "))+String(f[1]),28,570+layer*22,scale=1)
                    layer+=1
            device.text("SPACE PLAY / [] FRAME / HOME START / K CAMERA / J LIGHT / N NEXT",364,120,scale=1)
            device.text("TIME "+String(clock)+" / "+String(duration)+"  REV "+String(display_revision),364,144,scale=1)
            device.rect(356,560,908,152,Vec3(.045,.065,.08))
            device.text(preview_status,368,574,scale=1)
            for i in range(min(len(variants),4)):
                var f=variants[i].split("\t")
                device.text((String("> ") if i==variant_index else String("  "))+String(f[2])+" = "+String(f[3]),368,602+i*22,scale=1)
            curve_panel.draw(device)
        else:
            device.rect(16,112,560,600,Vec3(.035,.06,.085))
            device.rect(592,112,672,270,Vec3(.045,.065,.08))
            device.rect(592,398,672,314,Vec3(.04,.055,.075))
            device.text("PRIMS",28,124,scale=1)
            var start=max(0,selected-12)
            for i in range(start,min(len(paths),start+24)):
                if i==selected:device.rect(22,Float64(151+(i-start)*22),548,22,Vec3(.12,.25,.32))
                device.text(paths[i]+"  "+types[i],28,156+(i-start)*22,scale=1)
            device.text("VARIANTS",604,124,scale=1)
            for i in range(min(len(variants),9)):
                var f=variants[i].split("\t")
                device.text((String("> ") if i==variant_index else String("  "))+String(f[2])+" = "+String(f[3]),604,158+i*22,scale=1)
            device.text("LAYERS / B NEW / T TARGET / X CLEAR",604,410,scale=1)
            var layer=0
            for line in lines:
                var f=line.split("\t")
                if len(f)>=2 and String(f[0])=="layer" and layer<11:
                    device.text((String("> ") if len(f)>=4 and String(f[3])=="1" else String("  "))+String(f[1]),604,444+layer*22,scale=1)
                    layer+=1
        if typed_smoke:curve_panel.draw(device)
        device.text("TARGET "+edit_target+" "+edit_context+" / SOURCE CONFLICTS "+String(source_conflicts)+" / ID CONFLICTS "+String(identity_issues),20,732,scale=1)
        device.text((String("WORKSPACE UNSAVED | ") if workspace_dirty else String("WORKSPACE SAVED | "))+status,20,756,scale=1)
        if workspace_smoke and sequence==5 and ack==5:
            if status!="OK open_workspace" or workspace_dirty or edit_target!="Animation" or len(edit_layers)!=3:raise Error("Workspace editor failed: "+status)
            device.snapshot("build/usd-workspace.bmp")
            break
        if typed_smoke and sequence==6 and ack==6:
            if status!="OK save_workspace" or workspace_dirty or len(curve_panel.properties)!=3:raise Error("Typed curve editor failed: "+status)
            device.snapshot("build/usd-channels.bmp")
            break
        if source_smoke and sequence==6 and ack==6:
            if status!="OK open_workspace" or workspace_dirty or edit_target!="working:0" or edit_context!="/Shot":raise Error("Source editor failed: "+status)
            device.snapshot("build/usd-source.bmp")
            break
        if layers_smoke and sequence==10 and ack==10 and display_revision==source_revision:
            if status!="OK save" or edit_target!="Shot" or len(edit_layers)!=3:raise Error("Layer editor failed: "+status)
            device.snapshot("build/usd-layers.bmp")
            break
        if keys_smoke and sequence==7 and ack==7 and display_revision==source_revision:
            if status!="OK save":raise Error("Keyframe editor failed: "+status)
            device.snapshot("build/usd-keyframes.bmp")
            break
        if playback_smoke and display_revision==source_revision:
            device.snapshot("build/usd-playback-"+String(playback_capture)+".bmp")
            playback_capture+=1
            if playback_capture==2:break
        if capture_before:
            device.snapshot("build/usd-viewport-before.bmp")
            capture_before=False
        if viewport_smoke and not playback_smoke and not keys_smoke and not layers_smoke and sequence==1 and ack==1 and display_revision==source_revision:
            device.snapshot("build/usd-viewport-after.bmp")
            break
        if smoke and not viewport_smoke and not workspace_smoke and not source_smoke and not typed_smoke and sequence==4 and ack==4:
            if status!="OK save" or not exists(work+"/last-export.txt"):raise Error("USD editor save failed: "+status)
            device.snapshot("build/usd-editor.bmp")
            break
        device.present()
        frames+=1
        external_call["SDL_Delay",NoneType](UInt32(5))
        if smoke and frames>10000:raise Error("USD editor smoke timed out")
    device.text_input(False)
    assets.close(device)
    worker.close()
    # Only this invocation's protocol files are removed; saved USD remains in output.
    for name in [String("request.tsv"),String("state.tsv"),String("last-export.txt"),String("last-workspace.txt"),String("curves.tsv")]:
        var path=work+"/"+name
        _=external_call["unlink",Int32](path.as_c_string_span())
    _=external_call["rmdir",Int32](work.as_c_string_span())
    if device.validation_errors()!=0:raise Error("USD editor Vulkan validation failed")
    print("USD native editor passed:",device.driver(),"revision acknowledgement",ack)
