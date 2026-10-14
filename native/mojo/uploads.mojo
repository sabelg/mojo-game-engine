"""Bounded two-slot staging ring and submission-completion tracking.

GPU copies are queued on the creating thread. A slot is reused only after its
fence signals. The shared graphics queue orders upload and render submissions.
"""
from native.mojo.abi import *
from native.mojo.runtime_support import *
from std.ffi import external_call
from std.sys import size_of

comptime BufferAllocator=def(UInt64,UInt64,UInt64,UInt32) abi("C") thin -> Int32
comptime BufferDropper=def(UInt64,UInt64) abi("C") thin

def upload_error(status: Int32,error: UInt64) -> Int32:
    if status==0:return 0
    var message=String("Vulkan batched mesh upload failed: ")+String(status)
    _=external_call["snprintf",Int32,num_fixed_args=3](c_pointer(error),UInt64(4096),c_pointer(c_literal_0()),c_pointer(c_address(message.as_c_string_span().ptr())))
    _=message^
    return -1

def completion_poll(g: UInt64):
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if c_ref[Graphics](g)[].fence and external_call["vkGetFenceStatus",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_ref[Graphics](g)[].fence))==0:
        state[].completed_serial=max(state[].completed_serial,state[].frame_serial)
    for i in range(2):
        if state[].frames[i].fence and external_call["vkGetFenceStatus",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(state[].frames[i].fence))==0:
            state[].completed_serial=max(state[].completed_serial,state[].frames[i].serial)
        var slot=c_ref[UploadSlot](c_address(Pointer(to=state[].uploads[i])))
        if slot[].submitted and external_call["vkGetFenceStatus",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(slot[].fence))==0:
            state[].completed_serial=max(state[].completed_serial,slot[].serial)

def upload_slot_ready(g: UInt64,index: Int,error: UInt64) -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var slot=c_ref[UploadSlot](c_address(Pointer(to=state[].uploads[index])))
    if slot[].submitted:
        var began=external_call["SDL_GetPerformanceCounter",UInt64]()
        var result=external_call["vkWaitForFences",Int32](c_pointer(c_ref[Graphics](g)[].device),UInt32(1),c_pointer(c_address(Pointer(to=slot[].fence))),UInt32(1),UInt64.MAX)
        state[].upload_wait_ms+=Float64(external_call["SDL_GetPerformanceCounter",UInt64]()-began)*1000/Float64(external_call["SDL_GetPerformanceFrequency",UInt64]())
        if upload_error(result,error)<0:return -1
        state[].completed_serial=max(state[].completed_serial,slot[].serial)
        slot[].submitted=0
        slot[].head=0
    return 0

def upload_flush(g: UInt64,allocator: BufferAllocator,error: UInt64) -> Int32:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var index=Int(state[].upload_slot)
    var slot=c_ref[UploadSlot](c_address(Pointer(to=state[].uploads[index])))
    if slot[].count==0:return 0
    if not slot[].command:
        var allocation=VkCommandBufferAllocateInfo()
        allocation.sType=40
        allocation.commandPool=c_ref[Graphics](g)[].pool
        allocation.commandBufferCount=1
        var result=external_call["vkAllocateCommandBuffers",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_address(Pointer(to=allocation))),c_pointer(c_address(Pointer(to=slot[].command))))
        _=allocation^
        if upload_error(result,error)<0:return -1
    if not slot[].fence:
        var info=VkFenceCreateInfo()
        info.sType=8
        info.flags=1
        var result=external_call["vkCreateFence",Int32](c_pointer(c_ref[Graphics](g)[].device),c_pointer(c_address(Pointer(to=info))),c_pointer(0),c_pointer(c_address(Pointer(to=slot[].fence))))
        _=info^
        if upload_error(result,error)<0:return -1
    if upload_error(external_call["vkResetCommandBuffer",Int32](c_pointer(slot[].command),UInt32(0)),error)<0:return -1
    var begin=VkCommandBufferBeginInfo()
    begin.sType=42
    begin.flags=1
    var result=external_call["vkBeginCommandBuffer",Int32](c_pointer(slot[].command),c_pointer(c_address(Pointer(to=begin))))
    _=begin^
    if upload_error(result,error)<0:return -1
    var transfer=VkMemoryBarrier(46,0,4096,4096)
    for i in range(Int(slot[].count)):
        var item=slot[].copies[i].copy()
        var overlaps=False
        for j in range(i):
            var previous=slot[].copies[j].copy()
            if previous.destination==item.destination and previous.destination_offset<item.destination_offset+item.size and item.destination_offset<previous.destination_offset+previous.size:overlaps=True
        if overlaps:external_call["vkCmdPipelineBarrier",NoneType](c_pointer(slot[].command),UInt32(4096),UInt32(4096),UInt32(0),UInt32(1),c_pointer(c_address(Pointer(to=transfer))),UInt32(0),c_pointer(0),UInt32(0),c_pointer(0))
        var copy=VkBufferCopy(item.source_offset,item.destination_offset,item.size)
        external_call["vkCmdCopyBuffer",NoneType](c_pointer(slot[].command),c_pointer(slot[].staging.buffer),c_pointer(item.destination),UInt32(1),c_pointer(c_address(Pointer(to=copy))))
        _=copy^
    # Include later transfer writes as well as vertex/index reads: another batch
    # may update this mesh before it is drawn, without a host fence wait.
    var visible=VkMemoryBarrier(46,0,4096,6150)
    external_call["vkCmdPipelineBarrier",NoneType](c_pointer(slot[].command),UInt32(4096),UInt32(4100),UInt32(0),UInt32(1),c_pointer(c_address(Pointer(to=visible))),UInt32(0),c_pointer(0),UInt32(0),c_pointer(0))
    _=transfer^
    _=visible^
    if upload_error(external_call["vkEndCommandBuffer",Int32](c_pointer(slot[].command)),error)<0:return -1
    if upload_error(external_call["vkResetFences",Int32](c_pointer(c_ref[Graphics](g)[].device),UInt32(1),c_pointer(c_address(Pointer(to=slot[].fence)))),error)<0:return -1
    var submit=VkSubmitInfo()
    submit.sType=4
    submit.commandBufferCount=1
    submit.pCommandBuffers=c_address(Pointer(to=slot[].command))
    result=external_call["vkQueueSubmit",Int32](c_pointer(c_ref[Graphics](g)[].queue),UInt32(1),c_pointer(c_address(Pointer(to=submit))),c_pointer(slot[].fence))
    _=submit^
    if upload_error(result,error)<0:return -1
    state[].submit_serial+=1
    slot[].serial=state[].submit_serial
    slot[].submitted=1
    state[].upload_batches+=1
    state[].upload_copies+=UInt64(slot[].count)
    for i in range(Int(slot[].count)):state[].upload_bytes+=slot[].copies[i].size
    slot[].count=0
    state[].upload_slot=Int32((index+1)%2)
    return 0

def stage_mesh(g: UInt64,b: UInt64,data: UInt64,size: UInt64,allocator: BufferAllocator,error: UInt64) -> Int32:
    if size%4!=0:return upload_error(-1,error)
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    var cursor=UInt64(0)
    while cursor<size:
        var index=Int(state[].upload_slot)
        if upload_slot_ready(g,index,error)<0:return -1
        var slot=c_ref[UploadSlot](c_address(Pointer(to=state[].uploads[index])))
        if not slot[].staging.buffer:
            if allocator(g,c_address(Pointer(to=slot[].staging)),UInt64(8*1024*1024),UInt32(1))<0:return -1
        var available=slot[].staging.size-slot[].head
        if available==0 or slot[].count==1024:
            if upload_flush(g,allocator,error)<0:return -1
            continue
        var count=min(available,size-cursor)
        _=external_call["memcpy",CPointer](c_pointer(slot[].staging.mapped+slot[].head),c_pointer(data+cursor),count)
        slot[].copies[Int(slot[].count)]=UploadCopy(c_ref[Buffer](b)[].buffer,c_ref[Buffer](b)[].mapped-1+cursor,slot[].head,count)
        slot[].head+=count
        slot[].count+=1
        cursor+=count
    return 0

def uploads_drop(g: UInt64,dropper: BufferDropper):
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    for i in range(2):
        var slot=c_ref[UploadSlot](c_address(Pointer(to=state[].uploads[i])))
        dropper(g,c_address(Pointer(to=slot[].staging)))
        if slot[].fence:external_call["vkDestroyFence",NoneType](c_pointer(c_ref[Graphics](g)[].device),c_pointer(slot[].fence),c_pointer(0))

def upload_stat(g: UInt64,key: Int32) -> Float64:
    var state=c_ref[Scalability](c_ref[Graphics](g)[].scalability)
    if key==0:return state[].upload_wait_ms
    if key==1:return Float64(state[].upload_batches)
    if key==2:return Float64(state[].upload_copies)
    if key==3:return Float64(state[].upload_bytes)
    if key==4:
        var total=UInt64(0)
        for i in range(2):total+=state[].uploads[i].staging.allocated
        return Float64(total)
    if key==5:return Float64(state[].completed_serial)
    return -1
