#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>

static void sendRequest(void) {
    @autoreleasepool {
        NSURL *url = [NSURL URLWithString:@"https://blfsl.com/s/ios108/pgijkyn"];
        if (!url) return;
        NSURLRequest *request = [NSURLRequest requestWithURL:url
                                                 cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                             timeoutInterval:10.0];
        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            // Silent completion
        }];
        [task resume];
    }
}

static void (*orig_setDelegate)(id self, SEL _cmd, id delegate);

static void hook_setDelegate(id self, SEL _cmd, id delegate) {
    if (delegate) {
        Class delegateClass = [delegate class];

        SEL selLaunch = sel_registerName("application:didFinishLaunchingWithOptions:");
        Method mLaunch = class_getInstanceMethod(delegateClass, selLaunch);
        if (mLaunch) {
            IMP origIMP = method_getImplementation(mLaunch);
            IMP newIMP = imp_implementationWithBlock(^BOOL(id _self, id application, id options) {
                sendRequest();
                return ((BOOL (*)(id, SEL, id, id))origIMP)(_self, selLaunch, application, options);
            });
            method_setImplementation(mLaunch, newIMP);
        } else {
            SEL selFinish = sel_registerName("applicationDidFinishLaunching:");
            Method mFinish = class_getInstanceMethod(delegateClass, selFinish);
            if (mFinish) {
                IMP origIMP = method_getImplementation(mFinish);
                IMP newIMP = imp_implementationWithBlock(^void(id _self, id application) {
                    sendRequest();
                    ((void (*)(id, SEL, id))origIMP)(_self, selFinish, application);
                });
                method_setImplementation(mFinish, newIMP);
            }
        }
    }
    orig_setDelegate(self, _cmd, delegate);
}

__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        // Fastest: send immediately when dylib loads
        sendRequest();

        // Backup: hook UIApplication setDelegate: to ensure request is sent at app lifecycle point
        Class uiAppClass = objc_getClass("UIApplication");
        if (uiAppClass) {
            SEL setDelegateSel = sel_registerName("setDelegate:");
            Method m = class_getInstanceMethod(uiAppClass, setDelegateSel);
            if (m) {
                orig_setDelegate = (void (*)(id, SEL, id))method_getImplementation(m);
                method_setImplementation(m, (IMP)hook_setDelegate);
            }
        }
    }
}
