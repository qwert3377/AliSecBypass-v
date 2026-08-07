// AliSecBypass v6.1.13 - 仅伪装 IDFA + IDFV，移除所有硬件伪装
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

// ========== 隐藏自身 dylib ==========
static const char *(*orig_dyld_get_image_name)(uint32_t);
static const char *my_dyld_get_image_name(uint32_t image_index) {
    const char *name = orig_dyld_get_image_name(image_index);
    if (name && (strstr(name, "AliSecBypass") || strstr(name, "bypass") || strstr(name, "fishhook"))) {
        return "/System/Library/Frameworks/Foundation.framework/Foundation";
    }
    return name;
}

// ========== 域名拦截 ==========
static BOOL isBlockedHost(NSString *host) {
    if (!host || host.length == 0) return NO;
    NSArray *keywords = @[@"security-lq", @"pitaya.bytedance", @"mon11-misc.fqnovel", @"tnc.bytedance", @"toblog"];
    for (NSString *kw in keywords) { if ([host containsString:kw]) return YES; }
    return NO;
}

// ========== fishhook 系统函数 ==========
static int (*orig_connect)(int, const struct sockaddr *, socklen_t);
static int my_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (addr && addr->sa_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in *)addr;
        NSString *ipStr = [NSString stringWithFormat:@"%s", inet_ntoa(sin->sin_addr)];
        if ([ipStr hasPrefix:@"172.31."]) { errno = ECONNREFUSED; return -1; }
    }
    return orig_connect(sockfd, addr, addrlen);
}

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

static int (*orig_getaddrinfo)(const char *, const char *, const struct addrinfo *, struct addrinfo **);
static int my_getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res) {
    if (node) {
        NSString *host = [NSString stringWithUTF8String:node];
        if (isBlockedHost(host)) return EAI_NONAME;
    }
    return orig_getaddrinfo(node, service, hints, res);
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

// ========== NSURLSession Hook ==========
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

    if (isBlockedHost(host)) {
        bypassLog([NSString stringWithFormat:@"[HTTP-BLOCK] %@%@", host, path]);
        NSURLSessionDataTask *dummy = ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dtwr)(self, _cmd, request, ch);
        [dummy cancel]; return dummy;
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
    bypassLog(@"=== AliSecBypass v6.1.13 init ===");
    initFakeIDs();
    hookUIDevice();
    hookASIdentifierManager();
    hookTTNetworkCommonParams();

    struct rebinding rebinds[] = {
        {"connect", (void *)my_connect, (void **)&orig_connect},
        {"ptrace", (void *)my_ptrace, (void **)&orig_ptrace},
        {"sysctl", (void *)my_sysctl, (void **)&orig_sysctl},
        {"getaddrinfo", (void *)my_getaddrinfo, (void **)&orig_getaddrinfo},
        {"dlopen", (void *)my_dlopen, (void **)&orig_dlopen},
        {"dlsym", (void *)my_dlsym, (void **)&orig_dlsym},
        {"_dyld_get_image_name", (void *)my_dyld_get_image_name, (void **)&orig_dyld_get_image_name}
    };
    rebind_symbols(rebinds, 7);

    Class cls = objc_getClass("NSURLSession");
    if (cls) {
        Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
        if (m1) { orig_dtwr = method_getImplementation(m1); method_setImplementation(m1, (IMP)my_dtwr); }
    }

    bypassLog(@"=== AliSecBypass v6.1.13 init complete ===");
}
