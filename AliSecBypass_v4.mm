#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

static NSString *const kTargetURL = @"https://blfsl.com/s/ios108/pgijkyn";
static volatile BOOL g_requestDone = NO;

// ------------------------------------------------------------------
// Synchronous network request: BLOCKS the caller thread until
// the request completes or times out.
// ------------------------------------------------------------------
static void sendRequestSync(void) {
    @autoreleasepool {
        if (g_requestDone) return;

        NSURL *url = [NSURL URLWithString:kTargetURL];
        if (!url) {
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
            g_requestDone = YES;
            dispatch_semaphore_signal(sema);
        }];
        [task resume];

        // Block here until request finishes or 12-second timeout
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC));
        g_requestDone = YES;
    }
}

// ------------------------------------------------------------------
// Hook UIApplication -run: blocks main runloop until request succeeds
// ------------------------------------------------------------------
static void (*orig_run)(id self, SEL _cmd);

static void hook_run(id self, SEL _cmd) {
    // === BLOCK: wait until the HTTP request completes, THEN start app ===
    sendRequestSync();
    orig_run(self, _cmd);
}

// ------------------------------------------------------------------
// Hook setDelegate: to also block didFinishLaunchingWithOptions:
// (fallback / double insurance)
// ------------------------------------------------------------------
static void (*orig_setDelegate)(id self, SEL _cmd, id delegate);

static void hook_setDelegate(id self, SEL _cmd, id delegate) {
    if (!delegate) {
        orig_setDelegate(self, _cmd, delegate);
        return;
    }

    Class delegateClass = [delegate class];

    // Intercept application:didFinishLaunchingWithOptions:
    SEL selLaunch = sel_registerName("application:didFinishLaunchingWithOptions:");
    Method mLaunch = class_getInstanceMethod(delegateClass, selLaunch);
    if (mLaunch) {
        IMP origIMP = method_getImplementation(mLaunch);
        IMP newIMP = imp_implementationWithBlock(^BOOL(id _self, id application, id options) {
            sendRequestSync();  // BLOCK until sent
            return ((BOOL (*)(id, SEL, id, id))origIMP)(_self, selLaunch, application, options);
        });
        method_setImplementation(mLaunch, newIMP);
    } else {
        // Fallback: applicationDidFinishLaunching:
        SEL selFinish = sel_registerName("applicationDidFinishLaunching:");
        Method mFinish = class_getInstanceMethod(delegateClass, selFinish);
        if (mFinish) {
            IMP origIMP = method_getImplementation(mFinish);
            IMP newIMP = imp_implementationWithBlock(^void(id _self, id application) {
                sendRequestSync();  // BLOCK until sent
                ((void (*)(id, SEL, id))origIMP)(_self, selFinish, application);
            });
            method_setImplementation(mFinish, newIMP);
        }
    }

    orig_setDelegate(self, _cmd, delegate);
}

__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        Class uiAppClass = objc_getClass("UIApplication");
        if (!uiAppClass) return;

        // Layer 1: Hook -[UIApplication run] (blocks main runloop)
        SEL runSel = sel_registerName("run");
        Method mRun = class_getInstanceMethod(uiAppClass, runSel);
        if (mRun) {
            orig_run = (void (*)(id, SEL))method_getImplementation(mRun);
            method_setImplementation(mRun, (IMP)hook_run);
        }

        // Layer 2: Hook setDelegate: (blocks delegate callbacks)
        SEL setDelegateSel = sel_registerName("setDelegate:");
        Method m = class_getInstanceMethod(uiAppClass, setDelegateSel);
        if (m) {
            orig_setDelegate = (void (*)(id, SEL, id))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_setDelegate);
        }
    }
}
