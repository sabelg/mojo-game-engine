
# This suffix is appended to the CPU oracle by qualify-axis-normalization.py.
# The GPU executes production normalization/assembly and rotation. Trig is host
# supplied because this locked NVIDIA backend does not support Float64 sin/cos.
from max.gpu.host import DeviceContext
from max.gpu import block_idx, block_dim, thread_idx
from std.memory import Pointer

comptime INPUT_STRIDE=8
comptime OUTPUT_STRIDE=10
comptime GUARD=Float64(-987654321.25)

def axis_kernel(inputs: Pointer[Float64,MutAnyOrigin],outputs: Pointer[Float64,MutAnyOrigin],count: Int32):
    var i=Int(block_idx.x*block_dim.x+thread_idx.x)
    if i>=Int(count):return
    var k=i*INPUT_STRIDE
    var q=Quaternion._axis_angle_from_sin_cos(Vec3(inputs[unsafe_offset=k],inputs[unsafe_offset=k+1],inputs[unsafe_offset=k+2]),inputs[unsafe_offset=k+3],inputs[unsafe_offset=k+4])
    var v=Vec3(inputs[unsafe_offset=k+5],inputs[unsafe_offset=k+6],inputs[unsafe_offset=k+7])
    var rotated=q.rotate(v)
    var inverse=Quaternion(-q.x,-q.y,-q.z,q.w).rotate(rotated)
    k=1+i*OUTPUT_STRIDE
    outputs[unsafe_offset=k]=q.x;outputs[unsafe_offset=k+1]=q.y;outputs[unsafe_offset=k+2]=q.z;outputs[unsafe_offset=k+3]=q.w
    outputs[unsafe_offset=k+4]=rotated.x;outputs[unsafe_offset=k+5]=rotated.y;outputs[unsafe_offset=k+6]=rotated.z
    outputs[unsafe_offset=k+7]=inverse.x;outputs[unsafe_offset=k+8]=inverse.y;outputs[unsafe_offset=k+9]=inverse.z

def append_input(mut values: List[Float64],axis: Vec3,s: Float64,c: Float64,v: Vec3):
    values.append(axis.x);values.append(axis.y);values.append(axis.z);values.append(s);values.append(c)
    values.append(v.x);values.append(v.y);values.append(v.z)

def main() raises:
    var values=List[Float64]();var expected=List[Vec3]();var original=List[Vec3]();var directions=List[Vec3]()
    for f in fixtures():
        for angle in [Float64(0),Float64(1.5707963267948966),Float64(3.141592653589793),Float64(-.37),Float64(.61)]:
            for v in [Vec3(1,0,0),Vec3(.37,-2,4),Vec3(-5,.7,2.3)]:
                append_input(values,f.axis,sin(angle*.5),cos(angle*.5),v)
                expected.append(oracle(f.direction,v,angle));original.append(v);directions.append(f.direction)
    var finite_count=len(expected);var v=Vec3(.37,-2,4)
    for s in [Float64(.3),Float64("nan"),Float64("inf")]:
        append_input(values,Vec3(-0.0,0,-0.0),s,Float64("nan"),v)
    for value in [Float64("nan"),Float64("inf"),Float64("-inf")]:
        for axis in [Vec3(value,0,0),Vec3(0,value,1),Vec3(1,0,value)]:
            append_input(values,axis,.3,.9,v)
        append_input(values,Vec3(0,0,1),value,.9,v)
        append_input(values,Vec3(0,0,1),.3,value,v)
    var count=len(values)//INPUT_STRIDE
    with DeviceContext() as ctx:
        print("Actual GPU device:",ctx.name())
        var inputs=ctx.enqueue_create_buffer[DType.float64](len(values))
        var outputs=ctx.enqueue_create_buffer[DType.float64](count*OUTPUT_STRIDE+2)
        with inputs.map_to_host() as host:
            for i in range(len(values)):host[i]=values[i]
        outputs.enqueue_fill(GUARD)
        ctx.enqueue_function[axis_kernel](inputs,outputs,Int32(count),grid_dim=(count+63)//64,block_dim=64)
        ctx.synchronize()
        with outputs.map_to_host() as host:
            assert_equal(host[0],GUARD);assert_equal(host[count*OUTPUT_STRIDE+1],GUARD)
            for i in range(count):
                var k=1+i*OUTPUT_STRIDE
                var q=Quaternion(host[k],host[k+1],host[k+2],host[k+3])
                var actual=Vec3(host[k+4],host[k+5],host[k+6])
                if i<finite_count:
                    near(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w,1)
                    vector(actual,expected[i]);near(dot(actual,actual),dot(original[i],original[i]))
                    near(dot(directions[i],actual),dot(directions[i],original[i]))
                    vector(Vec3(host[k+7],host[k+8],host[k+9]),original[i])
                elif i<finite_count+3:
                    assert_equal(q.x,Float64(0));assert_equal(q.y,Float64(0));assert_equal(q.z,Float64(0));assert_equal(q.w,Float64(1))
                    vector(actual,v)
                else:
                    invalid(q)
                    assert_true(actual.x!=actual.x and actual.y!=actual.y and actual.z!=actual.z)
    print("Actual GPU extreme-axis Rodrigues:",finite_count,"rotations, zero/non-finite contract and output/tail guards passed")
