//
//  kiosker_premium_reliable.mm
//  Kiosker Premium Unlock - RevenueCat JSON Injection
//  Target: com.c-konsult.kiosker-sub
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - Logging

static void klog(NSString *msg) {
    @autoreleasepool {
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        if (!doc) return;
        NSString *path = [doc stringByAppendingPathComponent:@"kiosker_premium.log"];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) {
            [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
            if (fh) {
                [fh seekToEndOfFile];
                [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [fh closeFile];
            }
        }
    }
}

#pragma mark - Fake RevenueCat JSON

static NSString *fakeRCJson(void) {
    return @"{"
        @"\"request_date\":\"2026-08-31T00:00:00Z\","
        @"\"request_date_ms\":1756588800000,"
        @"\"subscriber\":{"
            @"\"entitlements\":{"
                @"\"premium\":{"
                    @"\"expires_date\":\"2099-12-31T23:59:59Z\","
                    @"\"product_identifier\":\"com.c-konsult.kiosker-sub.premium\","
                    @"\"purchase_date\":\"2026-08-01T00:00:00Z\""
                @"}"
            @"},"
            @"\"first_seen\":\"2026-08-01T00:00:00Z\","
            @"\"original_app_user_id\":\"kiosker_user\","
            @"\"original_application_version\":\"281\","
            @"\"other_purchases\":{},"
            @"\"subscriptions\":{"
                @"\"com.c-konsult.kiosker-sub.premium\":{""
                    @"\"billing_issues_detected_at\":null,"
                    @"\"expires_date\":\"2099-12-31T23:59:59Z\","
                    @"\"grace_period_expires_date\":null,"
                    @"\"is_sandbox\":false,"
                    @"\"original_purchase_date\":\"2026-08-01T00:00:00Z\","
                    @"\"period_type\":\"normal\","
                    @"\"purchase_date\":\"2026-08-01T00:00:00Z\","
                    @"\"store\":\"app_store\","
                    @"\"unsubscribe_detected_at\":null"
                @"}"
            @"}"
        @"}"
    @"}";
}

#pragma mark - Original IMPs

static IMP orig_jsonParse = NULL;
static IMP orig_timerTick = NULL;
static IMP orig_init = NULL;
static IMP orig_presentVC = NULL;
static IMP orig_addPayment = NULL;
static IMP orig_rcIsActive = NULL;

#pragma mark - Hooked Methods

// Hook NSJSONSerialization +JSONObjectWithData:options:error:
// Intercept RevenueCat subscriber JSON and inject fake premium data
static id hooked_jsonParse(Class cls, SEL _cmd, NSData *data, NSJSONReadingOptions opt, NSError **error) {
    if (!data || data.length == 0) {
        if (orig_jsonParse) {
            return ((id (*)(Class, SEL, NSData*, NSJSONReadingOptions, NSError**))orig_jsonParse)(cls, _cmd, data, opt, error);
        }
        return nil;
    }

    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!str) {
        if (orig_jsonParse) {
            return ((id (*)(Class, SEL, NSData*, NSJSONReadingOptions, NSError**))orig_jsonParse)(cls, _cmd, data, opt, error);
        }
        return nil;
    }

    // Detect RevenueCat subscriber response
    BOOL isRC = ([str containsString:@"subscriber"] && [str containsString:@"original_app_user_id"]) ||
                ([str containsString:@"entitlements"] && [str containsString:@"request_date"]);

    if (isRC) {
        klog(@"[JSON] Intercepted RevenueCat data, injecting fake premium...");
        NSString *fake = fakeRCJson();
        NSData *fakeData = [fake dataUsingEncoding:NSUTF8StringEncoding];
        if (orig_jsonParse) {
            id result = ((id (*)(Class, SEL, NSData*, NSJSONReadingOptions, NSError**))orig_jsonParse)(cls, _cmd, fakeData, opt, error);
            klog(@"[JSON] Fake data injected successfully");
            return result;
        }
    }

    if (orig_jsonParse) {
        return ((id (*)(Class, SEL, NSData*, NSJSONReadingOptions, NSError**))orig_jsonParse)(cls, _cmd, data, opt, error);
    }
    return nil;
}

// Hook RCEntitlementInfo -isActive
static BOOL hooked_rcIsActive(id self, SEL _cmd) {
    klog(@"[RC] isActive => forced YES");
    return YES;
}

// Hook SubscriptionHandler -timerTick
static void hooked_timerTick(id self, SEL _cmd) {
    if (orig_timerTick) {
        ((void (*)(id, SEL))orig_timerTick)(self, _cmd);
    }
}

// Hook SubscriptionHandler -init
static id hooked_init(id self, SEL _cmd) {
    id result = self;
    if (orig_init) {
        result = ((id (*)(id, SEL))orig_init)(self, _cmd);
    }
    klog(@"[SH] init called");
    return result;
}

// Hook UIViewController -presentViewController:animated:completion:
static void hooked_presentVC(id self, SEL _cmd, UIViewController *vc, BOOL animated, id completion) {
    NSString *clsName = NSStringFromClass([vc class]);
    if ([clsName containsString:@"PresentationHostingController"] ||
        [clsName containsString:@"UIHostingController"] ||
        [clsName containsString:@"SKStore"] ||
        [clsName containsString:@"Paywall"]) {
        klog([NSString stringWithFormat:@"[POPUP] Blocked: %@", clsName]);
        return;
    }
    if (orig_presentVC) {
        ((void (*)(id, SEL, UIViewController*, BOOL, id))orig_presentVC)(self, _cmd, vc, animated, completion);
    }
}

// Hook SKPaymentQueue -addPayment:
static void hooked_addPayment(id self, SEL _cmd, id payment) {
    klog(@"[IAP] Blocked addPayment");
}

#pragma mark - Installation

static void install_hooks(void) {
    klog(@"=== Kiosker Premium Reliable v2.0 ===");

    // 1. Hook NSJSONSerialization - intercept RevenueCat API responses
    Class jsonClass = [NSJSONSerialization class];
    Method mJson = class_getClassMethod(jsonClass, @selector(JSONObjectWithData:options:error:));
    if (mJson) {
        orig_jsonParse = method_setImplementation(mJson, (IMP)hooked_jsonParse);
        klog(@"[HOOK] NSJSONSerialization JSONObjectWithData: hooked");
    } else {
        klog(@"[ERR] NSJSONSerialization method not found");
    }

    // 2. Hook RCEntitlementInfo -isActive
    Class rcClass = NSClassFromString(@"RCEntitlementInfo");
    if (rcClass) {
        Method mActive = class_getInstanceMethod(rcClass, @selector(isActive));
        if (mActive) {
            orig_rcIsActive = method_setImplementation(mActive, (IMP)hooked_rcIsActive);
            klog(@"[HOOK] RCEntitlementInfo isActive hooked");
        }
    } else {
        klog(@"[WARN] RCEntitlementInfo not found (may load later)");
    }

    // 3. Hook SubscriptionHandler
    Class shClass = NSClassFromString(@"Kiosker.SubscriptionHandler");
    if (shClass) {
        Method mTick = class_getInstanceMethod(shClass, @selector(timerTick));
        if (mTick) {
            orig_timerTick = method_setImplementation(mTick, (IMP)hooked_timerTick);
            klog(@"[HOOK] SubscriptionHandler timerTick hooked");
        }
        Method mInit = class_getInstanceMethod(shClass, @selector(init));
        if (mInit) {
            orig_init = method_setImplementation(mInit, (IMP)hooked_init);
            klog(@"[HOOK] SubscriptionHandler init hooked");
        }
    } else {
        klog(@"[WARN] Kiosker.SubscriptionHandler not found (may load later)");
    }

    // 4. Hook UIViewController presentViewController
    Class vcClass = [UIViewController class];
    Method mPresent = class_getInstanceMethod(vcClass, @selector(presentViewController:animated:completion:));
    if (mPresent) {
        orig_presentVC = method_setImplementation(mPresent, (IMP)hooked_presentVC);
        klog(@"[HOOK] UIViewController presentViewController: hooked");
    }

    // 5. Hook SKPaymentQueue
    Class skClass = NSClassFromString(@"SKPaymentQueue");
    if (skClass) {
        Method mAdd = class_getInstanceMethod(skClass, @selector(addPayment:));
        if (mAdd) {
            orig_addPayment = method_setImplementation(mAdd, (IMP)hooked_addPayment);
            klog(@"[HOOK] SKPaymentQueue addPayment: hooked");
        }
    }

    klog(@"[DONE] All hooks installed.");
}

#pragma mark - Constructor

__attribute__((constructor))
static void constructor(void) {
    // Delay to ensure classes are loaded
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        install_hooks();
    });
}
