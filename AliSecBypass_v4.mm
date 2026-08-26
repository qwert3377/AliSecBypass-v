//
//  ElyndorTV VIP Tweak v4.4 — Data Key Fix
//  Adds dataForKey: + dictionaryForKey: hooks (v4.3 was missing these)
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#pragma mark - 字段配置

static const char *AUTH_KEYS[] = {"authcode", "auth_code", "status", "isVip", "isMember", "isPremium", "isSubscribed"};
static const char *EXPIRE_KEYS[] = {"expire", "endtime", "end_time", "is_expired", "expireTime", "vipExpire", "memberExpire"};
static const char *LEVEL_KEYS[] = {
    "participantvoteterm", "edtcactivedirectacquirecentral",
    "k9mnpq7xzv2r8w4t", "kgdtdeviceav1forceresetdowngradeversionkey",
    "vip_level", "viplevel", "member_level", "user_level", "level", "grade",
    "viplevel", "memberlevel", "userlevel", "vip_grade", "vipgrade",
    "tier", "vipTier", "memberTier", "subscriptionLevel", "requiredVipTier"
};
static const char *UD_KEYS[] = {"kvipStatusStorageKey", "kvipstatusstoragekey", "EDTCActiveDirectAcquireCentral"};

static BOOL strMatch(const char *key, const char **list, size_t count) {
    if (!key) return NO;
    size_t klen = strlen(key);
    for (size_t i = 0; i < count; i++) {
        const char *v = list[i];
        size_t vlen = strlen(v);
        if (klen == vlen && strcasecmp(key, v) == 0) return YES;
        if (strcasestr(key, v) != NULL) return YES;
    }
    return NO;
}

static BOOL isAuthKey(const char *k)    { return strMatch(k, AUTH_KEYS, sizeof(AUTH_KEYS)/sizeof(char*)); }
static BOOL isExpireKey(const char *k)  { return strMatch(k, EXPIRE_KEYS, sizeof(EXPIRE_KEYS)/sizeof(char*)); }
static BOOL isLevelKey(const char *k)   { return strMatch(k, LEVEL_KEYS, sizeof(LEVEL_KEYS)/sizeof(char*)); }
static BOOL isUDKey(const char *k)      {
    if (!k) return NO;
    for (size_t i = 0; i < sizeof(UD_KEYS)/sizeof(char*); i++) {
        if (strcasecmp(k, UD_KEYS[i]) == 0) return YES;
    }
    return NO;
}

#pragma mark - Fake JSON Data

static NSData *fakeVipJsonData(void) {
    static NSData *gData = nil;
    if (!gData) {
        NSDictionary *d = @{
            @"isVip": @YES,
            @"isMember": @YES,
            @"tier": @8,
            @"level": @8,
            @"grade": @8,
            @"vipLevel": @8,
            @"memberLevel": @8,
            @"expireTime": @(4102444800),
            @"vipExpire": @(4102444800),
            @"memberExpire": @(4102444800),
            @"status": @"active",
            @"type": @"lifetime",
            @"membershipType": @"premium"
        };
        gData = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
    }
    return gData;
}

static NSDictionary *fakeVipDict(void) {
    static NSDictionary *gDict = nil;
    if (!gDict) {
        gDict = @{
            @"isVip": @YES,
            @"isMember": @YES,
            @"tier": @8,
            @"level": @8,
            @"grade": @8,
            @"vipLevel": @8,
            @"memberLevel": @8,
            @"expireTime": @(4102444800),
            @"vipExpire": @(4102444800),
            @"memberExpire": @(4102444800),
            @"status": @"active",
            @"type": @"lifetime",
            @"membershipType": @"premium"
        };
    }
    return gDict;
}

#pragma mark - JSON Patch (recursive)

static NSDictionary * patchDictRecursively(NSDictionary *dict) {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *keys = [dict allKeys];
    if (!keys || keys.count == 0) return nil;

    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:dict];
    BOOL modified = NO;

    for (NSString *key in keys) {
        const char *kl = [key UTF8String];
        id v = dict[key];
        if (!v) continue;

        if (isLevelKey(kl)) {
            if ([v isKindOfClass:[NSNumber class]]) {
                int iv = [v intValue];
                if (iv >= 0 && iv < 8) { m[key] = @8; modified = YES; }
            } else if ([v isKindOfClass:[NSString class]]) {
                NSString *s = v;
                if ([s isEqualToString:@"0"] || [s isEqualToString:@"1"] || [s isEqualToString:@"2"] ||
                    [s isEqualToString:@"3"] || [s isEqualToString:@"4"] || [s isEqualToString:@"5"] ||
                    [s isEqualToString:@"6"] || [s isEqualToString:@"7"]) {
                    m[key] = @"8"; modified = YES;
                }
            }
        }
        else if (isAuthKey(kl)) {
            if ([v isKindOfClass:[NSNumber class]] && [v intValue] == 0) { m[key] = @1; modified = YES; }
            else if ([v isKindOfClass:[NSString class]] && [v isEqualToString:@"0"]) { m[key] = @"1"; modified = YES; }
        }
        else if (isExpireKey(kl)) {
            if ([v isKindOfClass:[NSString class]]) { m[key] = @"2099-12-31"; modified = YES; }
            else if ([v isKindOfClass:[NSNumber class]]) { m[key] = @(4102444799000LL); modified = YES; }
        }
        else if ([v isKindOfClass:[NSDictionary class]]) {
            NSDictionary *n = patchDictRecursively(v);
            if (n) { m[key] = n; modified = YES; }
        }
        else if ([v isKindOfClass:[NSArray class]]) {
            NSArray *arr = v;
            NSMutableArray *ma = [NSMutableArray arrayWithArray:arr];
            BOOL arrMod = NO;
            for (NSUInteger j = 0; j < ma.count; j++) {
                id item = ma[j];
                if ([item isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *np = patchDictRecursively(item);
                    if (np) { ma[j] = np; arrMod = YES; }
                }
            }
            if (arrMod) { m[key] = ma; modified = YES; }
        }
    }
    return modified ? m : nil;
}

#pragma mark - NSJSONSerialization Hook

typedef id (*JSONImp_t)(Class, SEL, NSData *, NSJSONReadingOptions, NSError **);
static JSONImp_t orig_JSON = NULL;

static id new_JSON(Class cls, SEL sel, NSData *data, NSJSONReadingOptions opt, NSError **error) {
    id result = orig_JSON(cls, sel, data, opt, error);
    if ([result isKindOfClass:[NSDictionary class]]) {
        NSDictionary *patched = patchDictRecursively(result);
        if (patched) return patched;
    }
    return result;
}

static void hookJSONSerialization(void) {
    Class cls = objc_getClass("NSJSONSerialization");
    if (!cls) return;
    SEL sel = @selector(JSONObjectWithData:options:error:);
    Method m = class_getClassMethod(cls, sel);
    if (!m) return;
    orig_JSON = (JSONImp_t)method_getImplementation(m);
    method_setImplementation(m, (IMP)new_JSON);
}

#pragma mark - NSUserDefaults Hooks (8 methods)

typedef BOOL (*BoolImp_t)(id, SEL, NSString *);
typedef NSInteger (*IntImp_t)(id, SEL, NSString *);
typedef NSString * (*StrImp_t)(id, SEL, NSString *);
typedef id (*ObjImp_t)(id, SEL, NSString *);
typedef id (*DataImp_t)(id, SEL, NSString *);
typedef id (*DictImp_t)(id, SEL, NSString *);

static BoolImp_t orig_boolForKey = NULL;
static IntImp_t orig_integerForKey = NULL;
static StrImp_t orig_stringForKey = NULL;
static ObjImp_t orig_objectForKey = NULL;
static DataImp_t orig_dataForKey = NULL;
static DictImp_t orig_dictionaryForKey = NULL;

static BOOL new_boolForKey(id self, SEL sel, NSString *key) {
    const char *k = [key UTF8String];
    if (isUDKey(k) || isAuthKey(k)) return YES;
    return orig_boolForKey(self, sel, key);
}

static NSInteger new_integerForKey(id self, SEL sel, NSString *key) {
    const char *k = [key UTF8String];
    NSInteger val = orig_integerForKey(self, sel, key);
    if ((isUDKey(k) || isLevelKey(k)) && val >= 0 && val < 8) return 8;
    return val;
}

static NSString * new_stringForKey(id self, SEL sel, NSString *key) {
    const char *k = [key UTF8String];
    NSString *val = orig_stringForKey(self, sel, key);
    if (!val) return val;
    if (isUDKey(k) || isLevelKey(k)) {
        if ([val isEqualToString:@"0"] || [val isEqualToString:@"1"] || [val isEqualToString:@"2"] ||
            [val isEqualToString:@"3"] || [val isEqualToString:@"4"] || [val isEqualToString:@"5"] ||
            [val isEqualToString:@"6"] || [val isEqualToString:@"7"]) {
            return @"8";
        }
    }
    return val;
}

static id new_objectForKey(id self, SEL sel, NSString *key) {
    const char *k = [key UTF8String];
    id val = orig_objectForKey(self, sel, key);
    if (!val) return val;
    if (isUDKey(k) || isLevelKey(k)) {
        if ([val isKindOfClass:[NSNumber class]]) {
            int iv = [val intValue];
            if (iv >= 0 && iv < 8) return @8;
        } else if ([val isKindOfClass:[NSString class]]) {
            NSString *s = val;
            if ([s isEqualToString:@"0"] || [s isEqualToString:@"1"] || [s isEqualToString:@"2"] ||
                [s isEqualToString:@"3"] || [s isEqualToString:@"4"] || [s isEqualToString:@"5"] ||
                [s isEqualToString:@"6"] || [s isEqualToString:@"7"]) {
                return @"8";
            }
        } else if ([val isKindOfClass:[NSDictionary class]]) {
            NSDictionary *patched = patchDictRecursively(val);
            if (patched) return patched;
        } else if ([val isKindOfClass:[NSData class]]) {
            // Parse NSData as JSON and patch
            NSData *d = val;
            NSError *err = nil;
            id json = [NSJSONSerialization JSONObjectWithData:d options:0 error:&err];
            if (json && [json isKindOfClass:[NSDictionary class]]) {
                NSDictionary *patched = patchDictRecursively(json);
                if (patched) {
                    NSData *newData = [NSJSONSerialization dataWithJSONObject:patched options:0 error:nil];
                    if (newData) return newData;
                }
            }
        }
    }
    return val;
}

// ===== NEW: dataForKey hook =====
static id new_dataForKey(id self, SEL sel, NSString *key) {
    const char *k = [key UTF8String];
    id val = orig_dataForKey(self, sel, key);
    if (!val) return val;
    if (isUDKey(k) || isLevelKey(k) || isAuthKey(k) || isExpireKey(k)) {
        // If the stored value is NSData, try to parse and patch
        if ([val isKindOfClass:[NSData class]]) {
            NSData *d = val;
            NSError *err = nil;
            id json = [NSJSONSerialization JSONObjectWithData:d options:0 error:&err];
            if (json && [json isKindOfClass:[NSDictionary class]]) {
                NSDictionary *patched = patchDictRecursively(json);
                if (patched) {
                    NSData *newData = [NSJSONSerialization dataWithJSONObject:patched options:0 error:nil];
                    if (newData) return newData;
                }
            }
        }
    }
    return val;
}

// ===== NEW: dictionaryForKey hook =====
static id new_dictionaryForKey(id self, SEL sel, NSString *key) {
    const char *k = [key UTF8String];
    id val = orig_dictionaryForKey(self, sel, key);
    if (!val) return val;
    if (isUDKey(k) || isLevelKey(k)) {
        if ([val isKindOfClass:[NSDictionary class]]) {
            NSDictionary *patched = patchDictRecursively(val);
            if (patched) return patched;
        }
    }
    return val;
}

static void hookUserDefaults(void) {
    Class cls = objc_getClass("NSUserDefaults");
    if (!cls) return;

    Method m1 = class_getInstanceMethod(cls, @selector(boolForKey:));
    if (m1) { orig_boolForKey = (BoolImp_t)method_getImplementation(m1); method_setImplementation(m1, (IMP)new_boolForKey); }

    Method m2 = class_getInstanceMethod(cls, @selector(integerForKey:));
    if (m2) { orig_integerForKey = (IntImp_t)method_getImplementation(m2); method_setImplementation(m2, (IMP)new_integerForKey); }

    Method m3 = class_getInstanceMethod(cls, @selector(stringForKey:));
    if (m3) { orig_stringForKey = (StrImp_t)method_getImplementation(m3); method_setImplementation(m3, (IMP)new_stringForKey); }

    Method m4 = class_getInstanceMethod(cls, @selector(objectForKey:));
    if (m4) { orig_objectForKey = (ObjImp_t)method_getImplementation(m4); method_setImplementation(m4, (IMP)new_objectForKey); }

    // NEW in v4.4
    Method m5 = class_getInstanceMethod(cls, @selector(dataForKey:));
    if (m5) { orig_dataForKey = (DataImp_t)method_getImplementation(m5); method_setImplementation(m5, (IMP)new_dataForKey); }

    Method m6 = class_getInstanceMethod(cls, @selector(dictionaryForKey:));
    if (m6) { orig_dictionaryForKey = (DictImp_t)method_getImplementation(m6); method_setImplementation(m6, (IMP)new_dictionaryForKey); }
}

#pragma mark - Hook UILabel setText:

typedef void (*LabelSetTextImp_t)(id, SEL, NSString *);
static LabelSetTextImp_t orig_labelSetText = NULL;

static void new_labelSetText(id self, SEL sel, NSString *text) {
    if (text) {
        NSString *nt = nil;
        if ([text containsString:@"立即开通"] || [text containsString:@"尚未开通"] ||
            [text containsString:@"未开通"] || [text containsString:@"非会员"]) {
            nt = @"VIP会员已开通";
        }
        if (nt) { orig_labelSetText(self, sel, nt); return; }
    }
    orig_labelSetText(self, sel, text);
}

static void hookUILabel(void) {
    Class cls = objc_getClass("UILabel");
    if (!cls) return;
    SEL sel = @selector(setText:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    orig_labelSetText = (LabelSetTextImp_t)method_getImplementation(m);
    method_setImplementation(m, (IMP)new_labelSetText);
}

#pragma mark - Entry

__attribute__((constructor))
static void init(void) {
    NSLog(@"[ElyndorTV] VIP v4.4 MM — 加载中...");
    hookJSONSerialization();
    hookUserDefaults();
    hookUILabel();
    NSLog(@"[ElyndorTV] VIP v4.4 MM — 已激活（NSJSONSerialization + NSUserDefaults(8种) + UILabel）");
}
