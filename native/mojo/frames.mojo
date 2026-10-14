"""Frame resources and mapped-stream banks, independent of public Graphics ABI.

Prepare waits only for the bank being reused. Render targets remain ordered on
one queue; snapshots, replacement and resize explicitly synchronize that queue.
"""
from native.mojo.abi import *
from native.mojo.runtime_support import *
from native.mojo.uploads import upload_error,completion_poll
from std.ffi import external_call
from std.sys import size_of

def frame_capture(g: UInt64,index: Int):
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    state[].frames[index].command=c_ref[Graphics](g)[].command
    state[].frames[index].fence=c_ref[Graphics](g)[].fence
    state[].frames[index].timestamps=c_ref[Graphics](g)[].timestamps
    state[].frames[index].acquired=c_ref[Graphics](g)[].acquired
    state[].frames[index].serial=state[].frame_serial

def frame_prepare(g: UInt64,error: UInt64) -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if state[].frame_prepared:return 0
    if not state[].frames_initialized:
        frame_capture(g,0)
        if state[].frame_count==2:
            var slot=c_ref[FrameSlot](c_address(Pointer(to=state[].frames[1])))
            if not slot[].command:
                var allocation=VkCommandBufferAllocateInfo()
                allocation.sType=40
                allocation.commandPool=c_ref[Graphics](g)[].pool
                allocation.commandBufferCount=1
                var result=external_call["vkAllocateCommandBuffers",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_address(Pointer(to=allocation))),c_pointer(c_address(Pointer(to=slot[].command))))
                _=allocation^
                if upload_error(result,error)<0:return -1
            if not slot[].fence:
                var fence=VkFenceCreateInfo()
                fence.sType=8
                fence.flags=1
                var result=external_call["vkCreateFence",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_address(Pointer(to=fence))),c_pointer(0),c_pointer(c_address(Pointer(to=slot[].fence))))
                _=fence^
                if upload_error(result,error)<0:return -1
            if c_ref[Graphics](g)[].timestamps and not slot[].timestamps:
                var query=VkQueryPoolCreateInfo()
                query.sType=11
                query.queryType=2
                query.queryCount=2
                var result=external_call["vkCreateQueryPool",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_address(Pointer(to=query))),c_pointer(0),c_pointer(c_address(Pointer(to=slot[].timestamps))))
                _=query^
                if upload_error(result,error)<0:return -1
            if not slot[].acquired:
                var semaphore=VkSemaphoreCreateInfo()
                semaphore.sType=9
                var result=external_call["vkCreateSemaphore",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_address(Pointer(to=semaphore))),c_pointer(0),c_pointer(c_address(Pointer(to=slot[].acquired))))
                _=semaphore^
                if upload_error(result,error)<0:return -1
        state[].frames_initialized=1
    else:
        frame_capture(g,Int(state[].frame_index))
        state[].frame_index=(state[].frame_index+1)%state[].frame_count
    var slot=c_ref[FrameSlot](c_address(Pointer(to=state[].frames[Int(state[].frame_index)])))
    c_ref[Graphics](g)[].command=slot[].command
    c_ref[Graphics](g)[].fence=slot[].fence
    c_ref[Graphics](g)[].timestamps=slot[].timestamps
    c_ref[Graphics](g)[].acquired=slot[].acquired
    state[].frame_serial=slot[].serial
    var began=external_call["SDL_GetPerformanceCounter",UInt64]()
    var result=external_call["vkWaitForFences",Int32](c_pointer(c_ref[Graphics](g)[].device),UInt32(1),c_pointer(c_address(Pointer(to=slot[].fence))),UInt32(1),UInt64.MAX)
    c_ref[Graphics](g)[].detail_ms[0]+=Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-began)*1000/Float64(external_call["SDL_GetPerformanceFrequency",UInt64]())
    if upload_error(result,error)<0:return -1
    completion_poll(g)
    if state[].frame_count==2 and slot[].query_ready:
        var ticks=Array[UInt64,2](fill=0)
        result=external_call["vkGetQueryPoolResults",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(slot[].timestamps),UInt32(0),UInt32(2),UInt64(size_of[Array[UInt64,2]]()),c_pointer(c_address(Pointer(to=ticks))),UInt64(8),UInt32(1))
        if upload_error(result,error)<0:return -1
        var mask=UInt64.MAX if c_ref[Graphics](g)[].timestamp_bits==64 else (UInt64(1)<<UInt64(c_ref[Graphics](g)[].timestamp_bits))-1
        c_ref[Graphics](g)[].stage_ms[4]=Float64((ticks[1]-ticks[0])&mask)*Float64(c_ref[Graphics](g)[].timestamp_period)/1000000
        state[].gpu_frame=slot[].render_id
        slot[].query_ready=0
        _=ticks^
    state[].frame_prepared=1
    return 0

def frame_drop(g: UInt64):
    # Device idle is guaranteed by close. The existing destructor owns the
    # currently selected handles; destroy every other (including partial) slot.
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    for i in range(2):
        var slot=c_ref[FrameSlot](c_address(Pointer(to=state[].frames[i])))
        if slot[].fence and slot[].fence!=c_ref[Graphics](g)[].fence:external_call["vkDestroyFence",NoneType](c_pointer(c_ref[Graphics](g)[].device),c_pointer(slot[].fence),c_pointer(0))
        if slot[].timestamps and slot[].timestamps!=c_ref[Graphics](g)[].timestamps:external_call["vkDestroyQueryPool",NoneType](c_pointer(c_ref[Graphics](g)[].device),c_pointer(slot[].timestamps),c_pointer(0))
        if slot[].acquired and slot[].acquired!=c_ref[Graphics](g)[].acquired:external_call["vkDestroySemaphore",NoneType](c_pointer(c_ref[Graphics](g)[].device),c_pointer(slot[].acquired),c_pointer(0))
