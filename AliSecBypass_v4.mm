//
//  SSLBypass_fixed.mm
//  修复: 删除自定义 SecTrustRef typedef，避免与 SDK 冲突
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

#pragma mark - BoringSSL Hooks

static void (*orig_SSL_CTX_set_custom_verify)(void *ctx, int mode, void *callbacks);
static void fake_SSL_CTX_set_custom_verify(void *ctx, int mode, void *callbacks) {
    SSL_LOG(@"[SSL] SSL_CTX_set_custom_verify bypassed");
}

static void (*orig_SSL_set_verify)(void *ssl, int mode, void *callback);
static void fake_SSL_set_verify(void *ssl, int mode, void *callback) {
    SSL_LOG(@"[SSL] SSL_set_verify bypassed");
}

#pragma mark - Security.framework Hooks

// 不用 typedef，直接用 void * 代替 SecTrustRef
static int (*orig_SecTrustEvaluate)(void *trust, void *result);
static int fake_SecTrustEvaluate(void *trust, void *result) {
    SSL_LOG(@"[SSL] SecTrustEvaluate bypassed");
    if (result) {
        *(int *)result = 4; // kSecTrustResultProceed
    }
    return 0; // errSecSuccess
}

static int (*orig_SecTrustEvaluateWithError)(void *trust, void *error);
static int fake_SecTrustEvaluateWithError(void *trust, void *error) {
    SSL_LOG(@"[SSL] SecTrustEvaluateWithError bypassed");
    if (error) {
        *(void **)error = NULL;
    }
    return 1; // true
}

#pragma mark - NSURLSession Pinning Hook

static void hookNSURLSessionPinning(void) {
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        SEL sel = @selector(URLSession:didReceiveChallenge:completionHandler:);
        if (class_respondsToSelector(cls, sel)) {
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                IMP orig = method_getImplementation(m);
                IMP fake = imp_implementationWithBlock(^(id self, id session, id challenge, void (^completionHandler)(NSInteger, id)) {
                    SSL_LOG(@"[SSL] Challenge from %@", NSStringFromClass(cls));
                    completionHandler(0, nil); // NSURLSessionAuthChallengeUseCredential
                });
                method_setImplementation(m, fake);
            }
        }
    }
    free(classes);
    SSL_LOG(@"[SSL] Hooked challenge handlers");
}

#pragma mark - Constructor

__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        SSL_LOG(@"=== SSLBypass loaded ===");

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

        SSL_LOG(@"=== SSLBypass init complete ===");
    }
}
