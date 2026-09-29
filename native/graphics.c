/* Vulkan 1.1 renderer. Main-thread API, one synchronous frame in flight.
 * Both headless and windowed modes render the same offscreen attachments.
 * Windowed presentation blits that image into an SDL Vulkan swapchain. */
#include "shaders.h"
#include <SDL2/SDL.h>
#include <SDL2/SDL_vulkan.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#define MAX_MESHES 4096
#define MAX_TEXTURES 256
#define SHADOW_SIZE 4096

typedef struct {
  VkBuffer buffer;
  VkDeviceMemory memory;
  VkDeviceSize size;
} Buffer;
typedef struct {
  VkImage image;
  VkDeviceMemory memory;
  VkImageView view;
  uint32_t levels;
} Image;
typedef struct {
  Buffer vertices, indices;
  uint32_t count, generation;
  uint64_t topology;
} Mesh;
typedef struct {
  Image image;
  VkDescriptorSet set;
  int normal;
} Texture;
typedef struct {
  float model[16], color[4], params[4], pose[4];
} Object;
typedef struct {
  int mesh, texture, next_mesh;
  Object object;
} Draw;
typedef struct {
  float vp[16], light[16], sun_fog[4];
  float sky[4], ground[4], sun_color[4], haze[4];
} Frame;
typedef struct Graphics {
  SDL_Window *window;
  uint32_t sdl_flags;
  VkInstance instance;
  VkDebugUtilsMessengerEXT debug;
  VkPhysicalDevice physical;
  VkDevice device;
  VkPhysicalDeviceMemoryProperties memory;
  VkSurfaceKHR surface;
  VkQueue queue;
  uint32_t family;
  VkCommandPool pool;
  VkCommandBuffer command;
  VkFence fence;
  VkSemaphore acquired;
  VkSemaphore *present_done;
  VkSwapchainKHR swapchain;
  VkImage *swap_images;
  uint32_t swap_count, swap_width, swap_height;
  VkRenderPass shadow_pass, color_pass;
  VkFramebuffer shadow_fb, color_fb;
  Image shadow, color, depth;
  VkSampler shadow_sampler, texture_sampler;
  float anisotropy, ui_scale;
  VkDescriptorSetLayout set_layout;
  VkDescriptorPool descriptors;
  VkPipelineLayout pipeline_layout;
  VkPipeline world_pipeline, shadow_pipeline, overlay_pipeline;
  Buffer uniform, overlay_buffer, readback;
  Texture textures[MAX_TEXTURES + 1];
  uint32_t texture_count;
  int font_texture;
  Mesh meshes[MAX_MESHES];
  Draw *shadow_draws, *color_draws;
  size_t shadow_count, color_count, shadow_capacity, color_capacity;
  float *quads;
  size_t quad_count, quad_capacity;
  Frame frame;
  int width, height, target_width, target_height, rendered, frame_started,
      triangles;
  int validation_errors, validation_enabled;
  char driver[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE];
} Graphics;
static char error_text[4096];
const char *mg_error(void) { return error_text; }
static int fail(const char *message) {
  snprintf(error_text, sizeof(error_text), "%s", message);
  return -1;
}
static int result(VkResult r, const char *operation) {
  if (r == VK_SUCCESS)
    return 0;
  snprintf(error_text, sizeof(error_text), "%s: VkResult %d", operation, r);
  return -1;
}
#define TRY(call)                                                              \
  do {                                                                         \
    if (result((call), #call) < 0)                                             \
      return -1;                                                               \
  } while (0)
static VKAPI_ATTR VkBool32 VKAPI_CALL
debug_message(VkDebugUtilsMessageSeverityFlagBitsEXT severity,
              VkDebugUtilsMessageTypeFlagsEXT type,
              const VkDebugUtilsMessengerCallbackDataEXT *data, void *user) {
  (void)type;
  Graphics *g = user;
  if (severity & VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT)
    g->validation_errors++;
  fprintf(stderr, "Vulkan validation: %s\n", data->pMessage);
  return VK_FALSE;
}
static int memory_type(Graphics *g, uint32_t bits,
                       VkMemoryPropertyFlags properties, uint32_t *index) {
  for (uint32_t i = 0; i < g->memory.memoryTypeCount; i++)
    if ((bits & (1u << i)) &&
        (g->memory.memoryTypes[i].propertyFlags & properties) == properties) {
      *index = i;
      return 0;
    }
  return fail("No compatible Vulkan memory type");
}
static void buffer_drop(Graphics *g, Buffer *b) {
  if (b->buffer)
    vkDestroyBuffer(g->device, b->buffer, NULL);
  if (b->memory)
    vkFreeMemory(g->device, b->memory, NULL);
  memset(b, 0, sizeof(*b));
}
static int buffer_make(Graphics *g, Buffer *b, VkDeviceSize size,
                       VkBufferUsageFlags usage) {
  VkBufferCreateInfo info = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                             .size = size,
                             .usage = usage,
                             .sharingMode = VK_SHARING_MODE_EXCLUSIVE};
  TRY(vkCreateBuffer(g->device, &info, NULL, &b->buffer));
  VkMemoryRequirements req;
  vkGetBufferMemoryRequirements(g->device, b->buffer, &req);
  uint32_t type;
  if (memory_type(g, req.memoryTypeBits,
                  VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                      VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                  &type) < 0)
    return -1;
  VkMemoryAllocateInfo allocation = {.sType =
                                         VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                                     .allocationSize = req.size,
                                     .memoryTypeIndex = type};
  TRY(vkAllocateMemory(g->device, &allocation, NULL, &b->memory));
  TRY(vkBindBufferMemory(g->device, b->buffer, b->memory, 0));
  b->size = size;
  return 0;
}
static int buffer_write(Graphics *g, Buffer *b, const void *data, size_t size) {
  if (size > b->size)
    return fail("Buffer write exceeds capacity");
  void *mapped;
  TRY(vkMapMemory(g->device, b->memory, 0, size, 0, &mapped));
  memcpy(mapped, data, size);
  vkUnmapMemory(g->device, b->memory);
  return 0;
}
static void image_drop(Graphics *g, Image *i) {
  if (i->view)
    vkDestroyImageView(g->device, i->view, NULL);
  if (i->image)
    vkDestroyImage(g->device, i->image, NULL);
  if (i->memory)
    vkFreeMemory(g->device, i->memory, NULL);
  memset(i, 0, sizeof(*i));
}
static int image_make(Graphics *g, Image *image, uint32_t w, uint32_t h,
                      uint32_t levels, VkFormat format, VkImageUsageFlags usage,
                      VkImageAspectFlags aspect) {
  image->levels = levels;
  VkImageCreateInfo info = {.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
                            .imageType = VK_IMAGE_TYPE_2D,
                            .format = format,
                            .extent = {w, h, 1},
                            .mipLevels = levels,
                            .arrayLayers = 1,
                            .samples = VK_SAMPLE_COUNT_1_BIT,
                            .tiling = VK_IMAGE_TILING_OPTIMAL,
                            .usage = usage,
                            .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
                            .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED};
  TRY(vkCreateImage(g->device, &info, NULL, &image->image));
  VkMemoryRequirements req;
  vkGetImageMemoryRequirements(g->device, image->image, &req);
  uint32_t type;
  if (memory_type(g, req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                  &type) < 0)
    return -1;
  VkMemoryAllocateInfo allocation = {.sType =
                                         VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                                     .allocationSize = req.size,
                                     .memoryTypeIndex = type};
  TRY(vkAllocateMemory(g->device, &allocation, NULL, &image->memory));
  TRY(vkBindImageMemory(g->device, image->image, image->memory, 0));
  VkImageViewCreateInfo view = {.sType =
                                    VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                                .image = image->image,
                                .viewType = VK_IMAGE_VIEW_TYPE_2D,
                                .format = format,
                                .subresourceRange = {aspect, 0, levels, 0, 1}};
  TRY(vkCreateImageView(g->device, &view, NULL, &image->view));
  return 0;
}
static void barrier(Graphics *g, VkImage image, VkImageAspectFlags aspect,
                    uint32_t level, uint32_t count, VkImageLayout old,
                    VkImageLayout next, VkPipelineStageFlags src,
                    VkPipelineStageFlags dst, VkAccessFlags read,
                    VkAccessFlags write) {
  VkImageMemoryBarrier b = {.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                            .srcAccessMask = read,
                            .dstAccessMask = write,
                            .oldLayout = old,
                            .newLayout = next,
                            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                            .image = image,
                            .subresourceRange = {aspect, level, count, 0, 1}};
  vkCmdPipelineBarrier(g->command, src, dst, 0, 0, NULL, 0, NULL, 1, &b);
}
static int command_begin(Graphics *g) {
  TRY(vkWaitForFences(g->device, 1, &g->fence, VK_TRUE, UINT64_MAX));
  TRY(vkResetCommandBuffer(g->command, 0));
  VkCommandBufferBeginInfo begin = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
  TRY(vkBeginCommandBuffer(g->command, &begin));
  return 0;
}
static int command_submit(Graphics *g, VkSemaphore wait, VkSemaphore signal) {
  TRY(vkEndCommandBuffer(g->command));
  VkPipelineStageFlags stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
  VkSubmitInfo submit = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                         .waitSemaphoreCount = wait ? 1 : 0,
                         .pWaitSemaphores = wait ? &wait : NULL,
                         .pWaitDstStageMask = wait ? &stage : NULL,
                         .commandBufferCount = 1,
                         .pCommandBuffers = &g->command,
                         .signalSemaphoreCount = signal ? 1 : 0,
                         .pSignalSemaphores = signal ? &signal : NULL};
  TRY(vkResetFences(g->device, 1, &g->fence));
  VkResult status = vkQueueSubmit(g->queue, 1, &submit, g->fence);
  if (status != VK_SUCCESS) {
    /* Keep teardown and later calls from waiting forever on an unsignaled
     * fence. */
    vkDestroyFence(g->device, g->fence, NULL);
    g->fence = VK_NULL_HANDLE;
    VkFenceCreateInfo info = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                              .flags = VK_FENCE_CREATE_SIGNALED_BIT};
    (void)vkCreateFence(g->device, &info, NULL, &g->fence);
    return result(status, "vkQueueSubmit");
  }
  TRY(vkWaitForFences(g->device, 1, &g->fence, VK_TRUE, UINT64_MAX));
  return 0;
}
static int passes_make(Graphics *g) {
  VkAttachmentDescription depth = {
      .format = VK_FORMAT_D32_SFLOAT,
      .samples = VK_SAMPLE_COUNT_1_BIT,
      .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
      .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
      .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
      .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
      .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
      .finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL};
  VkAttachmentReference dr = {0,
                              VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};
  VkSubpassDescription sub = {.pipelineBindPoint =
                                  VK_PIPELINE_BIND_POINT_GRAPHICS,
                              .pDepthStencilAttachment = &dr};
  VkSubpassDependency deps[2] = {
      {.srcSubpass = VK_SUBPASS_EXTERNAL,
       .dstSubpass = 0,
       .srcStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
       .dstStageMask = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT |
                       VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
       .srcAccessMask = VK_ACCESS_SHADER_READ_BIT,
       .dstAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT},
      {.srcSubpass = 0,
       .dstSubpass = VK_SUBPASS_EXTERNAL,
       .srcStageMask = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT |
                       VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
       .dstStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
       .srcAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
       .dstAccessMask = VK_ACCESS_SHADER_READ_BIT}};
  VkRenderPassCreateInfo info = {.sType =
                                     VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
                                 .attachmentCount = 1,
                                 .pAttachments = &depth,
                                 .subpassCount = 1,
                                 .pSubpasses = &sub,
                                 .dependencyCount = 2,
                                 .pDependencies = deps};
  TRY(vkCreateRenderPass(g->device, &info, NULL, &g->shadow_pass));
  VkAttachmentDescription attachments[2] = {
      {.format = VK_FORMAT_R8G8B8A8_UNORM,
       .samples = VK_SAMPLE_COUNT_1_BIT,
       .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
       .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
       .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
       .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
       .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
       .finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL},
      depth};
  attachments[1].finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
  attachments[1].storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
  VkAttachmentReference cr = {0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
  dr.attachment = 1;
  sub.colorAttachmentCount = 1;
  sub.pColorAttachments = &cr;
  deps[0] = (VkSubpassDependency){
      .srcSubpass = VK_SUBPASS_EXTERNAL,
      .dstSubpass = 0,
      .srcStageMask = VK_PIPELINE_STAGE_TRANSFER_BIT |
                      VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
      .dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                      VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
      .srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT |
                       VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
      .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT |
                       VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT};
  deps[1] = (VkSubpassDependency){
      .srcSubpass = 0,
      .dstSubpass = VK_SUBPASS_EXTERNAL,
      .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      .dstStageMask = VK_PIPELINE_STAGE_TRANSFER_BIT,
      .srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
      .dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT};
  info.attachmentCount = 2;
  info.pAttachments = attachments;
  TRY(vkCreateRenderPass(g->device, &info, NULL, &g->color_pass));
  return 0;
}
static int pipeline_make(Graphics *g, VkPipeline *pipeline, int kind,
                         const uint32_t *vs, size_t vs_size, const uint32_t *fs,
                         size_t fs_size) {
  VkShaderModule v = VK_NULL_HANDLE, f = VK_NULL_HANDLE;
  VkShaderModuleCreateInfo module = {
      .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = vs_size,
      .pCode = vs};
  TRY(vkCreateShaderModule(g->device, &module, NULL, &v));
  module.codeSize = fs_size;
  module.pCode = fs;
  if (result(vkCreateShaderModule(g->device, &module, NULL, &f),
             "fragment shader module") < 0) {
    vkDestroyShaderModule(g->device, v, NULL);
    return -1;
  }
  VkPipelineShaderStageCreateInfo stages[2] = {
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = VK_SHADER_STAGE_VERTEX_BIT,
       .module = v,
       .pName = "main"},
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
       .module = f,
       .pName = "main"}};
  VkVertexInputBindingDescription bindings[2] = {
      {0, 32, VK_VERTEX_INPUT_RATE_VERTEX},
      {1, 32, VK_VERTEX_INPUT_RATE_VERTEX}};
  VkVertexInputAttributeDescription attributes[5] = {
      {0, 0, VK_FORMAT_R32G32B32_SFLOAT, 0},
      {1, 0, VK_FORMAT_R32G32B32_SFLOAT, 12},
      {2, 0, VK_FORMAT_R32G32_SFLOAT, 24},
      {3, 1, VK_FORMAT_R32G32B32_SFLOAT, 0},
      {4, 1, VK_FORMAT_R32G32B32_SFLOAT, 12}};
  if (kind == 2) {
    attributes[0].format = VK_FORMAT_R32G32_SFLOAT;
    attributes[1].format = VK_FORMAT_R32G32B32A32_SFLOAT;
    attributes[1].offset = 8;
    attributes[2].offset = 24;
  }
  if (kind == 1) { attributes[1] = attributes[2]; attributes[2] = attributes[3]; }
  VkPipelineVertexInputStateCreateInfo vertex = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
      .vertexBindingDescriptionCount = kind == 2 ? 1 : 2,
      .pVertexBindingDescriptions = bindings,
      .vertexAttributeDescriptionCount = kind == 0 ? 5 : 3,
      .pVertexAttributeDescriptions = attributes};
  VkPipelineInputAssemblyStateCreateInfo assembly = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
      .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST};
  VkPipelineViewportStateCreateInfo viewport = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
      .viewportCount = 1,
      .scissorCount = 1};
  VkPipelineRasterizationStateCreateInfo raster = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
      .polygonMode = VK_POLYGON_MODE_FILL,
      .cullMode = VK_CULL_MODE_NONE,
      .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE,
      .depthBiasEnable = kind == 1,
      .depthBiasConstantFactor = 4,
      .depthBiasSlopeFactor = 2,
      .lineWidth = 1};
  VkPipelineMultisampleStateCreateInfo samples = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
      .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT};
  VkPipelineDepthStencilStateCreateInfo depth = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
      .depthTestEnable = kind != 2,
      .depthWriteEnable = kind != 2,
      .depthCompareOp = VK_COMPARE_OP_LESS_OR_EQUAL,
      .maxDepthBounds = 1};
  VkPipelineColorBlendAttachmentState blend = {
      .blendEnable = kind == 2,
      .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
      .dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
      .colorBlendOp = VK_BLEND_OP_ADD,
      .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
      .dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
      .alphaBlendOp = VK_BLEND_OP_ADD,
      .colorWriteMask = 15};
  VkPipelineColorBlendStateCreateInfo blending = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
      .attachmentCount = kind == 1 ? 0 : 1,
      .pAttachments = &blend};
  VkDynamicState dynamics[2] = {VK_DYNAMIC_STATE_VIEWPORT,
                                VK_DYNAMIC_STATE_SCISSOR};
  VkPipelineDynamicStateCreateInfo dynamic = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
      .dynamicStateCount = 2,
      .pDynamicStates = dynamics};
  VkGraphicsPipelineCreateInfo info = {
      .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
      .stageCount = 2,
      .pStages = stages,
      .pVertexInputState = &vertex,
      .pInputAssemblyState = &assembly,
      .pViewportState = &viewport,
      .pRasterizationState = &raster,
      .pMultisampleState = &samples,
      .pDepthStencilState = &depth,
      .pColorBlendState = &blending,
      .pDynamicState = &dynamic,
      .layout = g->pipeline_layout,
      .renderPass = kind == 1 ? g->shadow_pass : g->color_pass};
  VkResult status = vkCreateGraphicsPipelines(g->device, VK_NULL_HANDLE, 1,
                                              &info, NULL, pipeline);
  vkDestroyShaderModule(g->device, v, NULL);
  vkDestroyShaderModule(g->device, f, NULL);
  return result(status, "graphics pipeline");
}
static int targets_make(Graphics *g) {
  if (g->target_width == g->width && g->target_height == g->height)
    return 0;
  TRY(vkDeviceWaitIdle(g->device));
  if (g->color_fb)
    vkDestroyFramebuffer(g->device, g->color_fb, NULL);
  g->color_fb = VK_NULL_HANDLE;
  image_drop(g, &g->color);
  image_drop(g, &g->depth);
  buffer_drop(g, &g->readback);
  g->target_width = g->target_height = 0;
  if (image_make(g, &g->color, g->width, g->height, 1, VK_FORMAT_R8G8B8A8_UNORM,
                 VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                     VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
                 VK_IMAGE_ASPECT_COLOR_BIT) < 0)
    return -1;
  if (image_make(g, &g->depth, g->width, g->height, 1, VK_FORMAT_D32_SFLOAT,
                 VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                 VK_IMAGE_ASPECT_DEPTH_BIT) < 0)
    return -1;
  VkImageView views[2] = {g->color.view, g->depth.view};
  VkFramebufferCreateInfo fb = {.sType =
                                    VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                                .renderPass = g->color_pass,
                                .attachmentCount = 2,
                                .pAttachments = views,
                                .width = g->width,
                                .height = g->height,
                                .layers = 1};
  TRY(vkCreateFramebuffer(g->device, &fb, NULL, &g->color_fb));
  if (buffer_make(g, &g->readback, (VkDeviceSize)g->width * g->height * 4,
                  VK_BUFFER_USAGE_TRANSFER_DST_BIT) < 0)
    return -1;
  g->target_width = g->width;
  g->target_height = g->height;
  return 0;
}
static int texture_make(Graphics *g, Texture *texture,
                        const unsigned char *pixels, uint32_t w, uint32_t h, int linear) {
  uint32_t levels = 1;
  VkFormat format = linear ? VK_FORMAT_R8G8B8A8_UNORM : VK_FORMAT_R8G8B8A8_SRGB;
  VkFormatProperties props;
  vkGetPhysicalDeviceFormatProperties(g->physical, format, &props);
  VkFormatFeatureFlags required =
      VK_FORMAT_FEATURE_BLIT_SRC_BIT | VK_FORMAT_FEATURE_BLIT_DST_BIT |
      VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT;
  if ((props.optimalTilingFeatures & required) == required)
    for (uint32_t size = w > h ? w : h; size > 1; size /= 2)
      levels++;
  Buffer staging = {0};
  int rc = -1;
  if (buffer_make(g, &staging, (VkDeviceSize)w * h * 4,
                  VK_BUFFER_USAGE_TRANSFER_SRC_BIT) < 0)
    goto done;
  if (buffer_write(g, &staging, pixels, (size_t)w * h * 4) < 0)
    goto done;
  if (image_make(g, &texture->image, w, h, levels, format,
                 VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                     VK_IMAGE_USAGE_TRANSFER_DST_BIT |
                     VK_IMAGE_USAGE_SAMPLED_BIT,
                 VK_IMAGE_ASPECT_COLOR_BIT) < 0)
    goto done;
  if (command_begin(g) < 0)
    goto done;
  barrier(g, texture->image.image, VK_IMAGE_ASPECT_COLOR_BIT, 0, levels,
          VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
          VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
          VK_ACCESS_TRANSFER_WRITE_BIT);
  VkBufferImageCopy copy = {
      .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
      .imageExtent = {w, h, 1}};
  vkCmdCopyBufferToImage(g->command, staging.buffer, texture->image.image,
                         VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
  int32_t mw = (int32_t)w, mh = (int32_t)h;
  for (uint32_t level = 1; level < levels; level++) {
    barrier(g, texture->image.image, VK_IMAGE_ASPECT_COLOR_BIT, level - 1, 1,
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
            VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT);
    int32_t nw = mw > 1 ? mw / 2 : 1, nh = mh > 1 ? mh / 2 : 1;
    VkImageBlit blit = {
        .srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level - 1, 0, 1},
        .srcOffsets = {{0, 0, 0}, {mw, mh, 1}},
        .dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level, 0, 1},
        .dstOffsets = {{0, 0, 0}, {nw, nh, 1}}};
    vkCmdBlitImage(g->command, texture->image.image,
                   VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, texture->image.image,
                   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit,
                   VK_FILTER_LINEAR);
    barrier(g, texture->image.image, VK_IMAGE_ASPECT_COLOR_BIT, level - 1, 1,
            VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            VK_PIPELINE_STAGE_TRANSFER_BIT,
            VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_ACCESS_TRANSFER_READ_BIT,
            VK_ACCESS_SHADER_READ_BIT);
    mw = nw;
    mh = nh;
  }
  barrier(g, texture->image.image, VK_IMAGE_ASPECT_COLOR_BIT, levels - 1, 1,
          VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
          VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
          VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
          VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT);
  if (command_submit(g, VK_NULL_HANDLE, VK_NULL_HANDLE) < 0)
    goto done;
  VkDescriptorSetAllocateInfo allocation = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
      .descriptorPool = g->descriptors,
      .descriptorSetCount = 1,
      .pSetLayouts = &g->set_layout};
  if (result(vkAllocateDescriptorSets(g->device, &allocation, &texture->set),
             "texture descriptor allocation") < 0)
    goto done;
  VkDescriptorBufferInfo uniform = {g->uniform.buffer, 0, sizeof(Frame)};
  VkDescriptorImageInfo shadow = {
      g->shadow_sampler, g->shadow.view,
      VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL};
  VkDescriptorImageInfo image = {g->texture_sampler, texture->image.view,
                                 VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
  VkWriteDescriptorSet writes[5] = {
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
       .dstSet = texture->set,
       .dstBinding = 0,
       .descriptorCount = 1,
       .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
       .pBufferInfo = &uniform},
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
       .dstSet = texture->set,
       .dstBinding = 1,
       .descriptorCount = 1,
       .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
       .pImageInfo = &shadow},
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
       .dstSet = texture->set,
       .dstBinding = 2,
       .descriptorCount = 1,
       .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
       .pImageInfo = &image},
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
       .dstSet = texture->set, .dstBinding = 3, .descriptorCount = 1,
       .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
       .pImageInfo = &image},
      {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
       .dstSet = texture->set, .dstBinding = 4, .descriptorCount = 1,
       .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
       .pImageInfo = &image}};
  vkUpdateDescriptorSets(g->device, 5, writes, 0, NULL);
  rc = 0;
done:
  buffer_drop(g, &staging);
  if (rc < 0)
    image_drop(g, &texture->image);
  return rc;
}
static int resources_make(Graphics *g) {
  VkDescriptorSetLayoutBinding bindings[5] = {
      {0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1,
       VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, NULL},
      {1, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1,
       VK_SHADER_STAGE_FRAGMENT_BIT, NULL},
      {2, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1,
       VK_SHADER_STAGE_FRAGMENT_BIT, NULL},
      {3, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1,
       VK_SHADER_STAGE_FRAGMENT_BIT, NULL},
      {4, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1,
       VK_SHADER_STAGE_FRAGMENT_BIT, NULL}};
  VkDescriptorSetLayoutCreateInfo layout = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount = 5,
      .pBindings = bindings};
  TRY(vkCreateDescriptorSetLayout(g->device, &layout, NULL, &g->set_layout));
  VkDescriptorPoolSize sizes[2] = {
      {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, MAX_TEXTURES + 1},
      {VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, (MAX_TEXTURES + 1) * 4}};
  VkDescriptorPoolCreateInfo pool = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
      .maxSets = MAX_TEXTURES + 1,
      .poolSizeCount = 2,
      .pPoolSizes = sizes};
  TRY(vkCreateDescriptorPool(g->device, &pool, NULL, &g->descriptors));
  VkPushConstantRange push = {VK_SHADER_STAGE_VERTEX_BIT |
                                  VK_SHADER_STAGE_FRAGMENT_BIT,
                              0, sizeof(Object)};
  VkPipelineLayoutCreateInfo pipeline = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .setLayoutCount = 1,
      .pSetLayouts = &g->set_layout,
      .pushConstantRangeCount = 1,
      .pPushConstantRanges = &push};
  TRY(vkCreatePipelineLayout(g->device, &pipeline, NULL, &g->pipeline_layout));
  if (buffer_make(g, &g->uniform, sizeof(Frame),
                  VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT) < 0)
    return -1;
  if (passes_make(g) < 0)
    return -1;
  if (image_make(g, &g->shadow, SHADOW_SIZE, SHADOW_SIZE, 1,
                 VK_FORMAT_D32_SFLOAT,
                 VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
                     VK_IMAGE_USAGE_SAMPLED_BIT,
                 VK_IMAGE_ASPECT_DEPTH_BIT) < 0)
    return -1;
  VkFramebufferCreateInfo fb = {.sType =
                                    VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                                .renderPass = g->shadow_pass,
                                .attachmentCount = 1,
                                .pAttachments = &g->shadow.view,
                                .width = SHADOW_SIZE,
                                .height = SHADOW_SIZE,
                                .layers = 1};
  TRY(vkCreateFramebuffer(g->device, &fb, NULL, &g->shadow_fb));
  VkSamplerCreateInfo sampler = {
      .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
      .magFilter = VK_FILTER_NEAREST,
      .minFilter = VK_FILTER_NEAREST,
      .mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST,
      .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
      .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
      .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
      .borderColor = VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE};
  TRY(vkCreateSampler(g->device, &sampler, NULL, &g->shadow_sampler));
  sampler.magFilter = sampler.minFilter = VK_FILTER_LINEAR;
  sampler.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
  sampler.addressModeU = sampler.addressModeV = sampler.addressModeW =
      VK_SAMPLER_ADDRESS_MODE_REPEAT;
  sampler.maxLod = VK_LOD_CLAMP_NONE;
  sampler.anisotropyEnable = g->anisotropy > 1;
  sampler.maxAnisotropy = g->anisotropy;
  TRY(vkCreateSampler(g->device, &sampler, NULL, &g->texture_sampler));
  if (pipeline_make(g, &g->world_pipeline, 0, world_vert, sizeof(world_vert),
                    world_frag, sizeof(world_frag)) < 0)
    return -1;
  if (pipeline_make(g, &g->shadow_pipeline, 1, shadow_vert, sizeof(shadow_vert),
                    shadow_frag, sizeof(shadow_frag)) < 0)
    return -1;
  if (pipeline_make(g, &g->overlay_pipeline, 2, overlay_vert,
                    sizeof(overlay_vert), overlay_frag,
                    sizeof(overlay_frag)) < 0)
    return -1;
  unsigned char white[4] = {255, 255, 255, 255};
  if (texture_make(g, &g->textures[0], white, 1, 1, 0) < 0)
    return -1;
  return targets_make(g);
}
static int instance_make(Graphics *g) {
  const char *extensions[32];
  unsigned count = 0;
  if (g->window) {
    if (!SDL_Vulkan_GetInstanceExtensions(g->window, &count, NULL))
      return fail(SDL_GetError());
    if (count > 30)
      return fail("Too many SDL Vulkan extensions");
    if (!SDL_Vulkan_GetInstanceExtensions(g->window, &count, extensions))
      return fail(SDL_GetError());
  }
  const char *validation = "VK_LAYER_KHRONOS_validation";
  const char *requested = getenv("MOJO_VK_VALIDATION");
  g->validation_enabled = requested && strcmp(requested, "0") != 0;
  if (g->validation_enabled)
    extensions[count++] = VK_EXT_DEBUG_UTILS_EXTENSION_NAME;
  VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                           .pApplicationName = "Atlas Mojo",
                           .applicationVersion = 1,
                           .pEngineName = "mojo_game",
                           .engineVersion = 1,
                           .apiVersion = VK_API_VERSION_1_1};
  VkDebugUtilsMessengerCreateInfoEXT debug = {
      .sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
      .messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                         VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
      .messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                     VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                     VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
      .pfnUserCallback = debug_message,
      .pUserData = g};
  VkInstanceCreateInfo info = {
      .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
      .pNext = g->validation_enabled ? &debug : NULL,
      .pApplicationInfo = &app,
      .enabledExtensionCount = count,
      .ppEnabledExtensionNames = extensions,
      .enabledLayerCount = g->validation_enabled ? 1 : 0,
      .ppEnabledLayerNames = g->validation_enabled ? &validation : NULL};
  TRY(vkCreateInstance(&info, NULL, &g->instance));
  if (g->validation_enabled) {
    PFN_vkCreateDebugUtilsMessengerEXT create =
        (PFN_vkCreateDebugUtilsMessengerEXT)vkGetInstanceProcAddr(
            g->instance, "vkCreateDebugUtilsMessengerEXT");
    if (!create)
      return fail("Vulkan debug messenger unavailable");
    TRY(create(g->instance, &debug, NULL, &g->debug));
  }
  if (g->window &&
      !SDL_Vulkan_CreateSurface(g->window, g->instance, &g->surface))
    return fail(SDL_GetError());
  return 0;
}
static int device_make(Graphics *g) {
  uint32_t count = 0;
  TRY(vkEnumeratePhysicalDevices(g->instance, &count, NULL));
  if (!count)
    return fail("No Vulkan device found; install a Vulkan ICD");
  VkPhysicalDevice *devices = calloc(count, sizeof(*devices));
  if (!devices)
    return fail("Device list allocation failed");
  VkResult enumeration =
      vkEnumeratePhysicalDevices(g->instance, &count, devices);
  if (result(enumeration, "enumerate devices") < 0) {
    free(devices);
    return -1;
  }
  int best = -1;
  for (uint32_t i = 0; i < count; i++) {
    VkPhysicalDeviceProperties properties;
    vkGetPhysicalDeviceProperties(devices[i], &properties);
    if (properties.apiVersion < VK_API_VERSION_1_1)
      continue;
    VkFormatProperties depth, color;
    vkGetPhysicalDeviceFormatProperties(devices[i], VK_FORMAT_D32_SFLOAT,
                                        &depth);
    vkGetPhysicalDeviceFormatProperties(devices[i], VK_FORMAT_R8G8B8A8_UNORM,
                                        &color);
    VkFormatFeatureFlags required =
        VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT |
        VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT;
    if ((depth.optimalTilingFeatures & required) != required ||
        !(color.optimalTilingFeatures & VK_FORMAT_FEATURE_BLIT_SRC_BIT))
      continue;
    uint32_t families = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &families, NULL);
    VkQueueFamilyProperties *queues = calloc(families, sizeof(*queues));
    if (!queues) {
      free(devices);
      return fail("Queue list allocation failed");
    }
    vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &families, queues);
    for (uint32_t q = 0; q < families; q++) {
      VkBool32 present = VK_TRUE;
      if (g->surface && vkGetPhysicalDeviceSurfaceSupportKHR(
                            devices[i], q, g->surface, &present) != VK_SUCCESS)
        present = VK_FALSE;
      if (!(queues[q].queueFlags & VK_QUEUE_GRAPHICS_BIT) || !present)
        continue;
      int score =
          properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU ? 100
          : properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
              ? 50
              : 10;
      if (score > best) {
        g->physical = devices[i];
        g->family = q;
        best = score;
        snprintf(g->driver, sizeof(g->driver), "%s", properties.deviceName);
      }
      break;
    }
    free(queues);
  }
  free(devices);
  if (!g->physical)
    return fail("No compatible Vulkan graphics/present queue or image format");
  float priority = 1;
  VkDeviceQueueCreateInfo queue = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex = g->family,
      .queueCount = 1,
      .pQueuePriorities = &priority};
  VkPhysicalDeviceFeatures supported, enabled = {0};
  VkPhysicalDeviceProperties properties;
  vkGetPhysicalDeviceFeatures(g->physical, &supported);
  vkGetPhysicalDeviceProperties(g->physical, &properties);
  enabled.samplerAnisotropy = supported.samplerAnisotropy;
  g->anisotropy = enabled.samplerAnisotropy ? (properties.limits.maxSamplerAnisotropy < 16.0f ? properties.limits.maxSamplerAnisotropy : 16.0f) : 1.0f;
  const char *swapchain = VK_KHR_SWAPCHAIN_EXTENSION_NAME;
  VkDeviceCreateInfo device = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                               .pEnabledFeatures = &enabled,
                               .queueCreateInfoCount = 1,
                               .pQueueCreateInfos = &queue,
                               .enabledExtensionCount = g->surface ? 1 : 0,
                               .ppEnabledExtensionNames =
                                   g->surface ? &swapchain : NULL};
  TRY(vkCreateDevice(g->physical, &device, NULL, &g->device));
  vkGetDeviceQueue(g->device, g->family, 0, &g->queue);
  vkGetPhysicalDeviceMemoryProperties(g->physical, &g->memory);
  VkCommandPoolCreateInfo pool = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
      .queueFamilyIndex = g->family};
  TRY(vkCreateCommandPool(g->device, &pool, NULL, &g->pool));
  VkCommandBufferAllocateInfo allocation = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool = g->pool,
      .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
      .commandBufferCount = 1};
  TRY(vkAllocateCommandBuffers(g->device, &allocation, &g->command));
  VkFenceCreateInfo fence = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                             .flags = VK_FENCE_CREATE_SIGNALED_BIT};
  TRY(vkCreateFence(g->device, &fence, NULL, &g->fence));
  VkSemaphoreCreateInfo semaphore = {
      .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
  TRY(vkCreateSemaphore(g->device, &semaphore, NULL, &g->acquired));
  return 0;
}
void mg_close(Graphics *g) {
  if (!g)
    return;
  if (g->device) {
    (void)vkDeviceWaitIdle(g->device);
    for (int i = 0; i < MAX_MESHES; i++) {
      buffer_drop(g, &g->meshes[i].vertices);
      buffer_drop(g, &g->meshes[i].indices);
    }
    for (int i = 0; i <= MAX_TEXTURES; i++)
      image_drop(g, &g->textures[i].image);
    buffer_drop(g, &g->uniform);
    buffer_drop(g, &g->overlay_buffer);
    buffer_drop(g, &g->readback);
    if (g->color_fb)
      vkDestroyFramebuffer(g->device, g->color_fb, NULL);
    if (g->shadow_fb)
      vkDestroyFramebuffer(g->device, g->shadow_fb, NULL);
    image_drop(g, &g->shadow);
    image_drop(g, &g->color);
    image_drop(g, &g->depth);
    if (g->world_pipeline)
      vkDestroyPipeline(g->device, g->world_pipeline, NULL);
    if (g->shadow_pipeline)
      vkDestroyPipeline(g->device, g->shadow_pipeline, NULL);
    if (g->overlay_pipeline)
      vkDestroyPipeline(g->device, g->overlay_pipeline, NULL);
    if (g->pipeline_layout)
      vkDestroyPipelineLayout(g->device, g->pipeline_layout, NULL);
    if (g->descriptors)
      vkDestroyDescriptorPool(g->device, g->descriptors, NULL);
    if (g->set_layout)
      vkDestroyDescriptorSetLayout(g->device, g->set_layout, NULL);
    if (g->shadow_sampler)
      vkDestroySampler(g->device, g->shadow_sampler, NULL);
    if (g->texture_sampler)
      vkDestroySampler(g->device, g->texture_sampler, NULL);
    if (g->color_pass)
      vkDestroyRenderPass(g->device, g->color_pass, NULL);
    if (g->shadow_pass)
      vkDestroyRenderPass(g->device, g->shadow_pass, NULL);
    if (g->swapchain)
      vkDestroySwapchainKHR(g->device, g->swapchain, NULL);
    if (g->acquired)
      vkDestroySemaphore(g->device, g->acquired, NULL);
    for (uint32_t i = 0; g->present_done && i < g->swap_count; i++)
      if (g->present_done[i])
        vkDestroySemaphore(g->device, g->present_done[i], NULL);
    if (g->fence)
      vkDestroyFence(g->device, g->fence, NULL);
    if (g->pool)
      vkDestroyCommandPool(g->device, g->pool, NULL);
    vkDestroyDevice(g->device, NULL);
  }
  if (g->surface)
    vkDestroySurfaceKHR(g->instance, g->surface, NULL);
  if (g->debug) {
    PFN_vkDestroyDebugUtilsMessengerEXT destroy =
        (PFN_vkDestroyDebugUtilsMessengerEXT)vkGetInstanceProcAddr(
            g->instance, "vkDestroyDebugUtilsMessengerEXT");
    if (destroy)
      destroy(g->instance, g->debug, NULL);
  }
  if (g->instance)
    vkDestroyInstance(g->instance, NULL);
  if (g->window)
    SDL_DestroyWindow(g->window);
  if (g->sdl_flags)
    SDL_QuitSubSystem(g->sdl_flags);
  free(g->swap_images);
  free(g->present_done);
  free(g->shadow_draws);
  free(g->color_draws);
  free(g->quads);
  free(g);
}
Graphics *mg_open_mode(const char *title, int width, int height, int hidden, int fullscreen) {
  if (width < 1 || height < 1 || width > 16384 || height > 16384) {
    fail("Invalid window dimensions");
    return NULL;
  }
  Graphics *g = calloc(1, sizeof(*g));
  if (!g) {
    fail("Graphics allocation failed");
    return NULL;
  }
  g->width = width;
  g->height = height;
  uint32_t flags =
      SDL_INIT_TIMER | SDL_INIT_EVENTS | (hidden ? 0 : SDL_INIT_VIDEO);
  if (SDL_InitSubSystem(flags) < 0) {
    fail(SDL_GetError());
    mg_close(g);
    return NULL;
  }
  g->sdl_flags = flags;
  g->font_texture = -1;
  if (!hidden) {
    g->window = SDL_CreateWindow(
        title, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, width, height,
        SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI |
        (fullscreen ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0));
    if (!g->window) {
      fail(SDL_GetError());
      mg_close(g);
      return NULL;
    }
    SDL_Vulkan_GetDrawableSize(g->window, &g->width, &g->height);
  }
  if (instance_make(g) < 0 || device_make(g) < 0 || resources_make(g) < 0) {
    mg_close(g);
    return NULL;
  }
  return g;
}
Graphics *mg_open(const char *title, int width, int height, int hidden) {
  return mg_open_mode(title, width, height, hidden, 0);
}
const char *mg_driver(Graphics *g) { return g->driver; }
int mg_width(Graphics *g) {
  if (g->window)
    SDL_Vulkan_GetDrawableSize(g->window, &g->width, &g->height);
  return g->width;
}
int mg_height(Graphics *g) {
  if (g->window)
    SDL_Vulkan_GetDrawableSize(g->window, &g->width, &g->height);
  return g->height;
}
uint32_t mg_mouse(Graphics *g, int32_t *x, int32_t *y) {
  if (!g->window) {
    *x = *y = 0;
    return 0;
  }
  int mx, my, w, h;
  uint32_t buttons = SDL_GetMouseState(&mx, &my);
  SDL_GetWindowSize(g->window, &w, &h);
  *x = w > 0 ? (int32_t)((int64_t)mx * g->width / w) : 0;
  *y = h > 0 ? (int32_t)((int64_t)my * g->height / h) : 0;
  return buttons;
}
static Mesh *mesh_at(Graphics *g, int id) {
  if (id < 0)
    return NULL;
  Mesh *m = &g->meshes[(unsigned)id & 4095];
  return m->count && m->generation == ((unsigned)id >> 12) ? m : NULL;
}
int mg_mesh(Graphics *g, const float *vertices, int floats,
            const uint32_t *indices, int count) {
  if (floats < 24 || floats % 8 || count < 3 || count % 3)
    return fail("Invalid mesh data");
  for (int i = 0; i < count; i++)
    if (indices[i] >= (unsigned)(floats / 8))
      return fail("Mesh index out of bounds");
  int slot = -1;
  for (int i = 0; i < MAX_MESHES; i++)
    if (!g->meshes[i].count && g->meshes[i].generation < 524287) {
      slot = i;
      break;
    }
  if (slot < 0)
    return fail("GPU mesh capacity exceeded");
  Mesh *m = &g->meshes[slot];
  if (buffer_make(g, &m->vertices, (VkDeviceSize)floats * 4,
                  VK_BUFFER_USAGE_VERTEX_BUFFER_BIT) < 0 ||
      buffer_make(g, &m->indices, (VkDeviceSize)count * 4,
                  VK_BUFFER_USAGE_INDEX_BUFFER_BIT) < 0 ||
      buffer_write(g, &m->vertices, vertices, (size_t)floats * 4) < 0 ||
      buffer_write(g, &m->indices, indices, (size_t)count * 4) < 0) {
    buffer_drop(g, &m->vertices);
    buffer_drop(g, &m->indices);
    return -1;
  }
  m->count = (uint32_t)count;
  m->topology = 1469598103934665603ULL;
  for (int i = 0; i < count; i++)
    m->topology = (m->topology ^ indices[i]) * 1099511628211ULL;
  return (int)(m->generation << 12) | slot;
}
int mg_release_mesh(Graphics *g, int id) {
  Mesh *m = mesh_at(g, id);
  if (!m)
    return fail("Stale mesh handle");
  /* Every submission completes synchronously; queued CPU draws validate
   * handles. */
  buffer_drop(g, &m->vertices);
  buffer_drop(g, &m->indices);
  m->count = 0;
  m->generation++;
  return 0;
}
int mg_texture_data(Graphics *g, const char *path, int linear) {
  if (g->texture_count == MAX_TEXTURES)
    return fail("Texture capacity exceeded");
  SDL_Surface *source = SDL_LoadBMP(path);
  if (!source)
    return fail(SDL_GetError());
  SDL_Surface *image =
      SDL_ConvertSurfaceFormat(source, SDL_PIXELFORMAT_ABGR8888, 0);
  SDL_FreeSurface(source);
  if (!image)
    return fail(SDL_GetError());
  int id = (int)g->texture_count;
  int rc = texture_make(g, &g->textures[id + 1], image->pixels,
                        (uint32_t)image->w, (uint32_t)image->h, linear);
  SDL_FreeSurface(image);
  if (rc < 0)
    return -1;
  g->texture_count++;
  return id;
}
int mg_texture(Graphics *g, const char *path) { return mg_texture_data(g, path, 0); }
int mg_normal_map(Graphics *g, int albedo, int normal) {
  if(albedo<0 || normal<0 || albedo>=(int)g->texture_count || normal>=(int)g->texture_count)
    return fail("Invalid normal-map texture handle");
  TRY(vkDeviceWaitIdle(g->device));
  VkDescriptorImageInfo image = {g->texture_sampler, g->textures[normal+1].image.view,
                                VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
  VkWriteDescriptorSet write = {.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    .dstSet=g->textures[albedo+1].set, .dstBinding=3, .descriptorCount=1,
    .descriptorType=VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo=&image};
  vkUpdateDescriptorSets(g->device,1,&write,0,NULL);
  g->textures[albedo+1].normal |= 1;
  return 0;
}
/* Packed linear R=occlusion, G=roughness, B=metallic. Bit 2 selects full
 * strength OpenGL normal maps; legacy materials retain their original scale. */
int mg_orm_map(Graphics *g, int albedo, int orm) {
  if(albedo<0 || orm<0 || albedo>=(int)g->texture_count || orm>=(int)g->texture_count)
    return fail("Invalid ORM texture handle");
  TRY(vkDeviceWaitIdle(g->device));
  VkDescriptorImageInfo image = {g->texture_sampler, g->textures[orm+1].image.view,
                                VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
  VkWriteDescriptorSet write = {.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
    .dstSet=g->textures[albedo+1].set, .dstBinding=4, .descriptorCount=1,
    .descriptorType=VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo=&image};
  vkUpdateDescriptorSets(g->device,1,&write,0,NULL);
  g->textures[albedo+1].normal |= 2;
  return 0;
}
static int append_draw(Draw **array, size_t *count, size_t *capacity,
                       Draw draw) {
  if (*count == *capacity) {
    size_t size = *capacity ? *capacity * 2 : 64;
    Draw *p = realloc(*array, size * sizeof(*p));
    if (!p)
      return fail("Draw queue allocation failed");
    *array = p;
    *capacity = size;
  }
  (*array)[(*count)++] = draw;
  return 0;
}
void mg_shadow_begin(Graphics *g, const float *light) {
  g->ui_scale = 1;
  memcpy(g->frame.light, light, 64);
  g->shadow_count = g->color_count = g->quad_count = 0;
  g->triangles = 0;
  g->rendered = 0;
  g->frame_started = 1;
}
int mg_shadow_material(Graphics *g, int id, const float *model, int texture) {
  if (!g->frame_started)
    return fail("shadow_begin must start the frame");
  if (!mesh_at(g, id))
    return fail("Stale shadow mesh handle");
  if(texture < -1 || texture >= (int)g->texture_count) return fail("Invalid shadow texture");
  Draw draw = {.mesh = id, .texture = texture, .next_mesh = id};
  draw.object.params[2] = texture >= 0;
  memcpy(draw.object.model, model, 64);
  g->rendered = 0;
  return append_draw(&g->shadow_draws, &g->shadow_count, &g->shadow_capacity,
                     draw);
}
int mg_shadow_draw(Graphics *g, int id, const float *model) {
  return mg_shadow_material(g,id,model,-1);
}
void mg_begin(Graphics *g, const float *vp, float sx, float sy, float sz,
              float fog) {
  memcpy(g->frame.vp, vp, 64);
  g->frame.sun_fog[0] = sx;
  g->frame.sun_fog[1] = sy;
  g->frame.sun_fog[2] = sz;
  g->frame.sun_fog[3] = fog;
  const float defaults[16] = {.22f,.29f,.36f,0, .08f,.09f,.12f,0,
                              3.4f,3.1f,2.7f,1, .42f,.57f,.72f,0};
  memcpy(g->frame.sky,defaults,sizeof(defaults));
  g->rendered = 0;
}
int mg_lighting(Graphics *g, const float *values) {
  for(int i=0;i<16;i++) if(!isfinite(values[i]) || values[i]<0)
    return fail("Invalid environment lighting");
  memcpy(g->frame.sky,values,16*sizeof(float));
  g->rendered=0;
  return 0;
}
int mg_draw(Graphics *g, int id, const float *model, float r, float green,
            float b, float rough, float metal, float emission, int texture) {
  Mesh *m = mesh_at(g, id);
  if (!m)
    return fail("Stale mesh handle");
  if (texture < -1 || texture >= (int)g->texture_count)
    return fail("Invalid texture handle");
  Draw draw = {.mesh = id,
               .next_mesh = id,
               .texture = texture,
               .object = {.color = {r, green, b, rough},
                          .params = {metal, emission, texture >= 0, g->textures[texture+1].normal}}};
  memcpy(draw.object.model, model, 64);
  if (append_draw(&g->color_draws, &g->color_count, &g->color_capacity, draw) <
      0)
    return -1;
  g->triangles += (int)(m->count / 3);
  g->rendered = 0;
  return 0;
}
int mg_can_morph(Graphics *g, int first, int next) {
  Mesh *a=mesh_at(g,first), *b=mesh_at(g,next);
  return a && b && a->count==b->count && a->vertices.size==b->vertices.size && a->topology==b->topology;
}
int mg_draw_morph(Graphics *g, int first, int next, float blend,
                  const float *model, float r, float green, float b,
                  float rough, float metal, float emission, int texture, int shadow) {
  if(!isfinite(blend) || blend<0 || blend>1 || !mg_can_morph(g,first,next))
    return fail("Incompatible morph meshes or blend");
  int result = shadow ? mg_shadow_material(g,first,model,texture) :
      mg_draw(g,first,model,r,green,b,rough,metal,emission,texture);
  if(result<0) return result;
  Draw *draw=shadow ? &g->shadow_draws[g->shadow_count-1] : &g->color_draws[g->color_count-1];
  draw->next_mesh=next;
  draw->object.pose[0]=blend;
  return 0;
}
void mg_ui_scale(Graphics *g, float scale) {
  if (scale >= 0.25f && scale <= 8.0f) g->ui_scale = scale;
}
static int ui_quad(Graphics *g, float x, float y, float w, float h, float r,
            float green, float b, float a, float u, float v, float du, float dv) {
  if (g->quad_count + 48 > g->quad_capacity) {
    size_t size = g->quad_capacity ? g->quad_capacity * 2 : 4096;
    float *p = realloc(g->quads, size * sizeof(float));
    if (!p)
      return fail("Overlay allocation failed");
    g->quads = p;
    g->quad_capacity = size;
  }
  float points[12] = {x, y, x + w, y,     x + w, y + h,
                      x, y, x + w, y + h, x,     y + h};
  float coords[12] = {u,v,u+du,v,u+du,v+dv,u,v,u+du,v+dv,u,v+dv};
  for (int i = 0; i < 6; i++) {
    float *p = g->quads + g->quad_count;
    p[0] = points[i * 2] * g->ui_scale;
    p[1] = points[i * 2 + 1] * g->ui_scale;
    p[2] = r;
    p[3] = green;
    p[4] = b;
    p[5] = a;
    p[6] = coords[i*2]; p[7] = coords[i*2+1];
    g->quad_count += 8;
  }
  g->rendered = 0;
  return 0;
}
int mg_rect(Graphics *g, float x, float y, float w, float h, float r,
            float green, float b, float a) {
  return ui_quad(g,x,y,w,h,r,green,b,a,-1,-1,0,0);
}
int mg_circle(Graphics *g,float x,float y,float radius,float r,float green,float b,float a) {
  return ui_quad(g,x-radius,y-radius,radius*2,radius*2,r,green,b,a,-3,0,1,1);
}
int mg_font(Graphics *g,int texture) {
  if(texture<0 || texture>=(int)g->texture_count) return fail("Invalid font atlas");
  g->font_texture=texture;
  return 0;
}
int mg_text(Graphics *g,const char *text,float x,float y,float r,float green,float b,int scale) {
  if(g->font_texture<0) return 0;
  if(scale<1) return fail("Invalid text scale");
  float left=x;
  for(const unsigned char *p=(const unsigned char *)text;*p;p++) {
    unsigned code=*p>=32 && *p<128 ? *p-32 : '?' - 32;
    if(*p=='\n'){ x=left; y+=11*scale; continue; }
    if(*p!=' ' && ui_quad(g,x-scale,y-2*scale,8*scale,11*scale,r,green,b,1,
                         (code%16)/16.0f,(code/16)/6.0f,1.0f/16,1.0f/6)<0) return -1;
    x+=6*scale;
  }
  return 1;
}
static void viewport(Graphics *g, uint32_t w, uint32_t h) {
  VkViewport v = {0, 0, (float)w, (float)h, 0, 1};
  VkRect2D scissor = {{0, 0}, {w, h}};
  vkCmdSetViewport(g->command, 0, 1, &v);
  vkCmdSetScissor(g->command, 0, 1, &scissor);
}
static void record_draw(Graphics *g, Draw *draw) {
  Mesh *m = mesh_at(g, draw->mesh);
  Mesh *next = mesh_at(g, draw->next_mesh);
  VkDeviceSize offsets[2] = {0,0};
  VkBuffer buffers[2] = {m->vertices.buffer,next->vertices.buffer};
  VkDescriptorSet set = g->textures[draw->texture + 1].set;
  vkCmdBindDescriptorSets(g->command, VK_PIPELINE_BIND_POINT_GRAPHICS,
                          g->pipeline_layout, 0, 1, &set, 0, NULL);
  vkCmdPushConstants(g->command, g->pipeline_layout,
                     VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                     0, sizeof(Object), &draw->object);
  vkCmdBindVertexBuffers(g->command, 0, 2, buffers, offsets);
  vkCmdBindIndexBuffer(g->command, m->indices.buffer, 0, VK_INDEX_TYPE_UINT32);
  vkCmdDrawIndexed(g->command, m->count, 1, 0, 0, 0);
}
static int render(Graphics *g) {
  if (g->rendered)
    return 0;
  if (!g->frame_started)
    return fail("shadow_begin must start each Vulkan frame");
  if (g->width < 1 || g->height < 1)
    return 0;
  for (size_t i = 0; i < g->shadow_count; i++)
    if (!mesh_at(g, g->shadow_draws[i].mesh) || !mesh_at(g, g->shadow_draws[i].next_mesh))
      return fail("Released mesh in shadow queue");
  for (size_t i = 0; i < g->color_count; i++)
    if (!mesh_at(g, g->color_draws[i].mesh) || !mesh_at(g, g->color_draws[i].next_mesh))
      return fail("Released mesh in draw queue");
  if (targets_make(g) < 0 ||
      buffer_write(g, &g->uniform, &g->frame, sizeof(Frame)) < 0)
    return -1;
  if (g->quad_count) {
    VkDeviceSize size = g->quad_count * sizeof(float);
    if (g->overlay_buffer.size < size) {
      buffer_drop(g, &g->overlay_buffer);
      if (buffer_make(g, &g->overlay_buffer, size,
                      VK_BUFFER_USAGE_VERTEX_BUFFER_BIT) < 0)
        return -1;
    }
    if (buffer_write(g, &g->overlay_buffer, g->quads, (size_t)size) < 0)
      return -1;
  }
  if (command_begin(g) < 0)
    return -1;
  VkClearValue depth = {.depthStencil = {1, 0}};
  VkRenderPassBeginInfo pass = {
      .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
      .renderPass = g->shadow_pass,
      .framebuffer = g->shadow_fb,
      .renderArea = {{0, 0}, {SHADOW_SIZE, SHADOW_SIZE}},
      .clearValueCount = 1,
      .pClearValues = &depth};
  vkCmdBeginRenderPass(g->command, &pass, VK_SUBPASS_CONTENTS_INLINE);
  viewport(g, SHADOW_SIZE, SHADOW_SIZE);
  vkCmdBindPipeline(g->command, VK_PIPELINE_BIND_POINT_GRAPHICS,
                    g->shadow_pipeline);
  for (size_t i = 0; i < g->shadow_count; i++)
    record_draw(g, &g->shadow_draws[i]);
  vkCmdEndRenderPass(g->command);
  VkClearValue clear[2] = {{.color = {{0.57f, 0.63f, 0.68f, 1}}},
                           {.depthStencil = {1, 0}}};
  pass.renderPass = g->color_pass;
  pass.framebuffer = g->color_fb;
  pass.renderArea.extent = (VkExtent2D){g->width, g->height};
  pass.clearValueCount = 2;
  pass.pClearValues = clear;
  vkCmdBeginRenderPass(g->command, &pass, VK_SUBPASS_CONTENTS_INLINE);
  viewport(g, g->width, g->height);
  vkCmdBindPipeline(g->command, VK_PIPELINE_BIND_POINT_GRAPHICS,
                    g->world_pipeline);
  for (size_t i = 0; i < g->color_count; i++)
    record_draw(g, &g->color_draws[i]);
  if (g->quad_count) {
    float screen[2] = {(float)g->width, (float)g->height};
    VkDeviceSize offset = 0;
    vkCmdBindPipeline(g->command, VK_PIPELINE_BIND_POINT_GRAPHICS,
                      g->overlay_pipeline);
    VkDescriptorSet ui_set=g->textures[g->font_texture+1].set;
    vkCmdBindDescriptorSets(g->command,VK_PIPELINE_BIND_POINT_GRAPHICS,g->pipeline_layout,0,1,&ui_set,0,NULL);
    vkCmdPushConstants(g->command, g->pipeline_layout,
                       VK_SHADER_STAGE_VERTEX_BIT |
                           VK_SHADER_STAGE_FRAGMENT_BIT,
                       0, sizeof(screen), screen);
    vkCmdBindVertexBuffers(g->command, 0, 1, &g->overlay_buffer.buffer,
                           &offset);
    vkCmdDraw(g->command, (uint32_t)(g->quad_count / 8), 1, 0, 0);
  }
  vkCmdEndRenderPass(g->command);
  if (command_submit(g, VK_NULL_HANDLE, VK_NULL_HANDLE) < 0)
    return -1;
  if (g->validation_errors)
    return fail("Vulkan validation reported an error; see stderr");
  g->rendered = 1;
  return 0;
}
static int swapchain_make(Graphics *g) {
  TRY(vkDeviceWaitIdle(g->device));
  VkSurfaceCapabilitiesKHR caps;
  TRY(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(g->physical, g->surface,
                                                &caps));
  if (!(caps.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_DST_BIT))
    return fail("Surface does not support transfer presentation");
  uint32_t count = 0;
  TRY(vkGetPhysicalDeviceSurfaceFormatsKHR(g->physical, g->surface, &count,
                                           NULL));
  if (!count)
    return fail("Surface has no formats");
  VkSurfaceFormatKHR *formats = calloc(count, sizeof(*formats));
  if (!formats)
    return fail("Surface format allocation failed");
  VkResult status = vkGetPhysicalDeviceSurfaceFormatsKHR(
      g->physical, g->surface, &count, formats);
  if (result(status, "surface formats") < 0) {
    free(formats);
    return -1;
  }
  VkSurfaceFormatKHR chosen = {VK_FORMAT_UNDEFINED,
                               VK_COLOR_SPACE_SRGB_NONLINEAR_KHR};
  for (uint32_t i = 0; i < count; i++) {
    VkFormat candidate = formats[i].format;
    if (candidate == VK_FORMAT_UNDEFINED)
      candidate = VK_FORMAT_B8G8R8A8_UNORM;
    VkFormatProperties properties;
    vkGetPhysicalDeviceFormatProperties(g->physical, candidate, &properties);
    if ((candidate == VK_FORMAT_B8G8R8A8_UNORM ||
         candidate == VK_FORMAT_R8G8B8A8_UNORM) &&
        formats[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR &&
        (properties.optimalTilingFeatures & VK_FORMAT_FEATURE_BLIT_DST_BIT)) {
      chosen = (VkSurfaceFormatKHR){candidate, formats[i].colorSpace};
      break;
    }
  }
  free(formats);
  if (chosen.format == VK_FORMAT_UNDEFINED)
    return fail("Surface requires an unsupported presentation format");
  VkExtent2D extent = caps.currentExtent;
  if (extent.width == UINT32_MAX) {
    extent = (VkExtent2D){(uint32_t)g->width, (uint32_t)g->height};
    if (extent.width < caps.minImageExtent.width)
      extent.width = caps.minImageExtent.width;
    if (extent.height < caps.minImageExtent.height)
      extent.height = caps.minImageExtent.height;
    if (extent.width > caps.maxImageExtent.width)
      extent.width = caps.maxImageExtent.width;
    if (extent.height > caps.maxImageExtent.height)
      extent.height = caps.maxImageExtent.height;
  }
  if (!extent.width || !extent.height)
    return 1;
  uint32_t images = caps.minImageCount + 1;
  if (caps.maxImageCount && images > caps.maxImageCount)
    images = caps.maxImageCount;
  VkCompositeAlphaFlagBitsKHR alpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  for (uint32_t bit = 1; bit <= VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR; bit <<= 1)
    if (caps.supportedCompositeAlpha & bit) {
      alpha = (VkCompositeAlphaFlagBitsKHR)bit;
      break;
    }
  VkSwapchainCreateInfoKHR info = {
      .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
      .surface = g->surface,
      .minImageCount = images,
      .imageFormat = chosen.format,
      .imageColorSpace = chosen.colorSpace,
      .imageExtent = extent,
      .imageArrayLayers = 1,
      .imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT,
      .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE,
      .preTransform = caps.currentTransform,
      .compositeAlpha = alpha,
      .presentMode = VK_PRESENT_MODE_FIFO_KHR,
      .clipped = VK_TRUE,
      .oldSwapchain = g->swapchain};
  VkSwapchainKHR replacement;
  TRY(vkCreateSwapchainKHR(g->device, &info, NULL, &replacement));
  if (g->swapchain)
    vkDestroySwapchainKHR(g->device, g->swapchain, NULL);
  g->swapchain = replacement;
  for (uint32_t i = 0; g->present_done && i < g->swap_count; i++)
    if (g->present_done[i])
      vkDestroySemaphore(g->device, g->present_done[i], NULL);
  free(g->present_done);
  g->present_done = NULL;
  free(g->swap_images);
  g->swap_images = NULL;
  g->swap_count = 0;
  TRY(vkGetSwapchainImagesKHR(g->device, g->swapchain, &g->swap_count, NULL));
  g->swap_images = calloc(g->swap_count, sizeof(*g->swap_images));
  if (!g->swap_images)
    return fail("Swapchain image allocation failed");
  TRY(vkGetSwapchainImagesKHR(g->device, g->swapchain, &g->swap_count,
                              g->swap_images));
  g->present_done = calloc(g->swap_count, sizeof(*g->present_done));
  if (!g->present_done)
    return fail("Presentation semaphore allocation failed");
  VkSemaphoreCreateInfo semaphore = {
      .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
  for (uint32_t i = 0; i < g->swap_count; i++)
    TRY(vkCreateSemaphore(g->device, &semaphore, NULL, &g->present_done[i]));
  g->swap_width = extent.width;
  g->swap_height = extent.height;
  return 0;
}
int mg_snapshot(Graphics *g, const char *path) {
  if (g->width < 1 || g->height < 1)
    return fail("Cannot snapshot a minimized window");
  if (render(g) < 0 || command_begin(g) < 0)
    return -1;
  VkBufferImageCopy copy = {
      .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
      .imageExtent = {(uint32_t)g->width, (uint32_t)g->height, 1}};
  vkCmdCopyImageToBuffer(g->command, g->color.image,
                         VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                         g->readback.buffer, 1, &copy);
  VkBufferMemoryBarrier memory = {
      .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
      .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
      .dstAccessMask = VK_ACCESS_HOST_READ_BIT,
      .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
      .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
      .buffer = g->readback.buffer,
      .size = VK_WHOLE_SIZE};
  vkCmdPipelineBarrier(g->command, VK_PIPELINE_STAGE_TRANSFER_BIT,
                       VK_PIPELINE_STAGE_HOST_BIT, 0, 0, NULL, 1, &memory, 0,
                       NULL);
  if (command_submit(g, VK_NULL_HANDLE, VK_NULL_HANDLE) < 0)
    return -1;
  SDL_Surface *surface = SDL_CreateRGBSurfaceWithFormat(
      0, g->width, g->height, 24, SDL_PIXELFORMAT_RGB24);
  if (!surface)
    return fail(SDL_GetError());
  unsigned char *pixels = NULL;
  if (result(vkMapMemory(g->device, g->readback.memory, 0, VK_WHOLE_SIZE, 0,
                         (void **)&pixels),
             "snapshot map") < 0) {
    SDL_FreeSurface(surface);
    return -1;
  }
  for (int y = 0; y < g->height; y++)
    for (int x = 0; x < g->width; x++) {
      unsigned char *src = pixels + ((size_t)y * g->width + x) * 4;
      unsigned char *dst =
          (unsigned char *)surface->pixels + (size_t)y * surface->pitch + x * 3;
      memcpy(dst, src, 3);
    }
  vkUnmapMemory(g->device, g->readback.memory);
  int rc = SDL_SaveBMP(surface, path);
  SDL_FreeSurface(surface);
  if (rc < 0)
    return fail(SDL_GetError());
  if (g->validation_errors)
    return fail("Vulkan validation error during snapshot");
  return 0;
}
int mg_present(Graphics *g) {
  if (g->width < 1 || g->height < 1)
    return 0;
  if (render(g) < 0)
    return -1;
  if (!g->window)
    return 0;
  if (!g->swapchain || g->swap_width != (uint32_t)g->width ||
      g->swap_height != (uint32_t)g->height) {
    int rc = swapchain_make(g);
    if (rc)
      return rc < 0 ? -1 : 0;
  }
  uint32_t index;
  VkResult acquired = vkAcquireNextImageKHR(
      g->device, g->swapchain, UINT64_MAX, g->acquired, VK_NULL_HANDLE, &index);
  if (acquired == VK_ERROR_OUT_OF_DATE_KHR) {
    int rc = swapchain_make(g);
    if (rc)
      return rc < 0 ? -1 : 0;
    acquired = vkAcquireNextImageKHR(g->device, g->swapchain, UINT64_MAX,
                                     g->acquired, VK_NULL_HANDLE, &index);
  }
  if (acquired != VK_SUCCESS && acquired != VK_SUBOPTIMAL_KHR)
    return result(acquired, "acquire swapchain image");
  if (command_begin(g) < 0)
    return -1;
  VkImage image = g->swap_images[index];
  barrier(g, image, VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, VK_IMAGE_LAYOUT_UNDEFINED,
          VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_PIPELINE_STAGE_TRANSFER_BIT,
          VK_PIPELINE_STAGE_TRANSFER_BIT, 0, VK_ACCESS_TRANSFER_WRITE_BIT);
  VkImageBlit blit = {
      .srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
      .srcOffsets = {{0, 0, 0}, {g->width, g->height, 1}},
      .dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
      .dstOffsets = {{0, 0, 0},
                     {(int32_t)g->swap_width, (int32_t)g->swap_height, 1}}};
  vkCmdBlitImage(
      g->command, g->color.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, image,
      VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_NEAREST);
  barrier(g, image, VK_IMAGE_ASPECT_COLOR_BIT, 0, 1,
          VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
          VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
          VK_ACCESS_TRANSFER_WRITE_BIT, 0);
  if (command_submit(g, g->acquired, g->present_done[index]) < 0)
    return -1;
  VkPresentInfoKHR present = {.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                              .waitSemaphoreCount = 1,
                              .pWaitSemaphores = &g->present_done[index],
                              .swapchainCount = 1,
                              .pSwapchains = &g->swapchain,
                              .pImageIndices = &index};
  VkResult status = vkQueuePresentKHR(g->queue, &present);
  /* Serialize present semaphore reuse, including presentation-engine
   * consumption. */
  TRY(vkQueueWaitIdle(g->queue));
  if (status == VK_ERROR_OUT_OF_DATE_KHR || status == VK_SUBOPTIMAL_KHR ||
      acquired == VK_SUBOPTIMAL_KHR) {
    int rc = swapchain_make(g);
    if (rc < 0)
      return -1;
  } else if (result(status, "present swapchain") < 0)
    return -1;
  if (g->validation_errors)
    return fail("Vulkan validation error during presentation");
  return 0;
}
int mg_draws(Graphics *g) { return (int)g->color_count; }
int mg_triangles(Graphics *g) { return g->triangles; }
int mg_validation_errors(Graphics *g) { return g->validation_errors; }
/* Used by regression tests and applications that configure their window size.
 */
int mg_resize(Graphics *g, int width, int height) {
  if (width < 1 || height < 1 || width > 16384 || height > 16384)
    return fail("Invalid resize dimensions");
  if (g->window)
    SDL_SetWindowSize(g->window, width, height);
  g->width = width;
  g->height = height;
  g->rendered = 0;
  return 0;
}

int mg_fullscreen(Graphics *g, int enabled) {
  if (!g->window) return fail("Fullscreen requires a window");
  /* SDL2-compat forwards to SDL3, whose window operations are asynchronous. */
  SDL_SetHint("SDL_VIDEO_SYNC_WINDOW_OPERATIONS", "1");
  SDL_PumpEvents();
  if (SDL_SetWindowFullscreen(g->window, enabled ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0) < 0)
    return fail(SDL_GetError());
  SDL_Vulkan_GetDrawableSize(g->window, &g->width, &g->height);
  g->rendered = 0;
  return 0;
}
int mg_is_fullscreen(Graphics *g) {
  return g->window && (SDL_GetWindowFlags(g->window) & SDL_WINDOW_FULLSCREEN) != 0;
}
