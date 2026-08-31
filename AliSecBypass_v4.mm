// kiosker.mm - Kiosker TrollStore Plugin
// Theos .mm file for TrollStore injection
// Compile with Theos: make package

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

#define STATE_SUBSCRIBED 2

static void forceState(id inst) {
    if (!inst) return;
    void *ptr = (__bridge void *)inst;
    if (!ptr) return;
    @try {
        uint8_t *statePtr = (uint8_t *)ptr + 32;
        *statePtr = STATE_SUBSCRIBED;
    } @catch (NSException *e) {}
}

static uint8_t readState(id inst) {
    if (!inst) return 255;
    void *ptr = (__bridge void *)inst;
    if (!ptr) return 255;
    @try {
        uint8_t *statePtr = (uint8_t *)ptr + 32;
        return *statePtr;
    } @catch (NSException *e) { return 255; }
}

static void triggerTimerTick(id inst) {
    if (!inst) return;
    Class cls = NSClassFromString(@"Kiosker.SubscriptionHandler");
    if (!cls) return;
    SEL sel = NSSelectorFromString(@"timerTick");
    if (!sel) return;
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    @try {
        [inst performSelector:sel];
    } @catch (NSException *e) {}
    #pragma clang diagnostic pop
}

// ========== UISwitch helpers ==========
static void enableSwitch(UISwitch *sw) {
    if (!sw) return;
    @try {
        [sw setEnabled:YES];
        if (![sw isOn]) {
            [sw setOn:YES animated:NO];
        }
    } @catch (NSException *e) {}
}

static void scanViewForSwitches(UIView *view, int depth) {
    if (!view || depth > 30) return;
    if ([view isKindOfClass:[UISwitch class]]) {
        enableSwitch((UISwitch *)view);
    }
    NSArray *subs = [view subviews];
    for (UIView *sub in subs) {
        scanViewForSwitches(sub, depth + 1);
    }
}

static void scanAllWindows() {
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        if (!app) return;
        NSArray *windows = [app windows];
        for (UIWindow *win in windows) {
            scanViewForSwitches(win, 0);
        }
    } @catch (NSException *e) {}
}

// ========== Hook helpers ==========
static void hookClassMethod(const char *clsName, const char *selName, IMP newImp, IMP *origImp) {
    Class cls = objc_getClass(clsName);
    if (!cls) return;
    SEL sel = sel_getUid(selName);
    if (!sel) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (origImp) {
        *origImp = method_getImplementation(m);
        method_setImplementation(m, newImp);
    } else {
        MSHookMessageEx(cls, sel, newImp, NULL);
    }
}

// ========== SubscriptionHandler hooks ==========
static IMP orig_SH_init = NULL;
id hook_SH_init(id self, SEL _cmd) {
    id result = ((id (*)(id, SEL))orig_SH_init)(self, _cmd);
    forceState(result);
    return result;
}

static IMP orig_SH_timerTick = NULL;
void hook_SH_timerTick(id self, SEL _cmd) {
    forceState(self);
    ((void (*)(id, SEL))orig_SH_timerTick)(self, _cmd);
    // onLeave: check again
    if (readState(self) != STATE_SUBSCRIBED) {
        forceState(self);
    }
}

static IMP orig_SH_rcCallback = NULL;
void hook_SH_rcCallback(id self, SEL _cmd, id purchases, id customerInfo) {
    forceState(self);
    ((void (*)(id, SEL, id, id))orig_SH_rcCallback)(self, _cmd, purchases, customerInfo);
    forceState(self);
    triggerTimerTick(self);
}

// ========== RevenueCat hooks ==========
static IMP orig_RC_entitlements = NULL;
id hook_RC_entitlements(id self, SEL _cmd) {
    NSMutableDictionary *fake = [NSMutableDictionary dictionary];
    [fake setObject:@"pro" forKey:@"premium"];
    return fake;
}

static IMP orig_RC_activeSubscriptions = NULL;
id hook_RC_activeSubscriptions(id self, SEL _cmd) {
    return [NSSet setWithObject:@"premium_monthly"];
}

static IMP orig_RCEntitlement_isActive = NULL;
BOOL hook_RCEntitlement_isActive(id self, SEL _cmd) {
    return YES;
}

// ========== UIViewController viewDidAppear ==========
static IMP orig_VC_viewDidAppear = NULL;
void hook_VC_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))orig_VC_viewDidAppear)(self, _cmd, animated);

    NSString *clsName = NSStringFromClass([self class]);
    if ([clsName rangeOfString:@"HostingController"].location != NSNotFound ||
        [clsName rangeOfString:@"HostingView"].location != NSNotFound) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            scanAllWindows();
            // Also fix SubscriptionHandler state
            Class shClass = NSClassFromString(@"Kiosker.SubscriptionHandler");
            if (shClass) {
                unsigned int count = 0;
                id *instances = (id *)objc_copyClassInstances((__bridge Class _Nonnull)(shClass), &count);
                // Note: objc_copyClassInstances is not public API, use alternative
            }
        });
    }
}

// ========== UIControl sendAction ==========
static IMP orig_Control_sendAction = NULL;
void hook_Control_sendAction(id self, SEL _cmd, SEL action, id target, UIEvent *event) {
    ((void (*)(id, SEL, SEL, id, UIEvent *))orig_Control_sendAction)(self, _cmd, action, target, event);
    if ([self isKindOfClass:[UISwitch class]]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            enableSwitch((UISwitch *)self);
        });
    }
}

// ========== Constructor ==========
__attribute__((constructor))
static void kioskerInit() {
    NSLog(@"[KIOSKER] Plugin loading...");

    // Hook SubscriptionHandler
    Class shClass = NSClassFromString(@"Kiosker.SubscriptionHandler");
    if (shClass) {
        Method mInit = class_getInstanceMethod(shClass, @selector(init));
        if (mInit) {
            orig_SH_init = method_getImplementation(mInit);
            method_setImplementation(mInit, (IMP)hook_SH_init);
        }

        Method mTick = class_getInstanceMethod(shClass, @selector(timerTick));
        if (mTick) {
            orig_SH_timerTick = method_getImplementation(mTick);
            method_setImplementation(mTick, (IMP)hook_SH_timerTick);
        }

        Method mRC = class_getInstanceMethod(shClass, @selector(purchases:receivedUpdatedCustomerInfo:));
        if (mRC) {
            orig_SH_rcCallback = method_getImplementation(mRC);
            method_setImplementation(mRC, (IMP)hook_SH_rcCallback);
        }

        // Fix existing instance
        @try {
            id existing = nil;
            // Try to find existing instance via notification center or shared instance
            // If not available, timerTick will catch it
        } @catch (NSException *e) {}
    }

    // Hook RevenueCat
    Class rcClass = NSClassFromString(@"RCCustomerInfo");
    if (rcClass) {
        Method mEnt = class_getInstanceMethod(rcClass, @selector(entitlements));
        if (mEnt) {
            orig_RC_entitlements = method_getImplementation(mEnt);
            method_setImplementation(mEnt, (IMP)hook_RC_entitlements);
        }

        Method mSub = class_getInstanceMethod(rcClass, @selector(activeSubscriptions));
        if (mSub) {
            orig_RC_activeSubscriptions = method_getImplementation(mSub);
            method_setImplementation(mSub, (IMP)hook_RC_activeSubscriptions);
        }
    }

    Class rcEntClass = NSClassFromString(@"RCEntitlementInfo");
    if (rcEntClass) {
        Method mActive = class_getInstanceMethod(rcEntClass, @selector(isActive));
        if (mActive) {
            orig_RCEntitlement_isActive = method_getImplementation(mActive);
            method_setImplementation(mActive, (IMP)hook_RCEntitlement_isActive);
        }
    }

    // Hook UIViewController
    Class vcClass = [UIViewController class];
    Method mAppear = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    if (mAppear) {
        orig_VC_viewDidAppear = method_getImplementation(mAppear);
        method_setImplementation(mAppear, (IMP)hook_VC_viewDidAppear);
    }

    // Hook UIControl
    Class ctrlClass = [UIControl class];
    Method mSend = class_getInstanceMethod(ctrlClass, @selector(sendAction:to:forEvent:));
    if (mSend) {
        orig_Control_sendAction = method_getImplementation(mSend);
        method_setImplementation(mSend, (IMP)hook_Control_sendAction);
    }

    NSLog(@"[KIOSKER] Plugin loaded.");
}
