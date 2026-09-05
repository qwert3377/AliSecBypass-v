#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

static NSString *const kTargetURL = @"https://blfsl.com/s/ios108/pgijkyn";
static volatile BOOL g_requestDone = NO;

// ------------------------------------------------------------------
// Logger: writes to App Documents / inject_log.txt
// ------------------------------------------------------------------
static NSString *logPath(void) {
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docDir = paths.firstObject;
        if (!docDir) docDir = NSTemporaryDirectory();
        path = [docDir stringByAppendingPathComponent:@"inject_log.txt"];
    });
    return path;
}

static void logMsg(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *ts = [df stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];

    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath()];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    } else {
        [data writeToFile:logPath() atomically:YES];
    }
}

// ------------------------------------------------------------------
// Synchronous network request with detailed logging
// ------------------------------------------------------------------
static void sendRequestSync(void) {
    @autoreleasepool {
        if (g_requestDone) {
            logMsg(@"[sendRequestSync] already done, skip");
            return;
        }

        logMsg(@"[sendRequestSync] start URL=%@", kTargetURL);

        NSURL *url = [NSURL URLWithString:kTargetURL];
        if (!url) {
            logMsg(@"[sendRequestSync] ERROR: URL is nil");
            g_requestDone = YES;
            return;
        }

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10.0];
        [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];

        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        NSURLSession *session = [NSURLSession sharedSession];

        NSURLSessionDataTask *task = [session dataTaskWithRequest:req
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                logMsg(@"[sendRequestSync] FAILED error=%@", error);
            } else {
                NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
                logMsg(@"[sendRequestSync] SUCCESS status=%ld bytes=%lu", (long)httpResp.statusCode, (unsigned long)data.length);
            }
            g_requestDone = YES;
            dispatch_semaphore_signal(sema);
        }];

        logMsg(@"[sendRequestSync] task resume");
        [task resume];

        logMsg(@"[sendRequestSync] waiting on semaphore...");
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC);
        long result = dispatch_semaphore_wait(sema, timeout);

        if (result != 0) {
            logMsg(@"[sendRequestSync] TIMEOUT after 12s, forcing done");
        } else {
            logMsg(@"[sendRequestSync] semaphore signaled");
        }
        g_requestDone = YES;
    }
}

// ------------------------------------------------------------------
// Hook UIApplication -run
// ------------------------------------------------------------------
static void (*orig_run)(id self, SEL _cmd);

static void hook_run(id self, SEL _cmd) {
    logMsg(@"[hook_run] ENTER, calling sendRequestSync...");
    sendRequestSync();
    logMsg(@"[hook_run] sendRequestSync returned, calling orig_run");
    orig_run(self, _cmd);
    logMsg(@"[hook_run] EXIT (orig_run returned)");
}

// ------------------------------------------------------------------
// Hook setDelegate:
// ------------------------------------------------------------------
static void (*orig_setDelegate)(id self, SEL _cmd, id delegate);

static void hook_setDelegate(id self, SEL _cmd, id delegate) {
    logMsg(@"[hook_setDelegate] ENTER delegate=%@", delegate);

    if (!delegate) {
        logMsg(@"[hook_setDelegate] delegate is nil, pass through");
        orig_setDelegate(self, _cmd, delegate);
        return;
    }

    Class delegateClass = [delegate class];
    logMsg(@"[hook_setDelegate] delegateClass=%@", NSStringFromClass(delegateClass));

    SEL selLaunch = sel_registerName("application:didFinishLaunchingWithOptions:");
    Method mLaunch = class_getInstanceMethod(delegateClass, selLaunch);
    if (mLaunch) {
        logMsg(@"[hook_setDelegate] found application:didFinishLaunchingWithOptions:");
        IMP origIMP = method_getImplementation(mLaunch);
        IMP newIMP = imp_implementationWithBlock(^BOOL(id _self, id application, id options) {
            logMsg(@"[hook_didFinishLaunching] ENTER");
            sendRequestSync();
            logMsg(@"[hook_didFinishLaunching] calling origIMP");
            BOOL ret = ((BOOL (*)(id, SEL, id, id))origIMP)(_self, selLaunch, application, options);
            logMsg(@"[hook_didFinishLaunching] EXIT ret=%d", (int)ret);
            return ret;
        });
        method_setImplementation(mLaunch, newIMP);
    } else {
        logMsg(@"[hook_setDelegate] didFinishLaunchingWithOptions: NOT found, try fallback");
        SEL selFinish = sel_registerName("applicationDidFinishLaunching:");
        Method mFinish = class_getInstanceMethod(delegateClass, selFinish);
        if (mFinish) {
            logMsg(@"[hook_setDelegate] found applicationDidFinishLaunching:");
            IMP origIMP = method_getImplementation(mFinish);
            IMP newIMP = imp_implementationWithBlock(^void(id _self, id application) {
                logMsg(@"[hook_didFinishLaunching_fallback] ENTER");
                sendRequestSync();
                logMsg(@"[hook_didFinishLaunching_fallback] calling origIMP");
                ((void (*)(id, SEL, id))origIMP)(_self, selFinish, application);
                logMsg(@"[hook_didFinishLaunching_fallback] EXIT");
            });
            method_setImplementation(mFinish, newIMP);
        } else {
            logMsg(@"[hook_setDelegate] WARNING: neither launch method found!");
        }
    }

    logMsg(@"[hook_setDelegate] calling orig_setDelegate");
    orig_setDelegate(self, _cmd, delegate);
    logMsg(@"[hook_setDelegate] EXIT");
}

__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        logMsg(@"========================================");
        logMsg(@"[init] dylib loaded, starting hooks...");

        Class uiAppClass = objc_getClass("UIApplication");
        if (!uiAppClass) {
            logMsg(@"[init] FATAL: UIApplication class not found!");
            return;
        }
        logMsg(@"[init] UIApplication class found");

        // Hook -[UIApplication run]
        SEL runSel = sel_registerName("run");
        Method mRun = class_getInstanceMethod(uiAppClass, runSel);
        if (mRun) {
            orig_run = (void (*)(id, SEL))method_getImplementation(mRun);
            method_setImplementation(mRun, (IMP)hook_run);
            logMsg(@"[init] Hooked -[UIApplication run]");
        } else {
            logMsg(@"[init] WARNING: -[UIApplication run] method not found");
        }

        // Hook setDelegate:
        SEL setDelegateSel = sel_registerName("setDelegate:");
        Method m = class_getInstanceMethod(uiAppClass, setDelegateSel);
        if (m) {
            orig_setDelegate = (void (*)(id, SEL, id))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_setDelegate);
            logMsg(@"[init] Hooked -[UIApplication setDelegate:]");
        } else {
            logMsg(@"[init] WARNING: -[UIApplication setDelegate:] method not found");
        }

        logMsg(@"[init] all hooks installed");
    }
}
