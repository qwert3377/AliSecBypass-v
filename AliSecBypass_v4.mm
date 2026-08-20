//
//  ElyndorTV VIP v3.41 TrollStore.dylib
//  Pure ObjC Runtime — no %hook / Logos
//  Compile: make package FINALPACKAGE=1
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - Constants

static NSString * const kUDKeys[] = {
    @"kvipStatusStorageKey",
    @"EDTCActiveDirectAcquireCentral"
};
static const int kUDKeyCount = 2;

static NSString * const kAuthPatterns[] = {
    @"auth", @"vip", @"member", @"status", @"level", @"grade", @"expire", @"end"
};
static const int kAuthPatternCount = 8;

static NSString * const kAdPatterns[] = {
    @"splashad", @"splashview", @"adviewcontroller", @"nativeexpressad",
    @"interstitialad", @"rewardvideoad", @"fullscreenad", @"drawvideoad",
    @"bannerad", @"gdtad", @"baidumobad", @"klnsplash", @"tradplussplash",
    @"sigmobad", @"windad", @"tpadxsplash", @"adsuyiad", @"easyad"
};
static const int kAdPatternCount = 18;

static NSString * const kAdWhitelist[] = {
    @"skip", @"button", @"close", @"countdown", @"timer", @"progress"
};
static const int kAdWhitelistCount = 6;

#pragma mark - Helpers

static BOOL isUDKey(NSString *key) {
    if (!key) return NO;
    for (int i = 0; i < kUDKeyCount; i++) {
        if ([key isEqualToString:kUDKeys[i]]) return YES;
    }
    return NO;
}

static BOOL isAuthKey(NSString *key) {
    if (!key) return NO;
    NSString *lower = [key lowercaseString];
    for (int i = 0; i < kAuthPatternCount; i++) {
        if ([lower containsString:kAuthPatterns[i]]) return YES;
    }
    return NO;
}

static BOOL isAdViewClass(NSString *clsName) {
    if (!clsName) return NO;
    NSString *lower = [clsName lowercaseString];
    for (int i = 0; i < kAdWhitelistCount; i++) {
        if ([lower containsString:kAdWhitelist[i]]) return NO;
    }
    for (int i = 0; i < kAdPatternCount; i++) {
        if ([lower containsString:kAdPatterns[i]]) return YES;
    }
    return NO;
}

static NSDictionary* patchDictionary(NSDictionary *dict) {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *keys = [dict allKeys];
    if (!keys || keys.count == 0) return nil;

    BOOL needsPatch = NO;
    for (NSString *key in keys) {
        NSString *lk = [key lowercaseString];
        id val = dict[key];
        if (!val) continue;
        if ([lk isEqualToString:@"authcode"] || [lk isEqualToString:@"auth_code"]) {
            if ([val isKindOfClass:[NSNumber class]] && [val intValue] == 0) needsPatch = YES;
            else if ([val isKindOfClass:[NSString class]] && [val isEqualToString:@"0"]) needsPatch = YES;
        } else if ([lk isEqualToString:@"status"] && [val isKindOfClass:[NSNumber class]] && [val intValue] == 0) {
            needsPatch = YES;
        } else if ([lk containsString:@"expire"] || [lk containsString:@"endtime"] ||
                   [lk containsString:@"end_time"] || [lk isEqualToString:@"is_expired"]) {
            needsPatch = YES;
        }
    }
    if (!needsPatch) return nil;

    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:dict];
    for (NSString *key in keys) {
        NSString *lk = [key lowercaseString];
        id val = dict[key];
        if (!val) continue;
        if ([lk isEqualToString:@"authcode"] || [lk isEqualToString:@"auth_code"]) {
            if ([val isKindOfClass:[NSNumber class]] && [val intValue] == 0) m[key] = @1;
            else if ([val isKindOfClass:[NSString class]] && [val isEqualToString:@"0"]) m[key] = @"1";
        } else if ([lk isEqualToString:@"status"] && [val isKindOfClass:[NSNumber class]] && [val intValue] == 0) {
            m[key] = @1;
        } else if ([lk containsString:@"expire"] || [lk containsString:@"endtime"] ||
                   [lk containsString:@"end_time"] || [lk isEqualToString:@"is_expired"]) {
            if ([val isKindOfClass:[NSString class]]) m[key] = @"2099-12-31";
            else if ([val isKindOfClass:[NSNumber class]]) m[key] = @(4102444799000);
        }
    }
    return m;
}

#pragma mark - Empty IMPs for ad SDK blocking

static void empty_imp_0(__unused id self, __unused SEL _cmd) {}
static void empty_imp_1(__unused id self, __unused SEL _cmd, __unused id a1) {}
static void empty_imp_2(__unused id self, __unused SEL _cmd, __unused id a1, __unused id a2) {}

static void blockSplashMethod(Class cls, SEL sel) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) m = class_getClassMethod(cls, sel);
    if (!m) return;
    unsigned int nargs = method_getNumberOfArguments(m);
    IMP emptyIMP;
    if (nargs <= 2) emptyIMP = (IMP)empty_imp_0;
    else if (nargs == 3) emptyIMP = (IMP)empty_imp_1;
    else emptyIMP = (IMP)empty_imp_2;
    method_setImplementation(m, emptyIMP);
}

#pragma mark - NSUserDefaults Hooks

static BOOL (*orig_boolForKey)(NSUserDefaults*, SEL, NSString*);
static BOOL hook_boolForKey(NSUserDefaults *self, SEL _cmd, NSString *key) {
    if (isUDKey(key)) return YES;
    return orig_boolForKey(self, _cmd, key);
}

static NSInteger (*orig_integerForKey)(NSUserDefaults*, SEL, NSString*);
static NSInteger hook_integerForKey(NSUserDefaults *self, SEL _cmd, NSString *key) {
    if (isUDKey(key)) return 999;
    return orig_integerForKey(self, _cmd, key);
}

static id (*orig_objectForKey_UD)(NSUserDefaults*, SEL, NSString*);
static id hook_objectForKey_UD(NSUserDefaults *self, SEL _cmd, NSString *key) {
    if (isUDKey(key)) return @YES;
    return orig_objectForKey_UD(self, _cmd, key);
}

static NSString* (*orig_stringForKey_UD)(NSUserDefaults*, SEL, NSString*);
static NSString* hook_stringForKey_UD(NSUserDefaults *self, SEL _cmd, NSString *key) {
    if (isUDKey(key)) return @"1";
    return orig_stringForKey_UD(self, _cmd, key);
}

#pragma mark - NSDictionary Hooks

static id (*orig_objectForKey_Dict)(NSDictionary*, SEL, id);
static id hook_objectForKey_Dict(NSDictionary *self, SEL _cmd, id key) {
    id result = orig_objectForKey_Dict(self, _cmd, key);
    if (!result) return result;
    NSString *keyStr = nil;
    if ([key isKindOfClass:[NSString class]]) keyStr = (NSString*)key;
    else if ([key respondsToSelector:@selector(stringValue)]) keyStr = [(NSNumber*)key stringValue];
    if (!keyStr || !isAuthKey(keyStr)) return result;
    NSString *lk = [keyStr lowercaseString];
    if ([lk containsString:@"auth"] || [lk containsString:@"status"]) {
        if ([result isKindOfClass:[NSNumber class]] && [result intValue] == 0) return @1;
    } else if ([lk containsString:@"end"] || [lk containsString:@"expire"] || [lk isEqualToString:@"is_expired"]) {
        return @"2099-12-31";
    } else if ([lk containsString:@"level"] || [lk containsString:@"grade"]) {
        return @999;
    }
    return result;
}

static id (*orig_valueForKey)(NSDictionary*, SEL, NSString*);
static id hook_valueForKey(NSDictionary *self, SEL _cmd, NSString *key) {
    id result = orig_valueForKey(self, _cmd, key);
    if (!result || !isAuthKey(key)) return result;
    NSString *lk = [key lowercaseString];
    if ([lk containsString:@"auth"] || [lk containsString:@"status"]) {
        if ([result isKindOfClass:[NSNumber class]] && [result intValue] == 0) return @1;
    } else if ([lk containsString:@"end"] || [lk containsString:@"expire"]) {
        return @"2099-12-31";
    } else if ([lk containsString:@"level"] || [lk containsString:@"grade"]) {
        return @999;
    }
    return result;
}

static id (*orig_objectForKeyedSubscript_Dict)(NSDictionary*, SEL, id);
static id hook_objectForKeyedSubscript_Dict(NSDictionary *self, SEL _cmd, id key) {
    id result = orig_objectForKeyedSubscript_Dict(self, _cmd, key);
    if (!result) return result;
    NSString *keyStr = nil;
    if ([key isKindOfClass:[NSString class]]) keyStr = (NSString*)key;
    if (!keyStr || !isAuthKey(keyStr)) return result;
    NSString *lk = [keyStr lowercaseString];
    if ([lk containsString:@"auth"] || [lk containsString:@"status"]) {
        if ([result isKindOfClass:[NSNumber class]] && [result intValue] == 0) return @1;
    } else if ([lk containsString:@"end"] || [lk containsString:@"expire"] || [lk isEqualToString:@"is_expired"]) {
        return @"2099-12-31";
    } else if ([lk containsString:@"level"] || [lk containsString:@"grade"]) {
        return @999;
    }
    return result;
}

#pragma mark - NSJSONSerialization Hook

static id (*orig_JSONParse)(Class, SEL, NSData*, NSJSONReadingOptions, NSError**);
static id hook_JSONParse(Class self, SEL _cmd, NSData *data, NSJSONReadingOptions opt, NSError **error) {
    id result = orig_JSONParse(self, _cmd, data, opt, error);
    if (!result) return result;
    NSDictionary *patched = patchDictionary(result);
    return patched ? patched : result;
}

#pragma mark - NSMutableDictionary Hooks

static void (*orig_setObjectForKey)(NSMutableDictionary*, SEL, id, id);
static void hook_setObjectForKey(NSMutableDictionary *self, SEL _cmd, id obj, id key) {
    NSString *keyStr = ([key isKindOfClass:[NSString class]]) ? (NSString*)key : nil;
    if (keyStr) {
        NSString *lk = [keyStr lowercaseString];
        if ([lk isEqualToString:@"authcode"] || [lk isEqualToString:@"auth_code"]) {
            if ([obj isKindOfClass:[NSNumber class]] && [obj intValue] == 0) obj = @1;
            else if ([obj isKindOfClass:[NSString class]] && [(NSString*)obj isEqualToString:@"0"]) obj = @"1";
        } else if ([lk isEqualToString:@"status"] && [obj isKindOfClass:[NSNumber class]] && [obj intValue] == 0) {
            obj = @1;
        } else if (([lk containsString:@"expire"] || [lk containsString:@"endtime"] ||
                    [lk containsString:@"end_time"] || [lk isEqualToString:@"is_expired"]) &&
                   [obj isKindOfClass:[NSString class]]) {
            obj = @"2099-12-31";
        }
    }
    orig_setObjectForKey(self, _cmd, obj, key);
}

static void (*orig_setObjectForKeyedSubscript)(NSMutableDictionary*, SEL, id, id);
static void hook_setObjectForKeyedSubscript(NSMutableDictionary *self, SEL _cmd, id obj, id key) {
    NSString *keyStr = ([key isKindOfClass:[NSString class]]) ? (NSString*)key : nil;
    if (keyStr) {
        NSString *lk = [keyStr lowercaseString];
        if ([lk isEqualToString:@"authcode"] || [lk isEqualToString:@"auth_code"]) {
            if ([obj isKindOfClass:[NSNumber class]] && [obj intValue] == 0) obj = @1;
            else if ([obj isKindOfClass:[NSString class]] && [(NSString*)obj isEqualToString:@"0"]) obj = @"1";
        } else if ([lk isEqualToString:@"status"] && [obj isKindOfClass:[NSNumber class]] && [obj intValue] == 0) {
            obj = @1;
        } else if (([lk containsString:@"expire"] || [lk containsString:@"endtime"] ||
                    [lk containsString:@"end_time"] || [lk isEqualToString:@"is_expired"]) &&
                   [obj isKindOfClass:[NSString class]]) {
            obj = @"2099-12-31";
        }
    }
    orig_setObjectForKeyedSubscript(self, _cmd, obj, key);
}

#pragma mark - UILabel Hook

static void (*orig_setText)(UILabel*, SEL, NSString*);
static void hook_setText(UILabel *self, SEL _cmd, NSString *text) {
    NSString *nt = nil;
    if ([text containsString:@"立即开通"] || [text containsString:@"尚未开通"] ||
        [text containsString:@"未开通"] || [text containsString:@"非会员"]) {
        nt = @"VIP会员已开通";
    }
    orig_setText(self, _cmd, nt ? nt : text);
}

#pragma mark - Ad Block: UIWindow / UIView

static void (*orig_windowAddSubview)(UIWindow*, SEL, UIView*);
static void hook_windowAddSubview(UIWindow *self, SEL _cmd, UIView *view) {
    orig_windowAddSubview(self, _cmd, view);
    if (view && isAdViewClass(NSStringFromClass([view class]))) {
        [view removeFromSuperview];
    }
}

static void (*orig_viewAddSubview)(UIView*, SEL, UIView*);
static void hook_viewAddSubview(UIView *self, SEL _cmd, UIView *view) {
    orig_viewAddSubview(self, _cmd, view);
    if (view && isAdViewClass(NSStringFromClass([view class]))) {
        [view removeFromSuperview];
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void init() {
    NSLog(@"[ElyndorVIP] dylib loaded");

    Method m;

    // NSUserDefaults
    m = class_getInstanceMethod([NSUserDefaults class], @selector(boolForKey:));
    if (m) { orig_boolForKey = (BOOL (*)(NSUserDefaults*,SEL,NSString*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_boolForKey); }

    m = class_getInstanceMethod([NSUserDefaults class], @selector(integerForKey:));
    if (m) { orig_integerForKey = (NSInteger (*)(NSUserDefaults*,SEL,NSString*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_integerForKey); }

    m = class_getInstanceMethod([NSUserDefaults class], @selector(objectForKey:));
    if (m) { orig_objectForKey_UD = (id (*)(NSUserDefaults*,SEL,NSString*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_objectForKey_UD); }

    m = class_getInstanceMethod([NSUserDefaults class], @selector(stringForKey:));
    if (m) { orig_stringForKey_UD = (NSString* (*)(NSUserDefaults*,SEL,NSString*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_stringForKey_UD); }

    // NSDictionary
    m = class_getInstanceMethod([NSDictionary class], @selector(objectForKey:));
    if (m) { orig_objectForKey_Dict = (id (*)(NSDictionary*,SEL,id))method_getImplementation(m); method_setImplementation(m, (IMP)hook_objectForKey_Dict); }

    m = class_getInstanceMethod([NSDictionary class], @selector(valueForKey:));
    if (m) { orig_valueForKey = (id (*)(NSDictionary*,SEL,NSString*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_valueForKey); }

    m = class_getInstanceMethod([NSDictionary class], @selector(objectForKeyedSubscript:));
    if (m) { orig_objectForKeyedSubscript_Dict = (id (*)(NSDictionary*,SEL,id))method_getImplementation(m); method_setImplementation(m, (IMP)hook_objectForKeyedSubscript_Dict); }

    // NSJSONSerialization (class method)
    m = class_getClassMethod([NSJSONSerialization class], @selector(JSONObjectWithData:options:error:));
    if (m) { orig_JSONParse = (id (*)(Class,SEL,NSData*,NSJSONReadingOptions,NSError**))method_getImplementation(m); method_setImplementation(m, (IMP)hook_JSONParse); }

    // NSMutableDictionary
    m = class_getInstanceMethod([NSMutableDictionary class], @selector(setObject:forKey:));
    if (m) { orig_setObjectForKey = (void (*)(NSMutableDictionary*,SEL,id,id))method_getImplementation(m); method_setImplementation(m, (IMP)hook_setObjectForKey); }

    m = class_getInstanceMethod([NSMutableDictionary class], @selector(setObject:forKeyedSubscript:));
    if (m) { orig_setObjectForKeyedSubscript = (void (*)(NSMutableDictionary*,SEL,id,id))method_getImplementation(m); method_setImplementation(m, (IMP)hook_setObjectForKeyedSubscript); }

    // UILabel
    m = class_getInstanceMethod([UILabel class], @selector(setText:));
    if (m) { orig_setText = (void (*)(UILabel*,SEL,NSString*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_setText); }

    // Ad Block
    m = class_getInstanceMethod([UIWindow class], @selector(addSubview:));
    if (m) { orig_windowAddSubview = (void (*)(UIWindow*,SEL,UIView*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_windowAddSubview); }

    m = class_getInstanceMethod([UIView class], @selector(addSubview:));
    if (m) { orig_viewAddSubview = (void (*)(UIView*,SEL,UIView*))method_getImplementation(m); method_setImplementation(m, (IMP)hook_viewAddSubview); }

    // Block known splash SDK methods
    NSArray *splashClasses = @[
        @"GDTSplashAd", @"BUNativeExpressSplashView", @"BUNativeExpressSplashViewController",
        @"BaiduMobAdSplash", @"KLNSplashAd", @"EasyAdSplash", @"ADSuyiSDKSplashAd",
        @"CSJSplashAdView", @"CSJSplashViewController", @"TradPlusSplash", @"TPADXSplashView",
        @"SigmobSplashAd", @"WindSplashAd"
    ];
    NSArray *splashMethods = @[
        @"loadAndShowInWindow:", @"loadAndShowInWindow:withBottomView:",
        @"showAdInWindow:", @"showAd", @"loadAndShowAd", @"showSplashAd",
        @"showSplash", @"showInWindow:", @"show"
    ];
    for (NSString *clsName in splashClasses) {
        Class cls = NSClassFromString(clsName);
        if (!cls) continue;
        for (NSString *selName in splashMethods) {
            blockSplashMethod(cls, NSSelectorFromString(selName));
        }
    }

    NSLog(@"[ElyndorVIP] All hooks installed");
}
