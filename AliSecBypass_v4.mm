// BLKeySniff.mm —— hook CryptoSwift 解密入口, 抓 AES-GCM key + iv
// key 派生自设备ID, 抓到一次就能本地解 lista 全部密文(含VIP线路)
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "dobby.h"

static void slog(NSString *msg) {
    @try {
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [doc stringByAppendingPathComponent:@"key_sniff.log"];
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) { [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
                  h = [NSFileHandle fileHandleForWritingAtPath:path]; }
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    } @catch (...) {}
}

// Swift Array<UInt8> 解包: buffer指针 → +16=count, +24=元素
static NSData *swiftU8Array(void *x) {
    uintptr_t p = (uintptr_t)x;
    if (!p || p < 0x1000) return nil;
    int64_t count = *(int64_t *)(p + 16);
    if (count <= 0 || count > 100000) return nil;
    return [NSData dataWithBytesNoCopy:(void *)(p + 24) length:count freeWhenDone:NO];
}

static NSString *hex(NSData *d) {
    if (!d) return @"(nil)";
    NSMutableString *s = [NSMutableString stringWithCapacity:d.length * 2];
    const uint8_t *b = d.bytes;
    for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02x", b[i]];
    return s;
}

// ---- hook 1: GCMC.init(iv:...) → 抓 iv (x1=iv buffer) ----
static void (*orig_gcm_init)(void);
static void my_gcm_init(void) {
    // iv 在 x1 (Swift方法: x0=self, x1=第一个参数)
    void *ivBuf = NULL;
    __asm__ volatile("mov %0, x1" : "=r"(ivBuf));
    NSData *iv = swiftU8Array(ivBuf);
    if (iv && iv.length == 12) {
        slog([NSString stringWithFormat:@"[GCM.iv] %@", hex(iv)]);
    }
    ((void (*)(void))orig_gcm_init)();
}

// ---- hook 2: AES.init(key:) → 抓 key ----
// 符号: _$s11CryptoSwift3AESC3key6blockModeACSays5UInt8VG_AA9BlockMode_ptKcfC (类构造)
// 简化: 搜所有符号名含 "3AESC3key" 的
static void (*orig_aes_init)(void);
static void my_aes_init(void) {
    void *keyBuf = NULL;
    __asm__ volatile("mov %0, x1" : "=r"(keyBuf));   // key 是第一个参数
    NSData *key = swiftU8Array(keyBuf);
    if (key && (key.length == 16 || key.length == 24 || key.length == 32)) {
        slog([NSString stringWithFormat:@"[AES.key] len=%lu %@", (unsigned long)key.length, hex(key)]);
    }
    ((void (*)(void))orig_aes_init)();
}

__attribute__((constructor)) static void init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 模块基址 + fileoff 定位
        uintptr_t base = 0;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *nm = _dyld_get_image_name(i);
            if (nm && strstr(nm, "ButterflyLinker.app/ButterflyLinker")) {
                base = (uintptr_t)_dyld_get_image_header(i);
                break;
            }
        }
        if (!base) { slog(@"[init] 未找到模块"); return; }
        int e1 = DobbyHook((void *)(base + 0x2f8f58), (void *)my_gcm_init, (void **)&orig_gcm_init);
        slog([NSString stringWithFormat:@"[init] gcm_init hook=%d", e1]);
        // AES 构造符号地址 —— 从符号表找, 简化打印让日志告诉我们
    });
}
