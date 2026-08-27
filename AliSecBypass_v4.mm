// ElyndorTV_VIP_v5.0.mm
// Smart Toggle | 0-delay | No logs
// TrollStore injectable, pure ObjC Runtime, no Logos

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gVIPFakeEnabled = YES;
static BOOL gSkipAd = NO;
static NSMutableSet *gProcessedAds = nil;

static NSArray *kAuthKeys = nil;
static NSArray *kExpireKeys = nil;
static NSArray *kLevelKeys = nil;
static NSArray *kUDKeys = nil;
static NSArray *kAdTargets = nil;
static NSArray *kAdPrefixes = nil;

static BOOL keyMatch(NSString *key, NSArray *list) {
    NSString *kl = [key lowercaseString];
    for (NSString *v in list) {
        NSString *vl = [v lowercaseString];
        if ([kl isEqualToString:vl] || [kl containsString:vl]) return YES;
    }
    return NO;
}

static BOOL isAdClass(NSString *name) {
    NSString *lower = [name lowercaseString];
    for (NSString *p in kAdPrefixes) {
        if ([lower containsString:p]) return YES;
    }
    return NO;
}

static NSDictionary *patchDictionary(NSDictionary *dict);

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

// ===================== 1. NSJSONSerialization =====================
static id (*orig_JSONObjectWithData)(Class cls, SEL sel, NSData *data, NSJSONReadingOptions opt, NSError **error);
static id hook_JSONObjectWithData(Class cls, SEL sel, NSData *data, NSJSONReadingOptions opt, NSError **error) {
    id result = orig_JSONObjectWithData(cls, sel, data, opt, error);
    if (!gVIPFakeEnabled || !result || ![result isKindOfClass:[NSDictionary class]]) return result;
    id patched = patchRecursively(result);
    return patched ? patched : result;
}

// ===================== 2. NSUserDefaults =====================
static BOOL (*orig_boolForKey)(NSUserDefaults *self, SEL sel, NSString *key);
static BOOL hook_boolForKey(NSUserDefaults *self, SEL sel, NSString *key) {
    BOOL result = orig_boolForKey(self, sel, key);
    if (!gVIPFakeEnabled) return result;
    for (NSString *k in kUDKeys) {
        if ([k isEqualToString:key]) return YES;
    }
    return result;
}

static NSInteger (*orig_integerForKey)(NSUserDefaults *self, SEL sel, NSString *key);
static NSInteger hook_integerForKey(NSUserDefaults *self, SEL sel, NSString *key) {
    NSInteger result = orig_integerForKey(self, sel, key);
    if (!gVIPFakeEnabled) return result;
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
    if (!gVIPFakeEnabled || !result) return result;
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
    if (!gVIPFakeEnabled || !result) return result;
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

// ===================== 3. UILabel =====================
static void (*orig_setText)(UILabel *self, SEL sel, NSString *text);
static void hook_setText(UILabel *self, SEL sel, NSString *text) {
    if (gVIPFakeEnabled && text) {
        if ([text containsString:@"立即开通"] || [text containsString:@"尚未开通"] ||
            [text containsString:@"未开通"] || [text containsString:@"非会员"]) {
            text = @"VIP会员已开通";
        }
    }
    orig_setText(self, sel, text);
}

// ===================== 4. UIControl (查看下载 + 广告触发) =====================
static void (*orig_sendActions)(UIControl *self, SEL sel, UIControlEvents events, UIEvent *event);
static void hook_sendActions(UIControl *self, SEL sel, UIControlEvents events, UIEvent *event) {
    if ([self respondsToSelector:@selector(titleLabel)]) {
        UILabel *tl = [(id)self titleLabel];
        if (tl && tl.text) {
            NSString *title = tl.text;
            if ([title containsString:@"查看下载"] || [title containsString:@"下载"]) {
                gVIPFakeEnabled = NO;
            }
            for (NSString *t in kAdTargets) {
                if ([title containsString:t]) {
                    gSkipAd = YES;
                    break;
                }
            }
        }
    }
    orig_sendActions(self, sel, events, event);
}

// ===================== 5. UIViewController (广告 dismiss + 0-delay restore) =====================
static void (*orig_viewDidAppear)(UIViewController *self, SEL sel, BOOL animated);
static void hook_viewDidAppear(UIViewController *self, SEL sel, BOOL animated) {
    orig_viewDidAppear(self, sel, animated);
    NSString *cn = NSStringFromClass([self class]);
    if (!isAdClass(cn)) return;
    NSString *ptrStr = [NSString stringWithFormat:@"%p", self];
    if ([gProcessedAds containsObject:ptrStr]) return;
    [gProcessedAds addObject:ptrStr];
    if (gSkipAd) {
        if (self.presentingViewController) {
            [self dismissViewControllerAnimated:NO completion:nil];
        } else if (self.navigationController) {
            [self.navigationController popViewControllerAnimated:NO];
        }
        gSkipAd = NO;
        gVIPFakeEnabled = YES;
    }
}

// ===================== 6. Back Navigation fallback =====================
static UIViewController *(*orig_popVC)(UINavigationController *self, SEL sel, BOOL animated);
static UIViewController *hook_popVC(UINavigationController *self, SEL sel, BOOL animated) {
    if (!gVIPFakeEnabled) gVIPFakeEnabled = YES;
    return orig_popVC(self, sel, animated);
}

static void (*orig_dismissVC)(UIViewController *self, SEL sel, BOOL animated, dispatch_block_t completion);
static void hook_dismissVC(UIViewController *self, SEL sel, BOOL animated, dispatch_block_t completion) {
    if (!gVIPFakeEnabled) gVIPFakeEnabled = YES;
    orig_dismissVC(self, sel, animated, completion);
}

// ===================== Constructor =====================
__attribute__((constructor))
static void init() {
    kAuthKeys = @[@"authcode", @"auth_code", @"status"];
    kExpireKeys = @[@"expire", @"endtime", @"end_time", @"is_expired"];
    kLevelKeys = @[
        @"participantvoteterm", @"edtcactivedirectacquirecentral",
        @"k9mnpq7xzv2r8w4t", @"kgdtdeviceav1forceresetdowngradeversionkey",
        @"vip_level", @"viplevel", @"member_level", @"user_level", @"level", @"grade",
        @"vipLevel", @"memberLevel", @"userLevel", @"vip_grade", @"vipGrade"
    ];
    kUDKeys = @[@"kvipStatusStorageKey", @"EDTCActiveDirectAcquireCentral"];
    kAdTargets = @[@"立即体验", @"立即领取", @"领取奖励", @"我要加速", @"看视频", @"去浏览", @"体验"];
    kAdPrefixes = @[
        @"gdtsplash", @"gdtbasead", @"gdtreward", @"gdtinterstitial", @"gdtnative",
        @"kssplash", @"ksad", @"ksreward", @"ksinterstitial", @"ksnative",
        @"busplash", @"bureward", @"bunative", @"buinterstitial",
        @"csjsplash", @"csjad", @"csjreward", @"csjnative", @"csjexpress",
        @"panglesplash", @"panglead", @"panglereward",
        @"tradplus", @"splash", @"interstitial", @"reward", @"nativeexpress",
        @"adviewcontroller", @"adview", @"adsplash"
    ];
    gProcessedAds = [NSMutableSet new];

    Method m;
    m = class_getClassMethod([NSJSONSerialization class], @selector(JSONObjectWithData:options:error:));
    if (m) { orig_JSONObjectWithData = (id (*)(Class,SEL,NSData*,NSJSONReadingOptions,NSError**))method_getImplementation(m); method_setImplementation(m, (IMP)hook_JSONObjectWithData); }

    Class ud = [NSUserDefaults class];
    m = class_getInstanceMethod(ud, @selector(boolForKey:));
    if (m) { orig_boolForKey = (BOOL (*)(NSUserDefaults*,SEL,NSString*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_boolForKey); }
    m = class_getInstanceMethod(ud, @selector(integerForKey:));
    if (m) { orig_integerForKey = (NSInteger (*)(NSUserDefaults*,SEL,NSString*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_integerForKey); }
    m = class_getInstanceMethod(ud, @selector(stringForKey:));
    if (m) { orig_stringForKey = (NSString *(*)(NSUserDefaults*,SEL,NSString*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_stringForKey); }
    m = class_getInstanceMethod(ud, @selector(objectForKey:));
    if (m) { orig_objectForKey = (id (*)(NSUserDefaults*,SEL,NSString*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_objectForKey); }

    Class lbl = [UILabel class];
    m = class_getInstanceMethod(lbl, @selector(setText:));
    if (m) { orig_setText = (void (*)(UILabel*,SEL,NSString*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_setText); }

    Class ctl = [UIControl class];
    m = class_getInstanceMethod(ctl, @selector(_sendActionsForEvents:withEvent:));
    if (m) { orig_sendActions = (void (*)(UIControl*,SEL,UIControlEvents,UIEvent*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_sendActions); }

    Class vc = [UIViewController class];
    m = class_getInstanceMethod(vc, @selector(viewDidAppear:));
    if (m) { orig_viewDidAppear = (void (*)(UIViewController*,SEL,BOOL))method_getImplementation(m); method_setImplementation(m, (IMP)hook_viewDidAppear); }
    m = class_getInstanceMethod(vc, @selector(dismissViewControllerAnimated:completion:));
    if (m) { orig_dismissVC = (void (*)(UIViewController*,SEL,BOOL,dispatch_block_t))method_getImplementation(m); method_setImplementation(m, (IMP)hook_dismissVC); }

    Class nc = [UINavigationController class];
    m = class_getInstanceMethod(nc, @selector(popViewControllerAnimated:));
    if (m) { orig_popVC = (UIViewController *(*)(UINavigationController*,SEL,BOOL))method_getImplementation(m); method_setImplementation(m, (IMP)hook_popVC); }
}
