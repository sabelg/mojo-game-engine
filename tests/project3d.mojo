"""Project settings parity and asynchronous shell-free tooling lifecycle."""
from std.testing import assert_equal,assert_true,assert_raises
from std.ffi import external_call
from mojo_game import Project3D,ProjectOperation,WorldStore

def main() raises:
    var folder="build/project-native-"+String(external_call["SDL_GetPerformanceCounter",UInt64]())
    _=external_call["mkdir",Int32](folder.as_c_string_span(),Int(493))
    var project=Project3D("Native settings")
    project.cell_size=64
    project.manifests.append("assets/content/content-assets.atlas")
    project.save(folder)
    var loaded=Project3D.load(folder)
    assert_equal(loaded.name,project.name)
    assert_equal(loaded.cell_size,Float64(64))
    assert_equal(loaded.manifests[0],project.manifests[0])
    project.manifests.append("../escape.atlas")
    with assert_raises():project.save(folder)
    assert_equal(len(Project3D.load(folder).manifests),1)
    var store=WorldStore(folder.copy())
    store.prepare()
    var flags=external_call["fcntl",Int32,num_fixed_args=2](store.lock_fd,Int32(1))
    assert_true((flags&Int32(1))!=0)
    var operation=ProjectOperation()
    var destination=folder+"/created with spaces"
    var arguments: List[String]=["python3","scripts/atlas-project.py","create","--project",destination,"--name","Spawned world"]
    operation.start(arguments^)
    for _ in range(2000):
        if operation.poll():break
        external_call["SDL_Delay",NoneType](UInt32(1))
    assert_equal(operation.pid,Int32(0))
    assert_equal(operation.exit_code,0)
    assert_equal(Project3D.load(destination).name,String("Spawned world"))
    var check: List[String]=["python3","scripts/atlas-project.py","check","--project",destination]
    operation.start(check^)
    var busy: List[String]=["python3","--version"]
    with assert_raises():operation.start(busy^)
    for _ in range(2000):
        if operation.poll():break
        external_call["SDL_Delay",NoneType](UInt32(1))
    assert_equal(operation.exit_code,0)
    print("Project API passed: shared settings, failed save preserves settings, owned argv, asynchronous execution and single operation lifecycle")
