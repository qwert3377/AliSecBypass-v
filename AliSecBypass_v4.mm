//
//  kiosker_premium.mm
//  Kiosker Premium Unlock - TrollStore Injection
//  Target: com.c-konsult.kiosker-sub
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - Constants

#define KIOSKER_STATE_SUBSCRIBED    2
#define KIOSKER_STATE_OFFSET        32  // @Published<SubscriptionState> enum value offset

#pragma mark - Logging

static void kiosker_log(NSString *msg) {
    @autoreleasepool {
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        if (!docPath) return;
        NSString *logPath = [docPath stringByAppendingPathComponent:@"kiosker_premium.log"];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:logPath]) {
            [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
            if (fh) {
                [fh seekToEndOfFile];
                [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [fh closeFile];
            }
        }
    }
}

#pragma mark - State Patching

static inline void force_subscribed_state(id instance) {
    if (!instance) return;
    uint8_t *ptr = (uint8_t *)instance;
    // _state is @Published<SubscriptionState>, enum value at offset 32
    // 0=free, 1=trial, 2=subscribed
    ptr[KIOSKER_STATE_OFFSET] = KIOSKER_STATE_SUBSCRIBED;
}

static inline uint8_t read_state(id instance) {
    if (!instance) return 0xFF;
    uint8_t *ptr = (uint8_t *)instance;
    return ptr[KIOSKER_STATE_OFFSET];
}

#pragma mark - Original IMPs

static IMP orig_timerTick = NULL;
static IMP orig_init = NULL;
static IMP orig_customerInfo = NULL;
static IMP orig_presentVC = NULL;
static IMP orig_addPayment = NULL;

#pragma mark - Hooked Methods

// Hook SubscriptionHandler -timerTick
// Force _state=2 BEFORE timerTick executes, so timerTick reads subscribed and does not reset
static void hooked_timerTick(id self, SEL _cmd) {
    uint8_t old = read_state(self);
    if (old != KIOSKER_STATE_SUBSCRIBED) {
        force_subscribed_state(self);
        kiosker_log([NSString stringWithFormat:@"timerTick pre-fix: %d => %d", old, KIOSKER_STATE_SUBSCRIBED]);
    }

    if (orig_timerTick) {
        ((void (*)(id, SEL))orig_timerTick)(self, _cmd);
    }

    // Double-check after execution
    uint8_t after = read_state(self);
    if (after != KIOSKER_STATE_SUBSCRIBED) {
        force_subscribed_state(self);
        kiosker_log([NSString stringWithFormat:@"timerTick post-fix: %d => %d", after, KIOSKER_STATE_SUBSCRIBED]);
    }
}

// Hook SubscriptionHandler -init
static id hooked_init(id self, SEL _cmd) {
    id result = self;
    if (orig_init) {
        result = ((id (*)(id, SEL))orig_init)(self, _cmd);
    }
    if (result) {
        force_subscribed_state(result);
        kiosker_log(@"init: _state => 2");
    }
    return result;
}

// Hook SubscriptionHandler -purchases:receivedUpdatedCustomerInfo:
static void hooked_customerInfo(id self, SEL _cmd, id purchases, id customerInfo) {
    if (orig_customerInfo) {
        ((void (*)(id, SEL, id, id))orig_customerInfo)(self, _cmd, purchases, customerInfo);
    }
    // Force state back after RevenueCat callback
    force_subscribed_state(self);
    kiosker_log(@"customerInfo callback: _state => 2");
}

// Hook UIViewController -presentViewController:animated:completion:
static void hooked_presentVC(id self, SEL _cmd, UIViewController *viewControllerToPresent, BOOL animated, id completion) {
    NSString *clsName = NSStringFromClass([viewControllerToPresent class]);
    if ([clsName containsString:@"PresentationHostingController"] ||
        [clsName containsString:@"UIHostingController"] ||
        [clsName containsString:@"SKStore"] ||
        [clsName containsString:@"Paywall"]) {
        kiosker_log([NSString stringWithFormat:@"Blocked present: %@", clsName]);
        return;
    }
    if (orig_presentVC) {
        ((void (*)(id, SEL, UIViewController*, BOOL, id))orig_presentVC)(self, _cmd, viewControllerToPresent, animated, completion);
    }
}

// Hook SKPaymentQueue -addPayment:
static void hooked_addPayment(id self, SEL _cmd, id payment) {
    kiosker_log(@"Blocked SKPaymentQueue addPayment");
    // Do nothing - silently drop the payment
}

#pragma mark - Hook Installation

static void install_hooks(void) {
    kiosker_log(@"=== Kiosker Premium Plugin v1.0 ===");

    // 1. Hook Kiosker.SubscriptionHandler
    Class shClass = NSClassFromString(@"Kiosker.SubscriptionHandler");
    if (shClass) {
        kiosker_log(@"Found Kiosker.SubscriptionHandler");

        // Hook timerTick
        Method mTick = class_getInstanceMethod(shClass, @selector(timerTick));
        if (mTick) {
            orig_timerTick = method_setImplementation(mTick, (IMP)hooked_timerTick);
            kiosker_log(@"Hooked timerTick");
        } else {
            kiosker_log(@"timerTick not found");
        }

        // Hook init
        Method mInit = class_getInstanceMethod(shClass, @selector(init));
        if (mInit) {
            orig_init = method_setImplementation(mInit, (IMP)hooked_init);
            kiosker_log(@"Hooked init");
        }

        // Hook purchases:receivedUpdatedCustomerInfo:
        Method mInfo = class_getInstanceMethod(shClass, @selector(purchases:receivedUpdatedCustomerInfo:));
        if (mInfo) {
            orig_customerInfo = method_setImplementation(mInfo, (IMP)hooked_customerInfo);
            kiosker_log(@"Hooked purchases:receivedUpdatedCustomerInfo:");
        }
    } else {
        kiosker_log(@"Kiosker.SubscriptionHandler NOT FOUND");
    }

    // 2. Hook UIViewController presentViewController
    Class vcClass = [UIViewController class];
    Method mPresent = class_getInstanceMethod(vcClass, @selector(presentViewController:animated:completion:));
    if (mPresent) {
        orig_presentVC = method_setImplementation(mPresent, (IMP)hooked_presentVC);
        kiosker_log(@"Hooked presentViewController");
    }

    // 3. Hook SKPaymentQueue addPayment (prevent real purchase)
    Class skClass = NSClassFromString(@"SKPaymentQueue");
    if (skClass) {
        Method mAdd = class_getInstanceMethod(skClass, @selector(addPayment:));
        if (mAdd) {
            orig_addPayment = method_setImplementation(mAdd, (IMP)hooked_addPayment);
            kiosker_log(@"Hooked SKPaymentQueue addPayment:");
        }
    }

    kiosker_log(@"All hooks installed.");
}

#pragma mark - Constructor

__attribute__((constructor))
static void kiosker_premium_constructor(void) {
    // Delay 2 seconds to ensure App classes are loaded
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        install_hooks();
    });
}
