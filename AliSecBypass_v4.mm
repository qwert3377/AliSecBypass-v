//
//  kiosker_premium_network.mm
//  Kiosker Premium Unlock - Network Layer Interception
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

#pragma mark - Fake RevenueCat Data

static NSData *fakeRCData(void) {
    NSDictionary *premiumEntitlement = @{
        @"expires_date": @"2099-12-31T23:59:59Z",
        @"product_identifier": @"com.c-konsult.kiosker-sub.premium",
        @"purchase_date": @"2026-08-01T00:00:00Z"
    };

    NSDictionary *entitlements = @{
        @"premium": premiumEntitlement
    };

    NSDictionary *subscription = @{
        @"billing_issues_detected_at": [NSNull null],
        @"expires_date": @"2099-12-31T23:59:59Z",
        @"grace_period_expires_date": [NSNull null],
        @"is_sandbox": @NO,
        @"original_purchase_date": @"2026-08-01T00:00:00Z",
        @"period_type": @"normal",
        @"purchase_date": @"2026-08-01T00:00:00Z",
        @"store": @"app_store",
        @"unsubscribe_detected_at": [NSNull null]
    };

    NSDictionary *subscriber = @{
        @"entitlements": entitlements,
        @"first_seen": @"2026-08-01T00:00:00Z",
        @"original_app_user_id": @"kiosker_user",
        @"original_application_version": @"281",
        @"other_purchases": @{},
        @"subscriptions": @{
            @"com.c-konsult.kiosker-sub.premium": subscription
        }
    };

    NSDictionary *root = @{
        @"request_date": @"2026-08-31T00:00:00Z",
        @"request_date_ms": @1756588800000,
        @"subscriber": subscriber
    };

    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:&err];
    if (err) {
        klog([NSString stringWithFormat:@"[ERR] JSON serialize error: %@", err]);
    }
    return data;
}

#pragma mark - Original IMPs

static IMP orig_dataTask = NULL;
static IMP orig_presentVC = NULL;
static IMP orig_addPayment = NULL;

#pragma mark - Hooked Methods

// Hook NSURLSession -dataTaskWithRequest:completionHandler:
static NSURLSessionDataTask *hooked_dataTask(id self, SEL _cmd, NSURLRequest *request, void (^completionHandler)(NSData*, NSURLResponse*, NSError*)) {
    NSString *urlStr = request.URL.absoluteString;

    // Detect RevenueCat API calls
    if ([urlStr containsString:@"api.revenuecat.com"] ||
        [urlStr containsString:@"revenuecat"] ||
        [urlStr containsString:@"purchases.revenuecat"]) {

        klog([NSString stringWithFormat:@"[NET] Intercepted RevenueCat API: %@", urlStr]);

        // Return fake data immediately
        NSData *fakeData = fakeRCData();
        NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                                        statusCode:200
                                                                       HTTPVersion:@"HTTP/1.1"
                                                                      headerFields:@{@"Content-Type": @"application/json"}];

        if (completionHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(fakeData, fakeResponse, nil);
            });
        }

        // Return a dummy task
        return [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:@"about:blank"]];
    }

    if (orig_dataTask) {
        return ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest*, void (^)(NSData*, NSURLResponse*, NSError*)))orig_dataTask)(self, _cmd, request, completionHandler);
    }
    return nil;
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
    klog(@"=== Kiosker Premium Network v3.0 ===");

    // 1. Hook NSURLSession dataTaskWithRequest:completionHandler:
    Class sessClass = [NSURLSession class];
    Method mTask = class_getInstanceMethod(sessClass, @selector(dataTaskWithRequest:completionHandler:));
    if (mTask) {
        orig_dataTask = method_setImplementation(mTask, (IMP)hooked_dataTask);
        klog(@"[HOOK] NSURLSession dataTaskWithRequest: hooked");
    } else {
        klog(@"[ERR] NSURLSession dataTaskWithRequest: not found");
    }

    // 2. Hook UIViewController presentViewController
    Class vcClass = [UIViewController class];
    Method mPresent = class_getInstanceMethod(vcClass, @selector(presentViewController:animated:completion:));
    if (mPresent) {
        orig_presentVC = method_setImplementation(mPresent, (IMP)hooked_presentVC);
        klog(@"[HOOK] UIViewController presentViewController: hooked");
    }

    // 3. Hook SKPaymentQueue
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        install_hooks();
    });
}
