//
// vip_hook_balecc.mm
// TrollStore inject dylib for com.balecc.iosv2
// Pure ObjC Runtime, no Logos syntax
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ========== Logging ==========
static NSString* vipLogPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = [paths firstObject];
    return [doc stringByAppendingPathComponent:@"vip_hook.log"];
}

static void vipLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSString *path = vipLogPath();
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    NSLog(@"[VIP] %@", msg);
}

// ========== NSUserDefaults Original IMPs ==========
static id (*orig_objectForKey)(id, SEL, NSString*);
static NSString* (*orig_stringForKey)(id, SEL, NSString*);
static NSInteger (*orig_integerForKey)(id, SEL, NSString*);
static BOOL (*orig_boolForKey)(id, SEL, NSString*);
static double (*orig_doubleForKey)(id, SEL, NSString*);
static void (*orig_setObject)(id, SEL, id, NSString*);
static void (*orig_setInteger)(id, SEL, NSInteger, NSString*);
static void (*orig_setBool)(id, SEL, BOOL, NSString*);
static void (*orig_setDouble)(id, SEL, double, NSString*);

// ========== NSUserDefaults Hooks ==========
static id vip_objectForKey(id self, SEL _cmd, NSString *key) {
    id val = orig_objectForKey(self, _cmd, key);
    NSString *lk = [key lowercaseString];
    if ([lk isEqualToString:@"is_vip"] || [lk isEqualToString:@"vip"] ||
        [lk isEqualToString:@"is_member"] || [lk isEqualToString:@"member"] ||
        [lk isEqualToString:@"is_premium"] || [lk isEqualToString:@"premium"] ||
        [lk isEqualToString:@"is_pro"] || [lk isEqualToString:@"pro"] ||
        [lk isEqualToString:@"subscribed"] || [lk isEqualToString:@"is_subscribed"] ||
        [lk isEqualToString:@"has_subscription"] || [lk isEqualToString:@"is_active"] ||
        [lk isEqualToString:@"active"] || [lk isEqualToString:@"enabled"] ||
        [lk isEqualToString:@"valid"]) {
        vipLog(@"Prefs.READ objectForKey:%@ -> FORCED YES", key);
        return @YES;
    }
    if ([lk isEqualToString:@"vip_level"] || [lk isEqualToString:@"member_level"] ||
        [lk isEqualToString:@"grade"] || [lk isEqualToString:@"level"] ||
        [lk isEqualToString:@"remaining_days"] || [lk isEqualToString:@"days_left"] ||
        [lk isEqualToString:@"days"]) {
        vipLog(@"Prefs.READ objectForKey:%@ -> FORCED 9999", key);
        return @(9999);
    }
    if ([lk isEqualToString:@"expire_time"] || [lk isEqualToString:@"vip_expire"] ||
        [lk isEqualToString:@"expire"] || [lk isEqualToString:@"expired_at"] ||
        [lk isEqualToString:@"deadline"] || [lk isEqualToString:@"end_time"]) {
        vipLog(@"Prefs.READ objectForKey:%@ -> FORCED 2099-12-31", key);
        return @"2099-12-31T23:59:59Z";
    }
    if ([lk isEqualToString:@"plan"] || [lk isEqualToString:@"plan_name"] ||
        [lk isEqualToString:@"plan_type"] || [lk isEqualToString:@"package"] ||
        [lk isEqualToString:@"package_name"] || [lk isEqualToString:@"package_type"] ||
        [lk isEqualToString:@"user_type"] || [lk isEqualToString:@"member_type"] ||
        [lk isEqualToString:@"vip_type"]) {
        vipLog(@"Prefs.READ objectForKey:%@ -> FORCED Pro", key);
        return @"Pro";
    }
    if ([lk isEqualToString:@"traffic_limit"] || [lk isEqualToString:@"traffic_total"] ||
        [lk isEqualToString:@"traffic_remaining"] || [lk isEqualToString:@"traffic"]) {
        vipLog(@"Prefs.READ objectForKey:%@ -> FORCED 999999", key);
        return @(999999);
    }
    if ([lk isEqualToString:@"traffic_used"]) {
        vipLog(@"Prefs.READ objectForKey:%@ -> FORCED 0", key);
        return @(0);
    }
    vipLog(@"Prefs.READ objectForKey:%@ val=%@", key, val);
    return val;
}

static NSString* vip_stringForKey(id self, SEL _cmd, NSString *key) {
    NSString *val = orig_stringForKey(self, _cmd, key);
    NSString *lk = [key lowercaseString];
    if ([lk isEqualToString:@"expire_time"] || [lk isEqualToString:@"vip_expire"] ||
        [lk isEqualToString:@"expire"] || [lk isEqualToString:@"expired_at"] ||
        [lk isEqualToString:@"deadline"] || [lk isEqualToString:@"end_time"]) {
        vipLog(@"Prefs.READ stringForKey:%@ -> FORCED 2099-12-31", key);
        return @"2099-12-31T23:59:59Z";
    }
    if ([lk isEqualToString:@"plan"] || [lk isEqualToString:@"plan_name"] ||
        [lk isEqualToString:@"plan_type"] || [lk isEqualToString:@"package"] ||
        [lk isEqualToString:@"package_name"] || [lk isEqualToString:@"package_type"] ||
        [lk isEqualToString:@"user_type"] || [lk isEqualToString:@"member_type"] ||
        [lk isEqualToString:@"vip_type"]) {
        vipLog(@"Prefs.READ stringForKey:%@ -> FORCED Pro", key);
        return @"Pro";
    }
    vipLog(@"Prefs.READ stringForKey:%@ val=%@", key, val);
    return val;
}

static NSInteger vip_integerForKey(id self, SEL _cmd, NSString *key) {
    NSInteger val = orig_integerForKey(self, _cmd, key);
    NSString *lk = [key lowercaseString];
    if ([lk isEqualToString:@"vip_level"] || [lk isEqualToString:@"member_level"] ||
        [lk isEqualToString:@"grade"] || [lk isEqualToString:@"level"] ||
        [lk isEqualToString:@"remaining_days"] || [lk isEqualToString:@"days_left"] ||
        [lk isEqualToString:@"days"]) {
        vipLog(@"Prefs.READ integerForKey:%@ -> FORCED 9999", key);
        return 9999;
    }
    if ([lk isEqualToString:@"traffic_limit"] || [lk isEqualToString:@"traffic_total"] ||
        [lk isEqualToString:@"traffic_remaining"] || [lk isEqualToString:@"traffic"]) {
        vipLog(@"Prefs.READ integerForKey:%@ -> FORCED 999999", key);
        return 999999;
    }
    if ([lk isEqualToString:@"traffic_used"]) {
        vipLog(@"Prefs.READ integerForKey:%@ -> FORCED 0", key);
        return 0;
    }
    vipLog(@"Prefs.READ integerForKey:%@ val=%ld", key, (long)val);
    return val;
}

static BOOL vip_boolForKey(id self, SEL _cmd, NSString *key) {
    NSString *lk = [key lowercaseString];
    if ([lk isEqualToString:@"is_vip"] || [lk isEqualToString:@"vip"] ||
        [lk isEqualToString:@"is_member"] || [lk isEqualToString:@"member"] ||
        [lk isEqualToString:@"is_premium"] || [lk isEqualToString:@"premium"] ||
        [lk isEqualToString:@"is_pro"] || [lk isEqualToString:@"pro"] ||
        [lk isEqualToString:@"subscribed"] || [lk isEqualToString:@"is_subscribed"] ||
        [lk isEqualToString:@"has_subscription"] || [lk isEqualToString:@"is_active"] ||
        [lk isEqualToString:@"active"] || [lk isEqualToString:@"enabled"] ||
        [lk isEqualToString:@"valid"] || [lk isEqualToString:@"trial"] ||
        [lk isEqualToString:@"is_trial"]) {
        vipLog(@"Prefs.READ boolForKey:%@ -> FORCED YES", key);
        return YES;
    }
    BOOL val = orig_boolForKey(self, _cmd, key);
    vipLog(@"Prefs.READ boolForKey:%@ val=%d", key, val);
    return val;
}

static double vip_doubleForKey(id self, SEL _cmd, NSString *key) {
    NSString *lk = [key lowercaseString];
    if ([lk isEqualToString:@"expire_time"] || [lk isEqualToString:@"vip_expire"] ||
        [lk isEqualToString:@"expire"] || [lk isEqualToString:@"expired_at"] ||
        [lk isEqualToString:@"deadline"] || [lk isEqualToString:@"end_time"]) {
        vipLog(@"Prefs.READ doubleForKey:%@ -> FORCED 4102444800", key);
        return 4102444800.0;
    }
    double val = orig_doubleForKey(self, _cmd, key);
    vipLog(@"Prefs.READ doubleForKey:%@ val=%f", key, val);
    return val;
}

static void vip_setObject(id self, SEL _cmd, id val, NSString *key) {
    vipLog(@"Prefs.WRITE setObject:%@ forKey:%@", val, key);
    orig_setObject(self, _cmd, val, key);
}

static void vip_setInteger(id self, SEL _cmd, NSInteger val, NSString *key) {
    vipLog(@"Prefs.WRITE setInteger:%ld forKey:%@", (long)val, key);
    orig_setInteger(self, _cmd, val, key);
}

static void vip_setBool(id self, SEL _cmd, BOOL val, NSString *key) {
    vipLog(@"Prefs.WRITE setBool:%d forKey:%@", val, key);
    orig_setBool(self, _cmd, val, key);
}

static void vip_setDouble(id self, SEL _cmd, double val, NSString *key) {
    vipLog(@"Prefs.WRITE setDouble:%f forKey:%@", val, key);
    orig_setDouble(self, _cmd, val, key);
}

// ========== Inject VIP Defaults ==========
static void injectVIPDefaults(void) {
    vipLog(@"=== Injecting VIP Defaults ===");
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSDictionary *injections = @{
        @"is_vip": @YES, @"vip": @YES, @"vip_status": @1,
        @"is_member": @YES, @"member": @YES, @"member_status": @1,
        @"is_premium": @YES, @"premium": @YES,
        @"is_pro": @YES, @"pro": @YES,
        @"subscribed": @YES, @"is_subscribed": @YES,
        @"has_subscription": @YES,
        @"user_type": @"vip", @"member_type": @"vip", @"vip_type": @"lifetime",
        @"vip_level": @3, @"member_level": @3, @"grade": @3, @"level": @3,
        @"expire_time": @"2099-12-31T23:59:59Z", @"vip_expire": @"2099-12-31T23:59:59Z",
        @"expire": @"2099-12-31T23:59:59Z", @"expired_at": @"2099-12-31T23:59:59Z",
        @"deadline": @"2099-12-31T23:59:59Z", @"end_time": @"2099-12-31T23:59:59Z",
        @"plan": @"Pro", @"plan_name": @"Pro计划", @"plan_type": @"pro",
        @"package": @"Pro", @"package_name": @"Pro计划", @"package_type": @"pro",
        @"traffic_limit": @999999, @"traffic_total": @999999,
        @"traffic_used": @0, @"traffic_remaining": @999999,
        @"remaining_days": @9999, @"days_left": @9999, @"days": @9999,
        @"is_trial": @NO, @"trial": @NO,
        @"is_active": @YES, @"active": @YES,
        @"enabled": @YES, @"valid": @YES,
        @"subscribe_url": @"https://api.ibale.cc/v1/user/subscribe",
        @"subscribe_token": @"fake_vip_token",
    };
    [injections enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        [defs setObject:obj forKey:key];
    }];
    [defs synchronize];
    vipLog(@"Injected %lu keys", (unsigned long)injections.count);
}

// ========== NSJSONSerialization Hook ==========
static id (*orig_jsonObject)(Class, SEL, NSData*, NSJSONReadingOptions, NSError**);
static id vip_jsonObject(Class cls, SEL _cmd, NSData *data, NSJSONReadingOptions opt, NSError **err) {
    id obj = orig_jsonObject(cls, _cmd, data, opt, err);
    if (!obj) return obj;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *md = [obj mutableCopy];
        BOOL patched = NO;
        for (NSString *key in [md allKeys]) {
            NSString *lk = [key lowercaseString];
            if ([lk isEqualToString:@"is_vip"] || [lk isEqualToString:@"vip"] ||
                [lk isEqualToString:@"is_member"] || [lk isEqualToString:@"member"] ||
                [lk isEqualToString:@"is_premium"] || [lk isEqualToString:@"premium"] ||
                [lk isEqualToString:@"is_pro"] || [lk isEqualToString:@"pro"] ||
                [lk isEqualToString:@"subscribed"] || [lk isEqualToString:@"is_subscribed"] ||
                [lk isEqualToString:@"has_subscription"] || [lk isEqualToString:@"is_active"] ||
                [lk isEqualToString:@"active"] || [lk isEqualToString:@"enabled"] ||
                [lk isEqualToString:@"valid"]) {
                vipLog(@"JSON PATCH bool: %@", key);
                md[key] = @YES;
                patched = YES;
            } else if ([lk isEqualToString:@"level"] || [lk isEqualToString:@"grade"] ||
                       [lk isEqualToString:@"vip_level"] || [lk isEqualToString:@"member_level"] ||
                       [lk isEqualToString:@"remaining_days"] || [lk isEqualToString:@"days_left"] ||
                       [lk isEqualToString:@"days"]) {
                vipLog(@"JSON PATCH int: %@", key);
                md[key] = @9999;
                patched = YES;
            } else if ([lk rangeOfString:@"expire"].location != NSNotFound ||
                       [lk rangeOfString:@"deadline"].location != NSNotFound ||
                       [lk rangeOfString:@"end_time"].location != NSNotFound) {
                vipLog(@"JSON PATCH expire: %@", key);
                md[key] = @"2099-12-31T23:59:59Z";
                patched = YES;
            } else if ([lk isEqualToString:@"plan"] || [lk isEqualToString:@"plan_name"] ||
                       [lk isEqualToString:@"plan_type"] || [lk isEqualToString:@"package"] ||
                       [lk isEqualToString:@"package_name"] || [lk isEqualToString:@"package_type"]) {
                vipLog(@"JSON PATCH plan: %@", key);
                md[key] = @"Pro计划";
                patched = YES;
            } else if ([lk rangeOfString:@"traffic"].location != NSNotFound ||
                       [lk rangeOfString:@"flow"].location != NSNotFound ||
                       [lk rangeOfString:@"data"].location != NSNotFound) {
                vipLog(@"JSON PATCH traffic: %@", key);
                md[key] = @999999;
                patched = YES;
            }
        }
        if (patched) return md;
    }
    return obj;
}

// ========== AppDelegate Hook ==========
static BOOL (*orig_appLaunch)(id, SEL, id, id);
static BOOL vip_appLaunch(id self, SEL _cmd, id app, id opts) {
    BOOL ret = orig_appLaunch(self, _cmd, app, opts);
    injectVIPDefaults();
    return ret;
}

// ========== Swizzling Helper ==========
static void swizzleInstanceMethod(Class cls, SEL origSel, IMP newImp, IMP *outOrig) {
    Method m = class_getInstanceMethod(cls, origSel);
    if (!m) return;
    *outOrig = method_getImplementation(m);
    const char *type = method_getTypeEncoding(m);
    class_replaceMethod(cls, origSel, newImp, type);
}

static void swizzleClassMethod(Class cls, SEL origSel, IMP newImp, IMP *outOrig) {
    Method m = class_getClassMethod(cls, origSel);
    if (!m) return;
    *outOrig = method_getImplementation(m);
    const char *type = method_getTypeEncoding(m);
    class_replaceMethod(object_getClass(cls), origSel, newImp, type);
}

// ========== Constructor ==========
__attribute__((constructor))
static void vipHookInit(void) {
    @autoreleasepool {
        vipLog(@"=== VIP Hook .mm loaded ===");

        // Hook NSUserDefaults
        Class udCls = objc_getClass("NSUserDefaults");
        if (udCls) {
            swizzleInstanceMethod(udCls, @selector(objectForKey:), (IMP)vip_objectForKey, (IMP*)&orig_objectForKey);
            swizzleInstanceMethod(udCls, @selector(stringForKey:), (IMP)vip_stringForKey, (IMP*)&orig_stringForKey);
            swizzleInstanceMethod(udCls, @selector(integerForKey:), (IMP)vip_integerForKey, (IMP*)&orig_integerForKey);
            swizzleInstanceMethod(udCls, @selector(boolForKey:), (IMP)vip_boolForKey, (IMP*)&orig_boolForKey);
            swizzleInstanceMethod(udCls, @selector(doubleForKey:), (IMP)vip_doubleForKey, (IMP*)&orig_doubleForKey);
            swizzleInstanceMethod(udCls, @selector(setObject:forKey:), (IMP)vip_setObject, (IMP*)&orig_setObject);
            swizzleInstanceMethod(udCls, @selector(setInteger:forKey:), (IMP)vip_setInteger, (IMP*)&orig_setInteger);
            swizzleInstanceMethod(udCls, @selector(setBool:forKey:), (IMP)vip_setBool, (IMP*)&orig_setBool);
            swizzleInstanceMethod(udCls, @selector(setDouble:forKey:), (IMP)vip_setDouble, (IMP*)&orig_setDouble);
            vipLog(@"NSUserDefaults swizzled");
        }

        // Hook NSJSONSerialization
        Class jsonCls = objc_getClass("NSJSONSerialization");
        if (jsonCls) {
            swizzleClassMethod(jsonCls, @selector(JSONObjectWithData:options:error:), (IMP)vip_jsonObject, (IMP*)&orig_jsonObject);
            vipLog(@"NSJSONSerialization swizzled");
        }

        // Hook AppDelegate
        Class appDel = objc_getClass("AppDelegate");
        if (appDel) {
            swizzleInstanceMethod(appDel, @selector(application:didFinishLaunchingWithOptions:), (IMP)vip_appLaunch, (IMP*)&orig_appLaunch);
            vipLog(@"AppDelegate swizzled");
        }

        // Immediate inject
        injectVIPDefaults();

        vipLog(@"=== Init complete ===");
    }
}
