//
//  Kiosker_Premium_Unlock.mm
//  TrollStore Injection Plugin for Kiosker 26.4.2
//  Logs to app Documents directory
//  Blocks purchase popups by intercepting view controller presentation
//

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static id (*orig_init)(id, SEL) = NULL;
static NSString *logPath = nil;

static void fileLog(NSString *fmt, ...) {
    if (!logPath) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docDir = [paths firstObject];
        logPath = [docDir stringByAppendingPathComponent:@"kiosker_premium.log"];
    }
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    NSLog(@"[KioskerPremium] %@", msg);
}

// ==================== 1. SubscriptionHandler init patch ====================

static id kiosker_init(id self, SEL _cmd) {
    fileLog(@"init called self=%p", self);
    self = orig_init(self, _cmd);
    if (self) {
        uint8_t *base = (uint8_t *)(__bridge void *)self;
        uint8_t old = base[24];
        base[24] = 1;
        fileLog(@"PATCHED _state %d->1 offset=+24", old);
    }
    return self;
}

// ==================== 2. Block purchase popups ====================

// Hook UIViewController presentViewController to block purchase sheets
static void (*orig_present)(id, SEL, id, BOOL, id) = NULL;
static void hook_present(id self, SEL _cmd, UIViewController *vc, BOOL animated, id completion) {
    NSString *className = NSStringFromClass([vc class]);
    fileLog(@"presentViewController: %@", className);

    // Block known purchase/subscription view controllers
    NSArray *blocked = @[@"SKStoreProductViewController",
                         @"RCPaywallViewController",
                         @"PaywallViewController",
                         @"SubscriptionViewController",
                         @"PurchaseViewController",
                         @"UIAlertController"];

    for (NSString *blockedClass in blocked) {
        if ([className isEqualToString:blockedClass] || [vc isKindOfClass:NSClassFromString(blockedClass)]) {
            fileLog(@"BLOCKED popup: %@", className);
            if (completion) {
                void (^block)(void) = completion;
                block();
            }
            return;
        }
    }

    // Also block if title contains purchase keywords
    if ([vc respondsToSelector:@selector(title)]) {
        NSString *title = [(UIViewController *)vc title];
        if (title && ([title rangeOfString:@"订阅"].location != NSNotFound ||
                      [title rangeOfString:@"Premium"].location != NSNotFound ||
                      [title rangeOfString:@"购买"].location != NSNotFound ||
                      [title rangeOfString:@"Upgrade"].location != NSNotFound)) {
            fileLog(@"BLOCKED popup by title: %@", title);
            if (completion) {
                void (^block)(void) = completion;
                block();
            }
            return;
        }
    }

    orig_present(self, _cmd, vc, animated, completion);
}

// ==================== 3. Hook RevenueCat purchases ====================

static void (*orig_purchase)(id, SEL, id, id) = NULL;
static void hook_purchase(id self, SEL _cmd, id product, id completion) {
    fileLog(@"BLOCKED RevenueCat purchase: %@", product);
    if (completion) {
        // Return fake success
        void (^block)(id, id, id, BOOL) = completion;
        block(nil, nil, nil, YES);
    }
}

// ==================== 4. Hook SKPaymentQueue ====================

static void (*orig_addPayment)(id, SEL, id) = NULL;
static void hook_addPayment(id self, SEL _cmd, id payment) {
    fileLog(@"BLOCKED SKPaymentQueue addPayment");
}

// ==================== Constructor ====================

static void doHook() {
    // Hook SubscriptionHandler init
    Class subCls = NSClassFromString(@"_TtC7Kiosker19SubscriptionHandler");
    if (subCls) {
        Method m = class_getInstanceMethod(subCls, @selector(init));
        if (m) {
            IMP cur = method_getImplementation(m);
            if (cur != (IMP)kiosker_init) {
                orig_init = (id (*)(id, SEL))cur;
                method_setImplementation(m, (IMP)kiosker_init);
                fileLog(@"HOOKED SubscriptionHandler.init");
            }
        }
    } else {
        fileLog(@"SubscriptionHandler not found yet");
    }

    // Hook UIViewController presentViewController
    Class vcCls = [UIViewController class];
    Method pm = class_getInstanceMethod(vcCls, @selector(presentViewController:animated:completion:));
    if (pm) {
        IMP cur = method_getImplementation(pm);
        if (cur != (IMP)hook_present) {
            orig_present = (void (*)(id, SEL, id, BOOL, id))cur;
            method_setImplementation(pm, (IMP)hook_present);
            fileLog(@"HOOKED UIViewController.presentViewController");
        }
    }

    // Hook RCPurchases purchase methods
    Class rcCls = NSClassFromString(@"RCPurchases");
    if (rcCls) {
        Method pm1 = class_getInstanceMethod(rcCls, NSSelectorFromString(@"purchaseProduct:withCompletion:"));
        if (pm1) {
            IMP cur = method_getImplementation(pm1);
            if (cur != (IMP)hook_purchase) {
                orig_purchase = (void (*)(id, SEL, id, id))cur;
                method_setImplementation(pm1, (IMP)hook_purchase);
                fileLog(@"HOOKED RCPurchases.purchaseProduct");
            }
        }
    }

    // Hook SKPaymentQueue addPayment
    Class skCls = NSClassFromString(@"SKPaymentQueue");
    if (skCls) {
        Method am = class_getInstanceMethod(skCls, @selector(addPayment:));
        if (am) {
            IMP cur = method_getImplementation(am);
            if (cur != (IMP)hook_addPayment) {
                orig_addPayment = (void (*)(id, SEL, id))cur;
                method_setImplementation(am, (IMP)hook_addPayment);
                fileLog(@"HOOKED SKPaymentQueue.addPayment");
            }
        }
    }
}

__attribute__((constructor))
static void constructor() {
    @autoreleasepool {
        fileLog(@"=== constructor ===");
        doHook();

        // Retry if class not loaded yet
        if (!NSClassFromString(@"_TtC7Kiosker19SubscriptionHandler")) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                for (int i = 0; i < 20; i++) {
                    [NSThread sleepForTimeInterval:0.5];
                    doHook();
                    if (NSClassFromString(@"_TtC7Kiosker19SubscriptionHandler")) break;
                }
            });
        }
    }
}
