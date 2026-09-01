//
//  Kiosker_Premium_Unlock.mm
//  TrollStore Injection Plugin for Kiosker 26.4.2
//  Strategy: Patch _state ivar to 1 during SubscriptionHandler init
//

#import <objc/runtime.h>
#import <Foundation/Foundation.h>

static IMP orig_init = NULL;

static id kiosker_init(id self, SEL _cmd) {
    self = orig_init(self, _cmd);
    if (self) {
        // _state ivar is at offset +24 (confirmed via Frida ivar dump)
        uint8_t *base = (uint8_t *)self;
        base[24] = 1;  // 1 = subscribed
    }
    return self;
}

static void hook_subscription_handler() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"_TtC7Kiosker19SubscriptionHandler");
        if (!cls) {
            NSLog(@"[KioskerPremium] SubscriptionHandler not found");
            return;
        }

        Method m = class_getInstanceMethod(cls, @selector(init));
        if (!m) {
            NSLog(@"[KioskerPremium] init not found");
            return;
        }

        orig_init = method_getImplementation(m);
        method_setImplementation(m, (IMP)kiosker_init);
        NSLog(@"[KioskerPremium] Hooked SubscriptionHandler init");
    });
}

__attribute__((constructor))
static void constructor() {
    @autoreleasepool {
        // Delay 1s to ensure Swift runtime has loaded the class
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            hook_subscription_handler();
        });
    }
}
