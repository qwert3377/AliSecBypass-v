//
//  YSB_Pro_Unlock_v55_AntiSuicide.mm
//  功能: YSBrowser Pro 解锁 (Frida v53 移植) + 防自杀 (YSKit exit 点补丁 + exit 家族 hook)
//  环境: Theos 编译单文件 .mm, TrollStore 注入 (非越狱)
//  说明: 全程 ObjC Runtime + MSHookFunction (从 App 自带 CydiaSubstrate.framework dlsym)
//        无 %hook, 无 Logos 语法
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <string.h>
#import <stdio.h>
#import <stdlib.h>
#import <stdarg.h>
#import <stdint.h>
#import <unistd.h>
#import <sys/mman.h>

#pragma mark - 日志 (NSLog + Documents/ysb_pro.log)

static FILE *g_logFile = NULL;

static void ysb_log(const char *fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    NSLog(@"[YSB-Pro] %s", buf);
    if (!g_logFile) {
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ysb_pro.log"];
        g_logFile = fopen(path.UTF8String, "a");
    }
    if (g_logFile) {
        fprintf(g_logFile, "%s\n", buf);
        fflush(g_logFile);
    }
}

#pragma mark - MSHookFunction (来自 App 自带的 CydiaSubstrate.framework)

typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
static MSHookFunction_t g_msHook = NULL;

static void setup_ms_hook(void) {
    void *ms = dlopen("CydiaSubstrate.framework/CydiaSubstrate", RTLD_NOW | RTLD_GLOBAL);
    if (!ms) ms = dlopen("/Applications/YSBrowser.app/Frameworks/CydiaSubstrate.framework/CydiaSubstrate", RTLD_NOW);
    if (!ms) ms = RTLD_DEFAULT;
    g_msHook = (MSHookFunction_t)dlsym(ms, "MSHookFunction");
    if (g_msHook) {
        ysb_log("MSHookFunction found: %p", g_msHook);
    } else {
        ysb_log("MSHookFunction NOT found, hooks disabled!");
    }
}

#pragma mark - 模块基址

static uintptr_t g_ysb_base = 0;   // YSBrowser 主程序实际加载基址 (slide 后)

static void find_ysb_base(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "YSBrowser.app/YSBrowser")) {
            g_ysb_base = (uintptr_t)_dyld_get_image_header(i) + (uintptr_t)_dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    ysb_log("YSBrowser base = 0x%lx", (unsigned long)g_ysb_base);
}

#pragma mark - 内存补丁

static bool write_bytes(void *addr, const uint8_t *bytes, size_t len, const char *desc) {
    long ps = getpagesize();
    void *page = (void *)((uintptr_t)addr & ~((uintptr_t)ps - 1));
    if (mprotect(page, (size_t)ps * 4, PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
        ysb_log("PATCH FAIL (mprotect) %s @ %p", desc, addr);
        return false;
    }
    memcpy(addr, bytes, len);
    bool ok = (memcmp(addr, bytes, len) == 0);
    mprotect(page, (size_t)ps * 4, PROT_READ | PROT_EXEC);
    ysb_log("PATCH %s @ 0x%lx %s", desc,
            g_ysb_base ? (unsigned long)((uintptr_t)addr - g_ysb_base) : 0, ok ? "OK" : "FAIL");
    return ok;
}

static bool patch_nop(uintptr_t rva, const char *desc) {
    if (!g_ysb_base) return false;
    const uint8_t nop[4] = { 0x1f, 0x20, 0x03, 0xd5 };
    return write_bytes((void *)(g_ysb_base + rva), nop, 4, desc);
}

// 与 Frida v53 patchBranch 完全一致 (含 -4 偏移, 保持已验证行为)
static bool patch_branch(uintptr_t pc_rva, uintptr_t tgt_rva, const char *desc) {
    if (!g_ysb_base) return false;
    int64_t diff = (int64_t)(g_ysb_base + tgt_rva) - (int64_t)(g_ysb_base + pc_rva) - 4;
    uint32_t imm26 = ((uint32_t)(diff / 4)) & 0x3FFFFFFu;
    uint32_t enc = 0x14000000u | imm26;
    uint8_t b[4] = { (uint8_t)enc, (uint8_t)(enc >> 8), (uint8_t)(enc >> 16), (uint8_t)(enc >> 24) };
    return write_bytes((void *)(g_ysb_base + pc_rva), b, 4, desc);
}

static void hook_rva(uintptr_t rva, void *repl, void **orig, const char *desc) {
    if (!g_ysb_base || !g_msHook) return;
    g_msHook((void *)(g_ysb_base + rva), repl, orig);
    ysb_log("HOOK %s @ 0x%lx", desc, (unsigned long)rva);
}

#pragma mark - 0x4054e8 嵌套计数 (C 辅助函数, 供汇编调用)

static int g_depth4054 = 0;

extern "C" void ysb_pre_4054(void) {
    g_depth4054++;
}

// 返回 1 = 最外层调用 (需要强制返回 1)
extern "C" int ysb_post_4054(void) {
    if (g_depth4054 > 0) g_depth4054--;
    return (g_depth4054 == 0) ? 1 : 0;
}

extern "C" void ysb_log_ret4e0(uintptr_t v, uintptr_t v2) {
    if (v != 0) ysb_log("0x4e0b7c returned: 0x%lx (x1=0x%lx)", v, v2);
}

#pragma mark - 裸函数 Hook 实现 (ARM64, 仅寄存器级操作)

void *ysb_orig_188588 = NULL;
const char ysb_provcs[] = "YSBrowser.ProViewController";

// 0x188588: onEnter 若 x0 是 ProViewController 则置 nil, 其余寄存器原样透传
__attribute__((naked)) static void ysb_repl_188588(void) {
    __asm__ volatile(
        "sub sp, sp, #0xb0\n"
        "stp x29, x30, [sp, #0xa0]\n"
        "stp x0, x1, [sp, #0x00]\n"
        "stp x2, x3, [sp, #0x10]\n"
        "stp x4, x5, [sp, #0x20]\n"
        "stp x6, x7, [sp, #0x30]\n"
        "str x8, [sp, #0x40]\n"
        "cbz x0, 1f\n"
        "bl _object_getClass\n"          // x0 = Class
        "bl _class_getName\n"            // x0 = class name
        "adrp x1, _ysb_provcs@PAGE\n"
        "add x1, x1, _ysb_provcs@PAGEOFF\n"
        "bl _strcmp\n"
        "cbnz w0, 1f\n"
        "str xzr, [sp, #0x00]\n"         // x0 = nil
        "1:\n"
        "ldp x0, x1, [sp, #0x00]\n"
        "ldp x2, x3, [sp, #0x10]\n"
        "ldp x4, x5, [sp, #0x20]\n"
        "ldp x6, x7, [sp, #0x30]\n"
        "ldr x8, [sp, #0x40]\n"
        "ldp x29, x30, [sp, #0xa0]\n"
        "add sp, sp, #0xb0\n"
        "adrp x16, _ysb_orig_188588@PAGE\n"
        "add x16, x16, _ysb_orig_188588@PAGEOFF\n"
        "ldr x16, [x16]\n"
        "br x16\n"
    );
}

void *ysb_orig_35f50c = NULL;

// 0x35f50c / 0x448a84: 调原函数, 返回值强制为 1
__attribute__((naked)) static void ysb_repl_ret1_35f50c(void) {
    __asm__ volatile(
        "sub sp, sp, #0xb0\n"
        "stp x29, x30, [sp, #0xa0]\n"
        "stp x0, x1, [sp, #0x00]\n"
        "stp x2, x3, [sp, #0x10]\n"
        "stp x4, x5, [sp, #0x20]\n"
        "stp x6, x7, [sp, #0x30]\n"
        "str x8, [sp, #0x40]\n"
        "adrp x16, _ysb_orig_35f50c@PAGE\n"
        "add x16, x16, _ysb_orig_35f50c@PAGEOFF\n"
        "ldr x16, [x16]\n"
        "blr x16\n"
        "mov w0, #1\n"
        "ldp x2, x3, [sp, #0x10]\n"
        "ldp x4, x5, [sp, #0x20]\n"
        "ldp x6, x7, [sp, #0x30]\n"
        "ldr x8, [sp, #0x40]\n"
        "ldp x29, x30, [sp, #0xa0]\n"
        "add sp, sp, #0xb0\n"
        "ret\n"
    );
}

void *ysb_orig_4054e8 = NULL;

// 0x4054e8: 嵌套计数, 仅最外层强制返回 1
__attribute__((naked)) static void ysb_repl_4054e8(void) {
    __asm__ volatile(
        "sub sp, sp, #0xc0\n"
        "stp x29, x30, [sp, #0xb0]\n"
        "stp x0, x1, [sp, #0x00]\n"
        "stp x2, x3, [sp, #0x10]\n"
        "stp x4, x5, [sp, #0x20]\n"
        "stp x6, x7, [sp, #0x30]\n"
        "str x8, [sp, #0x40]\n"
        "bl _ysb_pre_4054\n"
        "ldp x0, x1, [sp, #0x00]\n"
        "ldp x2, x3, [sp, #0x10]\n"
        "ldp x4, x5, [sp, #0x20]\n"
        "ldp x6, x7, [sp, #0x30]\n"
        "ldr x8, [sp, #0x40]\n"
        "adrp x16, _ysb_orig_4054e8@PAGE\n"
        "add x16, x16, _ysb_orig_4054e8@PAGEOFF\n"
        "ldr x16, [x16]\n"
        "blr x16\n"
        "stp x0, x1, [sp, #0x50]\n"        // 保存原返回值
        "bl _ysb_post_4054\n"              // w0 = 是否最外层
        "cmp w0, #0\n"
        "beq 1f\n"
        "mov w0, #1\n"
        "b 2f\n"
        "1:\n"
        "ldp x0, x1, [sp, #0x50]\n"        // 恢复原返回值
        "2:\n"
        "ldp x2, x3, [sp, #0x10]\n"
        "ldp x4, x5, [sp, #0x20]\n"
        "ldp x6, x7, [sp, #0x30]\n"
        "ldr x8, [sp, #0x40]\n"
        "ldp x29, x30, [sp, #0xb0]\n"
        "add sp, sp, #0xc0\n"
        "ret\n"
    );
}

void *ysb_orig_448a84 = NULL;

__attribute__((naked)) static void ysb_repl_ret1_448a84(void) {
    __asm__ volatile(
        "sub sp, sp, #0xb0\n"
        "stp x29, x30, [sp, #0xa0]\n"
        "stp x0, x1, [sp, #0x00]\n"
        "stp x2, x3, [sp, #0x10]\n"
        "stp x4, x5, [sp, #0x20]\n"
        "stp x6, x7, [sp, #0x30]\n"
        "str x8, [sp, #0x40]\n"
        "adrp x16, _ysb_orig_448a84@PAGE\n"
        "add x16, x16, _ysb_orig_448a84@PAGEOFF\n"
        "ldr x16, [x16]\n"
        "blr x16\n"
        "mov w0, #1\n"
        "ldp x2, x3, [sp, #0x10]\n"
        "ldp x4, x5, [sp, #0x20]\n"
        "ldp x6, x7, [sp, #0x30]\n"
        "ldr x8, [sp, #0x40]\n"
        "ldp x29, x30, [sp, #0xa0]\n"
        "add sp, sp, #0xb0\n"
        "ret\n"
    );
}

void *ysb_orig_448644 = NULL;

// 0x448644: onEnter x0 = 1, 其余寄存器不动, 尾调原函数
__attribute__((naked)) static void ysb_repl_448644(void) {
    __asm__ volatile(
        "mov x0, #1\n"
        "adrp x16, _ysb_orig_448644@PAGE\n"
        "add x16, x16, _ysb_orig_448644@PAGEOFF\n"
        "ldr x16, [x16]\n"
        "br x16\n"
    );
}

void *ysb_orig_4e0b7c = NULL;

// 0x4e0b7c: 仅监控, 返回值非 0 时记录日志, 原样返回
__attribute__((naked)) static void ysb_repl_4e0b7c(void) {
    __asm__ volatile(
        "sub sp, sp, #0xc0\n"
        "stp x29, x30, [sp, #0xb0]\n"
        "stp x0, x1, [sp, #0x00]\n"
        "stp x2, x3, [sp, #0x10]\n"
        "stp x4, x5, [sp, #0x20]\n"
        "stp x6, x7, [sp, #0x30]\n"
        "str x8, [sp, #0x40]\n"
        "adrp x16, _ysb_orig_4e0b7c@PAGE\n"
        "add x16, x16, _ysb_orig_4e0b7c@PAGEOFF\n"
        "ldr x16, [x16]\n"
        "blr x16\n"
        "stp x0, x1, [sp, #0x50]\n"
        "ldp x0, x1, [sp, #0x50]\n"
        "bl _ysb_log_ret4e0\n"
        "ldp x0, x1, [sp, #0x50]\n"
        "ldp x2, x3, [sp, #0x10]\n"
        "ldp x4, x5, [sp, #0x20]\n"
        "ldp x6, x7, [sp, #0x30]\n"
        "ldr x8, [sp, #0x40]\n"
        "ldp x29, x30, [sp, #0xb0]\n"
        "add sp, sp, #0xc0\n"
        "ret\n"
    );
}

#pragma mark - 防自杀: exit 家族 Hook

static void ysb_repl_exit(int code)    { ysb_log("BLOCKED exit(%d)", code); }
static void ysb_repl__exit(int code)   { ysb_log("BLOCKED _exit(%d)", code); }
static void ysb_repl__Exit(int code)   { ysb_log("BLOCKED _Exit(%d)", code); }
static void ysb_repl_abort(void)       { ysb_log("BLOCKED abort()"); }

static void (*o_kill)(void);          // log-only 占位
static void (*o_pthread_kill)(void);
static void (*o___pthread_kill)(void);
static void (*o_raise)(void);

static int ysb_repl_kill(int pid, int sig) {
    int r = ((int (*)(int, int))o_kill)(pid, sig);
    if (sig == 6 || sig == 9 || sig == 10 || sig == 11)
        ysb_log("kill(pid=%d, sig=%d) called", pid, sig);
    return r;
}
static int ysb_repl_pthread_kill(void *t, int sig) {
    int r = ((int (*)(void *, int))o_pthread_kill)(t, sig);
    if (sig >= 6 && sig <= 11) ysb_log("pthread_kill(sig=%d) called", sig);
    return r;
}
static int ysb_repl___pthread_kill(void *t, int sig) {
    int r = ((int (*)(void *, int))o___pthread_kill)(t, sig);
    if (sig >= 6 && sig <= 11) ysb_log("__pthread_kill(sig=%d) called", sig);
    return r;
}
static int ysb_repl_raise(int sig) {
    int r = ((int (*)(int))o_raise)(sig);
    if (sig >= 6 && sig <= 11) ysb_log("raise(sig=%d) called", sig);
    return r;
}

static void hook_signal_family(void) {
    if (!g_msHook) return;
    void *p;
    p = dlsym(RTLD_DEFAULT, "kill");           if (p) { g_msHook(p, (void *)ysb_repl_kill, (void **)&o_kill); }
    p = dlsym(RTLD_DEFAULT, "pthread_kill");   if (p) { g_msHook(p, (void *)ysb_repl_pthread_kill, (void **)&o_pthread_kill); }
    p = dlsym(RTLD_DEFAULT, "__pthread_kill"); if (p) { g_msHook(p, (void *)ysb_repl___pthread_kill, (void **)&o___pthread_kill); }
    p = dlsym(RTLD_DEFAULT, "raise");          if (p) { g_msHook(p, (void *)ysb_repl_raise, (void **)&o_raise); }
    ysb_log("signal family hooked (log-only)");
}

static void hook_exit_family(void) {
    if (!g_msHook) return;
    static void *o1, *o2, *o3, *o4;  // orig 占位 (不调用原函数)
    void *p;
    p = dlsym(RTLD_DEFAULT, "exit");   if (p) { g_msHook(p, (void *)ysb_repl_exit,   &o1); ysb_log("HOOK exit"); }
    p = dlsym(RTLD_DEFAULT, "_exit");  if (p) { g_msHook(p, (void *)ysb_repl__exit,  &o2); ysb_log("HOOK _exit"); }
    p = dlsym(RTLD_DEFAULT, "_Exit");  if (p) { g_msHook(p, (void *)ysb_repl__Exit,  &o3); ysb_log("HOOK _Exit"); }
    p = dlsym(RTLD_DEFAULT, "abort");  if (p) { g_msHook(p, (void *)ysb_repl_abort,  &o4); ysb_log("HOOK abort"); }
}

#pragma mark - 防自杀: YSKit 三个 exit 点补丁

static bool g_yskit_patched = false;

static void patch_yskit_at(uintptr_t base) {
    if (g_yskit_patched) return;
    g_yskit_patched = true;

    const uint8_t nop[4]  = { 0x1f, 0x20, 0x03, 0xd5 };
    const uint8_t ret2[8] = { 0xfd, 0x7b, 0xc1, 0xa8, 0xc0, 0x03, 0x5f, 0xd6 }; // LDP x29,x30,[sp],#16 ; RET

    // 点1: 真正的 exit 调用是 0x148d4 的 BLR x16 (间接调用)
    // 0x148e0 是 Swift ARC 指令(AND x8,x8,#-8), 必须恢复, NOP 它会崩溃!
    const uint8_t orig_and[4] = { 0x08, 0xed, 0x7c, 0x92 };
    write_bytes((void *)(base + 0x148e0), orig_and, 4, "YSKit restore AND @0x148e0");
    write_bytes((void *)(base + 0x148d4), nop, 4, "YSKit NOP BLR exit @0x148d4");

    // 点2: cfU2_Tm 0x168b0 (52 字节) -> 立即返回
    uint8_t b2[52];
    memcpy(b2, ret2, 8);
    for (int i = 8; i < 52; i += 4) memcpy(b2 + i, nop, 4);
    write_bytes((void *)(base + 0x168b0), b2, 52, "YSKit cfU2_Tm -> RET");

    // 点3: 弹窗按钮闭包 0x16d38 (16 字节) -> 立即返回
    uint8_t b3[16];
    memcpy(b3, ret2, 8);
    memcpy(b3 + 8, nop, 4);
    memcpy(b3 + 12, nop, 4);
    write_bytes((void *)(base + 0x16d38), b3, 16, "YSKit alert handler -> RET");
}

static void patch_yskit_now(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "YSKit.framework/YSKit")) {
            uintptr_t base = (uintptr_t)_dyld_get_image_header(i) + (uintptr_t)_dyld_get_image_vmaddr_slide(i);
            patch_yskit_at(base);
            return;
        }
    }
}

static void ysb_image_added(const struct mach_header *mh, intptr_t slide) {
    patch_yskit_now();
}

#pragma mark - Pro 检查批量 swizzle (对应 Frida hookProChecks)

static const char *g_selNames[] = {
    "isPro", "isVip", "isPurchased", "isProUser", "isVipUser",
    "isProVersion", "isProMember", "isVipMember", "isMember",
    "hasPro", "hasVip", "hasPurchased", "isPremium", "isSubscribed"
};
static const int g_selCount = sizeof(g_selNames) / sizeof(g_selNames[0]);

static uintptr_t ysb_yes_imp(id self, SEL _cmd) {
    return 1;
}

static int swizzle_methods_in(Class cls) {
    int hooked = 0;
    unsigned int mc = 0;
    Method *mlist = class_copyMethodList(cls, &mc);
    for (unsigned int j = 0; j < mc; j++) {
        const char *sn = sel_getName(method_getName(mlist[j]));
        for (int k = 0; k < g_selCount; k++) {
            if (strcmp(sn, g_selNames[k]) == 0) {
                method_setImplementation(mlist[j], (IMP)ysb_yes_imp);
                hooked++;
                break;
            }
        }
    }
    free(mlist);
    return hooked;
}

static int swizzle_pro_checks(void) {
    int total = 0;
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return 0;
    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
    if (!classes) return 0;
    int got = objc_getClassList(classes, count);
    for (int i = 0; i < got; i++) {
        const char *cn = class_getName(classes[i]);
        if (!cn || strncmp(cn, "YSBrowser", 9) != 0) continue;
        total += swizzle_methods_in(classes[i]);          // 实例方法
        total += swizzle_methods_in(object_getClass(classes[i])); // 类方法
    }
    free(classes);
    return total;
}

#pragma mark - Pasteboard 监控

static void (*ysb_orig_setString)(id, SEL, NSString *);

static void ysb_repl_setString(id self, SEL _cmd, NSString *s) {
    if (s && [s isKindOfClass:[NSString class]]) {
        NSString *show = ([s length] > 200) ? [s substringToIndex:200] : s;
        ysb_log("PASTEBOARD: %@", show);
    }
    ysb_orig_setString(self, _cmd, s);
}

#pragma mark - 主入口

__attribute__((constructor)) static void ysb_init(void) {
    ysb_log("=== YSB Pro Unlock v55 + AntiSuicide init ===");

    setup_ms_hook();
    find_ysb_base();

    // ---- 防自杀 ----
    hook_exit_family();
    hook_signal_family();
    patch_yskit_now();   // YSKit 可能已加载
    _dyld_register_func_for_add_image(ysb_image_added);  // 未加载则等回调

    // ---- Pro 解锁: 函数级 hook ----
    hook_rva(0x188588, (void *)ysb_repl_188588,      (void **)&ysb_orig_188588, "0x188588 ProVC->nil");
    hook_rva(0x35f50c, (void *)ysb_repl_ret1_35f50c, (void **)&ysb_orig_35f50c, "0x35f50c ret=1");
    hook_rva(0x4054e8, (void *)ysb_repl_4054e8,      (void **)&ysb_orig_4054e8, "0x4054e8 ret=1 outermost");
    hook_rva(0x448a84, (void *)ysb_repl_ret1_448a84, (void **)&ysb_orig_448a84, "0x448a84 ret=1");
    hook_rva(0x448644, (void *)ysb_repl_448644,      (void **)&ysb_orig_448644, "0x448644 x0=1");
    hook_rva(0x4e0b7c, (void *)ysb_repl_4e0b7c,      (void **)&ysb_orig_4e0b7c, "0x4e0b7c monitor");

    // ---- Pro 解锁: 内存补丁 ----
    patch_branch(0x3520f8, 0x352138, "tbnz->b (export entry)");
    patch_nop(0x3509dc, "cbz->nop (export check 2)");
    patch_nop(0x3509f8, "cbz->nop (export check 3)");
    patch_nop(0x1829f4, "tbz->nop (Pro path x0=0)");
    patch_nop(0x182a50, "tbz->nop (Pro path x0!=0)");
    patch_nop(0x448668, "tbz->nop (settings w22)");
    patch_nop(0x35f53c, "tbz->nop (export internal)");
    patch_nop(0x40e0d8, "tbz->nop (pro check)");

    // ---- Pro 检查批量 swizzle (立即 + 3 秒后补一轮, 捕获晚加载类) ----
    int n1 = swizzle_pro_checks();
    ysb_log("swizzled %d pro checks (pass 1)", n1);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        int n2 = swizzle_pro_checks();
        ysb_log("swizzled %d pro checks (pass 2)", n2);
    });

    // ---- Pasteboard 监控 ----
    Method pm = class_getInstanceMethod([UIPasteboard class], @selector(setString:));
    if (pm) {
        ysb_orig_setString = (void (*)(id, SEL, NSString *))method_setImplementation(pm, (IMP)ysb_repl_setString);
        ysb_log("UIPasteboard.setString: hooked");
    }

    ysb_log("=== init done ===");
}
