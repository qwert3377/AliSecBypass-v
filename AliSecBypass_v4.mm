// BLKeySniff.mm —— hook CryptoSwift AES.init + GCM.init, 抓解密 key/iv
// 密文结构: AES-GCM(nonce12 + ct + tag16), key 派生自设备ID
// 抓到 key 后本地可解 lista 全部密文(含VIP线路)
// 日志: Documents/key_sniff.log
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
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

// Swift Array<UInt8> 解包: buffer堆对象 +16=count +24=元素
static NSData *swiftU8(void *x) {
    uintptr_t p = (uintptr_t)x;
    if (!p || ((p & 0x400000000000) == 0 && (p < 0x1000 || p > 0x400000000000))) return nil;
    int64_t c = *(int64_t *)(p + 16);
    if (c <= 0 || c > 100000) return nil;
    return [NSData dataWithBytesNoCopy:(void *)(p + 24) length:(NSUInteger)c freeWhenDone:NO];
}

static NSString *hex(NSData *d) {
    if (!d) return @"(nil)";
    NSMutableString *s = [NSMutableString stringWithCapacity:d.length * 2];
    const uint8_t *b = (const uint8_t *)d.bytes;
    for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02x", b[i]];
    return s;
}

typedef void (*VoidFn)(void);
static VoidFn orig_aes = NULL, orig_gcm = NULL;

// AES.init(key:blockMode:padding:) @ base+0x2e9630, key 在 x1
static void my_aes(void) {
    void *x1 = NULL;
    __asm__ volatile("mov %0, x1" : "=r"(x1));
    NSData *key = swiftU8(x1);
    if (key && (key.length == 16 || key.length == 24 || key.length == 32))
        slog([NSString stringWithFormat:@"[AES.key] %luB %@", (unsigned long)key.length, hex(key)]);
    ((VoidFn)orig_aes)();
}

// GCMC.init(iv:...) @ base+0x2f8f58, iv 在 x1
static void my_gcm(void) {
    void *x1 = NULL;
    __asm__ volatile("mov %0, x1" : "=r"(x1));
    NSData *iv = swiftU8(x1);
    if (iv && iv.length == 12)
        slog([NSString stringWithFormat:@"[GCM.iv] %@", hex(iv)]);
    ((VoidFn)orig_gcm)();
}

__attribute__((constructor)) static void init(void) {
    uintptr_t base = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "ButterflyLinker.app/ButterflyLinker")) {
            base = (uintptr_t)_dyld_get_image_header(i);
            break;
        }
    }
    if (!base) { slog(@"[init] 模块未找到"); return; }
    int e1 = DobbyHook((void *)(base + 0x2e9630), (void *)my_aes, (void **)&orig_aes);
    int e2 = DobbyHook((void *)(base + 0x2f8f58), (void *)my_gcm, (void **)&orig_gcm);
    slog([NSString stringWithFormat:@"[init] aes=%d gcm=%d base=%#lx", e1, e2, base]);
}
