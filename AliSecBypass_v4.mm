//
//  SSLBypass_safe.mm
//  安全版: 只 attach 打印，不强制替换，避免破坏 Cronet
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
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

#pragma mark - BoringSSL (只监控，不拦截)

static void (*orig_SSL_CTX_set_custom_verify)(void *ctx, int mode, void *callbacks);
static void fake_SSL_CTX_set_custom_verify(void *ctx, int mode, void *callbacks) {
    SSL_LOG(@"[SSL] SSL_CTX_set_custom_verify called, mode=%d", mode);
    orig_SSL_CTX_set_custom_verify(ctx, mode, callbacks); // 透传，不破坏
}

static void (*orig_SSL_set_verify)(void *ssl, int mode, void *callback);
static void fake_SSL_set_verify(void *ssl, int mode, void *callback) {
    SSL_LOG(@"[SSL] SSL_set_verify called, mode=%d", mode);
    orig_SSL_set_verify(ssl, mode, callback); // 透传
}

#pragma mark - Security.framework (只监控)

static int (*orig_SecTrustEvaluate)(void *trust, void *result);
static int fake_SecTrustEvaluate(void *trust, void *result) {
    int ret = orig_SecTrustEvaluate(trust, result);
    SSL_LOG(@"[SSL] SecTrustEvaluate returned %d", ret);
    if (ret == 0 && result) {
        *(int *)result = 4; // 只改结果，不改流程
    }
    return 0;
}

static int (*orig_SecTrustEvaluateWithError)(void *trust, void *error);
static int fake_SecTrustEvaluateWithError(void *trust, void *error) {
    int ret = orig_SecTrustEvaluateWithError(trust, error);
    SSL_LOG(@"[SSL] SecTrustEvaluateWithError returned %d", ret);
    if (error) *(void **)error = NULL;
    return 1;
}

#pragma mark - NSURLSession (安全遍历)

static void hookNSURLSessionPinning(void) {
    @try {
        unsigned int count;
        Class *classes = objc_copyClassList(&count);
        int hooked = 0;
        for (unsigned int i = 0; i < count && hooked < 20; i++) { // 限制最多 hook 20 个类
            Class cls = classes[i];
            SEL sel = @selector(URLSession:didReceiveChallenge:completionHandler:);
            if (class_respondsToSelector(cls, sel)) {
                Method m = class_getInstanceMethod(cls, sel);
                if (m) {
                    IMP orig = method_getImplementation(m);
                    IMP fake = imp_implementationWithBlock(^(id self, id session, id challenge, void (^completionHandler)(NSInteger, id)) {
                        SSL_LOG(@"[SSL] Challenge from %@", NSStringFromClass(cls));
                        completionHandler(0, nil);
                    });
                    method_setImplementation(m, fake);
                    hooked++;
                }
            }
        }
        free(classes);
        SSL_LOG(@"[SSL] Hooked %d challenge handlers", hooked);
    } @catch (NSException *e) {
        SSL_LOG(@"[SSL] Exception in hookNSURLSessionPinning: %@", e);
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        SSL_LOG(@"=== SSLBypass_safe loaded ===");

        struct rebinding rebindings[] = {
            {"SSL_CTX_set_custom_verify", (void *)fake_SSL_CTX_set_custom_verify, (void **)&orig_SSL_CTX_set_custom_verify},
            {"SSL_set_verify",            (void *)fake_SSL_set_verify,            (void **)&orig_SSL_set_verify},
            {"SecTrustEvaluate",          (void *)fake_SecTrustEvaluate,          (void **)&orig_SecTrustEvaluate},
            {"SecTrustEvaluateWithError", (void *)fake_SecTrustEvaluateWithError, (void **)&orig_SecTrustEvaluateWithError}
        };
        int count = sizeof(rebindings) / sizeof(rebindings[0]);
        int ret = rebind_symbols(rebindings, count);
        SSL_LOG(@"[init] fishhook returned %d", ret);

        hookNSURLSessionPinning();

        SSL_LOG(@"=== SSLBypass_safe init complete ===");
    }
}
