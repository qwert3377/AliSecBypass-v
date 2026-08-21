// AliSecBypass_v4.mm
// TrollStore 注入用，纯 Runtime Hook
// 功能：解锁 Working Copy 所有付费功能

#import <objc/runtime.h>
#import <Foundation/Foundation.h>

#pragma mark - 原始 IMP 备份

static IMP orig_allowedFeature = NULL;
static IMP orig_runningTrial = NULL;
static IMP orig_trialDaysLeft = NULL;
static IMP orig_unlimitedReposAllowed = NULL;
static IMP orig_latestTrialPurchased = NULL;

#pragma mark - Hook 实现

static BOOL new_allowedFeature(id self, SEL _cmd, id feature, BOOL missingValue, BOOL allowTrial) {
    return YES;
}

static BOOL new_runningTrial(id self, SEL _cmd) {
    return YES;
}

static NSInteger new_trialDaysLeft(id self, SEL _cmd) {
    return 999;
}

static BOOL new_unlimitedReposAllowed(id self, SEL _cmd) {
    return YES;
}

static BOOL new_latestTrialPurchased(id self, SEL _cmd) {
    return YES;
}

#pragma mark - Hook 执行

static void doHook() {
    Class paymentStatus = objc_getClass("PaymentStatus");
    if (!paymentStatus) {
        return;
    }

    static BOOL hooked = NO;
    if (hooked) return;
    hooked = YES;

    NSLog(@"[WC-VIP] PaymentStatus 已找到，开始 Hook...");

    Method m1 = class_getInstanceMethod(paymentStatus, @selector(allowedFeature:missingValue:allowTrial:));
    if (m1 && !orig_allowedFeature) {
        orig_allowedFeature = method_setImplementation(m1, (IMP)new_allowedFeature);
        NSLog(@"[WC-VIP] ✅ allowedFeature:missingValue:allowTrial:");
    }

    Method m2 = class_getInstanceMethod(paymentStatus, @selector(runningTrial));
    if (m2 && !orig_runningTrial) {
        orig_runningTrial = method_setImplementation(m2, (IMP)new_runningTrial);
        NSLog(@"[WC-VIP] ✅ runningTrial");
    }

    Method m3 = class_getInstanceMethod(paymentStatus, @selector(trialDaysLeft));
    if (m3 && !orig_trialDaysLeft) {
        orig_trialDaysLeft = method_setImplementation(m3, (IMP)new_trialDaysLeft);
        NSLog(@"[WC-VIP] ✅ trialDaysLeft");
    }

    Method m4 = class_getInstanceMethod(paymentStatus, @selector(unlimitedReposAllowedByDownloadDate));
    if (m4 && !orig_unlimitedReposAllowed) {
        orig_unlimitedReposAllowed = method_setImplementation(m4, (IMP)new_unlimitedReposAllowed);
        NSLog(@"[WC-VIP] ✅ unlimitedReposAllowedByDownloadDate");
    }

    Method m5 = class_getInstanceMethod(paymentStatus, @selector(latestTrialPurchased));
    if (m5 && !orig_latestTrialPurchased) {
        orig_latestTrialPurchased = method_setImplementation(m5, (IMP)new_latestTrialPurchased);
        NSLog(@"[WC-VIP] ✅ latestTrialPurchased");
    }

    NSLog(@"[WC-VIP] 🎉 Hook 完成");
}

#pragma mark - 轮询等待类加载

static void startPolling() {
    static int attempts = 0;
    const int maxAttempts = 30;

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 2.0 * NSEC_PER_SEC, 0);

    dispatch_source_set_event_handler(timer, ^{
        attempts++;
        doHook();

        if (orig_allowedFeature || attempts >= maxAttempts) {
            dispatch_source_cancel(timer);
            if (!orig_allowedFeature) {
                NSLog(@"[WC-VIP] ⚠️ 超时未找到 PaymentStatus");
            }
        }
    });

    dispatch_resume(timer);
}

#pragma mark - 初始化

__attribute__((constructor))
static void wc_vip_init() {
    @autoreleasepool {
        NSLog(@"[WC-VIP] Tweak 已加载，等待 PaymentStatus 类...");

        // 延迟 3 秒后开始轮询（等 App 启动完成）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            startPolling();
        });
    }
}
