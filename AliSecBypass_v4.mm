//
//  ElyndorTV VIP v4.1 — Theos .mm Plugin
//  TrollStore / Non-Jailbreak Injection
//  Pure ObjC Runtime, no Logos / %hook
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#pragma mark - Config

static NSArray *gAuthKeys;
static NSArray *gExpireKeys;
static NSArray *gLevelKeys;
static NSArray *gUDKeys;

static void InitKeys(void) {
    gAuthKeys   = @[ @"authcode", @"auth_code", @"status" ];
    gExpireKeys = @[ @"expire", @"endtime", @"end_time", @"is_expired" ];
    gLevelKeys  = @[
        @"participantvoteterm", @"edtcactivedirectacquirecentral",
        @"k9mnpq7xzv2r8w4t", @"kgdtdeviceav1forceresetdowngradeversionkey",
        @"vip_level", @"viplevel", @"member_level", @"user_level", @"level", @"grade",
        @"vipLevel", @"memberLevel", @"userLevel", @"vip_grade", @"vipGrade"
    ];
    gUDKeys     = @[ @"kvipStatusStorageKey", @"EDTCActiveDirectAcquireCentral" ];
}

static void VIPLog(NSString *tag, NSString *msg) {
    NSLog(@"%@ %@", tag, msg);
}

#pragma mark - Key Matching

static BOOL MatchKey(NSString *key, NSArray *list) {
    NSString *kl = [key lowercaseString];
    for (NSString *v in list) {
        if ([kl isEqualToString:[v lowercaseString]] || [kl containsString:[v lowercaseString]]) {
            return YES;
        }
    }
    return NO;
}

static BOOL IsUDKey(NSString *k) {
    for (NSString *v in gUDKeys) {
        if ([v isEqualToString:k]) return YES;
    }
    return NO;
}

static BOOL IsLevelKey(NSString *k) {
    return MatchKey(k, gLevelKeys);
}

#pragma mark - JSON Patch

static NSMutableDictionary *PatchDict(NSDictionary *d);

static id PatchRecursively(id obj) {
    NSMutableDictionary *p = PatchDict(obj);
    if (p) return p;

    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *d = obj;
    NSArray *keys = [d allKeys];
    BOOL mod = NO;
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:d];
    for (id keyObj in keys) {
        if (![keyObj isKindOfClass:[NSString class]]) continue;
        NSString *key = (NSString *)keyObj;
        id v = d[key];
        if ([v isKindOfClass:[NSDictionary class]]) {
            id n = PatchRecursively(v);
            if (n) { m[key] = n; mod = YES; }
        } else if ([v isKindOfClass:[NSArray class]]) {
            NSArray *arr = v;
            NSMutableArray *ma = [NSMutableArray arrayWithArray:arr];
            BOOL am = NO;
            for (NSUInteger j = 0; j < ma.count; j++) {
                id item = ma[j];
                if ([item isKindOfClass:[NSDictionary class]]) {
                    id np = PatchRecursively(item);
                    if (np) { ma[j] = np; am = YES; }
                }
            }
            if (am) { m[key] = ma; mod = YES; }
        }
    }
    return mod ? m : nil;
}

static NSMutableDictionary *PatchDict(NSDictionary *d) {
    if (!d || ![d isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *keys = [d allKeys];
    if (!keys || keys.count == 0) return nil;

    BOOL need = NO;
    for (id keyObj in keys) {
        if (![keyObj isKindOfClass:[NSString class]]) continue;
        NSString *k = (NSString *)keyObj;
        NSString *kl = [k lowercaseString];
        id v = d[k];
        if (!v || [v isKindOfClass:[NSNull class]]) continue;
        if ((MatchKey(kl, gAuthKeys) && [v isKindOfClass:[NSNumber class]] && [v intValue] == 0) ||
            (MatchKey(kl, gExpireKeys) && ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]])) ||
            (MatchKey(kl, gLevelKeys) && [v isKindOfClass:[NSNumber class]] && [v intValue] >= 0 && [v intValue] < 8)) {
            need = YES;
        }
    }
    if (!need) return nil;

    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:d];
    for (id keyObj in keys) {
        if (![keyObj isKindOfClass:[NSString class]]) continue;
        NSString *key = (NSString *)keyObj;
        NSString *ks = key;
        NSString *kl = [ks lowercaseString];
        id v = d[key];
        if (!v || [v isKindOfClass:[NSNull class]]) continue;

        if (MatchKey(kl, gAuthKeys)) {
            if ([v isKindOfClass:[NSNumber class]] && [v intValue] == 0) {
                m[key] = @1;
                VIPLog(@"[JSON]", [NSString stringWithFormat:@"%@: 0→1", ks]);
            } else if ([v isKindOfClass:[NSString class]] && [v isEqualToString:@"0"]) {
                m[key] = @"1";
                VIPLog(@"[JSON]", [NSString stringWithFormat:@"%@: \"0\"→\"1\"", ks]);
            }
        } else if (MatchKey(kl, gExpireKeys)) {
            if ([v isKindOfClass:[NSString class]]) {
                m[key] = @"2099-12-31";
                VIPLog(@"[JSON]", [NSString stringWithFormat:@"%@→2099", ks]);
            } else if ([v isKindOfClass:[NSNumber class]]) {
                m[key] = @(4102444799000);
                VIPLog(@"[JSON]", [NSString stringWithFormat:@"%@→MAX", ks]);
            }
        } else if (MatchKey(kl, gLevelKeys)) {
            if ([v isKindOfClass:[NSNumber class]]) {
                int iv = [v intValue];
                if (iv >= 0 && iv < 8) {
                    m[key] = @8;
                    VIPLog(@"[JSON]", [NSString stringWithFormat:@"等级 %@: %d→8", ks, iv]);
                }
            } else if ([v isKindOfClass:[NSString class]]) {
                NSString *s = v;
                if ([@"0" isEqualToString:s] || [@"1" isEqualToString:s] || [@"2" isEqualToString:s] ||
                    [@"3" isEqualToString:s] || [@"4" isEqualToString:s] || [@"5" isEqualToString:s] ||
                    [@"6" isEqualToString:s] || [@"7" isEqualToString:s]) {
                    m[key] = @"8";
                    VIPLog(@"[JSON]", [NSString stringWithFormat:@"等级 %@: \"%@\"→\"8\"", ks, s]);
                }
            }
        }
    }
    return m;
}

#pragma mark - Original IMPs

static id   (*orig_JSONObjectWithData)(id self, SEL _cmd, NSData *data, NSUInteger options, NSError **error);
static BOOL (*orig_boolForKey)(id self, SEL _cmd, NSString *key);
static NSInteger (*orig_integerForKey)(id self, SEL _cmd, NSString *key);
static NSString * (*orig_stringForKey)(id self, SEL _cmd, NSString *key);
static id   (*orig_objectForKey)(id self, SEL _cmd, NSString *key);
static void (*orig_setText)(id self, SEL _cmd, NSString *text);

#pragma mark - Hooks

static id hook_JSONObjectWithData(id self, SEL _cmd, NSData *data, NSUInteger options, NSError **error) {
    id result = orig_JSONObjectWithData(self, _cmd, data, options, error);
    if (!result || ![result isKindOfClass:[NSDictionary class]]) return result;
    id patched = PatchRecursively(result);
    if (patched) {
        VIPLog(@"[VIP]", @"NSJSONSerialization patched");
        return patched;
    }
    return result;
}

static BOOL hook_boolForKey(id self, SEL _cmd, NSString *key) {
    if (IsUDKey(key)) return YES;
    return orig_boolForKey(self, _cmd, key);
}

static NSInteger hook_integerForKey(id self, SEL _cmd, NSString *key) {
    if (IsUDKey(key) || IsLevelKey(key)) {
        NSInteger v = orig_integerForKey(self, _cmd, key);
        if (v >= 0 && v < 8) return 8;
        return v;
    }
    return orig_integerForKey(self, _cmd, key);
}

static NSString * hook_stringForKey(id self, SEL _cmd, NSString *key) {
    NSString *v = orig_stringForKey(self, _cmd, key);
    if (!v) return v;
    if ((IsUDKey(key) || IsLevelKey(key)) &&
        ([@"0" isEqualToString:v] || [@"1" isEqualToString:v] || [@"2" isEqualToString:v] ||
         [@"3" isEqualToString:v] || [@"4" isEqualToString:v] || [@"5" isEqualToString:v] ||
         [@"6" isEqualToString:v] || [@"7" isEqualToString:v])) {
        VIPLog(@"[UD]", [NSString stringWithFormat:@"UD等级: \"%@\"→\"8\"", v]);
        return @"8";
    }
    return v;
}

static id hook_objectForKey(id self, SEL _cmd, NSString *key) {
    id v = orig_objectForKey(self, _cmd, key);
    if (!v) return v;
    if (IsUDKey(key) || IsLevelKey(key)) {
        if ([v isKindOfClass:[NSNumber class]]) {
            int iv = [v intValue];
            if (iv >= 0 && iv < 8) {
                VIPLog(@"[UD]", [NSString stringWithFormat:@"UD等级: %d→8", iv]);
                return @8;
            }
        } else if ([v isKindOfClass:[NSString class]]) {
            NSString *s = v;
            if ([@"0" isEqualToString:s] || [@"1" isEqualToString:s] || [@"2" isEqualToString:s] ||
                [@"3" isEqualToString:s] || [@"4" isEqualToString:s] || [@"5" isEqualToString:s] ||
                [@"6" isEqualToString:s] || [@"7" isEqualToString:s]) {
                VIPLog(@"[UD]", [NSString stringWithFormat:@"UD等级: \"%@\"→\"8\"", s]);
                return @"8";
            }
        }
    }
    return v;
}

static void hook_setText(id self, SEL _cmd, NSString *text) {
    NSString *nt = nil;
    if ([text containsString:@"立即开通"] || [text containsString:@"尚未开通"] ||
        [text containsString:@"未开通"] || [text containsString:@"非会员"]) {
        nt = @"VIP会员已开通";
    }
    if (nt) {
        VIPLog(@"[UI]", [NSString stringWithFormat:@"\"%@\"→\"VIP会员已开通\"", text]);
        orig_setText(self, _cmd, nt);
    } else {
        orig_setText(self, _cmd, text);
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void ElyndorInit(void) {
    NSLog(@"\n=== ElyndorTV VIP v4.1 ===");
    NSLog(@"=== Theos .mm Plugin ===\n");

    InitKeys();

    // 1. NSJSONSerialization
    Class jsonClass = objc_getClass("NSJSONSerialization");
    if (jsonClass) {
        Method m = class_getClassMethod(jsonClass, @selector(JSONObjectWithData:options:error:));
        if (m) {
            orig_JSONObjectWithData = (id (*)(id, SEL, NSData *, NSUInteger, NSError **))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_JSONObjectWithData);
            VIPLog(@"[VIP]", @"已Hook NSJSONSerialization");
        }
    }

    // 2. NSUserDefaults
    Class udClass = objc_getClass("NSUserDefaults");
    if (udClass) {
        Method m1 = class_getInstanceMethod(udClass, @selector(boolForKey:));
        if (m1) {
            orig_boolForKey = (BOOL (*)(id, SEL, NSString *))method_getImplementation(m1);
            method_setImplementation(m1, (IMP)hook_boolForKey);
        }
        Method m2 = class_getInstanceMethod(udClass, @selector(integerForKey:));
        if (m2) {
            orig_integerForKey = (NSInteger (*)(id, SEL, NSString *))method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hook_integerForKey);
        }
        Method m3 = class_getInstanceMethod(udClass, @selector(stringForKey:));
        if (m3) {
            orig_stringForKey = (NSString * (*)(id, SEL, NSString *))method_getImplementation(m3);
            method_setImplementation(m3, (IMP)hook_stringForKey);
        }
        Method m4 = class_getInstanceMethod(udClass, @selector(objectForKey:));
        if (m4) {
            orig_objectForKey = (id (*)(id, SEL, NSString *))method_getImplementation(m4);
            method_setImplementation(m4, (IMP)hook_objectForKey);
        }
        VIPLog(@"[VIP]", @"已Hook NSUserDefaults");
    }

    // 3. UILabel
    Class labelClass = objc_getClass("UILabel");
    if (labelClass) {
        Method m = class_getInstanceMethod(labelClass, @selector(setText:));
        if (m) {
            orig_setText = (void (*)(id, SEL, NSString *))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_setText);
            VIPLog(@"[VIP]", @"已Hook UILabel");
        }
    }

    NSLog(@"\n=== 已激活 ===");
    NSLog(@"=== NSJSONSerialization + NSUserDefaults + UILabel ===\n");
}
