//
//  KuwoVIPCrack.mm
//  酷我音乐VIP破解 - TrollStore注入版
//  日志写入App Documents目录
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#pragma mark - 日志系统 (写入App Documents)

static NSString *gLogPath = nil;
static NSFileHandle *gLogFile = nil;
static dispatch_queue_t gLogQueue = nil;

static void initLogSystem(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 获取App Documents目录
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docDir = paths.firstObject;
        if (!docDir) {
            // fallback: 使用Library/Caches
            paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
            docDir = paths.firstObject;
        }
        if (!docDir) {
            docDir = NSHomeDirectory();
        }

        gLogPath = [docDir stringByAppendingPathComponent:@"kuwo_vip_crack.log"];

        // 创建或清空日志文件
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:gLogPath]) {
            [@"=== KuwoVIP Crack Log ===\n" writeToFile:gLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }

        gLogFile = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
        [gLogFile seekToEndOfFile];

        gLogQueue = dispatch_queue_create("com.kuwo.vip.log", DISPATCH_QUEUE_SERIAL);
    });
}

static void vipLog(NSString *fmt, ...) {
    initLogSystem();

    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [NSDate date], msg];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    dispatch_async(gLogQueue, ^{
        if (gLogFile && data) {
            [gLogFile writeData:data];
            [gLogFile synchronizeFile];
        }
    });

    // 同时输出到系统日志(调试用)
    NSLog(@"[KuwoVIP] %@", msg);
}

#pragma mark - 配置

static NSString * const kFakeVIPJSON = @"{\"ctime\":9999999999999,\"data\":{\"luxuryIcon\":\"https://img1.kuwo.cn/v2/20220901/tech_common/de688c240ccbc48a30d0bb2902ee4a51.png\",\"uid\":\"503481971\",\"svipAutoPayUser\":\"1\",\"chezaiIcon\":\"https://img1.kuwo.cn/v2/20220901/tech_common/873a93c717c7f3da7996eaa2fdc600fd.png\",\"vipSpeakerExpire\":\"9999999999999\",\"vipOverSeasExpire\":\"9999999999999\",\"isYearUser\":\"1\",\"isNewUser\":\"0\",\"luxVipDays\":\"9999\",\"cheZaiDays\":\"9999\",\"svipIcon\":\"https://img1.kuwo.cn/v2/20220901/tech_common/ef034da7a993e80cc3fbde1082a462c0.png\",\"openBtnText\":\"已开通\",\"iconJumpUrl\":\"https://h5app.kuwo.cn/pay/vip2/vipcenter.html\",\"chezaiExpire\":\"9999999999999\",\"vipTag\":\"SVIP\",\"iconConf\":\"{\\\"jumpType\\\":1,\\\"iconUrl\\\":\\\"https://h5app.kuwo.cn/pay/vip2/vipcenter.html\\\"}\",\"biedAlbum\":\"1\",\"vipmDays\":\"9999\",\"userVipType\":\"3\",\"linQiPrice\":\"\",\"vipExpire\":\"9999999999999\",\"vipmAutoPayUser\":\"1\",\"growthValue\":\"99999\",\"vipWatch1Expire\":\"9999999999999\",\"vipmIcon\":\"https://img1.kuwo.cn/v2/20220901/tech_common/c2f83eb842be0cbc04cf3652e32b7fd5.png\",\"vipAdIcon\":\"\",\"lwPrice\":\"2\",\"experienceExpire\":\"9999999999999\",\"linQiType\":\"1\",\"svipExpire\":\"9999999999999\",\"vipSpeakerIcon\":\"https://h5s.kuwo.cn/upload/pictures/20250814/3139462f1fc5f70670ce7abeb1f8360f.png\",\"biedSong\":\"1\",\"userType\":\"3\",\"vipmExpire\":\"9999999999999\",\"vipAdAutoPayUser\":\"1\",\"cheZaiAutoPayUser\":\"1\",\"luxAutoPayUser\":\"1\",\"time\":\"9999999999999\",\"vipAdExpire\":\"9999999999999\",\"vipIcon\":\"https://h5s.kuwo.cn/upload/pictures/20250306/d4d17ba5489034431f291075ef189c63.png\",\"svipDays\":\"9999\",\"vipLuxuryExpire\":\"9999999999999\"},\"meta\":{\"desc\":\"成功\",\"code\":200}}";

#pragma mark - 防递归保护

static __thread BOOL gInHook = NO;

#define HOOK_GUARD_BEGIN \
    if (gInHook) return nil; \
    gInHook = YES;

#define HOOK_GUARD_BEGIN_VOID \
    if (gInHook) return; \
    gInHook = YES;

#define HOOK_GUARD_END \
    gInHook = NO;

#pragma mark - 工具函数

static BOOL isVIPDefaultsKey(NSString *key) {
    if (!key) return NO;
    return [key rangeOfString:@"VIP_INFO"].location != NSNotFound ||
           [key rangeOfString:@"vip_info"].location != NSNotFound;
}

static BOOL isVIPURL(NSString *url) {
    if (!url) return NO;
    NSString *low = [url lowercaseString];
    return [low rangeOfString:@"isvip=0"].location != NSNotFound;
}

static id fakeVIPDict(void) {
    static id sFakeDict = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [kFakeVIPJSON dataUsingEncoding:NSUTF8StringEncoding];
        if (data) {
            sFakeDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        }
    });
    return sFakeDict;
}

#pragma mark - NSUserDefaults Hook

typedef id (*orig_objectForKey_t)(id self, SEL _cmd, id key);
static orig_objectForKey_t orig_NSUserDefaults_objectForKey = NULL;

static id hook_NSUserDefaults_objectForKey(id self, SEL _cmd, id key) {
    HOOK_GUARD_BEGIN
    id result = orig_NSUserDefaults_objectForKey(self, _cmd, key);
    if (isVIPDefaultsKey(key)) {
        vipLog(@"[NSUserDefaults] objectForKey:%@ -> FAKE", key);
        HOOK_GUARD_END
        return [kFakeVIPJSON copy];
    }
    HOOK_GUARD_END
    return result;
}

typedef id (*orig_stringForKey_t)(id self, SEL _cmd, NSString *key);
static orig_stringForKey_t orig_NSUserDefaults_stringForKey = NULL;

static id hook_NSUserDefaults_stringForKey(id self, SEL _cmd, NSString *key) {
    HOOK_GUARD_BEGIN
    id result = orig_NSUserDefaults_stringForKey(self, _cmd, key);
    if (isVIPDefaultsKey(key)) {
        vipLog(@"[NSUserDefaults] stringForKey:%@ -> FAKE", key);
        HOOK_GUARD_END
        return [kFakeVIPJSON copy];
    }
    HOOK_GUARD_END
    return result;
}

typedef id (*orig_dictionaryForKey_t)(id self, SEL _cmd, NSString *key);
static orig_dictionaryForKey_t orig_NSUserDefaults_dictionaryForKey = NULL;

static id hook_NSUserDefaults_dictionaryForKey(id self, SEL _cmd, NSString *key) {
    HOOK_GUARD_BEGIN
    id result = orig_NSUserDefaults_dictionaryForKey(self, _cmd, key);
    if (isVIPDefaultsKey(key)) {
        vipLog(@"[NSUserDefaults] dictionaryForKey:%@ -> FAKE", key);
        id fake = fakeVIPDict();
        HOOK_GUARD_END
        return fake ?: result;
    }
    HOOK_GUARD_END
    return result;
}

typedef void (*orig_setObject_t)(id self, SEL _cmd, id obj, id key);
static orig_setObject_t orig_NSUserDefaults_setObject = NULL;

static void hook_NSUserDefaults_setObject(id self, SEL _cmd, id obj, id key) {
    HOOK_GUARD_BEGIN_VOID
    if (isVIPDefaultsKey(key)) {
        vipLog(@"[NSUserDefaults] BLOCK setObject:%@", key);
        HOOK_GUARD_END
        return;
    }
    orig_NSUserDefaults_setObject(self, _cmd, obj, key);
    HOOK_GUARD_END
}

#pragma mark - NSJSONSerialization Hook

typedef id (*orig_JSONObject_t)(Class cls, SEL _cmd, NSData *data, NSJSONReadingOptions opt, NSError **err);
static orig_JSONObject_t orig_NSJSONSerialization_JSONObject = NULL;

static id hook_NSJSONSerialization_JSONObject(Class cls, SEL _cmd, NSData *data, NSJSONReadingOptions opt, NSError **err) {
    id result = orig_NSJSONSerialization_JSONObject(cls, _cmd, data, opt, err);
    if (![result isKindOfClass:[NSDictionary class]]) return result;

    NSDictionary *dict = (NSDictionary *)result;
    id expire = dict[@"expireTime"];
    id level = dict[@"level"];
    id dataObj = dict[@"data"];

    if (!expire && !level && !dataObj) return result;
    if (dataObj && ![dataObj isKindOfClass:[NSDictionary class]]) return result;

    NSDictionary *dataDict = dataObj ? (NSDictionary *)dataObj : dict;
    id vipExpire = dataDict[@"vipExpire"];
    id svipExpire = dataDict[@"svipExpire"];
    if (!vipExpire && !svipExpire && !expire && !level) return result;

    vipLog(@"[NSJSONSerialization] VIP JSON detected, patching...");

    NSMutableDictionary *newDict = [NSMutableDictionary dictionaryWithDictionary:dict];
    NSMutableDictionary *newData = dataObj ? [NSMutableDictionary dictionaryWithDictionary:dataDict] : newDict;

    NSArray *numKeys = @[@"expireTime", @"vipExpire", @"svipExpire", @"vipmExpire", @"level",
                         @"curVipValue", @"starvipLevel", @"starvipType", @"cloakingStatus",
                         @"status", @"isSign", @"isGift", @"isLook", @"isYearUser",
                         @"isNewUser", @"userType", @"biedAlbum", @"biedSong"];

    for (NSString *k in numKeys) {
        id val = newData[k];
        if (!val) continue;
        int num = [val intValue];
        int fake = 0;
        if ([k isEqualToString:@"expireTime"] || [k isEqualToString:@"vipExpire"] ||
            [k isEqualToString:@"svipExpire"] || [k isEqualToString:@"vipmExpire"]) {
            if (num < 9999999999) fake = 9999999999;
        } else if ([k isEqualToString:@"level"] || [k isEqualToString:@"curVipValue"] ||
                   [k isEqualToString:@"starvipLevel"]) {
            if (num < 10) fake = 10;
        } else if ([k isEqualToString:@"starvipType"]) {
            if (num < 3) fake = 3;
        } else if ([k isEqualToString:@"userType"]) {
            if (num == 0 || num == 2) fake = 3;
        } else {
            if (num == 0) fake = 1;
        }
        if (fake > 0) {
            newData[k] = @(fake);
            vipLog(@"[PATCH] %@: %d -> %d", k, num, fake);
        }
    }

    NSString *tag = newData[@"vipTag"];
    if ([tag isKindOfClass:[NSString class]] && [tag rangeOfString:@"VIP"].location != NSNotFound
        && [tag rangeOfString:@"SVIP"].location == NSNotFound) {
        newData[@"vipTag"] = @"SVIP";
        vipLog(@"[PATCH] vipTag: %@ -> SVIP", tag);
    }

    if (dataObj) {
        newDict[@"data"] = newData;
    }

    vipLog(@"[NSJSONSerialization] Patched OK");
    return newDict;
}

#pragma mark - NSURLSession Hook

typedef id (*orig_dataTask_t)(id self, SEL _cmd, NSURLRequest *req);
static orig_dataTask_t orig_NSURLSession_dataTask = NULL;

static id hook_NSURLSession_dataTask(id self, SEL _cmd, NSURLRequest *req) {
    NSURL *url = req.URL;
    NSString *urlStr = url.absoluteString;
    if (isVIPURL(urlStr)) {
        NSString *newUrl = [urlStr stringByReplacingOccurrencesOfString:@"isVip=0" withString:@"isVip=1"];
        NSMutableURLRequest *newReq = [req mutableCopy];
        newReq.URL = [NSURL URLWithString:newUrl];
        vipLog(@"[NET] isVip=0 -> 1 | %@", [newUrl substringToIndex:MIN(80, newUrl.length)]);
        return orig_NSURLSession_dataTask(self, _cmd, newReq);
    }
    return orig_NSURLSession_dataTask(self, _cmd, req);
}

#pragma mark - 初始化

static void hookClassMethod(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) {
        vipLog(@"[WARN] Class method not found: %@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    *origImp = method_setImplementation(m, newImp);
}

static void hookInstanceMethod(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        vipLog(@"[WARN] Instance method not found: %@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    *origImp = method_setImplementation(m, newImp);
}

__attribute__((constructor))
static void kuwo_vip_init(void) {
    vipLog(@"=== KuwoVIP Crack Loading ===");

    // 1. 预注入NSUserDefaults
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSDictionary *all = [defs dictionaryRepresentation];
    int injectCount = 0;
    for (NSString *key in all.allKeys) {
        if (isVIPDefaultsKey(key)) {
            vipLog(@"[INJECT] NSUserDefaults: %@", key);
            [defs setObject:kFakeVIPJSON forKey:key];
            injectCount++;
        }
    }
    [defs synchronize];
    vipLog(@"[OK] NSUserDefaults pre-injected: %d keys", injectCount);

    // 2. Hook NSUserDefaults
    Class udCls = [NSUserDefaults class];
    hookInstanceMethod(udCls, @selector(objectForKey:), (IMP)hook_NSUserDefaults_objectForKey, (IMP *)&orig_NSUserDefaults_objectForKey);
    hookInstanceMethod(udCls, @selector(stringForKey:), (IMP)hook_NSUserDefaults_stringForKey, (IMP *)&orig_NSUserDefaults_stringForKey);
    hookInstanceMethod(udCls, @selector(dictionaryForKey:), (IMP)hook_NSUserDefaults_dictionaryForKey, (IMP *)&orig_NSUserDefaults_dictionaryForKey);
    hookInstanceMethod(udCls, @selector(setObject:forKey:), (IMP)hook_NSUserDefaults_setObject, (IMP *)&orig_NSUserDefaults_setObject);
    vipLog(@"[OK] NSUserDefaults hooked");

    // 3. Hook NSJSONSerialization
    hookClassMethod([NSJSONSerialization class], @selector(JSONObjectWithData:options:error:),
                    (IMP)hook_NSJSONSerialization_JSONObject, (IMP *)&orig_NSJSONSerialization_JSONObject);
    vipLog(@"[OK] NSJSONSerialization hooked");

    // 4. Hook NSURLSession
    hookInstanceMethod([NSURLSession class], @selector(dataTaskWithRequest:),
                       (IMP)hook_NSURLSession_dataTask, (IMP *)&orig_NSURLSession_dataTask);
    vipLog(@"[OK] NSURLSession hooked");

    // 5. 记录日志路径
    if (gLogPath) {
        vipLog(@"[INFO] Log file: %@", gLogPath);
    }

    vipLog(@"=== KuwoVIP Crack Loaded ===");
}
