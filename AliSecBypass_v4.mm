// AliSecBypass v5.8 - Hook TTNetwork + 探测设备指纹上报 + 隐藏容器内网IP
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

// ========== 辅助：打印对象描述（递归安全）==========
static NSString *safeDescription(id obj) {
    if (!obj) return @"(nil)";
    if ([obj isKindOfClass:[NSString class]]) return obj;
    if ([obj isKindOfClass:[NSNumber class]]) return [obj stringValue];
    if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *arr = obj;
        if (arr.count == 0) return @"[]";
        NSMutableString *s = [NSMutableString stringWithString:@"["];
        for (id item in arr) { [s appendFormat:@"%@,", safeDescription(item)]; }
        [s appendString:@"]"];
        return s;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = obj;
        if (dict.count == 0) return @"{}";
        NSMutableString *s = [NSMutableString stringWithString:@"{"];
        [dict enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
            [s appendFormat:@"%@=%@;", key, safeDescription(val)];
        }];
        [s appendString:@"}"];
        return s;
    }
    if ([obj isKindOfClass:[NSData class]]) {
        NSData *d = obj;
        NSString *str = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (str) return str;
        return [d base64EncodedStringWithOptions:0];
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
    } else {
        bypassLog([NSString stringWithFormat:@"[Profile] REUSE: %@", saved]);
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
        // 隐藏容器内网IP连接（172.31.x.x 是 AWS/阿里云内网，暴露容器环境）
        if ([ipStr hasPrefix:@"172.31."]) {
            bypassLog([NSString stringWithFormat:@"[connect] HIDDEN container IP: %@:%d", ipStr, port]);
            // 返回连接失败，让App以为这个服务不可用
            errno = ECONNREFUSED;
            return -1;
        }
        bypassLog([NSString stringWithFormat:@"[connect] %@:%d", ipStr, port]);
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
    bypassLog([NSString stringWithFormat:@"[NSURLSession] %@ %@", request.HTTPMethod, url.absoluteString]);
    if (isBlockedHost(host)) {
        NSURLSessionDataTask *dummy = ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dtwr)(self, _cmd, request, ch);
        [dummy cancel]; return dummy;
    }
    return ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dtwr)(self, _cmd, request, ch);
}

// ========== 9. TTNetwork Hook - 截获字节自研网络库请求 ==========
static void logTTRequest(id requestObj) {
    if (!requestObj) return;
    // 尝试读取 URL
    NSString *url = nil;
    if ([requestObj respondsToSelector:@selector(URL)]) url = [requestObj performSelector:@selector(URL)];
    if (!url && [requestObj respondsToSelector:@selector(url)]) url = [requestObj performSelector:@selector(url)];
    if (!url && [requestObj respondsToSelector:@selector(requestURL)]) url = [requestObj performSelector:@selector(requestURL)];

    // 尝试读取 params
    id params = nil;
    if ([requestObj respondsToSelector:@selector(params)]) params = [requestObj performSelector:@selector(params)];
    if (!params && [requestObj respondsToSelector:@selector(requestParams)]) params = [requestObj performSelector:@selector(requestParams)];

    // 尝试读取 method
    NSString *method = @"GET";
    if ([requestObj respondsToSelector:@selector(method)]) {
        id m = [requestObj performSelector:@selector(method)];
        if (m) method = [m description];
    }

    bypassLog([NSString stringWithFormat:@"[TTNetwork] %@ %@ | params: %@", method, url ?: @"(no url)", safeDescription(params)]);
}

// Hook TTNetworkManager 的通用请求方法
static IMP orig_tt_request = NULL;
static id my_tt_request(id self, SEL _cmd, id arg1, id arg2, id arg3, id arg4, id arg5, id arg6, id arg7, id arg8) {
    logTTRequest(arg1);
    bypassLog([NSString stringWithFormat:@"[TTNetwork] request called: %@", NSStringFromSelector(_cmd)]);
    return ((id (*)(id, SEL, id, id, id, id, id, id, id, id))orig_tt_request)(self, _cmd, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8);
}

static void hookTTNetwork(void) {
    Class ttMgr = objc_getClass("TTNetworkManager");
    if (!ttMgr) { bypassLog(@"[TTNetwork] TTNetworkManager not found"); return; }

    bypassLog(@"[TTNetwork] Hooking TTNetworkManager...");

    // 探测所有方法
    unsigned int count;
    Method *methods = class_copyMethodList(object_getClass(ttMgr), &count); // 类方法
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(sel);
        bypassLog([NSString stringWithFormat:@"[TTNetwork] ClassMethod: %@", name]);
    }
    free(methods);

    methods = class_copyMethodList(ttMgr, &count); // 实例方法
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(sel);
        bypassLog([NSString stringWithFormat:@"[TTNetwork] InstanceMethod: %@", name]);

        // Hook 包含 request/Request 且参数较多的方法（通常是网络请求）
        if ([name containsString:@"request"] || [name containsString:@"Request"]) {
            int nargs = method_getNumberOfArguments(methods[i]);
            bypassLog([NSString stringWithFormat:@"[TTNetwork] Will hook: %@ (args=%d)", name, nargs]);
            // 用 DobbyHook 替换实现
            IMP oldIMP = method_getImplementation(methods[i]);
            // 创建通用 hook，记录调用
            // 由于方法签名不同，这里用 method_setImplementation 做简单替换
            // 实际替换需要匹配参数数量
        }
    }
    free(methods);

    // Hook TTNetworkManager sharedInstance 获取单例后，hook 其 request 方法
    // 常见方法名尝试
    NSArray *methodNames = @[
        @"requestForJSONWithURL:params:method:needCommonParams:requestSerializer:responseSerializer:success:failure:",
        @"requestForBinaryWithURL:params:method:needCommonParams:requestSerializer:responseSerializer:success:failure:",
        @"requestWithURL:params:method:needCommonParams:requestSerializer:responseSerializer:success:failure:",
        @"requestForJSONWithURL:params:method:needCommonParams:requestSerializer:responseSerializer:progress:success:failure:",
        @"requestForBinaryWithURL:params:method:needCommonParams:requestSerializer:responseSerializer:progress:success:failure:",
        @"requestWithURL:params:method:needCommonParams:requestSerializer:responseSerializer:progress:success:failure:",
    ];

    for (NSString *mname in methodNames) {
        SEL sel = NSSelectorFromString(mname);
        Method m = class_getInstanceMethod(ttMgr, sel);
        if (m) {
            bypassLog([NSString stringWithFormat:@"[TTNetwork] Hooked: %@", mname]);
            // 用 block 方式 hook，记录参数
            orig_tt_request = method_getImplementation(m);
            method_setImplementation(m, (IMP)my_tt_request);
        }
    }

    // 也尝试 hook TTHttpTask
    Class ttTask = objc_getClass("TTHttpTask");
    if (ttTask) {
        Method *taskMethods = class_copyMethodList(ttTask, &count);
        for (unsigned int i = 0; i < count; i++) {
            SEL sel = method_getName(taskMethods[i]);
            NSString *name = NSStringFromSelector(sel);
            bypassLog([NSString stringWithFormat:@"[TTNetwork] TTHttpTask method: %@", name]);
        }
        free(taskMethods);
    }
}

// ========== 10. 初始化 (priority 101) ==========
__attribute__((constructor(101))) static void constructor(void) {
    bypassLog(@"=== AliSecBypass v5.8 init ===");

    initDeviceProfile();
    hookUIDevice();
    hookASIdentifierManager();
    hookScreenAndProcessInfo();
    hookTTNetwork();

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

    bypassLog(@"=== AliSecBypass v5.8 init complete ===");
}
