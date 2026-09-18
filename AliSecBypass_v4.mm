// BLSniff_v7.mm —— 只 hook quickDecrypt: 拿 passphrase + 密文明文对
// 加固: slog串行队列 / safeRead防野指针 / 单hook减崩溃面
// 标记 sniff2nd 手动控制: 无=清缓存自杀一遍, 有=纯监听(保留)
// 日志: Documents/sniff.log
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import "dobby.h"

static dispatch_queue_t g_logQ = nil;
static int g_n = 0;

static void slog(NSString *msg) {
    if (!g_logQ) g_logQ = dispatch_queue_create("sniff.log", DISPATCH_QUEUE_SERIAL);
    dispatch_async(g_logQ, ^{
        @try {
            NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *path = [doc stringByAppendingPathComponent:@"sniff.log"];
            NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
            if (!h) { [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
                      h = [NSFileHandle fileHandleForWritingAtPath:path]; }
            [h seekToEndOfFile];
            [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [h closeFile];
        } @catch (...) {}
    });
}

static NSString *docsPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}

#pragma mark - 安全内存读(未映射区域返回NO, 绝不SIGSEGV)
static BOOL safeRead(const void *addr, void *buf, size_t len) {
    vm_size_t out = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(),
                        (vm_address_t)addr, len, (vm_address_t)buf, &out);
    return kr == KERN_SUCCESS && out == len;
}

#pragma mark - Swift String 解包: 大字符串 hi=堆指针, +24=count, +32=UTF8
static NSString *swiftStr(uint64_t lo, uint64_t hi) {
    (void)lo;
    if (hi > 0x100000000ULL && hi < 0x400000000000ULL) {
        int64_t cnt = 0;
        if (!safeRead((void *)(uintptr_t)(hi + 24), &cnt, 8) || cnt <= 0 || cnt > 20000) return nil;
        void *buf = malloc((size_t)cnt + 1);
        if (!buf) return nil;
        if (!safeRead((void *)(uintptr_t)(hi + 32), buf, (size_t)cnt)) { free(buf); return nil; }
        ((uint8_t *)buf)[cnt] = 0;
        NSString *s = [[NSString alloc] initWithUTF8String:(const char *)buf];
        free(buf);
        return s;
    }
    return nil;
}

#pragma mark - hook: BLAESDecryptor.quickDecrypt @ base+0xf958
typedef void (*VoidFn)(void);
static VoidFn orig_quick = NULL;

static void my_quick(void) {
    uint64_t inLo = 0, inHi = 0, pLo = 0, pHi = 0;
    __asm__ volatile("mov %0, x1\n\tmov %1, x2\n\tmov %2, x3\n\tmov %3, x4"
                     : "=r"(inLo), "=r"(inHi), "=r"(pLo), "=r"(pHi));
    NSString *input = swiftStr(inLo, inHi);
    NSString *pass = swiftStr(pLo, pHi);
    ((VoidFn)orig_quick)();                     // trampoline, 返回后 x0/x1 = String?
    uint64_t outLo = 0, outHi = 0;
    __asm__ volatile("mov %0, x0\n\tmov %1, x1" : "=r"(outLo), "=r"(outHi));
    NSString *out = outLo ? swiftStr(outLo, outHi) : nil;

    if (pass && pass.length > 0)
        slog([NSString stringWithFormat:@"★PASSPHRASE: %@", pass]);
    if (g_n < 8 && input && input.length > 16 && out && out.length > 16) {
        g_n++;
        slog([NSString stringWithFormat:@"[对#%d] 密文前80: %@",
              g_n, [input substringToIndex:MIN(80, input.length)]]);
        if ([out containsString:@"server"] || [out containsString:@"vless"] || [out containsString:@"outbounds"]) {
            slog([NSString stringWithFormat:@"★★明文: %@", [out substringToIndex:MIN(400, out.length)]]);
        } else {
            slog([NSString stringWithFormat:@"  明文前80: %@", [out substringToIndex:MIN(80, out.length)]]);
        }
    }
}

static void clearServerCache(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *k in @[@"Tananas", @"Abitproducts", @"Dugayon", @"Mansanas", @"Mearind",
                          @"Klase", @"Usuario", @"Sausuario", @"Tandaan", @"Abitcoifugs"]) {
        [ud removeObjectForKey:k];
    }
    [ud synchronize];
}

__attribute__((constructor)) static void init(void) {
    NSString *marker = [docsPath() stringByAppendingPathComponent:@"sniff2nd"];
    BOOL second = [[NSFileManager defaultManager] fileExistsAtPath:marker];

    dispatch_async(dispatch_get_main_queue(), ^{
        uintptr_t base = 0;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *nm = _dyld_get_image_name(i);
            if (nm && strstr(nm, "ButterflyLinker.app/ButterflyLinker")) {
                base = (uintptr_t)_dyld_get_image_header(i);
                break;
            }
        }
        if (!base) { slog(@"[init] 模块未找到"); return; }

        int e = DobbyHook((void *)(base + 0xf958), (void *)my_quick, (void **)&orig_quick);
        slog([NSString stringWithFormat:@"[init] quick=%d 模式=%@", e, second ? @"②监听" : @"①清缓存"]);

        if (!second) {
            // 第一遍: 3秒后清缓存+写标记+自杀(再开即监听)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                clearServerCache();
                [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
                slog(@"[第一遍] 已清缓存+写标记 → 1秒后自杀");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ exit(0); });
            });
        } else {
            // 监听模式: 标记保留, 手动删除 sniff2nd 可重置
            slog(@"[第二遍] 纯监听(标记保留) —— 进App国家页下拉刷新可触发解密");
        }
    });
}
