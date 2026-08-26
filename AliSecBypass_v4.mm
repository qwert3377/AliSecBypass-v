//
//  ElyndorTV VIP Tweak v4.6 — Detailed JSON Logging + URL Tracking
//  Logs WHAT keys were patched + WHICH URLs returned member data
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#pragma mark - Logger

static NSString *gLogPath = nil;

static NSString *getLogPath(void) {
    if (gLogPath) return gLogPath;
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (docs.count > 0) {
        gLogPath = [[docs[0] stringByAppendingPathComponent:@"vip_v46.log"] copy];
    } else {
        gLogPath = @"/tmp/vip_v46.log";
    }
    return gLogPath;
}

static void vipLog(NSString *fmt, ...) {
    @try {
        va_list args;
        va_start(args, fmt);
        NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
        va_end(args);
        NSString *line = [NSString stringWithFormat:@"%@ [VIP] %@\n",
            [[NSDate date] descriptionWithLocale:nil], msg];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSString *path = getLogPath();
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:data];
            [fh closeFile];
        } else {
            [data writeToFile:path atomically:YES];
        }
    } @catch (NSException *e) {}
}

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

#pragma mark - JSON Patch with detailed logging

static NSDictionary * patchDictRecursively(NSDictionary *dict, int depth) {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) return dict;
    NSArray *keys = [dict allKeys];
    if (!keys || keys.count == 0) return dict;

    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:dict];
    BOOL modified = NO;

    for (NSString *key in keys) {
        const char *kl = [key UTF8String];
        id v = dict[key];
        if (!v) continue;

        if (isLevelKey(kl)) {
            if ([v isKindOfClass:[NSNumber class]]) {
                int iv = [v intValue];
                if (iv >= 0 && iv < 8) {
                    m[key] = @8;
                    modified = YES;
                    vipLog(@"[PATCH] level key='%@' %d->8 (depth=%d)", key, iv, depth);
                }
            } else if ([v isKindOfClass:[NSString class]]) {
                NSString *s = v;
                if ([s isEqualToString:@"0"] || [s isEqualToString:@"1"] || [s isEqualToString:@"2"] ||
                    [s isEqualToString:@"3"] || [s isEqualToString:@"4"] || [s isEqualToString:@"5"] ||
                    [s isEqualToString:@"6"] || [s isEqualToString:@"7"]) {
                    m[key] = @"8";
                    modified = YES;
                    vipLog(@"[PATCH] level key='%@' '%@'->'8' (depth=%d)", key, s, depth);
                }
            }
        }
        else if (isAuthKey(kl)) {
            if ([v isKindOfClass:[NSNumber class]] && [v intValue] == 0) {
                m[key] = @1; modified = YES;
                vipLog(@"[PATCH] auth key='%@' 0->1 (depth=%d)", key, depth);
            }
            else if ([v isKindOfClass:[NSString class]] && [v isEqualToString:@"0"]) {
                m[key] = @"1"; modified = YES;
                vipLog(@"[PATCH] auth key='%@' '0'->'1' (depth=%d)", key, depth);
            }
        }
        else if (isExpireKey(kl)) {
            if ([v isKindOfClass:[NSString class]]) { m[key] = @"2099-12-31"; modified = YES; }
            else if ([v isKindOfClass:[NSNumber class]]) { m[key] = @(4102444799000LL); modified = YES; }
        }
        else if ([v isKindOfClass:[NSDictionary class]]) {
            NSDictionary *n = patchDictRecursively(v, depth + 1);
            if (n != v) { m[key] = n; modified = YES; }
        }
        else if ([v isKindOfClass:[NSArray class]]) {
            NSArray *arr = v;
            NSMutableArray *ma = [NSMutableArray arrayWithArray:arr];
            BOOL arrMod = NO;
            for (NSUInteger j = 0; j < ma.count; j++) {
                id item = ma[j];
                if ([item isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *np = patchDictRecursively(item, depth + 1);
                    if (np != item) { ma[j] = np; arrMod = YES; }
                }
            }
            if (arrMod) { m[key] = ma; modified = YES; }
        }
    }
    return modified ? m : dict;
}

#pragma mark - NSJSONSerialization Hook with URL tracking

static NSString *gLastURL = nil;

typedef id (*JSONImp_t)(Class, SEL, NSData *, NSJSONReadingOptions, NSError **);
static JSONImp_t orig_JSON = NULL;

static id new_JSON(Class cls, SEL sel, NSData *data, NSJSONReadingOptions opt, NSError **error) {
    id result = orig_JSON(cls, sel, data, opt, error);
    if ([result isKindOfClass:[NSDictionary class]]) {
        NSDictionary *patched = patchDictRecursively(result, 0);
        if (patched != result) {
            vipLog(@"[JSON] Patched dict from URL: %@", gLastURL ?: @"<unknown>");
            return patched;
        }
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
    vipLog(@"[HOOK] NSJSONSerialization");
}

#pragma mark - NSURLSession URL Logger (safe, no block wrap)

typedef id (*DTImp_t)(id, SEL, id, id);
static DTImp_t orig_dtReq = NULL;
static DTImp_t orig_dtURL = NULL;

static id new_dtReq(id self, SEL sel, id req, id completion) {
    NSString *url = nil;
    if ([req isKindOfClass:[NSURLRequest class]]) {
        url = [[req URL] absoluteString];
    }
    if (url) {
        gLastURL = url;
        // Log member-related URLs
        NSString *lower = [url lowercaseString];
        if ([lower containsString:@"member"] || [lower containsString:@"vip"] ||
            [lower containsString:@"user"] || [lower containsString:@"account"] ||
            [lower containsString:@"profile"] || [lower containsString:@"tier"] ||
            [lower containsString:@"level"] || [lower containsString:@"grade"]) {
            vipLog(@"[NET-MEMBER] %@", url);
        }
    }
    return orig_dtReq(self, sel, req, completion);
}

static id new_dtURL(id self, SEL sel, id url, id completion) {
    if ([url isKindOfClass:[NSURL class]]) {
        NSString *urlStr = [url absoluteString];
        gLastURL = urlStr;
        NSString *lower = [urlStr lowercaseString];
        if ([lower containsString:@"member"] || [lower containsString:@"vip"] ||
            [lower containsString:@"user"] || [lower containsString:@"account"] ||
            [lower containsString:@"profile"] || [lower containsString:@"tier"] ||
            [lower containsString:@"level"] || [lower containsString:@"grade"]) {
            vipLog(@"[NET-MEMBER] %@", urlStr);
        }
    }
    return orig_dtURL(self, sel, url, completion);
}

static void hookNSURLSession(void) {
    Class cls = objc_getClass("NSURLSession");
    if (!cls) return;
    Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
    if (m1) { orig_dtReq = (DTImp_t)method_getImplementation(m1); method_setImplementation(m1, (IMP)new_dtReq); }
    Method m2 = class_getInstanceMethod(cls, @selector(dataTaskWithURL:completionHandler:));
    if (m2) { orig_dtURL = (DTImp_t)method_getImplementation(m2); method_setImplementation(m2, (IMP)new_dtURL); }
    vipLog(@"[HOOK] NSURLSession");
}

#pragma mark - NSUserDefaults Hooks

typedef BOOL (*BoolImp_t)(id, SEL, NSString *);
typedef NSInteger (*IntImp_t)(id, SEL, NSString *);
typedef NSString * (*StrImp_t)(id, SEL, NSString *);
typedef id (*ObjImp_t)(id, SEL, NSString *);

static BoolImp_t orig_boolForKey = NULL;
static IntImp_t orig_integerForKey = NULL;
static StrImp_t orig_stringForKey = NULL;
static ObjImp_t orig_objectForKey = NULL;

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
            NSDictionary *patched = patchDictRecursively(val, 0);
            if (patched != val) return patched;
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
    vipLog(@"[HOOK] NSUserDefaults");
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
    vipLog(@"[HOOK] UILabel");
}

#pragma mark - Entry

__attribute__((constructor))
static void init(void) {
    vipLog(@"========================================");
    vipLog(@"ElyndorTV VIP Tweak v4.6");
    vipLog(@"Build: 2026-08-26");
    vipLog(@"Log: %@", getLogPath());
    vipLog(@"========================================");

    hookJSONSerialization();
    hookNSURLSession();
    hookUserDefaults();
    hookUILabel();

    vipLog(@"[INIT] All hooks installed");
}
