// BLSniff_v6.mm —— 冷启动抓解密: Cipher.decrypt + quickDecrypt + 缓存写入拦截
// 模式控制(手动, 标记文件 sniff2nd 只增不删):
//   无标记 = 第一遍: 3秒清缓存+写标记 → 自杀 → 再开即监听
//   有标记 = 监听模式: 纯捕获, 标记保留; 手动删标记可重置回第一遍
// 日志: Documents/sniff.log
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import "dobby.h"

static BOOL g_inLog = NO;
static int g_n = 0;
static NSSet *g_cacheKeys = nil;

static void slog(NSString *msg) {
    if (g_inLog) return;
    g_inLog = YES;
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
    g_inLog = NO;
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

#pragma mark - Swift 值解包
// Array<UInt8>: buffer堆对象, +16=count, +24=元素数据
static NSData *swiftU8(void *x) {
    uintptr_t p = (uintptr_t)x;
    if (!p || p < 0x1000 || p > 0x400000000000) return nil;
    int64_t c = 0;
    if (!safeRead((void *)(p + 16), &c, 8)) return nil;
    if (c <= 0 || c > 300000) return nil;
    void *buf = malloc((size_t)c);
    if (!buf) return nil;
    if (!safeRead((void *)(p + 24), buf, (size_t)c)) { free(buf); return nil; }
    return [NSData dataWithBytesNoCopy:buf length:(NSUInteger)c freeWhenDone:YES];
}

// String: 大字符串 hi=堆指针, +24=count, +32=UTF8数据
static NSString *swiftStr(uint64_t lo, uint64_t hi) {
    (void)lo;
    if (hi > 0x100000000ULL && hi < 0x400000000000ULL) {
        int64_t cnt = 0;
        if (!safeRead((void *)(uintptr_t)(hi + 24), &cnt, 8) || cnt <= 0 || cnt > 5000) return nil;
        void *buf = malloc((size_t)cnt);
        if (!buf) return nil;
        if (!safeRead((void *)(uintptr_t)(hi + 32), buf, (size_t)cnt)) { free(buf); return nil; }
        NSString *s = [[NSString alloc] initWithBytes:buf length:(NSUInteger)cnt encoding:NSUTF8StringEncoding];
        free(buf);
        return s;
    }
    return nil;
}

static NSString *hexStr(NSData *d, NSUInteger n) {
    if (!d) return @"";
    NSMutableString *s = [NSMutableString string];
    const uint8_t *b = (const uint8_t *)d.bytes;
    for (NSUInteger i = 0; i < MIN(n, d.length); i++) [s appendFormat:@"%02x", b[i]];
    return s;
}

#pragma mark - hook 1: Cipher.decrypt @ base+0xfc28 (所有解密必经)
typedef void (*VoidFn)(void);
static VoidFn orig_cipher = NULL;

static void my_cipher(void) {
    void *in1 = NULL;
    __asm__ volatile("mov %0, x1" : "=r"(in1));
    ((VoidFn)orig_cipher)();                       // trampoline, 返回后 x0=输出buffer
    uintptr_t ret = 0;
    __asm__ volatile("mov %0, x0" : "=r"(ret));
    NSData *inD = swiftU8(in1);
    NSData *outD = swiftU8((void *)ret);
    if (inD && outD && outD.length > 10 && g_n < 12) {
        g_n++;
        NSString *outS = [[NSString alloc] initWithData:outD encoding:NSUTF8StringEncoding];
        slog([NSString stringWithFormat:@"[Cipher#%d] in=%luB %@ → out=%luB",
              g_n, (unsigned long)inD.length, hexStr(inD, 20), (unsigned long)outD.length]);
        if (outS && ([outS containsString:@"server"] || [outS containsString:@"vless"])) {
            slog([NSString stringWithFormat:@"★★明文: %@",
                  [outS substringToIndex:MIN(250, outS.length)]]);
        }
    }
}

#pragma mark - hook 2: BLAESDecryptor.quickDecrypt @ base+0xf958 (拿 passphrase)
static VoidFn orig_quick = NULL;

static void my_quick(void) {
    uint64_t lo = 0, hi = 0;
    __asm__ volatile("mov %0, x3\n\tmov %1, x4" : "=r"(lo), "=r"(hi));
    NSString *p = swiftStr(lo, hi);
    if (p && p.length > 0 && p.length < 200)
        slog([NSString stringWithFormat:@"★PASSPHRASE: %@", p]);
    ((VoidFn)orig_quick)();
}

#pragma mark - hook 3: 丢弃列表缓存写入 (磁盘永无缓存)
static id (*orig_setObj)(NSUserDefaults *, SEL, id, id);
static id my_setObj(NSUserDefaults *self, SEL _cmd, id v, id k) {
    if ([k isKindOfClass:[NSString class]] && [g_cacheKeys containsObject:(NSString *)k]) {
        slog([NSString stringWithFormat:@"[拦截缓存] %@", k]);
        v = [NSNull null];
    }
    return orig_setObj(self, _cmd, v, k);
}

static void clearServerCache(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *k in @[@"Tananas", @"Abitproducts", @"Dugayon", @"Mansanas", @"Mearind",
                          @"Klase", @"Usuario", @"Sausuario", @"Tandaan", @"Abitcoifugs",
                          @"Bitasyon", @"Libutan", @"Adlaw", @"Liyente"]) {
        [ud removeObjectForKey:k];
    }
    [ud synchronize];
}

__attribute__((constructor)) static void init(void) {
    g_cacheKeys = [NSSet setWithArray:@[@"Tananas", @"Abitproducts", @"Dugayon", @"Mansanas",
                                        @"Mearind", @"Klase"]];
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

        int e1 = DobbyHook((void *)(base + 0xfc28), (void *)my_cipher, (void **)&orig_cipher);
        int e2 = DobbyHook((void *)(base + 0xf958), (void *)my_quick, (void **)&orig_quick);

        int e3 = -1;
        Class udCls = objc_getClass("NSUserDefaults");
        if (udCls) {
            Method m = class_getInstanceMethod(udCls, @selector(setObject:forKey:));
            if (m) {
                orig_setObj = (id (*)(NSUserDefaults *, SEL, id, id))method_setImplementation(m, (IMP)my_setObj);
                e3 = 0;
            }
        }
        slog([NSString stringWithFormat:@"[init] cipher=%d quick=%d setObj=%d 模式=%@",
              e1, e2, e3, second ? @"②监听" : @"①清缓存"]);

        if (!second) {
            // 第一遍: 3秒后清缓存 + 写标记 + 自杀(之后每次启动都是监听, 直到手动删标记)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                clearServerCache();
                [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
                slog(@"[第一遍] 缓存已清+标记已写 → 1秒后自杀, 再开即监听模式");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ exit(0); });
            });
        } else {
            // 监听模式: 保留标记不删, 手动删除 sniff2nd 文件才能回到第一遍
            slog(@"[第二遍] 纯监听中 —— 标记保留; 想重新清缓存请手动删除 sniff2nd");
        }
    });
}
