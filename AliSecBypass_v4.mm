// YSBrowser Pro Unlock - TrollStore Injection (.mm)
// Clean version: Only confirmed-effective patches.
// Working: Settings unlocked, Pro activated, File export.

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <libkern/OSCacheControl.h>

static uintptr_t g_base = 0;

static uintptr_t getModuleBase(const char *name) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *imgName = _dyld_get_image_name(i);
        if (strstr(imgName, name)) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

static int patch4(uintptr_t offset, uint32_t val) {
    uintptr_t addr = g_base + offset;
    kern_return_t kr;

    mach_port_t task = mach_task_self();
    vm_address_t region = addr & ~0x3FFF;
    vm_size_t size = 0x4000;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    memory_object_name_t obj;

    kr = vm_region_64(task, &region, &size, VM_REGION_BASIC_INFO_64,
                      (vm_region_info_t)&info, &count, &obj);
    if (kr != KERN_SUCCESS) return -1;

    kr = vm_protect(task, region, size, false, info.protection | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) return -1;

    *(volatile uint32_t *)addr = val;

    vm_protect(task, region, size, false, info.protection);
    sys_icache_invalidate((void *)addr, 4);
    return 0;
}

static inline void nop(uintptr_t o) { patch4(o, 0xd503201f); }
static inline void ret(uintptr_t o) { patch4(o, 0xd65f03c0); }
static inline void mov_w0_1(uintptr_t o) { patch4(o, 0x52800020); }
static void func_true(uintptr_t o) { mov_w0_1(o); ret(o + 4); }

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        g_base = getModuleBase("YSBrowser");
        if (!g_base) { NSLog(@"[YSB] base not found"); return; }

        // Settings: "Pro 高级版" -> "已解锁"
        nop(0x448668);

        // Pro page: "未激活" -> "已永久激活"
        func_true(0x448a84);
        nop(0x448644);

        // File export
        patch4(0x3520f8, 0x1400000e);  // b 0x352138
        nop(0x3509dc);
        nop(0x3509f8);
        nop(0x35f53c);
        func_true(0x35f50c);

        // Export button: skip Pro popup paths
        nop(0x1829f4);
        nop(0x182a50);

        // General Pro check
        nop(0x40e0d8);

        NSLog(@"[YSB] Patches OK");
    });
}
