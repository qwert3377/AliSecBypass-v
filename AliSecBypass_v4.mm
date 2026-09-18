// ButterflyTrialPatch.mm
// 编译: TrollStore 注入环境, Theos 直接编译此单文件为 dylib
// 原理: 把 isSubscribed / isPremium 两个 Swift getter 的前 8 字节
//       改写为 mov w0,#1 ; ret —— 会员状态出口恒定 true
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <sys/mman.h>
#import <string.h>
#import <stdint.h>

// fileoff（静态分析 + 动态校验确认, 与 ASLR 无关）:
//   BLSubscriptionManager.isSubscribed getter = 0x4a8d4
//   BLConnectionMainViewModel.isPremium getter = 0x137350
static const uintptr_t kIsSubscribedOff = 0x4a8d4;
static const uintptr_t kIsPremiumOff    = 0x137350;

static void log_msg(NSString *msg) {
    NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *path = [doc stringByAppendingPathComponent:@"trial_patch.log"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    [h seekToEndOfFile];
    [h writeData:[[NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg] dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

static uintptr_t find_base(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "ButterflyLinker.app/ButterflyLinker"))
            return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

// arm64: mov w0, #1 = 0x52800020 ; ret = 0xD65F03C0
static void patch_getter(uintptr_t base, uintptr_t fileoff, const char *tag) {
    uintptr_t addr = base + fileoff;
    uint32_t patch[2] = { 0x52800020u, 0xD65F03C0u };
    // 校验原指令是 stp (A9xx) 函数序言, 防止版本不符写坏
    uint32_t first;
    memcpy(&first, (void *)addr, 4);
    if ((first & 0xFF000000) != 0xA9000000 && (first & 0xFF000000) != 0xD1000000 &&
        (first & 0xFC000000) != 0xA9000000) {
        log_msg([NSString stringWithFormat:@"[跳过] %s 首指令 %#x 非预期序言", tag, first]);
        return;
    }
    uintptr_t page = addr & ~0x3FFFUL;          // iOS arm64 页 = 16KB
    size_t len = ((addr + 8 - page) + 0x3FFF) & ~0x3FFFUL;
    mprotect((void *)page, len, PROT_READ | PROT_WRITE | PROT_EXEC);
    memcpy((void *)addr, patch, 8);
    __builtin___clear_cache((void *)addr, (void *)(addr + 8));
    mprotect((void *)page, len, PROT_READ | PROT_EXEC);
    log_msg([NSString stringWithFormat:@"[成功] %s getter patched @ %#lx (原指令 %#x)", tag, addr, first]);
}

__attribute__((constructor)) static void trial_patch_init(void) {
    uintptr_t base = find_base();
    if (!base) { log_msg(@"[失败] 未找到 ButterflyLinker 模块"); return; }
    log_msg([NSString stringWithFormat:@"[*] 模块基址 %#lx", base]);
    patch_getter(base, kIsSubscribedOff, "isSubscribed");
    patch_getter(base, kIsPremiumOff, "isPremium");
    log_msg(@"[*] 注入完成, 会员状态已解锁");
}
