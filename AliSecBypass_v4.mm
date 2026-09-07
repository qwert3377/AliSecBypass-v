// YSBrowser Pro Unlock - TrollStore Injection (.mm)
// Fix: Use vm_protect instead of mprotect for iOS code patching.
//      Added retry logic and error checking.

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <libkern/OSCacheControl.h>
#import <pthread.h>

static uintptr_t g_base = 0;

static uintptr_t getModuleBase(const char *name) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *imgName = _dyld_get_image_name(i);
        if (strstr(imgName, name)) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

static int patchMemory(uintptr_t addr, const void *data, size_t size) {
    kern_return_t err;

    // Get current protection
    mach_port_t task = mach_task_self();
    vm_address_t region_addr = addr;
    vm_size_t region_size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;
    memory_object_name_t object_name;

    err = vm_region_64(task, &region_addr, &region_size, VM_REGION_BASIC_INFO_64,
                       (vm_region_info_t)&info, &info_count, &object_name);
    if (err != KERN_SUCCESS) {
        NSLog(@"[YSB-Pro] vm_region failed: %d", err);
        return -1;
    }

    // Change protection to allow writing
    err = vm_protect(task, region_addr, region_size, false,
                     info.protection | VM_PROT_WRITE | VM_PROT_COPY);
    if (err != KERN_SUCCESS) {
        NSLog(@"[YSB-Pro] vm_protect failed: %d", err);
        return -1;
    }

    // Write data
    err = vm_write(task, addr, (vm_offset_t)data, (mach_msg_type_number_t)size);
    if (err != KERN_SUCCESS) {
        NSLog(@"[YSB-Pro] vm_write failed: %d", err);
        // Try restore protection even if write failed
        vm_protect(task, region_addr, region_size, false, info.protection);
        return -1;
    }

    // Restore original protection
    err = vm_protect(task, region_addr, region_size, false, info.protection);
    if (err != KERN_SUCCESS) {
        NSLog(@"[YSB-Pro] vm_protect restore failed: %d", err);
    }

    // Flush cache
    sys_icache_invalidate((void *)addr, size);

    return 0;
}

static void patch32(uintptr_t offset, uint32_t value) {
    if (!g_base) return;
    uintptr_t addr = g_base + offset;
    uint32_t data = value;
    if (patchMemory(addr, &data, 4) != 0) {
        NSLog(@"[YSB-Pro] Failed to patch 0x%llx", (unsigned long long)offset);
    }
}

static inline void patchNop(uintptr_t offset) { patch32(offset, 0xd503201f); }
static inline void patchRet(uintptr_t offset) { patch32(offset, 0xd65f03c0); }
static inline void patchMovW0_1(uintptr_t offset) { patch32(offset, 0x52800020); }

static void patchFuncReturnTrue(uintptr_t offset) {
    patchMovW0_1(offset);
    patchRet(offset + 4);
}

static void setupPatches() {
    NSLog(@"[YSB-Pro] Applying patches at base=0x%llx", (unsigned long long)g_base);

    // === Settings page ===
    patchNop(0x448668);

    // === Pro detail page ===
    patchFuncReturnTrue(0x448a84);
    patchNop(0x448644);

    // === Export checks ===
    patch32(0x3520f8, 0x1400000e);
    patchNop(0x3509dc);
    patchNop(0x3509f8);
    patchNop(0x35f53c);
    patchFuncReturnTrue(0x35f50c);

    // === Export button Pro paths ===
    patchNop(0x1829f4);
    patchNop(0x182a50);

    // === Pro check ===
    patchNop(0x40e0d8);

    NSLog(@"[YSB-Pro] All patches applied");
}

__attribute__((constructor))
static void ysbProInit() {
    // Wait for YSBrowser to be fully loaded
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        g_base = getModuleBase("YSBrowser");
        if (g_base) {
            setupPatches();
        } else {
            NSLog(@"[YSB-Pro] YSBrowser module not found, retrying...");
            // Retry after 5 more seconds
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                g_base = getModuleBase("YSBrowser");
                if (g_base) {
                    setupPatches();
                } else {
                    NSLog(@"[YSB-Pro] YSBrowser module still not found");
                }
            });
        }
    });
}
