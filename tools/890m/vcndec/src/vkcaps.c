// SPDX-License-Identifier: BSD-3-Clause-Clear
// vkcaps: video extensions and per-queue-family video codec operations of the Vulkan devices (RADV next to NVMTL).
// A VIDEO_DECODE family (flags 0x20) needs videoOps 0xf = H.264 0x1 | H.265 0x2 | AV1 0x4 | VP9 0x8 for VCNDec 0.2.0;
// the RADV built with -Dvideo-codecs=all_free shows 0xc (AV1 + VP9 only).
// usage: VK_DRIVER_FILES=/Library/GPUBundles/nvmtl/radeon_icd.json build/vkcaps
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void){
  VkApplicationInfo ai={VK_STRUCTURE_TYPE_APPLICATION_INFO,0,"q",1,"q",1,VK_API_VERSION_1_3};
  VkInstanceCreateInfo ci={VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,0,0,&ai};
  const char *ext[]={"VK_KHR_portability_enumeration"}; ci.flags=VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR; ci.enabledExtensionCount=1; ci.ppEnabledExtensionNames=ext;
  VkInstance in; VkResult r=vkCreateInstance(&ci,0,&in); if(r){ci.flags=0;ci.enabledExtensionCount=0;r=vkCreateInstance(&ci,0,&in);} if(r){printf("instance %d\n",r);return 1;}
  uint32_t n=4; VkPhysicalDevice pd[4]; vkEnumeratePhysicalDevices(in,&n,pd);
  for(uint32_t i=0;i<n;i++){ VkPhysicalDeviceProperties p; vkGetPhysicalDeviceProperties(pd[i],&p); printf("dev %s\n",p.deviceName);
    uint32_t e=0; vkEnumerateDeviceExtensionProperties(pd[i],0,&e,0); VkExtensionProperties *ep=calloc(e,sizeof*ep); vkEnumerateDeviceExtensionProperties(pd[i],0,&e,ep);
    for(uint32_t k=0;k<e;k++) if(strstr(ep[k].extensionName,"video")) printf("  ext %s\n",ep[k].extensionName);
    uint32_t q=0; vkGetPhysicalDeviceQueueFamilyProperties2(pd[i],&q,0); VkQueueFamilyProperties2 *qp=calloc(q,sizeof*qp); VkQueueFamilyVideoPropertiesKHR *vp=calloc(q,sizeof*vp);
    for(uint32_t k=0;k<q;k++){qp[k].sType=VK_STRUCTURE_TYPE_QUEUE_FAMILY_PROPERTIES_2; vp[k].sType=VK_STRUCTURE_TYPE_QUEUE_FAMILY_VIDEO_PROPERTIES_KHR; qp[k].pNext=&vp[k];}
    vkGetPhysicalDeviceQueueFamilyProperties2(pd[i],&q,qp);
    for(uint32_t k=0;k<q;k++) printf("  qf %u flags 0x%x videoOps 0x%x\n",k,qp[k].queueFamilyProperties.queueFlags,vp[k].videoCodecOperations);
  } return 0; }
