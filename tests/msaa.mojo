from std.ffi import external_call
from mojo_game import Graphics3D,Mesh,Vec3,Mat4,Material

def main() raises:
    var d=Graphics3D("MSAA resolve validation",320,240,True)
    var m=Mesh()
    m.triangle(Vec3(-.83,-.73,-.5),Vec3(.71,-.56,-.5),Vec3(.18,.81,-.5))
    var handle=d.upload(m)
    var samples=external_call["mg_samples",Int32](d.handle.value())
    var first_allocation: UInt64=0
    for pass_index in range(3):
        if pass_index==1:
            if external_call["mg_resize",Int32](d.handle.value(),Int32(333),Int32(251))<0:raise Error("Resize failed")
        if pass_index==2:
            if external_call["mg_resize",Int32](d.handle.value(),Int32(320),Int32(240))<0:raise Error("Restore failed")
        d.shadow_begin(Mat4())
        d.begin(Mat4(),fog=0)
        d.lighting(Vec3(0,0,0),Vec3(0,0,0),Vec3(0,0,0),Vec3(0,0,0))
        d.draw(handle,Mat4(),Material(Vec3(1,0,0),emission=3))
        d.rect(12,12,38,18,Vec3(.1,.8,.2))
        d.snapshot("build/msaa-"+String(samples)+"-"+String(pass_index)+".bmp")
        var allocated=external_call["mg_allocated_bytes",UInt64](d.handle.value())
        if pass_index==0:first_allocation=allocated
        if pass_index==2 and allocated!=first_allocation:raise Error("MSAA resize leaked an allocation")
        if d.validation_errors()>0:raise Error("MSAA validation failed")
    print("MSAA samples",samples,"resolve and resize passed; Vulkan allocation bytes",external_call["mg_allocated_bytes",UInt64](d.handle.value()))
