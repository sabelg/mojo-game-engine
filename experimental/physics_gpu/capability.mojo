from max.gpu.host import DeviceContext
from max.gpu import block_idx, block_dim, thread_idx
from std.memory import Pointer
from std.testing import assert_equal

def probe(output: Pointer[Float64, MutAnyOrigin], count: Int32):
    var i = Int(block_idx.x * block_dim.x + thread_idx.x)
    if i < Int(count):
        output[unsafe_offset=i] = Float64(i) * 2 + 0.5

def main() raises:
    with DeviceContext() as ctx:
        print("Actual GPU device:", ctx.name())
        var output = ctx.enqueue_create_buffer[DType.float64](17)
        output.enqueue_fill(-1)
        ctx.enqueue_function[probe](output, Int32(17), grid_dim=1, block_dim=64)
        ctx.synchronize()
        with output.map_to_host() as values:
            for i in range(17):
                assert_equal(values[i], Float64(i) * 2 + 0.5)
        print("G01 capability passed: actual 64-thread Float64 GPU kernel, 17 guarded outputs")
