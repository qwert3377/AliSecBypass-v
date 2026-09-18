// BLSniff_v6.mm —— 冷启动抓解密: Cipher.decrypt + quickDecrypt + 缓存写入拦截
// 两遍机制:
//   第一遍(无标记): 装hook → 3秒清缓存+写标记 → 自杀
//   第二遍(有标记): 删标记 → 纯监听 → App冷启动无缓存必请求lista → 解密自动捕获
// 日志: Documents/sniff.log
#import <Foundation/Foundation.h>
#import <dlfcn.h>
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

#pragma mark Swift 值解包
static NSData *swiftU8(void *x) {
    uintptr_t p = (uintptr_t)x;
    if (!p || p < 0x1000 || p > 0x400000000000) return nil;
    int64_t c = *(int64_t *)(p + 16);
    if (c <= 0 || c > 300000) return nil;
    return [NSData dataWithBytesNoCopy:(void *)(p + 24) length:(NSUInteger)c freeWhenDone:NO];
}
static NSString *swiftStr(uint64_t lo, uint64_t hi) {
    if (hi > 0x100000000ULL && hi < 0x400000000000ULL) {
        int64_t cnt = *(int64_t *)(uintptr_t)(hi + 24);
        if (cnt > 0 && cnt < 5000) {
            return [[NSString alloc] initWithBytes:(void *)(uintptr_t)(hi + 32)
                                            length:(NSUInteger)cnt encoding:NSUTF8StringEncoding];
        }
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

#pragma mark hook 1: Cipher.decrypt (底层, 所有解密必经) @ base+0xfc28
typedef void (*VoidFn)(void);
static VoidFn orig_cipher = NULL;
static void my_cipher(void) {
    void *in1 = NULL;
    __asm__ volatile("mov %0, x1" : "=r"(in1));
    ((VoidFn)orig_cipher)();                 // trampoline, 返回后 x0=输出buffer
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
            slog([NSString stringWithFormat:@"★★明文: %@", [outS substringToIndex:MIN(250, outS.length)]]);
        }
    }
}

#pragma mark hook 2: quickDecrypt (拿 passphrase) @ base+0xf958
static VoidFn orig_quick = NULL;
static void my_quick(void) {
    uint64_t lo = 0, hi = 0;
    __asm__ volatile("mov %0, x3\n\tmov %1, x4" : "=r"(lo), "=r"(hi));
    NSString *p = swiftStr(lo, hi);
    if (p && p.length > 0 && p.length < 200)
        slog([NSString stringWithFormat:@"★PASSPHRASE: %@", p]);
    ((VoidFn)orig_quick)();
}

#pragma mark hook 3: 丢弃列表缓存写入 (磁盘永无缓存)
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

        Class udCls = objc_getClass("NSUserDefaults");
        int e3 = -1;
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
            // 第一遍: 3秒后清缓存 + 写标记 + 自杀
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                clearServerCache();
                [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
                slog(@"[第一遍] 缓存已清+标记已写 → 1秒后自杀, 请重新打开App");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ exit(0); });
            });
        } else {
            [[NSFileManager defaultManager] removeItemAtPath:marker error:nil];
            slog(@"[第二遍] 纯监听中 —— App冷启动将自动请求并解密, 无需任何操作");
        }
    });
}
