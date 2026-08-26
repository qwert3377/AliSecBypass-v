//
//  ElyndorTV VIP Tweak v10.0
//  Target: LysenthoTVSpace (com.influx4.motion.axis26)
//  Build: 2026-08-26
//  Strategy: Pure Runtime Hook (no Logos %hook)
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define MAX_TIER 8
#define VIP_KEY @"kvipstatusstoragekey"

#pragma mark - Fake Data Builder

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
}

#pragma mark - NSUserDefaults Hooks

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

static id hook_objectForKey(id self, SEL _cmd, NSString *key) {
    if ([key isEqualToString:VIP_KEY] || isMemberKey(key)) {
        NSLog(@"[VIP] objectForKey:'%@' -> fake dict", key);
        return buildFakeVipDict();
    }
    return orig_objectForKey(self, _cmd, key);
}

static id hook_stringForKey(id self, SEL _cmd, NSString *key) {
    if (isMemberKey(key)) {
        NSLog(@"[VIP] stringForKey:'%@' -> fake JSON", key);
        return @"{\"isVip\":true,\"tier\":8,\"level\":8,\"grade\":8}";
    }
    return orig_stringForKey(self, _cmd, key);
}

static id hook_dataForKey(id self, SEL _cmd, NSString *key) {
    if (isMemberKey(key)) {
        NSLog(@"[VIP] dataForKey:'%@' -> fake data", key);
        return [NSJSONSerialization dataWithJSONObject:buildFakeVipDict() options:0 error:nil];
    }
    return orig_dataForKey(self, _cmd, key);
}

static id hook_dictionaryForKey(id self, SEL _cmd, NSString *key) {
    if (isMemberKey(key)) {
        NSLog(@"[VIP] dictionaryForKey:'%@' -> fake dict", key);
        return buildFakeVipDict();
    }
    return orig_dictionaryForKey(self, _cmd, key);
}

static id hook_arrayForKey(id self, SEL _cmd, NSString *key) {
    if (isMemberKey(key)) return @[];
    return orig_arrayForKey(self, _cmd, key);
}

static NSInteger hook_integerForKey(id self, SEL _cmd, NSString *key) {
    if (isMemberKey(key)) {
        NSLog(@"[VIP] integerForKey:'%@' -> %d", key, MAX_TIER);
        return MAX_TIER;
    }
    return orig_integerForKey(self, _cmd, key);
}

static int hook_intForKey(id self, SEL _cmd, NSString *key) {
    if (isMemberKey(key)) return MAX_TIER;
    return orig_intForKey(self, _cmd, key);
}

static BOOL hook_boolForKey(id self, SEL _cmd, NSString *key) {
    if (isMemberKey(key)) {
        NSLog(@"[VIP] boolForKey:'%@' -> YES", key);
        return YES;
    }
    return orig_boolForKey(self, _cmd, key);
}

static double hook_doubleForKey(id self, SEL _cmd, NSString *key) {
    if (isMemberKey(key)) return 4102444800.0;
    return orig_doubleForKey(self, _cmd, key);
}

static float hook_floatForKey(id self, SEL _cmd, NSString *key) {
    if (isMemberKey(key)) return 4102444800.0f;
    return orig_floatForKey(self, _cmd, key);
}

static void hook_setObject(id self, SEL _cmd, id value, NSString *key) {
    if ([key isEqualToString:VIP_KEY] || isMemberKey(key)) {
        NSLog(@"[VIP] BLOCKED setObject:forKey:'%@'", key);
        return;
    }
    orig_setObject(self, _cmd, value, key);
}

static void hook_setInteger(id self, SEL _cmd, NSInteger value, NSString *key) {
    if (isMemberKey(key)) {
        NSLog(@"[VIP] BLOCKED setInteger:forKey:'%@'", key);
        return;
    }
    orig_setInteger(self, _cmd, value, key);
}

static void hook_setBool(id self, SEL _cmd, BOOL value, NSString *key) {
    if (isMemberKey(key)) {
        NSLog(@"[VIP] BLOCKED setBool:forKey:'%@'", key);
        return;
    }
    orig_setBool(self, _cmd, value, key);
}

static void hook_setDouble(id self, SEL _cmd, double value, NSString *key) {
    if (isMemberKey(key)) {
        NSLog(@"[VIP] BLOCKED setDouble:forKey:'%@'", key);
        return;
    }
    orig_setDouble(self, _cmd, value, key);
}

static void hook_setFloat(id self, SEL _cmd, float value, NSString *key) {
    if (isMemberKey(key)) {
        NSLog(@"[VIP] BLOCKED setFloat:forKey:'%@'", key);
        return;
    }
    orig_setFloat(self, _cmd, value, key);
}

static void hook_removeObject(id self, SEL _cmd, NSString *key) {
    if ([key isEqualToString:VIP_KEY] || isMemberKey(key)) {
        NSLog(@"[VIP] BLOCKED removeObjectForKey:'%@'", key);
        return;
    }
    orig_removeObject(self, _cmd, key);
}

#pragma mark - NSJSONSerialization Hook

static id (*orig_JSONWithData)(Class, SEL, NSData *, NSJSONReadingOptions, NSError **);

static id hook_JSONWithData(Class self, SEL _cmd, NSData *data, NSJSONReadingOptions opt, NSError **error) {
    id result = orig_JSONWithData(self, _cmd, data, opt, error);
    if (![result isKindOfClass:[NSDictionary class]]) return result;

    NSDictionary *dict = result;
    BOOL isMember = NO;
    for (NSString *k in dict.allKeys) {
        NSString *lower = [k lowercaseString];
        if ([lower containsString:@"vip"] || [lower containsString:@"member"] ||
            [lower containsString:@"tier"] || [lower containsString:@"level"] ||
            [lower containsString:@"grade"] || [lower containsString:@"premium"] ||
            [lower containsString:@"subscri"] || [lower containsString:@"expire"]) {
            isMember = YES;
            break;
        }
    }

    if (isMember) {
        NSLog(@"[VIP] JSON member response detected");
        if ([result isKindOfClass:[NSMutableDictionary class]]) {
            NSMutableDictionary *md = result;
            md[@"isVip"]     = @YES;
            md[@"tier"]      = @(MAX_TIER);
            md[@"level"]     = @(MAX_TIER);
            md[@"grade"]     = @(MAX_TIER);
            md[@"status"]    = @"active";
            md[@"expireTime"] = @(4102444800);
            NSLog(@"[VIP] Injected into mutable JSON dict");
        }
    }
    return result;
}

#pragma mark - NSKeyedUnarchiver Hooks

static id (*orig_unarchivedObject)(Class, SEL, Class, NSData *, NSError **);
static id (*orig_unarchiveObject)(Class, SEL, NSData *);

static id hook_unarchivedObject(Class self, SEL _cmd, Class cls, NSData *data, NSError **error) {
    id result = orig_unarchivedObject(self, _cmd, cls, data, error);
    NSString *name = NSStringFromClass(cls);
    if ([name containsString:@"Member"] || [name containsString:@"VIP"] ||
        [name containsString:@"Tier"] || [name containsString:@"Level"] ||
        [name containsString:@"Account"] || [name containsString:@"Profile"]) {
        NSLog(@"[VIP] Unarchived member class: %@ -> %@", name, result);
    }
    return result;
}

static id hook_unarchiveObject(Class self, SEL _cmd, NSData *data) {
    id result = orig_unarchiveObject(self, _cmd, data);
    if (result) {
        NSString *name = NSStringFromClass([result class]);
        if ([name containsString:@"Member"] || [name containsString:@"VIP"] ||
            [name containsString:@"Tier"] || [name containsString:@"Level"]) {
            NSLog(@"[VIP] Unarchived object: %@ -> %@", name, result);
        }
    }
    return result;
}

#pragma mark - NSDate Hook (expire checks)

static id (*orig_dateWithTI)(Class, SEL, NSTimeInterval);

static id hook_dateWithTI(Class self, SEL _cmd, NSTimeInterval ti) {
    if (ti > 1000000000 && ti < 1704067200) {
        NSLog(@"[VIP] Rewriting past NSDate %f -> 4102444800", ti);
        return orig_dateWithTI(self, _cmd, 4102444800);
    }
    return orig_dateWithTI(self, _cmd, ti);
}

#pragma mark - Helper

static void swizzle(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) m = class_getClassMethod(cls, sel);
    if (!m) {
        NSLog(@"[VIP] WARNING: method not found %@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    *origImp = method_setImplementation(m, newImp);
}

static void swizzleClass(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) {
        NSLog(@"[VIP] WARNING: class method not found %@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    *origImp = method_setImplementation(m, newImp);
}

#pragma mark - Constructor

__attribute__((constructor))
static void init(void) {
    NSLog(@"[VIP] ============================================");
    NSLog(@"[VIP] ElyndorTV VIP Tweak v10.0 Loading");
    NSLog(@"[VIP] Build: 2026-08-26");
    NSLog(@"[VIP] Target: LysenthoTVSpace");
    NSLog(@"[VIP] Max Tier: %d", MAX_TIER);
    NSLog(@"[VIP] ============================================");

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

    Class JSON = [NSJSONSerialization class];
    swizzleClass(JSON, @selector(JSONObjectWithData:options:error:), (IMP)hook_JSONWithData, (IMP *)&orig_JSONWithData);

    Class Unarchiver = [NSKeyedUnarchiver class];
    swizzleClass(Unarchiver, @selector(unarchivedObjectOfClass:fromData:error:), (IMP)hook_unarchivedObject, (IMP *)&orig_unarchivedObject);
    swizzleClass(Unarchiver, @selector(unarchiveObjectWithData:), (IMP)hook_unarchiveObject, (IMP *)&orig_unarchiveObject);

    Class NSDateClass = [NSDate class];
    swizzleClass(NSDateClass, @selector(dateWithTimeIntervalSince1970:), (IMP)hook_dateWithTI, (IMP *)&orig_dateWithTI);

    // Initial injection
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:buildFakeVipDict() forKey:VIP_KEY];
    [ud synchronize];
    NSLog(@"[VIP] Injected fake VIP dict at load time");

    // Re-inject after delay (catch async loads)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSUserDefaults *ud2 = [NSUserDefaults standardUserDefaults];
        [ud2 setObject:buildFakeVipDict() forKey:VIP_KEY];
        [ud2 synchronize];
        NSLog(@"[VIP] Re-injected after 3s delay");
    });

    NSLog(@"[VIP] All hooks installed, tweak active");
}
