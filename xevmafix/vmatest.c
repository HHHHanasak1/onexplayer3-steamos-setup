#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static PFN_vkGetInstanceProcAddr gipa;
#define IF(n) PFN_##n n = (PFN_##n)gipa(inst, #n)

static double now(void) { struct timespec t; clock_gettime(CLOCK_REALTIME, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static void stamp(const char *msg, int r) { time_t t = time(NULL); char b[32]; strftime(b, sizeof b, "%H:%M:%S", localtime(&t)); printf("%s %s %d\n", b, msg, r); fflush(stdout); }

int main(int argc, char **argv) {
    int count = argc > 1 ? atoi(argv[1]) : 20000;
    int chunk_kib = argc > 2 ? atoi(argv[2]) : 64;
    int seconds = argc > 3 ? atoi(argv[3]) : 120;
    void *lib = dlopen("libvulkan.so.1", RTLD_NOW);
    if (!lib) { puts("no libvulkan"); return 2; }
    gipa = (PFN_vkGetInstanceProcAddr)dlsym(lib, "vkGetInstanceProcAddr");
    VkInstance inst = VK_NULL_HANDLE;
    PFN_vkCreateInstance vkCreateInstance = (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
    VkApplicationInfo ai = { VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_1 };
    VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ai };
    if (vkCreateInstance(&ici, NULL, &inst)) { puts("instance fail"); return 2; }
    IF(vkEnumeratePhysicalDevices); IF(vkGetPhysicalDeviceMemoryProperties); IF(vkGetPhysicalDeviceQueueFamilyProperties);
    IF(vkCreateDevice); IF(vkGetDeviceQueue); IF(vkCreateBuffer); IF(vkGetBufferMemoryRequirements); IF(vkAllocateMemory);
    IF(vkBindBufferMemory); IF(vkCreateCommandPool); IF(vkAllocateCommandBuffers); IF(vkBeginCommandBuffer); IF(vkEndCommandBuffer);
    IF(vkCmdFillBuffer); IF(vkQueueSubmit); IF(vkQueueWaitIdle); IF(vkResetCommandBuffer); IF(vkGetPhysicalDeviceProperties);
    uint32_t n = 1; VkPhysicalDevice pd; vkEnumeratePhysicalDevices(inst, &n, &pd);
    VkPhysicalDeviceProperties pp; vkGetPhysicalDeviceProperties(pd, &pp); printf("device %s\n", pp.deviceName);
    VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd, &mp);
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &prio };
    VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qci };
    VkDevice dev; if (vkCreateDevice(pd, &dci, NULL, &dev)) { puts("device fail"); return 2; }
    VkQueue q; vkGetDeviceQueue(dev, 0, 0, &q);
    VkCommandPoolCreateInfo cpi = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, .queueFamilyIndex = 0 };
    VkCommandPool pool; vkCreateCommandPool(dev, &cpi, NULL, &pool);
    VkCommandBufferAllocateInfo cai = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
    VkCommandBuffer cb; vkAllocateCommandBuffers(dev, &cai, &cb);
    VkBuffer *bufs = calloc(count, sizeof *bufs);
    VkDeviceSize sz = (VkDeviceSize)chunk_kib << 10;
    for (int i = 0; i < count; i++) {
        VkDeviceSize s = i == 0 ? 4096 : sz;
        VkBufferCreateInfo bci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = s, .usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT };
        vkCreateBuffer(dev, &bci, NULL, &bufs[i]);
        VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev, bufs[i], &mr);
        uint32_t t = 0;
        for (; t < mp.memoryTypeCount; t++)
            if ((mr.memoryTypeBits & (1u << t)) && (mp.memoryTypes[t].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) break;
        VkMemoryAllocateInfo mai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size, .memoryTypeIndex = t };
        VkDeviceMemory m; VkResult r = vkAllocateMemory(dev, &mai, NULL, &m);
        if (r) { stamp("alloc fail at chunk", i); return 3; }
        vkBindBufferMemory(dev, bufs[i], m, 0);
    }
    VkCommandBufferBeginInfo bbi = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
    VkSubmitInfo si = { VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb };
    vkBeginCommandBuffer(cb, &bbi);
    for (int i = 1; i < count; i++) vkCmdFillBuffer(cb, bufs[i], 0, VK_WHOLE_SIZE, 0x5a5a5a5a);
    vkEndCommandBuffer(cb);
    VkResult r = vkQueueSubmit(q, 1, &si, VK_NULL_HANDLE); if (!r) r = vkQueueWaitIdle(q);
    printf("filled %d allocations of %d KiB (%.2f GiB)\n", count - 1, chunk_kib, (double)(count - 1) * chunk_kib / 1048576);
    stamp("fill", r);
    double end = now() + seconds;
    int fails = 0;
    while (now() < end) {
        double t0 = now();
        vkResetCommandBuffer(cb, 0); vkBeginCommandBuffer(cb, &bbi);
        vkCmdFillBuffer(cb, bufs[0], 0, 4096, 1); vkEndCommandBuffer(cb);
        r = vkQueueSubmit(q, 1, &si, VK_NULL_HANDLE); if (!r) r = vkQueueWaitIdle(q);
        double dt = now() - t0;
        if (r || dt > 0.5) { char m[64]; snprintf(m, sizeof m, "submit took %.2fs result", dt); stamp(m, r); }
        if (r && ++fails > 3) return 4;
        usleep(500000);
    }
    stamp("done", 0);
    return 0;
}
