// YSBrowser Pro Unlock - TrollStore Injection (.mm)
// Environment: Non-jailbreak / TrollStore / Theos
// Compile as single .mm file, no Logos preprocessing needed.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <sys/mman.h>
#import <libkern/OSCacheControl.h>

static uintptr_t g_base = 0;

// Find module base address
static uintptr_t getModuleBase(const char *name) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *imgName = _dyld_get_image_name(i);
        if (strstr(imgName, name)) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

// Patch 4 bytes at offset (relative to module base)
static void patch32(uintptr_t offset, uint32_t value) {
    uintptr_t addr = g_base + offset;
    uintptr_t page = addr & ~(PAGE_SIZE - 1);
    size_t len = PAGE_SIZE;

    // Make page writable
    mprotect((void *)page, len, PROT_READ | PROT_WRITE | PROT_EXEC);

    // Write
    *(volatile uint32_t *)addr = value;

    // Restore protection
    mprotect((void *)page, len, PROT_READ | PROT_EXEC);

    // Flush instruction cache
    sys_icache_invalidate((void *)addr, 4);
}

static inline void patchNop(uintptr_t offset) { patch32(offset, 0xd503201f); }
static inline void patchRet(uintptr_t offset) { patch32(offset, 0xd65f03c0); }
static inline void patchMovW0_1(uintptr_t offset) { patch32(offset, 0x52800020); }

// Replace function body with "mov w0, #1; ret"
static void patchFuncReturnTrue(uintptr_t offset) {
    patchMovW0_1(offset);
    patchRet(offset + 4);
}

static void setupPatches() {
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

    NSLog(@"[YSB-Pro] All patches applied (base=0x%llx)", (unsigned long long)g_base);
}

__attribute__((constructor))
static void ysbProInit() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        g_base = getModuleBase("YSBrowser");
        if (g_base) {
            setupPatches();
        } else {
            NSLog(@"[YSB-Pro] YSBrowser module not found");
        }
    });
}
