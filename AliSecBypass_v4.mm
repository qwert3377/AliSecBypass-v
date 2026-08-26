//
//  ElyndorTV VIP Safe Tweak v11.0
//  Target: LysenthoTVSpace (com.influx4.motion.axis26)
//  Build: 2026-08-26
//  Strategy: NSUserDefaults ONLY + file logging + crash-proof
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define MAX_TIER 8
#define VIP_KEY @"kvipstatusstoragekey"

static NSString *gLogPath = nil;

#pragma mark - File Logger (write to App Documents)

static void vipLog(NSString *fmt, ...) {
    @try {
        if (!gLogPath) {
            NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            if (docs.count > 0) {
                gLogPath = [[docs[0] stringByAppendingPathComponent:@"vip_tweak.log"] copy];
            }
        }
        if (!gLogPath) return;

        va_list args;
        va_start(args, fmt);
        NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
        va_end(args);

        NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
            [[NSDate date] descriptionWithLocale:nil], msg];

        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:gLogPath]) {
            [fm createFileAtPath:gLogPath contents:data attributes:nil];
        } else {
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
            if (fh) {
                [fh seekToEndOfFile];
                [fh writeData:data];
                [fh closeFile];
            }
        }
    } @catch (NSException *e) {
        // silent fail
    }
}

#pragma mark - Fake Data

static NSMutableDictionary *buildFakeVipDict(void) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"isVip"]        = @YES;
    d[@"isMember"]     = @YES;
    d[@"tier"]         = @(MAX_TIER);
    d[@"level"]        = @(MAX_TIER);
    d[@"grade"]        = @(MAX_TIER);
    d[@"vipLevel"]     = @(MAX_TIER);
    d[@"memberLevel"]  = @(MAX_TIER);
    d[@"expireTime"]   = @(4102444800);
    d[@"vipExpire"]    = @(4102444800);
    d[@"memberExpire"] = @(4102444800);
    d[@"status"]       = @"active";
    d[@"type"]         = @"lifetime";
    d[@"membershipType"] = @"premium";
    return d;
}

static BOOL isMemberKey(NSString *key) {
    @try {
        if (!key) return NO;
        NSString *lower = [key lowercaseString];
        return [lower containsString:@"vip"]
            || [lower containsString:@"member"]
            || [lower containsString:@"tier"]
            || [lower containsString:@"level"]
            || [lower containsString:@"grade"]
            || [lower containsString:@"premium"]
            || [lower containsString:@"subscri"]
            || [lower containsString:@"expire"];
    } @catch (NSException *e) { return NO; }
}

#pragma mark - Original IMPs

static id  (*orig_objectForKey)(id, SEL, NSString *);
static id  (*orig_stringForKey)(id, SEL, NSString *);
static id  (*orig_dataForKey)(id, SEL, NSString *);
static id  (*orig_dictionaryForKey)(id, SEL, NSString *);
static id  (*orig_arrayForKey)(id, SEL, NSString *);
static NSInteger (*orig_integerForKey)(id, SEL, NSString *);
static int   (*orig_intForKey)(id, SEL, NSString *);
static BOOL  (*orig_boolForKey)(id, SEL, NSString *);
static double (*orig_doubleForKey)(id, SEL, NSString *);
static float (*orig_floatForKey)(id, SEL, NSString *);

static void (*orig_setObject)(id, SEL, id, NSString *);
static void (*orig_setInteger)(id, SEL, NSInteger, NSString *);
static void (*orig_setBool)(id, SEL, BOOL, NSString *);
static void (*orig_setDouble)(id, SEL, double, NSString *);
static void (*orig_setFloat)(id, SEL, float, NSString *);
static void (*orig_removeObject)(id, SEL, NSString *);

#pragma mark - Hooks

static id hook_objectForKey(id self, SEL _cmd, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[FAKE] objectForKey:'%@' -> dict", key);
            return buildFakeVipDict();
        }
    } @catch (NSException *e) {}
    return orig_objectForKey(self, _cmd, key);
}

static id hook_stringForKey(id self, SEL _cmd, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[FAKE] stringForKey:'%@' -> JSON", key);
            return @"{\"isVip\":true,\"tier\":8,\"level\":8,\"grade\":8}";
        }
    } @catch (NSException *e) {}
    return orig_stringForKey(self, _cmd, key);
}

static id hook_dataForKey(id self, SEL _cmd, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[FAKE] dataForKey:'%@' -> data", key);
            return [NSJSONSerialization dataWithJSONObject:buildFakeVipDict() options:0 error:nil];
        }
    } @catch (NSException *e) {}
    return orig_dataForKey(self, _cmd, key);
}

static id hook_dictionaryForKey(id self, SEL _cmd, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[FAKE] dictionaryForKey:'%@' -> dict", key);
            return buildFakeVipDict();
        }
    } @catch (NSException *e) {}
    return orig_dictionaryForKey(self, _cmd, key);
}

static id hook_arrayForKey(id self, SEL _cmd, NSString *key) {
    @try {
        if (isMemberKey(key)) return @[];
    } @catch (NSException *e) {}
    return orig_arrayForKey(self, _cmd, key);
}

static NSInteger hook_integerForKey(id self, SEL _cmd, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[FAKE] integerForKey:'%@' -> %d", key, MAX_TIER);
            return MAX_TIER;
        }
    } @catch (NSException *e) {}
    return orig_integerForKey(self, _cmd, key);
}

static int hook_intForKey(id self, SEL _cmd, NSString *key) {
    @try {
        if (isMemberKey(key)) return MAX_TIER;
    } @catch (NSException *e) {}
    return orig_intForKey(self, _cmd, key);
}

static BOOL hook_boolForKey(id self, SEL _cmd, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[FAKE] boolForKey:'%@' -> YES", key);
            return YES;
        }
    } @catch (NSException *e) {}
    return orig_boolForKey(self, _cmd, key);
}

static double hook_doubleForKey(id self, SEL _cmd, NSString *key) {
    @try {
        if (isMemberKey(key)) return 4102444800.0;
    } @catch (NSException *e) {}
    return orig_doubleForKey(self, _cmd, key);
}

static float hook_floatForKey(id self, SEL _cmd, NSString *key) {
    @try {
        if (isMemberKey(key)) return 4102444800.0f;
    } @catch (NSException *e) {}
    return orig_floatForKey(self, _cmd, key);
}

static void hook_setObject(id self, SEL _cmd, id value, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[BLOCK] setObject:forKey:'%@'", key);
            return;
        }
    } @catch (NSException *e) {}
    orig_setObject(self, _cmd, value, key);
}

static void hook_setInteger(id self, SEL _cmd, NSInteger value, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[BLOCK] setInteger:forKey:'%@'", key);
            return;
        }
    } @catch (NSException *e) {}
    orig_setInteger(self, _cmd, value, key);
}

static void hook_setBool(id self, SEL _cmd, BOOL value, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[BLOCK] setBool:forKey:'%@'", key);
            return;
        }
    } @catch (NSException *e) {}
    orig_setBool(self, _cmd, value, key);
}

static void hook_setDouble(id self, SEL _cmd, double value, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[BLOCK] setDouble:forKey:'%@'", key);
            return;
        }
    } @catch (NSException *e) {}
    orig_setDouble(self, _cmd, value, key);
}

static void hook_setFloat(id self, SEL _cmd, float value, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[BLOCK] setFloat:forKey:'%@'", key);
            return;
        }
    } @catch (NSException *e) {}
    orig_setFloat(self, _cmd, value, key);
}

static void hook_removeObject(id self, SEL _cmd, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[BLOCK] removeObjectForKey:'%@'", key);
            return;
        }
    } @catch (NSException *e) {}
    orig_removeObject(self, _cmd, key);
}

#pragma mark - Swizzle Helper

static void swizzle(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    @try {
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) m = class_getClassMethod(cls, sel);
        if (!m) {
            vipLog(@"[WARN] method not found %@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
            return;
        }
        *origImp = method_setImplementation(m, newImp);
    } @catch (NSException *e) {
        vipLog(@"[WARN] swizzle exception: %@", e);
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void init(void) {
    // Init log path early
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (docs.count > 0) {
        gLogPath = [[docs[0] stringByAppendingPathComponent:@"vip_tweak.log"] copy];
    }

    vipLog(@"========================================");
    vipLog(@"ElyndorTV VIP Safe Tweak v11.0 Loading");
    vipLog(@"Build: 2026-08-26");
    vipLog(@"Target: LysenthoTVSpace");
    vipLog(@"Max Tier: %d", MAX_TIER);
    vipLog(@"Log: %@", gLogPath ?: @"<unknown>");
    vipLog(@"========================================");

    Class UD = [NSUserDefaults class];
    swizzle(UD, @selector(objectForKey:),            (IMP)hook_objectForKey,      (IMP *)&orig_objectForKey);
    swizzle(UD, @selector(stringForKey:),            (IMP)hook_stringForKey,      (IMP *)&orig_stringForKey);
    swizzle(UD, @selector(dataForKey:),              (IMP)hook_dataForKey,        (IMP *)&orig_dataForKey);
    swizzle(UD, @selector(dictionaryForKey:),        (IMP)hook_dictionaryForKey,  (IMP *)&orig_dictionaryForKey);
    swizzle(UD, @selector(arrayForKey:),             (IMP)hook_arrayForKey,       (IMP *)&orig_arrayForKey);
    swizzle(UD, @selector(integerForKey:),           (IMP)hook_integerForKey,     (IMP *)&orig_integerForKey);
    swizzle(UD, @selector(intForKey:),               (IMP)hook_intForKey,         (IMP *)&orig_intForKey);
    swizzle(UD, @selector(boolForKey:),              (IMP)hook_boolForKey,        (IMP *)&orig_boolForKey);
    swizzle(UD, @selector(doubleForKey:),            (IMP)hook_doubleForKey,      (IMP *)&orig_doubleForKey);
    swizzle(UD, @selector(floatForKey:),             (IMP)hook_floatForKey,       (IMP *)&orig_floatForKey);
    swizzle(UD, @selector(setObject:forKey:),        (IMP)hook_setObject,         (IMP *)&orig_setObject);
    swizzle(UD, @selector(setInteger:forKey:),       (IMP)hook_setInteger,        (IMP *)&orig_setInteger);
    swizzle(UD, @selector(setBool:forKey:),          (IMP)hook_setBool,           (IMP *)&orig_setBool);
    swizzle(UD, @selector(setDouble:forKey:),        (IMP)hook_setDouble,         (IMP *)&orig_setDouble);
    swizzle(UD, @selector(setFloat:forKey:),         (IMP)hook_setFloat,          (IMP *)&orig_setFloat);
    swizzle(UD, @selector(removeObjectForKey:),      (IMP)hook_removeObject,      (IMP *)&orig_removeObject);

    // Initial injection
    @try {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setObject:buildFakeVipDict() forKey:VIP_KEY];
        [ud synchronize];
        vipLog(@"[INIT] Injected fake VIP dict at load time");
    } @catch (NSException *e) {
        vipLog(@"[INIT] Injection failed: %@", e);
    }

    // Re-inject after delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            NSUserDefaults *ud2 = [NSUserDefaults standardUserDefaults];
            [ud2 setObject:buildFakeVipDict() forKey:VIP_KEY];
            [ud2 synchronize];
            vipLog(@"[INIT] Re-injected after 3s delay");
        } @catch (NSException *e) {
            vipLog(@"[INIT] Re-inject failed: %@", e);
        }
    });

    vipLog(@"[INIT] All hooks installed, tweak active");
}
