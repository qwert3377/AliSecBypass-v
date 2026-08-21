// WorkingCopyVIP.mm
// TrollStore 注入用，纯 Runtime Hook，无 Logos %hook
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

// 1. 功能权限检查 — 核心方法，强制返回 YES
static BOOL new_allowedFeature(id self, SEL _cmd, id feature, BOOL missingValue, BOOL allowTrial) {
    return YES;
}

// 2. 是否在试用期内 — 强制返回 YES
static BOOL new_runningTrial(id self, SEL _cmd) {
    return YES;
}

// 3. 试用剩余天数 — 返回一个大正数
static NSInteger new_trialDaysLeft(id self, SEL _cmd) {
    return 999;
}

// 4. 是否允许无限仓库 — 强制返回 YES
static BOOL new_unlimitedReposAllowed(id self, SEL _cmd) {
    return YES;
}

// 5. 是否购买过试用 — 强制返回 YES
static BOOL new_latestTrialPurchased(id self, SEL _cmd) {
    return YES;
}

#pragma mark - 初始化

__attribute__((constructor))
static void wc_vip_init() {
    @autoreleasepool {
        // 延迟执行，确保 PaymentStatus 类已加载
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

            Class paymentStatus = objc_getClass("PaymentStatus");
            if (!paymentStatus) {
                NSLog(@"[WC-VIP] PaymentStatus 类未找到");
                return;
            }

            NSLog(@"[WC-VIP] 开始 Hook PaymentStatus...");

            // Hook allowedFeature:missingValue:allowTrial:
            Method m1 = class_getInstanceMethod(paymentStatus, @selector(allowedFeature:missingValue:allowTrial:));
            if (m1) {
                orig_allowedFeature = method_setImplementation(m1, (IMP)new_allowedFeature);
                NSLog(@"[WC-VIP] ✅ Hooked allowedFeature:missingValue:allowTrial:");
            }

            // Hook runningTrial
            Method m2 = class_getInstanceMethod(paymentStatus, @selector(runningTrial));
            if (m2) {
                orig_runningTrial = method_setImplementation(m2, (IMP)new_runningTrial);
                NSLog(@"[WC-VIP] ✅ Hooked runningTrial");
            }

            // Hook trialDaysLeft
            Method m3 = class_getInstanceMethod(paymentStatus, @selector(trialDaysLeft));
            if (m3) {
                orig_trialDaysLeft = method_setImplementation(m3, (IMP)new_trialDaysLeft);
                NSLog(@"[WC-VIP] ✅ Hooked trialDaysLeft");
            }

            // Hook unlimitedReposAllowedByDownloadDate
            Method m4 = class_getInstanceMethod(paymentStatus, @selector(unlimitedReposAllowedByDownloadDate));
            if (m4) {
                orig_unlimitedReposAllowed = method_setImplementation(m4, (IMP)new_unlimitedReposAllowed);
                NSLog(@"[WC-VIP] ✅ Hooked unlimitedReposAllowedByDownloadDate");
            }

            // Hook latestTrialPurchased
            Method m5 = class_getInstanceMethod(paymentStatus, @selector(latestTrialPurchased));
            if (m5) {
                orig_latestTrialPurchased = method_setImplementation(m5, (IMP)new_latestTrialPurchased);
                NSLog(@"[WC-VIP] ✅ Hooked latestTrialPurchased");
            }

            NSLog(@"[WC-VIP] 🎉 Working Copy VIP 解锁完成");
        });
    }
}
