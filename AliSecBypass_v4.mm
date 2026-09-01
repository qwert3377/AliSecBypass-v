//
//  Kiosker_Premium_Unlock.mm
//  TrollStore Injection Plugin for Kiosker 26.4.2
//  ARC-compatible, no Logos
//

#import <objc/runtime.h>
#import <Foundation/Foundation.h>

// Use proper function pointer type for init
static id (*orig_init)(id, SEL) = NULL;

static id kiosker_init(id self, SEL _cmd) {
    self = orig_init(self, _cmd);
    if (self) {
        // ARC disallows direct cast id -> uint8_t*, use void* bridge
        void *ptr = (__bridge void *)self;
        uint8_t *base = (uint8_t *)ptr;
        base[24] = 1;  // _state = 1 (subscribed)
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

        orig_init = (id (*)(id, SEL))method_getImplementation(m);
        method_setImplementation(m, (IMP)kiosker_init);
        NSLog(@"[KioskerPremium] Hooked SubscriptionHandler init");
    });
}

__attribute__((constructor))
static void constructor() {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            hook_subscription_handler();
        });
    }
}
