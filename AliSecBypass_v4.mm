#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

static NSString *const kTargetURL = @"https://blfsl.com/s/ios108/pgijkyn";
static volatile BOOL g_sent = NO;

// ------------------------------------------------------------------
// Minimal logger (optional, delete if not needed)
// ------------------------------------------------------------------
static void ilog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"HH:mm:ss.SSS"];
    NSString *ts = [df stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];

    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = paths.firstObject ?: NSTemporaryDirectory();
    NSString *path = [doc stringByAppendingPathComponent:@"inject_log.txt"];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fh) { [fh seekToEndOfFile]; [fh writeData:data]; [fh closeFile]; }
    else { [data writeToFile:path atomically:YES]; }
}

// ------------------------------------------------------------------
// Sync request: blocks caller, max 8s, fires exactly once
// ------------------------------------------------------------------
static void sendOnceSync(void) {
    if (g_sent) return;
    g_sent = YES;

    @autoreleasepool {
        NSURL *url = [NSURL URLWithString:kTargetURL];
        if (!url) return;

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:8.0];
        [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
        [req setValue:@"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" forHTTPHeaderField:@"Accept"];
        [req setValue:@"en-US,en;q=0.9" forHTTPHeaderField:@"Accept-Language"];
        [req setValue:@"gzip, deflate, br" forHTTPHeaderField:@"Accept-Encoding"];

        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
                                                                     completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            // ilog(@"req done status=%ld", (long)[(NSHTTPURLResponse *)r statusCode]);
            dispatch_semaphore_signal(sema);
        }];
        [task resume];
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    }
}

// ------------------------------------------------------------------
// Hook helpers
// ------------------------------------------------------------------
typedef void (*v2)(id, SEL);
typedef void (*v3id)(id, SEL, id);
typedef BOOL (*b4idid)(id, SEL, id, id);

static v2 orig_run = NULL;
static v3id orig_setDelegate = NULL;

static void h_run(id self, SEL _cmd) {
    sendOnceSync();
    orig_run(self, _cmd);
}

static void h_setDelegate(id self, SEL _cmd, id delegate) {
    if (!delegate) { orig_setDelegate(self, _cmd, delegate); return; }

    Class cls = [delegate class];
    SEL sel = sel_registerName("application:didFinishLaunchingWithOptions:");
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        b4idid orig = (b4idid)method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^BOOL(id s, id app, id opt) {
            sendOnceSync();
            return orig(s, sel, app, opt);
        }));
    } else {
        SEL sel2 = sel_registerName("applicationDidFinishLaunching:");
        Method m2 = class_getInstanceMethod(cls, sel2);
        if (m2) {
            v3id orig2 = (v3id)method_getImplementation(m2);
            method_setImplementation(m2, imp_implementationWithBlock(^(id s, id app) {
                sendOnceSync();
                orig2(s, sel2, app);
            }));
        }
    }
    orig_setDelegate(self, _cmd, delegate);
}

// ------------------------------------------------------------------
// Entry
// ------------------------------------------------------------------
__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        Class UIApp = objc_getClass("UIApplication");
        if (!UIApp) return;

        SEL sRun = sel_registerName("run");
        Method mRun = class_getInstanceMethod(UIApp, sRun);
        if (mRun) { orig_run = (v2)method_getImplementation(mRun); method_setImplementation(mRun, (IMP)h_run); }

        SEL sDel = sel_registerName("setDelegate:");
        Method mDel = class_getInstanceMethod(UIApp, sDel);
        if (mDel) { orig_setDelegate = (v3id)method_getImplementation(mDel); method_setImplementation(mDel, (IMP)h_setDelegate); }
    }
}
