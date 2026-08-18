//
//  SSLBypass_final.mm
//  最终版: 只 hook SecTrustEvaluate，安全模式，延迟加载
//  如果还闪退，说明 TrollStore 环境下无法 hook 系统安全函数，请改用 Frida
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "fishhook.h"

#pragma mark - Logger

static NSString *sslLogPath(void) {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        path = [[paths.firstObject stringByAppendingPathComponent:@"SSLBypass.log"] copy];
    });
    return path;
}

static void SSL_LOG(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [[NSDate date] descriptionWithLocale:nil], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:sslLogPath()];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [line writeToFile:sslLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

#pragma mark - SecTrustEvaluate Hook (Safe Mode)

// 使用 void * 避免与 SDK 的 SecTrustRef 冲突
static int (*orig_SecTrustEvaluate)(void *trust, void *result);

static int fake_SecTrustEvaluate(void *trust, void *result) {
    // 先调用原始函数，保持正常流程
    int ret = 0;
    if (orig_SecTrustEvaluate) {
        ret = orig_SecTrustEvaluate(trust, result);
    }

    // 然后修改结果为"信任"
    if (result) {
        // kSecTrustResultProceed = 4, kSecTrustResultUnspecified = 2
        // 写 4 表示用户明确信任
        *(int *)result = 4;
    }

    SSL_LOG(@"[SSL] SecTrustEvaluate bypassed (orig_ret=%d)", ret);
    return 0; // errSecSuccess
}

#pragma mark - Delayed Setup

static void setupSSLBypass(void) {
    @try {
        SSL_LOG(@"[SSL] Setting up...");

        struct rebinding rebindings[] = {
            {"SecTrustEvaluate", (void *)fake_SecTrustEvaluate, (void **)&orig_SecTrustEvaluate}
        };
        int ret = rebind_symbols(rebindings, 1);
        SSL_LOG(@"[SSL] fishhook returned %d", ret);

        if (ret != 0) {
            SSL_LOG(@"[SSL] fishhook failed, trying dlsym...");
            // 备用：通过 dlsym 获取地址，手动替换
            void *handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW);
            if (handle) {
                void *sym = dlsym(handle, "SecTrustEvaluate");
                SSL_LOG(@"[SSL] SecTrustEvaluate @ %p", sym);
            }
        }

        SSL_LOG(@"[SSL] Setup complete");

    } @catch (NSException *e) {
        SSL_LOG(@"[SSL] Exception: %@", e);
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        SSL_LOG(@"=== SSLBypass_final loaded ===");

        // 延迟 5 秒，等 App 完全启动后再 hook
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            setupSSLBypass();
        });

        SSL_LOG(@"[init] Will setup in 5 seconds...");
    }
}
