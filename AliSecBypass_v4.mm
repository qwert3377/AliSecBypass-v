// AliSecBypass_v4.mm
// TrollStore 注入用，纯 Runtime Hook
// 功能：解锁 Working Copy 所有付费功能 + 移除锁图标

#import <objc/runtime.h>
#import <Foundation/Foundation.h>

#pragma mark - PaymentStatus Hooks

static IMP orig_allowedFeature = NULL;
static IMP orig_runningTrial = NULL;
static IMP orig_trialDaysLeft = NULL;
static IMP orig_unlimitedReposAllowed = NULL;
static IMP orig_latestTrialPurchased = NULL;

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

#pragma mark - AppFeature Hooks (控制 UI 锁图标)

static IMP orig_lockedFeatures = NULL;
static IMP orig_quickAllowed = NULL;
static IMP orig_proFeatureTip = NULL;
static IMP orig_upgradeReason = NULL;

// lockedFeatures 返回空数组 = 没有功能被锁定
static id new_lockedFeatures(id self, SEL _cmd) {
    return [NSArray array]; // 空数组
}

// quickAllowedForEnterpriseYear: 返回 YES
static BOOL new_quickAllowed(id self, SEL _cmd, id year) {
    return YES;
}

// proFeatureTip 返回 nil
static id new_proFeatureTip(id self, SEL _cmd) {
    return nil;
}

// upgradeReasonMessage 返回 nil
static id new_upgradeReason(id self, SEL _cmd) {
    return nil;
}

#pragma mark - Hook 执行

static void hookPaymentStatus() {
    Class cls = objc_getClass("PaymentStatus");
    if (!cls) return;

    Method m1 = class_getInstanceMethod(cls, @selector(allowedFeature:missingValue:allowTrial:));
    if (m1 && !orig_allowedFeature) {
        orig_allowedFeature = method_setImplementation(m1, (IMP)new_allowedFeature);
        NSLog(@"[WC-VIP] ✅ PaymentStatus.allowedFeature");
    }

    Method m2 = class_getInstanceMethod(cls, @selector(runningTrial));
    if (m2 && !orig_runningTrial) {
        orig_runningTrial = method_setImplementation(m2, (IMP)new_runningTrial);
        NSLog(@"[WC-VIP] ✅ PaymentStatus.runningTrial");
    }

    Method m3 = class_getInstanceMethod(cls, @selector(trialDaysLeft));
    if (m3 && !orig_trialDaysLeft) {
        orig_trialDaysLeft = method_setImplementation(m3, (IMP)new_trialDaysLeft);
        NSLog(@"[WC-VIP] ✅ PaymentStatus.trialDaysLeft");
    }

    Method m4 = class_getInstanceMethod(cls, @selector(unlimitedReposAllowedByDownloadDate));
    if (m4 && !orig_unlimitedReposAllowed) {
        orig_unlimitedReposAllowed = method_setImplementation(m4, (IMP)new_unlimitedReposAllowed);
        NSLog(@"[WC-VIP] ✅ PaymentStatus.unlimitedReposAllowedByDownloadDate");
    }

    Method m5 = class_getInstanceMethod(cls, @selector(latestTrialPurchased));
    if (m5 && !orig_latestTrialPurchased) {
        orig_latestTrialPurchased = method_setImplementation(m5, (IMP)new_latestTrialPurchased);
        NSLog(@"[WC-VIP] ✅ PaymentStatus.latestTrialPurchased");
    }
}

static void hookAppFeature() {
    Class cls = objc_getClass("AppFeature");
    if (!cls) return;

    Method m1 = class_getInstanceMethod(cls, @selector(lockedFeatures));
    if (m1 && !orig_lockedFeatures) {
        orig_lockedFeatures = method_setImplementation(m1, (IMP)new_lockedFeatures);
        NSLog(@"[WC-VIP] ✅ AppFeature.lockedFeatures -> []");
    }

    Method m2 = class_getInstanceMethod(cls, @selector(quickAllowedForEnterpriseYear:));
    if (m2 && !orig_quickAllowed) {
        orig_quickAllowed = method_setImplementation(m2, (IMP)new_quickAllowed);
        NSLog(@"[WC-VIP] ✅ AppFeature.quickAllowedForEnterpriseYear");
    }

    Method m3 = class_getInstanceMethod(cls, @selector(proFeatureTip));
    if (m3 && !orig_proFeatureTip) {
        orig_proFeatureTip = method_setImplementation(m3, (IMP)new_proFeatureTip);
        NSLog(@"[WC-VIP] ✅ AppFeature.proFeatureTip");
    }

    Method m4 = class_getInstanceMethod(cls, @selector(upgradeReasonMessage));
    if (m4 && !orig_upgradeReason) {
        orig_upgradeReason = method_setImplementation(m4, (IMP)new_upgradeReason);
        NSLog(@"[WC-VIP] ✅ AppFeature.upgradeReasonMessage");
    }
}

#pragma mark - 轮询等待类加载

static void startPolling() {
    static int attempts = 0;
    const int maxAttempts = 30;

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 2.0 * NSEC_PER_SEC, 0);

    dispatch_source_set_event_handler(timer, ^{
        attempts++;

        hookPaymentStatus();
        hookAppFeature();

        // 两个类都 Hook 成功后停止
        if ((orig_allowedFeature && orig_lockedFeatures) || attempts >= maxAttempts) {
            dispatch_source_cancel(timer);
            if (orig_allowedFeature && orig_lockedFeatures) {
                NSLog(@"[WC-VIP] 🎉 全部 Hook 完成，功能已解锁 + 锁图标已移除");
            } else if (attempts >= maxAttempts) {
                NSLog(@"[WC-VIP] ⚠️ 超时，部分 Hook 可能未生效");
            }
        }
    });

    dispatch_resume(timer);
}

#pragma mark - 初始化

__attribute__((constructor))
static void wc_vip_init() {
    @autoreleasepool {
        NSLog(@"[WC-VIP] Tweak 已加载，等待类加载...");

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            startPolling();
        });
    }
}
