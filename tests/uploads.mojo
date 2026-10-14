"""Batch submission, staging accounting and overlapping dynamic vertex updates."""
from std.testing import assert_true,assert_equal
from mojo_game import Graphics3D,Mesh,Mat4,Vec3,Transform3D,Material

def capture(device: Graphics3D,handle: Int,path: String) raises:
    var vp=Mat4.perspective(1.04719755,1.5,.1,100)*Mat4.look_at(Vec3(0,2,5),Vec3(0,0,0))
    var light=Mat4.orthographic(12,.1,50)*Mat4.look_at(Vec3(4,8,4),Vec3(0,0,0))
    device.shadow_begin(light)
    device.shadow(handle,Mat4())
    device.begin(vp)
    device.draw(handle,Mat4(),Material())
    device.snapshot(path)
    device.present()

def main() raises:
    var device=Graphics3D("Atlas upload batches",240,160,True)
    var mesh=Mesh.cube()
    var handles=List[Int]()
    for _ in range(32):handles.append(device.upload(mesh))
    assert_equal(device.upload_stat(1),0.0)
    device.flush_uploads()
    assert_equal(device.upload_stat(1),1.0)
    assert_equal(device.upload_stat(2),64.0)
    assert_true(device.upload_stat(4)>=8*1024*1024)
    assert_true(Float64(device.allocated_bytes())>=device.upload_stat(4))
    var changed=mesh.copy()
    for vertex in range(len(changed.vertices)//8):changed.vertices[vertex*8]+=0.5
    device.update_mesh(handles[0],changed)
    device.update_mesh(handles[0],mesh)
    device.update_mesh(handles[0],changed)
    var reference=device.upload(changed)
    capture(device,handles[0],"build/atlas-upload-updated.bmp")
    capture(device,reference,"build/atlas-upload-reference.bmp")
    for handle in handles:device.release(handle)
    device.release(reference)
    assert_equal(device.validation_errors(),0)
    print("Uploads passed: 64 writes in one GPU batch, staging accounting, overlapping updates, completion-based retirement")
