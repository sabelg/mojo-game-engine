"""Mojo Vulkan/SDL runtime with the existing public engine ABI.

Foreign pointers are stored as addresses in POD descriptors. Explicit uses
(and aggregate transfers to _) retain stack storage through the last FFI
call; removing those lifetime anchors can invalidate descriptor pointers.
SDL callbacks access one synchronized process state, owned by the pinned
Mojo compiler runtime and shared with the main thread.
"""
from native.mojo.runtime_support import *
from native.mojo.shaders import *
from std.collections import Array
from std.sys import size_of
from std.ffi import external_call
from std.math import isfinite, sqrt, sin, cos, ceil


from native.mojo.abi import *
from native.mojo.frames import frame_prepare,frame_capture,frame_drop
from native.mojo.uploads import stage_mesh,upload_flush as flush_upload_batch,uploads_drop as drop_upload_slots,completion_poll,BufferAllocator,BufferDropper,upload_stat

def port_state_init() abi("C") -> UInt64:
    var p = c_nullable_address(external_call["calloc", CPointer](UInt64(1), UInt64(size_of[PortGlobals]())))
    c_ref[PortGlobals](p)[].master_gain = Float32(1)
    c_ref[PortGlobals](p)[].music_gain = Float32(.7)
    c_ref[PortGlobals](p)[].effects_gain = Float32(1)
    return p
def port_state_drop(p: UInt64) abi("C"):
    external_call["free", NoneType](c_pointer(p))
def port_globals() -> UInt64:
    var initialize: def() abi("C") thin -> UInt64 = port_state_init
    var destroy: def(UInt64) abi("C") thin = port_state_drop
    return external_call["KGEN_CompilerRT_GetOrCreateGlobal", UInt64](c_literal_167(), UInt64(26), Pointer(to=initialize).unsafe_bitcast[CRawPointer]()[], Pointer(to=destroy).unsafe_bitcast[CRawPointer]()[])


@export("mg_error")
def mg_error() abi("C") -> UInt64:
    var process_state = port_globals()
    var c_temp_1 = UInt64(c_address(Pointer(to=c_ref[PortGlobals](process_state)[].error_text)))
    return c_temp_1

def fail(var message: UInt64) -> Int32:
    var process_state = port_globals()
    _ = external_call["snprintf", Int32, num_fixed_args=3](c_pointer(UInt64(c_address(Pointer(to=c_ref[PortGlobals](process_state)[].error_text)))), UInt64(UInt64(size_of[Array[Int8, 4096]]())), c_pointer(UInt64(c_literal_0())), c_pointer(UInt64(message)))
    var c_temp_2 = Int32((-1))
    return c_temp_2

def c_result(var r: Int32, var operation: UInt64) -> Int32:
    var process_state = port_globals()
    if Bool((Int32(r) == Int32(0))):
        var c_temp_3 = Int32(0)
        return c_temp_3
    _ = external_call["snprintf", Int32, num_fixed_args=3](c_pointer(UInt64(c_address(Pointer(to=c_ref[PortGlobals](process_state)[].error_text)))), UInt64(UInt64(size_of[Array[Int8, 4096]]())), c_pointer(UInt64(c_literal_1())), c_pointer(UInt64(operation)), Int32(r))
    var c_temp_4 = Int32((-1))
    return c_temp_4

def debug_message(var severity: Int32, var c_type: UInt32, var data: UInt64, var user: UInt64) abi("C") -> UInt32:
    _ = c_type
    var g_5: UInt64 = UInt64(user)
    if Bool((Int32(severity) & Int32(4096))):
        c_ref[Graphics](g_5)[].validation_errors += 1
    _ = port_log(c_literal_2(), c_ref[VkDebugUtilsMessengerCallbackDataEXT](data)[].pMessage)
    var c_temp_6 = UInt32(0)
    return c_temp_6

def memory_type(var g: UInt64, var bits: UInt32, var properties: UInt32, var c_index: UInt64) -> Int32:
    var i_7: UInt32 = UInt32(0)
    while Bool((UInt32(i_7) < UInt32(c_ref[Graphics](g)[].memory.memoryTypeCount))):
        if Bool((Bool((UInt32(bits) & UInt32((UInt32(1) << UInt32(i_7))))) and Bool((UInt32((UInt32(c_ref[Graphics](g)[].memory.memoryTypes[Int(i_7)].propertyFlags) & UInt32(properties))) == UInt32(properties))))):
            c_ref[UInt32](c_index)[] = UInt32(i_7)
            var c_temp_8 = Int32(0)
            return c_temp_8
        i_7 += 1
    var c_temp_9 = Int32(fail(UInt64(c_literal_3())))
    return c_temp_9

def buffer_drop(var g: UInt64, var b: UInt64):
    if pool_page(g,b)>=0:
        pool_retire(g,b)
        _=external_call["memset",CPointer](c_pointer(b),Int32(0),UInt64(size_of[Buffer]()))
        return
    # Individual mesh allocations remain a supported comparison path. Their
    # backing memory has no pool retirement record, so wait for every frame and
    # queued copy before freeing it. The default pooled path stays asynchronous.
    var mesh_start=c_address(Pointer(to=c_ref[Graphics](g)[].meshes))
    if b>=mesh_start and b<mesh_start+UInt64(size_of[Array[Mesh,4096]]()) and c_ref[Buffer](b)[].buffer:
        _=upload_flush(g)
        _=external_call["vkDeviceWaitIdle",Int32](c_pointer(c_ref[Graphics](g)[].device))
    if Bool(c_ref[Buffer](b)[].mapped):
        external_call["vkUnmapMemory", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Buffer](b)[].memory)))
    if Bool(c_ref[Buffer](b)[].buffer):
        external_call["vkDestroyBuffer", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Buffer](b)[].buffer)), c_pointer(UInt64(UInt64(0))))
    if Bool(c_ref[Buffer](b)[].memory):
        external_call["vkFreeMemory", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Buffer](b)[].memory)), c_pointer(UInt64(UInt64(0))))
    _ = c_nullable_address(external_call["memset", CPointer](c_pointer(UInt64(b)), Int32(0), UInt64(UInt64(size_of[Buffer]()))))

def buffer_make(var g: UInt64, var b: UInt64, var size: UInt64, var usage: UInt32, device_local: Bool=False) -> Int32:
    var info_10 = VkBufferCreateInfo()
    info_10.sType = Int32(12)
    info_10.size = UInt64(size)
    info_10.usage = UInt32(usage) | (UInt32(2) if device_local else UInt32(0))
    info_10.sharingMode = Int32(0)
    if Bool((Int32(c_result(Int32(external_call["vkCreateBuffer", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=info_10)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Buffer](b)[].buffer)))))), UInt64(c_literal_4()))) < Int32(0))):
        var c_temp_11 = Int32((-1))
        _ = b
        _ = info_10^
        return c_temp_11
    var req_12 = VkMemoryRequirements()
    external_call["vkGetBufferMemoryRequirements", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Buffer](b)[].buffer)), c_pointer(UInt64(c_address(Pointer(to=req_12)))))
    var c_type_13: UInt32 = UInt32(0)
    if Bool((Int32(memory_type(UInt64(g), UInt32(req_12.memoryTypeBits), (UInt32(1) if device_local else UInt32(6)), UInt64(c_address(Pointer(to=c_type_13))))) < Int32(0))):
        var c_temp_14 = Int32((-1))
        _ = b
        _ = info_10^
        _ = req_12^
        _ = c_type_13
        return c_temp_14
    var allocation_15 = VkMemoryAllocateInfo()
    allocation_15.sType = Int32(5)
    allocation_15.allocationSize = UInt64(req_12.size)
    allocation_15.memoryTypeIndex = UInt32(c_type_13)
    if Bool((Int32(c_result(Int32(external_call["vkAllocateMemory", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=allocation_15)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Buffer](b)[].memory)))))), UInt64(c_literal_5()))) < Int32(0))):
        var c_temp_16 = Int32((-1))
        _ = b
        _ = info_10^
        _ = req_12^
        _ = c_type_13
        _ = allocation_15^
        return c_temp_16
    c_ref[Buffer](b)[].allocated = UInt64(req_12.size)
    if Bool((Int32(c_result(Int32(external_call["vkBindBufferMemory", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Buffer](b)[].buffer)), c_pointer(UInt64(c_ref[Buffer](b)[].memory)), UInt64(0))), UInt64(c_literal_6()))) < Int32(0))):
        var c_temp_17 = Int32((-1))
        _ = b
        _ = info_10^
        _ = req_12^
        _ = c_type_13
        _ = allocation_15^
        return c_temp_17
    c_ref[Buffer](b)[].size = UInt64(size)
    if not device_local:
        if Bool((Int32(c_result(Int32(external_call["vkMapMemory", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Buffer](b)[].memory)), UInt64(0), UInt64((~0)), UInt32(0), c_pointer(UInt64(c_address(Pointer(to=c_ref[Buffer](b)[].mapped)))))), UInt64(c_literal_7()))) < Int32(0))):
            var c_temp_18 = Int32((-1))
            _ = b
            _ = info_10^
            _ = req_12^
            _ = c_type_13
            _ = allocation_15^
            return c_temp_18
    var c_temp_19 = Int32(0)
    _ = b
    _ = info_10^
    _ = req_12^
    _ = c_type_13
    _ = allocation_15^
    return c_temp_19

def buffer_write(var g: UInt64, var b: UInt64, var data: UInt64, var size: UInt64, offset: UInt64=0) -> Int32:
    if Bool((UInt64(size) > UInt64(c_ref[Buffer](b)[].size))):
        var c_temp_20 = Int32(fail(UInt64(c_literal_8())))
        return c_temp_20
    var page=pool_page(g,b)
    if page>=0 and not c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].pages[page].mapped:
        return mesh_stage(g,b,data,size)
    var bank=UInt64(0)
    if c_ref[Graphics](g)[].scalability:
        var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
        if b==c_address(Pointer(to=c_ref[Graphics](g)[].uniform)):bank=UInt64(state[].frame_index)*state[].uniform_stride
        elif b==c_address(Pointer(to=c_ref[Graphics](g)[].overlay_buffer)):bank=UInt64(state[].frame_index)*state[].overlay_stride
        elif b==c_address(Pointer(to=state[].instance_buffer)):bank=UInt64(state[].frame_index)*state[].instance_stride
        elif b==c_address(Pointer(to=state[].skin_buffer)):bank=UInt64(state[].frame_index)*UInt64(16*1024*1024)
    bank+=offset
    if bank>c_ref[Buffer](b)[].size or size>c_ref[Buffer](b)[].size-bank:return fail(c_literal_8())
    _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_ref[Buffer](b)[].mapped)+bank), c_pointer(UInt64(data)), UInt64(size)))
    if page>=0:
        var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
        state[].upload_bytes+=size
        state[].upload_copies+=1
    var c_temp_21 = Int32(0)
    return c_temp_21

def image_drop(var g: UInt64, var i: UInt64):
    if Bool(c_ref[Image](i)[].view):
        external_call["vkDestroyImageView", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Image](i)[].view)), c_pointer(UInt64(UInt64(0))))
    if Bool(c_ref[Image](i)[].image):
        external_call["vkDestroyImage", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Image](i)[].image)), c_pointer(UInt64(UInt64(0))))
    if Bool(c_ref[Image](i)[].memory):
        external_call["vkFreeMemory", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Image](i)[].memory)), c_pointer(UInt64(UInt64(0))))
    _ = c_nullable_address(external_call["memset", CPointer](c_pointer(UInt64(i)), Int32(0), UInt64(UInt64(size_of[Image]()))))

def image_make_samples(var g: UInt64, var image: UInt64, var w: UInt32, var h: UInt32, var levels: UInt32, var c_format: Int32, var usage: UInt32, var aspect: UInt32, var samples: Int32) -> Int32:
    c_ref[Image](image)[].levels = UInt32(levels)
    var info_22 = VkImageCreateInfo()
    info_22.sType = Int32(14)
    info_22.imageType = Int32(1)
    info_22.c_format = Int32(c_format)
    info_22.extent.width = UInt32(w)
    info_22.extent.height = UInt32(h)
    info_22.extent.depth = UInt32(1)
    info_22.mipLevels = UInt32(levels)
    info_22.arrayLayers = UInt32(1)
    info_22.samples = Int32(samples)
    info_22.tiling = Int32(0)
    info_22.usage = UInt32(usage)
    info_22.sharingMode = Int32(0)
    info_22.initialLayout = Int32(0)
    if Bool((Int32(c_result(Int32(external_call["vkCreateImage", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=info_22)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Image](image)[].image)))))), UInt64(c_literal_9()))) < Int32(0))):
        var c_temp_23 = Int32((-1))
        _ = image
        _ = info_22^
        return c_temp_23
    var req_24 = VkMemoryRequirements()
    external_call["vkGetImageMemoryRequirements", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Image](image)[].image)), c_pointer(UInt64(c_address(Pointer(to=req_24)))))
    var c_type_25: UInt32 = UInt32(0)
    if Bool((Int32(memory_type(UInt64(g), UInt32(req_24.memoryTypeBits), UInt32(1), UInt64(c_address(Pointer(to=c_type_25))))) < Int32(0))):
        var c_temp_26 = Int32((-1))
        _ = image
        _ = info_22^
        _ = req_24^
        _ = c_type_25
        return c_temp_26
    var allocation_27 = VkMemoryAllocateInfo()
    allocation_27.sType = Int32(5)
    allocation_27.allocationSize = UInt64(req_24.size)
    allocation_27.memoryTypeIndex = UInt32(c_type_25)
    if Bool((Int32(c_result(Int32(external_call["vkAllocateMemory", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=allocation_27)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Image](image)[].memory)))))), UInt64(c_literal_10()))) < Int32(0))):
        var c_temp_28 = Int32((-1))
        _ = image
        _ = info_22^
        _ = req_24^
        _ = c_type_25
        _ = allocation_27^
        return c_temp_28
    c_ref[Image](image)[].allocated = UInt64(req_24.size)
    if Bool((Int32(c_result(Int32(external_call["vkBindImageMemory", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Image](image)[].image)), c_pointer(UInt64(c_ref[Image](image)[].memory)), UInt64(0))), UInt64(c_literal_11()))) < Int32(0))):
        var c_temp_29 = Int32((-1))
        _ = image
        _ = info_22^
        _ = req_24^
        _ = c_type_25
        _ = allocation_27^
        return c_temp_29
    var view_30 = VkImageViewCreateInfo()
    view_30.sType = Int32(15)
    view_30.image = UInt64(c_ref[Image](image)[].image)
    view_30.viewType = Int32(1)
    view_30.c_format = Int32(c_format)
    view_30.subresourceRange.aspectMask = UInt32(aspect)
    view_30.subresourceRange.baseMipLevel = UInt32(0)
    view_30.subresourceRange.levelCount = UInt32(levels)
    view_30.subresourceRange.baseArrayLayer = UInt32(0)
    view_30.subresourceRange.layerCount = UInt32(1)
    if Bool((Int32(c_result(Int32(external_call["vkCreateImageView", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=view_30)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Image](image)[].view)))))), UInt64(c_literal_12()))) < Int32(0))):
        var c_temp_31 = Int32((-1))
        _ = image
        _ = info_22^
        _ = req_24^
        _ = c_type_25
        _ = allocation_27^
        _ = view_30^
        return c_temp_31
    var c_temp_32 = Int32(0)
    _ = image
    _ = info_22^
    _ = req_24^
    _ = c_type_25
    _ = allocation_27^
    _ = view_30^
    return c_temp_32

def image_make(var g: UInt64, var image: UInt64, var w: UInt32, var h: UInt32, var levels: UInt32, var c_format: Int32, var usage: UInt32, var aspect: UInt32) -> Int32:
    var c_temp_33 = Int32(image_make_samples(UInt64(g), UInt64(image), UInt32(w), UInt32(h), UInt32(levels), Int32(c_format), UInt32(usage), UInt32(aspect), Int32(1)))
    return c_temp_33

def barrier(var g: UInt64, var image: UInt64, var aspect: UInt32, var level: UInt32, var c_count: UInt32, var old: Int32, var c_next: Int32, var src: UInt32, var dst: UInt32, var c_read: UInt32, var write: UInt32):
    var b_34 = VkImageMemoryBarrier()
    b_34.sType = Int32(45)
    b_34.srcAccessMask = UInt32(c_read)
    b_34.dstAccessMask = UInt32(write)
    b_34.oldLayout = Int32(old)
    b_34.newLayout = Int32(c_next)
    b_34.srcQueueFamilyIndex = UInt32((~0))
    b_34.dstQueueFamilyIndex = UInt32((~0))
    b_34.image = UInt64(image)
    b_34.subresourceRange.aspectMask = UInt32(aspect)
    b_34.subresourceRange.baseMipLevel = UInt32(level)
    b_34.subresourceRange.levelCount = UInt32(c_count)
    b_34.subresourceRange.baseArrayLayer = UInt32(0)
    b_34.subresourceRange.layerCount = UInt32(1)
    external_call["vkCmdPipelineBarrier", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), UInt32(src), UInt32(dst), UInt32(0), UInt32(0), c_pointer(UInt64(UInt64(0))), UInt32(0), c_pointer(UInt64(UInt64(0))), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=b_34)))))
    _ = b_34^

def command_begin(var g: UInt64) -> Int32:
    if c_ref[Graphics](g)[].scalability and upload_flush(g)<0:return -1
    var began_35: Float64 = Float64(milliseconds())
    if Bool((Int32(c_result(Int32(external_call["vkWaitForFences", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].fence)))), UInt32(1), UInt64(18446744073709551615))), UInt64(c_literal_13()))) < Int32(0))):
        var c_temp_36 = Int32((-1))
        _ = g
        return c_temp_36
    c_ref[Graphics](g)[].detail_ms[Int(0)] += Float64((Float64(milliseconds()) - Float64(began_35)))
    if Bool((Int32(c_result(Int32(external_call["vkResetCommandBuffer", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].command)), UInt32(0))), UInt64(c_literal_14()))) < Int32(0))):
        var c_temp_37 = Int32((-1))
        _ = g
        return c_temp_37
    pool_reclaim(g)
    var begin_38 = VkCommandBufferBeginInfo()
    begin_38.sType = Int32(42)
    begin_38.flags = UInt32(1)
    if Bool((Int32(c_result(Int32(external_call["vkBeginCommandBuffer", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_address(Pointer(to=begin_38)))))), UInt64(c_literal_15()))) < Int32(0))):
        var c_temp_39 = Int32((-1))
        _ = g
        _ = begin_38^
        return c_temp_39
    var c_temp_40 = Int32(0)
    _ = g
    _ = begin_38^
    return c_temp_40

def command_submit_mode(var g: UInt64, var wait: UInt64, var signal: UInt64, var complete: Int32) -> Int32:
    if Bool((Int32(c_result(Int32(external_call["vkEndCommandBuffer", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].command)))), UInt64(c_literal_16()))) < Int32(0))):
        var c_temp_41 = Int32((-1))
        return c_temp_41
    var stage_42: UInt32 = UInt32(4096)
    var submit_43 = VkSubmitInfo()
    submit_43.sType = Int32(4)
    submit_43.waitSemaphoreCount = UInt32((Int32(1) if Bool(wait) else Int32(0)))
    submit_43.pWaitSemaphores = UInt64((UInt64(c_address(Pointer(to=wait))) if Bool(wait) else UInt64(UInt64(0))))
    submit_43.pWaitDstStageMask = UInt64((UInt64(c_address(Pointer(to=stage_42))) if Bool(wait) else UInt64(UInt64(0))))
    submit_43.commandBufferCount = UInt32(1)
    submit_43.pCommandBuffers = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].command)))
    submit_43.signalSemaphoreCount = UInt32((Int32(1) if Bool(signal) else Int32(0)))
    submit_43.pSignalSemaphores = UInt64((UInt64(c_address(Pointer(to=signal))) if Bool(signal) else UInt64(UInt64(0))))
    if Bool((Int32(c_result(Int32(external_call["vkResetFences", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].fence)))))), UInt64(c_literal_17()))) < Int32(0))):
        var c_temp_44 = Int32((-1))
        _ = g
        _ = wait
        _ = signal
        _ = stage_42
        return c_temp_44
    var began_45: Float64 = Float64(milliseconds())
    var status_46: Int32 = Int32(external_call["vkQueueSubmit", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].queue)), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=submit_43)))), c_pointer(UInt64(c_ref[Graphics](g)[].fence))))
    c_ref[Graphics](g)[].detail_ms[Int(1)] += Float64((Float64(milliseconds()) - Float64(began_45)))
    if Bool((Int32(status_46) != Int32(0))):
        external_call["vkDestroyFence", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].fence)), c_pointer(UInt64(UInt64(0))))
        c_ref[Graphics](g)[].fence = UInt64(0)
        var info_47 = VkFenceCreateInfo()
        info_47.sType = Int32(8)
        info_47.flags = UInt32(1)
        _ = external_call["vkCreateFence", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=info_47)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].fence)))))
        if c_ref[Graphics](g)[].scalability and c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].frames_initialized:
            frame_capture(g,Int(c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].frame_index))
        var c_temp_48 = Int32(c_result(Int32(status_46), UInt64(c_literal_18())))
        _ = g
        _ = wait
        _ = signal
        _ = stage_42
        _ = submit_43^
        _ = info_47^
        return c_temp_48
    if c_ref[Graphics](g)[].scalability:
        var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
        state[].submit_serial+=1
        state[].frame_serial=state[].submit_serial
        if state[].frames_initialized:frame_capture(g,Int(state[].frame_index))
    if Bool(complete):
        began_45 = Float64(milliseconds())
        if Bool((Int32(c_result(Int32(external_call["vkWaitForFences", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].fence)))), UInt32(1), UInt64(18446744073709551615))), UInt64(c_literal_13()))) < Int32(0))):
            var c_temp_49 = Int32((-1))
            _ = g
            _ = wait
            _ = signal
            _ = stage_42
            _ = submit_43^
            return c_temp_49
        c_ref[Graphics](g)[].detail_ms[Int(2)] += Float64((Float64(milliseconds()) - Float64(began_45)))
    var c_temp_50 = Int32(0)
    _ = g
    _ = wait
    _ = signal
    _ = stage_42
    _ = submit_43^
    return c_temp_50

def command_submit(var g: UInt64, var wait: UInt64, var signal: UInt64) -> Int32:
    var c_temp_51 = Int32(command_submit_mode(UInt64(g), UInt64(wait), UInt64(signal), Int32(1)))
    return c_temp_51

def milliseconds() -> Float64:
    var c_temp_52 = Float64((Float64((Float64(Float64(external_call["SDL_GetPerformanceCounter", UInt64]())) * Float64(1000.0))) / Float64(Float64(external_call["SDL_GetPerformanceFrequency", UInt64]()))))
    return c_temp_52

def passes_make(var g: UInt64) -> Int32:
    var depth_53 = VkAttachmentDescription()
    depth_53.c_format = Int32(126)
    depth_53.samples = Int32(1)
    depth_53.loadOp = Int32(1)
    depth_53.storeOp = Int32(0)
    depth_53.stencilLoadOp = Int32(2)
    depth_53.stencilStoreOp = Int32(1)
    depth_53.initialLayout = Int32(0)
    depth_53.finalLayout = Int32(4)
    var dr_54 = VkAttachmentReference()
    dr_54.attachment = UInt32(0)
    dr_54.layout = Int32(3)
    var sub_55 = VkSubpassDescription()
    sub_55.pipelineBindPoint = Int32(0)
    sub_55.pDepthStencilAttachment = UInt64(c_address(Pointer(to=dr_54)))
    var deps_56 = Array[VkSubpassDependency, 2](fill=VkSubpassDependency())
    deps_56[0].srcSubpass = UInt32((~0))
    deps_56[0].dstSubpass = UInt32(0)
    deps_56[0].srcStageMask = UInt32(128)
    deps_56[0].dstStageMask = UInt32((Int32(256) | Int32(512)))
    deps_56[0].srcAccessMask = UInt32(32)
    deps_56[0].dstAccessMask = UInt32(1024)
    deps_56[1].srcSubpass = UInt32(0)
    deps_56[1].dstSubpass = UInt32((~0))
    deps_56[1].srcStageMask = UInt32((Int32(256) | Int32(512)))
    deps_56[1].dstStageMask = UInt32(128)
    deps_56[1].srcAccessMask = UInt32(1024)
    deps_56[1].dstAccessMask = UInt32(32)
    var info_57 = VkRenderPassCreateInfo()
    info_57.sType = Int32(38)
    info_57.attachmentCount = UInt32(1)
    info_57.pAttachments = UInt64(c_address(Pointer(to=depth_53)))
    info_57.subpassCount = UInt32(1)
    info_57.pSubpasses = UInt64(c_address(Pointer(to=sub_55)))
    info_57.dependencyCount = UInt32(2)
    info_57.pDependencies = UInt64(c_address(Pointer(to=deps_56)))
    if Bool((Int32(c_result(Int32(external_call["vkCreateRenderPass", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=info_57)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].shadow_pass)))))), UInt64(c_literal_19()))) < Int32(0))):
        var c_temp_58 = Int32((-1))
        _ = g
        _ = depth_53^
        _ = dr_54^
        _ = sub_55^
        _ = deps_56^
        _ = info_57^
        return c_temp_58
    var attachments_59 = Array[VkAttachmentDescription, 3](fill=VkAttachmentDescription())
    attachments_59[0].c_format = Int32(37)
    attachments_59[0].samples = Int32(1)
    attachments_59[0].loadOp = Int32(1)
    attachments_59[0].storeOp = Int32(0)
    attachments_59[0].stencilLoadOp = Int32(2)
    attachments_59[0].stencilStoreOp = Int32(1)
    attachments_59[0].initialLayout = Int32(0)
    attachments_59[0].finalLayout = Int32(6)
    attachments_59[1] = (depth_53).copy()
    attachments_59[Int(1)].finalLayout = Int32(3)
    attachments_59[Int(1)].storeOp = Int32(0)
    var resolve_60 = VkAttachmentReference()
    resolve_60.attachment = UInt32(2)
    resolve_60.layout = Int32(2)
    if Bool((Int32(c_ref[Graphics](g)[].samples) != Int32(1))):
        attachments_59[Int(2)] = (attachments_59[Int(0)]).copy()
        attachments_59[Int(2)].loadOp = Int32(2)
        attachments_59[Int(0)].samples = Int32(c_set[DType.int32](c_address(Pointer(to=attachments_59[Int(1)].samples)), Int32(c_ref[Graphics](g)[].samples)))
        attachments_59[Int(0)].storeOp = Int32(0)
        attachments_59[Int(0)].finalLayout = Int32(2)
        sub_55.pResolveAttachments = UInt64(c_address(Pointer(to=resolve_60)))
    var cr_61 = VkAttachmentReference()
    cr_61.attachment = UInt32(0)
    cr_61.layout = Int32(2)
    dr_54.attachment = UInt32(1)
    sub_55.colorAttachmentCount = UInt32(1)
    sub_55.pColorAttachments = UInt64(c_address(Pointer(to=cr_61)))
    var c_temp_62 = VkSubpassDependency()
    c_temp_62.srcSubpass = UInt32((~0))
    c_temp_62.dstSubpass = UInt32(0)
    c_temp_62.srcStageMask = UInt32((Int32(4096) | Int32(512)))
    c_temp_62.dstStageMask = UInt32((Int32(1024) | Int32(256)))
    c_temp_62.srcAccessMask = UInt32((Int32(2048) | Int32(1024)))
    c_temp_62.dstAccessMask = UInt32((Int32(256) | Int32(1024)))
    deps_56[Int(0)] = (c_temp_62).copy()
    var c_temp_63 = VkSubpassDependency()
    c_temp_63.srcSubpass = UInt32(0)
    c_temp_63.dstSubpass = UInt32((~0))
    c_temp_63.srcStageMask = UInt32(1024)
    c_temp_63.dstStageMask = UInt32(4096)
    c_temp_63.srcAccessMask = UInt32(256)
    c_temp_63.dstAccessMask = UInt32(2048)
    deps_56[Int(1)] = (c_temp_63).copy()
    deps_56[Int(0)].srcStageMask |= UInt32(1024)
    deps_56[Int(0)].srcAccessMask |= UInt32(256)
    deps_56[Int(0)].dstAccessMask |= UInt32((Int32(128) | Int32(512)))
    info_57.attachmentCount = UInt32((Int32(2) if Bool((Int32(c_ref[Graphics](g)[].samples) == Int32(1))) else Int32(3)))
    info_57.pAttachments = UInt64(c_address(Pointer(to=attachments_59)))
    if Bool((Int32(c_result(Int32(external_call["vkCreateRenderPass", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=info_57)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].color_pass)))))), UInt64(c_literal_20()))) < Int32(0))):
        var c_temp_64 = Int32((-1))
        _ = g
        _ = depth_53^
        _ = dr_54^
        _ = sub_55^
        _ = deps_56^
        _ = info_57^
        _ = attachments_59^
        _ = resolve_60^
        _ = cr_61^
        return c_temp_64
    var hdr_state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    attachments_59[0].c_format=97
    attachments_59[2].c_format=97
    if c_result(external_call["vkCreateRenderPass",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_address(Pointer(to=info_57))),c_pointer(0),c_pointer(c_address(Pointer(to=hdr_state[].hdr_pass)))),c_literal_20())<0:return -1
    attachments_59[0].c_format=37
    attachments_59[2].c_format=37
    attachments_59[Int(0)].loadOp = Int32(c_set[DType.int32](c_address(Pointer(to=attachments_59[Int(1)].loadOp)), Int32(0)))
    attachments_59[Int(0)].initialLayout = Int32((Int32(6) if Bool((Int32(c_ref[Graphics](g)[].samples) == Int32(1))) else Int32(2)))
    attachments_59[Int(1)].initialLayout = Int32(3)
    if Bool((Int32(c_ref[Graphics](g)[].samples) != Int32(1))):
        attachments_59[Int(2)].initialLayout = Int32(6)
    if Bool((Int32(c_result(Int32(external_call["vkCreateRenderPass", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=info_57)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].water_pass)))))), UInt64(c_literal_21()))) < Int32(0))):
        var c_temp_65 = Int32((-1))
        _ = g
        _ = depth_53^
        _ = dr_54^
        _ = sub_55^
        _ = deps_56^
        _ = info_57^
        _ = attachments_59^
        _ = resolve_60^
        _ = cr_61^
        return c_temp_65
    attachments_59[0].c_format=97
    attachments_59[2].c_format=97
    if c_result(external_call["vkCreateRenderPass",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_address(Pointer(to=info_57))),c_pointer(0),c_pointer(c_address(Pointer(to=hdr_state[].hdr_water_pass)))),c_literal_21())<0:return -1
    if display_pass_make(g)<0:return -1
    var c_temp_66 = Int32(0)
    _ = g
    _ = depth_53^
    _ = dr_54^
    _ = sub_55^
    _ = deps_56^
    _ = info_57^
    _ = attachments_59^
    _ = resolve_60^
    _ = cr_61^
    return c_temp_66

def pipeline_make(var g: UInt64, var pipeline: UInt64, var kind: Int32, var vs: UInt64, var vs_size: UInt64, var fs: UInt64, var fs_size: UInt64) -> Int32:
    var depth_only_67: Int32 = Int32((Bool((Int32(kind) == Int32(1))) or Bool((Int32(kind) == Int32(3)))))
    var v_68: UInt64 = UInt64(0)
    var f_69: UInt64 = UInt64(0)
    var module_70 = VkShaderModuleCreateInfo()
    module_70.sType = Int32(16)
    module_70.codeSize = UInt64(vs_size)
    module_70.pCode = UInt64(vs)
    if Bool((Int32(c_result(Int32(external_call["vkCreateShaderModule", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=module_70)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=v_68)))))), UInt64(c_literal_22()))) < Int32(0))):
        var c_temp_71 = Int32((-1))
        _ = v_68
        _ = module_70^
        return c_temp_71
    module_70.codeSize = UInt64(fs_size)
    module_70.pCode = UInt64(fs)
    if Bool((Int32(c_result(Int32(external_call["vkCreateShaderModule", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=module_70)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=f_69)))))), UInt64(c_literal_23()))) < Int32(0))):
        external_call["vkDestroyShaderModule", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(v_68)), c_pointer(UInt64(UInt64(0))))
        var c_temp_72 = Int32((-1))
        _ = v_68
        _ = f_69
        _ = module_70^
        return c_temp_72
    var stages_73 = Array[VkPipelineShaderStageCreateInfo, 2](fill=VkPipelineShaderStageCreateInfo())
    stages_73[0].sType = Int32(18)
    stages_73[0].stage = Int32(1)
    stages_73[0].module = UInt64(v_68)
    stages_73[0].pName = UInt64(c_literal_24())
    stages_73[1].sType = Int32(18)
    stages_73[1].stage = Int32(16)
    stages_73[1].module = UInt64(f_69)
    stages_73[1].pName = UInt64(c_literal_24())
    var bindings_74 = Array[VkVertexInputBindingDescription, 5](fill=VkVertexInputBindingDescription())
    bindings_74[0].binding = UInt32(0)
    bindings_74[0].stride = UInt32(32)
    bindings_74[0].inputRate = Int32(0)
    bindings_74[1].binding = UInt32(1)
    bindings_74[1].stride = UInt32(32)
    bindings_74[1].inputRate = Int32(0)
    bindings_74[2].binding = UInt32(2)
    bindings_74[2].stride = UInt32(32)
    bindings_74[2].inputRate = Int32(0)
    bindings_74[3].binding = UInt32(3)
    bindings_74[3].stride = UInt32(32)
    bindings_74[3].inputRate = Int32(0)
    var attributes_75 = Array[VkVertexInputAttributeDescription, 13](fill=VkVertexInputAttributeDescription())
    attributes_75[0].location = UInt32(0)
    attributes_75[0].binding = UInt32(0)
    attributes_75[0].c_format = Int32(106)
    attributes_75[0].offset = UInt32(0)
    attributes_75[1].location = UInt32(1)
    attributes_75[1].binding = UInt32(0)
    attributes_75[1].c_format = Int32(106)
    attributes_75[1].offset = UInt32(12)
    attributes_75[2].location = UInt32(2)
    attributes_75[2].binding = UInt32(0)
    attributes_75[2].c_format = Int32(103)
    attributes_75[2].offset = UInt32(24)
    attributes_75[3].location = UInt32(3)
    attributes_75[3].binding = UInt32(1)
    attributes_75[3].c_format = Int32(106)
    attributes_75[3].offset = UInt32(0)
    attributes_75[4].location = UInt32(4)
    attributes_75[4].binding = UInt32(1)
    attributes_75[4].c_format = Int32(106)
    attributes_75[4].offset = UInt32(12)
    attributes_75[5].location = UInt32(5)
    attributes_75[5].binding = UInt32(2)
    attributes_75[5].c_format = Int32(106)
    attributes_75[5].offset = UInt32(0)
    attributes_75[6].location = UInt32(6)
    attributes_75[6].binding = UInt32(2)
    attributes_75[6].c_format = Int32(106)
    attributes_75[6].offset = UInt32(12)
    attributes_75[7].location = UInt32(7)
    attributes_75[7].binding = UInt32(3)
    attributes_75[7].c_format = Int32(106)
    attributes_75[7].offset = UInt32(0)
    attributes_75[8].location = UInt32(8)
    attributes_75[8].binding = UInt32(3)
    attributes_75[8].c_format = Int32(106)
    attributes_75[8].offset = UInt32(12)
    if Bool((Int32(kind) == Int32(2))):
        attributes_75[Int(0)].c_format = Int32(103)
        attributes_75[Int(1)].c_format = Int32(109)
        attributes_75[Int(1)].offset = UInt32(8)
        attributes_75[Int(2)].offset = UInt32(24)
    if Bool(depth_only_67):
        attributes_75[Int(1)] = (attributes_75[Int(2)]).copy()
        attributes_75[Int(2)] = (attributes_75[Int(3)]).copy()
        attributes_75[Int(3)] = (attributes_75[Int(5)]).copy()
        attributes_75[Int(4)] = (attributes_75[Int(7)]).copy()
    bindings_74[4].binding=4
    bindings_74[4].stride=64
    bindings_74[4].inputRate=1
    for column in range(4):
        var attribute=VkVertexInputAttributeDescription()
        attribute.location=UInt32(9+column)
        attribute.binding=4
        attribute.c_format=109
        attribute.offset=UInt32(column*16)
        attributes_75[(5 if depth_only_67 else 9)+column]=attribute^
    var vertex_76 = VkPipelineVertexInputStateCreateInfo()
    vertex_76.sType = Int32(19)
    vertex_76.vertexBindingDescriptionCount = UInt32((Int32(1) if Bool((Int32(kind) == Int32(2))) else Int32(5)))
    vertex_76.pVertexBindingDescriptions = UInt64(c_address(Pointer(to=bindings_74)))
    vertex_76.vertexAttributeDescriptionCount = UInt32((Int32(13) if Bool((Int32(kind) == Int32(0))) else Int32((Int32(9) if Bool(depth_only_67) else Int32(3)))))
    vertex_76.pVertexAttributeDescriptions = UInt64(c_address(Pointer(to=attributes_75)))
    if kind==4:
        vertex_76.vertexBindingDescriptionCount=0
        vertex_76.vertexAttributeDescriptionCount=0
    elif kind==5:
        bindings_74[0].stride=32
        attributes_75[0].c_format=103
        attributes_75[0].offset=0
        attributes_75[1].c_format=109
        attributes_75[1].offset=8
        attributes_75[2].c_format=103
        attributes_75[2].offset=24
        vertex_76.vertexBindingDescriptionCount=1
        vertex_76.vertexAttributeDescriptionCount=3
    elif kind==6:vertex_76.vertexAttributeDescriptionCount=13
    var assembly_77 = VkPipelineInputAssemblyStateCreateInfo()
    assembly_77.sType = Int32(20)
    assembly_77.topology = Int32(3)
    var viewport_78 = VkPipelineViewportStateCreateInfo()
    viewport_78.sType = Int32(22)
    viewport_78.viewportCount = UInt32(1)
    viewport_78.scissorCount = UInt32(1)
    var raster_79 = VkPipelineRasterizationStateCreateInfo()
    raster_79.sType = Int32(23)
    raster_79.polygonMode = Int32(0)
    raster_79.cullMode = UInt32(0)
    raster_79.frontFace = Int32(0)
    raster_79.depthBiasEnable = UInt32((Int32(kind) == Int32(1)))
    raster_79.depthBiasConstantFactor = Float32(4)
    raster_79.depthBiasSlopeFactor = Float32(2)
    raster_79.lineWidth = Float32(1)
    var samples_80 = VkPipelineMultisampleStateCreateInfo()
    samples_80.sType = Int32(24)
    samples_80.rasterizationSamples = Int32(1 if depth_only_67 or kind==4 or kind==5 else c_ref[Graphics](g)[].samples)
    var depth_81 = VkPipelineDepthStencilStateCreateInfo()
    depth_81.sType = Int32(25)
    depth_81.depthTestEnable = UInt32(kind!=2 and kind!=4 and kind!=5)
    depth_81.depthWriteEnable = UInt32(kind!=2 and kind!=4 and kind!=5)
    depth_81.depthCompareOp = Int32(3)
    depth_81.maxDepthBounds = Float32(1)
    var blend_82 = VkPipelineColorBlendAttachmentState()
    blend_82.blendEnable = UInt32(kind==2 or kind==5)
    blend_82.srcColorBlendFactor = Int32(6)
    blend_82.dstColorBlendFactor = Int32(7)
    blend_82.colorBlendOp = Int32(0)
    blend_82.srcAlphaBlendFactor = Int32(1)
    blend_82.dstAlphaBlendFactor = Int32(7)
    blend_82.alphaBlendOp = Int32(0)
    blend_82.colorWriteMask = UInt32(15)
    var blending_83 = VkPipelineColorBlendStateCreateInfo()
    blending_83.sType = Int32(26)
    blending_83.attachmentCount = UInt32((Int32(0) if Bool(depth_only_67) else Int32(1)))
    blending_83.pAttachments = UInt64(c_address(Pointer(to=blend_82)))
    var dynamics_84 = Array[Int32, 2](fill=Int32(0))
    dynamics_84[0] = Int32(0)
    dynamics_84[1] = Int32(1)
    var dynamic_85 = VkPipelineDynamicStateCreateInfo()
    dynamic_85.sType = Int32(27)
    dynamic_85.dynamicStateCount = UInt32(2)
    dynamic_85.pDynamicStates = UInt64(c_address(Pointer(to=dynamics_84)))
    var info_86 = VkGraphicsPipelineCreateInfo()
    info_86.sType = Int32(28)
    info_86.stageCount = UInt32(2)
    info_86.pStages = UInt64(c_address(Pointer(to=stages_73)))
    info_86.pVertexInputState = UInt64(c_address(Pointer(to=vertex_76)))
    info_86.pInputAssemblyState = UInt64(c_address(Pointer(to=assembly_77)))
    info_86.pViewportState = UInt64(c_address(Pointer(to=viewport_78)))
    info_86.pRasterizationState = UInt64(c_address(Pointer(to=raster_79)))
    info_86.pMultisampleState = UInt64(c_address(Pointer(to=samples_80)))
    info_86.pDepthStencilState = UInt64(c_address(Pointer(to=depth_81)))
    info_86.pColorBlendState = UInt64(c_address(Pointer(to=blending_83)))
    info_86.pDynamicState = UInt64(c_address(Pointer(to=dynamic_85)))
    info_86.layout = UInt64(c_ref[Graphics](g)[].pipeline_layout)
    info_86.renderPass = UInt64((UInt64(c_ref[Graphics](g)[].shadow_pass) if Bool(depth_only_67) else UInt64(c_ref[Graphics](g)[].color_pass)))
    if kind==4 or kind==5:info_86.renderPass=c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].display_pass
    elif kind==6:info_86.renderPass=c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].hdr_pass
    var status_87: Int32 = Int32(external_call["vkCreateGraphicsPipelines", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(0)), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=info_86)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(pipeline))))
    external_call["vkDestroyShaderModule", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(v_68)), c_pointer(UInt64(UInt64(0))))
    external_call["vkDestroyShaderModule", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(f_69)), c_pointer(UInt64(UInt64(0))))
    var c_temp_88 = Int32(c_result(Int32(status_87), UInt64(c_literal_25())))
    _ = v_68
    _ = f_69
    _ = module_70^
    _ = stages_73^
    _ = bindings_74^
    _ = attributes_75^
    _ = vertex_76^
    _ = assembly_77^
    _ = viewport_78^
    _ = raster_79^
    _ = samples_80^
    _ = depth_81^
    _ = blend_82^
    _ = blending_83^
    _ = dynamics_84^
    _ = dynamic_85^
    _ = info_86^
    return c_temp_88

def targets_make(var g: UInt64) -> Int32:
    if Bool((Bool((Int32(c_ref[Graphics](g)[].target_width) == Int32(c_ref[Graphics](g)[].width))) and Bool((Int32(c_ref[Graphics](g)[].target_height) == Int32(c_ref[Graphics](g)[].height))))):
        var c_temp_89 = Int32(0)
        return c_temp_89
    if Bool((Int32(c_result(Int32(external_call["vkDeviceWaitIdle", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)))), UInt64(c_literal_26()))) < Int32(0))):
        var c_temp_90 = Int32((-1))
        return c_temp_90
    if Bool(c_ref[Graphics](g)[].color_fb):
        external_call["vkDestroyFramebuffer", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].color_fb)), c_pointer(UInt64(UInt64(0))))
    c_ref[Graphics](g)[].color_fb = UInt64(0)
    hdr_targets_drop(g)
    image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].color))))
    image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].depth))))
    image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].multisample))))
    if Bool(c_ref[Graphics](g)[].scene_depth_fb):
        external_call["vkDestroyFramebuffer", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].scene_depth_fb)), c_pointer(UInt64(UInt64(0))))
    c_ref[Graphics](g)[].scene_depth_fb = UInt64(0)
    image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].scene_depth))))
    image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].scene_color))))
    buffer_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].readback))))
    c_ref[Graphics](g)[].target_width = Int32(c_set[DType.int32](c_address(Pointer(to=c_ref[Graphics](g)[].target_height)), Int32(0)))
    if Bool((Int32(image_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].color))), UInt32(c_ref[Graphics](g)[].width), UInt32(c_ref[Graphics](g)[].height), UInt32(1), Int32(37), UInt32((Int32(16) | Int32(1))), UInt32(1))) < Int32(0))):
        var c_temp_91 = Int32((-1))
        _ = g
        return c_temp_91
    if Bool((Int32(image_make_samples(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].depth))), UInt32(c_ref[Graphics](g)[].width), UInt32(c_ref[Graphics](g)[].height), UInt32(1), Int32(126), UInt32(32), UInt32(2), Int32(c_ref[Graphics](g)[].samples))) < Int32(0))):
        var c_temp_92 = Int32((-1))
        _ = g
        return c_temp_92
    if Bool((Bool((Int32(c_ref[Graphics](g)[].samples) != Int32(1))) and Bool((Int32(image_make_samples(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].multisample))), UInt32(c_ref[Graphics](g)[].width), UInt32(c_ref[Graphics](g)[].height), UInt32(1), Int32(37), UInt32(16), UInt32(1), Int32(c_ref[Graphics](g)[].samples))) < Int32(0))))):
        var c_temp_93 = Int32((-1))
        _ = g
        return c_temp_93
    var views_94 = Array[UInt64, 3](fill=UInt64(0))
    views_94[0] = UInt64((UInt64(c_ref[Graphics](g)[].color.view) if Bool((Int32(c_ref[Graphics](g)[].samples) == Int32(1))) else UInt64(c_ref[Graphics](g)[].multisample.view)))
    views_94[1] = UInt64(c_ref[Graphics](g)[].depth.view)
    views_94[2] = UInt64(c_ref[Graphics](g)[].color.view)
    var fb_95 = VkFramebufferCreateInfo()
    fb_95.sType = Int32(37)
    fb_95.renderPass = UInt64(c_ref[Graphics](g)[].color_pass)
    fb_95.attachmentCount = UInt32((Int32(2) if Bool((Int32(c_ref[Graphics](g)[].samples) == Int32(1))) else Int32(3)))
    fb_95.pAttachments = UInt64(c_address(Pointer(to=views_94)))
    fb_95.width = UInt32(c_ref[Graphics](g)[].width)
    fb_95.height = UInt32(c_ref[Graphics](g)[].height)
    fb_95.layers = UInt32(1)
    if Bool((Int32(c_result(Int32(external_call["vkCreateFramebuffer", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=fb_95)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].color_fb)))))), UInt64(c_literal_27()))) < Int32(0))):
        var c_temp_96 = Int32((-1))
        _ = g
        _ = views_94^
        _ = fb_95^
        return c_temp_96
    if Bool((Int32(buffer_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].readback))), UInt64((UInt64((UInt64(UInt64(c_ref[Graphics](g)[].width)) * UInt64(c_ref[Graphics](g)[].height))) * UInt64(4))), UInt32(2))) < Int32(0))):
        var c_temp_97 = Int32((-1))
        _ = g
        _ = views_94^
        _ = fb_95^
        return c_temp_97
    if Bool((Int32(image_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].scene_depth))), UInt32(c_ref[Graphics](g)[].width), UInt32(c_ref[Graphics](g)[].height), UInt32(1), Int32(126), UInt32((Int32((Int32(32) | Int32(4))) | Int32(2))), UInt32(2))) < Int32(0))):
        var c_temp_98 = Int32((-1))
        _ = g
        _ = views_94^
        _ = fb_95^
        return c_temp_98
    if Bool((Int32(image_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].scene_color))), UInt32(c_ref[Graphics](g)[].width), UInt32(c_ref[Graphics](g)[].height), UInt32(1), Int32(97 if c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].hdr_enabled else 37), UInt32((Int32(4) | Int32(2))), UInt32(1))) < Int32(0))):
        var c_temp_99 = Int32((-1))
        _ = g
        _ = views_94^
        _ = fb_95^
        return c_temp_99
    fb_95.renderPass = UInt64(c_ref[Graphics](g)[].shadow_pass)
    fb_95.attachmentCount = UInt32(1)
    fb_95.pAttachments = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].scene_depth.view)))
    if Bool((Int32(c_result(Int32(external_call["vkCreateFramebuffer", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=fb_95)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].scene_depth_fb)))))), UInt64(c_literal_28()))) < Int32(0))):
        var c_temp_100 = Int32((-1))
        _ = g
        _ = views_94^
        _ = fb_95^
        return c_temp_100
    if hdr_targets_make(g)<0:return -1
    if Bool((Int32(command_begin(UInt64(g))) < Int32(0))):
        var c_temp_101 = Int32((-1))
        _ = g
        _ = views_94^
        _ = fb_95^
        return c_temp_101
    barrier(UInt64(g), UInt64(c_ref[Graphics](g)[].scene_color.image), UInt32(1), UInt32(0), UInt32(1), Int32(0), Int32(7), UInt32(1), UInt32(4096), UInt32(0), UInt32(4096))
    barrier(UInt64(g), UInt64(c_ref[Graphics](g)[].scene_depth.image), UInt32(2), UInt32(0), UInt32(1), Int32(0), Int32(7), UInt32(1), UInt32(4096), UInt32(0), UInt32(4096))
    var c_range_102 = VkImageSubresourceRange()
    c_range_102.aspectMask = UInt32(1)
    c_range_102.baseMipLevel = UInt32(0)
    c_range_102.levelCount = UInt32(1)
    c_range_102.baseArrayLayer = UInt32(0)
    c_range_102.layerCount = UInt32(1)
    var zero_103 = VkClearColorValue()
    c_ref[Array[Float32, 4]](c_address(Pointer(to=zero_103)))[][0] = Float32(0)
    c_ref[Array[Float32, 4]](c_address(Pointer(to=zero_103)))[][1] = Float32(0)
    c_ref[Array[Float32, 4]](c_address(Pointer(to=zero_103)))[][2] = Float32(0)
    c_ref[Array[Float32, 4]](c_address(Pointer(to=zero_103)))[][3] = Float32(1)
    external_call["vkCmdClearColorImage", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_ref[Graphics](g)[].scene_color.image)), Int32(7), c_pointer(UInt64(c_address(Pointer(to=zero_103)))), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=c_range_102)))))
    c_range_102.aspectMask = UInt32(2)
    var far_104 = VkClearDepthStencilValue()
    far_104.depth = Float32(1)
    far_104.stencil = UInt32(0)
    external_call["vkCmdClearDepthStencilImage", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_ref[Graphics](g)[].scene_depth.image)), Int32(7), c_pointer(UInt64(c_address(Pointer(to=far_104)))), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=c_range_102)))))
    barrier(UInt64(g), UInt64(c_ref[Graphics](g)[].scene_color.image), UInt32(1), UInt32(0), UInt32(1), Int32(7), Int32(5), UInt32(4096), UInt32(128), UInt32(4096), UInt32(32))
    barrier(UInt64(g), UInt64(c_ref[Graphics](g)[].scene_depth.image), UInt32(2), UInt32(0), UInt32(1), Int32(7), Int32(4), UInt32(4096), UInt32(128), UInt32(4096), UInt32(32))
    if Bool((Int32(command_submit(UInt64(g), UInt64(0), UInt64(0))) < Int32(0))):
        var c_temp_105 = Int32((-1))
        _ = g
        _ = views_94^
        _ = fb_95^
        _ = c_range_102^
        _ = zero_103^
        _ = far_104^
        return c_temp_105
    var images_106 = Array[VkDescriptorImageInfo, 2](fill=VkDescriptorImageInfo())
    images_106[0].sampler = UInt64(c_ref[Graphics](g)[].shadow_sampler)
    images_106[0].imageView = UInt64(c_ref[Graphics](g)[].scene_depth.view)
    images_106[0].imageLayout = Int32(4)
    images_106[1].sampler = UInt64(c_ref[Graphics](g)[].shadow_sampler)
    images_106[1].imageView = UInt64(c_ref[Graphics](g)[].scene_color.view)
    images_106[1].imageLayout = Int32(5)
    var i_107: UInt32 = UInt32(0)
    while Bool((UInt32(i_107) <= UInt32(c_ref[Graphics](g)[].texture_count))):
        if Bool(c_ref[Graphics](g)[].textures[Int(i_107)].set):
            var writes_108 = Array[VkWriteDescriptorSet, 2](fill=VkWriteDescriptorSet())
            _ = c_nullable_address(external_call["memset", CPointer](c_pointer(UInt64(c_address(Pointer(to=writes_108)))), Int32(0), UInt64(UInt64(size_of[Array[VkWriteDescriptorSet, 2]]()))))
            var k_109: Int32 = Int32(0)
            while Bool((Int32(k_109) < Int32(2))):
                writes_108[Int(k_109)].sType = Int32(35)
                writes_108[Int(k_109)].dstSet = UInt64(c_ref[Graphics](g)[].textures[Int(i_107)].set)
                writes_108[Int(k_109)].dstBinding = UInt32((Int32(5) + Int32(k_109)))
                writes_108[Int(k_109)].descriptorCount = UInt32(1)
                writes_108[Int(k_109)].descriptorType = Int32(1)
                writes_108[Int(k_109)].pImageInfo = UInt64(c_address(Pointer(to=images_106[Int(k_109)])))
                k_109 += 1
            _ = k_109
            external_call["vkUpdateDescriptorSets", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), UInt32(2), c_pointer(UInt64(c_address(Pointer(to=writes_108)))), UInt32(0), c_pointer(UInt64(UInt64(0))))
            _ = writes_108^
        i_107 += 1
    hdr_descriptors_update(g)
    c_ref[Graphics](g)[].target_width = Int32(c_ref[Graphics](g)[].width)
    c_ref[Graphics](g)[].target_height = Int32(c_ref[Graphics](g)[].height)
    var c_temp_110 = Int32(0)
    _ = g
    _ = views_94^
    _ = fb_95^
    _ = c_range_102^
    _ = zero_103^
    _ = far_104^
    _ = images_106^
    return c_temp_110

def texture_make(var g: UInt64, var texture: UInt64, var pixels: UInt64, var w: UInt32, var h: UInt32, var linear: Int32) -> Int32:
    c_ref[Texture](texture)[].opaque = Int32(1)
    var i_111: UInt64 = UInt64(0)
    while Bool((UInt64(i_111) < UInt64((UInt64(UInt64(w)) * UInt64(h))))):
        if Bool((Int32(c_ref[UInt8](pixels)[unsafe_offset=Int((UInt64((UInt64(i_111) * UInt64(4))) + UInt64(3)))]) != Int32(255))):
            c_ref[Texture](texture)[].opaque = Int32(0)
            break
        i_111 += 1
    var levels_112: UInt32 = UInt32(1)
    var c_format_113: Int32 = Int32((Int32(37) if Bool(linear) else Int32(43)))
    var props_114 = VkFormatProperties()
    external_call["vkGetPhysicalDeviceFormatProperties", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), Int32(c_format_113), c_pointer(UInt64(c_address(Pointer(to=props_114)))))
    var required_115: UInt32 = UInt32((Int32((Int32(1024) | Int32(2048))) | Int32(4096)))
    if Bool((UInt32((UInt32(props_114.optimalTilingFeatures) & UInt32(required_115))) == UInt32(required_115))):
        var size_116: UInt32 = UInt32((UInt32(w) if Bool((UInt32(w) > UInt32(h))) else UInt32(h)))
        while Bool((UInt32(size_116) > UInt32(1))):
            levels_112 += 1
            size_116 //= UInt32(2)
    var staging_117 = Buffer()
    var rc_118: Int32 = Int32((-1))
    try:
        if Bool((Int32(buffer_make(UInt64(g), UInt64(c_address(Pointer(to=staging_117))), UInt64((UInt64((UInt64(UInt64(w)) * UInt64(h))) * UInt64(4))), UInt32(1))) < Int32(0))):
            raise Error("port cleanup")
        if Bool((Int32(buffer_write(UInt64(g), UInt64(c_address(Pointer(to=staging_117))), UInt64(pixels), UInt64((UInt64((UInt64(UInt64(w)) * UInt64(h))) * UInt64(4))))) < Int32(0))):
            raise Error("port cleanup")
        if Bool((Int32(image_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Texture](texture)[].image))), UInt32(w), UInt32(h), UInt32(levels_112), Int32(c_format_113), UInt32((Int32((Int32(1) | Int32(2))) | Int32(4))), UInt32(1))) < Int32(0))):
            raise Error("port cleanup")
        if Bool((Int32(command_begin(UInt64(g))) < Int32(0))):
            raise Error("port cleanup")
        barrier(UInt64(g), UInt64(c_ref[Texture](texture)[].image.image), UInt32(1), UInt32(0), UInt32(levels_112), Int32(0), Int32(7), UInt32(1), UInt32(4096), UInt32(0), UInt32(4096))
        var copy_119 = VkBufferImageCopy()
        copy_119.imageSubresource.aspectMask = UInt32(1)
        copy_119.imageSubresource.mipLevel = UInt32(0)
        copy_119.imageSubresource.baseArrayLayer = UInt32(0)
        copy_119.imageSubresource.layerCount = UInt32(1)
        copy_119.imageExtent.width = UInt32(w)
        copy_119.imageExtent.height = UInt32(h)
        copy_119.imageExtent.depth = UInt32(1)
        external_call["vkCmdCopyBufferToImage", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(staging_117.buffer)), c_pointer(UInt64(c_ref[Texture](texture)[].image.image)), Int32(7), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=copy_119)))))
        var mw_120: Int32 = Int32(Int32(w))
        var mh_121: Int32 = Int32(Int32(h))
        var level_122: UInt32 = UInt32(1)
        while Bool((UInt32(level_122) < UInt32(levels_112))):
            barrier(UInt64(g), UInt64(c_ref[Texture](texture)[].image.image), UInt32(1), UInt32((UInt32(level_122) - UInt32(1))), UInt32(1), Int32(7), Int32(6), UInt32(4096), UInt32(4096), UInt32(4096), UInt32(2048))
            var nw_123: Int32 = Int32((Int32((Int32(mw_120) // Int32(2))) if Bool((Int32(mw_120) > Int32(1))) else Int32(1)))
            var nh_124: Int32 = Int32((Int32((Int32(mh_121) // Int32(2))) if Bool((Int32(mh_121) > Int32(1))) else Int32(1)))
            var blit_125 = VkImageBlit()
            blit_125.srcSubresource.aspectMask = UInt32(1)
            blit_125.srcSubresource.mipLevel = UInt32((UInt32(level_122) - UInt32(1)))
            blit_125.srcSubresource.baseArrayLayer = UInt32(0)
            blit_125.srcSubresource.layerCount = UInt32(1)
            blit_125.srcOffsets[0].x = Int32(0)
            blit_125.srcOffsets[0].y = Int32(0)
            blit_125.srcOffsets[0].z = Int32(0)
            blit_125.srcOffsets[1].x = Int32(mw_120)
            blit_125.srcOffsets[1].y = Int32(mh_121)
            blit_125.srcOffsets[1].z = Int32(1)
            blit_125.dstSubresource.aspectMask = UInt32(1)
            blit_125.dstSubresource.mipLevel = UInt32(level_122)
            blit_125.dstSubresource.baseArrayLayer = UInt32(0)
            blit_125.dstSubresource.layerCount = UInt32(1)
            blit_125.dstOffsets[0].x = Int32(0)
            blit_125.dstOffsets[0].y = Int32(0)
            blit_125.dstOffsets[0].z = Int32(0)
            blit_125.dstOffsets[1].x = Int32(nw_123)
            blit_125.dstOffsets[1].y = Int32(nh_124)
            blit_125.dstOffsets[1].z = Int32(1)
            external_call["vkCmdBlitImage", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_ref[Texture](texture)[].image.image)), Int32(6), c_pointer(UInt64(c_ref[Texture](texture)[].image.image)), Int32(7), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=blit_125)))), Int32(1))
            barrier(UInt64(g), UInt64(c_ref[Texture](texture)[].image.image), UInt32(1), UInt32((UInt32(level_122) - UInt32(1))), UInt32(1), Int32(6), Int32(5), UInt32(4096), UInt32(128), UInt32(2048), UInt32(32))
            mw_120 = Int32(nw_123)
            mh_121 = Int32(nh_124)
            _ = blit_125^
            level_122 += 1
        barrier(UInt64(g), UInt64(c_ref[Texture](texture)[].image.image), UInt32(1), UInt32((UInt32(levels_112) - UInt32(1))), UInt32(1), Int32(7), Int32(5), UInt32(4096), UInt32(128), UInt32(4096), UInt32(32))
        if Bool((Int32(command_submit(UInt64(g), UInt64(0), UInt64(0))) < Int32(0))):
            raise Error("port cleanup")
        var allocation_126 = VkDescriptorSetAllocateInfo()
        allocation_126.sType = Int32(34)
        allocation_126.descriptorPool = UInt64(c_ref[Graphics](g)[].descriptors)
        allocation_126.descriptorSetCount = UInt32(1)
        allocation_126.pSetLayouts = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].set_layout)))
        if Bool((Int32(c_result(Int32(external_call["vkAllocateDescriptorSets", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=allocation_126)))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Texture](texture)[].set)))))), UInt64(c_literal_29()))) < Int32(0))):
            raise Error("port cleanup")
        var uniform_127 = VkDescriptorBufferInfo()
        uniform_127.buffer = UInt64(c_ref[Graphics](g)[].uniform.buffer)
        uniform_127.offset = UInt64(0)
        uniform_127.c_range = UInt64(size_of[CascadeUniform]())
        var shadow_128 = VkDescriptorImageInfo()
        shadow_128.sampler = UInt64(c_ref[Graphics](g)[].shadow_sampler)
        shadow_128.imageView = UInt64(c_ref[Graphics](g)[].shadow.view)
        shadow_128.imageLayout = Int32(4)
        var image_129 = VkDescriptorImageInfo()
        image_129.sampler = UInt64(c_ref[Graphics](g)[].texture_sampler)
        image_129.imageView = UInt64(c_ref[Texture](texture)[].image.view)
        image_129.imageLayout = Int32(5)
        var opaque_depth_130 = VkDescriptorImageInfo()
        opaque_depth_130.sampler = UInt64(c_ref[Graphics](g)[].shadow_sampler)
        opaque_depth_130.imageView = UInt64(c_ref[Graphics](g)[].scene_depth.view)
        opaque_depth_130.imageLayout = Int32(4)
        var opaque_color_131 = VkDescriptorImageInfo()
        opaque_color_131.sampler = UInt64(c_ref[Graphics](g)[].shadow_sampler)
        opaque_color_131.imageView = UInt64(c_ref[Graphics](g)[].scene_color.view)
        opaque_color_131.imageLayout = Int32(5)
        var writes_132 = Array[VkWriteDescriptorSet, 8](fill=VkWriteDescriptorSet())
        writes_132[0].sType = Int32(35)
        writes_132[0].dstSet = UInt64(c_ref[Texture](texture)[].set)
        writes_132[0].dstBinding = UInt32(0)
        writes_132[0].descriptorCount = UInt32(1)
        writes_132[0].descriptorType = Int32(8)
        writes_132[0].pBufferInfo = UInt64(c_address(Pointer(to=uniform_127)))
        writes_132[1].sType = Int32(35)
        writes_132[1].dstSet = UInt64(c_ref[Texture](texture)[].set)
        writes_132[1].dstBinding = UInt32(1)
        writes_132[1].descriptorCount = UInt32(1)
        writes_132[1].descriptorType = Int32(1)
        writes_132[1].pImageInfo = UInt64(c_address(Pointer(to=shadow_128)))
        writes_132[2].sType = Int32(35)
        writes_132[2].dstSet = UInt64(c_ref[Texture](texture)[].set)
        writes_132[2].dstBinding = UInt32(2)
        writes_132[2].descriptorCount = UInt32(1)
        writes_132[2].descriptorType = Int32(1)
        writes_132[2].pImageInfo = UInt64(c_address(Pointer(to=image_129)))
        writes_132[3].sType = Int32(35)
        writes_132[3].dstSet = UInt64(c_ref[Texture](texture)[].set)
        writes_132[3].dstBinding = UInt32(3)
        writes_132[3].descriptorCount = UInt32(1)
        writes_132[3].descriptorType = Int32(1)
        writes_132[3].pImageInfo = UInt64(c_address(Pointer(to=image_129)))
        writes_132[4].sType = Int32(35)
        writes_132[4].dstSet = UInt64(c_ref[Texture](texture)[].set)
        writes_132[4].dstBinding = UInt32(4)
        writes_132[4].descriptorCount = UInt32(1)
        writes_132[4].descriptorType = Int32(1)
        writes_132[4].pImageInfo = UInt64(c_address(Pointer(to=image_129)))
        writes_132[5].sType = Int32(35)
        writes_132[5].dstSet = UInt64(c_ref[Texture](texture)[].set)
        writes_132[5].dstBinding = UInt32(5)
        writes_132[5].descriptorCount = UInt32(1)
        writes_132[5].descriptorType = Int32(1)
        writes_132[5].pImageInfo = UInt64(c_address(Pointer(to=opaque_depth_130)))
        writes_132[6].sType = Int32(35)
        writes_132[6].dstSet = UInt64(c_ref[Texture](texture)[].set)
        writes_132[6].dstBinding = UInt32(6)
        writes_132[6].descriptorCount = UInt32(1)
        writes_132[6].descriptorType = Int32(1)
        writes_132[6].pImageInfo = UInt64(c_address(Pointer(to=opaque_color_131)))
        var skin_info=VkDescriptorBufferInfo()
        skin_info.buffer=c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].skin_buffer.buffer
        skin_info.c_range=c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].skin_buffer.size
        writes_132[7].sType=35
        writes_132[7].dstSet=c_ref[Texture](texture)[].set
        writes_132[7].dstBinding=7
        writes_132[7].descriptorCount=1
        writes_132[7].descriptorType=7
        writes_132[7].pBufferInfo=c_address(Pointer(to=skin_info))
        external_call["vkUpdateDescriptorSets", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), UInt32(8), c_pointer(UInt64(c_address(Pointer(to=writes_132)))), UInt32(0), c_pointer(UInt64(UInt64(0))))
        _=skin_info^
        hdr_descriptor_update(g,c_ref[Texture](texture)[].set)
        rc_118 = Int32(0)
        _ = copy_119^
        _ = writes_132^
        _ = opaque_color_131^
        _ = allocation_126^
        _ = image_129^
        _ = opaque_depth_130^
        _ = uniform_127^
        _ = shadow_128^
    except:
        pass
    buffer_drop(UInt64(g), UInt64(c_address(Pointer(to=staging_117))))
    if Bool((Int32(rc_118) < Int32(0))):
        image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Texture](texture)[].image))))
    var c_temp_133 = Int32(rc_118)
    _ = g
    _ = texture
    _ = props_114^
    _ = staging_117^
    return c_temp_133

def resources_make(var g: UInt64) -> Int32:
    if scalability_init(g)<0:return -1
    var bindings_134 = Array[VkDescriptorSetLayoutBinding, 9](fill=VkDescriptorSetLayoutBinding())
    bindings_134[0].binding = UInt32(0)
    bindings_134[0].descriptorType = Int32(8)
    bindings_134[0].descriptorCount = UInt32(1)
    bindings_134[0].stageFlags = UInt32((Int32(1) | Int32(16)))
    bindings_134[0].pImmutableSamplers = UInt64(UInt64(0))
    bindings_134[1].binding = UInt32(1)
    bindings_134[1].descriptorType = Int32(1)
    bindings_134[1].descriptorCount = UInt32(1)
    bindings_134[1].stageFlags = UInt32(16)
    bindings_134[1].pImmutableSamplers = UInt64(UInt64(0))
    bindings_134[2].binding = UInt32(2)
    bindings_134[2].descriptorType = Int32(1)
    bindings_134[2].descriptorCount = UInt32(1)
    bindings_134[2].stageFlags = UInt32(16)
    bindings_134[2].pImmutableSamplers = UInt64(UInt64(0))
    bindings_134[3].binding = UInt32(3)
    bindings_134[3].descriptorType = Int32(1)
    bindings_134[3].descriptorCount = UInt32(1)
    bindings_134[3].stageFlags = UInt32(16)
    bindings_134[3].pImmutableSamplers = UInt64(UInt64(0))
    bindings_134[4].binding = UInt32(4)
    bindings_134[4].descriptorType = Int32(1)
    bindings_134[4].descriptorCount = UInt32(1)
    bindings_134[4].stageFlags = UInt32(16)
    bindings_134[4].pImmutableSamplers = UInt64(UInt64(0))
    bindings_134[5].binding = UInt32(5)
    bindings_134[5].descriptorType = Int32(1)
    bindings_134[5].descriptorCount = UInt32(1)
    bindings_134[5].stageFlags = UInt32(16)
    bindings_134[5].pImmutableSamplers = UInt64(UInt64(0))
    bindings_134[6].binding = UInt32(6)
    bindings_134[6].descriptorType = Int32(1)
    bindings_134[6].descriptorCount = UInt32(1)
    bindings_134[6].stageFlags = UInt32(16)
    bindings_134[6].pImmutableSamplers = UInt64(UInt64(0))
    var layout_135 = VkDescriptorSetLayoutCreateInfo()
    layout_135.sType = Int32(32)
    bindings_134[7].binding=7
    bindings_134[7].descriptorType=7
    bindings_134[7].descriptorCount=1
    bindings_134[7].stageFlags=1
    bindings_134[8].binding=8
    bindings_134[8].descriptorType=1
    bindings_134[8].descriptorCount=1
    bindings_134[8].stageFlags=16
    layout_135.bindingCount = UInt32(9)
    layout_135.pBindings = UInt64(c_address(Pointer(to=bindings_134)))
    if Bool((Int32(c_result(Int32(external_call["vkCreateDescriptorSetLayout", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=layout_135)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].set_layout)))))), UInt64(c_literal_30()))) < Int32(0))):
        var c_temp_136 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        return c_temp_136
    var sizes_137 = Array[VkDescriptorPoolSize, 3](fill=VkDescriptorPoolSize())
    sizes_137[0].c_type = Int32(8)
    sizes_137[0].descriptorCount = UInt32((Int32(256) + Int32(1)))
    sizes_137[1].c_type = Int32(1)
    sizes_137[1].descriptorCount = UInt32((Int32((Int32(256) + Int32(1))) * Int32(7)))
    var pool_138 = VkDescriptorPoolCreateInfo()
    pool_138.sType = Int32(33)
    pool_138.flags=1
    pool_138.maxSets = UInt32((Int32(256) + Int32(1)))
    sizes_137[2].c_type=7
    sizes_137[2].descriptorCount=257
    pool_138.poolSizeCount = UInt32(3)
    pool_138.pPoolSizes = UInt64(c_address(Pointer(to=sizes_137)))
    if Bool((Int32(c_result(Int32(external_call["vkCreateDescriptorPool", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=pool_138)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].descriptors)))))), UInt64(c_literal_31()))) < Int32(0))):
        var c_temp_139 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        return c_temp_139
    var push_140 = VkPushConstantRange()
    push_140.stageFlags = UInt32((Int32(1) | Int32(16)))
    push_140.offset = UInt32(0)
    push_140.size = UInt32(UInt64(size_of[Object]()))
    var pipeline_141 = VkPipelineLayoutCreateInfo()
    pipeline_141.sType = Int32(30)
    pipeline_141.setLayoutCount = UInt32(1)
    pipeline_141.pSetLayouts = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].set_layout)))
    pipeline_141.pushConstantRangeCount = UInt32(1)
    pipeline_141.pPushConstantRanges = UInt64(c_address(Pointer(to=push_140)))
    if Bool((Int32(c_result(Int32(external_call["vkCreatePipelineLayout", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=pipeline_141)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].pipeline_layout)))))), UInt64(c_literal_32()))) < Int32(0))):
        var c_temp_142 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        _ = push_140^
        _ = pipeline_141^
        return c_temp_142
    if Bool((Int32(buffer_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].uniform))), c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].uniform_stride*UInt64(c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].frame_count), UInt32(16))) < Int32(0))):
        var c_temp_143 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        _ = push_140^
        _ = pipeline_141^
        return c_temp_143
    var skin_state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if buffer_make(g,c_address(Pointer(to=skin_state[].skin_buffer)),4,UInt32(32))<0:return -1
    if Bool((Int32(passes_make(UInt64(g))) < Int32(0))):
        var c_temp_144 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        _ = push_140^
        _ = pipeline_141^
        return c_temp_144
    if Bool((Int32(image_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].shadow))), UInt32(4096), UInt32(4096), UInt32(1), Int32(126), UInt32((Int32(32) | Int32(4))), UInt32(2))) < Int32(0))):
        var c_temp_145 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        _ = push_140^
        _ = pipeline_141^
        return c_temp_145
    var fb_146 = VkFramebufferCreateInfo()
    fb_146.sType = Int32(37)
    fb_146.renderPass = UInt64(c_ref[Graphics](g)[].shadow_pass)
    fb_146.attachmentCount = UInt32(1)
    fb_146.pAttachments = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].shadow.view)))
    fb_146.width = UInt32(4096)
    fb_146.height = UInt32(4096)
    fb_146.layers = UInt32(1)
    if Bool((Int32(c_result(Int32(external_call["vkCreateFramebuffer", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=fb_146)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].shadow_fb)))))), UInt64(c_literal_33()))) < Int32(0))):
        var c_temp_147 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        _ = push_140^
        _ = pipeline_141^
        _ = fb_146^
        return c_temp_147
    var sampler_148 = VkSamplerCreateInfo()
    sampler_148.sType = Int32(31)
    sampler_148.magFilter = Int32(0)
    sampler_148.minFilter = Int32(0)
    sampler_148.mipmapMode = Int32(0)
    sampler_148.addressModeU = Int32(3)
    sampler_148.addressModeV = Int32(3)
    sampler_148.addressModeW = Int32(3)
    sampler_148.borderColor = Int32(4)
    if Bool((Int32(c_result(Int32(external_call["vkCreateSampler", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=sampler_148)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].shadow_sampler)))))), UInt64(c_literal_34()))) < Int32(0))):
        var c_temp_149 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        _ = push_140^
        _ = pipeline_141^
        _ = fb_146^
        _ = sampler_148^
        return c_temp_149
    sampler_148.magFilter = Int32(c_set[DType.int32](c_address(Pointer(to=sampler_148.minFilter)), Int32(1)))
    sampler_148.mipmapMode = Int32(1)
    sampler_148.addressModeU = Int32(c_set[DType.int32](c_address(Pointer(to=sampler_148.addressModeV)), Int32(c_set[DType.int32](c_address(Pointer(to=sampler_148.addressModeW)), Int32(0)))))
    sampler_148.maxLod = Float32(1000.0)
    sampler_148.anisotropyEnable = UInt32((Float32(c_ref[Graphics](g)[].anisotropy) > Float32(1)))
    sampler_148.maxAnisotropy = Float32(c_ref[Graphics](g)[].anisotropy)
    if Bool((Int32(c_result(Int32(external_call["vkCreateSampler", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=sampler_148)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].texture_sampler)))))), UInt64(c_literal_35()))) < Int32(0))):
        var c_temp_150 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        _ = push_140^
        _ = pipeline_141^
        _ = fb_146^
        _ = sampler_148^
        return c_temp_150
    if hdr_pipelines_make(g)<0:return -1
    if Bool((Int32(pipeline_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].world_pipeline))), Int32(0), UInt64(shader_world_vert()), shader_world_vert_size(), UInt64(shader_world_frag()), shader_world_frag_size())) < Int32(0))):
        var c_temp_151 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        _ = push_140^
        _ = pipeline_141^
        _ = fb_146^
        _ = sampler_148^
        return c_temp_151
    if Bool((Int32(pipeline_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].shadow_pipeline))), Int32(1), UInt64(shader_shadow_vert()), shader_shadow_vert_size(), UInt64(shader_shadow_frag()), shader_shadow_frag_size())) < Int32(0))):
        var c_temp_152 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        _ = push_140^
        _ = pipeline_141^
        _ = fb_146^
        _ = sampler_148^
        return c_temp_152
    if Bool((Int32(pipeline_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].overlay_pipeline))), Int32(2), UInt64(shader_overlay_vert()), shader_overlay_vert_size(), UInt64(shader_overlay_frag()), shader_overlay_frag_size())) < Int32(0))):
        var c_temp_153 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        _ = push_140^
        _ = pipeline_141^
        _ = fb_146^
        _ = sampler_148^
        return c_temp_153
    if Bool((Bool((Int32(pipeline_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].scene_depth_pipeline))), Int32(3), UInt64(shader_water_depth_vert()), shader_water_depth_vert_size(), UInt64(shader_shadow_frag()), shader_shadow_frag_size())) < Int32(0))) or Bool((Int32(targets_make(UInt64(g))) < Int32(0))))):
        var c_temp_154 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        _ = push_140^
        _ = pipeline_141^
        _ = fb_146^
        _ = sampler_148^
        return c_temp_154
    var white_155 = Array[UInt8, 4](fill=UInt8(0))
    white_155[0] = UInt8(255)
    white_155[1] = UInt8(255)
    white_155[2] = UInt8(255)
    white_155[3] = UInt8(255)
    if Bool((Int32(texture_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].textures[Int(0)]))), UInt64(c_address(Pointer(to=white_155))), UInt32(1), UInt32(1), Int32(0))) < Int32(0))):
        var c_temp_156 = Int32((-1))
        _ = g
        _ = bindings_134^
        _ = layout_135^
        _ = sizes_137^
        _ = pool_138^
        _ = push_140^
        _ = pipeline_141^
        _ = fb_146^
        _ = sampler_148^
        _ = white_155^
        return c_temp_156
    var c_temp_157 = Int32(0)
    _ = g
    _ = bindings_134^
    _ = layout_135^
    _ = sizes_137^
    _ = pool_138^
    _ = push_140^
    _ = pipeline_141^
    _ = fb_146^
    _ = sampler_148^
    _ = white_155^
    return c_temp_157

def instance_make(var g: UInt64) -> Int32:
    var extensions_158 = Array[UInt64, 32](fill=UInt64(0))
    var c_count_159: UInt32 = UInt32(0)
    if c_ref[Graphics](g)[].window:
        var extension_names = c_nullable_address(external_call["SDL_Vulkan_GetInstanceExtensions", CPointer](Pointer(to=c_count_159)))
        if not extension_names:return fail(c_nullable_address(external_call["SDL_GetError", CPointer]()))
        if c_count_159>30:return fail(c_literal_36())
        for i in range(Int(c_count_159)):
            extensions_158[i]=c_ref[UInt64](extension_names)[unsafe_offset=i]
    var validation_163: UInt64 = UInt64(c_literal_37())
    var requested_164: UInt64 = UInt64(c_nullable_address(external_call["getenv", CPointer](c_pointer(UInt64(c_literal_38())))))
    c_ref[Graphics](g)[].validation_enabled = Int32((Bool(requested_164) and Bool((Int32(external_call["strcmp", Int32](c_pointer(UInt64(requested_164)), c_pointer(UInt64(c_literal_39())))) != Int32(0)))))
    if Bool(c_ref[Graphics](g)[].validation_enabled):
        extensions_158[Int(c_increment[DType.uint32](c_address(Pointer(to=c_count_159)), 1, 1))] = UInt64(c_literal_40())
    var app_165 = VkApplicationInfo()
    app_165.sType = Int32(0)
    app_165.pApplicationName = UInt64(c_literal_41())
    app_165.applicationVersion = UInt32(1)
    app_165.pEngineName = UInt64(c_literal_42())
    app_165.engineVersion = UInt32(1)
    app_165.apiVersion = UInt32((UInt32((UInt32((UInt32((UInt32(UInt32(0)) << UInt32(29))) | UInt32((UInt32(UInt32(1)) << UInt32(22))))) | UInt32((UInt32(UInt32(1)) << UInt32(12))))) | UInt32(UInt32(0))))
    var debug_166 = VkDebugUtilsMessengerCreateInfoEXT()
    var c_temp_167: def(var Int32, var UInt32, var UInt64, var UInt64) abi("C") thin -> UInt32 = debug_message
    debug_166.sType = Int32(1000128004)
    debug_166.messageSeverity = UInt32((Int32(256) | Int32(4096)))
    debug_166.messageType = UInt32((Int32((Int32(1) | Int32(2))) | Int32(4)))
    debug_166.pfnUserCallback = UInt64(Pointer(to=c_temp_167).unsafe_bitcast[UInt64]()[])
    debug_166.pUserData = UInt64(g)
    var info_168 = VkInstanceCreateInfo()
    info_168.sType = Int32(1)
    info_168.pNext = UInt64((UInt64(c_address(Pointer(to=debug_166))) if Bool(c_ref[Graphics](g)[].validation_enabled) else UInt64(UInt64(0))))
    info_168.pApplicationInfo = UInt64(c_address(Pointer(to=app_165)))
    info_168.enabledExtensionCount = UInt32(c_count_159)
    info_168.ppEnabledExtensionNames = UInt64(c_address(Pointer(to=extensions_158)))
    info_168.enabledLayerCount = UInt32((Int32(1) if Bool(c_ref[Graphics](g)[].validation_enabled) else Int32(0)))
    info_168.ppEnabledLayerNames = UInt64((UInt64(c_address(Pointer(to=validation_163))) if Bool(c_ref[Graphics](g)[].validation_enabled) else UInt64(UInt64(0))))
    if Bool((Int32(c_result(Int32(external_call["vkCreateInstance", Int32](c_pointer(UInt64(c_address(Pointer(to=info_168)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].instance)))))), UInt64(c_literal_43()))) < Int32(0))):
        var c_temp_169 = Int32((-1))
        _ = g
        _ = extensions_158^
        _ = c_count_159
        _ = validation_163
        _ = app_165^
        _ = debug_166^
        _ = info_168^
        return c_temp_169
    if Bool(c_ref[Graphics](g)[].validation_enabled):
        var create_170: UInt64 = UInt64(UInt64(c_nullable_address(external_call["vkGetInstanceProcAddr", CPointer](c_pointer(UInt64(c_ref[Graphics](g)[].instance)), c_pointer(UInt64(c_literal_44()))))))
        if Bool((not Bool(create_170))):
            var c_temp_171 = Int32(fail(UInt64(c_literal_45())))
            _ = g
            _ = extensions_158^
            _ = c_count_159
            _ = validation_163
            _ = app_165^
            _ = debug_166^
            _ = info_168^
            return c_temp_171
        if Bool((Int32(c_result(Int32(c_function[def(var UInt64, var UInt64, var UInt64, var UInt64) abi("C") thin -> Int32](create_170)(UInt64(c_ref[Graphics](g)[].instance), UInt64(c_address(Pointer(to=debug_166))), UInt64(UInt64(0)), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].debug))))), UInt64(c_literal_46()))) < Int32(0))):
            var c_temp_172 = Int32((-1))
            _ = g
            _ = extensions_158^
            _ = c_count_159
            _ = validation_163
            _ = app_165^
            _ = debug_166^
            _ = info_168^
            return c_temp_172
    if Bool((Bool(c_ref[Graphics](g)[].window) and Bool((not Bool(external_call["SDL_Vulkan_CreateSurface", Bool](c_pointer(UInt64(c_ref[Graphics](g)[].window)), c_pointer(UInt64(c_ref[Graphics](g)[].instance)), CPointer(None), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].surface)))))))))):
        var c_temp_173 = Int32(fail(UInt64(c_nullable_address(external_call["SDL_GetError", CPointer]()))))
        _ = g
        _ = extensions_158^
        _ = c_count_159
        _ = validation_163
        _ = app_165^
        _ = debug_166^
        _ = info_168^
        return c_temp_173
    var c_temp_174 = Int32(0)
    _ = g
    _ = extensions_158^
    _ = c_count_159
    _ = validation_163
    _ = app_165^
    _ = debug_166^
    _ = info_168^
    return c_temp_174

def device_make(var g: UInt64) -> Int32:
    var c_count_175: UInt32 = UInt32(0)
    if Bool((Int32(c_result(Int32(external_call["vkEnumeratePhysicalDevices", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].instance)), c_pointer(UInt64(c_address(Pointer(to=c_count_175)))), c_pointer(UInt64(UInt64(0))))), UInt64(c_literal_47()))) < Int32(0))):
        var c_temp_176 = Int32((-1))
        _ = c_count_175
        return c_temp_176
    if Bool((not Bool(c_count_175))):
        var c_temp_177 = Int32(fail(UInt64(c_literal_48())))
        _ = c_count_175
        return c_temp_177
    var devices_178: UInt64 = UInt64(c_nullable_address(external_call["calloc", CPointer](UInt64(c_count_175), UInt64(UInt64(size_of[UInt64]())))))
    if Bool((not Bool(devices_178))):
        var c_temp_179 = Int32(fail(UInt64(c_literal_49())))
        _ = c_count_175
        return c_temp_179
    var enumeration_180: Int32 = Int32(external_call["vkEnumeratePhysicalDevices", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].instance)), c_pointer(UInt64(c_address(Pointer(to=c_count_175)))), c_pointer(UInt64(devices_178))))
    if Bool((Int32(c_result(Int32(enumeration_180), UInt64(c_literal_50()))) < Int32(0))):
        external_call["free", NoneType](c_pointer(UInt64(devices_178)))
        var c_temp_181 = Int32((-1))
        _ = c_count_175
        return c_temp_181
    var software_env_182: UInt64 = UInt64(c_nullable_address(external_call["getenv", CPointer](c_pointer(UInt64(c_literal_51())))))
    var hardware_env_183: UInt64 = UInt64(c_nullable_address(external_call["getenv", CPointer](c_pointer(UInt64(c_literal_52())))))
    var software_184: Int32 = Int32((Bool(software_env_182) and Bool((Int32(external_call["strcmp", Int32](c_pointer(UInt64(software_env_182)), c_pointer(UInt64(c_literal_39())))) != Int32(0)))))
    var hardware_185: Int32 = Int32((Bool(hardware_env_183) and Bool((Int32(external_call["strcmp", Int32](c_pointer(UInt64(hardware_env_183)), c_pointer(UInt64(c_literal_39())))) != Int32(0)))))
    if Bool((Bool(software_184) and Bool(hardware_185))):
        external_call["free", NoneType](c_pointer(UInt64(devices_178)))
        var c_temp_186 = Int32(fail(UInt64(c_literal_53())))
        _ = c_count_175
        return c_temp_186
    var best_187: Int32 = Int32((-1))
    var i_188: UInt32 = UInt32(0)
    while Bool((UInt32(i_188) < UInt32(c_count_175))):
        var properties_189 = VkPhysicalDeviceProperties()
        external_call["vkGetPhysicalDeviceProperties", NoneType](c_pointer(UInt64(c_ref[UInt64](devices_178)[unsafe_offset=Int(i_188)])), c_pointer(UInt64(c_address(Pointer(to=properties_189)))))
        var cpu_190: Int32 = Int32((Int32(properties_189.deviceType) == Int32(4)))
        var gpu_191: Int32 = Int32((Bool((Bool((Int32(properties_189.deviceType) == Int32(2))) or Bool((Int32(properties_189.deviceType) == Int32(1))))) or Bool((Int32(properties_189.deviceType) == Int32(3)))))
        if Bool((Bool((Bool(software_184) and Bool((not Bool(cpu_190))))) or Bool((Bool(hardware_185) and Bool((not Bool(gpu_191))))))):
            i_188 += 1
            _ = properties_189^
            continue
        if Bool((UInt32(properties_189.apiVersion) < UInt32((UInt32((UInt32((UInt32((UInt32(UInt32(0)) << UInt32(29))) | UInt32((UInt32(UInt32(1)) << UInt32(22))))) | UInt32((UInt32(UInt32(1)) << UInt32(12))))) | UInt32(UInt32(0)))))):
            i_188 += 1
            _ = properties_189^
            continue
        var depth_192 = VkFormatProperties()
        var color_193 = VkFormatProperties()
        external_call["vkGetPhysicalDeviceFormatProperties", NoneType](c_pointer(UInt64(c_ref[UInt64](devices_178)[unsafe_offset=Int(i_188)])), Int32(126), c_pointer(UInt64(c_address(Pointer(to=depth_192)))))
        external_call["vkGetPhysicalDeviceFormatProperties", NoneType](c_pointer(UInt64(c_ref[UInt64](devices_178)[unsafe_offset=Int(i_188)])), Int32(37), c_pointer(UInt64(c_address(Pointer(to=color_193)))))
        var required_194: UInt32 = UInt32((Int32(512) | Int32(1)))
        if Bool((Bool((UInt32((UInt32(depth_192.optimalTilingFeatures) & UInt32(required_194))) != UInt32(required_194))) or Bool((not Bool((UInt32(color_193.optimalTilingFeatures) & UInt32(1024))))))):
            i_188 += 1
            _ = depth_192^
            _ = properties_189^
            _ = color_193^
            continue
        var families_195: UInt32 = UInt32(0)
        external_call["vkGetPhysicalDeviceQueueFamilyProperties", NoneType](c_pointer(UInt64(c_ref[UInt64](devices_178)[unsafe_offset=Int(i_188)])), c_pointer(UInt64(c_address(Pointer(to=families_195)))), c_pointer(UInt64(UInt64(0))))
        var queues_196: UInt64 = UInt64(c_nullable_address(external_call["calloc", CPointer](UInt64(families_195), UInt64(UInt64(size_of[VkQueueFamilyProperties]())))))
        if Bool((not Bool(queues_196))):
            external_call["free", NoneType](c_pointer(UInt64(devices_178)))
            var c_temp_197 = Int32(fail(UInt64(c_literal_54())))
            _ = c_count_175
            _ = properties_189^
            _ = depth_192^
            _ = color_193^
            _ = families_195
            return c_temp_197
        external_call["vkGetPhysicalDeviceQueueFamilyProperties", NoneType](c_pointer(UInt64(c_ref[UInt64](devices_178)[unsafe_offset=Int(i_188)])), c_pointer(UInt64(c_address(Pointer(to=families_195)))), c_pointer(UInt64(queues_196)))
        var q_198: UInt32 = UInt32(0)
        while Bool((UInt32(q_198) < UInt32(families_195))):
            var present_199: UInt32 = UInt32(1)
            if Bool((Bool(c_ref[Graphics](g)[].surface) and Bool((Int32(external_call["vkGetPhysicalDeviceSurfaceSupportKHR", Int32](c_pointer(UInt64(c_ref[UInt64](devices_178)[unsafe_offset=Int(i_188)])), UInt32(q_198), c_pointer(UInt64(c_ref[Graphics](g)[].surface)), c_pointer(UInt64(c_address(Pointer(to=present_199)))))) != Int32(0))))):
                present_199 = UInt32(0)
            if Bool((Bool((not Bool((UInt32(c_ref[VkQueueFamilyProperties](queues_196)[unsafe_offset=Int(q_198)].queueFlags) & UInt32(1))))) or Bool((not Bool(present_199))))):
                q_198 += 1
                _ = present_199
                continue
            var score_200: Int32 = Int32((Int32(100) if Bool((Int32(properties_189.deviceType) == Int32(2))) else Int32((Int32(50) if Bool((Int32(properties_189.deviceType) == Int32(1))) else Int32(10)))))
            if Bool((Int32(score_200) > Int32(best_187))):
                c_ref[Graphics](g)[].physical = UInt64(c_ref[UInt64](devices_178)[unsafe_offset=Int(i_188)])
                c_ref[Graphics](g)[].family = UInt32(q_198)
                c_ref[Graphics](g)[].timestamp_bits = UInt32(c_ref[VkQueueFamilyProperties](queues_196)[unsafe_offset=Int(q_198)].timestampValidBits)
                best_187 = Int32(score_200)
                _ = external_call["snprintf", Int32, num_fixed_args=3](c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].driver)))), UInt64(UInt64(size_of[Array[Int8, 256]]())), c_pointer(UInt64(c_literal_0())), c_pointer(UInt64(c_address(Pointer(to=properties_189.deviceName)))))
            _ = present_199
            break
        external_call["free", NoneType](c_pointer(UInt64(queues_196)))
        _ = depth_192^
        _ = properties_189^
        _ = color_193^
        _ = families_195
        i_188 += 1
    external_call["free", NoneType](c_pointer(UInt64(devices_178)))
    if Bool((not Bool(c_ref[Graphics](g)[].physical))):
        var c_temp_201 = Int32(fail(UInt64((UInt64(c_literal_55()) if Bool(hardware_185) else UInt64((UInt64(c_literal_56()) if Bool(software_184) else UInt64(c_literal_57())))))))
        _ = g
        _ = c_count_175
        return c_temp_201
    var priority_202: Float32 = Float32(1)
    var queue_203 = VkDeviceQueueCreateInfo()
    queue_203.sType = Int32(2)
    queue_203.queueFamilyIndex = UInt32(c_ref[Graphics](g)[].family)
    queue_203.queueCount = UInt32(1)
    queue_203.pQueuePriorities = UInt64(c_address(Pointer(to=priority_202)))
    var supported_204 = VkPhysicalDeviceFeatures()
    var enabled_205 = VkPhysicalDeviceFeatures()
    var properties_206 = VkPhysicalDeviceProperties()
    external_call["vkGetPhysicalDeviceFeatures", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), c_pointer(UInt64(c_address(Pointer(to=supported_204)))))
    external_call["vkGetPhysicalDeviceProperties", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), c_pointer(UInt64(c_address(Pointer(to=properties_206)))))
    var requested_msaa_207: UInt64 = UInt64(c_nullable_address(external_call["getenv", CPointer](c_pointer(UInt64(c_literal_58())))))
    var requested_208: Int32 = Int32((Int32(external_call["atoi", Int32](c_pointer(UInt64(requested_msaa_207)))) if Bool(requested_msaa_207) else Int32(1)))
    if Bool((Bool((Bool((Int32(requested_208) != Int32(1))) and Bool((Int32(requested_208) != Int32(2))))) and Bool((Int32(requested_208) != Int32(4))))):
        var c_temp_209 = Int32(fail(UInt64(c_literal_59())))
        _ = g
        _ = c_count_175
        _ = priority_202
        _ = supported_204^
        _ = properties_206^
        return c_temp_209
    var color_properties_210 = VkImageFormatProperties()
    var depth_properties_211 = VkImageFormatProperties()
    if Bool((Int32(c_result(Int32(external_call["vkGetPhysicalDeviceImageFormatProperties", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), Int32(37), Int32(1), Int32(0), UInt32(16), UInt32(0), c_pointer(UInt64(c_address(Pointer(to=color_properties_210)))))), UInt64(c_literal_60()))) < Int32(0))):
        var c_temp_212 = Int32((-1))
        _ = g
        _ = c_count_175
        _ = priority_202
        _ = supported_204^
        _ = properties_206^
        _ = color_properties_210^
        return c_temp_212
    if Bool((Int32(c_result(Int32(external_call["vkGetPhysicalDeviceImageFormatProperties", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), Int32(126), Int32(1), Int32(0), UInt32(32), UInt32(0), c_pointer(UInt64(c_address(Pointer(to=depth_properties_211)))))), UInt64(c_literal_61()))) < Int32(0))):
        var c_temp_213 = Int32((-1))
        _ = g
        _ = c_count_175
        _ = priority_202
        _ = supported_204^
        _ = properties_206^
        _ = color_properties_210^
        _ = depth_properties_211^
        return c_temp_213
    var counts_214: UInt32 = UInt32((UInt32((UInt32((UInt32(properties_206.limits.framebufferColorSampleCounts) & UInt32(properties_206.limits.framebufferDepthSampleCounts))) & UInt32(color_properties_210.sampleCounts))) & UInt32(depth_properties_211.sampleCounts)))
    c_ref[Graphics](g)[].samples = Int32(1)
    if Bool((Bool((Int32(requested_208) >= Int32(4))) and Bool((UInt32(counts_214) & UInt32(4))))):
        c_ref[Graphics](g)[].samples = Int32(4)
    else:
        if Bool((Bool((Int32(requested_208) >= Int32(2))) and Bool((UInt32(counts_214) & UInt32(2))))):
            c_ref[Graphics](g)[].samples = Int32(2)
    enabled_205.samplerAnisotropy = UInt32(supported_204.samplerAnisotropy)
    c_ref[Graphics](g)[].anisotropy = Float32((Float32((Float32(properties_206.limits.maxSamplerAnisotropy) if Bool((Float32(properties_206.limits.maxSamplerAnisotropy) < Float32(16.0))) else Float32(16.0))) if Bool(enabled_205.samplerAnisotropy) else Float32(1.0)))
    var swapchain_215: UInt64 = UInt64(c_literal_62())
    var device_216 = VkDeviceCreateInfo()
    device_216.sType = Int32(3)
    device_216.pEnabledFeatures = UInt64(c_address(Pointer(to=enabled_205)))
    device_216.queueCreateInfoCount = UInt32(1)
    device_216.pQueueCreateInfos = UInt64(c_address(Pointer(to=queue_203)))
    device_216.enabledExtensionCount = UInt32((Int32(1) if Bool(c_ref[Graphics](g)[].surface) else Int32(0)))
    device_216.ppEnabledExtensionNames = UInt64((UInt64(c_address(Pointer(to=swapchain_215))) if Bool(c_ref[Graphics](g)[].surface) else UInt64(UInt64(0))))
    if Bool((Int32(c_result(Int32(external_call["vkCreateDevice", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), c_pointer(UInt64(c_address(Pointer(to=device_216)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].device)))))), UInt64(c_literal_63()))) < Int32(0))):
        var c_temp_217 = Int32((-1))
        _ = g
        _ = c_count_175
        _ = priority_202
        _ = queue_203^
        _ = supported_204^
        _ = enabled_205^
        _ = properties_206^
        _ = color_properties_210^
        _ = depth_properties_211^
        _ = swapchain_215
        _ = device_216^
        return c_temp_217
    external_call["vkGetDeviceQueue", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), UInt32(c_ref[Graphics](g)[].family), UInt32(0), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].queue)))))
    c_ref[Graphics](g)[].profile_enabled = Int32((Bool(c_nullable_address(external_call["getenv", CPointer](c_pointer(UInt64(c_literal_64()))))) and Bool(external_call["strcmp", Int32](c_pointer(UInt64(c_nullable_address(external_call["getenv", CPointer](c_pointer(UInt64(c_literal_64())))))), c_pointer(UInt64(c_literal_39()))))))
    c_ref[Graphics](g)[].present_sync = Int32((Bool((not Bool(c_nullable_address(external_call["getenv", CPointer](c_pointer(UInt64(c_literal_65()))))))) or Bool(external_call["strcmp", Int32](c_pointer(UInt64(c_nullable_address(external_call["getenv", CPointer](c_pointer(UInt64(c_literal_65())))))), c_pointer(UInt64(c_literal_39()))))))
    c_ref[Graphics](g)[].timestamp_period = Float32(properties_206.limits.timestampPeriod)
    if Bool((Bool((Bool(c_ref[Graphics](g)[].profile_enabled) and Bool(c_ref[Graphics](g)[].timestamp_bits))) and Bool((Float32(c_ref[Graphics](g)[].timestamp_period) > Float32(0))))):
        var queries_218 = VkQueryPoolCreateInfo()
        queries_218.sType = Int32(11)
        queries_218.queryType = Int32(2)
        queries_218.queryCount = UInt32(2)
        if Bool((Int32(c_result(Int32(external_call["vkCreateQueryPool", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=queries_218)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].timestamps)))))), UInt64(c_literal_66()))) < Int32(0))):
            var c_temp_219 = Int32((-1))
            _ = g
            _ = c_count_175
            _ = priority_202
            _ = queue_203^
            _ = supported_204^
            _ = enabled_205^
            _ = properties_206^
            _ = color_properties_210^
            _ = depth_properties_211^
            _ = swapchain_215
            _ = device_216^
            _ = queries_218^
            return c_temp_219
        _ = queries_218^
    external_call["vkGetPhysicalDeviceMemoryProperties", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].memory)))))
    var pool_220 = VkCommandPoolCreateInfo()
    pool_220.sType = Int32(39)
    pool_220.flags = UInt32(2)
    pool_220.queueFamilyIndex = UInt32(c_ref[Graphics](g)[].family)
    if Bool((Int32(c_result(Int32(external_call["vkCreateCommandPool", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=pool_220)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].pool)))))), UInt64(c_literal_67()))) < Int32(0))):
        var c_temp_221 = Int32((-1))
        _ = g
        _ = c_count_175
        _ = priority_202
        _ = queue_203^
        _ = supported_204^
        _ = enabled_205^
        _ = properties_206^
        _ = color_properties_210^
        _ = depth_properties_211^
        _ = swapchain_215
        _ = device_216^
        _ = pool_220^
        return c_temp_221
    var allocation_222 = VkCommandBufferAllocateInfo()
    allocation_222.sType = Int32(40)
    allocation_222.commandPool = UInt64(c_ref[Graphics](g)[].pool)
    allocation_222.level = Int32(0)
    allocation_222.commandBufferCount = UInt32(1)
    if Bool((Int32(c_result(Int32(external_call["vkAllocateCommandBuffers", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=allocation_222)))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].command)))))), UInt64(c_literal_68()))) < Int32(0))):
        var c_temp_223 = Int32((-1))
        _ = g
        _ = c_count_175
        _ = priority_202
        _ = queue_203^
        _ = supported_204^
        _ = enabled_205^
        _ = properties_206^
        _ = color_properties_210^
        _ = depth_properties_211^
        _ = swapchain_215
        _ = device_216^
        _ = pool_220^
        _ = allocation_222^
        return c_temp_223
    var fence_224 = VkFenceCreateInfo()
    fence_224.sType = Int32(8)
    fence_224.flags = UInt32(1)
    if Bool((Int32(c_result(Int32(external_call["vkCreateFence", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=fence_224)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].fence)))))), UInt64(c_literal_69()))) < Int32(0))):
        var c_temp_225 = Int32((-1))
        _ = g
        _ = c_count_175
        _ = priority_202
        _ = queue_203^
        _ = supported_204^
        _ = enabled_205^
        _ = properties_206^
        _ = color_properties_210^
        _ = depth_properties_211^
        _ = swapchain_215
        _ = device_216^
        _ = pool_220^
        _ = allocation_222^
        _ = fence_224^
        return c_temp_225
    var semaphore_226 = VkSemaphoreCreateInfo()
    semaphore_226.sType = Int32(9)
    if Bool((Int32(c_result(Int32(external_call["vkCreateSemaphore", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=semaphore_226)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].acquired)))))), UInt64(c_literal_70()))) < Int32(0))):
        var c_temp_227 = Int32((-1))
        _ = g
        _ = c_count_175
        _ = priority_202
        _ = queue_203^
        _ = supported_204^
        _ = enabled_205^
        _ = properties_206^
        _ = color_properties_210^
        _ = depth_properties_211^
        _ = swapchain_215
        _ = device_216^
        _ = pool_220^
        _ = allocation_222^
        _ = fence_224^
        _ = semaphore_226^
        return c_temp_227
    var c_temp_228 = Int32(0)
    _ = g
    _ = c_count_175
    _ = priority_202
    _ = queue_203^
    _ = supported_204^
    _ = enabled_205^
    _ = properties_206^
    _ = color_properties_210^
    _ = depth_properties_211^
    _ = swapchain_215
    _ = device_216^
    _ = pool_220^
    _ = allocation_222^
    _ = fence_224^
    _ = semaphore_226^
    return c_temp_228

@export("mg_close")
def mg_close(var g: UInt64) abi("C"):
    if Bool((not Bool(g))):
        return
    if Bool(c_ref[Graphics](g)[].device):
        _ = external_call["vkDeviceWaitIdle", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)))
        var i_229: Int32 = Int32(0)
        while Bool((Int32(i_229) < Int32(4096))):
            buffer_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].meshes[Int(i_229)].vertices))))
            buffer_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].meshes[Int(i_229)].indices))))
            i_229 += 1
        _ = i_229
        scalability_drop(g)
        var i_230: Int32 = Int32(0)
        while Bool((Int32(i_230) <= Int32(256))):
            image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].textures[Int(i_230)].image))))
            i_230 += 1
        _ = i_230
        buffer_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].uniform))))
        buffer_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].overlay_buffer))))
        buffer_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].readback))))
        if Bool(c_ref[Graphics](g)[].color_fb):
            external_call["vkDestroyFramebuffer", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].color_fb)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].shadow_fb):
            external_call["vkDestroyFramebuffer", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].shadow_fb)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].timestamps):
            external_call["vkDestroyQueryPool", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].timestamps)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].scene_depth_fb):
            external_call["vkDestroyFramebuffer", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].scene_depth_fb)), c_pointer(UInt64(UInt64(0))))
        image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].scene_depth))))
        image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].scene_color))))
        if Bool(c_ref[Graphics](g)[].scene_depth_pipeline):
            external_call["vkDestroyPipeline", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].scene_depth_pipeline)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].water_pass):
            external_call["vkDestroyRenderPass", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].water_pass)), c_pointer(UInt64(UInt64(0))))
        image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].shadow))))
        image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].color))))
        image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].depth))))
        image_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].multisample))))
        if Bool(c_ref[Graphics](g)[].world_pipeline):
            external_call["vkDestroyPipeline", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].world_pipeline)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].shadow_pipeline):
            external_call["vkDestroyPipeline", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].shadow_pipeline)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].overlay_pipeline):
            external_call["vkDestroyPipeline", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].overlay_pipeline)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].pipeline_layout):
            external_call["vkDestroyPipelineLayout", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].pipeline_layout)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].descriptors):
            external_call["vkDestroyDescriptorPool", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].descriptors)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].set_layout):
            external_call["vkDestroyDescriptorSetLayout", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].set_layout)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].shadow_sampler):
            external_call["vkDestroySampler", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].shadow_sampler)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].texture_sampler):
            external_call["vkDestroySampler", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].texture_sampler)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].color_pass):
            external_call["vkDestroyRenderPass", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].color_pass)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].shadow_pass):
            external_call["vkDestroyRenderPass", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].shadow_pass)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].swapchain):
            external_call["vkDestroySwapchainKHR", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].swapchain)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].acquired):
            external_call["vkDestroySemaphore", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].acquired)), c_pointer(UInt64(UInt64(0))))
        var i_231: UInt32 = UInt32(0)
        while Bool((Bool(c_ref[Graphics](g)[].present_done) and Bool((UInt32(i_231) < UInt32(c_ref[Graphics](g)[].swap_count))))):
            if Bool(c_ref[UInt64](c_ref[Graphics](g)[].present_done)[unsafe_offset=Int(i_231)]):
                external_call["vkDestroySemaphore", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[UInt64](c_ref[Graphics](g)[].present_done)[unsafe_offset=Int(i_231)])), c_pointer(UInt64(UInt64(0))))
            i_231 += 1
        _ = i_231
        if Bool(c_ref[Graphics](g)[].fence):
            external_call["vkDestroyFence", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].fence)), c_pointer(UInt64(UInt64(0))))
        if Bool(c_ref[Graphics](g)[].pool):
            external_call["vkDestroyCommandPool", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].pool)), c_pointer(UInt64(UInt64(0))))
        external_call["vkDestroyDevice", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(UInt64(0))))
    if Bool(c_ref[Graphics](g)[].surface):
        external_call["vkDestroySurfaceKHR", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].instance)), c_pointer(UInt64(c_ref[Graphics](g)[].surface)), c_pointer(UInt64(UInt64(0))))
    if Bool(c_ref[Graphics](g)[].debug):
        var destroy_232: UInt64 = UInt64(UInt64(c_nullable_address(external_call["vkGetInstanceProcAddr", CPointer](c_pointer(UInt64(c_ref[Graphics](g)[].instance)), c_pointer(UInt64(c_literal_71()))))))
        if Bool(destroy_232):
            c_function[def(var UInt64, var UInt64, var UInt64) abi("C") thin](destroy_232)(UInt64(c_ref[Graphics](g)[].instance), UInt64(c_ref[Graphics](g)[].debug), UInt64(UInt64(0)))
    if Bool(c_ref[Graphics](g)[].instance):
        external_call["vkDestroyInstance", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].instance)), c_pointer(UInt64(UInt64(0))))
    if Bool(c_ref[Graphics](g)[].window):
        external_call["SDL_DestroyWindow", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].window)))
    if Bool(c_ref[Graphics](g)[].sdl_flags):
        external_call["SDL_QuitSubSystem", NoneType](UInt32(c_ref[Graphics](g)[].sdl_flags))
    external_call["free", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].swap_images)))
    external_call["free", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].present_done)))
    external_call["free", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].shadow_draws)))
    external_call["free", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].color_draws)))
    external_call["free", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].quads)))
    external_call["free", NoneType](c_pointer(UInt64(g)))

@export("mg_open_mode")
def mg_open_mode(var title: UInt64, var width: Int32, var height: Int32, var hidden: Int32, var fullscreen: Int32) abi("C") -> UInt64:
    if Bool((Bool((Bool((Bool((Int32(width) < Int32(1))) or Bool((Int32(height) < Int32(1))))) or Bool((Int32(width) > Int32(16384))))) or Bool((Int32(height) > Int32(16384))))):
        _ = fail(UInt64(c_literal_72()))
        var c_temp_233 = UInt64(UInt64(0))
        return c_temp_233
    var g_234: UInt64 = UInt64(c_nullable_address(external_call["calloc", CPointer](UInt64(1), UInt64(UInt64(size_of[Graphics]())))))
    if Bool((not Bool(g_234))):
        _ = fail(UInt64(c_literal_73()))
        var c_temp_235 = UInt64(UInt64(0))
        return c_temp_235
    c_ref[Graphics](g_234)[].width = Int32(width)
    c_ref[Graphics](g_234)[].height = Int32(height)
    if external_call["SDL_GetVersion",Int32]()!=3004018:
        var message=String("Atlas requires the pinned native SDL3 3.4.18 runtime")
        _=fail(c_address(message.as_c_string_span().ptr()))
        mg_close(g_234)
        return 0
    var flags_236: UInt32 = UInt32((UInt32((UInt32(0) | UInt32(16384))) | UInt32((UInt32(0) if Bool(hidden) else UInt32(32)))))
    if Bool((not external_call["SDL_InitSubSystem", Bool](UInt32(flags_236)))):
        _ = fail(UInt64(c_nullable_address(external_call["SDL_GetError", CPointer]())))
        mg_close(UInt64(g_234))
        var c_temp_237 = UInt64(UInt64(0))
        return c_temp_237
    c_ref[Graphics](g_234)[].sdl_flags = UInt32(flags_236)
    c_ref[Graphics](g_234)[].font_texture = Int32((-1))
    if Bool((not Bool(hidden))):
        c_ref[Graphics](g_234)[].window = UInt64(c_nullable_address(external_call["SDL_CreateWindow", CPointer](c_pointer(UInt64(title)), Int32(width), Int32(height), UInt64(0x10000000 | 0x20 | 0x2000) | UInt64(1 if fullscreen else 0))))
        if Bool((not Bool(c_ref[Graphics](g_234)[].window))):
            _ = fail(UInt64(c_nullable_address(external_call["SDL_GetError", CPointer]())))
            mg_close(UInt64(g_234))
            var c_temp_238 = UInt64(UInt64(0))
            return c_temp_238
        _ = external_call["SDL_GetWindowSizeInPixels", Bool](c_pointer(UInt64(c_ref[Graphics](g_234)[].window)), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g_234)[].width)))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g_234)[].height)))))
    if Bool((Bool((Bool((Int32(instance_make(UInt64(g_234))) < Int32(0))) or Bool((Int32(device_make(UInt64(g_234))) < Int32(0))))) or Bool((Int32(resources_make(UInt64(g_234))) < Int32(0))))):
        mg_close(UInt64(g_234))
        var c_temp_239 = UInt64(UInt64(0))
        _ = width
        _ = height
        _ = g_234
        return c_temp_239
    var c_temp_240 = UInt64(g_234)
    _ = width
    _ = height
    _ = g_234
    return c_temp_240

@export("mg_open")
def mg_open(var title: UInt64, var width: Int32, var height: Int32, var hidden: Int32) abi("C") -> UInt64:
    var c_temp_241 = UInt64(mg_open_mode(UInt64(title), Int32(width), Int32(height), Int32(hidden), Int32(0)))
    return c_temp_241

@export("mg_driver")
def mg_driver(var g: UInt64) abi("C") -> UInt64:
    var c_temp_242 = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].driver)))
    _ = g
    return c_temp_242

@export("mg_width")
def mg_width(var g: UInt64) abi("C") -> Int32:
    if Bool(c_ref[Graphics](g)[].window):
        if not external_call["SDL_GetWindowSizeInPixels", Bool](c_pointer(UInt64(c_ref[Graphics](g)[].window)), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].width)))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].height))))):return 0
    var c_temp_243 = Int32(c_ref[Graphics](g)[].width)
    _ = g
    return c_temp_243

@export("mg_height")
def mg_height(var g: UInt64) abi("C") -> Int32:
    if Bool(c_ref[Graphics](g)[].window):
        if not external_call["SDL_GetWindowSizeInPixels", Bool](c_pointer(UInt64(c_ref[Graphics](g)[].window)), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].width)))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].height))))):return 0
    var c_temp_244 = Int32(c_ref[Graphics](g)[].height)
    _ = g
    return c_temp_244

@export("mg_mouse")
def mg_mouse(var g: UInt64, var x: UInt64, var y: UInt64) abi("C") -> UInt32:
    if Bool((not Bool(c_ref[Graphics](g)[].window))):
        c_ref[Int32](x)[] = Int32(c_set[DType.int32](c_address(Pointer(to=c_ref[Int32](y)[])), Int32(0)))
        var c_temp_245 = UInt32(0)
        _ = y
        return c_temp_245
    var mx_246: Float32 = Float32(0)
    var my_247: Float32 = Float32(0)
    var w_248: Int32 = Int32(0)
    var h_249: Int32 = Int32(0)
    var buttons_250: UInt32 = UInt32(external_call["SDL_GetMouseState", UInt32](c_pointer(UInt64(c_address(Pointer(to=mx_246)))), c_pointer(UInt64(c_address(Pointer(to=my_247))))))
    if not external_call["SDL_GetWindowSize", Bool](c_pointer(UInt64(c_ref[Graphics](g)[].window)), c_pointer(UInt64(c_address(Pointer(to=w_248)))), c_pointer(UInt64(c_address(Pointer(to=h_249))))):return 0
    c_ref[Int32](x)[] = Int32((Int32(Int32((Int64((Int64(mx_246) * Int64(c_ref[Graphics](g)[].width))) // Int64(w_248)))) if Bool((Int32(w_248) > Int32(0))) else Int32(0)))
    c_ref[Int32](y)[] = Int32((Int32(Int32((Int64((Int64(my_247) * Int64(c_ref[Graphics](g)[].height))) // Int64(h_249)))) if Bool((Int32(h_249) > Int32(0))) else Int32(0)))
    var c_temp_251 = UInt32(buttons_250)
    _ = y
    _ = mx_246
    _ = my_247
    _ = w_248
    _ = h_249
    return c_temp_251

def mesh_at(var g: UInt64, var id: Int32) -> UInt64:
    if Bool((Int32(id) < Int32(0))):
        var c_temp_252 = UInt64(UInt64(0))
        return c_temp_252
    var m_253: UInt64 = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].meshes[Int((UInt32(UInt32(id)) & UInt32(4095)))])))
    var c_temp_254 = UInt64((UInt64(m_253) if Bool((Bool(c_ref[Mesh](m_253)[].c_count) and Bool((UInt32(c_ref[Mesh](m_253)[].generation) == UInt32((UInt32(UInt32(id)) >> UInt32(12))))))) else UInt64(UInt64(0))))
    _ = g
    _ = id
    return c_temp_254

@export("mg_mesh")
def mg_mesh(var g: UInt64, var vertices: UInt64, var floats: Int32, var indices: UInt64, var c_count: Int32) abi("C") -> Int32:
    if Bool((Bool((Bool((Bool((Int32(floats) < Int32(24))) or Bool((Int32(floats) % Int32(8))))) or Bool((Int32(c_count) < Int32(3))))) or Bool((Int32(c_count) % Int32(3))))):
        var c_temp_255 = Int32(fail(UInt64(c_literal_74())))
        return c_temp_255
    var i_256: Int32 = Int32(0)
    while Bool((Int32(i_256) < Int32(c_count))):
        if Bool((UInt32(c_ref[UInt32](indices)[unsafe_offset=Int(i_256)]) >= UInt32(UInt32((Int32(floats) // Int32(8)))))):
            var c_temp_257 = Int32(fail(UInt64(c_literal_75())))
            return c_temp_257
        i_256 += 1
    var slot_258: Int32 = Int32((-1))
    var i_259: Int32 = Int32(0)
    while Bool((Int32(i_259) < Int32(4096))):
        if Bool((Bool((not Bool(c_ref[Graphics](g)[].meshes[Int(i_259)].c_count))) and Bool((UInt32(c_ref[Graphics](g)[].meshes[Int(i_259)].generation) < UInt32(524287))))):
            slot_258 = Int32(i_259)
            break
        i_259 += 1
    if Bool((Int32(slot_258) < Int32(0))):
        var c_temp_260 = Int32(fail(UInt64(c_literal_76())))
        return c_temp_260
    var m_261: UInt64 = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].meshes[Int(slot_258)])))
    if Bool((Bool((Bool((Bool((Int32(pool_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Mesh](m_261)[].vertices))), UInt64((UInt64(UInt64(floats)) * UInt64(4))), UInt32(128))) < Int32(0))) or Bool((Int32(pool_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Mesh](m_261)[].indices))), UInt64((UInt64(UInt64(c_count)) * UInt64(4))), UInt32(64))) < Int32(0))))) or Bool((Int32(buffer_write(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Mesh](m_261)[].vertices))), UInt64(vertices), UInt64((UInt64(UInt64(floats)) * UInt64(4))))) < Int32(0))))) or Bool((Int32(buffer_write(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Mesh](m_261)[].indices))), UInt64(indices), UInt64((UInt64(UInt64(c_count)) * UInt64(4))))) < Int32(0))))):
        buffer_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Mesh](m_261)[].vertices))))
        buffer_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Mesh](m_261)[].indices))))
        var c_temp_262 = Int32((-1))
        _ = g
        _ = vertices
        _ = indices
        _ = slot_258
        _ = m_261
        return c_temp_262
    c_ref[Mesh](m_261)[].c_count = UInt32(UInt32(c_count))
    c_ref[Mesh](m_261)[].topology = UInt64(1469598103934665603)
    var i_263: Int32 = Int32(0)
    while Bool((Int32(i_263) < Int32(c_count))):
        c_ref[Mesh](m_261)[].topology = UInt64((UInt64((UInt64(c_ref[Mesh](m_261)[].topology) ^ UInt64(c_ref[UInt32](indices)[unsafe_offset=Int(i_263)]))) * UInt64(1099511628211)))
        i_263 += 1
    var c_temp_264 = Int32((Int32(Int32((UInt32(c_ref[Mesh](m_261)[].generation) << UInt32(12)))) | Int32(slot_258)))
    _ = g
    _ = vertices
    _ = indices
    _ = slot_258
    _ = m_261
    return c_temp_264

@export("mg_release_mesh")
def mg_release_mesh(var g: UInt64, var id: Int32) abi("C") -> Int32:
    var m_265: UInt64 = UInt64(mesh_at(UInt64(g), Int32(id)))
    if Bool((not Bool(m_265))):
        var c_temp_266 = Int32(fail(UInt64(c_literal_77())))
        return c_temp_266
    buffer_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Mesh](m_265)[].vertices))))
    buffer_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Mesh](m_265)[].indices))))
    attributes_drop(g,Int(UInt32(id)&4095))
    c_ref[Mesh](m_265)[].c_count = UInt32(0)
    c_ref[Mesh](m_265)[].generation += 1
    var c_temp_267 = Int32(0)
    _ = m_265
    return c_temp_267

@export("mg_texture_pixels")
def mg_texture_pixels(var g: UInt64, var pixels: UInt64, var w: Int32, var h: Int32, var linear: Int32) abi("C") -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var available=-1
    for slot in range(256):
        if not state[].texture_alive[slot+1] and state[].texture_generations[slot+1]<8388607:
            available=slot
            break
    if available<0:return fail(c_literal_78())
    if Bool((Bool((Bool((Bool((Bool((Bool((not Bool(pixels))) or Bool((Int32(w) < Int32(1))))) or Bool((Int32(h) < Int32(1))))) or Bool((Int32(w) > Int32(8192))))) or Bool((Int32(h) > Int32(8192))))) or Bool((Bool((Int32(linear) != Int32(0))) and Bool((Int32(linear) != Int32(1))))))):
        var c_temp_269 = Int32(fail(UInt64(c_literal_79())))
        return c_temp_269
    var id_270: Int32 = Int32(available)
    if Bool((Int32(texture_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].textures[Int((Int32(id_270) + Int32(1)))]))), UInt64(pixels), UInt32(UInt32(w)), UInt32(UInt32(h)), Int32(linear))) < Int32(0))):
        var c_temp_271 = Int32((-1))
        _ = g
        _ = id_270
        return c_temp_271
    c_ref[Graphics](g)[].texture_count=max(c_ref[Graphics](g)[].texture_count,UInt32(available+1))
    state[].texture_alive[available+1]=1
    var c_temp_272 = Int32((state[].texture_generations[available+1]<<8)|UInt32(available))
    _ = g
    _ = id_270
    return c_temp_272

@export("mg_texture_data")
def mg_texture_data(var g: UInt64, var path: UInt64, var linear: Int32) abi("C") -> Int32:
    var source_273: UInt64 = UInt64(c_nullable_address(external_call["SDL_LoadBMP", CPointer](c_pointer(UInt64(path)))))
    if Bool((not Bool(source_273))):
        var c_temp_274 = Int32(fail(UInt64(c_nullable_address(external_call["SDL_GetError", CPointer]()))))
        return c_temp_274
    var image_275: UInt64 = UInt64(c_nullable_address(external_call["SDL_ConvertSurface", CPointer](c_pointer(UInt64(source_273)), UInt32(376840196))))
    external_call["SDL_DestroySurface", NoneType](c_pointer(UInt64(source_273)))
    if Bool((not Bool(image_275))):
        var c_temp_276 = Int32(fail(UInt64(c_nullable_address(external_call["SDL_GetError", CPointer]()))))
        return c_temp_276
    var id_277: Int32 = Int32(mg_texture_pixels(UInt64(g), UInt64(c_ref[SDL_Surface](image_275)[].pixels), Int32(c_ref[SDL_Surface](image_275)[].w), Int32(c_ref[SDL_Surface](image_275)[].h), Int32(linear)))
    external_call["SDL_DestroySurface", NoneType](c_pointer(UInt64(image_275)))
    var c_temp_278 = Int32(id_277)
    return c_temp_278

@export("mg_texture")
def mg_texture(var g: UInt64, var path: UInt64) abi("C") -> Int32:
    var c_temp_279 = Int32(mg_texture_data(UInt64(g), UInt64(path), Int32(0)))
    return c_temp_279

@export("mg_normal_map")
def mg_normal_map(var g: UInt64, var albedo: Int32, var normal: Int32) abi("C") -> Int32:
    albedo=texture_index(g,albedo)
    normal=texture_index(g,normal)
    if Bool((Bool((Bool((Bool((Int32(albedo) < Int32(0))) or Bool((Int32(normal) < Int32(0))))) or Bool((Int32(albedo) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))) or Bool((Int32(normal) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))):
        var c_temp_280 = Int32(fail(UInt64(c_literal_81())))
        return c_temp_280
    if Bool((Int32(c_result(Int32(external_call["vkDeviceWaitIdle", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)))), UInt64(c_literal_26()))) < Int32(0))):
        var c_temp_281 = Int32((-1))
        return c_temp_281
    if c_result(external_call["vkDeviceWaitIdle",Int32](c_pointer(c_ref[Graphics](g)[].device)),c_literal_26())<0:return -1
    c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].normal_source[Int(albedo)+1]=Int32(normal+1)
    var image_282 = VkDescriptorImageInfo()
    image_282.sampler = c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].texture_samplers[Int(normal)+1]
    if not image_282.sampler:image_282.sampler=c_ref[Graphics](g)[].texture_sampler
    image_282.imageView = UInt64(c_ref[Graphics](g)[].textures[Int((Int32(normal) + Int32(1)))].image.view)
    image_282.imageLayout = Int32(5)
    var write_283 = VkWriteDescriptorSet()
    write_283.sType = Int32(35)
    write_283.dstSet = UInt64(c_ref[Graphics](g)[].textures[Int((Int32(albedo) + Int32(1)))].set)
    write_283.dstBinding = UInt32(3)
    write_283.descriptorCount = UInt32(1)
    write_283.descriptorType = Int32(1)
    write_283.pImageInfo = UInt64(c_address(Pointer(to=image_282)))
    external_call["vkUpdateDescriptorSets", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=write_283)))), UInt32(0), c_pointer(UInt64(UInt64(0))))
    c_ref[Graphics](g)[].textures[Int((Int32(albedo) + Int32(1)))].normal |= Int32(1)
    var c_temp_284 = Int32(0)
    _ = image_282^
    _ = write_283^
    return c_temp_284

@export("mg_orm_map")
def mg_orm_map(var g: UInt64, var albedo: Int32, var orm: Int32) abi("C") -> Int32:
    albedo=texture_index(g,albedo)
    orm=texture_index(g,orm)
    if Bool((Bool((Bool((Bool((Int32(albedo) < Int32(0))) or Bool((Int32(orm) < Int32(0))))) or Bool((Int32(albedo) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))) or Bool((Int32(orm) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))):
        var c_temp_285 = Int32(fail(UInt64(c_literal_82())))
        return c_temp_285
    if Bool((Int32(c_result(Int32(external_call["vkDeviceWaitIdle", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)))), UInt64(c_literal_26()))) < Int32(0))):
        var c_temp_286 = Int32((-1))
        return c_temp_286
    if c_result(external_call["vkDeviceWaitIdle",Int32](c_pointer(c_ref[Graphics](g)[].device)),c_literal_26())<0:return -1
    c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].orm_source[Int(albedo)+1]=Int32(orm+1)
    var image_287 = VkDescriptorImageInfo()
    image_287.sampler = c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].texture_samplers[Int(orm)+1]
    if not image_287.sampler:image_287.sampler=c_ref[Graphics](g)[].texture_sampler
    image_287.imageView = UInt64(c_ref[Graphics](g)[].textures[Int((Int32(orm) + Int32(1)))].image.view)
    image_287.imageLayout = Int32(5)
    var write_288 = VkWriteDescriptorSet()
    write_288.sType = Int32(35)
    write_288.dstSet = UInt64(c_ref[Graphics](g)[].textures[Int((Int32(albedo) + Int32(1)))].set)
    write_288.dstBinding = UInt32(4)
    write_288.descriptorCount = UInt32(1)
    write_288.descriptorType = Int32(1)
    write_288.pImageInfo = UInt64(c_address(Pointer(to=image_287)))
    external_call["vkUpdateDescriptorSets", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=write_288)))), UInt32(0), c_pointer(UInt64(UInt64(0))))
    c_ref[Graphics](g)[].textures[Int((Int32(albedo) + Int32(1)))].normal |= Int32(2)
    var c_temp_289 = Int32(0)
    _ = image_287^
    _ = write_288^
    return c_temp_289

@export("mg_triplanar")
def mg_triplanar(var g: UInt64, var albedo: Int32, var scale: Float32) abi("C") -> Int32:
    albedo=texture_index(g,albedo)
    if Bool((Bool((Bool((Bool((Bool((Int32(albedo) < Int32(0))) or Bool((Int32(albedo) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))) or Bool((not Bool(isfinite(scale)))))) or Bool((Float32(scale) < Float32(0))))) or Bool((Float32(scale) > Float32(64))))):
        var c_temp_290 = Int32(fail(UInt64(c_literal_83())))
        return c_temp_290
    var texture_291: UInt64 = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].textures[Int((Int32(albedo) + Int32(1)))])))
    if Bool((Bool((Float32(scale) > Float32(0))) and Bool((not Bool(c_ref[Texture](texture_291)[].opaque))))):
        var c_temp_292 = Int32(fail(UInt64(c_literal_84())))
        _ = g
        _ = albedo
        return c_temp_292
    if Bool((Bool((Float32(scale) > Float32(0))) and Bool((Float32(c_ref[Texture](texture_291)[].foliage) > Float32(0))))):
        var c_temp_293 = Int32(fail(UInt64(c_literal_85())))
        _ = g
        _ = albedo
        return c_temp_293
    c_ref[Texture](texture_291)[].projection_scale = Float32(scale)
    if Bool((Float32(scale) > Float32(0))):
        c_ref[Texture](texture_291)[].normal |= Int32(4)
    else:
        c_ref[Texture](texture_291)[].normal &= Int32((~4))
    var c_temp_294 = Int32(0)
    _ = g
    _ = albedo
    return c_temp_294

@export("mg_foliage")
def mg_foliage(var g: UInt64, var albedo: Int32, var transmission: Float32) abi("C") -> Int32:
    albedo=texture_index(g,albedo)
    if Bool((Bool((Bool((Bool((Bool((Int32(albedo) < Int32(0))) or Bool((Int32(albedo) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))) or Bool((not Bool(isfinite(transmission)))))) or Bool((Float32(transmission) < Float32(0))))) or Bool((Float32(transmission) > Float32(1))))):
        var c_temp_295 = Int32(fail(UInt64(c_literal_86())))
        return c_temp_295
    var texture_296: UInt64 = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].textures[Int((Int32(albedo) + Int32(1)))])))
    if Bool((Bool((Float32(transmission) > Float32(0))) and Bool((Bool((Float32(c_ref[Texture](texture_296)[].projection_scale) > Float32(0))) or Bool((Int32(c_ref[Texture](texture_296)[].normal) & Int32(16))))))):
        var c_temp_297 = Int32(fail(UInt64(c_literal_87())))
        _ = g
        _ = albedo
        return c_temp_297
    c_ref[Texture](texture_296)[].foliage = Float32(transmission)
    if Bool((Float32(transmission) > Float32(0))):
        c_ref[Texture](texture_296)[].normal |= Int32(8)
    else:
        c_ref[Texture](texture_296)[].normal &= Int32((~(Int32(8) | Int32(32))))
    var c_temp_298 = Int32(0)
    _ = g
    _ = albedo
    return c_temp_298

@export("mg_wind_material")
def mg_wind_material(var g: UInt64, var albedo: Int32, var enabled: Int32) abi("C") -> Int32:
    albedo=texture_index(g,albedo)
    if Bool((Bool((Bool((Int32(albedo) < Int32(0))) or Bool((Int32(albedo) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))) or Bool((Bool((Int32(enabled) != Int32(0))) and Bool((Int32(enabled) != Int32(1))))))):
        var c_temp_299 = Int32(fail(UInt64(c_literal_88())))
        return c_temp_299
    var texture_300: UInt64 = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].textures[Int((Int32(albedo) + Int32(1)))])))
    if Bool((Bool(enabled) and Bool((Float32(c_ref[Texture](texture_300)[].foliage) <= Float32(0))))):
        var c_temp_301 = Int32(fail(UInt64(c_literal_89())))
        _ = g
        _ = albedo
        return c_temp_301
    if Bool(enabled):
        c_ref[Texture](texture_300)[].normal |= Int32(32)
    else:
        c_ref[Texture](texture_300)[].normal &= Int32((~32))
    var c_temp_302 = Int32(0)
    _ = g
    _ = albedo
    return c_temp_302

@export("mg_wind")
def mg_wind(var g: UInt64, var phase: Float64, var amplitude: Float32) abi("C") -> Int32:
    if Bool((Bool((Bool((Bool((Bool((Bool((not Bool(isfinite(phase)))) or Bool((Float64(phase) < Float64((-6.284)))))) or Bool((Float64(phase) > Float64(6.284))))) or Bool((not Bool(isfinite(amplitude)))))) or Bool((Float32(amplitude) < Float32(0))))) or Bool((Float32(amplitude) > Float32(0.25))))):
        var c_temp_303 = Int32(fail(UInt64(c_literal_90())))
        return c_temp_303
    c_ref[Graphics](g)[].frame.wind[Int(0)] = Float32(Float32(phase))
    c_ref[Graphics](g)[].frame.wind[Int(1)] = Float32(amplitude)
    c_ref[Graphics](g)[].rendered = Int32(0)
    var c_temp_304 = Int32(0)
    return c_temp_304

@export("mg_slope_tint")
def mg_slope_tint(var g: UInt64, var albedo: Int32, var enabled: Int32) abi("C") -> Int32:
    albedo=texture_index(g,albedo)
    if Bool((Bool((Bool((Int32(albedo) < Int32(0))) or Bool((Int32(albedo) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))) or Bool((Bool((Int32(enabled) != Int32(0))) and Bool((Int32(enabled) != Int32(1))))))):
        var c_temp_305 = Int32(fail(UInt64(c_literal_91())))
        return c_temp_305
    var texture_306: UInt64 = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].textures[Int((Int32(albedo) + Int32(1)))])))
    if Bool((Bool(enabled) and Bool((Bool((not Bool(c_ref[Texture](texture_306)[].opaque))) or Bool((Float32(c_ref[Texture](texture_306)[].foliage) > Float32(0))))))):
        var c_temp_307 = Int32(fail(UInt64(c_literal_92())))
        _ = g
        _ = albedo
        return c_temp_307
    if Bool(enabled):
        c_ref[Texture](texture_306)[].normal |= Int32(16)
    else:
        c_ref[Texture](texture_306)[].normal &= Int32((~16))
    var c_temp_308 = Int32(0)
    _ = g
    _ = albedo
    return c_temp_308

@export("mg_water_material")
def mg_water_material(var g: UInt64, var albedo: Int32) abi("C") -> Int32:
    albedo=texture_index(g,albedo)
    if Bool((Bool((Bool((Int32(albedo) < Int32(0))) or Bool((Int32(albedo) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))) or Bool((Float32(c_ref[Graphics](g)[].textures[Int((Int32(albedo) + Int32(1)))].foliage) > Float32(0))))):
        var c_temp_309 = Int32(fail(UInt64(c_literal_93())))
        return c_temp_309
    c_ref[Graphics](g)[].textures[Int((Int32(albedo) + Int32(1)))].normal |= Int32(64)
    var c_temp_310 = Int32(0)
    return c_temp_310

@export("mg_face_material")
def mg_face_material(var g: UInt64, var albedo: Int32) abi("C") -> Int32:
    albedo=texture_index(g,albedo)
    if Bool((Bool((Int32(albedo) < Int32(0))) or Bool((Int32(albedo) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))):
        var c_temp_311 = Int32(fail(UInt64(c_literal_94())))
        return c_temp_311
    c_ref[Graphics](g)[].textures[Int((Int32(albedo) + Int32(1)))].normal |= Int32(128)
    var c_temp_312 = Int32(0)
    return c_temp_312

@export("mg_face")
def mg_face(var g: UInt64, var rig: UInt64, var blink: Float32, var brow: Float32, var jaw: Float32) abi("C") -> Int32:
    if Bool((Bool((Bool((Bool((Bool((Bool((Bool((Bool((Bool((Bool((not Bool(rig))) or Bool((not Bool(isfinite(blink)))))) or Bool((not Bool(isfinite(brow)))))) or Bool((not Bool(isfinite(jaw)))))) or Bool((Float32(blink) < Float32(0))))) or Bool((Float32(blink) > Float32(1))))) or Bool((Float32(brow) < Float32(0))))) or Bool((Float32(brow) > Float32(1))))) or Bool((Float32(jaw) < Float32(0))))) or Bool((Float32(jaw) > Float32(1))))):
        var c_temp_313 = Int32(fail(UInt64(c_literal_95())))
        return c_temp_313
    var i_314: Int32 = Int32(0)
    while Bool((Int32(i_314) < Int32(21))):
        if Bool((not Bool(isfinite(c_ref[Float32](rig)[unsafe_offset=Int(i_314)])))):
            var c_temp_315 = Int32(fail(UInt64(c_literal_96())))
            return c_temp_315
        i_314 += 1
    var i_316: Int32 = Int32(0)
    while Bool((Int32(i_316) < Int32(5))):
        var k_317: Int32 = Int32(0)
        while Bool((Int32(k_317) < Int32(3))):
            c_ref[Graphics](g)[].frame.face_centers[Int(i_316)][Int(k_317)] = Float32(c_ref[Float32](rig)[unsafe_offset=Int((Int32((Int32(i_316) * Int32(3))) + Int32(k_317)))])
            k_317 += 1
        i_316 += 1
    var i_318: Int32 = Int32(0)
    while Bool((Int32(i_318) < Int32(2))):
        var k_319: Int32 = Int32(0)
        while Bool((Int32(k_319) < Int32(3))):
            c_ref[Graphics](g)[].frame.face_axis[Int(i_318)][Int(k_319)] = Float32(c_ref[Float32](rig)[unsafe_offset=Int((Int32((Int32(15) + Int32((Int32(i_318) * Int32(3))))) + Int32(k_319)))])
            k_319 += 1
        i_318 += 1
    c_ref[Graphics](g)[].frame.face_weights[Int(0)] = Float32((Float32((-1.48)) * Float32(blink)))
    c_ref[Graphics](g)[].frame.face_weights[Int(1)] = Float32((Float32(.0035) * Float32(brow)))
    c_ref[Graphics](g)[].frame.face_weights[Int(2)] = Float32((Float32((-.12)) * Float32(jaw)))
    c_ref[Graphics](g)[].rendered = Int32(0)
    var c_temp_320 = Int32(0)
    return c_temp_320

def append_draw(var c_array: UInt64, var c_count: UInt64, var capacity: UInt64, var draw: Draw) -> Int32:
    if Bool((UInt64(c_ref[UInt64](c_count)[]) == UInt64(c_ref[UInt64](capacity)[]))):
        var size_321: UInt64 = UInt64((UInt64((UInt64(c_ref[UInt64](capacity)[]) * UInt64(2))) if Bool(c_ref[UInt64](capacity)[]) else UInt64(64)))
        var p_322: UInt64 = UInt64(c_nullable_address(external_call["realloc", CPointer](c_pointer(UInt64(c_ref[UInt64](c_array)[])), UInt64((UInt64(size_321) * UInt64(UInt64(size_of[Draw]())))))))
        if Bool((not Bool(p_322))):
            var c_temp_323 = Int32(fail(UInt64(c_literal_97())))
            return c_temp_323
        c_ref[UInt64](c_array)[] = UInt64(p_322)
        c_ref[UInt64](capacity)[] = UInt64(size_321)
    c_ref[Draw](c_ref[UInt64](c_array)[])[unsafe_offset=Int(c_increment[DType.uint64](c_address(Pointer(to=c_ref[UInt64](c_count)[])), 1, 1))] = (draw).copy()
    var c_temp_324 = Int32(0)
    _ = c_count
    return c_temp_324

@export("mg_shadow_begin")
def mg_shadow_begin(var g: UInt64, var light: UInt64) abi("C"):
    c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].cascade_count=0
    c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].uniform_slice=0
    for channel in range(4):c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].cascade_eye[channel]=0
    c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].instance_count=1
    c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].skin_count=0
    _ = c_nullable_address(external_call["memset", CPointer](c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].frame.face_weights)))), Int32(0), UInt64(UInt64(size_of[Array[Float32, 4]]()))))
    c_ref[Graphics](g)[].ui_scale = Float32(1)
    _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].frame.light)))), c_pointer(UInt64(light)), UInt64(64)))
    _ = c_nullable_address(external_call["memset", CPointer](c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].frame.wind)))), Int32(0), UInt64(UInt64(size_of[Array[Float32, 4]]()))))
    c_ref[Graphics](g)[].shadow_count = UInt64(c_set[DType.uint64](c_address(Pointer(to=c_ref[Graphics](g)[].color_count)), UInt64(c_set[DType.uint64](c_address(Pointer(to=c_ref[Graphics](g)[].quad_count)), UInt64(0)))))
    c_ref[Graphics](g)[].triangles = Int32(0)
    c_ref[Graphics](g)[].rendered = Int32(0)
    c_ref[Graphics](g)[].frame_started = Int32(1)

@export("mg_shadow_material")
def mg_shadow_material(var g: UInt64, var id: Int32, var model: UInt64, var texture: Int32) abi("C") -> Int32:
    texture=texture_index(g,texture)
    if Bool((not Bool(c_ref[Graphics](g)[].frame_started))):
        var c_temp_325 = Int32(fail(UInt64(c_literal_98())))
        return c_temp_325
    if Bool((not Bool(mesh_at(UInt64(g), Int32(id))))):
        var c_temp_326 = Int32(fail(UInt64(c_literal_99())))
        return c_temp_326
    if Bool((Bool((Int32(texture) < Int32((-1)))) or Bool((Int32(texture) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))):
        var c_temp_327 = Int32(fail(UInt64(c_literal_100())))
        return c_temp_327
    var draw_328 = Draw()
    draw_328.mesh = Int32(id)
    draw_328.texture = Int32(texture)
    draw_328.target_mesh = Int32(id)
    draw_328.target_next_mesh = Int32(id)
    draw_328.next_mesh = Int32(id)
    draw_328.c_object.params[Int(2)] = texture_alpha_value(g,texture)
    draw_328.c_object.params[Int(3)] = Float32(c_ref[Graphics](g)[].textures[Int((Int32(texture) + Int32(1)))].normal)
    _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_address(Pointer(to=draw_328.c_object.model)))), c_pointer(UInt64(model)), UInt64(64)))
    c_ref[Graphics](g)[].rendered = Int32(0)
    var c_temp_329 = Int32(append_draw(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].shadow_draws))), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].shadow_count))), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].shadow_capacity))), (draw_328).copy()))
    _ = g
    _ = model
    if c_temp_329>=0 and queue_attributes(g,id,c_address(Pointer(to=c_ref[Draw](c_ref[Graphics](g)[].shadow_draws)[unsafe_offset=Int(c_ref[Graphics](g)[].shadow_count)-1])))<0:
        c_ref[Graphics](g)[].shadow_count-=1
        c_temp_329= -1
    _ = draw_328^
    return c_temp_329

@export("mg_shadow_draw")
def mg_shadow_draw(var g: UInt64, var id: Int32, var model: UInt64) abi("C") -> Int32:
    var c_temp_330 = Int32(mg_shadow_material(UInt64(g), Int32(id), UInt64(model), Int32((-1))))
    return c_temp_330

def inverse_matrix(var m: UInt64, var result_matrix: UInt64):
    var a_331 = Array[Array[Float64, 8], 4](fill=Array[Float64, 8](fill=Float64(0)))
    var r_332: Int32 = Int32(0)
    while Bool((Int32(r_332) < Int32(4))):
        var c_333: Int32 = Int32(0)
        while Bool((Int32(c_333) < Int32(8))):
            a_331[Int(r_332)][Int(c_333)] = Float64((Float32(c_ref[Float32](m)[unsafe_offset=Int((Int32((Int32(c_333) * Int32(4))) + Int32(r_332)))]) if Bool((Int32(c_333) < Int32(4))) else Float32((Int32(1) if Bool((Int32((Int32(c_333) - Int32(4))) == Int32(r_332))) else Int32(0)))))
            c_333 += 1
        r_332 += 1
    var c_334: Int32 = Int32(0)
    while Bool((Int32(c_334) < Int32(4))):
        var best_335: Int32 = Int32(c_334)
        var r_336: Int32 = Int32((Int32(c_334) + Int32(1)))
        while Bool((Int32(r_336) < Int32(4))):
            if Bool((Float64(abs(Float64(a_331[Int(r_336)][Int(c_334)]))) > Float64(abs(Float64(a_331[Int(best_335)][Int(c_334)]))))):
                best_335 = Int32(r_336)
            r_336 += 1
        if Bool((Float64(abs(Float64(a_331[Int(best_335)][Int(c_334)]))) < Float64(1e-12))):
            _ = c_nullable_address(external_call["memset", CPointer](c_pointer(UInt64(result_matrix)), Int32(0), UInt64(64)))
            var i_337: Int32 = Int32(0)
            while Bool((Int32(i_337) < Int32(4))):
                c_ref[Float32](result_matrix)[unsafe_offset=Int((Int32(i_337) * Int32(5)))] = Float32(1)
                i_337 += 1
            return
        var k_338: Int32 = Int32(0)
        while Bool((Int32(k_338) < Int32(8))):
            var t_339: Float64 = Float64(a_331[Int(c_334)][Int(k_338)])
            a_331[Int(c_334)][Int(k_338)] = Float64(a_331[Int(best_335)][Int(k_338)])
            a_331[Int(best_335)][Int(k_338)] = Float64(t_339)
            k_338 += 1
        var d_340: Float64 = Float64(a_331[Int(c_334)][Int(c_334)])
        var k_341: Int32 = Int32(0)
        while Bool((Int32(k_341) < Int32(8))):
            a_331[Int(c_334)][Int(k_341)] /= Float64(d_340)
            k_341 += 1
        var r_342: Int32 = Int32(0)
        while Bool((Int32(r_342) < Int32(4))):
            if Bool((Int32(r_342) != Int32(c_334))):
                var t_343: Float64 = Float64(a_331[Int(r_342)][Int(c_334)])
                var k_344: Int32 = Int32(0)
                while Bool((Int32(k_344) < Int32(8))):
                    a_331[Int(r_342)][Int(k_344)] -= Float64((Float64(a_331[Int(c_334)][Int(k_344)]) * Float64(t_343)))
                    k_344 += 1
            r_342 += 1
        c_334 += 1
    var r_345: Int32 = Int32(0)
    while Bool((Int32(r_345) < Int32(4))):
        var c_346: Int32 = Int32(0)
        while Bool((Int32(c_346) < Int32(4))):
            c_ref[Float32](result_matrix)[unsafe_offset=Int((Int32((Int32(c_346) * Int32(4))) + Int32(r_345)))] = Float32(Float32(a_331[Int(r_345)][Int((Int32(c_346) + Int32(4)))]))
            c_346 += 1
        r_345 += 1

@export("mg_begin")
def mg_begin(var g: UInt64, var vp: UInt64, var sx: Float32, var sy: Float32, var sz: Float32, var fog: Float32) abi("C"):
    if c_ref[Graphics](g)[].shadow_count==0:c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].instance_count=1
    _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].frame.vp)))), c_pointer(UInt64(vp)), UInt64(64)))
    inverse_matrix(UInt64(vp), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].frame.inverse_vp))))
    c_ref[Graphics](g)[].frame.sun_fog[Int(0)] = Float32(sx)
    c_ref[Graphics](g)[].frame.sun_fog[Int(1)] = Float32(sy)
    c_ref[Graphics](g)[].frame.sun_fog[Int(2)] = Float32(sz)
    c_ref[Graphics](g)[].frame.sun_fog[Int(3)] = Float32(fog)
    var defaults_347 = Array[Float32, 16](fill=Float32(0))
    defaults_347[0] = Float32(.22)
    defaults_347[1] = Float32(.29)
    defaults_347[2] = Float32(.36)
    defaults_347[3] = Float32(0)
    defaults_347[4] = Float32(.08)
    defaults_347[5] = Float32(.09)
    defaults_347[6] = Float32(.12)
    defaults_347[7] = Float32(0)
    defaults_347[8] = Float32(3.4)
    defaults_347[9] = Float32(3.1)
    defaults_347[10] = Float32(2.7)
    defaults_347[11] = Float32(1)
    defaults_347[12] = Float32(.42)
    defaults_347[13] = Float32(.57)
    defaults_347[14] = Float32(.72)
    defaults_347[15] = Float32(0)
    _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].frame.sky)))), c_pointer(UInt64(c_address(Pointer(to=defaults_347)))), UInt64(UInt64(size_of[Array[Float32, 16]]()))))
    _ = c_nullable_address(external_call["memset", CPointer](c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].frame.atmosphere)))), Int32(0), UInt64(UInt64(size_of[Array[Float32, 4]]()))))
    _ = c_nullable_address(external_call["memset", CPointer](c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].frame.cinema)))), Int32(0), UInt64(UInt64(size_of[Array[Float32, 4]]()))))
    c_ref[Graphics](g)[].frame.cinema[Int(2)] = Float32(Float32(c_ref[Graphics](g)[].width))
    c_ref[Graphics](g)[].frame.cinema[Int(3)] = Float32(Float32(c_ref[Graphics](g)[].height))
    c_ref[Graphics](g)[].rendered = Int32(0)
    _ = defaults_347^

@export("mg_lighting")
def mg_lighting(var g: UInt64, var values: UInt64) abi("C") -> Int32:
    var i_348: Int32 = Int32(0)
    while Bool((Int32(i_348) < Int32(16))):
        if Bool((Bool((not Bool(isfinite(c_ref[Float32](values)[unsafe_offset=Int(i_348)])))) or Bool((Float32(c_ref[Float32](values)[unsafe_offset=Int(i_348)]) < Float32(0))))):
            var c_temp_349 = Int32(fail(UInt64(c_literal_101())))
            return c_temp_349
        i_348 += 1
    _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].frame.sky)))), c_pointer(UInt64(values)), UInt64((UInt64(16) * UInt64(UInt64(size_of[Float32]()))))))
    c_ref[Graphics](g)[].rendered = Int32(0)
    var c_temp_350 = Int32(0)
    _ = g
    return c_temp_350

@export("mg_cinematic")
def mg_cinematic(var g: UInt64, var camera_y: Float32, var base_height: Float32, var density: Float32, var falloff: Float32, var strength: Float32, var vignette: Float32) abi("C") -> Int32:
    if Bool((Bool((Bool((Bool((Bool((Bool((Bool((Bool((Bool((Bool((Bool((Bool((Bool((Bool((not Bool(isfinite(camera_y)))) or Bool((not Bool(isfinite(base_height)))))) or Bool((not Bool(isfinite(density)))))) or Bool((not Bool(isfinite(falloff)))))) or Bool((not Bool(isfinite(strength)))))) or Bool((not Bool(isfinite(vignette)))))) or Bool((Float32(density) < Float32(0))))) or Bool((Float32(density) > Float32(0.2))))) or Bool((Float32(falloff) < Float32(0.01))))) or Bool((Float32(falloff) > Float32(2))))) or Bool((Float32(strength) < Float32(0))))) or Bool((Float32(strength) > Float32(1))))) or Bool((Float32(vignette) < Float32(0))))) or Bool((Float32(vignette) > Float32(0.5))))):
        var c_temp_351 = Int32(fail(UInt64(c_literal_102())))
        return c_temp_351
    var atmosphere_352 = Array[Float32, 4](fill=Float32(0))
    atmosphere_352[0] = Float32(camera_y)
    atmosphere_352[1] = Float32(base_height)
    atmosphere_352[2] = Float32(density)
    atmosphere_352[3] = Float32(falloff)
    var cinema_353 = Array[Float32, 4](fill=Float32(0))
    cinema_353[0] = Float32(strength)
    cinema_353[1] = Float32(vignette)
    cinema_353[2] = Float32(Float32(c_ref[Graphics](g)[].width))
    cinema_353[3] = Float32(Float32(c_ref[Graphics](g)[].height))
    _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].frame.atmosphere)))), c_pointer(UInt64(c_address(Pointer(to=atmosphere_352)))), UInt64(UInt64(size_of[Array[Float32, 4]]()))))
    _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].frame.cinema)))), c_pointer(UInt64(c_address(Pointer(to=cinema_353)))), UInt64(UInt64(size_of[Array[Float32, 4]]()))))
    c_ref[Graphics](g)[].rendered = Int32(0)
    var c_temp_354 = Int32(0)
    _ = g
    _ = atmosphere_352^
    _ = cinema_353^
    return c_temp_354

@export("mg_draw")
def mg_draw(var g: UInt64, var id: Int32, var model: UInt64, var r: Float32, var green: Float32, var b: Float32, var rough: Float32, var metal: Float32, var emission: Float32, var texture: Int32) abi("C") -> Int32:
    texture=texture_index(g,texture)
    var m_355: UInt64 = UInt64(mesh_at(UInt64(g), Int32(id)))
    if Bool((not Bool(m_355))):
        var c_temp_356 = Int32(fail(UInt64(c_literal_77())))
        return c_temp_356
    if Bool((Bool((Int32(texture) < Int32((-1)))) or Bool((Int32(texture) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))):
        var c_temp_357 = Int32(fail(UInt64(c_literal_103())))
        return c_temp_357
    var draw_358 = Draw()
    draw_358.mesh = Int32(id)
    draw_358.target_mesh = Int32(id)
    draw_358.target_next_mesh = Int32(id)
    draw_358.next_mesh = Int32(id)
    draw_358.texture = Int32(texture)
    draw_358.c_object.color[0] = Float32(r)
    draw_358.c_object.color[1] = Float32(green)
    draw_358.c_object.color[2] = Float32(b)
    draw_358.c_object.color[3] = Float32(rough)
    draw_358.c_object.params[0] = Float32(metal)
    draw_358.c_object.params[1] = Float32(emission)
    draw_358.c_object.params[2] = texture_alpha_value(g,texture)
    draw_358.c_object.params[3] = Float32(c_ref[Graphics](g)[].textures[Int((Int32(texture) + Int32(1)))].normal)
    _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_address(Pointer(to=draw_358.c_object.model)))), c_pointer(UInt64(model)), UInt64(64)))
    draw_358.c_object.pose[Int(3)] = Float32((Float32(c_ref[Graphics](g)[].textures[Int((Int32(texture) + Int32(1)))].projection_scale) if Bool((Float32(c_ref[Graphics](g)[].textures[Int((Int32(texture) + Int32(1)))].projection_scale) > Float32(0))) else Float32(c_ref[Graphics](g)[].textures[Int((Int32(texture) + Int32(1)))].foliage)))
    if Bool((Int32(append_draw(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].color_draws))), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].color_count))), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].color_capacity))), (draw_358).copy())) < Int32(0))):
        var c_temp_359 = Int32((-1))
        _ = g
        _ = model
        _ = draw_358^
        return c_temp_359
    c_ref[Graphics](g)[].triangles += Int32(Int32((UInt32(c_ref[Mesh](m_355)[].c_count) // UInt32(3))))
    c_ref[Graphics](g)[].rendered = Int32(0)
    var c_temp_360 = Int32(0)
    _ = g
    _ = model
    if queue_attributes(g,id,c_address(Pointer(to=c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int(c_ref[Graphics](g)[].color_count)-1])))<0:
        c_ref[Graphics](g)[].color_count-=1
        c_ref[Graphics](g)[].triangles-=Int32(c_ref[Mesh](m_355)[].c_count//3)
        c_temp_360= -1
    _ = draw_358^
    return c_temp_360

@export("mg_can_morph")
def mg_can_morph(var g: UInt64, var first: Int32, var c_next: Int32) abi("C") -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if state[].attribute_counts[Int(UInt32(first)&4095)] or state[].attribute_counts[Int(UInt32(c_next)&4095)]:return 0
    var a_361: UInt64 = UInt64(mesh_at(UInt64(g), Int32(first)))
    var b_362: UInt64 = UInt64(mesh_at(UInt64(g), Int32(c_next)))
    var c_temp_363 = Int32((Bool((Bool((Bool((Bool(a_361) and Bool(b_362))) and Bool((UInt32(c_ref[Mesh](a_361)[].c_count) == UInt32(c_ref[Mesh](b_362)[].c_count))))) and Bool((UInt64(c_ref[Mesh](a_361)[].vertices.size) == UInt64(c_ref[Mesh](b_362)[].vertices.size))))) and Bool((UInt64(c_ref[Mesh](a_361)[].topology) == UInt64(c_ref[Mesh](b_362)[].topology)))))
    return c_temp_363

@export("mg_draw_morph")
def mg_draw_morph(var g: UInt64, var first: Int32, var c_next: Int32, var blend: Float32, var model: UInt64, var r: Float32, var green: Float32, var b: Float32, var rough: Float32, var metal: Float32, var emission: Float32, var texture: Int32, var shadow: Int32) abi("C") -> Int32:
    if Bool((Bool((Bool((Bool((not Bool(isfinite(blend)))) or Bool((Float32(blend) < Float32(0))))) or Bool((Float32(blend) > Float32(1))))) or Bool((not Bool(mg_can_morph(UInt64(g), Int32(first), Int32(c_next))))))):
        var c_temp_364 = Int32(fail(UInt64(c_literal_104())))
        return c_temp_364
    var c_result_365: Int32 = Int32((Int32(mg_shadow_material(UInt64(g), Int32(first), UInt64(model), Int32(texture))) if Bool(shadow) else Int32(mg_draw(UInt64(g), Int32(first), UInt64(model), Float32(r), Float32(green), Float32(b), Float32(rough), Float32(metal), Float32(emission), Int32(texture)))))
    if Bool((Int32(c_result_365) < Int32(0))):
        var c_temp_366 = Int32(c_result_365)
        return c_temp_366
    var draw_367: UInt64 = UInt64((UInt64(c_address(Pointer(to=c_ref[Draw](c_ref[Graphics](g)[].shadow_draws)[unsafe_offset=Int((UInt64(c_ref[Graphics](g)[].shadow_count) - UInt64(1)))]))) if Bool(shadow) else UInt64(c_address(Pointer(to=c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int((UInt64(c_ref[Graphics](g)[].color_count) - UInt64(1)))])))))
    c_ref[Draw](draw_367)[].next_mesh = Int32(c_next)
    c_ref[Draw](draw_367)[].c_object.pose[Int(0)] = Float32(blend)
    var c_temp_368 = Int32(0)
    _ = g
    return c_temp_368

@export("mg_draw_crossfade")
def mg_draw_crossfade(var g: UInt64, var first: Int32, var c_next: Int32, var target: Int32, var target_next: Int32, var blend: Float32, var target_blend: Float32, var fade: Float32, var model: UInt64, var r: Float32, var green: Float32, var b: Float32, var rough: Float32, var metal: Float32, var emission: Float32, var texture: Int32, var shadow: Int32) abi("C") -> Int32:
    if Bool((Bool((Bool((Bool((Bool((Bool((Bool((Bool((not Bool(isfinite(target_blend)))) or Bool((Float32(target_blend) < Float32(0))))) or Bool((Float32(target_blend) > Float32(1))))) or Bool((not Bool(isfinite(fade)))))) or Bool((Float32(fade) < Float32(0))))) or Bool((Float32(fade) > Float32(1))))) or Bool((not Bool(mg_can_morph(UInt64(g), Int32(first), Int32(target))))))) or Bool((not Bool(mg_can_morph(UInt64(g), Int32(first), Int32(target_next))))))):
        var c_temp_369 = Int32(fail(UInt64(c_literal_105())))
        return c_temp_369
    var c_result_370: Int32 = Int32(mg_draw_morph(UInt64(g), Int32(first), Int32(c_next), Float32(blend), UInt64(model), Float32(r), Float32(green), Float32(b), Float32(rough), Float32(metal), Float32(emission), Int32(texture), Int32(shadow)))
    if Bool((Int32(c_result_370) < Int32(0))):
        var c_temp_371 = Int32(c_result_370)
        return c_temp_371
    var draw_372: UInt64 = UInt64((UInt64(c_address(Pointer(to=c_ref[Draw](c_ref[Graphics](g)[].shadow_draws)[unsafe_offset=Int((UInt64(c_ref[Graphics](g)[].shadow_count) - UInt64(1)))]))) if Bool(shadow) else UInt64(c_address(Pointer(to=c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int((UInt64(c_ref[Graphics](g)[].color_count) - UInt64(1)))])))))
    c_ref[Draw](draw_372)[].target_mesh = Int32(target)
    c_ref[Draw](draw_372)[].target_next_mesh = Int32(target_next)
    c_ref[Draw](draw_372)[].c_object.pose[Int(1)] = Float32(target_blend)
    c_ref[Draw](draw_372)[].c_object.pose[Int(2)] = Float32(fade)
    var c_temp_373 = Int32(0)
    _ = g
    return c_temp_373

@export("mg_ui_scale")
def mg_ui_scale(var g: UInt64, var scale: Float32) abi("C"):
    if Bool((Bool((Float32(scale) >= Float32(0.25))) and Bool((Float32(scale) <= Float32(8.0))))):
        c_ref[Graphics](g)[].ui_scale = Float32(scale)

def ui_quad(var g: UInt64, var x: Float32, var y: Float32, var w: Float32, var h: Float32, var r: Float32, var green: Float32, var b: Float32, var a: Float32, var u: Float32, var v: Float32, var du: Float32, var dv: Float32) -> Int32:
    if Bool((UInt64((UInt64(c_ref[Graphics](g)[].quad_count) + UInt64(48))) > UInt64(c_ref[Graphics](g)[].quad_capacity))):
        var size_374: UInt64 = UInt64((UInt64((UInt64(c_ref[Graphics](g)[].quad_capacity) * UInt64(2))) if Bool(c_ref[Graphics](g)[].quad_capacity) else UInt64(4096)))
        var p_375: UInt64 = UInt64(c_nullable_address(external_call["realloc", CPointer](c_pointer(UInt64(c_ref[Graphics](g)[].quads)), UInt64((UInt64(size_374) * UInt64(UInt64(size_of[Float32]())))))))
        if Bool((not Bool(p_375))):
            var c_temp_376 = Int32(fail(UInt64(c_literal_106())))
            return c_temp_376
        c_ref[Graphics](g)[].quads = UInt64(p_375)
        c_ref[Graphics](g)[].quad_capacity = UInt64(size_374)
    var points_377 = Array[Float32, 12](fill=Float32(0))
    points_377[0] = Float32(x)
    points_377[1] = Float32(y)
    points_377[2] = Float32((Float32(x) + Float32(w)))
    points_377[3] = Float32(y)
    points_377[4] = Float32((Float32(x) + Float32(w)))
    points_377[5] = Float32((Float32(y) + Float32(h)))
    points_377[6] = Float32(x)
    points_377[7] = Float32(y)
    points_377[8] = Float32((Float32(x) + Float32(w)))
    points_377[9] = Float32((Float32(y) + Float32(h)))
    points_377[10] = Float32(x)
    points_377[11] = Float32((Float32(y) + Float32(h)))
    var coords_378 = Array[Float32, 12](fill=Float32(0))
    coords_378[0] = Float32(u)
    coords_378[1] = Float32(v)
    coords_378[2] = Float32((Float32(u) + Float32(du)))
    coords_378[3] = Float32(v)
    coords_378[4] = Float32((Float32(u) + Float32(du)))
    coords_378[5] = Float32((Float32(v) + Float32(dv)))
    coords_378[6] = Float32(u)
    coords_378[7] = Float32(v)
    coords_378[8] = Float32((Float32(u) + Float32(du)))
    coords_378[9] = Float32((Float32(v) + Float32(dv)))
    coords_378[10] = Float32(u)
    coords_378[11] = Float32((Float32(v) + Float32(dv)))
    var i_379: Int32 = Int32(0)
    while Bool((Int32(i_379) < Int32(6))):
        var p_380: UInt64 = UInt64((c_ref[Graphics](g)[].quads + UInt64(Int(c_ref[Graphics](g)[].quad_count) * size_of[Float32]())))
        c_ref[Float32](p_380)[unsafe_offset=Int(0)] = Float32((Float32(points_377[Int((Int32(i_379) * Int32(2)))]) * Float32(c_ref[Graphics](g)[].ui_scale)))
        c_ref[Float32](p_380)[unsafe_offset=Int(1)] = Float32((Float32(points_377[Int((Int32((Int32(i_379) * Int32(2))) + Int32(1)))]) * Float32(c_ref[Graphics](g)[].ui_scale)))
        c_ref[Float32](p_380)[unsafe_offset=Int(2)] = Float32(r)
        c_ref[Float32](p_380)[unsafe_offset=Int(3)] = Float32(green)
        c_ref[Float32](p_380)[unsafe_offset=Int(4)] = Float32(b)
        c_ref[Float32](p_380)[unsafe_offset=Int(5)] = Float32(a)
        c_ref[Float32](p_380)[unsafe_offset=Int(6)] = Float32(coords_378[Int((Int32(i_379) * Int32(2)))])
        c_ref[Float32](p_380)[unsafe_offset=Int(7)] = Float32(coords_378[Int((Int32((Int32(i_379) * Int32(2))) + Int32(1)))])
        c_ref[Graphics](g)[].quad_count += UInt64(8)
        i_379 += 1
    c_ref[Graphics](g)[].rendered = Int32(0)
    var c_temp_381 = Int32(0)
    return c_temp_381

@export("mg_rect")
def mg_rect(var g: UInt64, var x: Float32, var y: Float32, var w: Float32, var h: Float32, var r: Float32, var green: Float32, var b: Float32, var a: Float32) abi("C") -> Int32:
    var c_temp_382 = Int32(ui_quad(UInt64(g), Float32(x), Float32(y), Float32(w), Float32(h), Float32(r), Float32(green), Float32(b), Float32(a), Float32((-1)), Float32((-1)), Float32(0), Float32(0)))
    return c_temp_382

@export("mg_circle")
def mg_circle(var g: UInt64, var x: Float32, var y: Float32, var radius: Float32, var r: Float32, var green: Float32, var b: Float32, var a: Float32) abi("C") -> Int32:
    var c_temp_383 = Int32(ui_quad(UInt64(g), Float32((Float32(x) - Float32(radius))), Float32((Float32(y) - Float32(radius))), Float32((Float32(radius) * Float32(2))), Float32((Float32(radius) * Float32(2))), Float32(r), Float32(green), Float32(b), Float32(a), Float32((-3)), Float32(0), Float32(1), Float32(1)))
    return c_temp_383

@export("mg_font")
def mg_font(var g: UInt64, var texture: Int32) abi("C") -> Int32:
    texture=texture_index(g,texture)
    if Bool((Bool((Int32(texture) < Int32(0))) or Bool((Int32(texture) >= Int32(Int32(c_ref[Graphics](g)[].texture_count)))))):
        var c_temp_384 = Int32(fail(UInt64(c_literal_107())))
        return c_temp_384
    c_ref[Graphics](g)[].font_texture = Int32(texture)
    var c_temp_385 = Int32(0)
    return c_temp_385

@export("mg_text")
def mg_text(var g: UInt64, var text: UInt64, var x: Float32, var y: Float32, var r: Float32, var green: Float32, var b: Float32, var scale: Int32) abi("C") -> Int32:
    if Bool((Int32(c_ref[Graphics](g)[].font_texture) < Int32(0))):
        var c_temp_386 = Int32(0)
        return c_temp_386
    if Bool((Int32(scale) < Int32(1))):
        var c_temp_387 = Int32(fail(UInt64(c_literal_108())))
        return c_temp_387
    var left_388: Float32 = Float32(x)
    var p_389: UInt64 = UInt64(UInt64(text))
    while Bool(c_ref[UInt8](p_389)[]):
        var code_390: UInt32 = UInt32((Int32((Int32(c_ref[UInt8](p_389)[]) - Int32(32))) if Bool((Bool((Int32(c_ref[UInt8](p_389)[]) >= Int32(32))) and Bool((Int32(c_ref[UInt8](p_389)[]) < Int32(128))))) else Int32((Int32(63) - Int32(32)))))
        if Bool((Int32(c_ref[UInt8](p_389)[]) == Int32(10))):
            x = Float32(left_388)
            y += Float32((Int32(11) * Int32(scale)))
            p_389 += UInt64(size_of[UInt8]())
            continue
        if Bool((Bool((Int32(c_ref[UInt8](p_389)[]) != Int32(32))) and Bool((Int32(ui_quad(UInt64(g), Float32((Float32(x) - Float32(scale))), Float32((Float32(y) - Float32((Int32(2) * Int32(scale))))), Float32((Int32(8) * Int32(scale))), Float32((Int32(11) * Int32(scale))), Float32(r), Float32(green), Float32(b), Float32(1), Float32((Float32((UInt32(code_390) % UInt32(16))) / Float32(16.0))), Float32((Float32((UInt32(code_390) // UInt32(16))) / Float32(6.0))), Float32((Float32(1.0) / Float32(16))), Float32((Float32(1.0) / Float32(6))))) < Int32(0))))):
            var c_temp_391 = Int32((-1))
            return c_temp_391
        x += Float32((Int32(6) * Int32(scale)))
        p_389 += UInt64(size_of[UInt8]())
    var c_temp_392 = Int32(1)
    return c_temp_392

def viewport(var g: UInt64, var w: UInt32, var h: UInt32):
    var v_393 = VkViewport()
    v_393.x = Float32(0)
    v_393.y = Float32(0)
    v_393.width = Float32(Float32(w))
    v_393.height = Float32(Float32(h))
    v_393.minDepth = Float32(0)
    v_393.maxDepth = Float32(1)
    var scissor_394 = VkRect2D()
    scissor_394.offset.x = Int32(0)
    scissor_394.offset.y = Int32(0)
    scissor_394.extent.width = UInt32(w)
    scissor_394.extent.height = UInt32(h)
    external_call["vkCmdSetViewport", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), UInt32(0), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=v_393)))))
    external_call["vkCmdSetScissor", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), UInt32(0), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=scissor_394)))))
    _ = scissor_394^
    _ = v_393^

def record_draw(var g: UInt64, var draw: UInt64):
    var m_395: UInt64 = UInt64(mesh_at(UInt64(g), Int32(c_ref[Draw](draw)[].mesh)))
    var c_next_396: UInt64 = UInt64(mesh_at(UInt64(g), Int32(c_ref[Draw](draw)[].next_mesh)))
    var offsets_397 = Array[UInt64, 5](fill=UInt64(0))
    offsets_397[0] = UInt64(0)
    offsets_397[1] = UInt64(0)
    offsets_397[2] = UInt64(0)
    offsets_397[3] = UInt64(0)
    var buffers_398 = Array[UInt64, 5](fill=UInt64(0))
    buffers_398[0] = UInt64(c_ref[Mesh](m_395)[].vertices.buffer)
    buffers_398[1] = UInt64(c_ref[Mesh](c_next_396)[].vertices.buffer)
    buffers_398[2] = UInt64(c_ref[Mesh](mesh_at(UInt64(g), Int32(c_ref[Draw](draw)[].target_mesh)))[].vertices.buffer)
    buffers_398[3] = UInt64(c_ref[Mesh](mesh_at(UInt64(g), Int32(c_ref[Draw](draw)[].target_next_mesh)))[].vertices.buffer)
    offsets_397[0]=pool_offset(g,c_address(Pointer(to=c_ref[Mesh](m_395)[].vertices)))
    offsets_397[1]=pool_offset(g,c_address(Pointer(to=c_ref[Mesh](c_next_396)[].vertices)))
    offsets_397[2]=pool_offset(g,c_address(Pointer(to=c_ref[Mesh](mesh_at(g,c_ref[Draw](draw)[].target_mesh))[].vertices)))
    offsets_397[3]=pool_offset(g,c_address(Pointer(to=c_ref[Mesh](mesh_at(g,c_ref[Draw](draw)[].target_next_mesh))[].vertices)))
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    buffers_398[4]=state[].instance_buffer.buffer
    offsets_397[4]=UInt64(state[].frame_index)*state[].instance_stride
    var uniform_offset=UInt32(UInt64(state[].frame_index)*state[].uniform_stride+UInt64(state[].uniform_slice)*state[].uniform_slice_stride)
    var texture_slot=Int(c_ref[Draw](draw)[].texture)+1
    texture_used(g,texture_slot)
    var set_399: UInt64 = UInt64(c_ref[Graphics](g)[].textures[texture_slot].set)
    external_call["vkCmdBindDescriptorSets", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), Int32(0), c_pointer(UInt64(c_ref[Graphics](g)[].pipeline_layout)), UInt32(0), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=set_399)))), UInt32(1), c_pointer(c_address(Pointer(to=uniform_offset))))
    var object=c_ref[Draw](draw)[].c_object.copy()
    var bank=Float32(Int(state[].frame_index)*4*1024*1024)
    if Int32(object.params[3])&256:object.pose[3]+=bank
    if Int32(object.params[3])&512:object.pose[0]+=bank
    if Int32(object.params[3])&1024:object.pose[1]+=bank
    external_call["vkCmdPushConstants", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_ref[Graphics](g)[].pipeline_layout)), UInt32((Int32(1) | Int32(16))), UInt32(0), UInt32(UInt64(size_of[Object]())), c_pointer(UInt64(c_address(Pointer(to=object)))))
    _=object^
    external_call["vkCmdBindVertexBuffers", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), UInt32(0), UInt32(5), c_pointer(UInt64(c_address(Pointer(to=buffers_398)))), c_pointer(UInt64(c_address(Pointer(to=offsets_397)))))
    external_call["vkCmdBindIndexBuffer", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_ref[Mesh](m_395)[].indices.buffer)), pool_offset(g,c_address(Pointer(to=c_ref[Mesh](m_395)[].indices))), Int32(1))
    external_call["vkCmdDrawIndexed", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), UInt32(c_ref[Mesh](m_395)[].c_count), c_ref[Draw](draw)[].instance_count, UInt32(0), Int32(0), c_ref[Draw](draw)[].instance_first)
    _ = uniform_offset
    _ = offsets_397^
    _ = set_399
    _ = buffers_398^

def render(var g: UInt64) -> Int32:
    if Bool(c_ref[Graphics](g)[].rendered):
        var c_temp_400 = Int32(0)
        return c_temp_400
    if Bool((not Bool(c_ref[Graphics](g)[].frame_started))):
        var c_temp_401 = Int32(fail(UInt64(c_literal_109())))
        return c_temp_401
    if Bool((Bool((Int32(c_ref[Graphics](g)[].width) < Int32(1))) or Bool((Int32(c_ref[Graphics](g)[].height) < Int32(1))))):
        var c_temp_402 = Int32(0)
        return c_temp_402
    var i_403: UInt64 = UInt64(0)
    while Bool((UInt64(i_403) < UInt64(c_ref[Graphics](g)[].shadow_count))):
        if Bool((Bool((Bool((Bool((not Bool(mesh_at(UInt64(g), Int32(c_ref[Draw](c_ref[Graphics](g)[].shadow_draws)[unsafe_offset=Int(i_403)].mesh))))) or Bool((not Bool(mesh_at(UInt64(g), Int32(c_ref[Draw](c_ref[Graphics](g)[].shadow_draws)[unsafe_offset=Int(i_403)].next_mesh))))))) or Bool((not Bool(mesh_at(UInt64(g), Int32(c_ref[Draw](c_ref[Graphics](g)[].shadow_draws)[unsafe_offset=Int(i_403)].target_mesh))))))) or Bool((not Bool(mesh_at(UInt64(g), Int32(c_ref[Draw](c_ref[Graphics](g)[].shadow_draws)[unsafe_offset=Int(i_403)].target_next_mesh))))))):
            var c_temp_404 = Int32(fail(UInt64(c_literal_110())))
            return c_temp_404
        i_403 += 1
    var i_405: UInt64 = UInt64(0)
    while Bool((UInt64(i_405) < UInt64(c_ref[Graphics](g)[].color_count))):
        if Bool((Bool((Bool((Bool((not Bool(mesh_at(UInt64(g), Int32(c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int(i_405)].mesh))))) or Bool((not Bool(mesh_at(UInt64(g), Int32(c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int(i_405)].next_mesh))))))) or Bool((not Bool(mesh_at(UInt64(g), Int32(c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int(i_405)].target_mesh))))))) or Bool((not Bool(mesh_at(UInt64(g), Int32(c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int(i_405)].target_next_mesh))))))):
            var c_temp_406 = Int32(fail(UInt64(c_literal_111())))
            return c_temp_406
        i_405 += 1
    if targets_make(g)<0:return -1
    if frame_prepare(g,mg_error())<0:return -1
    if upload_flush(g)<0 or instances_upload(g)<0:return -1
    var skin_state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if skin_state[].skin_count>0:
        if buffer_write(g,c_address(Pointer(to=skin_state[].skin_buffer)),skin_state[].skin_cpu,UInt64(skin_state[].skin_count)*4)<0:return -1
    if cascade_uniforms_write(g)<0:
        var c_temp_407 = Int32((-1))
        _ = g
        return c_temp_407
    if Bool(c_ref[Graphics](g)[].quad_count):
        var size_408: UInt64 = UInt64((UInt64(c_ref[Graphics](g)[].quad_count) * UInt64(UInt64(size_of[Float32]()))))
        var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
        if state[].overlay_stride<size_408:
            if c_result(external_call["vkDeviceWaitIdle",Int32](c_pointer(c_ref[Graphics](g)[].device)),c_literal_26())<0:return -1
            buffer_drop(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].overlay_buffer))))
            if Bool((Int32(buffer_make(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].overlay_buffer))), max(UInt64(size_408),UInt64(65536))*UInt64(state[].frame_count), UInt32(128))) < Int32(0))):
                var c_temp_409 = Int32((-1))
                _ = g
                return c_temp_409
            state[].overlay_stride=c_ref[Graphics](g)[].overlay_buffer.size//UInt64(state[].frame_count)
        if Bool((Int32(buffer_write(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].overlay_buffer))), UInt64(c_ref[Graphics](g)[].quads), UInt64(UInt64(size_408)))) < Int32(0))):
            var c_temp_410 = Int32((-1))
            _ = g
            return c_temp_410
    if Bool((Int32(command_begin(UInt64(g))) < Int32(0))):
        var c_temp_411 = Int32((-1))
        _ = g
        return c_temp_411
    var ordered=VkMemoryBarrier(46,0,98304,98304)
    external_call["vkCmdPipelineBarrier",NoneType](c_pointer(c_ref[Graphics](g)[].command),UInt32(65536),UInt32(65536),UInt32(0),UInt32(1),c_pointer(c_address(Pointer(to=ordered))),UInt32(0),c_pointer(0),UInt32(0),c_pointer(0))
    _=ordered^
    if Bool(c_ref[Graphics](g)[].timestamps):
        external_call["vkCmdResetQueryPool", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_ref[Graphics](g)[].timestamps)), UInt32(0), UInt32(2))
        external_call["vkCmdWriteTimestamp", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), Int32(1), c_pointer(UInt64(c_ref[Graphics](g)[].timestamps)), UInt32(0))
    var depth_412 = VkClearValue()
    c_ref[VkClearDepthStencilValue](c_address(Pointer(to=depth_412)))[].depth = Float32(1)
    c_ref[VkClearDepthStencilValue](c_address(Pointer(to=depth_412)))[].stencil = UInt32(0)
    var c_pass_413 = VkRenderPassBeginInfo()
    c_pass_413.sType = Int32(43)
    c_pass_413.renderPass = UInt64(c_ref[Graphics](g)[].shadow_pass)
    c_pass_413.framebuffer = UInt64(c_ref[Graphics](g)[].shadow_fb)
    c_pass_413.renderArea.offset.x = Int32(0)
    c_pass_413.renderArea.offset.y = Int32(0)
    c_pass_413.renderArea.extent.width = UInt32(4096)
    c_pass_413.renderArea.extent.height = UInt32(4096)
    c_pass_413.clearValueCount = UInt32(1)
    c_pass_413.pClearValues = UInt64(c_address(Pointer(to=depth_412)))
    external_call["vkCmdBeginRenderPass", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_address(Pointer(to=c_pass_413)))), Int32(0))
    viewport(UInt64(g), UInt32(4096), UInt32(4096))
    external_call["vkCmdBindPipeline", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), Int32(0), c_pointer(UInt64(c_ref[Graphics](g)[].shadow_pipeline)))
    var shadow_state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    for cascade in range(max(1,Int(shadow_state[].cascade_count))):
        if shadow_state[].cascade_count>0:
            shadow_state[].uniform_slice=Int32(cascade+1)
            shadow_tile_viewport(g,cascade)
        for i_414 in range(Int(c_ref[Graphics](g)[].shadow_count)):
            record_draw(g,c_address(Pointer(to=c_ref[Draw](c_ref[Graphics](g)[].shadow_draws)[unsafe_offset=i_414])))
    shadow_state[].uniform_slice=0
    external_call["vkCmdEndRenderPass", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)))
    var has_water_415: Int32 = Int32(0)
    var i_416: UInt64 = UInt64(0)
    while Bool((UInt64(i_416) < UInt64(c_ref[Graphics](g)[].color_count))):
        if Bool((Int32(Int32(c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int(i_416)].c_object.params[Int(3)])) & Int32(64))):
            has_water_415 = Int32(1)
        i_416 += 1
    _ = i_416
    if Bool(has_water_415):
        c_pass_413.framebuffer = UInt64(c_ref[Graphics](g)[].scene_depth_fb)
        var c_temp_417 = VkExtent2D()
        c_temp_417.width = UInt32(c_ref[Graphics](g)[].width)
        c_temp_417.height = UInt32(c_ref[Graphics](g)[].height)
        c_pass_413.renderArea.extent = (c_temp_417).copy()
        external_call["vkCmdBeginRenderPass", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_address(Pointer(to=c_pass_413)))), Int32(0))
        viewport(UInt64(g), UInt32(c_ref[Graphics](g)[].width), UInt32(c_ref[Graphics](g)[].height))
        external_call["vkCmdBindPipeline", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), Int32(0), c_pointer(UInt64(c_ref[Graphics](g)[].scene_depth_pipeline)))
        var i_418: UInt64 = UInt64(0)
        while Bool((UInt64(i_418) < UInt64(c_ref[Graphics](g)[].color_count))):
            if Bool((not Bool((Int32(Int32(c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int(i_418)].c_object.params[Int(3)])) & Int32(64))))):
                record_draw(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int(i_418)]))))
            i_418 += 1
        _ = i_418
        external_call["vkCmdEndRenderPass", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)))
    var hdr=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var clear_419 = Array[VkClearValue, 2](fill=VkClearValue())
    c_ref[Array[Float32, 4]](c_address(Pointer(to=c_ref[VkClearColorValue](c_address(Pointer(to=clear_419[0])))[])))[][0] = Float32(0.57)
    c_ref[Array[Float32, 4]](c_address(Pointer(to=c_ref[VkClearColorValue](c_address(Pointer(to=clear_419[0])))[])))[][1] = Float32(0.63)
    c_ref[Array[Float32, 4]](c_address(Pointer(to=c_ref[VkClearColorValue](c_address(Pointer(to=clear_419[0])))[])))[][2] = Float32(0.68)
    c_ref[Array[Float32, 4]](c_address(Pointer(to=c_ref[VkClearColorValue](c_address(Pointer(to=clear_419[0])))[])))[][3] = Float32(1)
    c_ref[VkClearDepthStencilValue](c_address(Pointer(to=clear_419[1])))[].depth = Float32(1)
    c_ref[VkClearDepthStencilValue](c_address(Pointer(to=clear_419[1])))[].stencil = UInt32(0)
    if hdr[].hdr_enabled:
        for channel in range(3):c_ref[Array[Float32,4]](c_address(Pointer(to=clear_419[0])))[][channel]=c_ref[Graphics](g)[].frame.haze[channel]
    c_pass_413.renderPass = hdr[].hdr_pass if hdr[].hdr_enabled else c_ref[Graphics](g)[].color_pass
    c_pass_413.framebuffer = hdr[].hdr_fb if hdr[].hdr_enabled else c_ref[Graphics](g)[].color_fb
    var c_temp_420 = VkExtent2D()
    c_temp_420.width = UInt32(c_ref[Graphics](g)[].width)
    c_temp_420.height = UInt32(c_ref[Graphics](g)[].height)
    c_pass_413.renderArea.extent = (c_temp_420).copy()
    c_pass_413.clearValueCount = UInt32(2)
    c_pass_413.pClearValues = UInt64(c_address(Pointer(to=clear_419)))
    external_call["vkCmdBeginRenderPass", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_address(Pointer(to=c_pass_413)))), Int32(0))
    viewport(UInt64(g), UInt32(c_ref[Graphics](g)[].width), UInt32(c_ref[Graphics](g)[].height))
    external_call["vkCmdBindPipeline", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), Int32(0), c_pointer(UInt64(hdr[].hdr_pipeline if hdr[].hdr_enabled else c_ref[Graphics](g)[].world_pipeline)))
    var i_421: UInt64 = UInt64(0)
    while Bool((UInt64(i_421) < UInt64(c_ref[Graphics](g)[].color_count))):
        if Bool((not Bool((Int32(Int32(c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int(i_421)].c_object.params[Int(3)])) & Int32(64))))):
            record_draw(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int(i_421)]))))
        i_421 += 1
    _ = i_421
    if Bool(has_water_415):
        external_call["vkCmdEndRenderPass", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)))
        barrier(UInt64(g), UInt64(c_ref[Graphics](g)[].scene_color.image), UInt32(1), UInt32(0), UInt32(1), Int32(5), Int32(7), UInt32(128), UInt32(4096), UInt32(32), UInt32(4096))
        var copy_422 = VkImageCopy()
        copy_422.srcSubresource.aspectMask = UInt32(1)
        copy_422.srcSubresource.mipLevel = UInt32(0)
        copy_422.srcSubresource.baseArrayLayer = UInt32(0)
        copy_422.srcSubresource.layerCount = UInt32(1)
        copy_422.dstSubresource.aspectMask = UInt32(1)
        copy_422.dstSubresource.mipLevel = UInt32(0)
        copy_422.dstSubresource.baseArrayLayer = UInt32(0)
        copy_422.dstSubresource.layerCount = UInt32(1)
        copy_422.extent.width = UInt32(UInt32(c_ref[Graphics](g)[].width))
        copy_422.extent.height = UInt32(UInt32(c_ref[Graphics](g)[].height))
        copy_422.extent.depth = UInt32(1)
        external_call["vkCmdCopyImage", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(hdr[].hdr_color.image if hdr[].hdr_enabled else c_ref[Graphics](g)[].color.image)), Int32(6), c_pointer(UInt64(c_ref[Graphics](g)[].scene_color.image)), Int32(7), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=copy_422)))))
        barrier(UInt64(g), UInt64(c_ref[Graphics](g)[].scene_color.image), UInt32(1), UInt32(0), UInt32(1), Int32(7), Int32(5), UInt32(4096), UInt32(128), UInt32(4096), UInt32(32))
        c_pass_413.renderPass = hdr[].hdr_water_pass if hdr[].hdr_enabled else c_ref[Graphics](g)[].water_pass
        c_pass_413.clearValueCount = UInt32(0)
        c_pass_413.pClearValues = UInt64(UInt64(0))
        external_call["vkCmdBeginRenderPass", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_address(Pointer(to=c_pass_413)))), Int32(0))
        viewport(UInt64(g), UInt32(c_ref[Graphics](g)[].width), UInt32(c_ref[Graphics](g)[].height))
        external_call["vkCmdBindPipeline", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), Int32(0), c_pointer(UInt64(hdr[].hdr_pipeline if hdr[].hdr_enabled else c_ref[Graphics](g)[].world_pipeline)))
        var i_423: UInt64 = UInt64(0)
        while Bool((UInt64(i_423) < UInt64(c_ref[Graphics](g)[].color_count))):
            if Bool((Int32(Int32(c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int(i_423)].c_object.params[Int(3)])) & Int32(64))):
                record_draw(UInt64(g), UInt64(c_address(Pointer(to=c_ref[Draw](c_ref[Graphics](g)[].color_draws)[unsafe_offset=Int(i_423)]))))
            i_423 += 1
        _ = i_423
        _ = copy_422^
    if hdr[].hdr_enabled:
        external_call["vkCmdEndRenderPass",NoneType](c_pointer(c_ref[Graphics](g)[].command))
        barrier(g,hdr[].hdr_color.image,1,0,1,6,5,1024,128,256,32)
        c_pass_413.renderPass=hdr[].display_pass
        c_pass_413.framebuffer=hdr[].display_fb
        c_pass_413.clearValueCount=0
        c_pass_413.pClearValues=0
        external_call["vkCmdBeginRenderPass",NoneType](c_pointer(c_ref[Graphics](g)[].command),c_pointer(c_address(Pointer(to=c_pass_413))),Int32(0))
        viewport(g,UInt32(c_ref[Graphics](g)[].width),UInt32(c_ref[Graphics](g)[].height))
        external_call["vkCmdBindPipeline",NoneType](c_pointer(c_ref[Graphics](g)[].command),Int32(0),c_pointer(hdr[].display_pipeline))
        var display_set=c_ref[Graphics](g)[].textures[0].set
        var display_offset=UInt32(UInt64(hdr[].frame_index)*hdr[].uniform_stride)
        external_call["vkCmdBindDescriptorSets",NoneType](c_pointer(c_ref[Graphics](g)[].command),Int32(0),c_pointer(c_ref[Graphics](g)[].pipeline_layout),UInt32(0),UInt32(1),c_pointer(c_address(Pointer(to=display_set))),UInt32(1),c_pointer(c_address(Pointer(to=display_offset))))
        external_call["vkCmdDraw",NoneType](c_pointer(c_ref[Graphics](g)[].command),UInt32(3),UInt32(1),UInt32(0),UInt32(0))
        _=display_set
        _=display_offset
    if Bool(c_ref[Graphics](g)[].quad_count):
        var screen_424 = Array[Float32, 2](fill=Float32(0))
        screen_424[0] = Float32(Float32(c_ref[Graphics](g)[].width))
        screen_424[1] = Float32(Float32(c_ref[Graphics](g)[].height))
        var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
        var offset_425=UInt64(state[].frame_index)*state[].overlay_stride
        var uniform_offset=UInt32(UInt64(state[].frame_index)*state[].uniform_stride)
        external_call["vkCmdBindPipeline", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), Int32(0), c_pointer(UInt64(hdr[].display_overlay if hdr[].hdr_enabled else c_ref[Graphics](g)[].overlay_pipeline)))
        texture_used(g,Int(c_ref[Graphics](g)[].font_texture)+1)
        var ui_set_426: UInt64 = UInt64(c_ref[Graphics](g)[].textures[Int((Int32(c_ref[Graphics](g)[].font_texture) + Int32(1)))].set)
        external_call["vkCmdBindDescriptorSets", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), Int32(0), c_pointer(UInt64(c_ref[Graphics](g)[].pipeline_layout)), UInt32(0), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=ui_set_426)))), UInt32(1), c_pointer(c_address(Pointer(to=uniform_offset))))
        external_call["vkCmdPushConstants", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_ref[Graphics](g)[].pipeline_layout)), UInt32((Int32(1) | Int32(16))), UInt32(0), UInt32(UInt64(size_of[Array[Float32, 2]]())), c_pointer(UInt64(c_address(Pointer(to=screen_424)))))
        external_call["vkCmdBindVertexBuffers", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), UInt32(0), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].overlay_buffer.buffer)))), c_pointer(UInt64(c_address(Pointer(to=offset_425)))))
        external_call["vkCmdDraw", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), UInt32(UInt32((UInt64(c_ref[Graphics](g)[].quad_count) // UInt64(8)))), UInt32(1), UInt32(0), UInt32(0))
        _ = uniform_offset
        _ = ui_set_426
        _ = offset_425
        _ = screen_424^
    external_call["vkCmdEndRenderPass", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)))
    if Bool(c_ref[Graphics](g)[].timestamps):
        external_call["vkCmdWriteTimestamp", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), Int32(8192), c_pointer(UInt64(c_ref[Graphics](g)[].timestamps)), UInt32(1))
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var wait=UInt64(0)
    var signal=UInt64(0)
    if state[].presentation_active:
        record_present_blit(g,state[].presentation_index)
        wait=c_ref[Graphics](g)[].acquired
        signal=c_ref[UInt64](c_ref[Graphics](g)[].present_done)[unsafe_offset=Int(state[].presentation_index)]
    if Bool((Int32(command_submit_mode(g,wait,signal,Int32(state[].frame_count==1))) < Int32(0))):
        var c_temp_427 = Int32((-1))
        _ = g
        _ = depth_412^
        _ = c_pass_413^
        _ = clear_419^
        return c_temp_427
    if Bool(c_ref[Graphics](g)[].validation_errors):
        var c_temp_428 = Int32(fail(UInt64(c_literal_112())))
        _ = g
        _ = depth_412^
        _ = c_pass_413^
        _ = clear_419^
        return c_temp_428
    if Bool(c_ref[Graphics](g)[].timestamps) and state[].frame_count==1:
        var query_started_429: Float64 = Float64(milliseconds())
        var ticks_430 = Array[UInt64, 2](fill=UInt64(0))
        if Bool((Int32(c_result(Int32(external_call["vkGetQueryPoolResults", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].timestamps)), UInt32(0), UInt32(2), UInt64(UInt64(size_of[Array[UInt64, 2]]())), c_pointer(UInt64(c_address(Pointer(to=ticks_430)))), UInt64(UInt64(size_of[UInt64]())), UInt32(1))), UInt64(c_literal_113()))) < Int32(0))):
            var c_temp_431 = Int32((-1))
            _ = g
            _ = depth_412^
            _ = c_pass_413^
            _ = clear_419^
            _ = ticks_430^
            return c_temp_431
        c_ref[Graphics](g)[].detail_ms[Int(5)] += Float64((Float64(milliseconds()) - Float64(query_started_429)))
        var mask_432: UInt64 = UInt64((UInt64(18446744073709551615) if Bool((UInt32(c_ref[Graphics](g)[].timestamp_bits) == UInt32(64))) else UInt64((UInt64((UInt64(1) << UInt64(c_ref[Graphics](g)[].timestamp_bits))) - UInt64(1)))))
        c_ref[Graphics](g)[].stage_ms[Int(4)] = Float64((Float64((Float64(Float64((UInt64((UInt64(ticks_430[Int(1)]) - UInt64(ticks_430[Int(0)]))) & UInt64(mask_432)))) * Float64(c_ref[Graphics](g)[].timestamp_period))) / Float64(1000000.0)))
        _ = ticks_430^
    state[].frame_sequence+=1
    state[].frames[Int(state[].frame_index)].query_ready=Int32(Bool(c_ref[Graphics](g)[].timestamps))
    state[].frames[Int(state[].frame_index)].render_id=state[].frame_sequence
    if state[].frame_count==1:state[].gpu_frame=state[].frame_sequence
    state[].frame_prepared=0
    c_ref[Graphics](g)[].rendered = Int32(1)
    var c_temp_433 = Int32(0)
    _ = g
    _ = depth_412^
    _ = c_pass_413^
    _ = clear_419^
    return c_temp_433

def swapchain_make(var g: UInt64) -> Int32:
    var began_434: Float64 = Float64(milliseconds())
    if Bool((Int32(c_result(Int32(external_call["vkDeviceWaitIdle", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)))), UInt64(c_literal_26()))) < Int32(0))):
        var c_temp_435 = Int32((-1))
        return c_temp_435
    var caps_436 = VkSurfaceCapabilitiesKHR()
    if Bool((Int32(c_result(Int32(external_call["vkGetPhysicalDeviceSurfaceCapabilitiesKHR", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), c_pointer(UInt64(c_ref[Graphics](g)[].surface)), c_pointer(UInt64(c_address(Pointer(to=caps_436)))))), UInt64(c_literal_114()))) < Int32(0))):
        var c_temp_437 = Int32((-1))
        _ = caps_436^
        return c_temp_437
    if Bool((not Bool((UInt32(caps_436.supportedUsageFlags) & UInt32(2))))):
        var c_temp_438 = Int32(fail(UInt64(c_literal_115())))
        _ = caps_436^
        return c_temp_438
    var c_count_439: UInt32 = UInt32(0)
    if Bool((Int32(c_result(Int32(external_call["vkGetPhysicalDeviceSurfaceFormatsKHR", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), c_pointer(UInt64(c_ref[Graphics](g)[].surface)), c_pointer(UInt64(c_address(Pointer(to=c_count_439)))), c_pointer(UInt64(UInt64(0))))), UInt64(c_literal_116()))) < Int32(0))):
        var c_temp_440 = Int32((-1))
        _ = caps_436^
        _ = c_count_439
        return c_temp_440
    if Bool((not Bool(c_count_439))):
        var c_temp_441 = Int32(fail(UInt64(c_literal_117())))
        _ = caps_436^
        _ = c_count_439
        return c_temp_441
    var formats_442: UInt64 = UInt64(c_nullable_address(external_call["calloc", CPointer](UInt64(c_count_439), UInt64(UInt64(size_of[VkSurfaceFormatKHR]())))))
    if Bool((not Bool(formats_442))):
        var c_temp_443 = Int32(fail(UInt64(c_literal_118())))
        _ = caps_436^
        _ = c_count_439
        return c_temp_443
    var status_444: Int32 = Int32(external_call["vkGetPhysicalDeviceSurfaceFormatsKHR", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), c_pointer(UInt64(c_ref[Graphics](g)[].surface)), c_pointer(UInt64(c_address(Pointer(to=c_count_439)))), c_pointer(UInt64(formats_442))))
    if Bool((Int32(c_result(Int32(status_444), UInt64(c_literal_119()))) < Int32(0))):
        external_call["free", NoneType](c_pointer(UInt64(formats_442)))
        var c_temp_445 = Int32((-1))
        _ = caps_436^
        _ = c_count_439
        return c_temp_445
    var chosen_446 = VkSurfaceFormatKHR()
    chosen_446.c_format = Int32(0)
    chosen_446.colorSpace = Int32(0)
    var i_447: UInt32 = UInt32(0)
    while Bool((UInt32(i_447) < UInt32(c_count_439))):
        var candidate_448: Int32 = Int32(c_ref[VkSurfaceFormatKHR](formats_442)[unsafe_offset=Int(i_447)].c_format)
        if Bool((Int32(candidate_448) == Int32(0))):
            candidate_448 = Int32(44)
        var properties_449 = VkFormatProperties()
        external_call["vkGetPhysicalDeviceFormatProperties", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), Int32(candidate_448), c_pointer(UInt64(c_address(Pointer(to=properties_449)))))
        if Bool((Bool((Bool((Bool((Int32(candidate_448) == Int32(44))) or Bool((Int32(candidate_448) == Int32(37))))) and Bool((Int32(c_ref[VkSurfaceFormatKHR](formats_442)[unsafe_offset=Int(i_447)].colorSpace) == Int32(0))))) and Bool((UInt32(properties_449.optimalTilingFeatures) & UInt32(2048))))):
            var c_temp_450 = VkSurfaceFormatKHR()
            c_temp_450.c_format = Int32(candidate_448)
            c_temp_450.colorSpace = Int32(c_ref[VkSurfaceFormatKHR](formats_442)[unsafe_offset=Int(i_447)].colorSpace)
            chosen_446 = (c_temp_450).copy()
            _ = properties_449^
            break
        _ = properties_449^
        i_447 += 1
    external_call["free", NoneType](c_pointer(UInt64(formats_442)))
    if Bool((Int32(chosen_446.c_format) == Int32(0))):
        var c_temp_451 = Int32(fail(UInt64(c_literal_120())))
        _ = caps_436^
        _ = c_count_439
        return c_temp_451
    var mode_452: Int32 = Int32(2)
    var requested_453: UInt64 = UInt64(c_nullable_address(external_call["getenv", CPointer](c_pointer(UInt64(c_literal_121())))))
    if Bool((Bool((Bool(requested_453) and Bool(external_call["strcmp", Int32](c_pointer(UInt64(requested_453)), c_pointer(UInt64(c_literal_122())))))) and Bool(external_call["strcmp", Int32](c_pointer(UInt64(requested_453)), c_pointer(UInt64(c_literal_123())))))):
        var c_temp_454 = Int32(fail(UInt64(c_literal_124())))
        _ = caps_436^
        _ = c_count_439
        return c_temp_454
    var mode_count_455: UInt32 = UInt32(0)
    if Bool((Int32(c_result(Int32(external_call["vkGetPhysicalDeviceSurfacePresentModesKHR", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), c_pointer(UInt64(c_ref[Graphics](g)[].surface)), c_pointer(UInt64(c_address(Pointer(to=mode_count_455)))), c_pointer(UInt64(UInt64(0))))), UInt64(c_literal_125()))) < Int32(0))):
        var c_temp_456 = Int32((-1))
        _ = caps_436^
        _ = c_count_439
        _ = mode_count_455
        return c_temp_456
    var modes_457: UInt64 = UInt64(c_nullable_address(external_call["calloc", CPointer](UInt64(mode_count_455), UInt64(UInt64(size_of[Int32]())))))
    if Bool((not Bool(modes_457))):
        var c_temp_458 = Int32(fail(UInt64(c_literal_126())))
        _ = caps_436^
        _ = c_count_439
        _ = mode_count_455
        return c_temp_458
    status_444 = Int32(external_call["vkGetPhysicalDeviceSurfacePresentModesKHR", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].physical)), c_pointer(UInt64(c_ref[Graphics](g)[].surface)), c_pointer(UInt64(c_address(Pointer(to=mode_count_455)))), c_pointer(UInt64(modes_457))))
    if Bool((Int32(c_result(Int32(status_444), UInt64(c_literal_127()))) < Int32(0))):
        external_call["free", NoneType](c_pointer(UInt64(modes_457)))
        var c_temp_459 = Int32((-1))
        _ = caps_436^
        _ = c_count_439
        _ = mode_count_455
        return c_temp_459
    if Bool((Bool(requested_453) and Bool((not Bool(external_call["strcmp", Int32](c_pointer(UInt64(requested_453)), c_pointer(UInt64(c_literal_123())))))))):
        var i_460: UInt32 = UInt32(0)
        while Bool((UInt32(i_460) < UInt32(mode_count_455))):
            if Bool((Int32(c_ref[Int32](modes_457)[unsafe_offset=Int(i_460)]) == Int32(1))):
                mode_452 = Int32(c_ref[Int32](modes_457)[unsafe_offset=Int(i_460)])
            i_460 += 1
    c_ref[Graphics](g)[].present_modes = UInt32(0)
    var i_461: UInt32 = UInt32(0)
    while Bool((UInt32(i_461) < UInt32(mode_count_455))):
        if Bool((Int32(c_ref[Int32](modes_457)[unsafe_offset=Int(i_461)]) < Int32(32))):
            c_ref[Graphics](g)[].present_modes |= UInt32((UInt32(1) << UInt32(c_ref[Int32](modes_457)[unsafe_offset=Int(i_461)])))
        i_461 += 1
    c_ref[Graphics](g)[].surface_min_images = UInt32(caps_436.minImageCount)
    c_ref[Graphics](g)[].surface_max_images = UInt32(caps_436.maxImageCount)
    external_call["free", NoneType](c_pointer(UInt64(modes_457)))
    var extent_462 = caps_436.currentExtent.copy()
    if Bool((UInt32(extent_462.width) == UInt32(4294967295))):
        var c_temp_463 = VkExtent2D()
        c_temp_463.width = UInt32(UInt32(c_ref[Graphics](g)[].width))
        c_temp_463.height = UInt32(UInt32(c_ref[Graphics](g)[].height))
        extent_462 = (c_temp_463).copy()
        if Bool((UInt32(extent_462.width) < UInt32(caps_436.minImageExtent.width))):
            extent_462.width = UInt32(caps_436.minImageExtent.width)
        if Bool((UInt32(extent_462.height) < UInt32(caps_436.minImageExtent.height))):
            extent_462.height = UInt32(caps_436.minImageExtent.height)
        if Bool((UInt32(extent_462.width) > UInt32(caps_436.maxImageExtent.width))):
            extent_462.width = UInt32(caps_436.maxImageExtent.width)
        if Bool((UInt32(extent_462.height) > UInt32(caps_436.maxImageExtent.height))):
            extent_462.height = UInt32(caps_436.maxImageExtent.height)
    if Bool((Bool((not Bool(extent_462.width))) or Bool((not Bool(extent_462.height))))):
        var c_temp_464 = Int32(1)
        _ = caps_436^
        _ = c_count_439
        _ = mode_count_455
        return c_temp_464
    var images_465: UInt32 = UInt32((UInt32(caps_436.minImageCount) + UInt32(1)))
    var image_request_466: UInt64 = UInt64(c_nullable_address(external_call["getenv", CPointer](c_pointer(UInt64(c_literal_128())))))
    if Bool(image_request_466):
        if Bool((Bool((Bool((UInt64(external_call["strlen", UInt64](c_pointer(UInt64(image_request_466)))) != UInt64(1))) or Bool((Int32(c_ref[Int8](image_request_466)[unsafe_offset=Int(0)]) < Int32(50))))) or Bool((Int32(c_ref[Int8](image_request_466)[unsafe_offset=Int(0)]) > Int32(52))))):
            var c_temp_467 = Int32(fail(UInt64(c_literal_129())))
            _ = caps_436^
            _ = c_count_439
            _ = mode_count_455
            return c_temp_467
        images_465 = UInt32(UInt32((Int32(c_ref[Int8](image_request_466)[unsafe_offset=Int(0)]) - Int32(48))))
        if Bool((UInt32(images_465) < UInt32(caps_436.minImageCount))):
            images_465 = UInt32(caps_436.minImageCount)
    if Bool((Bool(caps_436.maxImageCount) and Bool((UInt32(images_465) > UInt32(caps_436.maxImageCount))))):
        images_465 = UInt32(caps_436.maxImageCount)
    var alpha_468: Int32 = Int32(1)
    var bit_469: UInt32 = UInt32(1)
    while Bool((UInt32(bit_469) <= UInt32(8))):
        if Bool((UInt32(caps_436.supportedCompositeAlpha) & UInt32(bit_469))):
            alpha_468 = Int32(Int32(bit_469))
            break
        bit_469 <<= UInt32(1)
    var info_470 = VkSwapchainCreateInfoKHR()
    info_470.sType = Int32(1000001000)
    info_470.surface = UInt64(c_ref[Graphics](g)[].surface)
    info_470.minImageCount = UInt32(images_465)
    info_470.imageFormat = Int32(chosen_446.c_format)
    info_470.imageColorSpace = Int32(chosen_446.colorSpace)
    info_470.imageExtent = (extent_462).copy()
    info_470.imageArrayLayers = UInt32(1)
    info_470.imageUsage = UInt32(2)
    info_470.imageSharingMode = Int32(0)
    info_470.preTransform = Int32(caps_436.currentTransform)
    info_470.compositeAlpha = Int32(alpha_468)
    info_470.presentMode = Int32(mode_452)
    info_470.clipped = UInt32(1)
    info_470.oldSwapchain = UInt64(c_ref[Graphics](g)[].swapchain)
    var replacement_471: UInt64 = UInt64(0)
    if Bool((Int32(c_result(Int32(external_call["vkCreateSwapchainKHR", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=info_470)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=replacement_471)))))), UInt64(c_literal_130()))) < Int32(0))):
        var c_temp_472 = Int32((-1))
        _ = caps_436^
        _ = c_count_439
        _ = mode_count_455
        _ = info_470^
        _ = replacement_471
        return c_temp_472
    if Bool(c_ref[Graphics](g)[].swapchain):
        external_call["vkDestroySwapchainKHR", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].swapchain)), c_pointer(UInt64(UInt64(0))))
    c_ref[Graphics](g)[].swapchain = UInt64(replacement_471)
    c_ref[Graphics](g)[].present_mode = Int32(mode_452)
    var i_473: UInt32 = UInt32(0)
    while Bool((Bool(c_ref[Graphics](g)[].present_done) and Bool((UInt32(i_473) < UInt32(c_ref[Graphics](g)[].swap_count))))):
        if Bool(c_ref[UInt64](c_ref[Graphics](g)[].present_done)[unsafe_offset=Int(i_473)]):
            external_call["vkDestroySemaphore", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[UInt64](c_ref[Graphics](g)[].present_done)[unsafe_offset=Int(i_473)])), c_pointer(UInt64(UInt64(0))))
        i_473 += 1
    external_call["free", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].present_done)))
    c_ref[Graphics](g)[].present_done = UInt64(UInt64(0))
    external_call["free", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].swap_images)))
    c_ref[Graphics](g)[].swap_images = UInt64(UInt64(0))
    c_ref[Graphics](g)[].swap_count = UInt32(0)
    if Bool((Int32(c_result(Int32(external_call["vkGetSwapchainImagesKHR", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].swapchain)), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].swap_count)))), c_pointer(UInt64(UInt64(0))))), UInt64(c_literal_131()))) < Int32(0))):
        var c_temp_474 = Int32((-1))
        _ = g
        _ = caps_436^
        _ = c_count_439
        _ = mode_count_455
        _ = info_470^
        _ = replacement_471
        return c_temp_474
    c_ref[Graphics](g)[].swap_images = UInt64(c_nullable_address(external_call["calloc", CPointer](UInt64(c_ref[Graphics](g)[].swap_count), UInt64(UInt64(size_of[UInt64]())))))
    if Bool((not Bool(c_ref[Graphics](g)[].swap_images))):
        var c_temp_475 = Int32(fail(UInt64(c_literal_132())))
        _ = g
        _ = caps_436^
        _ = c_count_439
        _ = mode_count_455
        _ = info_470^
        _ = replacement_471
        return c_temp_475
    if Bool((Int32(c_result(Int32(external_call["vkGetSwapchainImagesKHR", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].swapchain)), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].swap_count)))), c_pointer(UInt64(c_ref[Graphics](g)[].swap_images)))), UInt64(c_literal_133()))) < Int32(0))):
        var c_temp_476 = Int32((-1))
        _ = g
        _ = caps_436^
        _ = c_count_439
        _ = mode_count_455
        _ = info_470^
        _ = replacement_471
        return c_temp_476
    c_ref[Graphics](g)[].present_done = UInt64(c_nullable_address(external_call["calloc", CPointer](UInt64(c_ref[Graphics](g)[].swap_count), UInt64(UInt64(size_of[UInt64]())))))
    if Bool((not Bool(c_ref[Graphics](g)[].present_done))):
        var c_temp_477 = Int32(fail(UInt64(c_literal_134())))
        _ = g
        _ = caps_436^
        _ = c_count_439
        _ = mode_count_455
        _ = info_470^
        _ = replacement_471
        return c_temp_477
    var semaphore_478 = VkSemaphoreCreateInfo()
    semaphore_478.sType = Int32(9)
    var i_479: UInt32 = UInt32(0)
    while Bool((UInt32(i_479) < UInt32(c_ref[Graphics](g)[].swap_count))):
        if Bool((Int32(c_result(Int32(external_call["vkCreateSemaphore", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_address(Pointer(to=semaphore_478)))), c_pointer(UInt64(UInt64(0))), c_pointer(UInt64(c_address(Pointer(to=c_ref[UInt64](c_ref[Graphics](g)[].present_done)[unsafe_offset=Int(i_479)])))))), UInt64(c_literal_135()))) < Int32(0))):
            var c_temp_480 = Int32((-1))
            _ = g
            _ = caps_436^
            _ = c_count_439
            _ = mode_count_455
            _ = info_470^
            _ = replacement_471
            _ = semaphore_478^
            _ = i_479
            return c_temp_480
        i_479 += 1
    _ = i_479
    c_ref[Graphics](g)[].swap_width = UInt32(extent_462.width)
    c_ref[Graphics](g)[].swap_height = UInt32(extent_462.height)
    c_ref[Graphics](g)[].detail_ms[Int(4)] += Float64((Float64(milliseconds()) - Float64(began_434)))
    var c_temp_481 = Int32(0)
    _ = g
    _ = caps_436^
    _ = c_count_439
    _ = mode_count_455
    _ = info_470^
    _ = replacement_471
    _ = semaphore_478^
    return c_temp_481

@export("mg_snapshot")
def mg_snapshot(var g: UInt64, var path: UInt64) abi("C") -> Int32:
    if Bool((Bool((Int32(c_ref[Graphics](g)[].width) < Int32(1))) or Bool((Int32(c_ref[Graphics](g)[].height) < Int32(1))))):
        var c_temp_482 = Int32(fail(UInt64(c_literal_136())))
        return c_temp_482
    if Bool((Bool((Int32(render(UInt64(g))) < Int32(0))) or Bool((Int32(command_begin(UInt64(g))) < Int32(0))))):
        var c_temp_483 = Int32((-1))
        return c_temp_483
    var copy_484 = VkBufferImageCopy()
    copy_484.imageSubresource.aspectMask = UInt32(1)
    copy_484.imageSubresource.mipLevel = UInt32(0)
    copy_484.imageSubresource.baseArrayLayer = UInt32(0)
    copy_484.imageSubresource.layerCount = UInt32(1)
    copy_484.imageExtent.width = UInt32(UInt32(c_ref[Graphics](g)[].width))
    copy_484.imageExtent.height = UInt32(UInt32(c_ref[Graphics](g)[].height))
    copy_484.imageExtent.depth = UInt32(1)
    external_call["vkCmdCopyImageToBuffer", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_ref[Graphics](g)[].color.image)), Int32(6), c_pointer(UInt64(c_ref[Graphics](g)[].readback.buffer)), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=copy_484)))))
    var memory_485 = VkBufferMemoryBarrier()
    memory_485.sType = Int32(44)
    memory_485.srcAccessMask = UInt32(4096)
    memory_485.dstAccessMask = UInt32(8192)
    memory_485.srcQueueFamilyIndex = UInt32((~0))
    memory_485.dstQueueFamilyIndex = UInt32((~0))
    memory_485.buffer = UInt64(c_ref[Graphics](g)[].readback.buffer)
    memory_485.size = UInt64((~0))
    external_call["vkCmdPipelineBarrier", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), UInt32(4096), UInt32(16384), UInt32(0), UInt32(0), c_pointer(UInt64(UInt64(0))), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=memory_485)))), UInt32(0), c_pointer(UInt64(UInt64(0))))
    if Bool((Int32(command_submit(UInt64(g), UInt64(0), UInt64(0))) < Int32(0))):
        var c_temp_486 = Int32((-1))
        _ = copy_484^
        _ = memory_485^
        return c_temp_486
    var surface_487: UInt64 = UInt64(c_nullable_address(external_call["SDL_CreateSurface", CPointer](Int32(c_ref[Graphics](g)[].width), Int32(c_ref[Graphics](g)[].height), UInt32(386930691))))
    if Bool((not Bool(surface_487))):
        var c_temp_488 = Int32(fail(UInt64(c_nullable_address(external_call["SDL_GetError", CPointer]()))))
        _ = copy_484^
        _ = memory_485^
        return c_temp_488
    var pixels_489: UInt64 = UInt64(c_ref[Graphics](g)[].readback.mapped)
    var y_490: Int32 = Int32(0)
    while Bool((Int32(y_490) < Int32(c_ref[Graphics](g)[].height))):
        var x_491: Int32 = Int32(0)
        while Bool((Int32(x_491) < Int32(c_ref[Graphics](g)[].width))):
            var src_492: UInt64 = UInt64((pixels_489 + UInt64(Int((UInt64((UInt64((UInt64(UInt64(y_490)) * UInt64(c_ref[Graphics](g)[].width))) + UInt64(x_491))) * UInt64(4))) * size_of[UInt8]())))
            var dst_493: UInt64 = UInt64(((UInt64(c_ref[SDL_Surface](surface_487)[].pixels) + UInt64(Int((UInt64(UInt64(y_490)) * UInt64(c_ref[SDL_Surface](surface_487)[].pitch))) * size_of[UInt8]())) + UInt64(Int((Int32(x_491) * Int32(3))) * size_of[UInt8]())))
            _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(dst_493)), c_pointer(UInt64(src_492)), UInt64(3)))
            x_491 += 1
        y_490 += 1
    var rc_494: Bool = Bool(external_call["SDL_SaveBMP", Bool](c_pointer(UInt64(surface_487)), c_pointer(UInt64(path))))
    external_call["SDL_DestroySurface", NoneType](c_pointer(UInt64(surface_487)))
    if Bool((not rc_494)):
        var c_temp_495 = Int32(fail(UInt64(c_nullable_address(external_call["SDL_GetError", CPointer]()))))
        _ = copy_484^
        _ = memory_485^
        return c_temp_495
    if Bool(c_ref[Graphics](g)[].validation_errors):
        var c_temp_496 = Int32(fail(UInt64(c_literal_138())))
        _ = copy_484^
        _ = memory_485^
        return c_temp_496
    var c_temp_497 = Int32(0)
    _ = copy_484^
    _ = memory_485^
    return c_temp_497

def present_combined(g: UInt64) -> Int32:
    var began=milliseconds()
    if targets_make(g)<0:return -1
    if not c_ref[Graphics](g)[].swapchain or c_ref[Graphics](g)[].swap_width!=UInt32(c_ref[Graphics](g)[].width) or c_ref[Graphics](g)[].swap_height!=UInt32(c_ref[Graphics](g)[].height):
        var result=swapchain_make(g)
        if result:return -1 if result<0 else 0
    if frame_prepare(g,mg_error())<0:return -1
    var acquire_began=milliseconds()
    var index=UInt32(0)
    var acquired=external_call["vkAcquireNextImageKHR",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_ref[Graphics](g)[].swapchain),UInt64.MAX,c_pointer(c_ref[Graphics](g)[].acquired),c_pointer(0),c_pointer(c_address(Pointer(to=index))))
    if acquired==-1000001004:
        var result=swapchain_make(g)
        if result:return -1 if result<0 else 0
        acquired=external_call["vkAcquireNextImageKHR",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_ref[Graphics](g)[].swapchain),UInt64.MAX,c_pointer(c_ref[Graphics](g)[].acquired),c_pointer(0),c_pointer(c_address(Pointer(to=index))))
    c_ref[Graphics](g)[].stage_ms[1]=milliseconds()-acquire_began
    if acquired!=0 and acquired!=1000001003:return c_result(acquired,c_literal_140())
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    state[].presentation_active=1
    state[].presentation_index=index
    var result=render(g)
    state[].presentation_active=0
    if result<0:return -1
    c_ref[Graphics](g)[].stage_ms[0]=milliseconds()-began-c_ref[Graphics](g)[].stage_ms[1]
    var present=VkPresentInfoKHR()
    present.sType=1000001001
    present.waitSemaphoreCount=1
    present.pWaitSemaphores=c_address(Pointer(to=c_ref[UInt64](c_ref[Graphics](g)[].present_done)[unsafe_offset=Int(index)]))
    present.swapchainCount=1
    present.pSwapchains=c_address(Pointer(to=c_ref[Graphics](g)[].swapchain))
    present.pImageIndices=c_address(Pointer(to=index))
    began=milliseconds()
    var status=external_call["vkQueuePresentKHR",Int32](c_pointer(c_ref[Graphics](g)[].queue),c_pointer(c_address(Pointer(to=present))))
    c_ref[Graphics](g)[].stage_ms[3]=milliseconds()-began
    _=present^
    _=index
    if status==-1000001004 or status==1000001003 or acquired==1000001003:
        if swapchain_make(g)<0:return -1
    elif c_result(status,c_literal_141())<0:return -1
    if c_ref[Graphics](g)[].validation_errors:return fail(c_literal_142())
    return 0

def record_present_blit(g: UInt64,index: UInt32):
    var image_513: UInt64 = UInt64(c_ref[UInt64](c_ref[Graphics](g)[].swap_images)[unsafe_offset=Int(index)])
    barrier(UInt64(g), UInt64(image_513), UInt32(1), UInt32(0), UInt32(1), Int32(0), Int32(7), UInt32(4096), UInt32(4096), UInt32(0), UInt32(4096))
    var blit_514 = VkImageBlit()
    blit_514.srcSubresource.aspectMask = UInt32(1)
    blit_514.srcSubresource.mipLevel = UInt32(0)
    blit_514.srcSubresource.baseArrayLayer = UInt32(0)
    blit_514.srcSubresource.layerCount = UInt32(1)
    blit_514.srcOffsets[0].x = Int32(0)
    blit_514.srcOffsets[0].y = Int32(0)
    blit_514.srcOffsets[0].z = Int32(0)
    blit_514.srcOffsets[1].x = Int32(c_ref[Graphics](g)[].width)
    blit_514.srcOffsets[1].y = Int32(c_ref[Graphics](g)[].height)
    blit_514.srcOffsets[1].z = Int32(1)
    blit_514.dstSubresource.aspectMask = UInt32(1)
    blit_514.dstSubresource.mipLevel = UInt32(0)
    blit_514.dstSubresource.baseArrayLayer = UInt32(0)
    blit_514.dstSubresource.layerCount = UInt32(1)
    blit_514.dstOffsets[0].x = Int32(0)
    blit_514.dstOffsets[0].y = Int32(0)
    blit_514.dstOffsets[0].z = Int32(0)
    blit_514.dstOffsets[1].x = Int32(Int32(c_ref[Graphics](g)[].swap_width))
    blit_514.dstOffsets[1].y = Int32(Int32(c_ref[Graphics](g)[].swap_height))
    blit_514.dstOffsets[1].z = Int32(1)
    external_call["vkCmdBlitImage", NoneType](c_pointer(UInt64(c_ref[Graphics](g)[].command)), c_pointer(UInt64(c_ref[Graphics](g)[].color.image)), Int32(6), c_pointer(UInt64(image_513)), Int32(7), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=blit_514)))), Int32(0))
    barrier(UInt64(g), UInt64(image_513), UInt32(1), UInt32(0), UInt32(1), Int32(7), Int32(1000001002), UInt32(4096), UInt32(8192), UInt32(4096), UInt32(0))
    _=blit_514^

@export("mg_present")
def mg_present(var g: UInt64) abi("C") -> Int32:
    var started_498: Float64 = Float64(milliseconds())
    var i_499: Int32 = Int32(0)
    while Bool((Int32(i_499) < Int32(4))):
        c_ref[Graphics](g)[].stage_ms[Int(i_499)] = Float64(0)
        i_499 += 1
    var i_500: Int32 = Int32(0)
    while Bool((Int32(i_500) < Int32(6))):
        c_ref[Graphics](g)[].detail_ms[Int(i_500)] = Float64(0)
        i_500 += 1
    if Bool((not Bool(c_ref[Graphics](g)[].timestamps))):
        c_ref[Graphics](g)[].stage_ms[Int(4)] = Float64((-1))
    if Bool((Bool((Int32(c_ref[Graphics](g)[].width) < Int32(1))) or Bool((Int32(c_ref[Graphics](g)[].height) < Int32(1))))):
        var c_temp_501 = Int32(0)
        return c_temp_501
    if c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].frame_count==2 and c_ref[Graphics](g)[].window and not c_ref[Graphics](g)[].rendered:
        return present_combined(g)
    if Bool((Int32(render(UInt64(g))) < Int32(0))):
        var c_temp_502 = Int32((-1))
        return c_temp_502
    c_ref[Graphics](g)[].stage_ms[Int(0)] = Float64((Float64(milliseconds()) - Float64(started_498)))
    if Bool((not Bool(c_ref[Graphics](g)[].window))):
        var c_temp_503 = Int32(0)
        return c_temp_503
    if Bool((Bool((Bool((not Bool(c_ref[Graphics](g)[].swapchain))) or Bool((UInt32(c_ref[Graphics](g)[].swap_width) != UInt32(UInt32(c_ref[Graphics](g)[].width)))))) or Bool((UInt32(c_ref[Graphics](g)[].swap_height) != UInt32(UInt32(c_ref[Graphics](g)[].height)))))):
        var rc_504: Int32 = Int32(swapchain_make(UInt64(g)))
        if Bool(rc_504):
            var c_temp_505 = Int32((Int32((-1)) if Bool((Int32(rc_504) < Int32(0))) else Int32(0)))
            return c_temp_505
    started_498 = Float64(milliseconds())
    if Bool((Int32(c_result(Int32(external_call["vkWaitForFences", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), UInt32(1), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].fence)))), UInt32(1), UInt64(18446744073709551615))), UInt64(c_literal_139()))) < Int32(0))):
        var c_temp_506 = Int32((-1))
        _ = g
        return c_temp_506
    c_ref[Graphics](g)[].detail_ms[Int(3)] += Float64((Float64(milliseconds()) - Float64(started_498)))
    var c_index_507: UInt32 = UInt32(0)
    var acquired_508: Int32 = Int32(external_call["vkAcquireNextImageKHR", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].swapchain)), UInt64(18446744073709551615), c_pointer(UInt64(c_ref[Graphics](g)[].acquired)), c_pointer(UInt64(0)), c_pointer(UInt64(c_address(Pointer(to=c_index_507))))))
    if Bool((Int32(acquired_508) == Int32(-1000001004))):
        var rc_509: Int32 = Int32(swapchain_make(UInt64(g)))
        if Bool(rc_509):
            var c_temp_510 = Int32((Int32((-1)) if Bool((Int32(rc_509) < Int32(0))) else Int32(0)))
            _ = g
            _ = c_index_507
            return c_temp_510
        acquired_508 = Int32(external_call["vkAcquireNextImageKHR", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].device)), c_pointer(UInt64(c_ref[Graphics](g)[].swapchain)), UInt64(18446744073709551615), c_pointer(UInt64(c_ref[Graphics](g)[].acquired)), c_pointer(UInt64(0)), c_pointer(UInt64(c_address(Pointer(to=c_index_507))))))
    c_ref[Graphics](g)[].stage_ms[Int(1)] = Float64((Float64(milliseconds()) - Float64(started_498)))
    started_498 = Float64(milliseconds())
    if Bool((Bool((Int32(acquired_508) != Int32(0))) and Bool((Int32(acquired_508) != Int32(1000001003))))):
        var c_temp_511 = Int32(c_result(Int32(acquired_508), UInt64(c_literal_140())))
        _ = g
        _ = c_index_507
        return c_temp_511
    if Bool((Int32(command_begin(UInt64(g))) < Int32(0))):
        var c_temp_512 = Int32((-1))
        _ = g
        _ = c_index_507
        return c_temp_512
    record_present_blit(g,c_index_507)
    if Bool((Int32(command_submit_mode(UInt64(g), UInt64(c_ref[Graphics](g)[].acquired), UInt64(c_ref[UInt64](c_ref[Graphics](g)[].present_done)[unsafe_offset=Int(c_index_507)]), Int32(c_ref[Graphics](g)[].present_sync))) < Int32(0))):
        var c_temp_515 = Int32((-1))
        _ = g
        _ = c_index_507
        return c_temp_515
    var present_516 = VkPresentInfoKHR()
    present_516.sType = Int32(1000001001)
    present_516.waitSemaphoreCount = UInt32(1)
    present_516.pWaitSemaphores = UInt64(c_address(Pointer(to=c_ref[UInt64](c_ref[Graphics](g)[].present_done)[unsafe_offset=Int(c_index_507)])))
    present_516.swapchainCount = UInt32(1)
    present_516.pSwapchains = UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].swapchain)))
    present_516.pImageIndices = UInt64(c_address(Pointer(to=c_index_507)))
    c_ref[Graphics](g)[].stage_ms[Int(2)] = Float64((Float64(milliseconds()) - Float64(started_498)))
    started_498 = Float64(milliseconds())
    var status_517: Int32 = Int32(external_call["vkQueuePresentKHR", Int32](c_pointer(UInt64(c_ref[Graphics](g)[].queue)), c_pointer(UInt64(c_address(Pointer(to=present_516))))))
    c_ref[Graphics](g)[].stage_ms[Int(3)] = Float64((Float64(milliseconds()) - Float64(started_498)))
    if Bool((Bool((Bool((Int32(status_517) == Int32(-1000001004))) or Bool((Int32(status_517) == Int32(1000001003))))) or Bool((Int32(acquired_508) == Int32(1000001003))))):
        var rc_518: Int32 = Int32(swapchain_make(UInt64(g)))
        if Bool((Int32(rc_518) < Int32(0))):
            var c_temp_519 = Int32((-1))
            _ = g
            _ = c_index_507
            _ = present_516^
            return c_temp_519
    else:
        if Bool((Int32(c_result(Int32(status_517), UInt64(c_literal_141()))) < Int32(0))):
            var c_temp_520 = Int32((-1))
            _ = g
            _ = c_index_507
            _ = present_516^
            return c_temp_520
    if Bool(c_ref[Graphics](g)[].validation_errors):
        var c_temp_521 = Int32(fail(UInt64(c_literal_142())))
        _ = g
        _ = c_index_507
        _ = present_516^
        return c_temp_521
    var c_temp_522 = Int32(0)
    _ = g
    _ = c_index_507
    _ = present_516^
    return c_temp_522

@export("mg_stage_ms")
def mg_stage_ms(var g: UInt64, var stage: Int32) abi("C") -> Float64:
    var c_temp_523 = Float64((Float64(c_ref[Graphics](g)[].stage_ms[Int(stage)]) if Bool((Bool((Int32(stage) >= Int32(0))) and Bool((Int32(stage) < Int32(5))))) else Float64((-1))))
    return c_temp_523

@export("mg_frame_stat")
def mg_frame_stat(g: UInt64,key: Int32) abi("C") -> UInt64:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if key==0:return UInt64(state[].frame_count)
    if key==1:return state[].frame_sequence
    if key==2:return state[].gpu_frame
    if key==3:return UInt64(state[].frame_index)
    return 0

@export("mg_detail_ms")
def mg_detail_ms(var g: UInt64, var stage: Int32) abi("C") -> Float64:
    var c_temp_524 = Float64((Float64(c_ref[Graphics](g)[].detail_ms[Int(stage)]) if Bool((Bool((Int32(stage) >= Int32(0))) and Bool((Int32(stage) < Int32(6))))) else Float64((-1))))
    return c_temp_524

@export("mg_surface_info")
def mg_surface_info(var g: UInt64, var key: Int32) abi("C") -> Int32:
    if key==4:
        if not c_ref[Graphics](g)[].window:return 0
        var display = external_call["SDL_GetDisplayForWindow", UInt32](c_pointer(c_ref[Graphics](g)[].window))
        var mode = c_nullable_address(external_call["SDL_GetCurrentDisplayMode", CPointer](display))
        return Int32(c_ref[SDL_DisplayMode](mode)[].refresh_rate) if mode else 0
    if key==0:return Int32(c_ref[Graphics](g)[].present_modes)
    if key==1:return Int32(c_ref[Graphics](g)[].surface_min_images)
    if key==2:return Int32(c_ref[Graphics](g)[].surface_max_images)
    if key==3:return Int32(c_ref[Graphics](g)[].swap_count)
    return -1

@export("mg_video_driver")
def mg_video_driver(var g: UInt64) abi("C") -> UInt64:
    _ = g
    var driver_528: UInt64 = UInt64(c_nullable_address(external_call["SDL_GetCurrentVideoDriver", CPointer]()))
    var c_temp_529 = UInt64((UInt64(driver_528) if Bool(driver_528) else UInt64(c_literal_143())))
    return c_temp_529

@export("mg_samples")
def mg_samples(var g: UInt64) abi("C") -> Int32:
    var c_temp_530 = Int32(Int32(c_ref[Graphics](g)[].samples))
    return c_temp_530

@export("mg_present_mode")
def mg_present_mode(var g: UInt64) abi("C") -> Int32:
    var c_temp_531 = Int32((Int32(Int32(c_ref[Graphics](g)[].present_mode)) if Bool(c_ref[Graphics](g)[].swapchain) else Int32((-1))))
    return c_temp_531

@export("mg_allocated_bytes")
def mg_allocated_bytes(var g: UInt64) abi("C") -> UInt64:
    var total_532: UInt64 = UInt64((UInt64((UInt64((UInt64((UInt64((UInt64((UInt64((UInt64((UInt64(c_ref[Graphics](g)[].shadow.allocated) + UInt64(c_ref[Graphics](g)[].color.allocated))) + UInt64(c_ref[Graphics](g)[].depth.allocated))) + UInt64(c_ref[Graphics](g)[].multisample.allocated))) + UInt64(c_ref[Graphics](g)[].scene_depth.allocated))) + UInt64(c_ref[Graphics](g)[].scene_color.allocated))) + UInt64(c_ref[Graphics](g)[].uniform.allocated))) + UInt64(c_ref[Graphics](g)[].overlay_buffer.allocated))) + UInt64(c_ref[Graphics](g)[].readback.allocated)))
    var i_533: Int32 = Int32(0)
    while Bool((Int32(i_533) <= Int32(256))):
        total_532 += UInt64(c_ref[Graphics](g)[].textures[Int(i_533)].image.allocated)
        i_533 += 1
    var i_534: Int32 = Int32(0)
    while Bool((Int32(i_534) < Int32(4096))):
        total_532 += UInt64((UInt64(c_ref[Graphics](g)[].meshes[Int(i_534)].vertices.allocated) + UInt64(c_ref[Graphics](g)[].meshes[Int(i_534)].indices.allocated)))
        i_534 += 1
    if c_ref[Graphics](g)[].scalability:
        var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
        for i in range(Int(state[].page_count)):total_532+=state[].pages[i].allocated
        total_532+=state[].instance_buffer.allocated+state[].skin_buffer.allocated+state[].hdr_color.allocated+state[].hdr_multisample.allocated
        for slot in range(2):total_532+=state[].uploads[slot].staging.allocated
    var c_temp_535 = UInt64(total_532)
    return c_temp_535

@export("mg_draws")
def mg_draws(var g: UInt64) abi("C") -> Int32:
    var c_temp_536 = Int32(Int32(c_ref[Graphics](g)[].color_count))
    return c_temp_536

@export("mg_triangles")
def mg_triangles(var g: UInt64) abi("C") -> Int32:
    var c_temp_537 = Int32(c_ref[Graphics](g)[].triangles)
    return c_temp_537

@export("mg_validation_errors")
def mg_validation_errors(var g: UInt64) abi("C") -> Int32:
    var c_temp_538 = Int32(c_ref[Graphics](g)[].validation_errors)
    return c_temp_538

@export("mg_resize")
def mg_resize(var g: UInt64, var width: Int32, var height: Int32) abi("C") -> Int32:
    if Bool((Bool((Bool((Bool((Int32(width) < Int32(1))) or Bool((Int32(height) < Int32(1))))) or Bool((Int32(width) > Int32(16384))))) or Bool((Int32(height) > Int32(16384))))):
        var c_temp_539 = Int32(fail(UInt64(c_literal_144())))
        return c_temp_539
    if Bool(c_ref[Graphics](g)[].window):
        _ = external_call["SDL_SetHint", Bool](c_pointer(UInt64(c_literal_145())), c_pointer(UInt64(c_literal_146())))
        if Bool((UInt32(external_call["SDL_GetWindowFlags", UInt64](c_pointer(UInt64(c_ref[Graphics](g)[].window)))) & UInt32(128))):
            _ = external_call["SDL_RestoreWindow", Bool](c_pointer(UInt64(c_ref[Graphics](g)[].window)))
        if not external_call["SDL_SetWindowSize", Bool](c_pointer(UInt64(c_ref[Graphics](g)[].window)), Int32(width), Int32(height)):return fail(c_nullable_address(external_call["SDL_GetError",CPointer]()))
        external_call["SDL_PumpEvents", NoneType]()
    c_ref[Graphics](g)[].width = Int32(width)
    c_ref[Graphics](g)[].height = Int32(height)
    c_ref[Graphics](g)[].rendered = Int32(0)
    var c_temp_540 = Int32(0)
    return c_temp_540

@export("mg_fullscreen")
def mg_fullscreen(var g: UInt64, var enabled: Int32) abi("C") -> Int32:
    if Bool((not Bool(c_ref[Graphics](g)[].window))):
        var c_temp_541 = Int32(fail(UInt64(c_literal_147())))
        return c_temp_541
    _ = external_call["SDL_SetHint", Bool](c_pointer(UInt64(c_literal_145())), c_pointer(UInt64(c_literal_146())))
    external_call["SDL_PumpEvents", NoneType]()
    if Bool((not external_call["SDL_SetWindowFullscreen", Bool](c_pointer(UInt64(c_ref[Graphics](g)[].window)), Bool(enabled)))):
        var c_temp_542 = Int32(fail(UInt64(c_nullable_address(external_call["SDL_GetError", CPointer]()))))
        return c_temp_542
    if not external_call["SDL_GetWindowSizeInPixels", Bool](c_pointer(UInt64(c_ref[Graphics](g)[].window)), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].width)))), c_pointer(UInt64(c_address(Pointer(to=c_ref[Graphics](g)[].height))))):return fail(c_nullable_address(external_call["SDL_GetError",CPointer]()))
    c_ref[Graphics](g)[].rendered = Int32(0)
    var c_temp_543 = Int32(0)
    _ = g
    return c_temp_543

@export("mg_is_fullscreen")
def mg_is_fullscreen(var g: UInt64) abi("C") -> Int32:
    var c_temp_544 = Int32((Bool(c_ref[Graphics](g)[].window) and Bool((UInt32((UInt32(external_call["SDL_GetWindowFlags", UInt64](c_pointer(UInt64(c_ref[Graphics](g)[].window)))) & UInt32(1))) != UInt32(0)))))
    return c_temp_544

def mesh_read(var path: UInt64, var vertices: UInt64, var c_count: UInt64) -> Int32:
    var f_545: UInt64 = UInt64(c_nullable_address(external_call["fopen", CPointer](c_pointer(UInt64(path)), c_pointer(UInt64(c_literal_80())))))
    if Bool((not Bool(f_545))):
        var c_temp_546 = Int32((-1))
        return c_temp_546
    var h_547 = Array[UInt32, 2](fill=UInt32(0))
    if Bool((Bool((Bool((Bool((Bool((UInt64(external_call["fread", UInt64](c_pointer(UInt64(c_address(Pointer(to=h_547)))), UInt64(4), UInt64(2), c_pointer(UInt64(f_545)))) != UInt64(2))) or Bool((UInt32(h_547[Int(0)]) != UInt32(827147865))))) or Bool((not Bool(h_547[Int(1)]))))) or Bool((UInt32(h_547[Int(1)]) > UInt32(3000000))))) or Bool((UInt32(h_547[Int(1)]) % UInt32(3))))):
        _ = external_call["fclose", Int32](c_pointer(UInt64(f_545)))
        var c_temp_548 = Int32((-1))
        _ = h_547^
        return c_temp_548
    var v_549: UInt64 = UInt64(c_nullable_address(external_call["malloc", CPointer](UInt64((UInt64(UInt64(h_547[Int(1)])) * UInt64(32))))))
    if Bool((not Bool(v_549))):
        _ = external_call["fclose", Int32](c_pointer(UInt64(f_545)))
        var c_temp_550 = Int32((-1))
        _ = h_547^
        return c_temp_550
    var ok_551: Int32 = Int32((Bool((UInt64(external_call["fread", UInt64](c_pointer(UInt64(v_549)), UInt64(32), UInt64(h_547[Int(1)]), c_pointer(UInt64(f_545)))) == UInt64(h_547[Int(1)]))) and Bool((Int32(external_call["fgetc", Int32](c_pointer(UInt64(f_545)))) == Int32((-1))))))
    _ = external_call["fclose", Int32](c_pointer(UInt64(f_545)))
    var i_552: UInt64 = UInt64(0)
    while Bool((Bool((UInt64(i_552) < UInt64((UInt64(UInt64(h_547[Int(1)])) * UInt64(8))))) and Bool(ok_551))):
        if Bool((not Bool(isfinite(c_ref[Float32](v_549)[unsafe_offset=Int(i_552)])))):
            ok_551 = Int32(0)
        i_552 += 1
    if Bool((not Bool(ok_551))):
        external_call["free", NoneType](c_pointer(UInt64(v_549)))
        var c_temp_553 = Int32((-1))
        _ = h_547^
        return c_temp_553
    c_ref[UInt64](vertices)[] = UInt64(v_549)
    c_ref[UInt32](c_count)[] = UInt32(h_547[Int(1)])
    var c_temp_554 = Int32(0)
    _ = h_547^
    return c_temp_554

def asset_size(var j: UInt64) -> UInt64:
    var f_555: UInt64 = UInt64(c_nullable_address(external_call["fopen", CPointer](c_pointer(UInt64(c_ref[MeshJob](j)[].path)), c_pointer(UInt64(c_literal_80())))))
    if Bool((not Bool(f_555))):
        var c_temp_556 = UInt64(0)
        return c_temp_556
    var h_557 = Array[UInt8, 54](fill=UInt8(0))
    var n_558: UInt64 = UInt64(external_call["fread", UInt64](c_pointer(UInt64(c_address(Pointer(to=h_557)))), UInt64(1), UInt64(UInt64(size_of[Array[UInt8, 54]]())), c_pointer(UInt64(f_555))))
    _ = external_call["fclose", Int32](c_pointer(UInt64(f_555)))
    if Bool((Int32(c_ref[MeshJob](j)[].kind) == Int32(0))):
        var a_559: UInt32 = UInt32(0)
        var b_560: UInt32 = UInt32(0)
        if Bool((UInt64(n_558) < UInt64(8))):
            var c_temp_561 = UInt64(0)
            _ = h_557^
            return c_temp_561
        _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_address(Pointer(to=a_559)))), c_pointer(UInt64(c_address(Pointer(to=h_557)))), UInt64(4)))
        _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_address(Pointer(to=b_560)))), c_pointer(UInt64((c_address(Pointer(to=h_557)) + UInt64(Int(4) * size_of[UInt8]())))), UInt64(4)))
        var c_temp_562 = UInt64((UInt64((UInt64(UInt64(b_560)) * UInt64(32))) if Bool((Bool((Bool((Bool((UInt32(a_559) == UInt32(827147865))) and Bool(b_560))) and Bool((UInt32((UInt32(b_560) % UInt32(3))) == UInt32(0))))) and Bool((UInt32(b_560) <= UInt32(3000000))))) else UInt64(0)))
        _ = h_557^
        _ = a_559
        _ = b_560
        return c_temp_562
    if Bool((Bool((Bool((UInt64(n_558) < UInt64(54))) or Bool((Int32(h_557[Int(0)]) != Int32(66))))) or Bool((Int32(h_557[Int(1)]) != Int32(77))))):
        var c_temp_563 = UInt64(0)
        _ = h_557^
        return c_temp_563
    var w_564: Int32 = Int32(0)
    var y_565: Int32 = Int32(0)
    _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_address(Pointer(to=w_564)))), c_pointer(UInt64((c_address(Pointer(to=h_557)) + UInt64(Int(18) * size_of[UInt8]())))), UInt64(4)))
    _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(c_address(Pointer(to=y_565)))), c_pointer(UInt64((c_address(Pointer(to=h_557)) + UInt64(Int(22) * size_of[UInt8]())))), UInt64(4)))
    if Bool((Bool((Bool((Bool((Bool((Int32(w_564) < Int32(1))) or Bool((Int32(w_564) > Int32(8192))))) or Bool((Int32(y_565) == Int32(0))))) or Bool((Int32(y_565) == Int32((Int32((-2147483647)) - Int32(1))))))) or Bool((Int32(external_call["abs", Int32](Int32(y_565))) > Int32(8192))))):
        var c_temp_566 = UInt64(0)
        _ = h_557^
        _ = w_564
        _ = y_565
        return c_temp_566
    var c_temp_567 = UInt64((UInt64((UInt64(UInt64(w_564)) * UInt64(UInt64(external_call["abs", Int32](Int32(y_565)))))) * UInt64(4)))
    _ = h_557^
    _ = w_564
    _ = y_565
    return c_temp_567

def image_read(var path: UInt64, var pixels: UInt64, var w: UInt64, var h: UInt64) -> Int32:
    var source_568: UInt64 = UInt64(c_nullable_address(external_call["SDL_LoadBMP", CPointer](c_pointer(UInt64(path)))))
    if Bool((not Bool(source_568))):
        var c_temp_569 = Int32((-1))
        return c_temp_569
    var image_570: UInt64 = UInt64(c_nullable_address(external_call["SDL_ConvertSurface", CPointer](c_pointer(UInt64(source_568)), UInt32(376840196))))
    external_call["SDL_DestroySurface", NoneType](c_pointer(UInt64(source_568)))
    if Bool((not Bool(image_570))):
        var c_temp_571 = Int32((-1))
        return c_temp_571
    var c_bytes_572: UInt64 = UInt64((UInt64((UInt64(UInt64(c_ref[SDL_Surface](image_570)[].w)) * UInt64(c_ref[SDL_Surface](image_570)[].h))) * UInt64(4)))
    var data_573: UInt64 = UInt64(c_nullable_address(external_call["malloc", CPointer](UInt64(c_bytes_572))))
    if Bool((not Bool(data_573))):
        external_call["SDL_DestroySurface", NoneType](c_pointer(UInt64(image_570)))
        var c_temp_574 = Int32((-1))
        return c_temp_574
    var y_575: Int32 = Int32(0)
    while Bool((Int32(y_575) < Int32(c_ref[SDL_Surface](image_570)[].h))):
        _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64((data_573 + UInt64(Int((UInt64((UInt64(UInt64(y_575)) * UInt64(c_ref[SDL_Surface](image_570)[].w))) * UInt64(4))) * size_of[UInt8]())))), c_pointer(UInt64((UInt64(c_ref[SDL_Surface](image_570)[].pixels) + UInt64(Int((UInt64(UInt64(y_575)) * UInt64(c_ref[SDL_Surface](image_570)[].pitch))) * size_of[UInt8]())))), UInt64((UInt64(UInt64(c_ref[SDL_Surface](image_570)[].w)) * UInt64(4)))))
        y_575 += 1
    c_ref[UInt64](pixels)[] = UInt64(data_573)
    c_ref[UInt32](w)[] = UInt32(UInt32(c_ref[SDL_Surface](image_570)[].w))
    c_ref[UInt32](h)[] = UInt32(UInt32(c_ref[SDL_Surface](image_570)[].h))
    external_call["SDL_DestroySurface", NoneType](c_pointer(UInt64(image_570)))
    var c_temp_576 = Int32(0)
    return c_temp_576

def mesh_reader(var unused: UInt64) abi("C") -> Int32:
    var process_state = port_globals()
    _ = unused
    var i_577: Int32 = Int32(0)
    while Bool((Int32(i_577) < Int32(c_ref[PortGlobals](process_state)[].loader.c_count))):
        var j_578: UInt64 = UInt64(c_address(Pointer(to=c_ref[PortGlobals](process_state)[].loader.jobs[Int(i_577)])))
        var c_bytes_579: UInt64 = UInt64(asset_size(UInt64(j_578)))
        var reserved_580: UInt64 = UInt64((UInt64(c_bytes_579) * UInt64((Int32(3) if Bool(c_ref[MeshJob](j_578)[].kind) else Int32(1)))))
        _ = external_call["SDL_LockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
        if Bool((Bool((not Bool(c_bytes_579))) or Bool((UInt64(reserved_580) > UInt64((UInt32((UInt32(64) * UInt32(1024))) * UInt32(1024))))))):
            c_ref[MeshJob](j_578)[].state = Int32((-1))
            _ = external_call["SDL_UnlockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
            i_577 += 1
            continue
        while Bool((Bool((Bool((Int32(c_ref[PortGlobals](process_state)[].loader.ready) >= Int32(3))) or Bool((UInt64((UInt64(c_ref[PortGlobals](process_state)[].loader.c_bytes) + UInt64(reserved_580))) > UInt64((UInt32((UInt32(64) * UInt32(1024))) * UInt32(1024))))))) and Bool((not Bool(c_ref[PortGlobals](process_state)[].loader.cancel))))):
            _ = external_call["SDL_WaitCondition", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.changed)), c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
        if Bool(c_ref[PortGlobals](process_state)[].loader.cancel):
            _ = external_call["SDL_UnlockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
            break
        c_ref[PortGlobals](process_state)[].loader.c_bytes += UInt64(reserved_580)
        if Bool((UInt64(c_ref[PortGlobals](process_state)[].loader.c_bytes) > UInt64(c_ref[PortGlobals](process_state)[].loader.peak))):
            c_ref[PortGlobals](process_state)[].loader.peak = UInt64(c_ref[PortGlobals](process_state)[].loader.c_bytes)
        c_ref[MeshJob](j_578)[].c_bytes = UInt64(reserved_580)
        _ = external_call["SDL_UnlockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
        var data_581: UInt64 = UInt64(UInt64(0))
        var n_582: UInt32 = UInt32(0)
        var height_583: UInt32 = UInt32(0)
        var ok_584: Int32 = Int32((Int32(image_read(UInt64(c_ref[MeshJob](j_578)[].path), UInt64(c_address(Pointer(to=data_581))), UInt64(c_address(Pointer(to=n_582))), UInt64(c_address(Pointer(to=height_583))))) if Bool(c_ref[MeshJob](j_578)[].kind) else Int32(mesh_read(UInt64(c_ref[MeshJob](j_578)[].path), UInt64(UInt64(c_address(Pointer(to=data_581)))), UInt64(c_address(Pointer(to=n_582)))))))
        if Bool((Bool((Int32(ok_584) == Int32(0))) and Bool((UInt64((UInt64((UInt64((UInt64(UInt64(n_582)) * UInt64(height_583))) * UInt64(4))) if Bool(c_ref[MeshJob](j_578)[].kind) else UInt64((UInt64(UInt64(n_582)) * UInt64(32))))) != UInt64(c_bytes_579))))):
            external_call["free", NoneType](c_pointer(UInt64(data_581)))
            data_581 = UInt64(UInt64(0))
            ok_584 = Int32((-1))
        _ = external_call["SDL_LockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
        c_ref[MeshJob](j_578)[].data = UInt64(data_581)
        c_ref[MeshJob](j_578)[].n = UInt32(n_582)
        c_ref[MeshJob](j_578)[].height = UInt32(height_583)
        c_ref[MeshJob](j_578)[].state = Int32((Int32((-1)) if Bool((Int32(ok_584) < Int32(0))) else Int32(1)))
        if Bool((Int32(ok_584) == Int32(0))):
            c_ref[PortGlobals](process_state)[].loader.ready += 1
            c_ref[PortGlobals](process_state)[].loader.c_bytes -= UInt64((UInt64(reserved_580) - UInt64(c_bytes_579)))
            c_ref[MeshJob](j_578)[].c_bytes = UInt64(c_bytes_579)
        else:
            c_ref[PortGlobals](process_state)[].loader.c_bytes -= UInt64(reserved_580)
            c_ref[MeshJob](j_578)[].c_bytes = UInt64(0)
        _ = external_call["SDL_BroadcastCondition", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.changed)))
        _ = external_call["SDL_UnlockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
        _ = n_582
        _ = height_583
        _ = data_581
        i_577 += 1
    _ = i_577
    var c_temp_585 = Int32(0)
    return c_temp_585

@export("mg_mesh_batch_cancel")
def mg_mesh_batch_cancel() abi("C"):
    var process_state = port_globals()
    if Bool(c_ref[PortGlobals](process_state)[].loader.lock):
        _ = external_call["SDL_LockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
        c_ref[PortGlobals](process_state)[].loader.cancel = Int32(1)
        _ = external_call["SDL_BroadcastCondition", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.changed)))
        _ = external_call["SDL_UnlockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
    if Bool(c_ref[PortGlobals](process_state)[].loader.thread):
        external_call["SDL_WaitThread", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.thread)), c_pointer(UInt64(UInt64(0))))
    var i_586: Int32 = Int32(0)
    while Bool((Int32(i_586) < Int32(c_ref[PortGlobals](process_state)[].loader.c_count))):
        external_call["free", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.jobs[Int(i_586)].path)))
        external_call["free", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.jobs[Int(i_586)].data)))
        i_586 += 1
    if Bool(c_ref[PortGlobals](process_state)[].loader.changed):
        external_call["SDL_DestroyCondition", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.changed)))
    if Bool(c_ref[PortGlobals](process_state)[].loader.lock):
        external_call["SDL_DestroyMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
    _ = c_nullable_address(external_call["SDL_memset", CPointer](c_pointer(UInt64(c_address(Pointer(to=c_ref[PortGlobals](process_state)[].loader)))), Int32(0), UInt64(UInt64(size_of[AssetLoader]()))))

@export("mg_asset_batch_add")
def mg_asset_batch_add(var path: UInt64, var kind: Int32) abi("C") -> Int32:
    var process_state = port_globals()
    if Bool((Bool((Bool(c_ref[PortGlobals](process_state)[].loader.thread) or Bool((Int32(c_ref[PortGlobals](process_state)[].loader.c_count) >= Int32(4096))))) or Bool((Bool((Int32(kind) != Int32(0))) and Bool((Int32(kind) != Int32(1))))))):
        var c_temp_587 = Int32((-1))
        return c_temp_587
    var i_588: Int32 = Int32(0)
    while Bool((Int32(i_588) < Int32(c_ref[PortGlobals](process_state)[].loader.c_count))):
        if Bool((not Bool(external_call["strcmp", Int32](c_pointer(UInt64(path)), c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.jobs[Int(i_588)].path)))))):
            var c_temp_589 = Int32((Int32(0) if Bool((Int32(c_ref[PortGlobals](process_state)[].loader.jobs[Int(i_588)].kind) == Int32(kind))) else Int32((-1))))
            return c_temp_589
        i_588 += 1
    var n_590: UInt64 = UInt64((UInt64(external_call["strlen", UInt64](c_pointer(UInt64(path)))) + UInt64(1)))
    var copy_591: UInt64 = UInt64(c_nullable_address(external_call["malloc", CPointer](UInt64(n_590))))
    if Bool((not Bool(copy_591))):
        var c_temp_592 = Int32((-1))
        return c_temp_592
    _ = c_nullable_address(external_call["memcpy", CPointer](c_pointer(UInt64(copy_591)), c_pointer(UInt64(path)), UInt64(n_590)))
    var c_temp_593 = MeshJob()
    c_temp_593.path = UInt64(copy_591)
    c_temp_593.kind = Int32(kind)
    c_ref[PortGlobals](process_state)[].loader.jobs[Int(c_increment[DType.int32](c_address(Pointer(to=c_ref[PortGlobals](process_state)[].loader.c_count)), 1, 1))] = (c_temp_593).copy()
    var c_temp_594 = Int32(0)
    return c_temp_594

@export("mg_mesh_batch_add")
def mg_mesh_batch_add(var path: UInt64) abi("C") -> Int32:
    var c_temp_595 = Int32(mg_asset_batch_add(UInt64(path), Int32(0)))
    return c_temp_595

@export("mg_mesh_batch_start")
def mg_mesh_batch_start() abi("C") -> Int32:
    var process_state = port_globals()
    c_ref[PortGlobals](process_state)[].loader.lock = UInt64(c_nullable_address(external_call["SDL_CreateMutex", CPointer]()))
    c_ref[PortGlobals](process_state)[].loader.changed = UInt64(c_nullable_address(external_call["SDL_CreateCondition", CPointer]()))
    if Bool((Bool((not Bool(c_ref[PortGlobals](process_state)[].loader.lock))) or Bool((not Bool(c_ref[PortGlobals](process_state)[].loader.changed))))):
        mg_mesh_batch_cancel()
        var c_temp_596 = Int32((-1))
        return c_temp_596
    var c_temp_597: def(var UInt64) abi("C") thin -> Int32 = mesh_reader
    c_ref[PortGlobals](process_state)[].loader.thread = UInt64(c_nullable_address(external_call["SDL_CreateThreadRuntime", CPointer](c_pointer(UInt64(Pointer(to=c_temp_597).unsafe_bitcast[UInt64]()[])), c_pointer(UInt64(c_literal_148())), c_pointer(UInt64(UInt64(0))), CPointer(None), CPointer(None))))
    if Bool((not Bool(c_ref[PortGlobals](process_state)[].loader.thread))):
        mg_mesh_batch_cancel()
        var c_temp_598 = Int32((-1))
        return c_temp_598
    var c_temp_599 = Int32(0)
    return c_temp_599

@export("mg_mesh_ready")
def mg_mesh_ready(var path: UInt64) abi("C") -> Int32:
    var process_state = port_globals()
    if Bool((not Bool(c_ref[PortGlobals](process_state)[].loader.lock))):
        var c_temp_600 = Int32(1)
        return c_temp_600
    var state_601: Int32 = Int32(2)
    _ = external_call["SDL_LockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
    var i_602: Int32 = Int32(0)
    while Bool((Int32(i_602) < Int32(c_ref[PortGlobals](process_state)[].loader.c_count))):
        if Bool((not Bool(external_call["strcmp", Int32](c_pointer(UInt64(path)), c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.jobs[Int(i_602)].path)))))):
            state_601 = Int32(c_ref[PortGlobals](process_state)[].loader.jobs[Int(i_602)].state)
            break
        i_602 += 1
    _ = external_call["SDL_UnlockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
    var c_temp_603 = Int32(state_601)
    return c_temp_603

@export("mg_asset_peak_bytes")
def mg_asset_peak_bytes() abi("C") -> UInt64:
    var process_state = port_globals()
    if Bool((not Bool(c_ref[PortGlobals](process_state)[].loader.lock))):
        var c_temp_604 = UInt64(0)
        return c_temp_604
    _ = external_call["SDL_LockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
    var c_bytes_605: UInt64 = UInt64(c_ref[PortGlobals](process_state)[].loader.peak)
    _ = external_call["SDL_UnlockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
    var c_temp_606 = UInt64(c_bytes_605)
    return c_temp_606

def asset_take(var path: UInt64, var kind: Int32) -> UInt64:
    var process_state = port_globals()
    if Bool((not Bool(c_ref[PortGlobals](process_state)[].loader.lock))):
        var c_temp_607 = UInt64(UInt64(0))
        return c_temp_607
    var job_608: UInt64 = UInt64(UInt64(0))
    _ = external_call["SDL_LockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
    var i_609: Int32 = Int32(0)
    while Bool((Int32(i_609) < Int32(c_ref[PortGlobals](process_state)[].loader.c_count))):
        if Bool((Bool((Bool((not Bool(external_call["strcmp", Int32](c_pointer(UInt64(path)), c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.jobs[Int(i_609)].path)))))) and Bool((Int32(c_ref[PortGlobals](process_state)[].loader.jobs[Int(i_609)].kind) == Int32(kind))))) and Bool((Int32(c_ref[PortGlobals](process_state)[].loader.jobs[Int(i_609)].state) == Int32(1))))):
            job_608 = UInt64(c_address(Pointer(to=c_ref[PortGlobals](process_state)[].loader.jobs[Int(i_609)])))
            c_ref[MeshJob](job_608)[].state = Int32(2)
            c_ref[PortGlobals](process_state)[].loader.ready -= 1
            break
        i_609 += 1
    _ = i_609
    _ = external_call["SDL_UnlockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
    var c_temp_610 = UInt64(job_608)
    return c_temp_610

def asset_done(var j: UInt64):
    var process_state = port_globals()
    if Bool((not Bool(j))):
        return
    external_call["free", NoneType](c_pointer(UInt64(c_ref[MeshJob](j)[].data)))
    c_ref[MeshJob](j)[].data = UInt64(UInt64(0))
    _ = external_call["SDL_LockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))
    c_ref[PortGlobals](process_state)[].loader.c_bytes -= UInt64(c_ref[MeshJob](j)[].c_bytes)
    c_ref[MeshJob](j)[].c_bytes = UInt64(0)
    _ = external_call["SDL_BroadcastCondition", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.changed)))
    _ = external_call["SDL_UnlockMutex", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].loader.lock)))

@export("mg_asset_texture")
def mg_asset_texture(var g: UInt64, var path: UInt64, var linear: Int32) abi("C") -> Int32:
    var j_611: UInt64 = UInt64(asset_take(UInt64(path), Int32(1)))
    if Bool((not Bool(j_611))):
        var c_temp_612 = Int32((-1))
        return c_temp_612
    var id_613: Int32 = Int32(mg_texture_pixels(UInt64(g), UInt64(c_ref[MeshJob](j_611)[].data), Int32(Int32(c_ref[MeshJob](j_611)[].n)), Int32(Int32(c_ref[MeshJob](j_611)[].height)), Int32(linear)))
    asset_done(UInt64(j_611))
    var c_temp_614 = Int32(id_613)
    return c_temp_614

@export("mg_asset_mesh")
def mg_asset_mesh(var g: UInt64, var path: UInt64) abi("C") -> Int32:
    var j_615: UInt64 = UInt64(asset_take(UInt64(path), Int32(0)))
    var v_616: UInt64 = UInt64((UInt64(c_ref[MeshJob](j_615)[].data) if Bool(j_615) else UInt64(UInt64(0))))
    var n_617: UInt32 = UInt32((UInt32(c_ref[MeshJob](j_615)[].n) if Bool(j_615) else UInt32(0)))
    if Bool((Bool((not Bool(v_616))) and Bool((Int32(mesh_read(UInt64(path), UInt64(c_address(Pointer(to=v_616))), UInt64(c_address(Pointer(to=n_617))))) < Int32(0))))):
        var c_temp_618 = Int32((-1))
        _ = v_616
        _ = n_617
        return c_temp_618
    var idx_619: UInt64 = UInt64(c_nullable_address(external_call["malloc", CPointer](UInt64((UInt64(UInt64(n_617)) * UInt64(4))))))
    var c_result_620: Int32 = Int32((-1))
    if Bool(idx_619):
        var i_621: UInt32 = UInt32(0)
        while Bool((UInt32(i_621) < UInt32(n_617))):
            c_ref[UInt32](idx_619)[unsafe_offset=Int(i_621)] = UInt32(i_621)
            i_621 += 1
        c_result_620 = Int32(mg_mesh(UInt64(g), UInt64(v_616), Int32((Int32(Int32(n_617)) * Int32(8))), UInt64(idx_619), Int32(Int32(n_617))))
        external_call["free", NoneType](c_pointer(UInt64(idx_619)))
    if Bool(j_615):
        asset_done(UInt64(j_615))
    else:
        external_call["free", NoneType](c_pointer(UInt64(v_616)))
    var c_temp_622 = Int32(c_result_620)
    _ = v_616
    _ = n_617
    return c_temp_622

def mix(var unused: UInt64, var stream: UInt64, var c_bytes: Int32) abi("C"):
    var process_state = port_globals()
    _ = unused
    var c_out_623: UInt64 = UInt64(UInt64(stream))
    var n_624: Int32 = Int32((Int32(c_bytes) // Int32(4)))
    var i_625: Int32 = Int32(0)
    while Bool((Int32(i_625) < Int32(n_624))):
        var value_626: Float32 = Float32(0)
        var j_627: Int32 = Int32(0)
        while Bool((Int32(j_627) < Int32(12))):
            var v_628: UInt64 = UInt64(c_address(Pointer(to=c_ref[PortGlobals](process_state)[].voices[Int(j_627)])))
            if Bool((Int32(c_ref[Voice](v_628)[].id) < Int32(0))):
                j_627 += 1
                continue
            if Bool((Int32(c_ref[Voice](v_628)[].pos) >= Int32(c_ref[PortGlobals](process_state)[].lengths[Int(c_ref[Voice](v_628)[].id)]))):
                if Bool(c_ref[Voice](v_628)[].loop):
                    c_ref[Voice](v_628)[].pos = Int32(0)
                else:
                    c_ref[Voice](v_628)[].id = Int32((-1))
                    j_627 += 1
                    continue
            value_626 += Float32((Float32((Float32((Float32(c_ref[Float32](c_ref[PortGlobals](process_state)[].samples[Int(c_ref[Voice](v_628)[].id)])[unsafe_offset=Int(c_increment[DType.int32](c_address(Pointer(to=c_ref[Voice](v_628)[].pos)), 1, 1))]) * Float32(c_ref[Voice](v_628)[].gain))) * Float32((Float32(c_ref[PortGlobals](process_state)[].music_gain) if Bool(c_ref[Voice](v_628)[].loop) else Float32(c_ref[PortGlobals](process_state)[].effects_gain))))) * Float32(c_ref[PortGlobals](process_state)[].master_gain)))
            _ = v_628
            j_627 += 1
        _ = j_627
        c_ref[Float32](c_out_623)[unsafe_offset=Int(i_625)] = Float32((Float32(0) if Bool(c_ref[PortGlobals](process_state)[].muted) else Float32(max(Float32((-1)), Float32(min(Float32(1), Float32(value_626)))))))
        i_625 += 1

def mix_stereo(var unused: UInt64,var stream: UInt64,var c_bytes: Int32) abi("C"):
    _ = unused
    var state=c_ref[PortGlobals](port_globals())
    var output=c_ref[Float32](stream)
    for frame in range(Int(c_bytes)//8):
        var left: Float32=0
        var right: Float32=0
        for slot in range(12):
            ref voice=state[].voices[slot]
            var id=Int(voice.id)
            if id<0:continue
            if id>=15:
                voice.id=-1
                continue
            if state[].lengths[id]<=0 or state[].samples[id]==0:
                voice.id=-1
                continue
            if voice.pos>=state[].lengths[id]:
                if voice.loop:voice.pos=0
                else:
                    voice.id=-1
                    continue
            var value=c_ref[Float32](state[].samples[id])[unsafe_offset=Int(voice.pos)]*voice.gain*state[].master_gain*(state[].music_gain if voice.loop else state[].effects_gain)
            voice.pos+=1
            left+=value*voice.left
            right+=value*voice.right
        output[unsafe_offset=frame*2]=0.0 if state[].muted else max(Float32(-1),min(Float32(1),left))
        output[unsafe_offset=frame*2+1]=0.0 if state[].muted else max(Float32(-1),min(Float32(1),right))

def audio_stream_callback(var userdata: UInt64,var stream: UInt64,var additional: Int32,var total: Int32) abi("C"):
    _=total
    var output=Array[Float32,2048](fill=0)
    var remaining=max(Int32(0),additional)
    while remaining>0:
        var amount=min(remaining,Int32(8192))
        amount=(amount+7)//8*8
        mix_stereo(userdata,c_address(output.unsafe_ptr()),amount)
        if not external_call["SDL_PutAudioStreamData",Bool](c_pointer(stream),output.unsafe_ptr(),amount):return
        remaining-=amount

@export("mg_audio_open")
def mg_audio_open() abi("C") -> Int32:
    var process_state = port_globals()
    if Bool(c_ref[PortGlobals](process_state)[].device):
        var c_temp_629 = Int32(0)
        return c_temp_629
    if Bool((not external_call["SDL_InitSubSystem", Bool](UInt32(16)))):
        _ = port_log(c_literal_149(), c_nullable_address(external_call["SDL_GetError", CPointer]()))
        var c_temp_630 = Int32((-1))
        return c_temp_630
    var spec=SDL_AudioSpec()
    spec.c_format=0x8120;spec.channels=2;spec.freq=44100
    var callback: def(var UInt64,var UInt64,var Int32,var Int32) abi("C") thin = audio_stream_callback
    for i in range(12):c_ref[PortGlobals](process_state)[].voices[i].id=-1
    var stream=c_nullable_address(external_call["SDL_OpenAudioDeviceStream",CPointer](UInt32(0xFFFFFFFF),Pointer(to=spec),c_pointer(Pointer(to=callback).unsafe_bitcast[UInt64]()[]),CPointer(None)))
    if not stream:
        external_call["SDL_QuitSubSystem",NoneType](UInt32(16))
        return -1
    c_ref[PortGlobals](process_state)[].device=stream
    if not external_call["SDL_ResumeAudioStreamDevice",Bool](c_pointer(stream)):
        external_call["SDL_DestroyAudioStream",NoneType](c_pointer(stream))
        c_ref[PortGlobals](process_state)[].device=0
        external_call["SDL_QuitSubSystem",NoneType](UInt32(16))
        return -1
    return 0


@export("mg_audio_load")
def mg_audio_load(var id: Int32,var path: UInt64) abi("C") -> Int32:
    var state=c_ref[PortGlobals](port_globals())
    if not state[].device or id<0 or id>=15 or not path:return -1
    var src=SDL_AudioSpec();var data=UInt64(0);var length=UInt32(0)
    if not external_call["SDL_LoadWAV",Bool](c_pointer(path),Pointer(to=src),Pointer(to=data),Pointer(to=length)):return -1
    var dst=SDL_AudioSpec();dst.c_format=0x8120;dst.channels=1;dst.freq=44100
    var converted=UInt64(0);var converted_length=Int32(0)
    var result=Int32(-1)
    var sample_bytes=Int(src.c_format&255)//8
    var output_frames=UInt64(0)
    if src.freq>0 and src.channels>0 and sample_bytes>0:
        output_frames=(UInt64(length)//UInt64(src.channels)//UInt64(sample_bytes)*44100+UInt64(src.freq)-1)//UInt64(src.freq)+512
    if length>0 and length<=64*1024*1024 and output_frames>0 and output_frames<=16*1024*1024:
        if external_call["SDL_ConvertAudioSamples",Bool](Pointer(to=src),c_pointer(data),Int32(length),Pointer(to=dst),Pointer(to=converted),Pointer(to=converted_length)):
            if converted_length>0 and converted_length<=64*1024*1024 and external_call["SDL_LockAudioStream", Bool](c_pointer(state[].device)):
                for i in range(12):
                    if state[].voices[i].id==id:state[].voices[i].id=-1
                external_call["SDL_free",NoneType](c_pointer(state[].samples[Int(id)]))
                state[].samples[Int(id)]=converted;state[].lengths[Int(id)]=converted_length//4
                _=external_call["SDL_UnlockAudioStream", Bool](c_pointer(state[].device))
                result=0
            else:external_call["SDL_free",NoneType](c_pointer(converted))
    external_call["SDL_free",NoneType](c_pointer(data))
    return result


def audio_start(var id: Int32,var loop: Int32,var left: Float32,var right: Float32):
    var process_state = port_globals()
    if Bool((Bool((Bool((Bool((not Bool(c_ref[PortGlobals](process_state)[].device))) or Bool((Int32(id) < Int32(0))))) or Bool((Int32(id) >= Int32(15))))) or Bool((not Bool(c_ref[PortGlobals](process_state)[].lengths[Int(id)]))))):
        return
    if not external_call["SDL_LockAudioStream", Bool](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].device))):return
    var slot_643: Int32 = Int32(0)
    if Bool((not Bool(loop))):
        slot_643 = Int32(1)
        var j_644: Int32 = Int32(1)
        while Bool((Int32(j_644) < Int32(12))):
            if Bool((Int32(c_ref[PortGlobals](process_state)[].voices[Int(j_644)].id) < Int32(0))):
                slot_643 = Int32(j_644)
                break
            j_644 += 1
    var c_temp_645 = Voice()
    c_temp_645.id = Int32(id)
    c_temp_645.pos = Int32(0)
    c_temp_645.loop = Int32(loop)
    c_temp_645.gain = Float32((Float32(.35) if Bool(loop) else Float32(.65)))
    c_temp_645.left=max(Float32(0),min(Float32(1),left))
    c_temp_645.right=max(Float32(0),min(Float32(1),right))
    c_ref[PortGlobals](process_state)[].voices[Int(slot_643)] = (c_temp_645).copy()
    _ = external_call["SDL_UnlockAudioStream", Bool](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].device)))

@export("mg_audio_play")
def mg_audio_play(var id: Int32,var loop: Int32) abi("C"):
    audio_start(id,loop,1.0,1.0)

@export("mg_audio_spatial")
def mg_audio_spatial(var id: Int32,var left: Float32,var right: Float32) abi("C"):
    audio_start(id,0,left,right)

@export("mg_audio_mute")
def mg_audio_mute(var value: Int32) abi("C"):
    var process_state = port_globals()
    if Bool(c_ref[PortGlobals](process_state)[].device):
        if not external_call["SDL_LockAudioStream", Bool](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].device))):return
    c_ref[PortGlobals](process_state)[].muted = Int32(value)
    if Bool(c_ref[PortGlobals](process_state)[].device):
        _ = external_call["SDL_UnlockAudioStream", Bool](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].device)))

@export("mg_audio_close")
def mg_audio_close() abi("C"):
    var process_state = port_globals()
    if Bool(c_ref[PortGlobals](process_state)[].device):
        external_call["SDL_DestroyAudioStream", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].device)))
        c_ref[PortGlobals](process_state)[].device = UInt64(0)
        external_call["SDL_QuitSubSystem",NoneType](UInt32(16))
    var i_646: Int32 = Int32(0)
    while Bool((Int32(i_646) < Int32(15))):
        external_call["SDL_free", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].samples[Int(i_646)])))
        c_ref[PortGlobals](process_state)[].samples[Int(i_646)] = UInt64(UInt64(0))
        c_ref[PortGlobals](process_state)[].lengths[Int(i_646)] = Int32(0)
        i_646 += 1

@export("mg_test_key")
def mg_test_key(var code: Int32, var pressed: Int32) abi("C") -> Int32:
    var event_647 = SDL_Event()
    _ = c_nullable_address(external_call["SDL_memset", CPointer](c_pointer(UInt64(c_address(Pointer(to=event_647)))), Int32(0), UInt64(UInt64(size_of[SDL_Event]()))))
    c_ref[UInt32](c_address(Pointer(to=event_647)))[] = UInt32((Int32(768) if Bool(pressed) else Int32(769)))
    c_ref[SDL_KeyboardEvent](c_address(Pointer(to=event_647)))[].scancode = Int32(Int32(code))
    c_ref[SDL_KeyboardEvent](c_address(Pointer(to=event_647)))[].down = Bool(pressed)
    var c_temp_648 = Int32(external_call["SDL_PushEvent", Bool](c_pointer(UInt64(c_address(Pointer(to=event_647))))))
    _ = event_647^
    return c_temp_648

@export("mg_audio_loaded")
def mg_audio_loaded() abi("C") -> Int32:
    var process_state = port_globals()
    var n_649: Int32 = Int32(0)
    var i_650: Int32 = Int32(0)
    while Bool((Int32(i_650) < Int32(15))):
        if Bool((Int32(c_ref[PortGlobals](process_state)[].lengths[Int(i_650)]) > Int32(0))):
            n_649 += 1
        i_650 += 1
    var c_temp_651 = Int32(n_649)
    return c_temp_651

@export("mg_peak_rss_kib")
def mg_peak_rss_kib() abi("C") -> UInt64:
    var usage_652 = rusage()
    var c_temp_653 = UInt64((UInt64(UInt64(usage_652.ru_maxrss)) if Bool((Int32(external_call["getrusage", Int32](Int32(0), c_pointer(UInt64(c_address(Pointer(to=usage_652)))))) == Int32(0))) else UInt64(0)))
    _ = usage_652^
    return c_temp_653

@export("mg_audio_levels")
def mg_audio_levels(var master: Float32, var music: Float32, var effects: Float32) abi("C"):
    var process_state = port_globals()
    if Bool(c_ref[PortGlobals](process_state)[].device):
        if not external_call["SDL_LockAudioStream", Bool](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].device))):return
    c_ref[PortGlobals](process_state)[].master_gain = Float32(max(Float32(0), Float32(min(Float32(1), Float32(master)))))
    c_ref[PortGlobals](process_state)[].music_gain = Float32(max(Float32(0), Float32(min(Float32(1), Float32(music)))))
    c_ref[PortGlobals](process_state)[].effects_gain = Float32(max(Float32(0), Float32(min(Float32(1), Float32(effects)))))
    if Bool(c_ref[PortGlobals](process_state)[].device):
        _ = external_call["SDL_UnlockAudioStream", Bool](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].device)))

@export("mg_pad_close")
def mg_pad_close() abi("C"):
    var process_state = port_globals()
    if Bool(c_ref[PortGlobals](process_state)[].controller):
        external_call["SDL_CloseGamepad", NoneType](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].controller)))
    c_ref[PortGlobals](process_state)[].controller = UInt64(UInt64(0))

@export("mg_pad_poll")
def mg_pad_poll(var focused: Int32) abi("C") -> UInt32:
    var process_state = port_globals()
    if Bool((not Bool((UInt32(external_call["SDL_WasInit", UInt32](UInt32(8192))) & UInt32(8192))))):
        if Bool((not external_call["SDL_InitSubSystem", Bool](UInt32(8192)))):
            var c_temp_654 = UInt32(0)
            return c_temp_654
    if Bool((Bool(c_ref[PortGlobals](process_state)[].controller) and Bool((not Bool(external_call["SDL_GamepadConnected", Bool](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].controller)))))))):
        mg_pad_close()
    if Bool((not Bool(c_ref[PortGlobals](process_state)[].controller))):
        var count=Int32(0)
        var ids=c_nullable_address(external_call["SDL_GetGamepads",CPointer](Pointer(to=count)))
        if ids:
            for i in range(Int(count)):
                var id=c_ref[UInt32](ids)[unsafe_offset=i]
                c_ref[PortGlobals](process_state)[].controller=c_nullable_address(external_call["SDL_OpenGamepad",CPointer](id))
                if c_ref[PortGlobals](process_state)[].controller:break
            external_call["SDL_free",NoneType](c_pointer(ids))
    var i_656: Int32 = Int32(0)
    while Bool((Int32(i_656) < Int32(4))):
        c_ref[PortGlobals](process_state)[].pad_axes[Int(i_656)] = Float64(0)
        i_656 += 1
    if Bool((Bool((not Bool(c_ref[PortGlobals](process_state)[].controller))) or Bool((not Bool(focused))))):
        var c_temp_657 = UInt32(0)
        return c_temp_657
    external_call["SDL_UpdateGamepads", NoneType]()
    var stick_658: Int32 = Int32(0)
    while Bool((Int32(stick_658) < Int32(2))):
        var x_659: Float64 = Float64((Float64(external_call["SDL_GetGamepadAxis", Int16](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].controller)), Int32(Int32((Int32(stick_658) * Int32(2)))))) / Float64(32768.0)))
        var y_660: Float64 = Float64((Float64(external_call["SDL_GetGamepadAxis", Int16](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].controller)), Int32(Int32((Int32((Int32(stick_658) * Int32(2))) + Int32(1)))))) / Float64(32768.0)))
        var magnitude_661: Float64 = Float64(sqrt(Float64((Float64((Float64(x_659) * Float64(x_659))) + Float64((Float64(y_660) * Float64(y_660)))))))
        if Bool((Float64(magnitude_661) > Float64(.18))):
            var scale_662: Float64 = Float64((Float64(external_call["fmin", Float64](Float64(1), Float64((Float64((Float64(magnitude_661) - Float64(.18))) / Float64(.82))))) / Float64(magnitude_661)))
            c_ref[PortGlobals](process_state)[].pad_axes[Int((Int32(stick_658) * Int32(2)))] = Float64((Float64(x_659) * Float64(scale_662)))
            c_ref[PortGlobals](process_state)[].pad_axes[Int((Int32((Int32(stick_658) * Int32(2))) + Int32(1)))] = Float64((Float64(y_660) * Float64(scale_662)))
        stick_658 += 1
    var buttons_663: UInt32 = UInt32(0)
    var i_664: Int32 = Int32(0)
    while Bool((Bool((Int32(i_664) < Int32(21))) and Bool((Int32(i_664) < Int32(32))))):
        if Bool(external_call["SDL_GetGamepadButton", Bool](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].controller)), Int32(Int32(i_664)))):
            buttons_663 |= UInt32((UInt32(1) << UInt32(i_664)))
        i_664 += 1
    var c_temp_665 = UInt32(buttons_663)
    return c_temp_665

@export("mg_pad_axis")
def mg_pad_axis(var axis: Int32) abi("C") -> Float64:
    var process_state = port_globals()
    var c_temp_666 = Float64((Float64(c_ref[PortGlobals](process_state)[].pad_axes[Int(axis)]) if Bool((Bool((Int32(axis) >= Int32(0))) and Bool((Int32(axis) < Int32(4))))) else Float64(0)))
    return c_temp_666

@export("mg_pad_connected")
def mg_pad_connected() abi("C") -> Int32:
    var process_state = port_globals()
    var c_temp_667 = Int32((Bool(c_ref[PortGlobals](process_state)[].controller) and Bool(external_call["SDL_GamepadConnected", Bool](c_pointer(UInt64(c_ref[PortGlobals](process_state)[].controller))))))
    return c_temp_667

@export("mg_window_focused")
def mg_window_focused() abi("C") -> Int32:
    var c_temp_668 = Int32((UInt64(c_nullable_address(external_call["SDL_GetKeyboardFocus", CPointer]())) != UInt64(UInt64(0))))
    return c_temp_668

# Atlas scalability: bounded pooled mesh buffers and one instance stream per frame.
def scalability_init(g: UInt64) -> Int32:
    var address=c_nullable_address(external_call["calloc",CPointer](UInt64(1),UInt64(size_of[Scalability]())))
    if not address:return fail(c_literal_73())
    c_ref[Graphics](g)[].scalability=address
    var state=c_ref[Scalability](address)
    var option=String("MOJO_VK_MESH_POOL")
    var value=external_call["getenv",CPointer](c_pointer(c_address(option.as_c_string_span().ptr())))
    state[].pool_enabled=Int32(not value or String(unsafe_from_utf8_ptr=value.value())!="0")
    var device_option=String("MOJO_VK_DEVICE_LOCAL_MESH")
    var device_value=external_call["getenv",CPointer](c_pointer(c_address(device_option.as_c_string_span().ptr())))
    state[].device_uploads=Int32(device_value and String(unsafe_from_utf8_ptr=device_value.value())=="1")
    _=device_option^
    var frame_option=String("MOJO_VK_FRAMES_IN_FLIGHT")
    var frame_value=external_call["getenv",CPointer](c_pointer(c_address(frame_option.as_c_string_span().ptr())))
    state[].frame_count=1 if frame_value and String(unsafe_from_utf8_ptr=frame_value.value())=="1" else 2
    var properties=VkPhysicalDeviceProperties()
    external_call["vkGetPhysicalDeviceProperties",NoneType](c_pointer(c_ref[Graphics](g)[].physical),c_pointer(c_address(Pointer(to=properties))))
    var alignment=max(UInt64(1),properties.limits.minUniformBufferOffsetAlignment)
    state[].uniform_slice_stride=(UInt64(size_of[CascadeUniform]())+alignment-1)//alignment*alignment
    state[].uniform_stride=state[].uniform_slice_stride*5
    c_ref[Graphics](g)[].stage_ms[4]=-1
    _=properties^
    _=frame_option^
    state[].instance_count=1
    for i in range(4):state[].instances[0][i*5]=1
    _=option^
    return 0

def pool_page(g: UInt64,b: UInt64) -> Int:
    if not c_ref[Graphics](g)[].scalability or c_ref[Buffer](b)[].memory:return -1
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    for i in range(Int(state[].page_count)):
        if state[].pages[i].buffer==c_ref[Buffer](b)[].buffer:return i
    return -1

def pool_offset(g: UInt64,b: UInt64) -> UInt64:
    var page=pool_page(g,b)
    if page<0:return 0
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    return c_ref[Buffer](b)[].mapped-state[].pages[page].mapped if state[].pages[page].mapped else c_ref[Buffer](b)[].mapped-1

def pool_free(g: UInt64,var span: PoolRange):
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    # Merge adjacent ranges before taking a metadata slot.
    var changed=True
    while changed:
        changed=False
        for i in range(Int(state[].range_count)):
            var other=state[].ranges[i].copy()
            if other.size==0 or other.page!=span.page:continue
            if other.offset+other.size==span.offset or span.offset+span.size==other.offset:
                span.offset=min(span.offset,other.offset)
                span.size+=other.size
                state[].ranges[i].size=0
                changed=True
    for i in range(Int(state[].range_count)):
        if state[].ranges[i].size==0:
            state[].ranges[i]=span^
            return
    if state[].range_count<16384:
        state[].ranges[Int(state[].range_count)]=span^
        state[].range_count+=1

def wait_frame(g: UInt64) -> Int32:
    var result=c_result(external_call["vkWaitForFences",Int32](c_pointer(c_ref[Graphics](g)[].device),UInt32(1),c_pointer(c_address(Pointer(to=c_ref[Graphics](g)[].fence))),UInt32(1),UInt64.MAX),c_literal_13())
    if result==0 and c_ref[Graphics](g)[].scalability:completion_poll(g)
    return result

def pool_reclaim(g: UInt64):
    if not c_ref[Graphics](g)[].scalability:return
    completion_poll(g)
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var kept=0
    for i in range(Int(state[].retired_count)):
        if state[].retired[i].serial<=state[].completed_serial:pool_free(g,state[].retired[i].range.copy())
        else:
            state[].retired[kept]=state[].retired[i].copy()
            kept+=1
    state[].retired_count=Int32(kept)

def pool_retire(g: UInt64,b: UInt64):
    var page=pool_page(g,b)
    if page<0:return
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var size=(c_ref[Buffer](b)[].size+255)&~UInt64(255)
    var pending=False
    for i in range(2):
        if state[].uploads[i].count>0:pending=True
    var serial=state[].submit_serial+UInt64(pending)
    var retired=RetiredRange(PoolRange(Int32(page),pool_offset(g,b),size),serial)
    if state[].retired_count==8192:
        if upload_flush(g)<0:return
        if external_call["vkDeviceWaitIdle",Int32](c_pointer(c_ref[Graphics](g)[].device))!=0:return
        pool_reclaim(g)
    if state[].retired_count<8192:
        state[].retired[Int(state[].retired_count)]=retired^
        state[].retired_count+=1

def pool_make(g: UInt64,b: UInt64,size: UInt64,usage: UInt32) -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if not state[].pool_enabled:return buffer_make(g,b,size,usage)
    pool_reclaim(g)
    var aligned=(size+255)&~UInt64(255)
    var slot=-1
    for i in range(Int(state[].range_count)):
        if state[].ranges[i].size>=aligned:
            slot=i
            break
    if slot<0:
        if state[].page_count==64:return fail(c_literal_76())
        var page=Int(state[].page_count)
        var bytes=max(UInt64(8*1024*1024),aligned)
        var reserved=UInt64(0)
        for i in range(Int(state[].page_count)):reserved+=state[].pages[i].size
        if reserved+bytes>UInt64(512*1024*1024):return fail(c_literal_76())
        if buffer_make(g,c_address(Pointer(to=state[].pages[page])),bytes,UInt32(192),Bool(state[].device_uploads))<0:return -1
        state[].page_count+=1
        pool_free(g,PoolRange(Int32(page),0,bytes))
        for i in range(Int(state[].range_count)):
            if state[].ranges[i].size>=aligned:
                slot=i
                break
    if slot<0:return fail(c_literal_76())
    var range=state[].ranges[slot].copy()
    var page=state[].pages[Int(range.page)].copy()
    c_ref[Buffer](b)[].buffer=page.buffer
    c_ref[Buffer](b)[].memory=0
    c_ref[Buffer](b)[].allocated=0
    c_ref[Buffer](b)[].size=size
    c_ref[Buffer](b)[].mapped=page.mapped+range.offset if page.mapped else range.offset+1
    state[].ranges[slot].offset+=aligned
    state[].ranges[slot].size-=aligned
    return 0

def instances_upload(g: UInt64) -> Int32:
    if wait_frame(g)<0:return -1
    pool_reclaim(g)
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var bytes=UInt64(state[].instance_count)*64
    var buffer=c_address(Pointer(to=state[].instance_buffer))
    if state[].instance_stride<bytes:
        if c_result(external_call["vkDeviceWaitIdle",Int32](c_pointer(c_ref[Graphics](g)[].device)),c_literal_26())<0:return -1
        buffer_drop(g,buffer)
        if buffer_make(g,buffer,max(bytes,UInt64(65536))*UInt64(state[].frame_count),UInt32(128))<0:return -1
        state[].instance_stride=state[].instance_buffer.size//UInt64(state[].frame_count)
    return buffer_write(g,buffer,c_address(Pointer(to=state[].instances)),bytes)

def scalability_drop(g: UInt64):
    var address=c_ref[Graphics](g)[].scalability
    if not address:return
    var state=c_ref[Scalability](address)
    hdr_drop(g)
    frame_drop(g)
    for i in range(4096):attributes_drop(g,i)
    for i in range(257):
        if state[].texture_samplers[i]:external_call["vkDestroySampler",NoneType](c_pointer(c_ref[Graphics](g)[].device),c_pointer(state[].texture_samplers[i]),c_pointer(0))
    buffer_drop(g,c_address(Pointer(to=state[].instance_buffer)))
    buffer_drop(g,c_address(Pointer(to=state[].staging)))
    buffer_drop(g,c_address(Pointer(to=state[].skin_buffer)))
    if state[].skin_cpu:external_call["free",NoneType](c_pointer(state[].skin_cpu))
    var dropper: BufferDropper=atlas_buffer_drop
    drop_upload_slots(g,dropper)
    _=dropper
    for i in range(Int(state[].page_count)):buffer_drop(g,c_address(Pointer(to=state[].pages[i])))
    external_call["free",NoneType](c_pointer(address))
    c_ref[Graphics](g)[].scalability=0

@export("mg_draw_instances")
def mg_draw_instances(g: UInt64,id: Int32,matrices: UInt64,count: Int32,r: Float32,green: Float32,b: Float32,rough: Float32,metal: Float32,emission: Float32,texture: Int32,shadow: Int32) abi("C") -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if count<1 or count>65535 or state[].instance_count+UInt32(count)>65536:return fail(c_literal_76())
    for i in range(Int(count)*16):
        if not isfinite(c_ref[Float32](matrices)[unsafe_offset=i]):return fail(c_literal_103())
    var identity=Array[Float32,16](fill=0)
    for i in range(4):identity[i*5]=1
    var result: Int32
    if shadow:result=mg_shadow_material(g,id,c_address(Pointer(to=identity)),texture)
    else:result=mg_draw(g,id,c_address(Pointer(to=identity)),r,green,b,rough,metal,emission,texture)
    if result<0:
        _=identity^
        return result
    var draw=c_ref[Draw](c_ref[Graphics](g)[].shadow_draws if shadow else c_ref[Graphics](g)[].color_draws)
    var index=Int(c_ref[Graphics](g)[].shadow_count if shadow else c_ref[Graphics](g)[].color_count)-1
    draw[unsafe_offset=index].instance_first=state[].instance_count
    draw[unsafe_offset=index].instance_count=UInt32(count)
    _=external_call["memcpy",CPointer](c_pointer(c_address(Pointer(to=state[].instances[Int(state[].instance_count)]))),c_pointer(matrices),UInt64(count)*64)
    state[].instance_count+=UInt32(count)
    if not shadow:c_ref[Graphics](g)[].triangles+=Int32(c_ref[Mesh](mesh_at(g,id))[].c_count//3)*(count-1)
    _=identity^
    return 0

@export("mg_draw_lod_instances")
def mg_draw_lod_instances(g: UInt64,id: Int32,matrices: UInt64,count: Int32,r: Float32,green: Float32,b: Float32,rough: Float32,metal: Float32,emission: Float32,texture: Int32,shadow: Int32,threshold: Float32,far: Int32) abi("C") -> Int32:
    if not isfinite(threshold) or threshold<0 or threshold>1 or (far!=0 and far!=1):return fail(c_literal_103())
    var result=mg_draw_instances(g,id,matrices,count,r,green,b,rough,metal,emission,texture,shadow)
    if result<0:return result
    var draws=c_ref[Draw](c_ref[Graphics](g)[].shadow_draws if shadow else c_ref[Graphics](g)[].color_draws)
    var index=Int(c_ref[Graphics](g)[].shadow_count if shadow else c_ref[Graphics](g)[].color_count)-1
    draws[unsafe_offset=index].c_object.params[3]=Float32(Int32(draws[unsafe_offset=index].c_object.params[3])|16384|Int32(32768 if far else 0))
    draws[unsafe_offset=index].c_object.pose[2]=threshold
    return 0

@export("mg_update_mesh")
def mg_update_mesh(g: UInt64,id: Int32,vertices: UInt64,floats: Int32,indices: UInt64,count: Int32) abi("C") -> Int32:
    var mesh=mesh_at(g,id)
    if not mesh or floats<0 or UInt64(floats)*4!=c_ref[Mesh](mesh)[].vertices.size:return fail(c_literal_74())
    if count<0 or UInt32(count)!=c_ref[Mesh](mesh)[].c_count:return fail(c_literal_74())
    var topology=UInt64(1469598103934665603)
    for i in range(Int(count)):topology=(topology ^ UInt64(c_ref[UInt32](indices)[unsafe_offset=i]))*UInt64(1099511628211)
    if topology!=c_ref[Mesh](mesh)[].topology:return fail(c_literal_74())
    for i in range(Int(floats)):
        if not isfinite(c_ref[Float32](vertices)[unsafe_offset=i]):return fail(c_literal_74())
    if wait_frame(g)<0:return -1
    return buffer_write(g,c_address(Pointer(to=c_ref[Mesh](mesh)[].vertices)),vertices,UInt64(floats)*4)

@export("mg_pool_pages")
def mg_pool_pages(g: UInt64) abi("C") -> Int32:
    return c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].page_count


def mesh_stage(g: UInt64,b: UInt64,data: UInt64,size: UInt64) -> Int32:
    var allocator: BufferAllocator=atlas_buffer_make
    var result=stage_mesh(g,b,data,size,allocator,mg_error())
    _=allocator
    return result

@export("_atlas_buffer_make")
def atlas_buffer_make(g: UInt64,b: UInt64,size: UInt64,usage: UInt32) abi("C") -> Int32:
    return buffer_make(g,b,size,usage)

@export("_atlas_buffer_drop")
def atlas_buffer_drop(g: UInt64,b: UInt64) abi("C"):
    buffer_drop(g,b)


def upload_flush(g: UInt64) -> Int32:
    var allocator: BufferAllocator=atlas_buffer_make
    var result=flush_upload_batch(g,allocator,mg_error())
    _=allocator
    return result

@export("mg_flush_uploads")
def mg_flush_uploads(g: UInt64) abi("C") -> Int32:
    return upload_flush(g)

@export("mg_upload_stat")
def mg_upload_stat(g: UInt64,key: Int32) abi("C") -> Float64:
    return upload_stat(g,key)

# Bounded, frame-banked shader skin data. Each draw owns a copied palette and
# influence block until submission; callers may reuse their host data at once.
@export("mg_draw_skin")
def mg_draw_skin(g: UInt64,id: Int32,data: UInt64,count: Int32,model: UInt64,r: Float32,green: Float32,b: Float32,rough: Float32,metal: Float32,emission: Float32,texture: Int32,shadow: Int32) abi("C") -> Int32:
    var mesh=mesh_at(g,id)
    if not mesh or not data or count<33 or count>4*1024*1024:return fail(c_literal_74())
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var slot=Int(UInt32(id)&4095)
    var attributes=state[].attribute_counts[slot]*UInt32(Int(state[].color_cpu[slot]!=0)+Int(state[].tangent_cpu[slot]!=0))
    if UInt64(state[].skin_count)+UInt64(count)+UInt64(attributes)>4*1024*1024:return fail(c_literal_76())
    for i in range(Int(count)):
        if not isfinite(c_ref[Float32](data)[unsafe_offset=i]):return fail(c_literal_74())
    var joints=Int(c_ref[Float32](data)[])
    var vertices=Int(c_ref[Mesh](mesh)[].vertices.size//32)
    if joints<1 or joints>4096 or Float32(joints)!=c_ref[Float32](data)[] or Int(count)!=1+joints*32+vertices*8:return fail(c_literal_74())
    for vertex in range(vertices):
        var sum=Float32(0)
        for influence in range(4):
            var start=1+joints*32+vertex*8+influence*2
            var joint=c_ref[Float32](data)[unsafe_offset=start]
            var weight=c_ref[Float32](data)[unsafe_offset=start+1]
            if joint<0 or joint>=Float32(joints) or joint!=Float32(Int(joint)) or weight<0:return fail(c_literal_74())
            sum+=weight
        if sum<1e-12 or not isfinite(sum):return fail(c_literal_74())
    var resolved=texture_index(g,texture)
    if resolved< -1:return fail(c_literal_103())
    if c_ref[Graphics](g)[].textures[Int(resolved)+1].normal&12:return fail(c_literal_103())
    if skin_storage_make(g)<0:return -1
    var result: Int32
    if shadow:result=mg_shadow_material(g,id,model,texture)
    else:result=mg_draw(g,id,model,r,green,b,rough,metal,emission,texture)
    if result<0:return result
    var draws=c_ref[Draw](c_ref[Graphics](g)[].shadow_draws if shadow else c_ref[Graphics](g)[].color_draws)
    var index=Int(c_ref[Graphics](g)[].shadow_count if shadow else c_ref[Graphics](g)[].color_count)-1
    draws[unsafe_offset=index].c_object.params[3]=Float32(Int32(draws[unsafe_offset=index].c_object.params[3])|256)
    draws[unsafe_offset=index].c_object.pose[3]=Float32(state[].skin_count)
    _=external_call["memcpy",CPointer](c_pointer(state[].skin_cpu+UInt64(state[].skin_count)*4),c_pointer(data),UInt64(count)*4)
    state[].skin_count+=UInt32(count)
    return 0

def texture_index(g: UInt64,id: Int32) -> Int32:
    if id== -1:return -1
    if id<0:return -2
    var slot=Int(UInt32(id)&255)+1
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if not state[].texture_alive[slot] or state[].texture_generations[slot]!=(UInt32(id)>>8):return -2
    return Int32(slot-1)

def texture_used(g: UInt64,slot: Int):
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    state[].texture_last_used[slot]=state[].submit_serial+1
    for channel in range(2):
        var source=state[].normal_source[slot] if channel==0 else state[].orm_source[slot]
        if source>0:state[].texture_last_used[Int(source)]=state[].submit_serial+1

@export("mg_texture_releasable")
def mg_texture_releasable(g: UInt64,id: Int32) abi("C") -> Int32:
    var index=texture_index(g,id)
    if index<0:return fail(c_literal_103())
    var slot=Int(index)+1
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    for i in range(1,257):
        if state[].texture_alive[i] and (state[].normal_source[i]==Int32(slot) or state[].orm_source[i]==Int32(slot)):return 0
    if not c_ref[Graphics](g)[].rendered:
        for pass_index in range(2):
            var count=c_ref[Graphics](g)[].shadow_count if pass_index==0 else c_ref[Graphics](g)[].color_count
            var draws=c_ref[Draw](c_ref[Graphics](g)[].shadow_draws if pass_index==0 else c_ref[Graphics](g)[].color_draws)
            for i in range(Int(count)):
                if draws[unsafe_offset=i].texture==index:return 0
        if c_ref[Graphics](g)[].quad_count>0 and c_ref[Graphics](g)[].font_texture==index:return 0
    completion_poll(g)
    return Int32(state[].texture_last_used[slot]<=state[].completed_serial)

@export("mg_release_texture")
def mg_release_texture(g: UInt64,id: Int32) abi("C") -> Int32:
    var ready=mg_texture_releasable(g,id)
    if ready<0:return ready
    if ready==0:return fail(c_literal_103())
    var index=texture_index(g,id)
    var slot=Int(index)+1
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var texture=c_ref[Graphics](g)[].textures[slot].set
    if texture:
        if c_result(external_call["vkFreeDescriptorSets",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_ref[Graphics](g)[].descriptors),UInt32(1),c_pointer(c_address(Pointer(to=texture)))),c_literal_26())<0:return -1
    image_drop(g,c_address(Pointer(to=c_ref[Graphics](g)[].textures[slot].image)))
    if state[].texture_samplers[slot]:external_call["vkDestroySampler",NoneType](c_pointer(c_ref[Graphics](g)[].device),c_pointer(state[].texture_samplers[slot]),c_pointer(0))
    state[].texture_samplers[slot]=0
    c_ref[Graphics](g)[].textures[slot]=Texture()
    state[].texture_alive[slot]=0
    state[].texture_generations[slot]+=1
    state[].normal_source[slot]=0
    state[].orm_source[slot]=0
    state[].texture_last_used[slot]=0
    state[].texture_alpha[slot]=0
    state[].texture_cutoff[slot]=0
    if c_ref[Graphics](g)[].font_texture==index:c_ref[Graphics](g)[].font_texture= -1
    _=texture
    return 0

# glTF sampler filters/wrap modes. Descriptor changes wait for existing use;
# candidates normally configure sampling before they are published or drawn.
@export("mg_texture_sampling")
def mg_texture_sampling(g: UInt64,id: Int32,wrap_s: Int32,wrap_t: Int32,min_filter: Int32,mag_filter: Int32) abi("C") -> Int32:
    var index=texture_index(g,id)
    if index<0:return fail(c_literal_103())
    if wrap_s!=10497 and wrap_s!=33071 and wrap_s!=33648:return fail(c_literal_103())
    if wrap_t!=10497 and wrap_t!=33071 and wrap_t!=33648:return fail(c_literal_103())
    if min_filter!=9728 and min_filter!=9729 and min_filter!=9984 and min_filter!=9985 and min_filter!=9986 and min_filter!=9987:return fail(c_literal_103())
    if mag_filter!=9728 and mag_filter!=9729:return fail(c_literal_103())
    var slot=Int(index)+1
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var sampler=VkSamplerCreateInfo()
    sampler.sType=31
    sampler.magFilter=1 if mag_filter==9729 else 0
    sampler.minFilter=1 if min_filter==9729 or min_filter==9985 or min_filter==9987 else 0
    sampler.mipmapMode=1 if min_filter==9986 or min_filter==9987 else 0
    sampler.addressModeU=Int32(0 if wrap_s==10497 else (1 if wrap_s==33648 else 2))
    sampler.addressModeV=Int32(0 if wrap_t==10497 else (1 if wrap_t==33648 else 2))
    sampler.addressModeW=0
    sampler.maxLod=0 if min_filter<9984 else Float32(c_ref[Graphics](g)[].textures[slot].image.levels-1)
    var handle=UInt64(0)
    if c_result(external_call["vkCreateSampler",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_address(Pointer(to=sampler))),c_pointer(0),c_pointer(c_address(Pointer(to=handle)))),c_literal_34())<0:return -1
    if c_result(external_call["vkDeviceWaitIdle",Int32](c_pointer(c_ref[Graphics](g)[].device)),c_literal_26())<0:
        external_call["vkDestroySampler",NoneType](c_pointer(c_ref[Graphics](g)[].device),c_pointer(handle),c_pointer(0))
        return -1
    var info=VkDescriptorImageInfo()
    info.sampler=handle
    info.imageView=c_ref[Graphics](g)[].textures[slot].image.view
    info.imageLayout=5
    var write=VkWriteDescriptorSet()
    write.sType=35
    write.descriptorCount=1
    write.descriptorType=1
    write.pImageInfo=c_address(Pointer(to=info))
    for i in range(1,Int(c_ref[Graphics](g)[].texture_count)+1):
        if not state[].texture_alive[i]:continue
        write.dstSet=c_ref[Graphics](g)[].textures[i].set
        for binding in range(2,5):
            if (binding==2 and i==slot) or (binding==3 and state[].normal_source[i]==Int32(slot)) or (binding==4 and state[].orm_source[i]==Int32(slot)):
                write.dstBinding=UInt32(binding)
                external_call["vkUpdateDescriptorSets",NoneType](c_pointer(c_ref[Graphics](g)[].device),UInt32(1),c_pointer(c_address(Pointer(to=write))),UInt32(0),c_pointer(0))
    if state[].texture_samplers[slot]:external_call["vkDestroySampler",NoneType](c_pointer(c_ref[Graphics](g)[].device),c_pointer(state[].texture_samplers[slot]),c_pointer(0))
    state[].texture_samplers[slot]=handle
    _=handle
    _=sampler^
    _=info^
    _=write^
    return 0

@export("mg_wait_idle")
def mg_wait_idle(g: UInt64) abi("C") -> Int32:
    if upload_flush(g)<0:return -1
    if c_result(external_call["vkDeviceWaitIdle",Int32](c_pointer(c_ref[Graphics](g)[].device)),c_literal_26())<0:return -1
    completion_poll(g)
    return 0

def texture_alpha_value(g: UInt64,index: Int32) -> Float32:
    if index<0:return 0
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var mode=state[].texture_alpha[Int(index)+1]
    if mode==1:return 2
    if mode==2:return 3+state[].texture_cutoff[Int(index)+1]
    return 1

@export("mg_texture_alpha")
def mg_texture_alpha(g: UInt64,id: Int32,mode: Int32,cutoff: Float32) abi("C") -> Int32:
    var index=texture_index(g,id)
    if index<0 or mode<0 or mode>2 or not isfinite(cutoff) or cutoff<0 or cutoff>1:return fail(c_literal_103())
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    state[].texture_alpha[Int(index)+1]=mode
    state[].texture_cutoff[Int(index)+1]=cutoff
    if mode==1:c_ref[Graphics](g)[].textures[Int(index)+1].opaque=1
    return 0

def skin_storage_make(g: UInt64) -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if not state[].skin_cpu:
        state[].skin_cpu=c_nullable_address(external_call["malloc",CPointer](UInt64(16*1024*1024)))
        if not state[].skin_cpu:return fail(c_literal_73())
    if state[].skin_buffer.size<UInt64(16*1024*1024)*UInt64(state[].frame_count):
        if c_result(external_call["vkDeviceWaitIdle",Int32](c_pointer(c_ref[Graphics](g)[].device)),c_literal_26())<0:return -1
        var candidate=Buffer()
        if buffer_make(g,c_address(Pointer(to=candidate)),UInt64(16*1024*1024)*UInt64(state[].frame_count),UInt32(32))<0:
            buffer_drop(g,c_address(Pointer(to=candidate)))
            return -1
        buffer_drop(g,c_address(Pointer(to=state[].skin_buffer)))
        state[].skin_buffer=candidate.copy()
        _=candidate^
        var info=VkDescriptorBufferInfo()
        info.buffer=state[].skin_buffer.buffer
        info.c_range=state[].skin_buffer.size
        var write=VkWriteDescriptorSet()
        write.sType=35
        write.dstBinding=7
        write.descriptorType=7
        write.descriptorCount=1
        write.pBufferInfo=c_address(Pointer(to=info))
        for i in range(Int(c_ref[Graphics](g)[].texture_count)+1):
            if not c_ref[Graphics](g)[].textures[i].set:continue
            write.dstSet=c_ref[Graphics](g)[].textures[i].set
            external_call["vkUpdateDescriptorSets",NoneType](c_pointer(c_ref[Graphics](g)[].device),UInt32(1),c_pointer(c_address(Pointer(to=write))),UInt32(0),c_pointer(0))
        _=info^
        _=write^
    return 0

# Optional CPU-owned mesh attributes are copied into frame storage when queued.
# This preserves their old value across updates, release and asynchronous frames.
@export("mg_mesh_attributes")
def mg_mesh_attributes(g: UInt64,id: Int32,colors: UInt64,tangents: UInt64,count: Int32) abi("C") -> Int32:
    var mesh=mesh_at(g,id)
    if not mesh or count<0 or count>4*1024*1024:return fail(c_literal_74())
    if UInt64(count)*8!=c_ref[Mesh](mesh)[].vertices.size:return fail(c_literal_74())
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var slot=Int(UInt32(id)&4095)
    var candidate=Array[UInt64,2](fill=0)
    for channel in range(2):
        var data=colors if channel==0 else tangents
        if not data:continue
        for i in range(Int(count)):
            var value=c_ref[Float32](data)[unsafe_offset=i]
            if not isfinite(value) or channel==0 and (value<0 or value>1):return fail(c_literal_74())
    var bytes=UInt64(count)*4*UInt64(Int(colors!=0)+Int(tangents!=0))
    var previous=UInt64(state[].attribute_counts[slot])*4*UInt64(Int(state[].color_cpu[slot]!=0)+Int(state[].tangent_cpu[slot]!=0))
    if state[].attribute_bytes-previous+bytes>128*1024*1024:return fail(c_literal_76())
    for channel in range(2):
        var data=colors if channel==0 else tangents
        if not data:continue
        candidate[channel]=c_nullable_address(external_call["malloc",CPointer](UInt64(count)*4))
        if not candidate[channel]:
            for index in range(2):
                if candidate[index]:external_call["free",NoneType](c_pointer(candidate[index]))
            return fail(c_literal_73())
        _=external_call["memcpy",CPointer](c_pointer(candidate[channel]),c_pointer(data),UInt64(count)*4)
    if state[].color_cpu[slot]:external_call["free",NoneType](c_pointer(state[].color_cpu[slot]))
    if state[].tangent_cpu[slot]:external_call["free",NoneType](c_pointer(state[].tangent_cpu[slot]))
    state[].color_cpu[slot]=candidate[0]
    state[].tangent_cpu[slot]=candidate[1]
    state[].attribute_counts[slot]=UInt32(count) if colors or tangents else 0
    state[].attribute_bytes=state[].attribute_bytes-previous+bytes
    _=candidate^
    return 0

def queue_attributes(g: UInt64,id: Int32,draw: UInt64) -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var slot=Int(UInt32(id)&4095)
    var count=state[].attribute_counts[slot]
    var required=count*UInt32(Int(state[].color_cpu[slot]!=0)+Int(state[].tangent_cpu[slot]!=0))
    if required==0:return 0
    if state[].skin_count+required>4*1024*1024:return fail(c_literal_76())
    if skin_storage_make(g)<0:return -1
    for channel in range(2):
        var data=state[].color_cpu[slot] if channel==0 else state[].tangent_cpu[slot]
        if not data:continue
        c_ref[Draw](draw)[].c_object.params[3]=Float32(Int32(c_ref[Draw](draw)[].c_object.params[3])|Int32(512 if channel==0 else 1024))
        c_ref[Draw](draw)[].c_object.pose[channel]=Float32(state[].skin_count)
        _=external_call["memcpy",CPointer](c_pointer(state[].skin_cpu+UInt64(state[].skin_count)*4),c_pointer(data),UInt64(count)*4)
        state[].skin_count+=count
    return 0

def attributes_drop(g: UInt64,slot: Int):
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    state[].attribute_bytes-=UInt64(state[].attribute_counts[slot])*4*UInt64(Int(state[].color_cpu[slot]!=0)+Int(state[].tangent_cpu[slot]!=0))
    if state[].color_cpu[slot]:external_call["free",NoneType](c_pointer(state[].color_cpu[slot]))
    if state[].tangent_cpu[slot]:external_call["free",NoneType](c_pointer(state[].tangent_cpu[slot]))
    state[].color_cpu[slot]=0
    state[].tangent_cpu[slot]=0
    state[].attribute_counts[slot]=0

def cascade_fail() -> Int32:
    var message=String("Invalid directional shadow cascade configuration")
    var result=fail(c_address(message.as_c_string_span().ptr()))
    _=message^
    return result

@export("mg_shadow_cascades")
def mg_shadow_cascades(g: UInt64,matrices: UInt64,splits: UInt64,count: Int32,fx: Float32,fy: Float32,fz: Float32,ex: Float32,ey: Float32,ez: Float32) abi("C") -> Int32:
    if not matrices or not splits or (count!=2 and count!=4):return cascade_fail()
    var length=fx*fx+fy*fy+fz*fz
    if not isfinite(length) or abs(length-1)>.001:return cascade_fail()
    if not isfinite(ex) or not isfinite(ey) or not isfinite(ez):return cascade_fail()
    var previous=Float32(0)
    for i in range(Int(count)):
        var split=c_ref[Float32](splits)[unsafe_offset=i]
        if not isfinite(split) or split<=previous or split>1000000:return cascade_fail()
        previous=split
        for j in range(16):
            var value=c_ref[Float32](matrices)[unsafe_offset=i*16+j]
            if not isfinite(value) or abs(value)>1e20:return cascade_fail()
    # Validate all input before resetting a queued frame or publishing metadata.
    mg_shadow_begin(g,matrices)
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    for i in range(Int(count)):
        state[].cascade_splits[i]=c_ref[Float32](splits)[unsafe_offset=i]
        for j in range(16):state[].cascade_matrices[i][j]=c_ref[Float32](matrices)[unsafe_offset=i*16+j]
    state[].cascade_count=count
    state[].cascade_forward[0]=fx
    state[].cascade_forward[1]=fy
    state[].cascade_forward[2]=fz
    state[].cascade_forward[3]=Float32(count)
    state[].cascade_eye[0]=ex
    state[].cascade_eye[1]=ey
    state[].cascade_eye[2]=ez
    return 0

def cascade_uniforms_write(g: UInt64) -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    state[].uniform_slice=0
    var block=CascadeUniform(c_ref[Graphics](g)[].frame.copy(),state[].cascade_matrices.copy(),state[].cascade_splits.copy(),state[].cascade_forward.copy(),state[].cascade_eye.copy(),Array[Float32,4](fill=0),state[].environment.copy(),state[].local_lights.copy())
    block.forward[3]=Float32(state[].cascade_count)
    block.policy[0]=Float32(state[].hdr_enabled)
    block.policy[1]=state[].environment_enabled
    block.policy[2]=Float32(state[].local_light_count)
    var buffer=c_address(Pointer(to=c_ref[Graphics](g)[].uniform))
    if buffer_write(g,buffer,c_address(Pointer(to=block)),UInt64(size_of[CascadeUniform]()))<0:return -1
    for i in range(Int(state[].cascade_count)):
        block.frame.light=state[].cascade_matrices[i].copy()
        if buffer_write(g,buffer,c_address(Pointer(to=block)),UInt64(size_of[CascadeUniform]()),UInt64(i+1)*state[].uniform_slice_stride)<0:return -1
    _=block^
    return 0

def shadow_tile_viewport(g: UInt64,index: Int):
    var view=VkViewport()
    view.x=Float32(index%2*2048)
    view.y=Float32(index//2*2048)
    view.width=2048
    view.height=2048
    view.minDepth=0
    view.maxDepth=1
    var scissor=VkRect2D()
    scissor.offset.x=Int32(index%2*2048)
    scissor.offset.y=Int32(index//2*2048)
    scissor.extent.width=2048
    scissor.extent.height=2048
    external_call["vkCmdSetViewport",NoneType](c_pointer(c_ref[Graphics](g)[].command),UInt32(0),UInt32(1),c_pointer(c_address(Pointer(to=view))))
    external_call["vkCmdSetScissor",NoneType](c_pointer(c_ref[Graphics](g)[].command),UInt32(0),UInt32(1),c_pointer(c_address(Pointer(to=scissor))))
    _=view^
    _=scissor^

@export("mg_shadow_debug")
def mg_shadow_debug(g: UInt64,enabled: Int32) abi("C"):
    c_ref[Scalability](c_ref[Graphics](g)[].scalability)[].cascade_eye[3]=1.0 if enabled!=0 else 0.0
    c_ref[Graphics](g)[].rendered=0

# HDR remains optional: legacy targets/pipelines and public ABI are unchanged.
def display_pass_make(g: UInt64) -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var attachment=VkAttachmentDescription()
    attachment.c_format=37
    attachment.samples=1
    attachment.loadOp=2
    attachment.storeOp=0
    attachment.stencilLoadOp=2
    attachment.stencilStoreOp=1
    attachment.initialLayout=0
    attachment.finalLayout=6
    var reference=VkAttachmentReference()
    reference.attachment=0
    reference.layout=2
    var sub=VkSubpassDescription()
    sub.pipelineBindPoint=0
    sub.colorAttachmentCount=1
    sub.pColorAttachments=c_address(Pointer(to=reference))
    var dependencies=Array[VkSubpassDependency,2](fill=VkSubpassDependency())
    dependencies[0].srcSubpass=UInt32.MAX
    dependencies[0].dstSubpass=0
    dependencies[0].srcStageMask=4096|1024
    dependencies[0].dstStageMask=1024
    dependencies[0].srcAccessMask=2048|256
    dependencies[0].dstAccessMask=256
    dependencies[1].srcSubpass=0
    dependencies[1].dstSubpass=UInt32.MAX
    dependencies[1].srcStageMask=1024
    dependencies[1].dstStageMask=4096
    dependencies[1].srcAccessMask=256
    dependencies[1].dstAccessMask=2048
    var info=VkRenderPassCreateInfo()
    info.sType=38
    info.attachmentCount=1
    info.pAttachments=c_address(Pointer(to=attachment))
    info.subpassCount=1
    info.pSubpasses=c_address(Pointer(to=sub))
    info.dependencyCount=2
    info.pDependencies=c_address(Pointer(to=dependencies))
    var result=c_result(external_call["vkCreateRenderPass",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_address(Pointer(to=info))),c_pointer(0),c_pointer(c_address(Pointer(to=state[].display_pass)))),c_literal_20())
    _=attachment^
    _=reference^
    _=sub^
    _=dependencies^
    _=info^
    return result

def hdr_pipelines_make(g: UInt64) -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if pipeline_make(g,c_address(Pointer(to=state[].hdr_pipeline)),6,shader_world_vert(),shader_world_vert_size(),shader_world_frag(),shader_world_frag_size())<0:return -1
    if pipeline_make(g,c_address(Pointer(to=state[].display_pipeline)),4,shader_display_vert(),shader_display_vert_size(),shader_display_frag(),shader_display_frag_size())<0:return -1
    return pipeline_make(g,c_address(Pointer(to=state[].display_overlay)),5,shader_overlay_vert(),shader_overlay_vert_size(),shader_overlay_frag(),shader_overlay_frag_size())

def hdr_targets_drop(g: UInt64):
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if state[].hdr_fb:external_call["vkDestroyFramebuffer",NoneType](c_pointer(c_ref[Graphics](g)[].device),c_pointer(state[].hdr_fb),c_pointer(0))
    if state[].display_fb:external_call["vkDestroyFramebuffer",NoneType](c_pointer(c_ref[Graphics](g)[].device),c_pointer(state[].display_fb),c_pointer(0))
    state[].hdr_fb=0
    state[].display_fb=0
    image_drop(g,c_address(Pointer(to=state[].hdr_color)))
    image_drop(g,c_address(Pointer(to=state[].hdr_multisample)))

def hdr_targets_make(g: UInt64) -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if not state[].hdr_enabled:return 0
    var w=UInt32(c_ref[Graphics](g)[].width)
    var h=UInt32(c_ref[Graphics](g)[].height)
    if image_make(g,c_address(Pointer(to=state[].hdr_color)),w,h,1,97,16|4|1,1)<0:return -1
    if c_ref[Graphics](g)[].samples!=1:
        if image_make_samples(g,c_address(Pointer(to=state[].hdr_multisample)),w,h,1,97,16,1,c_ref[Graphics](g)[].samples)<0:return -1
    var views=Array[UInt64,3](fill=0)
    views[0]=state[].hdr_color.view if c_ref[Graphics](g)[].samples==1 else state[].hdr_multisample.view
    views[1]=c_ref[Graphics](g)[].depth.view
    views[2]=state[].hdr_color.view
    var info=VkFramebufferCreateInfo()
    info.sType=37
    info.renderPass=state[].hdr_pass
    info.attachmentCount=2 if c_ref[Graphics](g)[].samples==1 else 3
    info.pAttachments=c_address(Pointer(to=views))
    info.width=w
    info.height=h
    info.layers=1
    if c_result(external_call["vkCreateFramebuffer",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_address(Pointer(to=info))),c_pointer(0),c_pointer(c_address(Pointer(to=state[].hdr_fb)))),c_literal_27())<0:return -1
    info.renderPass=state[].display_pass
    info.attachmentCount=1
    info.pAttachments=c_address(Pointer(to=c_ref[Graphics](g)[].color.view))
    var result=c_result(external_call["vkCreateFramebuffer",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_address(Pointer(to=info))),c_pointer(0),c_pointer(c_address(Pointer(to=state[].display_fb)))),c_literal_27())
    _=views^
    _=info^
    return result

def hdr_descriptor_update(g: UInt64,set: UInt64):
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var image=VkDescriptorImageInfo()
    image.sampler=c_ref[Graphics](g)[].shadow_sampler
    image.imageView=state[].hdr_color.view if state[].hdr_enabled and Bool(state[].hdr_color.view) else c_ref[Graphics](g)[].scene_color.view
    image.imageLayout=5
    var write=VkWriteDescriptorSet()
    write.sType=35
    write.dstSet=set
    write.dstBinding=8
    write.descriptorCount=1
    write.descriptorType=1
    write.pImageInfo=c_address(Pointer(to=image))
    external_call["vkUpdateDescriptorSets",NoneType](c_pointer(c_ref[Graphics](g)[].device),UInt32(1),c_pointer(c_address(Pointer(to=write))),UInt32(0),c_pointer(0))
    _=image^
    _=write^

def hdr_descriptors_update(g: UInt64):
    for i in range(257):
        if c_ref[Graphics](g)[].textures[i].set:hdr_descriptor_update(g,c_ref[Graphics](g)[].textures[i].set)

def hdr_drop(g: UInt64):
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    hdr_targets_drop(g)
    for pipeline in [state[].hdr_pipeline,state[].display_pipeline,state[].display_overlay]:
        if pipeline:external_call["vkDestroyPipeline",NoneType](c_pointer(c_ref[Graphics](g)[].device),c_pointer(pipeline),c_pointer(0))
    for render_pass in [state[].hdr_pass,state[].hdr_water_pass,state[].display_pass]:
        if render_pass:external_call["vkDestroyRenderPass",NoneType](c_pointer(c_ref[Graphics](g)[].device),c_pointer(render_pass),c_pointer(0))

@export("mg_hdr")
def mg_hdr(g: UInt64,enabled: Int32) abi("C") -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var mode=Int32(enabled!=0)
    if mode==state[].hdr_enabled:return 0
    if mode:
        var properties=VkFormatProperties()
        external_call["vkGetPhysicalDeviceFormatProperties",NoneType](c_pointer(c_ref[Graphics](g)[].physical),Int32(97),c_pointer(c_address(Pointer(to=properties))))
        var required=UInt32(1|128|16384|32768)
        if properties.optimalTilingFeatures&required!=required:return fail(c_literal_103())
        _=properties^
        var support=VkImageFormatProperties()
        var status=external_call["vkGetPhysicalDeviceImageFormatProperties",Int32](c_pointer(c_ref[Graphics](g)[].physical),Int32(97),Int32(1),Int32(0),UInt32(16),UInt32(0),c_pointer(c_address(Pointer(to=support))))
        if status!=0 or support.sampleCounts&UInt32(c_ref[Graphics](g)[].samples)==0:return fail(c_literal_103())
        _=support^
    state[].hdr_enabled=mode
    c_ref[Graphics](g)[].target_width=0
    c_ref[Graphics](g)[].rendered=0
    return 0

@export("mg_environment")
def mg_environment(g: UInt64,coefficients: UInt64,enabled: Int32) abi("C") -> Int32:
    if enabled:
        if not coefficients:return fail(c_literal_103())
        for i in range(27):
            var value=c_ref[Float32](coefficients)[unsafe_offset=i]
            if not isfinite(value) or abs(value)>500000:return fail(c_literal_103())
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if enabled:
        for i in range(9):
            for channel in range(3):state[].environment[i][channel]=c_ref[Float32](coefficients)[unsafe_offset=i*3+channel]
    state[].environment_enabled=1.0 if enabled else 0.0
    c_ref[Graphics](g)[].rendered=0
    return 0


@export("mg_camera_origin")
def mg_camera_origin(g: UInt64,x: Float32,y: Float32,z: Float32) abi("C") -> Int32:
    for value in [x,y,z]:
        if not isfinite(value) or abs(value)>1000000:return fail(c_literal_103())
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    state[].cascade_eye[0]=x
    state[].cascade_eye[1]=y
    state[].cascade_eye[2]=z
    c_ref[Graphics](g)[].rendered=0
    return 0


@export("mg_local_lights")
def mg_local_lights(g: UInt64,data: UInt64,count: Int32) abi("C") -> Int32:
    if count<0 or count>32 or (count>0 and not data):return fail(c_literal_103())
    for i in range(Int(count)):
        for j in range(12):
            var value=c_ref[Float32](data)[unsafe_offset=i*12+j]
            if not isfinite(value):return fail(c_literal_103())
            if j<3 and abs(value)>1000000:return fail(c_literal_103())
            if j>=4 and j<7 and (value<0 or value>1000000000):return fail(c_literal_103())
        var inner=c_ref[Float32](data)[unsafe_offset=i*12+3]
        var outer=c_ref[Float32](data)[unsafe_offset=i*12+7]
        if outer < -1 or outer>1 or inner<outer or inner>1:return fail(c_literal_103())
        if outer > -1:
            var squared: Float32=0
            for j in range(8,11):
                var v=c_ref[Float32](data)[unsafe_offset=i*12+j]
                squared+=v*v
            if abs(squared-1)>.0001:return fail(c_literal_103())
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    for i in range(Int(count)):
        for j in range(12):state[].local_lights[i][j]=c_ref[Float32](data)[unsafe_offset=i*12+j]
    state[].local_light_count=count
    c_ref[Graphics](g)[].rendered=0
    return 0

@export("mg_text_input")
def mg_text_input(var g: UInt64,var enabled: Int32) abi("C") -> Int32:
    var window=c_ref[Graphics](g)[].window
    if not window:return 0
    var ok=external_call["SDL_StartTextInput",Bool](c_pointer(window)) if enabled else external_call["SDL_StopTextInput",Bool](c_pointer(window))
    return 0 if ok else fail(c_nullable_address(external_call["SDL_GetError",CPointer]()))
