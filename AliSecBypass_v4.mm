// AliSecBypass_v4.mm
// TrollStore 注入用，纯 Runtime Hook
// 日志写入 App Documents/wc_vip_log.txt

#import <objc/runtime.h>
#import <Foundation/Foundation.h>

#pragma mark - 文件日志

static NSString *logPath = nil;

static void wcLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    // 同时输出到 NSLog（可能被系统过滤）
    NSLog(@"[WC-VIP] %@", msg);

    // 写入文件
    if (logPath) {
        NSString *line = [NSString stringWithFormat:@"%@ [WC-VIP] %@\n", 
            [NSDate date], msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        } else {
            [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }
}

static void initLog() {
    NSString *home = NSHomeDirectory();
    NSString *docs = [home stringByAppendingPathComponent:@"Documents"];
    logPath = [docs stringByAppendingPathComponent:@"wc_vip_log.txt"];

    // 确保 Documents 目录存在
    [[NSFileManager defaultManager] createDirectoryAtPath:docs 
        withIntermediateDirectories:YES attributes:nil error:nil];

    // 清空旧日志
    [@"" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    wcLog(@"日志初始化完成: %@", logPath);
}

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

#pragma mark - AppFeature Hooks

static IMP orig_lockedFeatures = NULL;
static IMP orig_quickAllowed = NULL;
static IMP orig_proFeatureTip = NULL;
static IMP orig_upgradeReason = NULL;

static id new_lockedFeatures(id self, SEL _cmd) {
    return [NSArray array];
}

static BOOL new_quickAllowed(id self, SEL _cmd, id year) {
    return YES;
}

static id new_proFeatureTip(id self, SEL _cmd) {
    return nil;
}

static id new_upgradeReason(id self, SEL _cmd) {
    return nil;
}

#pragma mark - Payment Hooks

static IMP orig_trialCanBeStarted = NULL;
static IMP orig_canPurchasePush = NULL;
static IMP orig_receiptRead = NULL;
static IMP orig_purchasesBeingMade = NULL;

static BOOL new_trialCanBeStarted(id self, SEL _cmd) {
    return YES;
}

static BOOL new_canPurchasePush(id self, SEL _cmd) {
    return YES;
}

static BOOL new_receiptRead(id self, SEL _cmd) {
    return YES;
}

static BOOL new_purchasesBeingMade(id self, SEL _cmd) {
    return NO;
}

#pragma mark - Hook 执行

static void hookPaymentStatus() {
    Class cls = objc_getClass("PaymentStatus");
    if (!cls) return;

    Method m1 = class_getInstanceMethod(cls, @selector(allowedFeature:missingValue:allowTrial:));
    if (m1 && !orig_allowedFeature) {
        orig_allowedFeature = method_setImplementation(m1, (IMP)new_allowedFeature);
        wcLog(@"✅ PaymentStatus.allowedFeature");
    }

    Method m2 = class_getInstanceMethod(cls, @selector(runningTrial));
    if (m2 && !orig_runningTrial) {
        orig_runningTrial = method_setImplementation(m2, (IMP)new_runningTrial);
        wcLog(@"✅ PaymentStatus.runningTrial");
    }

    Method m3 = class_getInstanceMethod(cls, @selector(trialDaysLeft));
    if (m3 && !orig_trialDaysLeft) {
        orig_trialDaysLeft = method_setImplementation(m3, (IMP)new_trialDaysLeft);
        wcLog(@"✅ PaymentStatus.trialDaysLeft");
    }

    Method m4 = class_getInstanceMethod(cls, @selector(unlimitedReposAllowedByDownloadDate));
    if (m4 && !orig_unlimitedReposAllowed) {
        orig_unlimitedReposAllowed = method_setImplementation(m4, (IMP)new_unlimitedReposAllowed);
        wcLog(@"✅ PaymentStatus.unlimitedReposAllowedByDownloadDate");
    }

    Method m5 = class_getInstanceMethod(cls, @selector(latestTrialPurchased));
    if (m5 && !orig_latestTrialPurchased) {
        orig_latestTrialPurchased = method_setImplementation(m5, (IMP)new_latestTrialPurchased);
        wcLog(@"✅ PaymentStatus.latestTrialPurchased");
    }
}

static void hookAppFeature() {
    Class cls = objc_getClass("AppFeature");
    if (!cls) return;

    Method m1 = class_getInstanceMethod(cls, @selector(lockedFeatures));
    if (m1 && !orig_lockedFeatures) {
        orig_lockedFeatures = method_setImplementation(m1, (IMP)new_lockedFeatures);
        wcLog(@"✅ AppFeature.lockedFeatures -> []");
    }

    Method m2 = class_getInstanceMethod(cls, @selector(quickAllowedForEnterpriseYear:));
    if (m2 && !orig_quickAllowed) {
        orig_quickAllowed = method_setImplementation(m2, (IMP)new_quickAllowed);
        wcLog(@"✅ AppFeature.quickAllowedForEnterpriseYear");
    }

    Method m3 = class_getInstanceMethod(cls, @selector(proFeatureTip));
    if (m3 && !orig_proFeatureTip) {
        orig_proFeatureTip = method_setImplementation(m3, (IMP)new_proFeatureTip);
        wcLog(@"✅ AppFeature.proFeatureTip");
    }

    Method m4 = class_getInstanceMethod(cls, @selector(upgradeReasonMessage));
    if (m4 && !orig_upgradeReason) {
        orig_upgradeReason = method_setImplementation(m4, (IMP)new_upgradeReason);
        wcLog(@"✅ AppFeature.upgradeReasonMessage");
    }
}

static void hookPayment() {
    Class cls = objc_getClass("Payment");
    if (!cls) return;

    Method m1 = class_getInstanceMethod(cls, @selector(trialCanBeStarted));
    if (m1 && !orig_trialCanBeStarted) {
        orig_trialCanBeStarted = method_setImplementation(m1, (IMP)new_trialCanBeStarted);
        wcLog(@"✅ Payment.trialCanBeStarted");
    }

    Method m2 = class_getInstanceMethod(cls, @selector(canPurchasePush));
    if (m2 && !orig_canPurchasePush) {
        orig_canPurchasePush = method_setImplementation(m2, (IMP)new_canPurchasePush);
        wcLog(@"✅ Payment.canPurchasePush");
    }

    Method m3 = class_getInstanceMethod(cls, @selector(receiptRead));
    if (m3 && !orig_receiptRead) {
        orig_receiptRead = method_setImplementation(m3, (IMP)new_receiptRead);
        wcLog(@"✅ Payment.receiptRead");
    }

    Method m4 = class_getInstanceMethod(cls, @selector(purchasesBeingMade));
    if (m4 && !orig_purchasesBeingMade) {
        orig_purchasesBeingMade = method_setImplementation(m4, (IMP)new_purchasesBeingMade);
        wcLog(@"✅ Payment.purchasesBeingMade");
    }
}

#pragma mark - 轮询

static void startPolling() {
    static int attempts = 0;
    const int maxAttempts = 600;

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 0.5 * NSEC_PER_SEC, 0);

    dispatch_source_set_event_handler(timer, ^{
        attempts++;

        hookPaymentStatus();
        hookAppFeature();
        hookPayment();

        BOOL paymentStatusDone = orig_allowedFeature != NULL;
        BOOL appFeatureDone = orig_lockedFeatures != NULL;
        BOOL paymentDone = orig_trialCanBeStarted != NULL;

        if ((paymentStatusDone && appFeatureDone && paymentDone) || attempts >= maxAttempts) {
            dispatch_source_cancel(timer);
            if (paymentStatusDone && appFeatureDone && paymentDone) {
                wcLog(@"🎉 全部 Hook 完成");
            } else {
                wcLog(@"⚠️ 轮询结束，PaymentStatus=%@ AppFeature=%@ Payment=%@",
                      paymentStatusDone?@"OK":@"FAIL",
                      appFeatureDone?@"OK":@"FAIL",
                      paymentDone?@"OK":@"FAIL");
            }
        }
    });

    dispatch_resume(timer);
}

#pragma mark - 初始化

__attribute__((constructor))
static void wc_vip_init() {
    @autoreleasepool {
        initLog();
        wcLog(@"Tweak 已加载，开始 Hook...");

        hookPaymentStatus();
        hookAppFeature();
        hookPayment();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            startPolling();
        });
    }
}
