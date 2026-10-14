"""64-bit Vulkan 1.1 and SDL2 ABI layouts plus runtime-owned POD records.

Handles and stored pointers use UInt64. SDL_AudioCVT is byte-packed; its
fields are accessed at SDL offsets in runtime.mojo. No C shim is required.
"""
from std.collections import Array

struct MeshJob(Copyable, Movable):
    var path: UInt64
    var data: UInt64
    var n: UInt32
    var height: UInt32
    var c_bytes: UInt64
    var kind: Int32
    var state: Int32
    def __init__(out self):
        self.path = UInt64(0)
        self.data = UInt64(0)
        self.n = UInt32(0)
        self.height = UInt32(0)
        self.c_bytes = UInt64(0)
        self.kind = Int32(0)
        self.state = Int32(0)

struct AssetLoader(Copyable, Movable):
    var jobs: Array[MeshJob, 4096]
    var c_count: Int32
    var ready: Int32
    var cancel: Int32
    var c_bytes: UInt64
    var peak: UInt64
    var lock: UInt64
    var changed: UInt64
    var thread: UInt64
    def __init__(out self):
        self.jobs = Array[MeshJob, 4096](fill=MeshJob())
        self.c_count = Int32(0)
        self.ready = Int32(0)
        self.cancel = Int32(0)
        self.c_bytes = UInt64(0)
        self.peak = UInt64(0)
        self.lock = UInt64(0)
        self.changed = UInt64(0)
        self.thread = UInt64(0)

struct Voice(Copyable, Movable):
    var id: Int32
    var pos: Int32
    var loop: Int32
    var gain: Float32
    var left: Float32
    var right: Float32
    def __init__(out self):
        self.id = Int32(0)
        self.pos = Int32(0)
        self.loop = Int32(0)
        self.gain = Float32(0)
        self.left = Float32(1)
        self.right = Float32(1)

struct PortGlobals(Copyable, Movable):
    var error_text: Array[Int8, 4096]
    var loader: AssetLoader
    var device: UInt64
    var samples: Array[UInt64, 15]
    var lengths: Array[Int32, 15]
    var voices: Array[Voice, 12]
    var muted: Int32
    var master_gain: Float32
    var music_gain: Float32
    var effects_gain: Float32
    var controller: UInt64
    var pad_axes: Array[Float64, 4]
    def __init__(out self):
        self.error_text = Array[Int8, 4096](fill=Int8(0))
        self.loader = AssetLoader()
        self.device = UInt64(0)
        self.samples = Array[UInt64, 15](fill=UInt64(0))
        self.lengths = Array[Int32, 15](fill=Int32(0))
        self.voices = Array[Voice, 12](fill=Voice())
        self.muted = Int32(0)
        self.master_gain = Float32(0)
        self.music_gain = Float32(0)
        self.effects_gain = Float32(0)
        self.controller = UInt64(0)
        self.pad_axes = Array[Float64, 4](fill=Float64(0))

struct VkMemoryType(Copyable, Movable):
    var propertyFlags: UInt32
    var heapIndex: UInt32
    def __init__(out self):
        self.propertyFlags = UInt32(0)
        self.heapIndex = UInt32(0)

struct VkMemoryHeap(Copyable, Movable):
    var size: UInt64
    var flags: UInt32
    def __init__(out self):
        self.size = UInt64(0)
        self.flags = UInt32(0)

struct VkPhysicalDeviceMemoryProperties(Copyable, Movable):
    var memoryTypeCount: UInt32
    var memoryTypes: Array[VkMemoryType, 32]
    var memoryHeapCount: UInt32
    var memoryHeaps: Array[VkMemoryHeap, 16]
    def __init__(out self):
        self.memoryTypeCount = UInt32(0)
        self.memoryTypes = Array[VkMemoryType, 32](fill=VkMemoryType())
        self.memoryHeapCount = UInt32(0)
        self.memoryHeaps = Array[VkMemoryHeap, 16](fill=VkMemoryHeap())

struct Image(Copyable, Movable):
    var image: UInt64
    var memory: UInt64
    var view: UInt64
    var levels: UInt32
    var allocated: UInt64
    def __init__(out self):
        self.image = UInt64(0)
        self.memory = UInt64(0)
        self.view = UInt64(0)
        self.levels = UInt32(0)
        self.allocated = UInt64(0)

struct Buffer(Copyable, Movable):
    var buffer: UInt64
    var memory: UInt64
    var size: UInt64
    var allocated: UInt64
    var mapped: UInt64
    def __init__(out self):
        self.buffer = UInt64(0)
        self.memory = UInt64(0)
        self.size = UInt64(0)
        self.allocated = UInt64(0)
        self.mapped = UInt64(0)

struct Texture(Copyable, Movable):
    var image: Image
    var set: UInt64
    var normal: Int32
    var opaque: Int32
    var projection_scale: Float32
    var foliage: Float32
    def __init__(out self):
        self.image = Image()
        self.set = UInt64(0)
        self.normal = Int32(0)
        self.opaque = Int32(0)
        self.projection_scale = Float32(0)
        self.foliage = Float32(0)

struct Mesh(Copyable, Movable):
    var vertices: Buffer
    var indices: Buffer
    var c_count: UInt32
    var generation: UInt32
    var topology: UInt64
    def __init__(out self):
        self.vertices = Buffer()
        self.indices = Buffer()
        self.c_count = UInt32(0)
        self.generation = UInt32(0)
        self.topology = UInt64(0)

struct Frame(Copyable, Movable):
    var vp: Array[Float32, 16]
    var light: Array[Float32, 16]
    var sun_fog: Array[Float32, 4]
    var sky: Array[Float32, 4]
    var ground: Array[Float32, 4]
    var sun_color: Array[Float32, 4]
    var haze: Array[Float32, 4]
    var atmosphere: Array[Float32, 4]
    var cinema: Array[Float32, 4]
    var wind: Array[Float32, 4]
    var face_centers: Array[Array[Float32, 4], 5]
    var face_axis: Array[Array[Float32, 4], 2]
    var face_weights: Array[Float32, 4]
    var inverse_vp: Array[Float32, 16]
    def __init__(out self):
        self.vp = Array[Float32, 16](fill=Float32(0))
        self.light = Array[Float32, 16](fill=Float32(0))
        self.sun_fog = Array[Float32, 4](fill=Float32(0))
        self.sky = Array[Float32, 4](fill=Float32(0))
        self.ground = Array[Float32, 4](fill=Float32(0))
        self.sun_color = Array[Float32, 4](fill=Float32(0))
        self.haze = Array[Float32, 4](fill=Float32(0))
        self.atmosphere = Array[Float32, 4](fill=Float32(0))
        self.cinema = Array[Float32, 4](fill=Float32(0))
        self.wind = Array[Float32, 4](fill=Float32(0))
        self.face_centers = Array[Array[Float32, 4], 5](fill=Array[Float32, 4](fill=Float32(0)))
        self.face_axis = Array[Array[Float32, 4], 2](fill=Array[Float32, 4](fill=Float32(0)))
        self.face_weights = Array[Float32, 4](fill=Float32(0))
        self.inverse_vp = Array[Float32, 16](fill=Float32(0))

struct Graphics(Copyable, Movable):
    var window: UInt64
    var sdl_flags: UInt32
    var instance: UInt64
    var debug: UInt64
    var physical: UInt64
    var device: UInt64
    var memory: VkPhysicalDeviceMemoryProperties
    var surface: UInt64
    var queue: UInt64
    var family: UInt32
    var pool: UInt64
    var command: UInt64
    var fence: UInt64
    var timestamps: UInt64
    var timestamp_bits: UInt32
    var timestamp_period: Float32
    var profile_enabled: Int32
    var present_sync: Int32
    var present_mode: Int32
    var stage_ms: Array[Float64, 5]
    var detail_ms: Array[Float64, 6]
    var present_modes: UInt32
    var surface_min_images: UInt32
    var surface_max_images: UInt32
    var acquired: UInt64
    var present_done: UInt64
    var swapchain: UInt64
    var swap_images: UInt64
    var swap_count: UInt32
    var swap_width: UInt32
    var swap_height: UInt32
    var shadow_pass: UInt64
    var color_pass: UInt64
    var water_pass: UInt64
    var shadow_fb: UInt64
    var color_fb: UInt64
    var scene_depth_fb: UInt64
    var shadow: Image
    var color: Image
    var depth: Image
    var multisample: Image
    var scene_depth: Image
    var scene_color: Image
    var samples: Int32
    var shadow_sampler: UInt64
    var texture_sampler: UInt64
    var anisotropy: Float32
    var ui_scale: Float32
    var set_layout: UInt64
    var descriptors: UInt64
    var pipeline_layout: UInt64
    var world_pipeline: UInt64
    var shadow_pipeline: UInt64
    var overlay_pipeline: UInt64
    var scene_depth_pipeline: UInt64
    var uniform: Buffer
    var overlay_buffer: Buffer
    var readback: Buffer
    var textures: Array[Texture, 257]
    var texture_count: UInt32
    var font_texture: Int32
    var meshes: Array[Mesh, 4096]
    var shadow_draws: UInt64
    var color_draws: UInt64
    var shadow_count: UInt64
    var color_count: UInt64
    var shadow_capacity: UInt64
    var color_capacity: UInt64
    var quads: UInt64
    var quad_count: UInt64
    var quad_capacity: UInt64
    var frame: Frame
    var width: Int32
    var height: Int32
    var target_width: Int32
    var target_height: Int32
    var rendered: Int32
    var frame_started: Int32
    var triangles: Int32
    var validation_errors: Int32
    var validation_enabled: Int32
    var driver: Array[Int8, 256]
    var scalability: UInt64
    def __init__(out self):
        self.window = UInt64(0)
        self.sdl_flags = UInt32(0)
        self.instance = UInt64(0)
        self.debug = UInt64(0)
        self.physical = UInt64(0)
        self.device = UInt64(0)
        self.memory = VkPhysicalDeviceMemoryProperties()
        self.surface = UInt64(0)
        self.queue = UInt64(0)
        self.family = UInt32(0)
        self.pool = UInt64(0)
        self.command = UInt64(0)
        self.fence = UInt64(0)
        self.timestamps = UInt64(0)
        self.timestamp_bits = UInt32(0)
        self.timestamp_period = Float32(0)
        self.profile_enabled = Int32(0)
        self.present_sync = Int32(0)
        self.present_mode = Int32(0)
        self.stage_ms = Array[Float64, 5](fill=Float64(0))
        self.detail_ms = Array[Float64, 6](fill=Float64(0))
        self.present_modes = UInt32(0)
        self.surface_min_images = UInt32(0)
        self.surface_max_images = UInt32(0)
        self.acquired = UInt64(0)
        self.present_done = UInt64(0)
        self.swapchain = UInt64(0)
        self.swap_images = UInt64(0)
        self.swap_count = UInt32(0)
        self.swap_width = UInt32(0)
        self.swap_height = UInt32(0)
        self.shadow_pass = UInt64(0)
        self.color_pass = UInt64(0)
        self.water_pass = UInt64(0)
        self.shadow_fb = UInt64(0)
        self.color_fb = UInt64(0)
        self.scene_depth_fb = UInt64(0)
        self.shadow = Image()
        self.color = Image()
        self.depth = Image()
        self.multisample = Image()
        self.scene_depth = Image()
        self.scene_color = Image()
        self.samples = Int32(0)
        self.shadow_sampler = UInt64(0)
        self.texture_sampler = UInt64(0)
        self.anisotropy = Float32(0)
        self.ui_scale = Float32(0)
        self.set_layout = UInt64(0)
        self.descriptors = UInt64(0)
        self.pipeline_layout = UInt64(0)
        self.world_pipeline = UInt64(0)
        self.shadow_pipeline = UInt64(0)
        self.overlay_pipeline = UInt64(0)
        self.scene_depth_pipeline = UInt64(0)
        self.uniform = Buffer()
        self.overlay_buffer = Buffer()
        self.readback = Buffer()
        self.textures = Array[Texture, 257](fill=Texture())
        self.texture_count = UInt32(0)
        self.font_texture = Int32(0)
        self.meshes = Array[Mesh, 4096](fill=Mesh())
        self.shadow_draws = UInt64(0)
        self.color_draws = UInt64(0)
        self.shadow_count = UInt64(0)
        self.color_count = UInt64(0)
        self.shadow_capacity = UInt64(0)
        self.color_capacity = UInt64(0)
        self.quads = UInt64(0)
        self.quad_count = UInt64(0)
        self.quad_capacity = UInt64(0)
        self.frame = Frame()
        self.width = Int32(0)
        self.height = Int32(0)
        self.target_width = Int32(0)
        self.target_height = Int32(0)
        self.rendered = Int32(0)
        self.frame_started = Int32(0)
        self.triangles = Int32(0)
        self.validation_errors = Int32(0)
        self.validation_enabled = Int32(0)
        self.driver = Array[Int8, 256](fill=Int8(0))
        self.scalability=0

struct VkDebugUtilsMessengerCallbackDataEXT(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var pMessageIdName: UInt64
    var messageIdNumber: Int32
    var pMessage: UInt64
    var queueLabelCount: UInt32
    var pQueueLabels: UInt64
    var cmdBufLabelCount: UInt32
    var pCmdBufLabels: UInt64
    var objectCount: UInt32
    var pObjects: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.pMessageIdName = UInt64(0)
        self.messageIdNumber = Int32(0)
        self.pMessage = UInt64(0)
        self.queueLabelCount = UInt32(0)
        self.pQueueLabels = UInt64(0)
        self.cmdBufLabelCount = UInt32(0)
        self.pCmdBufLabels = UInt64(0)
        self.objectCount = UInt32(0)
        self.pObjects = UInt64(0)

struct VkBufferCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var size: UInt64
    var usage: UInt32
    var sharingMode: Int32
    var queueFamilyIndexCount: UInt32
    var pQueueFamilyIndices: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.size = UInt64(0)
        self.usage = UInt32(0)
        self.sharingMode = Int32(0)
        self.queueFamilyIndexCount = UInt32(0)
        self.pQueueFamilyIndices = UInt64(0)

struct VkMemoryRequirements(Copyable, Movable):
    var size: UInt64
    var alignment: UInt64
    var memoryTypeBits: UInt32
    def __init__(out self):
        self.size = UInt64(0)
        self.alignment = UInt64(0)
        self.memoryTypeBits = UInt32(0)

struct VkMemoryAllocateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var allocationSize: UInt64
    var memoryTypeIndex: UInt32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.allocationSize = UInt64(0)
        self.memoryTypeIndex = UInt32(0)

struct VkExtent3D(Copyable, Movable):
    var width: UInt32
    var height: UInt32
    var depth: UInt32
    def __init__(out self):
        self.width = UInt32(0)
        self.height = UInt32(0)
        self.depth = UInt32(0)

struct VkImageCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var imageType: Int32
    var c_format: Int32
    var extent: VkExtent3D
    var mipLevels: UInt32
    var arrayLayers: UInt32
    var samples: Int32
    var tiling: Int32
    var usage: UInt32
    var sharingMode: Int32
    var queueFamilyIndexCount: UInt32
    var pQueueFamilyIndices: UInt64
    var initialLayout: Int32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.imageType = Int32(0)
        self.c_format = Int32(0)
        self.extent = VkExtent3D()
        self.mipLevels = UInt32(0)
        self.arrayLayers = UInt32(0)
        self.samples = Int32(0)
        self.tiling = Int32(0)
        self.usage = UInt32(0)
        self.sharingMode = Int32(0)
        self.queueFamilyIndexCount = UInt32(0)
        self.pQueueFamilyIndices = UInt64(0)
        self.initialLayout = Int32(0)

struct VkComponentMapping(Copyable, Movable):
    var r: Int32
    var g: Int32
    var b: Int32
    var a: Int32
    def __init__(out self):
        self.r = Int32(0)
        self.g = Int32(0)
        self.b = Int32(0)
        self.a = Int32(0)

struct VkImageSubresourceRange(Copyable, Movable):
    var aspectMask: UInt32
    var baseMipLevel: UInt32
    var levelCount: UInt32
    var baseArrayLayer: UInt32
    var layerCount: UInt32
    def __init__(out self):
        self.aspectMask = UInt32(0)
        self.baseMipLevel = UInt32(0)
        self.levelCount = UInt32(0)
        self.baseArrayLayer = UInt32(0)
        self.layerCount = UInt32(0)

struct VkImageViewCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var image: UInt64
    var viewType: Int32
    var c_format: Int32
    var components: VkComponentMapping
    var subresourceRange: VkImageSubresourceRange
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.image = UInt64(0)
        self.viewType = Int32(0)
        self.c_format = Int32(0)
        self.components = VkComponentMapping()
        self.subresourceRange = VkImageSubresourceRange()

struct VkImageMemoryBarrier(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var srcAccessMask: UInt32
    var dstAccessMask: UInt32
    var oldLayout: Int32
    var newLayout: Int32
    var srcQueueFamilyIndex: UInt32
    var dstQueueFamilyIndex: UInt32
    var image: UInt64
    var subresourceRange: VkImageSubresourceRange
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.srcAccessMask = UInt32(0)
        self.dstAccessMask = UInt32(0)
        self.oldLayout = Int32(0)
        self.newLayout = Int32(0)
        self.srcQueueFamilyIndex = UInt32(0)
        self.dstQueueFamilyIndex = UInt32(0)
        self.image = UInt64(0)
        self.subresourceRange = VkImageSubresourceRange()

struct VkCommandBufferBeginInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var pInheritanceInfo: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.pInheritanceInfo = UInt64(0)

struct VkSubmitInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var waitSemaphoreCount: UInt32
    var pWaitSemaphores: UInt64
    var pWaitDstStageMask: UInt64
    var commandBufferCount: UInt32
    var pCommandBuffers: UInt64
    var signalSemaphoreCount: UInt32
    var pSignalSemaphores: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.waitSemaphoreCount = UInt32(0)
        self.pWaitSemaphores = UInt64(0)
        self.pWaitDstStageMask = UInt64(0)
        self.commandBufferCount = UInt32(0)
        self.pCommandBuffers = UInt64(0)
        self.signalSemaphoreCount = UInt32(0)
        self.pSignalSemaphores = UInt64(0)

struct VkFenceCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)

struct VkAttachmentDescription(Copyable, Movable):
    var flags: UInt32
    var c_format: Int32
    var samples: Int32
    var loadOp: Int32
    var storeOp: Int32
    var stencilLoadOp: Int32
    var stencilStoreOp: Int32
    var initialLayout: Int32
    var finalLayout: Int32
    def __init__(out self):
        self.flags = UInt32(0)
        self.c_format = Int32(0)
        self.samples = Int32(0)
        self.loadOp = Int32(0)
        self.storeOp = Int32(0)
        self.stencilLoadOp = Int32(0)
        self.stencilStoreOp = Int32(0)
        self.initialLayout = Int32(0)
        self.finalLayout = Int32(0)

struct VkAttachmentReference(Copyable, Movable):
    var attachment: UInt32
    var layout: Int32
    def __init__(out self):
        self.attachment = UInt32(0)
        self.layout = Int32(0)

struct VkSubpassDescription(Copyable, Movable):
    var flags: UInt32
    var pipelineBindPoint: Int32
    var inputAttachmentCount: UInt32
    var pInputAttachments: UInt64
    var colorAttachmentCount: UInt32
    var pColorAttachments: UInt64
    var pResolveAttachments: UInt64
    var pDepthStencilAttachment: UInt64
    var preserveAttachmentCount: UInt32
    var pPreserveAttachments: UInt64
    def __init__(out self):
        self.flags = UInt32(0)
        self.pipelineBindPoint = Int32(0)
        self.inputAttachmentCount = UInt32(0)
        self.pInputAttachments = UInt64(0)
        self.colorAttachmentCount = UInt32(0)
        self.pColorAttachments = UInt64(0)
        self.pResolveAttachments = UInt64(0)
        self.pDepthStencilAttachment = UInt64(0)
        self.preserveAttachmentCount = UInt32(0)
        self.pPreserveAttachments = UInt64(0)

struct VkSubpassDependency(Copyable, Movable):
    var srcSubpass: UInt32
    var dstSubpass: UInt32
    var srcStageMask: UInt32
    var dstStageMask: UInt32
    var srcAccessMask: UInt32
    var dstAccessMask: UInt32
    var dependencyFlags: UInt32
    def __init__(out self):
        self.srcSubpass = UInt32(0)
        self.dstSubpass = UInt32(0)
        self.srcStageMask = UInt32(0)
        self.dstStageMask = UInt32(0)
        self.srcAccessMask = UInt32(0)
        self.dstAccessMask = UInt32(0)
        self.dependencyFlags = UInt32(0)

struct VkRenderPassCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var attachmentCount: UInt32
    var pAttachments: UInt64
    var subpassCount: UInt32
    var pSubpasses: UInt64
    var dependencyCount: UInt32
    var pDependencies: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.attachmentCount = UInt32(0)
        self.pAttachments = UInt64(0)
        self.subpassCount = UInt32(0)
        self.pSubpasses = UInt64(0)
        self.dependencyCount = UInt32(0)
        self.pDependencies = UInt64(0)

struct VkShaderModuleCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var codeSize: UInt64
    var pCode: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.codeSize = UInt64(0)
        self.pCode = UInt64(0)

struct VkPipelineShaderStageCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var stage: Int32
    var module: UInt64
    var pName: UInt64
    var pSpecializationInfo: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.stage = Int32(0)
        self.module = UInt64(0)
        self.pName = UInt64(0)
        self.pSpecializationInfo = UInt64(0)

struct VkVertexInputBindingDescription(Copyable, Movable):
    var binding: UInt32
    var stride: UInt32
    var inputRate: Int32
    def __init__(out self):
        self.binding = UInt32(0)
        self.stride = UInt32(0)
        self.inputRate = Int32(0)

struct VkVertexInputAttributeDescription(Copyable, Movable):
    var location: UInt32
    var binding: UInt32
    var c_format: Int32
    var offset: UInt32
    def __init__(out self):
        self.location = UInt32(0)
        self.binding = UInt32(0)
        self.c_format = Int32(0)
        self.offset = UInt32(0)

struct VkPipelineVertexInputStateCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var vertexBindingDescriptionCount: UInt32
    var pVertexBindingDescriptions: UInt64
    var vertexAttributeDescriptionCount: UInt32
    var pVertexAttributeDescriptions: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.vertexBindingDescriptionCount = UInt32(0)
        self.pVertexBindingDescriptions = UInt64(0)
        self.vertexAttributeDescriptionCount = UInt32(0)
        self.pVertexAttributeDescriptions = UInt64(0)

struct VkPipelineInputAssemblyStateCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var topology: Int32
    var primitiveRestartEnable: UInt32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.topology = Int32(0)
        self.primitiveRestartEnable = UInt32(0)

struct VkPipelineViewportStateCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var viewportCount: UInt32
    var pViewports: UInt64
    var scissorCount: UInt32
    var pScissors: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.viewportCount = UInt32(0)
        self.pViewports = UInt64(0)
        self.scissorCount = UInt32(0)
        self.pScissors = UInt64(0)

struct VkPipelineRasterizationStateCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var depthClampEnable: UInt32
    var rasterizerDiscardEnable: UInt32
    var polygonMode: Int32
    var cullMode: UInt32
    var frontFace: Int32
    var depthBiasEnable: UInt32
    var depthBiasConstantFactor: Float32
    var depthBiasClamp: Float32
    var depthBiasSlopeFactor: Float32
    var lineWidth: Float32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.depthClampEnable = UInt32(0)
        self.rasterizerDiscardEnable = UInt32(0)
        self.polygonMode = Int32(0)
        self.cullMode = UInt32(0)
        self.frontFace = Int32(0)
        self.depthBiasEnable = UInt32(0)
        self.depthBiasConstantFactor = Float32(0)
        self.depthBiasClamp = Float32(0)
        self.depthBiasSlopeFactor = Float32(0)
        self.lineWidth = Float32(0)

struct VkPipelineMultisampleStateCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var rasterizationSamples: Int32
    var sampleShadingEnable: UInt32
    var minSampleShading: Float32
    var pSampleMask: UInt64
    var alphaToCoverageEnable: UInt32
    var alphaToOneEnable: UInt32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.rasterizationSamples = Int32(0)
        self.sampleShadingEnable = UInt32(0)
        self.minSampleShading = Float32(0)
        self.pSampleMask = UInt64(0)
        self.alphaToCoverageEnable = UInt32(0)
        self.alphaToOneEnable = UInt32(0)

struct VkStencilOpState(Copyable, Movable):
    var failOp: Int32
    var passOp: Int32
    var depthFailOp: Int32
    var compareOp: Int32
    var compareMask: UInt32
    var writeMask: UInt32
    var reference: UInt32
    def __init__(out self):
        self.failOp = Int32(0)
        self.passOp = Int32(0)
        self.depthFailOp = Int32(0)
        self.compareOp = Int32(0)
        self.compareMask = UInt32(0)
        self.writeMask = UInt32(0)
        self.reference = UInt32(0)

struct VkPipelineDepthStencilStateCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var depthTestEnable: UInt32
    var depthWriteEnable: UInt32
    var depthCompareOp: Int32
    var depthBoundsTestEnable: UInt32
    var stencilTestEnable: UInt32
    var front: VkStencilOpState
    var back: VkStencilOpState
    var minDepthBounds: Float32
    var maxDepthBounds: Float32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.depthTestEnable = UInt32(0)
        self.depthWriteEnable = UInt32(0)
        self.depthCompareOp = Int32(0)
        self.depthBoundsTestEnable = UInt32(0)
        self.stencilTestEnable = UInt32(0)
        self.front = VkStencilOpState()
        self.back = VkStencilOpState()
        self.minDepthBounds = Float32(0)
        self.maxDepthBounds = Float32(0)

struct VkPipelineColorBlendAttachmentState(Copyable, Movable):
    var blendEnable: UInt32
    var srcColorBlendFactor: Int32
    var dstColorBlendFactor: Int32
    var colorBlendOp: Int32
    var srcAlphaBlendFactor: Int32
    var dstAlphaBlendFactor: Int32
    var alphaBlendOp: Int32
    var colorWriteMask: UInt32
    def __init__(out self):
        self.blendEnable = UInt32(0)
        self.srcColorBlendFactor = Int32(0)
        self.dstColorBlendFactor = Int32(0)
        self.colorBlendOp = Int32(0)
        self.srcAlphaBlendFactor = Int32(0)
        self.dstAlphaBlendFactor = Int32(0)
        self.alphaBlendOp = Int32(0)
        self.colorWriteMask = UInt32(0)

struct VkPipelineColorBlendStateCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var logicOpEnable: UInt32
    var logicOp: Int32
    var attachmentCount: UInt32
    var pAttachments: UInt64
    var blendConstants: Array[Float32, 4]
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.logicOpEnable = UInt32(0)
        self.logicOp = Int32(0)
        self.attachmentCount = UInt32(0)
        self.pAttachments = UInt64(0)
        self.blendConstants = Array[Float32, 4](fill=Float32(0))

struct VkPipelineDynamicStateCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var dynamicStateCount: UInt32
    var pDynamicStates: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.dynamicStateCount = UInt32(0)
        self.pDynamicStates = UInt64(0)

struct VkGraphicsPipelineCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var stageCount: UInt32
    var pStages: UInt64
    var pVertexInputState: UInt64
    var pInputAssemblyState: UInt64
    var pTessellationState: UInt64
    var pViewportState: UInt64
    var pRasterizationState: UInt64
    var pMultisampleState: UInt64
    var pDepthStencilState: UInt64
    var pColorBlendState: UInt64
    var pDynamicState: UInt64
    var layout: UInt64
    var renderPass: UInt64
    var subpass: UInt32
    var basePipelineHandle: UInt64
    var basePipelineIndex: Int32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.stageCount = UInt32(0)
        self.pStages = UInt64(0)
        self.pVertexInputState = UInt64(0)
        self.pInputAssemblyState = UInt64(0)
        self.pTessellationState = UInt64(0)
        self.pViewportState = UInt64(0)
        self.pRasterizationState = UInt64(0)
        self.pMultisampleState = UInt64(0)
        self.pDepthStencilState = UInt64(0)
        self.pColorBlendState = UInt64(0)
        self.pDynamicState = UInt64(0)
        self.layout = UInt64(0)
        self.renderPass = UInt64(0)
        self.subpass = UInt32(0)
        self.basePipelineHandle = UInt64(0)
        self.basePipelineIndex = Int32(0)

struct VkFramebufferCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var renderPass: UInt64
    var attachmentCount: UInt32
    var pAttachments: UInt64
    var width: UInt32
    var height: UInt32
    var layers: UInt32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.renderPass = UInt64(0)
        self.attachmentCount = UInt32(0)
        self.pAttachments = UInt64(0)
        self.width = UInt32(0)
        self.height = UInt32(0)
        self.layers = UInt32(0)

struct VkClearColorValue(Copyable, Movable):
    var storage: Array[UInt32, 4]
    def __init__(out self):
        self.storage = Array[UInt32, 4](fill=0)

struct VkClearDepthStencilValue(Copyable, Movable):
    var depth: Float32
    var stencil: UInt32
    def __init__(out self):
        self.depth = Float32(0)
        self.stencil = UInt32(0)

struct VkDescriptorImageInfo(Copyable, Movable):
    var sampler: UInt64
    var imageView: UInt64
    var imageLayout: Int32
    def __init__(out self):
        self.sampler = UInt64(0)
        self.imageView = UInt64(0)
        self.imageLayout = Int32(0)

struct VkWriteDescriptorSet(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var dstSet: UInt64
    var dstBinding: UInt32
    var dstArrayElement: UInt32
    var descriptorCount: UInt32
    var descriptorType: Int32
    var pImageInfo: UInt64
    var pBufferInfo: UInt64
    var pTexelBufferView: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.dstSet = UInt64(0)
        self.dstBinding = UInt32(0)
        self.dstArrayElement = UInt32(0)
        self.descriptorCount = UInt32(0)
        self.descriptorType = Int32(0)
        self.pImageInfo = UInt64(0)
        self.pBufferInfo = UInt64(0)
        self.pTexelBufferView = UInt64(0)

struct VkFormatProperties(Copyable, Movable):
    var linearTilingFeatures: UInt32
    var optimalTilingFeatures: UInt32
    var bufferFeatures: UInt32
    def __init__(out self):
        self.linearTilingFeatures = UInt32(0)
        self.optimalTilingFeatures = UInt32(0)
        self.bufferFeatures = UInt32(0)

struct VkImageSubresourceLayers(Copyable, Movable):
    var aspectMask: UInt32
    var mipLevel: UInt32
    var baseArrayLayer: UInt32
    var layerCount: UInt32
    def __init__(out self):
        self.aspectMask = UInt32(0)
        self.mipLevel = UInt32(0)
        self.baseArrayLayer = UInt32(0)
        self.layerCount = UInt32(0)

struct VkOffset3D(Copyable, Movable):
    var x: Int32
    var y: Int32
    var z: Int32
    def __init__(out self):
        self.x = Int32(0)
        self.y = Int32(0)
        self.z = Int32(0)

struct VkBufferImageCopy(Copyable, Movable):
    var bufferOffset: UInt64
    var bufferRowLength: UInt32
    var bufferImageHeight: UInt32
    var imageSubresource: VkImageSubresourceLayers
    var imageOffset: VkOffset3D
    var imageExtent: VkExtent3D
    def __init__(out self):
        self.bufferOffset = UInt64(0)
        self.bufferRowLength = UInt32(0)
        self.bufferImageHeight = UInt32(0)
        self.imageSubresource = VkImageSubresourceLayers()
        self.imageOffset = VkOffset3D()
        self.imageExtent = VkExtent3D()

struct VkImageBlit(Copyable, Movable):
    var srcSubresource: VkImageSubresourceLayers
    var srcOffsets: Array[VkOffset3D, 2]
    var dstSubresource: VkImageSubresourceLayers
    var dstOffsets: Array[VkOffset3D, 2]
    def __init__(out self):
        self.srcSubresource = VkImageSubresourceLayers()
        self.srcOffsets = Array[VkOffset3D, 2](fill=VkOffset3D())
        self.dstSubresource = VkImageSubresourceLayers()
        self.dstOffsets = Array[VkOffset3D, 2](fill=VkOffset3D())

struct VkDescriptorSetAllocateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var descriptorPool: UInt64
    var descriptorSetCount: UInt32
    var pSetLayouts: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.descriptorPool = UInt64(0)
        self.descriptorSetCount = UInt32(0)
        self.pSetLayouts = UInt64(0)

struct VkDescriptorBufferInfo(Copyable, Movable):
    var buffer: UInt64
    var offset: UInt64
    var c_range: UInt64
    def __init__(out self):
        self.buffer = UInt64(0)
        self.offset = UInt64(0)
        self.c_range = UInt64(0)

struct VkDescriptorSetLayoutBinding(Copyable, Movable):
    var binding: UInt32
    var descriptorType: Int32
    var descriptorCount: UInt32
    var stageFlags: UInt32
    var pImmutableSamplers: UInt64
    def __init__(out self):
        self.binding = UInt32(0)
        self.descriptorType = Int32(0)
        self.descriptorCount = UInt32(0)
        self.stageFlags = UInt32(0)
        self.pImmutableSamplers = UInt64(0)

struct VkDescriptorSetLayoutCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var bindingCount: UInt32
    var pBindings: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.bindingCount = UInt32(0)
        self.pBindings = UInt64(0)

struct VkDescriptorPoolSize(Copyable, Movable):
    var c_type: Int32
    var descriptorCount: UInt32
    def __init__(out self):
        self.c_type = Int32(0)
        self.descriptorCount = UInt32(0)

struct VkDescriptorPoolCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var maxSets: UInt32
    var poolSizeCount: UInt32
    var pPoolSizes: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.maxSets = UInt32(0)
        self.poolSizeCount = UInt32(0)
        self.pPoolSizes = UInt64(0)

struct VkPushConstantRange(Copyable, Movable):
    var stageFlags: UInt32
    var offset: UInt32
    var size: UInt32
    def __init__(out self):
        self.stageFlags = UInt32(0)
        self.offset = UInt32(0)
        self.size = UInt32(0)

struct Object(Copyable, Movable):
    var model: Array[Float32, 16]
    var color: Array[Float32, 4]
    var params: Array[Float32, 4]
    var pose: Array[Float32, 4]
    def __init__(out self):
        self.model = Array[Float32, 16](fill=Float32(0))
        self.color = Array[Float32, 4](fill=Float32(0))
        self.params = Array[Float32, 4](fill=Float32(0))
        self.pose = Array[Float32, 4](fill=Float32(0))

struct VkPipelineLayoutCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var setLayoutCount: UInt32
    var pSetLayouts: UInt64
    var pushConstantRangeCount: UInt32
    var pPushConstantRanges: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.setLayoutCount = UInt32(0)
        self.pSetLayouts = UInt64(0)
        self.pushConstantRangeCount = UInt32(0)
        self.pPushConstantRanges = UInt64(0)

struct VkSamplerCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var magFilter: Int32
    var minFilter: Int32
    var mipmapMode: Int32
    var addressModeU: Int32
    var addressModeV: Int32
    var addressModeW: Int32
    var mipLodBias: Float32
    var anisotropyEnable: UInt32
    var maxAnisotropy: Float32
    var compareEnable: UInt32
    var compareOp: Int32
    var minLod: Float32
    var maxLod: Float32
    var borderColor: Int32
    var unnormalizedCoordinates: UInt32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.magFilter = Int32(0)
        self.minFilter = Int32(0)
        self.mipmapMode = Int32(0)
        self.addressModeU = Int32(0)
        self.addressModeV = Int32(0)
        self.addressModeW = Int32(0)
        self.mipLodBias = Float32(0)
        self.anisotropyEnable = UInt32(0)
        self.maxAnisotropy = Float32(0)
        self.compareEnable = UInt32(0)
        self.compareOp = Int32(0)
        self.minLod = Float32(0)
        self.maxLod = Float32(0)
        self.borderColor = Int32(0)
        self.unnormalizedCoordinates = UInt32(0)

struct VkApplicationInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var pApplicationName: UInt64
    var applicationVersion: UInt32
    var pEngineName: UInt64
    var engineVersion: UInt32
    var apiVersion: UInt32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.pApplicationName = UInt64(0)
        self.applicationVersion = UInt32(0)
        self.pEngineName = UInt64(0)
        self.engineVersion = UInt32(0)
        self.apiVersion = UInt32(0)

struct VkDebugUtilsMessengerCreateInfoEXT(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var messageSeverity: UInt32
    var messageType: UInt32
    var pfnUserCallback: UInt64
    var pUserData: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.messageSeverity = UInt32(0)
        self.messageType = UInt32(0)
        self.pfnUserCallback = UInt64(0)
        self.pUserData = UInt64(0)

struct VkInstanceCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var pApplicationInfo: UInt64
    var enabledLayerCount: UInt32
    var ppEnabledLayerNames: UInt64
    var enabledExtensionCount: UInt32
    var ppEnabledExtensionNames: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.pApplicationInfo = UInt64(0)
        self.enabledLayerCount = UInt32(0)
        self.ppEnabledLayerNames = UInt64(0)
        self.enabledExtensionCount = UInt32(0)
        self.ppEnabledExtensionNames = UInt64(0)

struct VkPhysicalDeviceLimits(Copyable, Movable):
    var maxImageDimension1D: UInt32
    var maxImageDimension2D: UInt32
    var maxImageDimension3D: UInt32
    var maxImageDimensionCube: UInt32
    var maxImageArrayLayers: UInt32
    var maxTexelBufferElements: UInt32
    var maxUniformBufferRange: UInt32
    var maxStorageBufferRange: UInt32
    var maxPushConstantsSize: UInt32
    var maxMemoryAllocationCount: UInt32
    var maxSamplerAllocationCount: UInt32
    var bufferImageGranularity: UInt64
    var sparseAddressSpaceSize: UInt64
    var maxBoundDescriptorSets: UInt32
    var maxPerStageDescriptorSamplers: UInt32
    var maxPerStageDescriptorUniformBuffers: UInt32
    var maxPerStageDescriptorStorageBuffers: UInt32
    var maxPerStageDescriptorSampledImages: UInt32
    var maxPerStageDescriptorStorageImages: UInt32
    var maxPerStageDescriptorInputAttachments: UInt32
    var maxPerStageResources: UInt32
    var maxDescriptorSetSamplers: UInt32
    var maxDescriptorSetUniformBuffers: UInt32
    var maxDescriptorSetUniformBuffersDynamic: UInt32
    var maxDescriptorSetStorageBuffers: UInt32
    var maxDescriptorSetStorageBuffersDynamic: UInt32
    var maxDescriptorSetSampledImages: UInt32
    var maxDescriptorSetStorageImages: UInt32
    var maxDescriptorSetInputAttachments: UInt32
    var maxVertexInputAttributes: UInt32
    var maxVertexInputBindings: UInt32
    var maxVertexInputAttributeOffset: UInt32
    var maxVertexInputBindingStride: UInt32
    var maxVertexOutputComponents: UInt32
    var maxTessellationGenerationLevel: UInt32
    var maxTessellationPatchSize: UInt32
    var maxTessellationControlPerVertexInputComponents: UInt32
    var maxTessellationControlPerVertexOutputComponents: UInt32
    var maxTessellationControlPerPatchOutputComponents: UInt32
    var maxTessellationControlTotalOutputComponents: UInt32
    var maxTessellationEvaluationInputComponents: UInt32
    var maxTessellationEvaluationOutputComponents: UInt32
    var maxGeometryShaderInvocations: UInt32
    var maxGeometryInputComponents: UInt32
    var maxGeometryOutputComponents: UInt32
    var maxGeometryOutputVertices: UInt32
    var maxGeometryTotalOutputComponents: UInt32
    var maxFragmentInputComponents: UInt32
    var maxFragmentOutputAttachments: UInt32
    var maxFragmentDualSrcAttachments: UInt32
    var maxFragmentCombinedOutputResources: UInt32
    var maxComputeSharedMemorySize: UInt32
    var maxComputeWorkGroupCount: Array[UInt32, 3]
    var maxComputeWorkGroupInvocations: UInt32
    var maxComputeWorkGroupSize: Array[UInt32, 3]
    var subPixelPrecisionBits: UInt32
    var subTexelPrecisionBits: UInt32
    var mipmapPrecisionBits: UInt32
    var maxDrawIndexedIndexValue: UInt32
    var maxDrawIndirectCount: UInt32
    var maxSamplerLodBias: Float32
    var maxSamplerAnisotropy: Float32
    var maxViewports: UInt32
    var maxViewportDimensions: Array[UInt32, 2]
    var viewportBoundsRange: Array[Float32, 2]
    var viewportSubPixelBits: UInt32
    var minMemoryMapAlignment: UInt64
    var minTexelBufferOffsetAlignment: UInt64
    var minUniformBufferOffsetAlignment: UInt64
    var minStorageBufferOffsetAlignment: UInt64
    var minTexelOffset: Int32
    var maxTexelOffset: UInt32
    var minTexelGatherOffset: Int32
    var maxTexelGatherOffset: UInt32
    var minInterpolationOffset: Float32
    var maxInterpolationOffset: Float32
    var subPixelInterpolationOffsetBits: UInt32
    var maxFramebufferWidth: UInt32
    var maxFramebufferHeight: UInt32
    var maxFramebufferLayers: UInt32
    var framebufferColorSampleCounts: UInt32
    var framebufferDepthSampleCounts: UInt32
    var framebufferStencilSampleCounts: UInt32
    var framebufferNoAttachmentsSampleCounts: UInt32
    var maxColorAttachments: UInt32
    var sampledImageColorSampleCounts: UInt32
    var sampledImageIntegerSampleCounts: UInt32
    var sampledImageDepthSampleCounts: UInt32
    var sampledImageStencilSampleCounts: UInt32
    var storageImageSampleCounts: UInt32
    var maxSampleMaskWords: UInt32
    var timestampComputeAndGraphics: UInt32
    var timestampPeriod: Float32
    var maxClipDistances: UInt32
    var maxCullDistances: UInt32
    var maxCombinedClipAndCullDistances: UInt32
    var discreteQueuePriorities: UInt32
    var pointSizeRange: Array[Float32, 2]
    var lineWidthRange: Array[Float32, 2]
    var pointSizeGranularity: Float32
    var lineWidthGranularity: Float32
    var strictLines: UInt32
    var standardSampleLocations: UInt32
    var optimalBufferCopyOffsetAlignment: UInt64
    var optimalBufferCopyRowPitchAlignment: UInt64
    var nonCoherentAtomSize: UInt64
    def __init__(out self):
        self.maxImageDimension1D = UInt32(0)
        self.maxImageDimension2D = UInt32(0)
        self.maxImageDimension3D = UInt32(0)
        self.maxImageDimensionCube = UInt32(0)
        self.maxImageArrayLayers = UInt32(0)
        self.maxTexelBufferElements = UInt32(0)
        self.maxUniformBufferRange = UInt32(0)
        self.maxStorageBufferRange = UInt32(0)
        self.maxPushConstantsSize = UInt32(0)
        self.maxMemoryAllocationCount = UInt32(0)
        self.maxSamplerAllocationCount = UInt32(0)
        self.bufferImageGranularity = UInt64(0)
        self.sparseAddressSpaceSize = UInt64(0)
        self.maxBoundDescriptorSets = UInt32(0)
        self.maxPerStageDescriptorSamplers = UInt32(0)
        self.maxPerStageDescriptorUniformBuffers = UInt32(0)
        self.maxPerStageDescriptorStorageBuffers = UInt32(0)
        self.maxPerStageDescriptorSampledImages = UInt32(0)
        self.maxPerStageDescriptorStorageImages = UInt32(0)
        self.maxPerStageDescriptorInputAttachments = UInt32(0)
        self.maxPerStageResources = UInt32(0)
        self.maxDescriptorSetSamplers = UInt32(0)
        self.maxDescriptorSetUniformBuffers = UInt32(0)
        self.maxDescriptorSetUniformBuffersDynamic = UInt32(0)
        self.maxDescriptorSetStorageBuffers = UInt32(0)
        self.maxDescriptorSetStorageBuffersDynamic = UInt32(0)
        self.maxDescriptorSetSampledImages = UInt32(0)
        self.maxDescriptorSetStorageImages = UInt32(0)
        self.maxDescriptorSetInputAttachments = UInt32(0)
        self.maxVertexInputAttributes = UInt32(0)
        self.maxVertexInputBindings = UInt32(0)
        self.maxVertexInputAttributeOffset = UInt32(0)
        self.maxVertexInputBindingStride = UInt32(0)
        self.maxVertexOutputComponents = UInt32(0)
        self.maxTessellationGenerationLevel = UInt32(0)
        self.maxTessellationPatchSize = UInt32(0)
        self.maxTessellationControlPerVertexInputComponents = UInt32(0)
        self.maxTessellationControlPerVertexOutputComponents = UInt32(0)
        self.maxTessellationControlPerPatchOutputComponents = UInt32(0)
        self.maxTessellationControlTotalOutputComponents = UInt32(0)
        self.maxTessellationEvaluationInputComponents = UInt32(0)
        self.maxTessellationEvaluationOutputComponents = UInt32(0)
        self.maxGeometryShaderInvocations = UInt32(0)
        self.maxGeometryInputComponents = UInt32(0)
        self.maxGeometryOutputComponents = UInt32(0)
        self.maxGeometryOutputVertices = UInt32(0)
        self.maxGeometryTotalOutputComponents = UInt32(0)
        self.maxFragmentInputComponents = UInt32(0)
        self.maxFragmentOutputAttachments = UInt32(0)
        self.maxFragmentDualSrcAttachments = UInt32(0)
        self.maxFragmentCombinedOutputResources = UInt32(0)
        self.maxComputeSharedMemorySize = UInt32(0)
        self.maxComputeWorkGroupCount = Array[UInt32, 3](fill=UInt32(0))
        self.maxComputeWorkGroupInvocations = UInt32(0)
        self.maxComputeWorkGroupSize = Array[UInt32, 3](fill=UInt32(0))
        self.subPixelPrecisionBits = UInt32(0)
        self.subTexelPrecisionBits = UInt32(0)
        self.mipmapPrecisionBits = UInt32(0)
        self.maxDrawIndexedIndexValue = UInt32(0)
        self.maxDrawIndirectCount = UInt32(0)
        self.maxSamplerLodBias = Float32(0)
        self.maxSamplerAnisotropy = Float32(0)
        self.maxViewports = UInt32(0)
        self.maxViewportDimensions = Array[UInt32, 2](fill=UInt32(0))
        self.viewportBoundsRange = Array[Float32, 2](fill=Float32(0))
        self.viewportSubPixelBits = UInt32(0)
        self.minMemoryMapAlignment = UInt64(0)
        self.minTexelBufferOffsetAlignment = UInt64(0)
        self.minUniformBufferOffsetAlignment = UInt64(0)
        self.minStorageBufferOffsetAlignment = UInt64(0)
        self.minTexelOffset = Int32(0)
        self.maxTexelOffset = UInt32(0)
        self.minTexelGatherOffset = Int32(0)
        self.maxTexelGatherOffset = UInt32(0)
        self.minInterpolationOffset = Float32(0)
        self.maxInterpolationOffset = Float32(0)
        self.subPixelInterpolationOffsetBits = UInt32(0)
        self.maxFramebufferWidth = UInt32(0)
        self.maxFramebufferHeight = UInt32(0)
        self.maxFramebufferLayers = UInt32(0)
        self.framebufferColorSampleCounts = UInt32(0)
        self.framebufferDepthSampleCounts = UInt32(0)
        self.framebufferStencilSampleCounts = UInt32(0)
        self.framebufferNoAttachmentsSampleCounts = UInt32(0)
        self.maxColorAttachments = UInt32(0)
        self.sampledImageColorSampleCounts = UInt32(0)
        self.sampledImageIntegerSampleCounts = UInt32(0)
        self.sampledImageDepthSampleCounts = UInt32(0)
        self.sampledImageStencilSampleCounts = UInt32(0)
        self.storageImageSampleCounts = UInt32(0)
        self.maxSampleMaskWords = UInt32(0)
        self.timestampComputeAndGraphics = UInt32(0)
        self.timestampPeriod = Float32(0)
        self.maxClipDistances = UInt32(0)
        self.maxCullDistances = UInt32(0)
        self.maxCombinedClipAndCullDistances = UInt32(0)
        self.discreteQueuePriorities = UInt32(0)
        self.pointSizeRange = Array[Float32, 2](fill=Float32(0))
        self.lineWidthRange = Array[Float32, 2](fill=Float32(0))
        self.pointSizeGranularity = Float32(0)
        self.lineWidthGranularity = Float32(0)
        self.strictLines = UInt32(0)
        self.standardSampleLocations = UInt32(0)
        self.optimalBufferCopyOffsetAlignment = UInt64(0)
        self.optimalBufferCopyRowPitchAlignment = UInt64(0)
        self.nonCoherentAtomSize = UInt64(0)

struct VkPhysicalDeviceSparseProperties(Copyable, Movable):
    var residencyStandard2DBlockShape: UInt32
    var residencyStandard2DMultisampleBlockShape: UInt32
    var residencyStandard3DBlockShape: UInt32
    var residencyAlignedMipSize: UInt32
    var residencyNonResidentStrict: UInt32
    def __init__(out self):
        self.residencyStandard2DBlockShape = UInt32(0)
        self.residencyStandard2DMultisampleBlockShape = UInt32(0)
        self.residencyStandard3DBlockShape = UInt32(0)
        self.residencyAlignedMipSize = UInt32(0)
        self.residencyNonResidentStrict = UInt32(0)

struct VkPhysicalDeviceProperties(Copyable, Movable):
    var apiVersion: UInt32
    var driverVersion: UInt32
    var vendorID: UInt32
    var deviceID: UInt32
    var deviceType: Int32
    var deviceName: Array[Int8, 256]
    var pipelineCacheUUID: Array[UInt8, 16]
    var limits: VkPhysicalDeviceLimits
    var sparseProperties: VkPhysicalDeviceSparseProperties
    def __init__(out self):
        self.apiVersion = UInt32(0)
        self.driverVersion = UInt32(0)
        self.vendorID = UInt32(0)
        self.deviceID = UInt32(0)
        self.deviceType = Int32(0)
        self.deviceName = Array[Int8, 256](fill=Int8(0))
        self.pipelineCacheUUID = Array[UInt8, 16](fill=UInt8(0))
        self.limits = VkPhysicalDeviceLimits()
        self.sparseProperties = VkPhysicalDeviceSparseProperties()

struct VkQueueFamilyProperties(Copyable, Movable):
    var queueFlags: UInt32
    var queueCount: UInt32
    var timestampValidBits: UInt32
    var minImageTransferGranularity: VkExtent3D
    def __init__(out self):
        self.queueFlags = UInt32(0)
        self.queueCount = UInt32(0)
        self.timestampValidBits = UInt32(0)
        self.minImageTransferGranularity = VkExtent3D()

struct VkDeviceQueueCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var queueFamilyIndex: UInt32
    var queueCount: UInt32
    var pQueuePriorities: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.queueFamilyIndex = UInt32(0)
        self.queueCount = UInt32(0)
        self.pQueuePriorities = UInt64(0)

struct VkPhysicalDeviceFeatures(Copyable, Movable):
    var robustBufferAccess: UInt32
    var fullDrawIndexUint32: UInt32
    var imageCubeArray: UInt32
    var independentBlend: UInt32
    var geometryShader: UInt32
    var tessellationShader: UInt32
    var sampleRateShading: UInt32
    var dualSrcBlend: UInt32
    var logicOp: UInt32
    var multiDrawIndirect: UInt32
    var drawIndirectFirstInstance: UInt32
    var depthClamp: UInt32
    var depthBiasClamp: UInt32
    var fillModeNonSolid: UInt32
    var depthBounds: UInt32
    var wideLines: UInt32
    var largePoints: UInt32
    var alphaToOne: UInt32
    var multiViewport: UInt32
    var samplerAnisotropy: UInt32
    var textureCompressionETC2: UInt32
    var textureCompressionASTC_LDR: UInt32
    var textureCompressionBC: UInt32
    var occlusionQueryPrecise: UInt32
    var pipelineStatisticsQuery: UInt32
    var vertexPipelineStoresAndAtomics: UInt32
    var fragmentStoresAndAtomics: UInt32
    var shaderTessellationAndGeometryPointSize: UInt32
    var shaderImageGatherExtended: UInt32
    var shaderStorageImageExtendedFormats: UInt32
    var shaderStorageImageMultisample: UInt32
    var shaderStorageImageReadWithoutFormat: UInt32
    var shaderStorageImageWriteWithoutFormat: UInt32
    var shaderUniformBufferArrayDynamicIndexing: UInt32
    var shaderSampledImageArrayDynamicIndexing: UInt32
    var shaderStorageBufferArrayDynamicIndexing: UInt32
    var shaderStorageImageArrayDynamicIndexing: UInt32
    var shaderClipDistance: UInt32
    var shaderCullDistance: UInt32
    var shaderFloat64: UInt32
    var shaderInt64: UInt32
    var shaderInt16: UInt32
    var shaderResourceResidency: UInt32
    var shaderResourceMinLod: UInt32
    var sparseBinding: UInt32
    var sparseResidencyBuffer: UInt32
    var sparseResidencyImage2D: UInt32
    var sparseResidencyImage3D: UInt32
    var sparseResidency2Samples: UInt32
    var sparseResidency4Samples: UInt32
    var sparseResidency8Samples: UInt32
    var sparseResidency16Samples: UInt32
    var sparseResidencyAliased: UInt32
    var variableMultisampleRate: UInt32
    var inheritedQueries: UInt32
    def __init__(out self):
        self.robustBufferAccess = UInt32(0)
        self.fullDrawIndexUint32 = UInt32(0)
        self.imageCubeArray = UInt32(0)
        self.independentBlend = UInt32(0)
        self.geometryShader = UInt32(0)
        self.tessellationShader = UInt32(0)
        self.sampleRateShading = UInt32(0)
        self.dualSrcBlend = UInt32(0)
        self.logicOp = UInt32(0)
        self.multiDrawIndirect = UInt32(0)
        self.drawIndirectFirstInstance = UInt32(0)
        self.depthClamp = UInt32(0)
        self.depthBiasClamp = UInt32(0)
        self.fillModeNonSolid = UInt32(0)
        self.depthBounds = UInt32(0)
        self.wideLines = UInt32(0)
        self.largePoints = UInt32(0)
        self.alphaToOne = UInt32(0)
        self.multiViewport = UInt32(0)
        self.samplerAnisotropy = UInt32(0)
        self.textureCompressionETC2 = UInt32(0)
        self.textureCompressionASTC_LDR = UInt32(0)
        self.textureCompressionBC = UInt32(0)
        self.occlusionQueryPrecise = UInt32(0)
        self.pipelineStatisticsQuery = UInt32(0)
        self.vertexPipelineStoresAndAtomics = UInt32(0)
        self.fragmentStoresAndAtomics = UInt32(0)
        self.shaderTessellationAndGeometryPointSize = UInt32(0)
        self.shaderImageGatherExtended = UInt32(0)
        self.shaderStorageImageExtendedFormats = UInt32(0)
        self.shaderStorageImageMultisample = UInt32(0)
        self.shaderStorageImageReadWithoutFormat = UInt32(0)
        self.shaderStorageImageWriteWithoutFormat = UInt32(0)
        self.shaderUniformBufferArrayDynamicIndexing = UInt32(0)
        self.shaderSampledImageArrayDynamicIndexing = UInt32(0)
        self.shaderStorageBufferArrayDynamicIndexing = UInt32(0)
        self.shaderStorageImageArrayDynamicIndexing = UInt32(0)
        self.shaderClipDistance = UInt32(0)
        self.shaderCullDistance = UInt32(0)
        self.shaderFloat64 = UInt32(0)
        self.shaderInt64 = UInt32(0)
        self.shaderInt16 = UInt32(0)
        self.shaderResourceResidency = UInt32(0)
        self.shaderResourceMinLod = UInt32(0)
        self.sparseBinding = UInt32(0)
        self.sparseResidencyBuffer = UInt32(0)
        self.sparseResidencyImage2D = UInt32(0)
        self.sparseResidencyImage3D = UInt32(0)
        self.sparseResidency2Samples = UInt32(0)
        self.sparseResidency4Samples = UInt32(0)
        self.sparseResidency8Samples = UInt32(0)
        self.sparseResidency16Samples = UInt32(0)
        self.sparseResidencyAliased = UInt32(0)
        self.variableMultisampleRate = UInt32(0)
        self.inheritedQueries = UInt32(0)

struct VkImageFormatProperties(Copyable, Movable):
    var maxExtent: VkExtent3D
    var maxMipLevels: UInt32
    var maxArrayLayers: UInt32
    var sampleCounts: UInt32
    var maxResourceSize: UInt64
    def __init__(out self):
        self.maxExtent = VkExtent3D()
        self.maxMipLevels = UInt32(0)
        self.maxArrayLayers = UInt32(0)
        self.sampleCounts = UInt32(0)
        self.maxResourceSize = UInt64(0)

struct VkDeviceCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var queueCreateInfoCount: UInt32
    var pQueueCreateInfos: UInt64
    var enabledLayerCount: UInt32
    var ppEnabledLayerNames: UInt64
    var enabledExtensionCount: UInt32
    var ppEnabledExtensionNames: UInt64
    var pEnabledFeatures: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.queueCreateInfoCount = UInt32(0)
        self.pQueueCreateInfos = UInt64(0)
        self.enabledLayerCount = UInt32(0)
        self.ppEnabledLayerNames = UInt64(0)
        self.enabledExtensionCount = UInt32(0)
        self.ppEnabledExtensionNames = UInt64(0)
        self.pEnabledFeatures = UInt64(0)

struct VkQueryPoolCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var queryType: Int32
    var queryCount: UInt32
    var pipelineStatistics: UInt32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.queryType = Int32(0)
        self.queryCount = UInt32(0)
        self.pipelineStatistics = UInt32(0)

struct VkCommandPoolCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var queueFamilyIndex: UInt32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.queueFamilyIndex = UInt32(0)

struct VkCommandBufferAllocateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var commandPool: UInt64
    var level: Int32
    var commandBufferCount: UInt32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.commandPool = UInt64(0)
        self.level = Int32(0)
        self.commandBufferCount = UInt32(0)

struct VkSemaphoreCreateInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)

struct SDL_Rect(Copyable, Movable):
    var x: Int32
    var y: Int32
    var w: Int32
    var h: Int32
    def __init__(out self):
        self.x = Int32(0)
        self.y = Int32(0)
        self.w = Int32(0)
        self.h = Int32(0)

struct SDL_Surface(Copyable, Movable):
    var flags: UInt32
    var c_format: UInt32
    var w: Int32
    var h: Int32
    var pitch: Int32
    var pixels: UInt64
    var refcount: Int32
    var reserved: UInt64
    def __init__(out self):
        self.flags = UInt32(0)
        self.c_format = UInt32(0)
        self.w = Int32(0)
        self.h = Int32(0)
        self.pitch = Int32(0)
        self.pixels = UInt64(0)
        self.refcount = Int32(0)
        self.reserved = UInt64(0)

struct Draw(Copyable, Movable):
    var mesh: Int32
    var texture: Int32
    var next_mesh: Int32
    var target_mesh: Int32
    var target_next_mesh: Int32
    var c_object: Object
    var instance_first: UInt32
    var instance_count: UInt32
    def __init__(out self):
        self.mesh = Int32(0)
        self.texture = Int32(0)
        self.next_mesh = Int32(0)
        self.target_mesh = Int32(0)
        self.target_next_mesh = Int32(0)
        self.c_object = Object()
        self.instance_first=0
        self.instance_count=1

struct VkViewport(Copyable, Movable):
    var x: Float32
    var y: Float32
    var width: Float32
    var height: Float32
    var minDepth: Float32
    var maxDepth: Float32
    def __init__(out self):
        self.x = Float32(0)
        self.y = Float32(0)
        self.width = Float32(0)
        self.height = Float32(0)
        self.minDepth = Float32(0)
        self.maxDepth = Float32(0)

struct VkOffset2D(Copyable, Movable):
    var x: Int32
    var y: Int32
    def __init__(out self):
        self.x = Int32(0)
        self.y = Int32(0)

struct VkExtent2D(Copyable, Movable):
    var width: UInt32
    var height: UInt32
    def __init__(out self):
        self.width = UInt32(0)
        self.height = UInt32(0)

struct VkRect2D(Copyable, Movable):
    var offset: VkOffset2D
    var extent: VkExtent2D
    def __init__(out self):
        self.offset = VkOffset2D()
        self.extent = VkExtent2D()

struct VkClearValue(Copyable, Movable):
    var storage: Array[UInt32, 4]
    def __init__(out self):
        self.storage = Array[UInt32, 4](fill=0)

struct VkRenderPassBeginInfo(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var renderPass: UInt64
    var framebuffer: UInt64
    var renderArea: VkRect2D
    var clearValueCount: UInt32
    var pClearValues: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.renderPass = UInt64(0)
        self.framebuffer = UInt64(0)
        self.renderArea = VkRect2D()
        self.clearValueCount = UInt32(0)
        self.pClearValues = UInt64(0)

struct VkImageCopy(Copyable, Movable):
    var srcSubresource: VkImageSubresourceLayers
    var srcOffset: VkOffset3D
    var dstSubresource: VkImageSubresourceLayers
    var dstOffset: VkOffset3D
    var extent: VkExtent3D
    def __init__(out self):
        self.srcSubresource = VkImageSubresourceLayers()
        self.srcOffset = VkOffset3D()
        self.dstSubresource = VkImageSubresourceLayers()
        self.dstOffset = VkOffset3D()
        self.extent = VkExtent3D()

struct VkSurfaceCapabilitiesKHR(Copyable, Movable):
    var minImageCount: UInt32
    var maxImageCount: UInt32
    var currentExtent: VkExtent2D
    var minImageExtent: VkExtent2D
    var maxImageExtent: VkExtent2D
    var maxImageArrayLayers: UInt32
    var supportedTransforms: UInt32
    var currentTransform: Int32
    var supportedCompositeAlpha: UInt32
    var supportedUsageFlags: UInt32
    def __init__(out self):
        self.minImageCount = UInt32(0)
        self.maxImageCount = UInt32(0)
        self.currentExtent = VkExtent2D()
        self.minImageExtent = VkExtent2D()
        self.maxImageExtent = VkExtent2D()
        self.maxImageArrayLayers = UInt32(0)
        self.supportedTransforms = UInt32(0)
        self.currentTransform = Int32(0)
        self.supportedCompositeAlpha = UInt32(0)
        self.supportedUsageFlags = UInt32(0)

struct VkSurfaceFormatKHR(Copyable, Movable):
    var c_format: Int32
    var colorSpace: Int32
    def __init__(out self):
        self.c_format = Int32(0)
        self.colorSpace = Int32(0)

struct VkSwapchainCreateInfoKHR(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var flags: UInt32
    var surface: UInt64
    var minImageCount: UInt32
    var imageFormat: Int32
    var imageColorSpace: Int32
    var imageExtent: VkExtent2D
    var imageArrayLayers: UInt32
    var imageUsage: UInt32
    var imageSharingMode: Int32
    var queueFamilyIndexCount: UInt32
    var pQueueFamilyIndices: UInt64
    var preTransform: Int32
    var compositeAlpha: Int32
    var presentMode: Int32
    var clipped: UInt32
    var oldSwapchain: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.flags = UInt32(0)
        self.surface = UInt64(0)
        self.minImageCount = UInt32(0)
        self.imageFormat = Int32(0)
        self.imageColorSpace = Int32(0)
        self.imageExtent = VkExtent2D()
        self.imageArrayLayers = UInt32(0)
        self.imageUsage = UInt32(0)
        self.imageSharingMode = Int32(0)
        self.queueFamilyIndexCount = UInt32(0)
        self.pQueueFamilyIndices = UInt64(0)
        self.preTransform = Int32(0)
        self.compositeAlpha = Int32(0)
        self.presentMode = Int32(0)
        self.clipped = UInt32(0)
        self.oldSwapchain = UInt64(0)

struct VkBufferMemoryBarrier(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var srcAccessMask: UInt32
    var dstAccessMask: UInt32
    var srcQueueFamilyIndex: UInt32
    var dstQueueFamilyIndex: UInt32
    var buffer: UInt64
    var offset: UInt64
    var size: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.srcAccessMask = UInt32(0)
        self.dstAccessMask = UInt32(0)
        self.srcQueueFamilyIndex = UInt32(0)
        self.dstQueueFamilyIndex = UInt32(0)
        self.buffer = UInt64(0)
        self.offset = UInt64(0)
        self.size = UInt64(0)

struct VkPresentInfoKHR(Copyable, Movable):
    var sType: Int32
    var pNext: UInt64
    var waitSemaphoreCount: UInt32
    var pWaitSemaphores: UInt64
    var swapchainCount: UInt32
    var pSwapchains: UInt64
    var pImageIndices: UInt64
    var pResults: UInt64
    def __init__(out self):
        self.sType = Int32(0)
        self.pNext = UInt64(0)
        self.waitSemaphoreCount = UInt32(0)
        self.pWaitSemaphores = UInt64(0)
        self.swapchainCount = UInt32(0)
        self.pSwapchains = UInt64(0)
        self.pImageIndices = UInt64(0)
        self.pResults = UInt64(0)

struct SDL_DisplayMode(Copyable, Movable):
    var displayID: UInt32
    var c_format: UInt32
    var w: Int32
    var h: Int32
    var pixel_density: Float32
    var refresh_rate: Float32
    var refresh_rate_numerator: Int32
    var refresh_rate_denominator: Int32
    var internal: UInt64
    def __init__(out self):
        self.displayID = UInt32(0)
        self.c_format = UInt32(0)
        self.w = Int32(0)
        self.h = Int32(0)
        self.pixel_density = Float32(0)
        self.refresh_rate = Float32(0)
        self.refresh_rate_numerator = Int32(0)
        self.refresh_rate_denominator = Int32(0)
        self.internal = UInt64(0)

struct SDL_AudioSpec(Copyable, Movable):
    var c_format: Int32
    var channels: Int32
    var freq: Int32
    def __init__(out self):
        self.c_format = Int32(0)
        self.channels = Int32(0)
        self.freq = Int32(0)

struct SDL_KeyboardEvent(Copyable, Movable):
    var c_type: UInt32
    var reserved: UInt32
    var timestamp: UInt64
    var windowID: UInt32
    var which: UInt32
    var scancode: Int32
    var key: UInt32
    var mod: UInt16
    var raw: UInt16
    var down: Bool
    var repeat: Bool
    def __init__(out self):
        self.c_type = UInt32(0)
        self.reserved = UInt32(0)
        self.timestamp = UInt64(0)
        self.windowID = UInt32(0)
        self.which = UInt32(0)
        self.scancode = Int32(0)
        self.key = UInt32(0)
        self.mod = UInt16(0)
        self.raw = UInt16(0)
        self.down = Bool(0)
        self.repeat = Bool(0)

struct SDL_Event(Copyable, Movable):
    var storage: Array[UInt64, 16]
    def __init__(out self):
        self.storage = Array[UInt64, 16](fill=0)

struct timeval(Copyable, Movable):
    var tv_sec: Int64
    var tv_usec: Int64
    def __init__(out self):
        self.tv_sec = Int64(0)
        self.tv_usec = Int64(0)

struct rusage(Copyable, Movable):
    var ru_utime: timeval
    var ru_stime: timeval
    var ru_maxrss: Int64
    var ru_ixrss: Int64
    var ru_idrss: Int64
    var ru_isrss: Int64
    var ru_minflt: Int64
    var ru_majflt: Int64
    var ru_nswap: Int64
    var ru_inblock: Int64
    var ru_oublock: Int64
    var ru_msgsnd: Int64
    var ru_msgrcv: Int64
    var ru_nsignals: Int64
    var ru_nvcsw: Int64
    var ru_nivcsw: Int64
    def __init__(out self):
        self.ru_utime = timeval()
        self.ru_stime = timeval()
        self.ru_maxrss = Int64(0)
        self.ru_ixrss = Int64(0)
        self.ru_idrss = Int64(0)
        self.ru_isrss = Int64(0)
        self.ru_minflt = Int64(0)
        self.ru_majflt = Int64(0)
        self.ru_nswap = Int64(0)
        self.ru_inblock = Int64(0)
        self.ru_oublock = Int64(0)
        self.ru_msgsnd = Int64(0)
        self.ru_msgrcv = Int64(0)
        self.ru_nsignals = Int64(0)
        self.ru_nvcsw = Int64(0)
        self.ru_nivcsw = Int64(0)


# Engine-private renderer state; the public mg_* function signatures stay stable.
@fieldwise_init
struct PoolRange(Copyable,Movable):
    var page: Int32
    var offset: UInt64
    var size: UInt64

@fieldwise_init
struct RetiredRange(Copyable,Movable):
    var range: PoolRange
    var serial: UInt64

@fieldwise_init
struct UploadCopy(Copyable,Movable):
    var destination: UInt64
    var destination_offset: UInt64
    var source_offset: UInt64
    var size: UInt64

struct UploadSlot(Copyable,Movable):
    var staging: Buffer
    var command: UInt64
    var fence: UInt64
    var serial: UInt64
    var submitted: Int32
    var head: UInt64
    var copies: Array[UploadCopy,1024]
    var count: Int32

struct FrameSlot(Copyable,Movable):
    var command: UInt64
    var fence: UInt64
    var timestamps: UInt64
    var acquired: UInt64
    var serial: UInt64
    var query_ready: Int32
    var render_id: UInt64

struct Scalability(Copyable,Movable):
    var pages: Array[Buffer,64]
    var page_count: Int32
    var ranges: Array[PoolRange,16384]
    var range_count: Int32
    var retired: Array[RetiredRange,8192]
    var retired_count: Int32
    var pool_enabled: Int32
    var device_uploads: Int32
    var staging: Buffer
    var instance_buffer: Buffer
    var instances: Array[Array[Float32,16],65536]
    var instance_count: UInt32
    var uploads: Array[UploadSlot,2]
    var upload_slot: Int32
    var submit_serial: UInt64
    var completed_serial: UInt64
    var frame_serial: UInt64
    var upload_wait_ms: Float64
    var upload_batches: UInt64
    var upload_copies: UInt64
    var upload_bytes: UInt64
    var frames: Array[FrameSlot,2]
    var frame_count: Int32
    var frame_index: Int32
    var frames_initialized: Int32
    var frame_prepared: Int32
    var uniform_stride: UInt64
    var instance_stride: UInt64
    var overlay_stride: UInt64
    var frame_sequence: UInt64
    var gpu_frame: UInt64
    var presentation_active: Int32
    var presentation_index: UInt32
    var skin_buffer: Buffer
    var skin_cpu: UInt64
    var skin_count: UInt32
    var texture_alive: Array[Int32,257]
    var texture_generations: Array[UInt32,257]
    var texture_last_used: Array[UInt64,257]
    var normal_source: Array[Int32,257]
    var orm_source: Array[Int32,257]
    var texture_samplers: Array[UInt64,257]
    var texture_alpha: Array[Int32,257]
    var texture_cutoff: Array[Float32,257]
    var color_cpu: Array[UInt64,4096]
    var tangent_cpu: Array[UInt64,4096]
    var attribute_counts: Array[UInt32,4096]
    var attribute_bytes: UInt64
    var uniform_slice_stride: UInt64
    var uniform_slice: Int32
    var cascade_count: Int32
    var cascade_matrices: Array[Array[Float32,16],4]
    var cascade_splits: Array[Float32,4]
    var cascade_forward: Array[Float32,4]
    var cascade_eye: Array[Float32,4]
    var hdr_enabled: Int32
    var hdr_color: Image
    var hdr_multisample: Image
    var hdr_fb: UInt64
    var display_fb: UInt64
    var hdr_pass: UInt64
    var hdr_water_pass: UInt64
    var display_pass: UInt64
    var hdr_pipeline: UInt64
    var display_pipeline: UInt64
    var display_overlay: UInt64
    var environment: Array[Array[Float32,4],9]
    var environment_enabled: Float32
    var local_lights: Array[Array[Float32,12],32]
    var local_light_count: Int32

# Private GPU block extends the stable public Frame prefix (448 bytes).
@fieldwise_init
struct CascadeUniform(Copyable,Movable):
    var frame: Frame
    var lights: Array[Array[Float32,16],4]
    var splits: Array[Float32,4]
    var forward: Array[Float32,4]
    var eye: Array[Float32,4]
    var policy: Array[Float32,4]
    var environment: Array[Array[Float32,4],9]
    var local_lights: Array[Array[Float32,12],32]

@fieldwise_init
struct VkBufferCopy(Copyable,Movable):
    var srcOffset: UInt64
    var dstOffset: UInt64
    var size: UInt64

@fieldwise_init
struct VkMemoryBarrier(Copyable,Movable):
    var sType: Int32
    var pNext: UInt64
    var srcAccessMask: UInt32
    var dstAccessMask: UInt32
