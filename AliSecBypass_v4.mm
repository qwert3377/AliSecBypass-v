//
//  BaiduPan_VIP_ExperienceTrigger.mm
//  TrollStore inject plugin
//  v8 - VIP Core + Experience Trigger merged
//  No float button | Auto push download page | Auto trigger every 59s
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ============================================================
// VIP Core - Static Variables
// ============================================================
static NSArray *kAuthKeys = nil;
static NSArray *kExpireKeys = nil;
static NSArray *kLevelKeys = nil;
static NSArray *kUDKeys = nil;

// ============================================================
// Experience Trigger - Static Variables
// ============================================================
static NSString *const kLogFile = @"trigger.log";
static NSMutableArray *gInstances = nil;
static id (*orig_init)(id self, SEL _cmd);
static NSTimer *gAutoTimer = nil;
static id gTimerTarget = nil;

// ============================================================
// Forward Declarations
// ============================================================
static NSDictionary *patchDictionary(NSDictionary *dict);
static void doTrigger(void);

// ============================================================
// 1. Log
// ============================================================
static void logMsg(NSString *msg) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = paths[0];
    NSString *path = [doc stringByAppendingPathComponent:kLogFile];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"HH:mm:ss"];
    NSString *ts = [fmt stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

// ============================================================
// 2. Get Key Window
// ============================================================
static UIWindow* getKeyWindow(void) {
    UIWindow *result = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in ws.windows) {
                        if (w.isKeyWindow) { result = w; break; }
                    }
                    if (result) break;
                }
            }
        }
        if (!result) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    for (UIWindow *w in ws.windows) {
                        if (w.isKeyWindow) { result = w; break; }
                    }
                    if (result) break;
                }
            }
        }
    }
    return result;
}

// ============================================================
// 3. Get Navigation Controller
// ============================================================
static UINavigationController* getNavController(void) {
    UIWindow *kw = getKeyWindow();
    if (!kw) return nil;
    UIViewController *root = kw.rootViewController;
    if ([root isKindOfClass:[UINavigationController class]]) {
        return (UINavigationController *)root;
    }
    if ([root respondsToSelector:@selector(navigationController)]) {
        return [root navigationController];
    }
    return nil;
}

// ============================================================
// 4. VIP - Key Match
// ============================================================
static BOOL keyMatch(NSString *key, NSArray *list) {
    NSString *kl = [key lowercaseString];
    for (NSString *v in list) {
        NSString *vl = [v lowercaseString];
        if ([kl isEqualToString:vl] || [kl containsString:vl]) return YES;
    }
    return NO;
}

// ============================================================
// 5. VIP - Patch Recursively
// ============================================================
static id patchRecursively(id obj) {
    if (!obj) return nil;
    NSDictionary *patched = patchDictionary(obj);
    if (patched) return patched;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)obj;
        NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:d];
        BOOL modified = NO;
        for (NSString *key in d.allKeys) {
            id v = d[key];
            id nv = patchRecursively(v);
            if (nv) { m[key] = nv; modified = YES; }
        }
        return modified ? m : nil;
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)obj;
        NSMutableArray *m = [NSMutableArray arrayWithArray:arr];
        BOOL modified = NO;
        for (NSUInteger i = 0; i < m.count; i++) {
            id np = patchRecursively(m[i]);
            if (np) { m[i] = np; modified = YES; }
        }
        return modified ? m : nil;
    }
    return nil;
}

// ============================================================
// 6. VIP - Patch Dictionary
// ============================================================
static NSDictionary *patchDictionary(NSDictionary *dict) {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) return nil;
    BOOL need = NO;
    for (NSString *key in dict.allKeys) {
        NSString *kl = [key lowercaseString];
        id v = dict[key];
        if (!v) continue;
        if ((keyMatch(kl, kAuthKeys) && [v isKindOfClass:[NSNumber class]] && [v intValue] == 0) ||
            (keyMatch(kl, kExpireKeys) && ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]])) ||
            (keyMatch(kl, kLevelKeys) && [v isKindOfClass:[NSNumber class]] && [v intValue] >= 0 && [v intValue] < 8))
            need = YES;
    }
    if (!need) return nil;
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:dict];
    for (NSString *key in dict.allKeys) {
        NSString *kl = [key lowercaseString];
        id v = dict[key];
        if (!v) continue;
        if (keyMatch(kl, kAuthKeys)) {
            if ([v isKindOfClass:[NSNumber class]] && [v intValue] == 0) {
                m[key] = @1;
            } else if ([v isKindOfClass:[NSString class]] && [v isEqualToString:@"0"]) {
                m[key] = @"1";
            }
        } else if (keyMatch(kl, kExpireKeys)) {
            if ([v isKindOfClass:[NSString class]]) {
                m[key] = @"2099-12-31";
            } else if ([v isKindOfClass:[NSNumber class]]) {
                m[key] = @(4102444799000LL);
            }
        } else if (keyMatch(kl, kLevelKeys)) {
            if ([v isKindOfClass:[NSNumber class]]) {
                int iv = [v intValue];
                if (iv >= 0 && iv < 8) m[key] = @8;
            } else if ([v isKindOfClass:[NSString class]]) {
                NSString *s = (NSString *)v;
                if ([@[@"0",@"1",@"2",@"3",@"4",@"5",@"6",@"7"] containsObject:s]) {
                    m[key] = @"8";
                }
            }
        }
    }
    return m;
}

// ============================================================
// 7. VIP Hook - NSJSONSerialization
// ============================================================
static id (*orig_JSONObjectWithData)(Class cls, SEL sel, NSData *data, NSJSONReadingOptions opt, NSError **error);
static id hook_JSONObjectWithData(Class cls, SEL sel, NSData *data, NSJSONReadingOptions opt, NSError **error) {
    id result = orig_JSONObjectWithData(cls, sel, data, opt, error);
    if (!result || ![result isKindOfClass:[NSDictionary class]]) return result;
    id patched = patchRecursively(result);
    return patched ? patched : result;
}

// ============================================================
// 8. VIP Hook - NSUserDefaults
// ============================================================
static BOOL (*orig_boolForKey)(NSUserDefaults *self, SEL sel, NSString *key);
static BOOL hook_boolForKey(NSUserDefaults *self, SEL sel, NSString *key) {
    for (NSString *k in kUDKeys) {
        if ([k isEqualToString:key]) return YES;
    }
    return orig_boolForKey(self, sel, key);
}

static NSInteger (*orig_integerForKey)(NSUserDefaults *self, SEL sel, NSString *key);
static NSInteger hook_integerForKey(NSUserDefaults *self, SEL sel, NSString *key) {
    NSInteger result = orig_integerForKey(self, sel, key);
    BOOL hit = NO;
    for (NSString *k in kUDKeys) {
        if ([k isEqualToString:key]) { hit = YES; break; }
    }
    if (!hit && keyMatch(key, kLevelKeys)) hit = YES;
    if (hit && result >= 0 && result < 8) return 8;
    return result;
}

static NSString *(*orig_stringForKey)(NSUserDefaults *self, SEL sel, NSString *key);
static NSString *hook_stringForKey(NSUserDefaults *self, SEL sel, NSString *key) {
    NSString *result = orig_stringForKey(self, sel, key);
    if (!result) return result;
    BOOL hit = NO;
    for (NSString *k in kUDKeys) {
        if ([k isEqualToString:key]) { hit = YES; break; }
    }
    if (!hit && keyMatch(key, kLevelKeys)) hit = YES;
    if (hit && [@[@"0",@"1",@"2",@"3",@"4",@"5",@"6",@"7"] containsObject:result]) return @"8";
    return result;
}

static id (*orig_objectForKey)(NSUserDefaults *self, SEL sel, NSString *key);
static id hook_objectForKey(NSUserDefaults *self, SEL sel, NSString *key) {
    id result = orig_objectForKey(self, sel, key);
    if (!result) return result;
    BOOL hit = NO;
    for (NSString *k in kUDKeys) {
        if ([k isEqualToString:key]) { hit = YES; break; }
    }
    if (!hit && keyMatch(key, kLevelKeys)) hit = YES;
    if (!hit) return result;
    if ([result isKindOfClass:[NSNumber class]]) {
        int iv = [(NSNumber *)result intValue];
        if (iv >= 0 && iv < 8) return @8;
    } else if ([result isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)result;
        if ([@[@"0",@"1",@"2",@"3",@"4",@"5",@"6",@"7"] containsObject:s]) return @"8";
    }
    return result;
}

// ============================================================
// 9. VIP Hook - UILabel
// ============================================================
static void (*orig_setText)(UILabel *self, SEL sel, NSString *text);
static void hook_setText(UILabel *self, SEL sel, NSString *text) {
    if (text) {
        if ([text containsString:@"立即开通"] || [text containsString:@"尚未开通"] ||
            [text containsString:@"未开通"] || [text containsString:@"非会员"]) {
            text = @"VIP会员已开通";
        }
    }
    orig_setText(self, sel, text);
}

// ============================================================
// 10. Experience Trigger - Hook init
// ============================================================
static id hook_init(id self, SEL _cmd) {
    id result = orig_init(self, _cmd);
    if (!gInstances) {
        gInstances = [[NSMutableArray alloc] init];
    }
    [gInstances addObject:result];
    logMsg([NSString stringWithFormat:@"capture instance, count=%lu", (unsigned long)gInstances.count]);
    return result;
}

// ============================================================
// 11. Experience Trigger - Do Trigger
// ============================================================
static void doTrigger(void) {
    id inst = gInstances.lastObject;
    if (inst) {
        logMsg(@"trigger start");
        SEL sel = NSSelectorFromString(@"edtc_flowEnhanceAction");
        if ([inst respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [inst performSelector:sel];
#pragma clang diagnostic pop
            logMsg(@"trigger ok");
        } else {
            logMsg(@"no selector");
        }
    } else {
        logMsg(@"no instance");
    }
}

// ============================================================
// 12. Experience Trigger - Auto Open Download Page
// ============================================================
static void autoOpenDownloadPage(void) {
    logMsg(@"autoOpen: start");

    UINavigationController *nav = getNavController();
    if (!nav) {
        logMsg(@"autoOpen: no nav controller");
        return;
    }

    Class downloadClass = NSClassFromString(@"ElyndorTVCode.EDTCAssetAcquireProcessor");
    if (downloadClass) {
        id vc = [[downloadClass alloc] init];
        if (vc) {
            [nav pushViewController:vc animated:NO];
            logMsg(@"autoOpen: pushed download page");

            // 创建 ribbon 实例，触发 hook_init 捕获
            Class ribbonClass = NSClassFromString(@"ElyndorTVCode.EDTCGuildFeatureRibbon");
            if (ribbonClass) {
                id ribbon = [[ribbonClass alloc] init];
                if (ribbon) {
                    logMsg(@"autoOpen: created ribbon instance");
                }
            }

            // 马上 pop 回主页
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (nav.viewControllers.count > 1) {
                    [nav popViewControllerAnimated:NO];
                    logMsg(@"autoOpen: popped back");
                }

                // 回到主页后触发一次
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    logMsg(@"first trigger after pop");
                    doTrigger();

                    // 启动 59s 定时器
                    if (!gAutoTimer) {
                        gTimerTarget = [[NSObject alloc] init];
                        // 使用 block-based timer 避免 target 方法问题
                        gAutoTimer = [NSTimer scheduledTimerWithTimeInterval:59.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
                            doTrigger();
                        }];
                        logMsg(@"auto timer started (59s)");
                    }
                });
            });
            return;
        }
    }

    logMsg(@"autoOpen: failed");
}

// ============================================================
// 13. Constructor - Entry Point
// ============================================================
__attribute__((constructor))
static void initPlugin(void) {
    // ===== VIP Hooks (immediate) =====
    kAuthKeys = @[@"authcode", @"auth_code", @"status"];
    kExpireKeys = @[@"expire", @"endtime", @"end_time", @"is_expired"];
    kLevelKeys = @[
        @"participantvoteterm", @"edtcactivedirectacquirecentral",
        @"k9mnpq7xzv2r8w4t", @"kgdtdeviceav1forceresetdowngradeversionkey",
        @"vip_level", @"viplevel", @"member_level", @"user_level", @"level", @"grade",
        @"vipLevel", @"memberLevel", @"userLevel", @"vip_grade", @"vipGrade",
        @"increaseSeekSomebody", @"duringBehaviorDirection", @"radioExecutiveEach",
        @"runMilitaryResponse", @"chancePublicAll", @"serveFaceWay",
        @"todayRealityLearn", @"glassHundredPeace", @"yardOptionTask",
        @"placePassUsually", @"sortLearnMore", @"partnerCourtYou",
        @"answerHoldGrowth", @"presentIdeaNot"
    ];
    kUDKeys = @[@"kvipStatusStorageKey", @"EDTCActiveDirectAcquireCentral", @"yituanlaunma"];

    Method m;
    m = class_getClassMethod([NSJSONSerialization class], @selector(JSONObjectWithData:options:error:));
    if (m) {
        orig_JSONObjectWithData = (id (*)(Class,SEL,NSData*,NSJSONReadingOptions,NSError**))method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_JSONObjectWithData);
    }

    Class ud = [NSUserDefaults class];
    m = class_getInstanceMethod(ud, @selector(boolForKey:));
    if (m) {
        orig_boolForKey = (BOOL (*)(NSUserDefaults*,SEL,NSString*))method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_boolForKey);
    }
    m = class_getInstanceMethod(ud, @selector(integerForKey:));
    if (m) {
        orig_integerForKey = (NSInteger (*)(NSUserDefaults*,SEL,NSString*))method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_integerForKey);
    }
    m = class_getInstanceMethod(ud, @selector(stringForKey:));
    if (m) {
        orig_stringForKey = (NSString *(*)(NSUserDefaults*,SEL,NSString*))method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_stringForKey);
    }
    m = class_getInstanceMethod(ud, @selector(objectForKey:));
    if (m) {
        orig_objectForKey = (id (*)(NSUserDefaults*,SEL,NSString*))method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_objectForKey);
    }

    Class lbl = [UILabel class];
    m = class_getInstanceMethod(lbl, @selector(setText:));
    if (m) {
        orig_setText = (void (*)(UILabel*,SEL,NSString*))method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_setText);
    }

    // ===== Experience Trigger (delayed) =====
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        logMsg(@"plugin loaded");

        Class ribbonClass = NSClassFromString(@"ElyndorTVCode.EDTCGuildFeatureRibbon");
        if (ribbonClass) {
            IMP origImp = class_replaceMethod(ribbonClass, @selector(init), (IMP)hook_init, "@@:");
            if (origImp) {
                orig_init = (id (*)(id, SEL))origImp;
                logMsg(@"init hooked (replaced)");
            } else {
                Class superClass = class_getSuperclass(ribbonClass);
                orig_init = (id (*)(id, SEL))class_getMethodImplementation(superClass, @selector(init));
                logMsg(@"init hooked (added)");
            }
        } else {
            logMsg(@"ribbon class not found");
        }

        autoOpenDownloadPage();
    });
}
