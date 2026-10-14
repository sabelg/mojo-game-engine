"""Experimental G01 host owner: fixed buffers, explicit completion/snapshots.

Initial state is uploaded once. Integration and force commands run on device.
Only explicit snapshots return full state; each checked step reads four status bytes.
"""
from max.gpu.host import DeviceContext, DeviceBuffer
from std.collections import List, Array
from std.testing import assert_equal
from mojo_game.rigidbody3d import RigidBody3D, MassProperties3D
from mojo_game.math3d import Vec3
from mojo_game.transform3d import Quaternion
from .core import finite
from .kernels import CAPACITY, STRIDE, FIELDS, WORDS, SENTINEL, STATUS_SENTINEL
from .kernels import integrate_kernel, reduce_status_kernel, commit_kernel, forces_kernel, poses_kernel

def encode(b: RigidBody3D) -> Array[Float64, FIELDS]:
    var result: Array[Float64, FIELDS] = [b.properties.mass,
        b.properties.inertia.x, b.properties.inertia.y, b.properties.inertia.z,
        b.position.x, b.position.y, b.position.z,
        b.orientation.x, b.orientation.y, b.orientation.z, b.orientation.w,
        b.linear_velocity.x, b.linear_velocity.y, b.linear_velocity.z,
        b.angular_velocity.x, b.angular_velocity.y, b.angular_velocity.z,
        b.force.x, b.force.y, b.force.z, b.torque.x, b.torque.y, b.torque.z]
    return result^

struct GpuBatch(Movable):
    var ctx: DeviceContext
    var current: DeviceBuffer[DType.float64]
    var candidate: DeviceBuffer[DType.float64]
    var statuses: DeviceBuffer[DType.int32]
    var summary: DeviceBuffer[DType.int32]
    var poses: DeviceBuffer[DType.float64]
    var count: Int

    def __init__(out self) raises:
        self.ctx = DeviceContext()
        if String(self.ctx.name()) != "NVIDIA GB10":
            raise Error("G01 profile is qualified for NVIDIA GB10 only; no CPU fallback")
        self.current = self.ctx.enqueue_create_buffer[DType.float64](WORDS)
        self.candidate = self.ctx.enqueue_create_buffer[DType.float64](WORDS)
        self.statuses = self.ctx.enqueue_create_buffer[DType.int32](STRIDE)
        self.summary = self.ctx.enqueue_create_buffer[DType.int32](1)
        self.poses = self.ctx.enqueue_create_buffer[DType.float64](2)
        self.count = 0
        self.current.enqueue_fill(SENTINEL)
        self.candidate.enqueue_fill(SENTINEL)
        self.statuses.enqueue_fill(STATUS_SENTINEL)
        self.summary.enqueue_fill(0)
        self.poses.enqueue_fill(SENTINEL)
        self.ctx.synchronize()

    def device(self) raises -> String:
        return String(self.ctx.name())

    def upload(mut self, bodies: List[RigidBody3D]) raises:
        if len(bodies) > CAPACITY:
            raise Error("G01 capacity is 256 bodies")
        for b in bodies:
            b.validate()
        self.ctx.synchronize()
        self.current.enqueue_fill(SENTINEL)
        self.candidate.enqueue_fill(SENTINEL)
        self.statuses.enqueue_fill(STATUS_SENTINEL)
        self.summary.enqueue_fill(0)
        self.count = len(bodies)
        self.poses = self.ctx.enqueue_create_buffer[DType.float64](self.count * 7 + 2)
        self.poses.enqueue_fill(SENTINEL)
        with self.current.map_to_host() as values:
            for i in range(self.count):
                var b = encode(bodies[i])
                for f in range(FIELDS):
                    values[f * STRIDE + i + 1] = b[f]
        self.ctx.synchronize()

    def capacity(self) raises:
        if self.count < 0 or self.count > CAPACITY:
            raise Error("G01 body count outside fixed capacity")

    def forces(mut self, force: Vec3, torque: Vec3 = Vec3(0, 0, 0)) raises:
        self.capacity()
        if not finite(force) or not finite(torque):
            raise Error("G01 force/torque command must be finite")
        if self.count == 0:
            return
        self.ctx.enqueue_function[forces_kernel](self.current, Int32(self.count),
            force.x, force.y, force.z, torque.x, torque.y, torque.z,
            grid_dim=(self.count + 63) // 64, block_dim=64)

    def step(mut self, dt: Float64, gravity: Vec3 = Vec3(0, -9.81, 0),
             ceiling: Float64 = 1.0 / 120) raises -> Int32:
        self.capacity()
        if self.count == 0:
            return 0
        var blocks = (self.count + 63) // 64
        self.ctx.enqueue_function[integrate_kernel](self.current, self.candidate,
            self.statuses, Int32(self.count), dt, gravity.x, gravity.y, gravity.z,
            ceiling, grid_dim=blocks, block_dim=64)
        self.ctx.enqueue_function[reduce_status_kernel](self.statuses, self.summary,
            Int32(self.count), grid_dim=1, block_dim=1)
        self.ctx.enqueue_function[commit_kernel](self.current, self.candidate,
            self.summary, Int32(self.count), grid_dim=blocks, block_dim=64)
        self.ctx.synchronize()
        with self.summary.map_to_host() as status:
            return Int32(status[0])

    def raw(mut self) raises -> List[Float64]:
        self.ctx.synchronize()
        var result = List[Float64]()
        with self.current.map_to_host() as values:
            for i in range(WORDS):
                result.append(Float64(values[i]))
        return result^

    def pose_snapshot(mut self) raises -> List[Float64]:
        self.capacity()
        # Small staged render bridge: seven Float64 values per active body.
        # Includes two canaries; no CUDA-Vulkan zero-copy claim.
        if self.count:
            self.ctx.enqueue_function[poses_kernel](self.current, self.poses,
                Int32(self.count), grid_dim=(self.count + 63) // 64, block_dim=64)
        self.ctx.synchronize()
        var result = List[Float64]()
        with self.poses.map_to_host() as values:
            assert_equal(values[0], SENTINEL)
            assert_equal(values[self.count * 7 + 1], SENTINEL)
            for i in range(self.count * 7):
                result.append(Float64(values[i + 1]))
        return result^

    def inject(mut self, field: Int, body: Int, value: Float64) raises:
        # Qualification-only fault injection; never a public mutable world view.
        if field < 0 or field >= FIELDS or body < 0 or body >= self.count:
            raise Error("G01 fault injection out of range")
        self.ctx.synchronize()
        with self.current.map_to_host() as values:
            values[field * STRIDE + body + 1] = value
        self.ctx.synchronize()

    def canaries(mut self) raises:
        self.ctx.synchronize()
        with self.current.map_to_host() as a, self.candidate.map_to_host() as b:
            for f in range(FIELDS):
                assert_equal(a[f * STRIDE], SENTINEL)
                assert_equal(b[f * STRIDE], SENTINEL)
                for i in range(self.count + 1, STRIDE):
                    assert_equal(a[f * STRIDE + i], SENTINEL)
                    assert_equal(b[f * STRIDE + i], SENTINEL)
        with self.statuses.map_to_host() as status:
            assert_equal(status[0], STATUS_SENTINEL)
            for i in range(self.count + 1, STRIDE):
                assert_equal(status[i], STATUS_SENTINEL)
