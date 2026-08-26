//
//  ElyndorTV VIP Delayed Tweak v12.0
//  Target: LysenthoTVSpace (com.influx4.motion.axis26)
//  Build: 2026-08-26
//  Strategy: Delayed hook (5s after launch) + /tmp logging
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define MAX_TIER 8
#define VIP_KEY @"kvipstatusstoragekey"

#pragma mark - Ultra-safe logger to /tmp

static void vipLog(NSString *fmt, ...) {
    @try {
        va_list args;
        va_start(args, fmt);
        NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
        va_end(args);

        NSString *line = [NSString stringWithFormat:@"%@ [VIP] %@\n",
            [[NSDate date] descriptionWithLocale:nil], msg];

        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/vip_tweak.log"];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:data];
            [fh closeFile];
        } else {
            [data writeToFile:@"/tmp/vip_tweak.log" atomically:YES];
        }
    } @catch (NSException *e) {}
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
static NSInteger (*orig_integerForKey)(id, SEL, NSString *);
static BOOL  (*orig_boolForKey)(id, SEL, NSString *);

static void (*orig_setObject)(id, SEL, id, NSString *);
static void (*orig_removeObject)(id, SEL, NSString *);

#pragma mark - Minimal Hooks (only 5 most critical)

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

static NSInteger hook_integerForKey(id self, SEL _cmd, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[FAKE] integerForKey:'%@' -> %d", key, MAX_TIER);
            return MAX_TIER;
        }
    } @catch (NSException *e) {}
    return orig_integerForKey(self, _cmd, key);
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

static void hook_setObject(id self, SEL _cmd, id value, NSString *key) {
    @try {
        if (isMemberKey(key)) {
            vipLog(@"[BLOCK] setObject:forKey:'%@'", key);
            return;
        }
    } @catch (NSException *e) {}
    orig_setObject(self, _cmd, value, key);
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

#pragma mark - Swizzle

static void swizzle(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    @try {
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) {
            vipLog(@"[WARN] method not found %@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
            return;
        }
        *origImp = method_setImplementation(m, newImp);
        vipLog(@"[OK] Swizzled %@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
    } @catch (NSException *e) {
        vipLog(@"[WARN] swizzle exception: %@", e);
    }
}

#pragma mark - Core Logic (called after delay)

static void doHook(void) {
    vipLog(@"========================================");
    vipLog(@"ElyndorTV VIP Delayed Tweak v12.0");
    vipLog(@"Build: 2026-08-26");
    vipLog(@"Target: LysenthoTVSpace");
    vipLog(@"Max Tier: %d", MAX_TIER);
    vipLog(@"========================================");

    // Check if NSUserDefaults class is loaded
    Class UD = objc_getClass("NSUserDefaults");
    if (!UD) {
        vipLog(@"[ERR] NSUserDefaults class not found, aborting");
        return;
    }
    vipLog(@"[OK] NSUserDefaults class found");

    // Swizzle only the most critical methods
    swizzle(UD, @selector(objectForKey:),     (IMP)hook_objectForKey,     (IMP *)&orig_objectForKey);
    swizzle(UD, @selector(stringForKey:),     (IMP)hook_stringForKey,     (IMP *)&orig_stringForKey);
    swizzle(UD, @selector(dataForKey:),       (IMP)hook_dataForKey,       (IMP *)&orig_dataForKey);
    swizzle(UD, @selector(dictionaryForKey:), (IMP)hook_dictionaryForKey, (IMP *)&orig_dictionaryForKey);
    swizzle(UD, @selector(integerForKey:),    (IMP)hook_integerForKey,    (IMP *)&orig_integerForKey);
    swizzle(UD, @selector(boolForKey:),       (IMP)hook_boolForKey,       (IMP *)&orig_boolForKey);
    swizzle(UD, @selector(setObject:forKey:), (IMP)hook_setObject,        (IMP *)&orig_setObject);
    swizzle(UD, @selector(removeObjectForKey:), (IMP)hook_removeObject,   (IMP *)&orig_removeObject);

    // Inject into existing standardUserDefaults
    @try {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if (ud) {
            [ud setObject:buildFakeVipDict() forKey:VIP_KEY];
            [ud synchronize];
            vipLog(@"[INIT] Injected fake VIP dict");
        } else {
            vipLog(@"[INIT] standardUserDefaults is nil");
        }
    } @catch (NSException *e) {
        vipLog(@"[INIT] Injection exception: %@", e);
    }

    vipLog(@"[INIT] All hooks installed");
}

#pragma mark - Constructor (DO NOTHING except schedule delay)

__attribute__((constructor))
static void init(void) {
    // Write a startup marker immediately
    @try {
        NSString *marker = @"[STARTUP] Constructor called\n";
        NSData *data = [marker dataUsingEncoding:NSUTF8StringEncoding];
        [data writeToFile:@"/tmp/vip_tweak.log" atomically:YES];
    } @catch (NSException *e) {}

    // Schedule actual work after 5 seconds
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        doHook();
    });
}
