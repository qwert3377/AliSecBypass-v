// AliSecBypass v5.9 - Hook commonParams + TTHttpTask init 截获设备指纹
// fishhook + Dobby + ObjC Runtime 混合方案
// 纯库文件，无 Logos，TrollStore / 非越狱注入

#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#include <objc/runtime.h>
#include <dlfcn.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <fishhook.h>
#include <dobby.h>
#include <mach-o/dyld.h>

// ========== 日志工具 ==========
static dispatch_queue_t gLogQueue = NULL;
static void bypassLog(NSString *msg) {
    if (!gLogQueue) gLogQueue = dispatch_queue_create("com.bypass.log", DISPATCH_QUEUE_SERIAL);
    dispatch_async(gLogQueue, ^{
        NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *logPath = [paths.firstObject stringByAppendingPathComponent:@"AliSecBypass.log"];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
        else { [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
    });
}

// ========== 辅助：安全打印对象 ==========
static NSString *safeDesc(id obj) {
    if (!obj) return @"(nil)";
    if ([obj isKindOfClass:[NSString class]]) return obj;
    if ([obj isKindOfClass:[NSNumber class]]) return [obj stringValue];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = obj;
        NSMutableString *s = [NSMutableString stringWithString:@"{"];
        [d enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            [s appendFormat:@"%@=%@;", k, safeDesc(v)];
        }];
        [s appendString:@"}"];
        return s;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *a = obj;
        NSMutableString *s = [NSMutableString stringWithString:@"["];
        for (id item in a) [s appendFormat:@"%@,", safeDesc(item)];
        [s appendString:@"]"];
        return s;
    }
    if ([obj isKindOfClass:[NSData class]]) {
        NSString *str = [[NSString alloc] initWithData:obj encoding:NSUTF8StringEncoding];
        return str ?: [obj base64EncodedStringWithOptions:0];
    }
    return [obj description];
}

// ========== 设备指纹 ==========
static NSDictionary *gDeviceProfile = nil;
static NSString *gFakeIDFV = nil;
static NSString *gFakeIDFA = nil;

static void initDeviceProfile(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDictionary *saved = [ud objectForKey:@"AliSecBypass_DeviceProfile"];
    if (!saved) {
        NSArray *profiles = @[
            @{@"model": @"iPhone14,2", @"systemVersion": @"17.5.1", @"name": @"iPhone", @"machine": @"iPhone14,2",
              @"screenW": @393, @"screenH": @852, @"scale": @3.0, @"mem": @6, @"disk": @128,
              @"tz": @"Asia/Shanghai", @"lang": @"zh-Hans-CN", @"carrier": @"中国联通"},
            @{@"model": @"iPhone13,2", @"systemVersion": @"16.6.1", @"name": @"iPhone", @"machine": @"iPhone13,2",
              @"screenW": @390, @"screenH": @844, @"scale": @3.0, @"mem": @4, @"disk": @256,
              @"tz": @"Asia/Shanghai", @"lang": @"zh-Hans-CN", @"carrier": @"中国移动"},
            @{@"model": @"iPhone15,2", @"systemVersion": @"18.0", @"name": @"iPhone", @"machine": @"iPhone15,2",
              @"screenW": @393, @"screenH": @852, @"scale": @3.0, @"mem": @8, @"disk": @512,
              @"tz": @"Asia/Shanghai", @"lang": @"zh-Hans-CN", @"carrier": @"中国电信"},
        ];
        NSUInteger idx = arc4random_uniform((uint32_t)profiles.count);
        saved = profiles[idx];
        [ud setObject:saved forKey:@"AliSecBypass_DeviceProfile"];
        [ud synchronize];
        bypassLog([NSString stringWithFormat:@"[Profile] NEW: %@", saved]);
    }
    gDeviceProfile = saved;

    gFakeIDFV = [ud stringForKey:@"AliSecBypass_FakeIDFV"];
    if (!gFakeIDFV) { gFakeIDFV = [[NSUUID UUID] UUIDString]; [ud setObject:gFakeIDFV forKey:@"AliSecBypass_FakeIDFV"]; [ud synchronize]; }

    gFakeIDFA = [ud stringForKey:@"AliSecBypass_FakeIDFA"];
    if (!gFakeIDFA) { gFakeIDFA = [[NSUUID UUID] UUIDString]; [ud setObject:gFakeIDFA forKey:@"AliSecBypass_FakeIDFA"]; [ud synchronize]; }
}

// ========== 1. 伪造 UIDevice ==========
static IMP orig_idfv = NULL;
static NSUUID *my_idfv(id self, SEL _cmd) { return [[NSUUID alloc] initWithUUIDString:gFakeIDFV]; }
static NSUUID *my_uniqueVendor(id self, SEL _cmd) { return [[NSUUID alloc] initWithUUIDString:gFakeIDFV]; }
static NSString *my_sysVer(id self, SEL _cmd) { return gDeviceProfile[@"systemVersion"] ?: @"17.0"; }
static NSString *my_model(id self, SEL _cmd) { return gDeviceProfile[@"model"] ?: @"iPhone"; }
static NSString *my_name(id self, SEL _cmd) { return gDeviceProfile[@"name"] ?: @"iPhone"; }

static void hookUIDevice(void) {
    Class uid = objc_getClass("UIDevice");
    if (!uid) return;
    Method m;
    if ((m = class_getInstanceMethod(uid, @selector(identifierForVendor)))) { orig_idfv = method_getImplementation(m); method_setImplementation(m, (IMP)my_idfv); }
    if ((m = class_getInstanceMethod(uid, NSSelectorFromString(@"_uniqueVendorIdentifier")))) method_setImplementation(m, (IMP)my_uniqueVendor);
    if ((m = class_getInstanceMethod(uid, NSSelectorFromString(@"uniqueIdentifierForVendor")))) method_setImplementation(m, (IMP)my_uniqueVendor);
    if ((m = class_getInstanceMethod(uid, @selector(systemVersion)))) method_setImplementation(m, (IMP)my_sysVer);
    if ((m = class_getInstanceMethod(uid, @selector(model)))) method_setImplementation(m, (IMP)my_model);
    if ((m = class_getInstanceMethod(uid, @selector(name)))) method_setImplementation(m, (IMP)my_name);
}

// ========== 2. 伪造 ASIdentifierManager ==========
static IMP orig_adId = NULL;
static NSUUID *my_adId(id self, SEL _cmd) { return [[NSUUID alloc] initWithUUIDString:gFakeIDFA]; }
static void hookASIdentifierManager(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dlopen("/System/Library/Frameworks/AdSupport.framework/AdSupport", RTLD_LAZY); });
    Class asid = objc_getClass("ASIdentifierManager");
    if (asid) {
        Method m = class_getInstanceMethod(asid, @selector(advertisingIdentifier));
        if (m) { orig_adId = method_getImplementation(m); method_setImplementation(m, (IMP)my_adId); }
    }
}

// ========== 3. 伪造 UIScreen / NSProcessInfo ==========
static IMP orig_screenBounds = NULL, orig_screenScale = NULL;
static CGRect my_screenBounds(id self, SEL _cmd) {
    return CGRectMake(0, 0, [gDeviceProfile[@"screenW"] floatValue], [gDeviceProfile[@"screenH"] floatValue]);
}
static CGFloat my_screenScale(id self, SEL _cmd) { return [gDeviceProfile[@"scale"] floatValue] ?: 3.0f; }
static IMP orig_physicalMemory = NULL;
static unsigned long long my_physicalMemory(id self, SEL _cmd) {
    return ([gDeviceProfile[@"mem"] unsignedLongLongValue] ?: 6ULL) * 1024 * 1024 * 1024;
}
static void hookScreenAndProcessInfo(void) {
    Class screen = objc_getClass("UIScreen");
    if (screen) {
        Method m;
        if ((m = class_getInstanceMethod(screen, @selector(bounds)))) { orig_screenBounds = method_getImplementation(m); method_setImplementation(m, (IMP)my_screenBounds); }
        if ((m = class_getInstanceMethod(screen, @selector(scale)))) { orig_screenScale = method_getImplementation(m); method_setImplementation(m, (IMP)my_screenScale); }
    }
    Class pi = objc_getClass("NSProcessInfo");
    if (pi) {
        Method m = class_getInstanceMethod(pi, @selector(physicalMemory));
        if (m) { orig_physicalMemory = method_getImplementation(m); method_setImplementation(m, (IMP)my_physicalMemory); }
    }
}

// ========== 4. 伪造 uname ==========
static int (*orig_uname)(struct utsname *);
static int my_uname(struct utsname *name) {
    int ret = orig_uname(name);
    if (ret == 0 && gDeviceProfile) {
        NSString *machine = gDeviceProfile[@"machine"];
        if (machine) { strncpy(name->machine, [machine UTF8String], sizeof(name->machine)-1); name->machine[sizeof(name->machine)-1] = 0; }
        NSString *sysVer = gDeviceProfile[@"systemVersion"];
        if (sysVer) { strncpy(name->release, [sysVer UTF8String], sizeof(name->release)-1); name->release[sizeof(name->release)-1] = 0; }
    }
    return ret;
}

// ========== 5. 隐藏自身 dylib ==========
static const char *(*orig_dyld_get_image_name)(uint32_t);
static const char *my_dyld_get_image_name(uint32_t image_index) {
    const char *name = orig_dyld_get_image_name(image_index);
    if (name && (strstr(name, "AliSecBypass") || strstr(name, "bypass") || strstr(name, "fishhook"))) {
        return "/System/Library/Frameworks/Foundation.framework/Foundation";
    }
    return name;
}

// ========== 6. 域名拦截 ==========
static BOOL isBlockedHost(NSString *host) {
    if (!host || host.length == 0) return NO;
    NSArray *keywords = @[@"security-lq", @"pitaya.bytedance"];
    for (NSString *kw in keywords) { if ([host containsString:kw]) return YES; }
    return NO;
}

// ========== 7. fishhook 系统函数 ==========
static int (*orig_connect)(int, const struct sockaddr *, socklen_t);
static int my_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (addr && addr->sa_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in *)addr;
        NSString *ipStr = [NSString stringWithFormat:@"%s", inet_ntoa(sin->sin_addr)];
        int port = ntohs(sin->sin_port);
        if ([ipStr hasPrefix:@"172.31."]) { errno = ECONNREFUSED; return -1; }
    }
    return orig_connect(sockfd, addr, addrlen);
}

static ssize_t (*orig_sendto)(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
static ssize_t my_sendto(int sockfd, const void *buf, size_t len, int flags, const struct sockaddr *dest_addr, socklen_t addrlen) {
    return orig_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
}

static int (*orig_ptrace)(int, pid_t, caddr_t, int);
static int my_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == 0) return 0;
    return orig_ptrace(request, pid, addr, data);
}

static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int my_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (ret == 0 && namelen >= 2 && name[0] == CTL_KERN && name[1] == KERN_PROC) {
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

// ========== 8. NSURLSession Hook ==========
static IMP orig_dtwr = NULL;
static NSURLSessionDataTask *my_dtwr(id self, SEL _cmd, NSURLRequest *request, void (^ch)(NSData *, NSURLResponse *, NSError *)) {
    NSURL *url = request.URL;
    NSString *host = url.host ?: @"";
    if (isBlockedHost(host)) {
        NSURLSessionDataTask *dummy = ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dtwr)(self, _cmd, request, ch);
        [dummy cancel]; return dummy;
    }
    return ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dtwr)(self, _cmd, request, ch);
}

// ========== 9. TTNetworkManager commonParams Hook ==========
static IMP orig_commonParams = NULL;
static id my_commonParams(id self, SEL _cmd) {
    id result = ((id (*)(id, SEL))orig_commonParams)(self, _cmd);
    bypassLog([NSString stringWithFormat:@"[TTNetwork] commonParams -> %@", safeDesc(result)]);
    return result;
}

static IMP orig_commonParamsblock = NULL;
static id my_commonParamsblock(id self, SEL _cmd) {
    id result = ((id (*)(id, SEL))orig_commonParamsblock)(self, _cmd);
    bypassLog([NSString stringWithFormat:@"[TTNetwork] commonParamsblock -> %@", safeDesc(result)]);
    return result;
}

static IMP orig_commonParamsblockWithURL = NULL;
static id my_commonParamsblockWithURL(id self, SEL _cmd) {
    id result = ((id (*)(id, SEL))orig_commonParamsblockWithURL)(self, _cmd);
    bypassLog([NSString stringWithFormat:@"[TTNetwork] commonParamsblockWithURL -> %@", safeDesc(result)]);
    return result;
}

static IMP orig_creatAppInfo = NULL;
static id my_creatAppInfo(id self, SEL _cmd) {
    id result = ((id (*)(id, SEL))orig_creatAppInfo)(self, _cmd);
    bypassLog([NSString stringWithFormat:@"[TTNetwork] creatAppInfo -> %@", safeDesc(result)]);
    return result;
}

static IMP orig_clientIP = NULL;
static id my_clientIP(id self, SEL _cmd) {
    id result = ((id (*)(id, SEL))orig_clientIP)(self, _cmd);
    bypassLog([NSString stringWithFormat:@"[TTNetwork] clientIP -> %@", safeDesc(result)]);
    return result;
}

static void hookTTNetworkCommonParams(void) {
    Class ttMgr = objc_getClass("TTNetworkManager");
    if (!ttMgr) { bypassLog(@"[TTNetwork] TTNetworkManager not found"); return; }

    Method m;
    if ((m = class_getInstanceMethod(ttMgr, @selector(commonParams)))) {
        orig_commonParams = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_commonParams);
        bypassLog(@"[Hook] TTNetworkManager commonParams hooked");
    }
    if ((m = class_getInstanceMethod(ttMgr, @selector(commonParamsblock)))) {
        orig_commonParamsblock = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_commonParamsblock);
        bypassLog(@"[Hook] TTNetworkManager commonParamsblock hooked");
    }
    if ((m = class_getInstanceMethod(ttMgr, @selector(commonParamsblockWithURL)))) {
        orig_commonParamsblockWithURL = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_commonParamsblockWithURL);
        bypassLog(@"[Hook] TTNetworkManager commonParamsblockWithURL hooked");
    }
    if ((m = class_getInstanceMethod(ttMgr, @selector(creatAppInfo)))) {
        orig_creatAppInfo = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_creatAppInfo);
        bypassLog(@"[Hook] TTNetworkManager creatAppInfo hooked");
    }
    if ((m = class_getInstanceMethod(ttMgr, @selector(clientIP)))) {
        orig_clientIP = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_clientIP);
        bypassLog(@"[Hook] TTNetworkManager clientIP hooked");
    }
}

// ========== 10. TTHttpTask init Hook - 截获请求对象 ==========
static IMP orig_tt_init = NULL;
static id my_tt_init(id self, SEL _cmd, id request, id scheduler, id engine, id dispatchQueue, id taskId, id enableHttpCache, id completedCallback, id uploadProgressCallback, id downloadProgressCallback) {
    bypassLog([NSString stringWithFormat:@"[TTNetwork] TTHttpTask init request=%@", safeDesc(request)]);
    return ((id (*)(id, SEL, id, id, id, id, id, id, id, id, id))orig_tt_init)(self, _cmd, request, scheduler, engine, dispatchQueue, taskId, enableHttpCache, completedCallback, uploadProgressCallback, downloadProgressCallback);
}

static void hookTTHttpTask(void) {
    Class ttTask = objc_getClass("TTHttpTask");
    if (!ttTask) { bypassLog(@"[TTNetwork] TTHttpTask not found"); return; }

    // 尝试 hook initWithRequest: 变体
    SEL sel = NSSelectorFromString(@"initWithRequest_fq_scheduler:engine:dispatchQueue:taskId:enableHttpCache:completedCallback:uploadProgressCallback:downloadProgressCallback:");
    Method m = class_getInstanceMethod(ttTask, sel);
    if (m) {
        orig_tt_init = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_tt_init);
        bypassLog(@"[Hook] TTHttpTask initWithRequest_fq_scheduler hooked");
    } else {
        // 尝试更短的变体
        bypassLog(@"[TTNetwork] initWithRequest_fq_scheduler not found, trying alternatives");
    }
}

// ========== 11. 初始化 (priority 101) ==========
__attribute__((constructor(101))) static void constructor(void) {
    bypassLog(@"=== AliSecBypass v5.9 init ===");

    initDeviceProfile();
    hookUIDevice();
    hookASIdentifierManager();
    hookScreenAndProcessInfo();
    hookTTNetworkCommonParams();
    hookTTHttpTask();

    struct rebinding rebinds[] = {
        {"connect", (void *)my_connect, (void **)&orig_connect},
        {"sendto", (void *)my_sendto, (void **)&orig_sendto},
        {"ptrace", (void *)my_ptrace, (void **)&orig_ptrace},
        {"sysctl", (void *)my_sysctl, (void **)&orig_sysctl},
        {"getaddrinfo", (void *)my_getaddrinfo, (void **)&orig_getaddrinfo},
        {"uname", (void *)my_uname, (void **)&orig_uname},
        {"dlopen", (void *)my_dlopen, (void **)&orig_dlopen},
        {"dlsym", (void *)my_dlsym, (void **)&orig_dlsym},
        {"_dyld_get_image_name", (void *)my_dyld_get_image_name, (void **)&orig_dyld_get_image_name}
    };
    rebind_symbols(rebinds, 9);

    Class cls = objc_getClass("NSURLSession");
    if (cls) {
        Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
        if (m1) { orig_dtwr = method_getImplementation(m1); method_setImplementation(m1, (IMP)my_dtwr); }
    }

    bypassLog(@"=== AliSecBypass v5.9 init complete ===");
}
