// AliSecBypass v6.1.16 - 路B：底层环境变量伪装 + IDFA/IDFV
// 新增 getenv/NSProcessInfo.environment 伪装，不碰 NSBundle 路径（防崩溃）
// fishhook + ObjC Runtime 纯库方案，无 Logos，TrollStore / 非越狱 / LiveContainer 注入

#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#include <objc/runtime.h>
#include <dlfcn.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <fishhook.h>
#include <mach-o/dyld.h>
#include <stdlib.h>
#include <string.h>

// ========== 日志 ==========
static dispatch_queue_t gLogQueue = NULL;
static void bypassLog(NSString *msg) {
    if (!gLogQueue) gLogQueue = dispatch_queue_create("com.bypass.log", DISPATCH_QUEUE_SERIAL);
    dispatch_async(gLogQueue, ^{
        NSDateFormatter *f = [[NSDateFormatter alloc] init];
        [f setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *ts = [f stringFromDate:[NSDate date]];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *logPath = [paths.firstObject stringByAppendingPathComponent:@"AliSecBypass.log"];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
        else { [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
    });
}

// ========== 仅保留 IDFA / IDFV 伪装 ==========
static NSString *gFakeIDFV = nil;
static NSString *gFakeIDFA = nil;
static BOOL gLoggedFirstPatch = NO;

static void initFakeIDs(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    gFakeIDFV = [ud stringForKey:@"AliSecBypass_FakeIDFV"];
    if (!gFakeIDFV) { gFakeIDFV = [[NSUUID UUID] UUIDString]; [ud setObject:gFakeIDFV forKey:@"AliSecBypass_FakeIDFV"]; [ud synchronize]; }

    gFakeIDFA = [ud stringForKey:@"AliSecBypass_FakeIDFA"];
    if (!gFakeIDFA) { gFakeIDFA = [[NSUUID UUID] UUIDString]; [ud setObject:gFakeIDFA forKey:@"AliSecBypass_FakeIDFA"]; [ud synchronize]; }

    bypassLog([NSString stringWithFormat:@"[Init] IDFV=%@ IDFA=%@", gFakeIDFV, gFakeIDFA]);
}

// ========== 仅 patch IDFA/IDFV 相关字段 ==========
static NSDictionary *patchCommonParams(NSDictionary *original) {
    if (!original) return nil;
    NSMutableDictionary *mut = [original mutableCopy];
    if (!mut) return original;

    NSString *origVid = original[@"vid"];
    NSString *origIdfa = original[@"idfa"];
    NSString *origIdfv = original[@"idfv"];

    mut[@"vid"] = gFakeIDFV;
    mut[@"idfv"] = gFakeIDFV;
    mut[@"idfa"] = gFakeIDFA ?: @"00000000-0000-0000-0000-000000000000";
    mut[@"cdid"] = [[NSUUID UUID] UUIDString];

    if (!gLoggedFirstPatch) {
        gLoggedFirstPatch = YES;
        bypassLog([NSString stringWithFormat:@"[Patch] vid: %@ -> %@", origVid ?: @"(nil)", mut[@"vid"]]);
        bypassLog([NSString stringWithFormat:@"[Patch] idfa: %@ -> %@", origIdfa ?: @"(nil)", mut[@"idfa"]]);
        bypassLog([NSString stringWithFormat:@"[Patch] idfv: %@ -> %@", origIdfv ?: @"(nil)", mut[@"idfv"]]);
        bypassLog(@"[Patch] first patch logged, subsequent suppressed");
    }
    return mut;
}

// ========== TTNetworkManager Hook ==========
typedef NSDictionary * (^CommonParamsBlock)(void);
typedef NSDictionary * (^CommonParamsBlockWithURL)(NSURL *);

static IMP orig_commonParamsblock = NULL;
static IMP orig_commonParamsblockWithURL = NULL;
static IMP orig_commonParams = NULL;

static CommonParamsBlock makeWrappedBlock(CommonParamsBlock original) {
    if (!original) return nil;
    return [^NSDictionary *(void) {
        NSDictionary *result = original();
        return patchCommonParams(result);
    } copy];
}

static CommonParamsBlockWithURL makeWrappedBlockWithURL(CommonParamsBlockWithURL original) {
    if (!original) return nil;
    return [^NSDictionary *(NSURL *url) {
        NSDictionary *result = original(url);
        return patchCommonParams(result);
    } copy];
}

static id my_commonParamsblock(id self, SEL _cmd) {
    CommonParamsBlock original = ((CommonParamsBlock (*)(id, SEL))orig_commonParamsblock)(self, _cmd);
    return makeWrappedBlock(original);
}

static id my_commonParamsblockWithURL(id self, SEL _cmd) {
    CommonParamsBlockWithURL original = ((CommonParamsBlockWithURL (*)(id, SEL))orig_commonParamsblockWithURL)(self, _cmd);
    return makeWrappedBlockWithURL(original);
}

static id my_commonParams(id self, SEL _cmd) {
    id result = ((id (*)(id, SEL))orig_commonParams)(self, _cmd);
    if ([result isKindOfClass:[NSDictionary class]]) return patchCommonParams(result);
    return result;
}

static void hookTTNetworkCommonParams(void) {
    Class ttMgr = objc_getClass("TTNetworkManager");
    if (!ttMgr) { bypassLog(@"[TTNetwork] TTNetworkManager not found"); return; }
    Method m;
    if ((m = class_getInstanceMethod(ttMgr, @selector(commonParamsblock)))) {
        orig_commonParamsblock = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_commonParamsblock);
        bypassLog(@"[Hook] commonParamsblock hooked");
    }
    if ((m = class_getInstanceMethod(ttMgr, @selector(commonParamsblockWithURL)))) {
        orig_commonParamsblockWithURL = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_commonParamsblockWithURL);
        bypassLog(@"[Hook] commonParamsblockWithURL hooked");
    }
    if ((m = class_getInstanceMethod(ttMgr, @selector(commonParams)))) {
        orig_commonParams = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_commonParams);
        bypassLog(@"[Hook] commonParams hooked");
    }
}

// ========== UIDevice 仅 hook IDFV ==========
static NSUUID *my_idfv(id self, SEL _cmd) { return [[NSUUID alloc] initWithUUIDString:gFakeIDFV]; }
static NSUUID *my_uniqueVendor(id self, SEL _cmd) { return [[NSUUID alloc] initWithUUIDString:gFakeIDFV]; }

static void hookUIDevice(void) {
    Class uid = objc_getClass("UIDevice");
    if (!uid) return;
    Method m;
    if ((m = class_getInstanceMethod(uid, @selector(identifierForVendor)))) method_setImplementation(m, (IMP)my_idfv);
    if ((m = class_getInstanceMethod(uid, NSSelectorFromString(@"_uniqueVendorIdentifier")))) method_setImplementation(m, (IMP)my_uniqueVendor);
    if ((m = class_getInstanceMethod(uid, NSSelectorFromString(@"uniqueIdentifierForVendor")))) method_setImplementation(m, (IMP)my_uniqueVendor);
}

// ========== ASIdentifierManager 仅 hook IDFA ==========
static NSUUID *my_adId(id self, SEL _cmd) { return [[NSUUID alloc] initWithUUIDString:gFakeIDFA]; }

static void hookASIdentifierManager(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dlopen("/System/Library/Frameworks/AdSupport.framework/AdSupport", RTLD_LAZY); });
    Class asid = objc_getClass("ASIdentifierManager");
    if (asid) {
        Method m = class_getInstanceMethod(asid, @selector(advertisingIdentifier));
        if (m) method_setImplementation(m, (IMP)my_adId);
    }
}

// ========== NSBundle 仅 Hook bundleIdentifier + infoDictionary（不移除路径）==========
static NSString *gOriginalBundleID = nil;
static IMP orig_bundleIdentifier = NULL;
static IMP orig_infoDictionary = NULL;

static NSString *my_bundleIdentifier(id self, SEL _cmd) {
    return gOriginalBundleID ?: @"com.dragon.read";
}
static NSDictionary *my_infoDictionary(id self, SEL _cmd) {
    NSDictionary *orig = ((NSDictionary *(*)(id, SEL))orig_infoDictionary)(self, @selector(infoDictionary));
    NSMutableDictionary *mut = [orig mutableCopy];
    if (gOriginalBundleID) mut[@"CFBundleIdentifier"] = gOriginalBundleID;
    return mut;
}

static void hookNSBundle(void) {
    NSBundle *mainBundle = [NSBundle mainBundle];
    gOriginalBundleID = mainBundle.bundleIdentifier;

    if (gOriginalBundleID && ([gOriginalBundleID containsString:@"LiveContainer"] || [gOriginalBundleID containsString:@"esign"] || [gOriginalBundleID containsString:@"troll"])) {
        bypassLog([NSString stringWithFormat:@"[Bundle] Container detected: %@", gOriginalBundleID]);
        gOriginalBundleID = @"com.dragon.read";
    }

    Class bundleCls = objc_getClass("NSBundle");
    Method m;
    if ((m = class_getInstanceMethod(bundleCls, @selector(bundleIdentifier)))) {
        orig_bundleIdentifier = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_bundleIdentifier);
    }
    if ((m = class_getInstanceMethod(bundleCls, @selector(infoDictionary)))) {
        orig_infoDictionary = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_infoDictionary);
    }
    bypassLog(@"[Bundle] NSBundle hooked (identifier only)");
}

// ========== NSProcessInfo.environment 伪装 ==========
static IMP orig_environment = NULL;
static NSDictionary *my_environment(id self, SEL _cmd) {
    NSDictionary *orig = ((NSDictionary *(*)(id, SEL))orig_environment)(self, _cmd);
    NSMutableDictionary *mut = [orig mutableCopy];
    if (mut) {
        mut[@"HOME"] = @"/var/mobile/Containers/Data/Application/XXXX";
        mut[@"CFFIXED_USER_HOME"] = @"/var/mobile/Containers/Data/Application/XXXX";
        mut[@"TMPDIR"] = @"/var/mobile/Containers/Data/Application/XXXX/tmp";
    }
    return mut ?: orig;
}

static void hookNSProcessInfo(void) {
    Class pi = objc_getClass("NSProcessInfo");
    if (!pi) return;
    Method m = class_getInstanceMethod(pi, @selector(environment));
    if (m) {
        orig_environment = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_environment);
        bypassLog(@"[Hook] NSProcessInfo.environment hooked");
    }
}

// ========== getenv 伪装 ==========
static char *gFakeHome = "/var/mobile/Containers/Data/Application/XXXX";
static char *gFakeTmp = "/var/mobile/Containers/Data/Application/XXXX/tmp";

static char *(*orig_getenv)(const char *);
static char *my_getenv(const char *name) {
    if (name) {
        if (strcmp(name, "HOME") == 0 || strcmp(name, "CFFIXED_USER_HOME") == 0) {
            return gFakeHome;
        }
        if (strcmp(name, "TMPDIR") == 0) {
            return gFakeTmp;
        }
    }
    return orig_getenv(name);
}

// ========== 隐藏自身 dylib ==========
static const char *(*orig_dyld_get_image_name)(uint32_t);
static const char *my_dyld_get_image_name(uint32_t image_index) {
    const char *name = orig_dyld_get_image_name(image_index);
    if (name && (strstr(name, "AliSecBypass") || strstr(name, "bypass") || strstr(name, "fishhook"))) {
        return "/System/Library/Frameworks/Foundation.framework/Foundation";
    }
    return name;
}

// ========== fishhook 系统函数 ==========
static int (*orig_ptrace)(int, pid_t, void *, int);
static int my_ptrace(int request, pid_t pid, void *addr, int data) {
    if (request == 0) return 0;
    return orig_ptrace(request, pid, addr, data);
}

static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int my_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (ret != 0) return ret;
    if (namelen >= 2 && name[0] == CTL_KERN && name[1] == KERN_PROC) {
        if (oldp && oldlenp) memset(oldp, 0, *oldlenp);
        return 0;
    }
    return ret;
}

static void *(*orig_dlopen)(const char *, int);
static void *my_dlopen(const char *path, int mode) {
    if (path && (strstr(path, "AliSecBypass") || strstr(path, "bypass") || strstr(path, "fishhook"))) {
        return orig_dlopen("/System/Library/Frameworks/Foundation.framework/Foundation", mode);
    }
    return orig_dlopen(path, mode);
}

static void *(*orig_dlsym)(void *, const char *);
static void *my_dlsym(void *handle, const char *symbol) {
    void *ret = orig_dlsym(handle, symbol);
    if (symbol && (strstr(symbol, "Dobby") || strstr(symbol, "fishhook") || strstr(symbol, "rebind"))) return NULL;
    return ret;
}

// ========== NSURLSession Hook（仅日志，不拦截）==========
static IMP orig_dtwr = NULL;
static NSURLSessionDataTask *my_dtwr(id self, SEL _cmd, NSURLRequest *request, void (^ch)(NSData *, NSURLResponse *, NSError *)) {
    NSURL *url = request.URL;
    NSString *host = url.host ?: @"";
    NSString *path = url.path ?: @"";

    if ([path containsString:@"common" ] || [path containsString:@"params"] || [path containsString:@"device"] || [path containsString:@"log"]) {
        NSData *body = request.HTTPBody;
        NSString *bodyStr = body ? [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] : @"(no body)";
        bypassLog([NSString stringWithFormat:@"[HTTP-REQ] %@ %@ | Body: %@", host, path, bodyStr]);
    }

    void (^wrappedCh)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp && [path containsString:@"common" ]) {
            NSString *respStr = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"(empty)";
            bypassLog([NSString stringWithFormat:@"[HTTP-RESP] %@ %@ | Status:%ld | %@", host, path, (long)httpResp.statusCode, respStr]);
        }
        if (ch) ch(data, response, error);
    };

    return ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dtwr)(self, _cmd, request, wrappedCh);
}

// ========== 初始化 ==========
__attribute__((constructor(101))) static void constructor(void) {
    bypassLog(@"=== AliSecBypass v6.1.16 init ===");
    initFakeIDs();
    hookUIDevice();
    hookASIdentifierManager();
    hookTTNetworkCommonParams();
    hookNSBundle();
    hookNSProcessInfo();

    struct rebinding rebinds[] = {
        {"ptrace", (void *)my_ptrace, (void **)&orig_ptrace},
        {"sysctl", (void *)my_sysctl, (void **)&orig_sysctl},
        {"dlopen", (void *)my_dlopen, (void **)&orig_dlopen},
        {"dlsym", (void *)my_dlsym, (void **)&orig_dlsym},
        {"_dyld_get_image_name", (void *)my_dyld_get_image_name, (void **)&orig_dyld_get_image_name},
        {"getenv", (void *)my_getenv, (void **)&orig_getenv}
    };
    rebind_symbols(rebinds, 6);

    Class cls = objc_getClass("NSURLSession");
    if (cls) {
        Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
        if (m1) { orig_dtwr = method_getImplementation(m1); method_setImplementation(m1, (IMP)my_dtwr); }
    }

    bypassLog(@"=== AliSecBypass v6.1.16 init complete ===");
}
