//
//  YSB_AntiSuicide.mm
//  功能: YSBrowser 防自杀最小版 — 仅 YSKit 三个 exit 点补丁
//  原理: vm_protect + VM_PROT_COPY 写 __TEXT (mprotect 在启动早期会被拒)
//  环境: Theos 单文件, TrollStore 注入
//

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <string.h>
#import <stdio.h>
#import <stdarg.h>
#import <stdint.h>
#import <unistd.h>
#import <sys/mman.h>

#pragma mark - 日志

static FILE *g_logFile = NULL;

static void ysb_log(const char *fmt, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    NSLog(@"[YSB-Anti] %s", buf);
    if (!g_logFile) {
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ysb_pro.log"];
        g_logFile = fopen(path.UTF8String, "a");
    }
    if (g_logFile) {
        fprintf(g_logFile, "%s\n", buf);
        fflush(g_logFile);
    }
}

#pragma mark - 写内存 (vm_protect + VM_PROT_COPY)

static bool vm_write(void *addr, const uint8_t *bytes, size_t len, const char *desc) {
    uintptr_t ps = (uintptr_t)getpagesize();
    vm_address_t page = (vm_address_t)((uintptr_t)addr & ~(ps - 1));
    vm_size_t cover = (vm_size_t)(ps * 4);

    kern_return_t kr = vm_protect(mach_task_self(), page, cover, false,
                                  VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        ysb_log("FAIL %s @ %p vm_protect->w: %s", desc, addr, mach_error_string(kr));
        return false;
    }
    memcpy(addr, bytes, len);
    bool ok = (memcmp(addr, bytes, len) == 0);
    vm_protect(mach_task_self(), page, cover, false, VM_PROT_READ | VM_PROT_EXECUTE);
    ysb_log("%s %s @ %p", ok ? "PATCH OK" : "PATCH VERIFY-FAIL", desc, addr);
    return ok;
}

#pragma mark - YSKit 三个自杀点 (偏移 = 文件偏移 = VM 地址)

// 点1: 0x148d4 BLR x16 = 间接调 _exit  -> NOP
//      0x148e0 AND x8,x8,#-8 (Swift ARC) -> 必须保持原样, 写错会崩
// 点2: 0x168b0 cfU2_Tm 整个函数 (52字节) -> LDP/RET + NOP 填充
// 点3: 0x16d38 弹窗按钮闭包 (16字节)   -> LDP/RET + NOP 填充
static bool s_done[4] = { false, false, false, false };

static void patch_yskit_at(uintptr_t base) {
    static const uint8_t nop[4]  = { 0x1f, 0x20, 0x03, 0xd5 };
    static const uint8_t and_[4] = { 0x08, 0xed, 0x7c, 0x92 };                 // AND x8,x8,#-8 原指令
    static const uint8_t ret2[8] = { 0xfd, 0x7b, 0xc1, 0xa8,                    // LDP x29,x30,[sp],#16
                                     0xc0, 0x03, 0x5f, 0xd6 };                  // RET

    if (!s_done[0]) s_done[0] = vm_write((void *)(base + 0x148e0), and_, 4,  "restore AND  @0x148e0");
    if (!s_done[1]) s_done[1] = vm_write((void *)(base + 0x148d4), nop,  4,  "NOP BLR exit @0x148d4");
    if (!s_done[2]) {
        uint8_t b2[52];
        memcpy(b2, ret2, 8);
        for (int i = 8; i < 52; i += 4) memcpy(b2 + i, nop, 4);
        s_done[2] = vm_write((void *)(base + 0x168b0), b2, 52, "cfU2_Tm RET  @0x168b0");
    }
    if (!s_done[3]) {
        uint8_t b3[16];
        memcpy(b3, ret2, 8);
        memcpy(b3 + 8, nop, 4);
        memcpy(b3 + 12, nop, 4);
        s_done[3] = vm_write((void *)(base + 0x16d38), b3, 16, "alert RET    @0x16d38");
    }
}

static void patch_yskit_now(const char *tag) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "YSKit.framework/YSKit")) {
            uintptr_t base = (uintptr_t)_dyld_get_image_header(i) + (uintptr_t)_dyld_get_image_vmaddr_slide(i);
            ysb_log("[%s] YSKit base = 0x%lx", tag, (unsigned long)base);
            patch_yskit_at(base);
            return;
        }
    }
    ysb_log("[%s] YSKit not loaded yet", tag);
}

static void ysb_image_added(const struct mach_header *mh, intptr_t slide) {
    patch_yskit_now("add-image");
}

#pragma mark - 入口

__attribute__((constructor)) static void ysb_init(void) {
    ysb_log("=== YSB AntiSuicide init ===");

    // 1. 立即尝试 (vm_protect+COPY 在多数情况下早期就能成功)
    patch_yskit_now("ctor");

    // 2. YSKit 晚加载回调
    _dyld_register_func_for_add_image(ysb_image_added);

    // 3. 兜底: 主线程 0.3s 后再试 (防启动早期 VM 状态未就绪导致失败)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        patch_yskit_now("retry-0.3s");
    });

    ysb_log("=== init done ===");
}
