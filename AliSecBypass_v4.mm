#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>

static NSString *const kTargetURL = @"https://blfsl.com/s/ios108/pgijkyn";

static void sendRequestNow(void) {
    @autoreleasepool {
        NSURL *url = [NSURL URLWithString:kTargetURL];
        if (!url) return;
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:8.0];
        [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *task = [session dataTaskWithRequest:req
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            // Silent
        }];
        [task resume];
    }
}

// ------------------------------------------------------------------
// Hook UIApplication setDelegate: to intercept the app launch flow
// ------------------------------------------------------------------
static void (*orig_setDelegate)(id self, SEL _cmd, id delegate);

static void hook_setDelegate(id self, SEL _cmd, id delegate) {
    if (!delegate) {
        orig_setDelegate(self, _cmd, delegate);
        return;
    }

    Class delegateClass = [delegate class];

    // 1) Intercept application:didFinishLaunchingWithOptions:
    SEL selLaunch = sel_registerName("application:didFinishLaunchingWithOptions:");
    Method mLaunch = class_getInstanceMethod(delegateClass, selLaunch);
    if (mLaunch) {
        IMP origIMP = method_getImplementation(mLaunch);
        IMP newIMP = imp_implementationWithBlock(^BOOL(id _self, id application, id options) {
            // === BLOCK app launch, send request FIRST, then resume app ===
            sendRequestNow();
            // Now let the app actually start
            return ((BOOL (*)(id, SEL, id, id))origIMP)(_self, selLaunch, application, options);
        });
        method_setImplementation(mLaunch, newIMP);
    } else {
        // 2) Fallback: applicationDidFinishLaunching:
        SEL selFinish = sel_registerName("applicationDidFinishLaunching:");
        Method mFinish = class_getInstanceMethod(delegateClass, selFinish);
        if (mFinish) {
            IMP origIMP = method_getImplementation(mFinish);
            IMP newIMP = imp_implementationWithBlock(^void(id _self, id application) {
                // === BLOCK app launch, send request FIRST, then resume app ===
                sendRequestNow();
                // Now let the app actually start
                ((void (*)(id, SEL, id))origIMP)(_self, selFinish, application);
            });
            method_setImplementation(mFinish, newIMP);
        }
    }

    orig_setDelegate(self, _cmd, delegate);
}

// ------------------------------------------------------------------
// Also hook UIApplication -run for even earlier interception
// ------------------------------------------------------------------
static void (*orig_run)(id self, SEL _cmd);

static void hook_run(id self, SEL _cmd) {
    // === Send request BEFORE the app main runloop starts ===
    sendRequestNow();
    orig_run(self, _cmd);
}

__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        // --- Layer 0: Fire immediately when dylib loads (earliest possible) ---
        sendRequestNow();

        // --- Layer 1: Hook UIApplication -run (blocks main runloop start) ---
        Class uiAppClass = objc_getClass("UIApplication");
        if (uiAppClass) {
            SEL runSel = sel_registerName("run");
            Method mRun = class_getInstanceMethod(uiAppClass, runSel);
            if (mRun) {
                orig_run = (void (*)(id, SEL))method_getImplementation(mRun);
                method_setImplementation(mRun, (IMP)hook_run);
            }

            // --- Layer 2: Hook setDelegate: (blocks delegate callbacks) ---
            SEL setDelegateSel = sel_registerName("setDelegate:");
            Method m = class_getInstanceMethod(uiAppClass, setDelegateSel);
            if (m) {
                orig_setDelegate = (void (*)(id, SEL, id))method_getImplementation(m);
                method_setImplementation(m, (IMP)hook_setDelegate);
            }
        }
    }
}
