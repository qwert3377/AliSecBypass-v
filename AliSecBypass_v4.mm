//
//  SSLBypass.mm
//  SSL Pinning Bypass for iOS (TrollStore / 非越狱)
//  配合 mitmproxy/Charles 抓 HTTPS 包
//  日志: App Documents/SSLBypass.log
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

#pragma mark - BoringSSL / OpenSSL Hooks

typedef void *SSL_CTX;
typedef void *SSL;

static void (*orig_SSL_CTX_set_custom_verify)(SSL_CTX *ctx, int mode, void *callbacks);
static void fake_SSL_CTX_set_custom_verify(SSL_CTX *ctx, int mode, void *callbacks) {
    SSL_LOG(@"[SSL] SSL_CTX_set_custom_verify bypassed");
    // 不做任何事，直接返回，跳过证书校验
}

static void (*orig_SSL_set_verify)(SSL *ssl, int mode, void *callback);
static void fake_SSL_set_verify(SSL *ssl, int mode, void *callback) {
    SSL_LOG(@"[SSL] SSL_set_verify bypassed");
    // 不做任何事
}

#pragma mark - Security.framework Hooks

typedef void *SecTrustRef;
typedef int OSStatus;

static OSStatus (*orig_SecTrustEvaluate)(SecTrustRef trust, void *result);
static OSStatus fake_SecTrustEvaluate(SecTrustRef trust, void *result) {
    SSL_LOG(@"[SSL] SecTrustEvaluate bypassed -> errSecSuccess");
    if (result) {
        // kSecTrustResultProceed = 4
        *(int *)result = 4;
    }
    return 0; // errSecSuccess
}

static OSStatus (*orig_SecTrustEvaluateWithError)(SecTrustRef trust, void *error);
static OSStatus fake_SecTrustEvaluateWithError(SecTrustRef trust, void *error) {
    SSL_LOG(@"[SSL] SecTrustEvaluateWithError bypassed -> YES");
    if (error) {
        *(void **)error = NULL;
    }
    return 1; // true
}

#pragma mark - NSURLSession Pinning Hook (ObjC)

static void hookNSURLSessionPinning(void) {
    Class NSURLSession = objc_getClass("NSURLSession");
    if (!NSURLSession) return;

    // Hook _CFNetworkIsConnectedToCellular (可选，干扰网络检测)
    Class cfNetHelper = objc_getClass("__NSCFURLSessionConfiguration");
    if (!cfNetHelper) cfNetHelper = objc_getClass("NSURLSessionConfiguration");

    // Hook NSURLSessionDelegate 的 didReceiveChallenge
    // 很多 App 在 delegate 里做证书校验
    Class delegateCls = objc_getClass("TTNetworkManager"); // 字节跳动
    if (!delegateCls) delegateCls = objc_getClass("BDNetworkManager"); // 百度
    if (!delegateCls) delegateCls = objc_getClass("AliNetworkManager"); // 阿里

    // 通用：hook 所有类的 URLSession:didReceiveChallenge:completionHandler:
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
                    SSL_LOG(@"[SSL] URLSession challenge from %@", NSStringFromClass(cls));
                    // NSURLSessionAuthChallengeUseCredential = 0, 传空 credential 表示信任
                    completionHandler(0, nil);
                });
                method_setImplementation(m, fake);
            }
        }
    }
    free(classes);

    SSL_LOG(@"[SSL] Hooked NSURLSession challenge handlers");
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
