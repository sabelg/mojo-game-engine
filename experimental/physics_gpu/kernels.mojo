"""G01 bounded SoA kernels. One body per thread; ordered phase launches.

Candidate integration cannot mutate current state. A separate bounded reduction
precedes commit, so any invalid member rejects the entire batch and its forces.
"""
from max.gpu import block_idx, block_dim, thread_idx
from std.memory import Pointer
from std.collections import Array
from mojo_game.math3d import Vec3
from mojo_game.transform3d import Quaternion
from .core import BodyState

comptime CAPACITY = 256
comptime STRIDE = CAPACITY + 2
comptime FIELDS = 23
comptime WORDS = FIELDS * STRIDE
comptime SENTINEL = Float64(-987654321.25)
comptime STATUS_SENTINEL = Int32(-98765)

def at(data: Pointer[Float64, MutAnyOrigin], field: Int, body: Int) -> Float64:
    return data[unsafe_offset=field * STRIDE + body + 1]

def load(data: Pointer[Float64, MutAnyOrigin], i: Int) -> BodyState:
    return BodyState(at(data, 0, i),
        Vec3(at(data, 1, i), at(data, 2, i), at(data, 3, i)),
        Vec3(at(data, 4, i), at(data, 5, i), at(data, 6, i)),
        Quaternion(at(data, 7, i), at(data, 8, i), at(data, 9, i), at(data, 10, i)),
        Vec3(at(data, 11, i), at(data, 12, i), at(data, 13, i)),
        Vec3(at(data, 14, i), at(data, 15, i), at(data, 16, i)),
        Vec3(at(data, 17, i), at(data, 18, i), at(data, 19, i)),
        Vec3(at(data, 20, i), at(data, 21, i), at(data, 22, i)))

def store(data: Pointer[Float64, MutAnyOrigin], i: Int, s: BodyState):
    var v: Array[Float64, FIELDS] = [s.mass, s.inertia.x, s.inertia.y, s.inertia.z,
        s.position.x, s.position.y, s.position.z, s.orientation.x,
        s.orientation.y, s.orientation.z, s.orientation.w,
        s.linear.x, s.linear.y, s.linear.z, s.angular.x, s.angular.y, s.angular.z,
        s.force.x, s.force.y, s.force.z, s.torque.x, s.torque.y, s.torque.z]
    for f in range(FIELDS):
        data[unsafe_offset=f * STRIDE + i + 1] = v[f]

def integrate_kernel(current: Pointer[Float64, MutAnyOrigin],
                     candidate: Pointer[Float64, MutAnyOrigin],
                     statuses: Pointer[Int32, MutAnyOrigin], count: Int32,
                     dt: Float64, gx: Float64, gy: Float64, gz: Float64,
                     ceiling: Float64):
    var i = Int(block_idx.x * block_dim.x + thread_idx.x)
    if i >= Int(count) or i >= CAPACITY:
        return
    var s = load(current, i)
    statuses[unsafe_offset=i + 1] = s.integrate(dt, Vec3(gx, gy, gz), ceiling)
    store(candidate, i, s)

def reduce_status_kernel(statuses: Pointer[Int32, MutAnyOrigin],
                         summary: Pointer[Int32, MutAnyOrigin], count: Int32):
    # Single-thread integer reduction is intentionally tiny and deterministic.
    # Integration remains parallel. No floating-point atomic accumulation.
    if Int(block_idx.x * block_dim.x + thread_idx.x) != 0:
        return
    summary[unsafe_offset=0] = 0
    for i in range(min(Int(count), CAPACITY)):
        if statuses[unsafe_offset=i + 1] != 0:
            summary[unsafe_offset=0] = statuses[unsafe_offset=i + 1]
            return

def commit_kernel(current: Pointer[Float64, MutAnyOrigin],
                  candidate: Pointer[Float64, MutAnyOrigin],
                  summary: Pointer[Int32, MutAnyOrigin], count: Int32):
    var i = Int(block_idx.x * block_dim.x + thread_idx.x)
    if i >= Int(count) or i >= CAPACITY or summary[unsafe_offset=0] != 0:
        return
    for f in range(FIELDS):
        var index = f * STRIDE + i + 1
        current[unsafe_offset=index] = candidate[unsafe_offset=index]

def forces_kernel(current: Pointer[Float64, MutAnyOrigin], count: Int32,
                  fx: Float64, fy: Float64, fz: Float64,
                  tx: Float64, ty: Float64, tz: Float64):
    var i = Int(block_idx.x * block_dim.x + thread_idx.x)
    if i >= Int(count) or i >= CAPACITY:
        return
    current[unsafe_offset=17 * STRIDE + i + 1] = fx
    current[unsafe_offset=18 * STRIDE + i + 1] = fy
    current[unsafe_offset=19 * STRIDE + i + 1] = fz
    current[unsafe_offset=20 * STRIDE + i + 1] = tx
    current[unsafe_offset=21 * STRIDE + i + 1] = ty
    current[unsafe_offset=22 * STRIDE + i + 1] = tz

def poses_kernel(current: Pointer[Float64, MutAnyOrigin],
                 poses: Pointer[Float64, MutAnyOrigin], count: Int32):
    var i = Int(block_idx.x * block_dim.x + thread_idx.x)
    if i >= Int(count) or i >= CAPACITY:
        return
    for f in range(7):
        poses[unsafe_offset=i * 7 + f + 1] = current[unsafe_offset=(f + 4) * STRIDE + i + 1]
