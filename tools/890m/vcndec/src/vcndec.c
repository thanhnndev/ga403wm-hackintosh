// SPDX-License-Identifier: BSD-3-Clause-Clear
// vcndec: VP9 / AV1 on the 890M VCN (RADV Vulkan video through libavcodec), GPU copy into IOSurface pages.
// See vcndec.h. The decoded Vulkan image is copied with vkCmdCopyImageToBuffer into a VkBuffer that imports
// the destination IOSurface's own pages (VK_EXT_external_memory_host); one import per IOSurface, cached.
// When the import is not possible the copy goes through one host-cached staging buffer plus memcpy.
#include "vcndec.h"

#include <IOSurface/IOSurface.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_vulkan.h>
#include <libavutil/pixdesc.h>

#define NCACHE 32

typedef struct {
  IOSurfaceRef surf; // retained while imported
  void *base;
  VkDeviceMemory mem;
  VkBuffer buf;
  uint64_t last_use;
} import_ent;

struct vcn_dec {
  AVBufferRef *dev;
  AVCodecContext *cc;
  AVPacket *pkt;
  AVFrame *frm;
  // our own copy path
  VkDevice vd;
  VkPhysicalDevice pd;
  int qf, have_host_import;
  VkDeviceSize host_align;
  VkCommandPool pool;
  VkCommandBuffer cmd;
  VkFence fence;
  VkQueue queue;
  VkBuffer stage;
  VkDeviceMemory stage_mem;
  void *stage_ptr;
  VkDeviceSize stage_size;
  import_ent cache[NCACHE];
  uint64_t tick;
  uint64_t n_frames, n_gpu, n_cpu, n_imports;
  char err[256];
  // device functions
  PFN_vkGetDeviceProcAddr gdpa;
  PFN_vkGetPhysicalDeviceMemoryProperties GetPhysicalDeviceMemoryProperties;
  PFN_vkGetMemoryHostPointerPropertiesEXT GetMemoryHostPointerPropertiesEXT;
  PFN_vkAllocateMemory AllocateMemory;
  PFN_vkFreeMemory FreeMemory;
  PFN_vkCreateBuffer CreateBuffer;
  PFN_vkDestroyBuffer DestroyBuffer;
  PFN_vkBindBufferMemory BindBufferMemory;
  PFN_vkGetBufferMemoryRequirements GetBufferMemoryRequirements;
  PFN_vkMapMemory MapMemory;
  PFN_vkInvalidateMappedMemoryRanges InvalidateMappedMemoryRanges;
  PFN_vkCreateCommandPool CreateCommandPool;
  PFN_vkDestroyCommandPool DestroyCommandPool;
  PFN_vkAllocateCommandBuffers AllocateCommandBuffers;
  PFN_vkBeginCommandBuffer BeginCommandBuffer;
  PFN_vkEndCommandBuffer EndCommandBuffer;
  PFN_vkResetCommandBuffer ResetCommandBuffer;
  PFN_vkCmdPipelineBarrier CmdPipelineBarrier;
  PFN_vkCmdCopyImageToBuffer CmdCopyImageToBuffer;
  PFN_vkCreateFence CreateFence;
  PFN_vkDestroyFence DestroyFence;
  PFN_vkWaitForFences WaitForFences;
  PFN_vkResetFences ResetFences;
  PFN_vkQueueSubmit QueueSubmit;
  PFN_vkGetDeviceQueue GetDeviceQueue;
};

static void seterr(vcn_dec *d, const char *fmt, const char *a, int b) {
  snprintf(d->err, sizeof d->err, fmt, a, b);
}

const char *vcn_last_error(vcn_dec *d) { return d ? d->err : "no decoder"; }

static enum AVPixelFormat pick_fmt(AVCodecContext *c, const enum AVPixelFormat *f) {
  for (; *f != AV_PIX_FMT_NONE; f++)
    if (*f == AV_PIX_FMT_VULKAN) return *f;
  return AV_PIX_FMT_NONE; // no software fallback: VideoToolbox falls back to Apple / the app instead
}

static void global_init(void) {
  // The XPC service has no Vulkan environment: point the loader at the live RADV next to the NVMTL plugin.
  setenv("VK_DRIVER_FILES", "/Library/GPUBundles/nvmtl/radeon_icd.json", 0);
  if (!getenv("VCN_VERBOSE")) av_log_set_level(AV_LOG_ERROR);
}

#define LOADD(n) do { d->n = (void *)d->gdpa(d->vd, "vk" #n); if (!d->n) { seterr(d, "missing vk%s%.0d", #n, 0); return -1; } } while (0)

static int setup_copy(vcn_dec *d) {
  AVHWDeviceContext *hd = (AVHWDeviceContext *)d->dev->data;
  AVVulkanDeviceContext *vk = hd->hwctx;
  d->vd = vk->act_dev;
  d->pd = vk->phys_dev;
  d->gdpa = (PFN_vkGetDeviceProcAddr)vk->get_proc_addr(vk->inst, "vkGetDeviceProcAddr");
  d->GetPhysicalDeviceMemoryProperties =
      (PFN_vkGetPhysicalDeviceMemoryProperties)vk->get_proc_addr(vk->inst, "vkGetPhysicalDeviceMemoryProperties");
  if (!d->gdpa || !d->GetPhysicalDeviceMemoryProperties) { seterr(d, "no vkGetDeviceProcAddr%s%.0d", "", 0); return -1; }
  LOADD(AllocateMemory); LOADD(FreeMemory); LOADD(CreateBuffer); LOADD(DestroyBuffer); LOADD(BindBufferMemory);
  LOADD(GetBufferMemoryRequirements); LOADD(MapMemory); LOADD(InvalidateMappedMemoryRanges);
  LOADD(CreateCommandPool); LOADD(DestroyCommandPool); LOADD(AllocateCommandBuffers); LOADD(BeginCommandBuffer);
  LOADD(EndCommandBuffer); LOADD(ResetCommandBuffer); LOADD(CmdPipelineBarrier); LOADD(CmdCopyImageToBuffer);
  LOADD(CreateFence); LOADD(DestroyFence); LOADD(WaitForFences); LOADD(ResetFences); LOADD(QueueSubmit);
  LOADD(GetDeviceQueue);

  for (int i = 0; i < vk->nb_enabled_dev_extensions; i++)
    if (!strcmp(vk->enabled_dev_extensions[i], VK_EXT_EXTERNAL_MEMORY_HOST_EXTENSION_NAME)) d->have_host_import = 1;
  if (d->have_host_import) {
    d->GetMemoryHostPointerPropertiesEXT = (void *)d->gdpa(d->vd, "vkGetMemoryHostPointerPropertiesEXT");
    if (!d->GetMemoryHostPointerPropertiesEXT) d->have_host_import = 0;
  }
  d->host_align = 4096;
  if (getenv("VCN_NO_IMPORT")) d->have_host_import = 0;

  // a queue that can copy: graphics or compute (not the decode queue)
  d->qf = -1;
  for (int i = 0; i < vk->nb_qf && d->qf < 0; i++)
    if (vk->qf[i].flags & VK_QUEUE_GRAPHICS_BIT) d->qf = vk->qf[i].idx;
  for (int i = 0; i < vk->nb_qf && d->qf < 0; i++)
    if (vk->qf[i].flags & (VK_QUEUE_COMPUTE_BIT | VK_QUEUE_TRANSFER_BIT)) d->qf = vk->qf[i].idx;
  if (d->qf < 0) { seterr(d, "no copy queue%s%.0d", "", 0); return -1; }
  d->GetDeviceQueue(d->vd, d->qf, 0, &d->queue);

  VkCommandPoolCreateInfo pci = {VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, NULL,
                                 VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, (uint32_t)d->qf};
  if (d->CreateCommandPool(d->vd, &pci, NULL, &d->pool)) { seterr(d, "command pool%s%.0d", "", 0); return -1; }
  VkCommandBufferAllocateInfo cai = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, NULL, d->pool,
                                     VK_COMMAND_BUFFER_LEVEL_PRIMARY, 1};
  if (d->AllocateCommandBuffers(d->vd, &cai, &d->cmd)) { seterr(d, "command buffer%s%.0d", "", 0); return -1; }
  VkFenceCreateInfo fci = {VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
  if (d->CreateFence(d->vd, &fci, NULL, &d->fence)) { seterr(d, "fence%s%.0d", "", 0); return -1; }
  return 0;
}

vcn_dec *vcn_open(uint32_t codec, int width, int height, const uint8_t *extra, size_t extran, char *err, size_t errn) {
  static pthread_once_t once = PTHREAD_ONCE_INIT;
  pthread_once(&once, global_init);
  vcn_dec *d = calloc(1, sizeof *d);
  int r;
  const AVCodec *c = avcodec_find_decoder(codec == 'av01' ? AV_CODEC_ID_AV1 : AV_CODEC_ID_VP9);
  if (codec != 'vp09' && codec != 'av01') { seterr(d, "codec not handled%s%.0d", "", 0); goto fail; }
  if (!c) { seterr(d, "no libavcodec decoder%s%.0d", "", 0); goto fail; }
  if ((r = av_hwdevice_ctx_create(&d->dev, AV_HWDEVICE_TYPE_VULKAN, NULL, NULL, 0)) < 0) {
    seterr(d, "Vulkan device: %s (%d)", av_err2str(r), r); goto fail; }
  if (setup_copy(d) < 0) goto fail;
  d->cc = avcodec_alloc_context3(c);
  d->cc->hw_device_ctx = av_buffer_ref(d->dev);
  d->cc->get_format = pick_fmt;
  d->cc->thread_count = 1;
  d->cc->width = width;
  d->cc->height = height;
  d->cc->pkt_timebase = (AVRational){1, 1000000};
  if (extra && extran) {
    d->cc->extradata = av_mallocz(extran + AV_INPUT_BUFFER_PADDING_SIZE);
    memcpy(d->cc->extradata, extra, extran);
    d->cc->extradata_size = (int)extran;
  }
  if ((r = avcodec_open2(d->cc, c, NULL)) < 0) { seterr(d, "avcodec_open2: %s (%d)", av_err2str(r), r); goto fail; }
  d->pkt = av_packet_alloc();
  d->frm = av_frame_alloc();
  return d;
fail:
  if (err) snprintf(err, errn, "%s", d->err);
  vcn_close(d);
  return NULL;
}

int vcn_send(vcn_dec *d, const uint8_t *data, size_t size, int64_t pts) {
  av_packet_unref(d->pkt);
  if (av_new_packet(d->pkt, (int)size) < 0) return AVERROR(ENOMEM);
  memcpy(d->pkt->data, data, size);
  d->pkt->pts = pts;
  int r = avcodec_send_packet(d->cc, d->pkt);
  if (r < 0 && r != AVERROR(EAGAIN)) seterr(d, "send_packet: %s (%d)", av_err2str(r), r);
  return r;
}

int vcn_flush(vcn_dec *d) { return avcodec_send_packet(d->cc, NULL); }

static uint32_t find_type(vcn_dec *d, uint32_t bits, VkMemoryPropertyFlags want, VkMemoryPropertyFlags want2) {
  VkPhysicalDeviceMemoryProperties mp;
  d->GetPhysicalDeviceMemoryProperties(d->pd, &mp);
  for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
    if ((bits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & want) == want) return i;
  for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
    if ((bits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & want2) == want2) return i;
  return UINT32_MAX;
}

static void drop_import(vcn_dec *d, import_ent *e) {
  if (e->buf) d->DestroyBuffer(d->vd, e->buf, NULL);
  if (e->mem) d->FreeMemory(d->vd, e->mem, NULL);
  if (e->surf) CFRelease(e->surf);
  memset(e, 0, sizeof *e);
}

// VkBuffer over the IOSurface's own pages, cached per surface.
static VkBuffer surface_buffer(vcn_dec *d, IOSurfaceRef s) {
  void *base = IOSurfaceGetBaseAddress(s);
  import_ent *slot = &d->cache[0];
  for (int i = 0; i < NCACHE; i++) {
    import_ent *e = &d->cache[i];
    if (e->surf == s && e->base == base) { e->last_use = ++d->tick; return e->buf; }
    if (!e->surf) slot = e;
    else if (slot->surf && e->last_use < slot->last_use) slot = e;
  }
  if (((uintptr_t)base & (d->host_align - 1))) return VK_NULL_HANDLE;
  VkDeviceSize size = (IOSurfaceGetAllocSize(s) + d->host_align - 1) & ~(d->host_align - 1);
  VkMemoryHostPointerPropertiesEXT hp = {VK_STRUCTURE_TYPE_MEMORY_HOST_POINTER_PROPERTIES_EXT};
  if (d->GetMemoryHostPointerPropertiesEXT(d->vd, VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT, base, &hp))
    return VK_NULL_HANDLE;
  VkExternalMemoryBufferCreateInfo eb = {VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_BUFFER_CREATE_INFO, NULL,
                                         VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT};
  VkBufferCreateInfo bci = {VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, &eb, 0, size, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                            VK_SHARING_MODE_EXCLUSIVE};
  VkBuffer buf;
  if (d->CreateBuffer(d->vd, &bci, NULL, &buf)) return VK_NULL_HANDLE;
  VkMemoryRequirements mr;
  d->GetBufferMemoryRequirements(d->vd, buf, &mr);
  uint32_t ti = find_type(d, hp.memoryTypeBits & mr.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_CACHED_BIT, 0);
  VkImportMemoryHostPointerInfoEXT imp = {VK_STRUCTURE_TYPE_IMPORT_MEMORY_HOST_POINTER_INFO_EXT, NULL,
                                          VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT, base};
  VkMemoryAllocateInfo mai = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, &imp, size, ti};
  VkDeviceMemory mem;
  if (ti == UINT32_MAX || d->AllocateMemory(d->vd, &mai, NULL, &mem)) { d->DestroyBuffer(d->vd, buf, NULL); return VK_NULL_HANDLE; }
  if (d->BindBufferMemory(d->vd, buf, mem, 0)) { d->DestroyBuffer(d->vd, buf, NULL); d->FreeMemory(d->vd, mem, NULL); return VK_NULL_HANDLE; }
  if (slot->surf) drop_import(d, slot);
  slot->surf = (IOSurfaceRef)CFRetain(s);
  slot->base = base;
  slot->mem = mem;
  slot->buf = buf;
  slot->last_use = ++d->tick;
  d->n_imports++;
  return buf;
}

static VkBuffer staging(vcn_dec *d, VkDeviceSize size) {
  if (d->stage && d->stage_size >= size) return d->stage;
  if (d->stage) { d->DestroyBuffer(d->vd, d->stage, NULL); d->FreeMemory(d->vd, d->stage_mem, NULL); d->stage = 0; }
  VkBufferCreateInfo bci = {VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, NULL, 0, size, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                            VK_SHARING_MODE_EXCLUSIVE};
  if (d->CreateBuffer(d->vd, &bci, NULL, &d->stage)) return VK_NULL_HANDLE;
  VkMemoryRequirements mr;
  d->GetBufferMemoryRequirements(d->vd, d->stage, &mr);
  uint32_t ti = find_type(d, mr.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT,
                          VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT);
  VkMemoryAllocateInfo mai = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, NULL, mr.size, ti};
  if (ti == UINT32_MAX || d->AllocateMemory(d->vd, &mai, NULL, &d->stage_mem) ||
      d->BindBufferMemory(d->vd, d->stage, d->stage_mem, 0) ||
      d->MapMemory(d->vd, d->stage_mem, 0, VK_WHOLE_SIZE, 0, &d->stage_ptr)) {
    d->DestroyBuffer(d->vd, d->stage, NULL); d->stage = 0; return VK_NULL_HANDLE; }
  d->stage_size = size;
  return d->stage;
}

// GPU copy of the decoded frame's two planes into `pb`.
static int copy_out(vcn_dec *d, AVFrame *f, CVPixelBufferRef pb) {
  AVHWFramesContext *fc = (AVHWFramesContext *)f->hw_frames_ctx->data;
  AVVulkanFramesContext *vfc = fc->hwctx;
  AVHWDeviceContext *hd = (AVHWDeviceContext *)d->dev->data;
  AVVulkanDeviceContext *vk = hd->hwctx;
  AVVkFrame *vf = (AVVkFrame *)f->data[0];
  if (fc->sw_format != AV_PIX_FMT_NV12) { seterr(d, "sw_format %s not NV12%.0d", av_get_pix_fmt_name(fc->sw_format), 0); return -1; }
  IOSurfaceRef s = CVPixelBufferGetIOSurface(pb);
  if (!s) { seterr(d, "pixel buffer has no IOSurface%s%.0d", "", 0); return -1; }

  int w = f->width, h = f->height, cw = (w + 1) / 2, ch = (h + 1) / 2;
  size_t ybpr = IOSurfaceGetBytesPerRowOfPlane(s, 0), cbpr = IOSurfaceGetBytesPerRowOfPlane(s, 1);
  uint8_t *sbase = IOSurfaceGetBaseAddress(s);
  size_t yoff = (uint8_t *)IOSurfaceGetBaseAddressOfPlane(s, 0) - sbase;
  size_t coff = (uint8_t *)IOSurfaceGetBaseAddressOfPlane(s, 1) - sbase;
  if ((int)IOSurfaceGetWidthOfPlane(s, 0) < w || (int)IOSurfaceGetHeightOfPlane(s, 0) < h) {
    seterr(d, "surface smaller than frame%s%.0d", "", 0); return -1; }

  VkBuffer dst = d->have_host_import ? surface_buffer(d, s) : VK_NULL_HANDLE;
  int direct = dst != VK_NULL_HANDLE;
  size_t sy = 0, sc = (size_t)ybpr * h; // staging layout
  if (!direct) {
    dst = staging(d, sc + (size_t)cbpr * ch);
    if (!dst) { seterr(d, "staging buffer%s%.0d", "", 0); return -1; }
  }
  int nimg = vf->img[1] ? 2 : 1;

  vfc->lock_frame(fc, vf);
  d->ResetCommandBuffer(d->cmd, 0);
  VkCommandBufferBeginInfo bi = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, NULL,
                                 VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
  d->BeginCommandBuffer(d->cmd, &bi);
  VkImageMemoryBarrier ib[2];
  for (int i = 0; i < nimg; i++)
    ib[i] = (VkImageMemoryBarrier){VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, NULL, VK_ACCESS_MEMORY_WRITE_BIT,
                                   VK_ACCESS_TRANSFER_READ_BIT, vf->layout[i], VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                                   VK_QUEUE_FAMILY_IGNORED, VK_QUEUE_FAMILY_IGNORED, vf->img[i],
                                   {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
  if (nimg == 1) ib[0].subresourceRange.aspectMask = VK_IMAGE_ASPECT_PLANE_0_BIT | VK_IMAGE_ASPECT_PLANE_1_BIT;
  d->CmdPipelineBarrier(d->cmd, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0,
                        NULL, nimg, ib);
  VkBufferImageCopy rg[2] = {
      {direct ? yoff : sy, (uint32_t)ybpr, 0, {nimg == 1 ? VK_IMAGE_ASPECT_PLANE_0_BIT : VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
       {0, 0, 0}, {(uint32_t)w, (uint32_t)h, 1}},
      {direct ? coff : sc, (uint32_t)(cbpr / 2), 0, {nimg == 1 ? VK_IMAGE_ASPECT_PLANE_1_BIT : VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
       {0, 0, 0}, {(uint32_t)cw, (uint32_t)ch, 1}}};
  d->CmdCopyImageToBuffer(d->cmd, vf->img[0], VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, dst, 1, &rg[0]);
  d->CmdCopyImageToBuffer(d->cmd, vf->img[nimg - 1], VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, dst, 1, &rg[1]);
  VkBufferMemoryBarrier bb = {VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER, NULL, VK_ACCESS_TRANSFER_WRITE_BIT,
                              VK_ACCESS_HOST_READ_BIT, VK_QUEUE_FAMILY_IGNORED, VK_QUEUE_FAMILY_IGNORED, dst, 0,
                              VK_WHOLE_SIZE};
  d->CmdPipelineBarrier(d->cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 0, NULL, 1, &bb, 0, NULL);
  d->EndCommandBuffer(d->cmd);

  uint64_t wv[2], sv[2];
  VkPipelineStageFlags ws[2] = {VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT};
  for (int i = 0; i < nimg; i++) { wv[i] = vf->sem_value[i]; sv[i] = vf->sem_value[i] + 1; }
  VkTimelineSemaphoreSubmitInfo ts = {VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO, NULL, nimg, wv, nimg, sv};
  VkSubmitInfo si = {VK_STRUCTURE_TYPE_SUBMIT_INFO, &ts, nimg, vf->sem, ws, 1, &d->cmd, nimg, vf->sem};
  vk->lock_queue(hd, d->qf, 0);
  VkResult vr = d->QueueSubmit(d->queue, 1, &si, d->fence);
  vk->unlock_queue(hd, d->qf, 0);
  if (vr == VK_SUCCESS)
    for (int i = 0; i < nimg; i++) {
      vf->sem_value[i]++;
      vf->layout[i] = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
      vf->access[i] = VK_ACCESS_TRANSFER_READ_BIT;
    }
  vfc->unlock_frame(fc, vf);
  if (vr != VK_SUCCESS) { seterr(d, "copy submit failed%s %d", "", vr); return -1; }
  vr = d->WaitForFences(d->vd, 1, &d->fence, VK_TRUE, 2000000000ull);
  d->ResetFences(d->vd, 1, &d->fence);
  if (vr != VK_SUCCESS) { seterr(d, "copy fence%s %d", "", vr); return -1; }

  if (direct) { d->n_gpu++; return 0; }
  VkMappedMemoryRange mr = {VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, NULL, d->stage_mem, 0, VK_WHOLE_SIZE};
  d->InvalidateMappedMemoryRanges(d->vd, 1, &mr);
  IOSurfaceLock(s, 0, NULL);
  memcpy(sbase + yoff, (uint8_t *)d->stage_ptr + sy, ybpr * h);
  memcpy(sbase + coff, (uint8_t *)d->stage_ptr + sc, cbpr * ch);
  IOSurfaceUnlock(s, 0, NULL);
  d->n_cpu++;
  return 0;
}

int vcn_receive(vcn_dec *d, CVPixelBufferPoolRef pool, CVPixelBufferRef *out, int64_t *pts) {
  *out = NULL;
  int r = avcodec_receive_frame(d->cc, d->frm);
  if (r == AVERROR(EAGAIN) || r == AVERROR_EOF) return 0;
  if (r < 0) { seterr(d, "receive_frame: %s (%d)", av_err2str(r), r); return r; }
  if (d->frm->format != AV_PIX_FMT_VULKAN) { seterr(d, "frame not on the GPU (%s)%.0d", av_get_pix_fmt_name(d->frm->format), 0); av_frame_unref(d->frm); return -1; }
  CVPixelBufferRef pb = NULL;
  if (CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &pb) || !pb) { seterr(d, "pool empty%s%.0d", "", 0); av_frame_unref(d->frm); return -1; }
  r = copy_out(d, d->frm, pb);
  if (pts) *pts = d->frm->pts;
  av_frame_unref(d->frm);
  if (r < 0) { CVPixelBufferRelease(pb); return -1; }
  d->n_frames++;
  *out = pb;
  return 1;
}

void vcn_stats(vcn_dec *d, uint64_t *f, uint64_t *g, uint64_t *c, uint64_t *i) {
  *f = d->n_frames; *g = d->n_gpu; *c = d->n_cpu; *i = d->n_imports;
}

void vcn_close(vcn_dec *d) {
  if (!d) return;
  if (d->cc) avcodec_free_context(&d->cc);
  if (d->vd) {
    for (int i = 0; i < NCACHE; i++) if (d->cache[i].surf) drop_import(d, &d->cache[i]);
    if (d->stage) { d->DestroyBuffer(d->vd, d->stage, NULL); d->FreeMemory(d->vd, d->stage_mem, NULL); }
    if (d->fence) d->DestroyFence(d->vd, d->fence, NULL);
    if (d->pool) d->DestroyCommandPool(d->vd, d->pool, NULL);
  }
  av_packet_free(&d->pkt);
  av_frame_free(&d->frm);
  av_buffer_unref(&d->dev);
  free(d);
}
