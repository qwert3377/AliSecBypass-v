//
//  SSLBypass_minimal.mm
//  极简版: 延迟加载 + 只 hook NSURLSession delegate
//  不碰 BoringSSL/SecTrustEvaluate，避免闪退
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

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

#pragma mark - Safe Hook Helper

static void safeSwizzle(Class cls, SEL origSel, SEL newSel) {
    if (!cls) return;
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method newMethod = class_getInstanceMethod(cls, newSel);
    if (!origMethod || !newMethod) return;

    BOOL didAdd = class_addMethod(cls, origSel,
                                  method_getImplementation(newMethod),
                                  method_getTypeEncoding(newMethod));
    if (didAdd) {
        class_replaceMethod(cls, newSel,
                           method_getImplementation(origMethod),
                           method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, newMethod);
    }
}

#pragma mark - NSURLSession Challenge Bypass

@interface NSURLSessionDelegateHook : NSObject
@end

@implementation NSURLSessionDelegateHook

// 替换 URLSession:didReceiveChallenge:completionHandler:
- (void)hook_URLSession:(NSURLSession *)session
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {

    SSL_LOG(@"[SSL] Challenge for %@", challenge.protectionSpace.host);

    // 信任所有证书
    NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
    completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
}

@end

#pragma mark - Delayed Setup

static void setupSSLBypass(void) {
    @try {
        SSL_LOG(@"[SSL] Setting up bypass...");

        // 1. Hook NSURLSession 的 delegate 方法
        Class hookCls = [NSURLSessionDelegateHook class];
        SEL origSel = @selector(URLSession:didReceiveChallenge:completionHandler:);
        SEL hookSel = @selector(hook_URLSession:didReceiveChallenge:completionHandler:);

        // 遍历常见网络管理类
        const char *targetClasses[] = {
            "TTNetworkManager",
            "BDNetworkManager",
            "AliNetworkManager",
            "CronetNetworkManager",
            "TTHttpTask",
            "BDHttpTask",
            "NSURLSessionTask",
            "__NSCFURLSessionTask",
            nil
        };

        int hooked = 0;
        for (int i = 0; targetClasses[i]; i++) {
            Class cls = objc_getClass(targetClasses[i]);
            if (cls && class_respondsToSelector(cls, origSel)) {
                safeSwizzle(cls, origSel, hookSel);
                SSL_LOG(@"[SSL] Hooked %s", targetClasses[i]);
                hooked++;
            }
        }

        // 2. 如果没有找到特定类，尝试通用 hook：替换 NSURLSession 的 sharedSession
        if (hooked == 0) {
            Class sessionCls = objc_getClass("NSURLSession");
            if (sessionCls) {
                // 尝试 hook dataTaskWithRequest 来监控
                SEL origDataTask = @selector(dataTaskWithRequest:);
                Method m = class_getInstanceMethod(sessionCls, origDataTask);
                if (m) {
                    IMP orig = method_getImplementation(m);
                    IMP fake = imp_implementationWithBlock(^id(id self, NSURLRequest *request) {
                        SSL_LOG(@"[SSL] dataTaskWithRequest: %@", request.URL.absoluteString);
                        return ((id (*)(id, SEL, NSURLRequest *))orig)(self, origDataTask, request);
                    });
                    method_setImplementation(m, fake);
                    SSL_LOG(@"[SSL] Hooked NSURLSession dataTaskWithRequest:");
                }
            }
        }

        SSL_LOG(@"[SSL] Setup complete, hooked %d classes", hooked);

    } @catch (NSException *e) {
        SSL_LOG(@"[SSL] Exception: %@", e);
    }
}

#pragma mark - Constructor (delayed)

__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        SSL_LOG(@"=== SSLBypass_minimal loaded ===");

        // 延迟 3 秒执行，等 App 完全启动
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            setupSSLBypass();
        });

        SSL_LOG(@"[init] Will setup in 3 seconds...");
    }
}
