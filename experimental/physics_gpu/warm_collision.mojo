"""G03a owned sphere geometry and read-only detection over persistent G02 bodies."""
from max.gpu.host import DeviceBuffer
from std.collections import List
from std.testing import assert_equal
from mojo_game.math3d import Vec3
from mojo_game.transform3d import Quaternion
from .lifecycle import BodyHandle
from .warm_lifecycle import GpuWarmWorld as GpuWorld
from .shape_kernels import *

from .collision import ShapeHandle,SphereCommand,BoxDescriptor,BoxCommand,PairKey,SphereContact,DetectionFrame,read_key
struct GpuWarmCollisionWorld(Movable):
    var bodies: GpuWorld
    var _meta: DeviceBuffer[DType.uint64]
    var _pending: DeviceBuffer[DType.uint64]
    var _values: DeviceBuffer[DType.float64]
    var _pending_values: DeviceBuffer[DType.float64]
    var _diagnostic_meta: DeviceBuffer[DType.uint64]
    var _diagnostic_values: DeviceBuffer[DType.float64]
    var _headers: DeviceBuffer[DType.uint64]
    var _data: DeviceBuffer[DType.float64]
    var _results: DeviceBuffer[DType.uint64]
    var _shape_summary: DeviceBuffer[DType.int32]
    var _bounds: DeviceBuffer[DType.float64]
    var _statuses: DeviceBuffer[DType.int32]
    var _candidate_flags: DeviceBuffer[DType.int32]
    var _contact_flags: DeviceBuffer[DType.int32]
    var _geometry: DeviceBuffer[DType.float64]
    var _pair_out: DeviceBuffer[DType.uint64]
    var _contact_out: DeviceBuffer[DType.uint64]
    var _contact_values: DeviceBuffer[DType.float64]
    var _summary: DeviceBuffer[DType.int32]
    var _pair_limit: Int32
    var _contact_limit: Int32
    var _closed: Bool
    var _epoch: Int64
    var last_error: Int32
    var last_bad_command: Int32
    var logical_shape_command_bytes: Int64

    def __init__(out self,pair_limit: Int32=256,contact_limit: Int32=256) raises:
        if pair_limit<0 or pair_limit>Int32(PAIRS) or contact_limit<0 or contact_limit>Int32(PAIRS):
            raise Error("G03a output capacities must be in [0,2016]")
        self.bodies=GpuWorld()
        self._meta=self.bodies._ctx.enqueue_create_buffer[DType.uint64](META_FIELDS*SHAPE_STRIDE)
        self._pending=self.bodies._ctx.enqueue_create_buffer[DType.uint64](META_FIELDS*SHAPE_STRIDE)
        self._values=self.bodies._ctx.enqueue_create_buffer[DType.float64](VALUE_FIELDS*SHAPE_STRIDE)
        self._pending_values=self.bodies._ctx.enqueue_create_buffer[DType.float64](VALUE_FIELDS*SHAPE_STRIDE)
        self._diagnostic_meta=self.bodies._ctx.enqueue_create_buffer[DType.uint64](META_FIELDS*SHAPE_STRIDE)
        self._diagnostic_values=self.bodies._ctx.enqueue_create_buffer[DType.float64](VALUE_FIELDS*SHAPE_STRIDE)
        self._headers=self.bodies._ctx.enqueue_create_buffer[DType.uint64](SHAPES*7+2)
        self._data=self.bodies._ctx.enqueue_create_buffer[DType.float64](SHAPES*VALUE_FIELDS+2)
        self._results=self.bodies._ctx.enqueue_create_buffer[DType.uint64](SHAPES*4+2)
        self._shape_summary=self.bodies._ctx.enqueue_create_buffer[DType.int32](2)
        self._bounds=self.bodies._ctx.enqueue_create_buffer[DType.float64](SHAPES*BOUNDS_FIELDS+2)
        self._statuses=self.bodies._ctx.enqueue_create_buffer[DType.int32](SHAPE_STRIDE)
        self._candidate_flags=self.bodies._ctx.enqueue_create_buffer[DType.int32](PAIRS+2)
        self._contact_flags=self.bodies._ctx.enqueue_create_buffer[DType.int32](PAIRS+2)
        self._geometry=self.bodies._ctx.enqueue_create_buffer[DType.float64](PAIRS*CONTACT_FIELDS+2)
        self._pair_out=self.bodies._ctx.enqueue_create_buffer[DType.uint64](Int(pair_limit)*PAIR_HEADER+2)
        self._contact_out=self.bodies._ctx.enqueue_create_buffer[DType.uint64](Int(contact_limit)*PAIR_HEADER+2)
        self._contact_values=self.bodies._ctx.enqueue_create_buffer[DType.float64](Int(contact_limit)*CONTACT_FIELDS+2)
        self._summary=self.bodies._ctx.enqueue_create_buffer[DType.int32](4)
        self._pair_limit=pair_limit;self._contact_limit=contact_limit;self._closed=False;self._epoch=0
        self.last_error=0;self.last_bad_command=-1;self.logical_shape_command_bytes=0
        self._meta.enqueue_fill(UInt64.MAX);self._pending.enqueue_fill(UInt64.MAX);self._diagnostic_meta.enqueue_fill(UInt64.MAX)
        self._values.enqueue_fill(POISON);self._pending_values.enqueue_fill(POISON);self._diagnostic_values.enqueue_fill(POISON)
        self._headers.enqueue_fill(UInt64.MAX);self._data.enqueue_fill(POISON);self._results.enqueue_fill(UInt64.MAX)
        self._statuses.enqueue_fill(-98765);self._bounds.enqueue_fill(POISON);self._geometry.enqueue_fill(POISON)
        self._pair_out.enqueue_fill(UInt64.MAX);self._contact_out.enqueue_fill(UInt64.MAX);self._contact_values.enqueue_fill(POISON)
        self.bodies._ctx.enqueue_function[initialize_shapes](self._meta,grid_dim=1,block_dim=64)
        self.bodies._ctx.synchronize()

    def _open(self) raises:
        if self._closed:raise Error("G03a collision world closed")
        self.bodies._open()

    def submit_shapes(mut self,commands: List[SphereCommand]) raises -> List[ShapeHandle]:
        var boxes=List[BoxDescriptor]()
        for _ in commands:boxes.append(BoxDescriptor(Vec3(0,0,0),Quaternion()))
        return self._submit_commands(commands,boxes)

    def submit_boxes(mut self,commands: List[BoxCommand]) raises -> List[ShapeHandle]:
        var shapes=List[SphereCommand]();var boxes=List[BoxDescriptor]()
        for c in commands:
            shapes.append(SphereCommand(c.opcode,c.shape,c.body,BOX,0,c.local_center))
            boxes.append(BoxDescriptor(c.half_extents,c.local_orientation))
        return self._submit_commands(shapes,boxes)

    def _submit_commands(mut self,commands: List[SphereCommand],boxes: List[BoxDescriptor]) raises -> List[ShapeHandle]:
        self._open();var count=len(commands)
        if count>SHAPES:raise Error("G03a shape command capacity is 64")
        with self._headers.map_to_host() as header,self._data.map_to_host() as data:
            for i in range(count):
                var c=commands[i];var extra=boxes[i];var h=1+i*7;var p=1+i*VALUE_FIELDS
                header[h]=c.opcode;header[h+1]=UInt64(c.shape.slot);header[h+2]=c.shape.generation
                header[h+3]=UInt64(c.body.slot);header[h+4]=c.body.generation
                header[h+5]=c.body.owner if c.opcode==ATTACH else c.shape.owner;header[h+6]=c.kind
                data[p]=c.radius;data[p+1]=c.local_center.x;data[p+2]=c.local_center.y;data[p+3]=c.local_center.z
                data[p+4]=extra.half_extents.x;data[p+5]=extra.half_extents.y;data[p+6]=extra.half_extents.z
                data[p+7]=extra.local_orientation.x;data[p+8]=extra.local_orientation.y;data[p+9]=extra.local_orientation.z;data[p+10]=extra.local_orientation.w
        self.logical_shape_command_bytes+=Int64(count)*144
        self.bodies._ctx.enqueue_function[shape_transaction](self._meta,self._values,self._pending,self._pending_values,
            self.bodies._active,self.bodies._generations,self.bodies._namespace,self._headers,self._data,self._results,self._shape_summary,
            Int32(count),grid_dim=1,block_dim=1)
        self.bodies._ctx.synchronize()
        with self._shape_summary.map_to_host() as result:
            self.last_error=Int32(result[0]);self.last_bad_command=Int32(result[1])
        if self.last_error:raise Error("GPU sphere transaction rejected; code="+String(self.last_error))
        var created=List[ShapeHandle]();var has_attach=False
        for c in commands:
            if c.opcode==ATTACH:has_attach=True
        if has_attach:
            with self._results.map_to_host() as results:
                for i in range(count):
                    if commands[i].opcode==ATTACH:created.append(ShapeHandle(Int32(results[1+i*4]),UInt64(results[2+i*4]),UInt64(results[3+i*4])))
        return created^

    def _detect_on_device(mut self) raises -> Tuple[Int,Int]:
        self._open()
        # Empty successful transaction reconciles orphaned body attachments.
        var empty=List[SphereCommand]();_=self.submit_shapes(empty)
        self.bodies._ctx.enqueue_function[prepare_bounds](self.bodies._current,self._meta,self._values,self._bounds,self._statuses,grid_dim=1,block_dim=64)
        self.bodies._ctx.enqueue_function[pair_geometry](self._meta,self._bounds,self._statuses,self._candidate_flags,self._contact_flags,self._geometry,grid_dim=64,block_dim=64)
        self.bodies._ctx.enqueue_function[compact_detection](self._meta,self._statuses,self._candidate_flags,self._contact_flags,self._geometry,self._pair_out,self._contact_out,self._contact_values,self._summary,self._pair_limit,self._contact_limit,grid_dim=1,block_dim=1)
        self.bodies._ctx.synchronize()
        var pairs=Int(0);var contacts=Int(0)
        with self._summary.map_to_host() as summary:
            self.last_error=Int32(summary[0]);pairs=Int(summary[1]);contacts=Int(summary[2])
        if self.last_error:raise Error("GPU detection invalid/overflow; no frame published; code="+String(self.last_error))
        return pairs,contacts

    def detect(mut self) raises -> DetectionFrame:
        var counts=self._detect_on_device();var pairs=counts[0];var contacts=counts[1]
        var candidate_data=List[UInt64]();var contact_data=List[UInt64]();var geometry=List[Float64]()
        with self._pair_out.map_to_host() as a,self._contact_out.map_to_host() as b,self._contact_values.map_to_host() as g:
            assert_equal(a[0],UInt64.MAX);assert_equal(a[Int(self._pair_limit)*PAIR_HEADER+1],UInt64.MAX)
            assert_equal(b[0],UInt64.MAX);assert_equal(b[Int(self._contact_limit)*PAIR_HEADER+1],UInt64.MAX)
            assert_equal(g[0],POISON);assert_equal(g[Int(self._contact_limit)*CONTACT_FIELDS+1],POISON)
            for i in range(pairs*PAIR_HEADER+1):candidate_data.append(UInt64(a[i]))
            for i in range(contacts*PAIR_HEADER+1):contact_data.append(UInt64(b[i]))
            for i in range(contacts*CONTACT_FIELDS+1):geometry.append(Float64(g[i]))
        var candidate_keys=List[PairKey]();var hits=List[SphereContact]()
        for i in range(pairs):candidate_keys.append(read_key(candidate_data,i))
        for i in range(contacts):
            var k=1+i*CONTACT_FIELDS
            hits.append(SphereContact(read_key(contact_data,i),Vec3(geometry[k],geometry[k+1],geometry[k+2]),geometry[k+3],
                Vec3(geometry[k+4],geometry[k+5],geometry[k+6]),Vec3(geometry[k+7],geometry[k+8],geometry[k+9])))
        self._epoch+=1
        return DetectionFrame(candidate_keys^,hits^,self._epoch)

    def debug_registry(mut self) raises -> Tuple[List[UInt64],List[Float64]]:
        self._open()
        self.bodies._ctx.enqueue_function[shape_snapshot](self._meta,self._values,self._diagnostic_meta,self._diagnostic_values,grid_dim=1,block_dim=64)
        self.bodies._ctx.synchronize();var meta=List[UInt64]();var values=List[Float64]()
        with self._diagnostic_meta.map_to_host() as m,self._diagnostic_values.map_to_host() as v:
            for i in range(META_FIELDS*SHAPE_STRIDE):meta.append(UInt64(m[i]))
            for i in range(VALUE_FIELDS*SHAPE_STRIDE):values.append(Float64(v[i]))
        return meta^,values^

    def close(mut self) raises:
        if self._closed:return
        self.bodies.close();self._closed=True
