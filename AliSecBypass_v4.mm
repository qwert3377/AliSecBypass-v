// AliSecBypass v4.9 - 增强版：首次打开全设备指纹伪造 + 关键上报拦截
// fishhook + ObjC Runtime 混合方案
// 纯库文件，无 Logos，TrollStore / 非越狱注入

#include <Foundation/Foundation.h>
#include <objc/runtime.h>
#include <dlfcn.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <fishhook.h>
#include <dobby.h>

// ========== 日志工具（异步写 App Documents 目录）==========
static dispatch_queue_t gLogQueue = NULL;

static void bypassLog(NSString *msg) {
    if (!gLogQueue) {
        gLogQueue = dispatch_queue_create("com.bypass.log", DISPATCH_QUEUE_SERIAL);
    }
    dispatch_async(gLogQueue, ^{
        NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                      dateStyle:NSDateFormatterNoStyle
                                                      timeStyle:NSDateFormatterMediumStyle];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docDir = paths.firstObject;
        NSString *logPath = [docDir stringByAppendingPathComponent:@"AliSecBypass.log"];

        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        } else {
            [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    });
}

// ========== 设备指纹池（每次首次打开随机选一套）==========
static NSDictionary *gDeviceProfile = nil;

static void initDeviceProfile(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDictionary *saved = [ud objectForKey:@"AliSecBypass_DeviceProfile"];

    if (!saved) {
        // 预定义几套真实设备指纹
        NSArray *profiles = @[
            @{@"model": @"iPhone14,2", @"systemVersion": @"17.5.1", @"name": @"iPhone", @"machine": @"iPhone14,2"},
            @{@"model": @"iPhone13,2", @"systemVersion": @"16.6.1", @"name": @"iPhone", @"machine": @"iPhone13,2"},
            @{@"model": @"iPhone15,2", @"systemVersion": @"18.0",   @"name": @"iPhone", @"machine": @"iPhone15,2"},
            @{@"model": @"iPhone12,1", @"systemVersion": @"15.7.2", @"name": @"iPhone", @"machine": @"iPhone12,1"},
            @{@"model": @"iPhone14,7", @"systemVersion": @"17.2",   @"name": @"iPhone", @"machine": @"iPhone14,7"},
        ];
        NSUInteger idx = arc4random_uniform((uint32_t)profiles.count);
        saved = profiles[idx];
        [ud setObject:saved forKey:@"AliSecBypass_DeviceProfile"];
        [ud synchronize];
        bypassLog([NSString stringWithFormat:@"[Profile] New device profile: %@", saved]);
    } else {
        bypassLog([NSString stringWithFormat:@"[Profile] Reuse profile: %@", saved]);
    }
    gDeviceProfile = saved;
}

// ========== 1. 伪造 UIDevice 信息 ==========
static NSUUID *(*orig_identifierForVendor)(id, SEL);
static NSUUID *my_identifierForVendor(id self, SEL _cmd) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *fakeID = [ud stringForKey:@"AliSecBypass_FakeID"];
    if (!fakeID) {
        fakeID = [[NSUUID UUID] UUIDString];
        [ud setObject:fakeID forKey:@"AliSecBypass_FakeID"];
        [ud synchronize];
    }
    return [[NSUUID alloc] initWithUUIDString:fakeID];
}

static NSString *(*orig_systemVersion)(id, SEL);
static NSString *my_systemVersion(id self, SEL _cmd) {
    return gDeviceProfile[@"systemVersion"] ?: @"17.0";
}

static NSString *(*orig_model)(id, SEL);
static NSString *my_model(id self, SEL _cmd) {
    return gDeviceProfile[@"model"] ?: @"iPhone";
}

static NSString *(*orig_name)(id, SEL);
static NSString *my_name(id, SEL) {
    return gDeviceProfile[@"name"] ?: @"iPhone";
}

static void hookUIDevice(void) {
    Class cls = objc_getClass("UIDevice");
    if (!cls) return;

    Method m1 = class_getInstanceMethod(cls, sel_registerName("identifierForVendor"));
    if (m1) { orig_identifierForVendor = (void *)method_getImplementation(m1); method_setImplementation(m1, (IMP)my_identifierForVendor); }

    Method m2 = class_getInstanceMethod(cls, sel_registerName("systemVersion"));
    if (m2) { orig_systemVersion = (void *)method_getImplementation(m2); method_setImplementation(m2, (IMP)my_systemVersion); }

    Method m3 = class_getInstanceMethod(cls, sel_registerName("model"));
    if (m3) { orig_model = (void *)method_getImplementation(m3); method_setImplementation(m3, (IMP)my_model); }

    Method m4 = class_getInstanceMethod(cls, sel_registerName("name"));
    if (m4) { orig_name = (void *)method_getImplementation(m4); method_setImplementation(m4, (IMP)my_name); }

    bypassLog(@"[Hook] UIDevice hooked");
}

// ========== 2. 伪造 ASIdentifierManager advertisingIdentifier ==========
static NSUUID *(*orig_advertisingIdentifier)(id, SEL);
static NSUUID *my_advertisingIdentifier(id self, SEL _cmd) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *fakeID = [ud stringForKey:@"AliSecBypass_FakeID"];
    if (fakeID) {
        return [[NSUUID alloc] initWithUUIDString:fakeID];
    }
    return orig_advertisingIdentifier(self, _cmd);
}

static void hookASIdentifierManager(void) {
    Class cls = objc_getClass("ASIdentifierManager");
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel_registerName("advertisingIdentifier"));
    if (m) {
        orig_advertisingIdentifier = (void *)method_getImplementation(m);
        method_setImplementation(m, (IMP)my_advertisingIdentifier);
        bypassLog(@"[Hook] ASIdentifierManager hooked");
    }
}

// ========== 3. 伪造 uname / sysctl 获取 machine 型号 ==========
static int (*orig_uname)(struct utsname *);
static int my_uname(struct utsname *name) {
    int ret = orig_uname(name);
    if (ret == 0 && gDeviceProfile) {
        NSString *machine = gDeviceProfile[@"machine"];
        if (machine) {
            strncpy(name->machine, [machine UTF8String], sizeof(name->machine) - 1);
            name->machine[sizeof(name->machine) - 1] = '\0';
        }
    }
    return ret;
}

// ========== 4. fishhook 系统函数 Hook ==========
static int (*orig_connect)(int, const struct sockaddr *, socklen_t);
static int my_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (addr && addr->sa_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in *)addr;
        NSString *ipStr = [NSString stringWithFormat:@"%s", inet_ntoa(sin->sin_addr)];
        bypassLog([NSString stringWithFormat:@"[connect] %@:%d", ipStr, ntohs(sin->sin_port)]);
    }
    return orig_connect(sockfd, addr, addrlen);
}

static int (*orig_ptrace)(int, pid_t, caddr_t, int);
static int my_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == 0) {
        bypassLog(@"[ptrace] anti-debug blocked");
        return 0;
    }
    return orig_ptrace(request, pid, addr, data);
}

static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int my_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (ret == 0 && namelen >= 2) {
        if (name[0] == CTL_KERN && name[1] == KERN_PROC) {
            bypassLog(@"[sysctl] KERN_PROC query blocked");
            if (oldp && oldlenp) memset(oldp, 0, *oldlenp);
            return 0;
        }
    }
    return ret;
}

static BOOL isBlockedHost(NSString *host) {
    if (!host || host.length == 0) return NO;
    NSArray *blockKeywords = @[@"tnc16-alisg", @"tnc16-alisc1", @"mon11-misc", @"security-lq", @"pitaya.bytedance", @"mssdk3-normal"];
    for (NSString *kw in blockKeywords) {
        if ([host containsString:kw]) return YES;
    }
    return NO;
}

static BOOL isFirstLaunchReport(NSString *urlStr) {
    if (!urlStr) return NO;
    // 首次上报的关键域名/路径
    NSArray *reportKeywords = @[@"wosms.cn", @"unicomAuth", @"device_register", @"service_register", @"active"];
    for (NSString *kw in reportKeywords) {
        if ([urlStr containsString:kw]) return YES;
    }
    return NO;
}

static int (*orig_getaddrinfo)(const char *, const char *, const struct addrinfo *, struct addrinfo **);
static int my_getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res) {
    if (node) {
        NSString *host = [NSString stringWithUTF8String:node];
        bypassLog([NSString stringWithFormat:@"[getaddrinfo] %@", host]);
        if (isBlockedHost(host)) {
            bypassLog([NSString stringWithFormat:@"[getaddrinfo] BLOCKED: %@", host]);
            return EAI_NONAME;
        }
    }
    return orig_getaddrinfo(node, service, hints, res);
}

// ========== 5. NSURLSession Hook - 拦截首次上报 + 打印数据 ==========
static IMP orig_dataTaskWithRequest = NULL;

static NSURLSessionDataTask *my_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request, void (^completionHandler)(NSData *, NSURLResponse *, NSError *)) {
    NSURL *url = request.URL;
    NSString *urlStr = url.absoluteString;
    NSString *host = url.host ?: @"";

    // 打印关键请求（首次上报 + 检测域名）
    BOOL isReport = isFirstLaunchReport(urlStr);
    BOOL isBlocked = isBlockedHost(host);

    if (isReport || isBlocked) {
        NSMutableString *log = [NSMutableString stringWithFormat:@"\n========== %@ ==========\nURL: %@\nMethod: %@\nHeaders: %@\n", isReport ? @"FIRST LAUNCH REPORT" : @"BLOCKED REQUEST", urlStr, request.HTTPMethod, request.allHTTPHeaderFields];

        if (request.HTTPBody) {
            id json = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil];
            if (json) {
                [log appendFormat:@"Body(JSON): %@\n", json];
            } else {
                NSString *base64 = [request.HTTPBody base64EncodedStringWithOptions:0];
                [log appendFormat:@"Body(Base64): %@\n", base64];
            }
        }
        [log appendString:@"==============================\n"];
        bypassLog(log);
    }

    // 拦截检测域名
    if (isBlocked) {
        bypassLog([NSString stringWithFormat:@"[NSURLSession] BLOCKED: %@", host]);
        NSURLSessionDataTask *dummy = ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dataTaskWithRequest)(self, _cmd, request, completionHandler);
        [dummy cancel];
        return dummy;
    }

    // 拦截首次上报（让上报失败，App 继续运行）
    if (isReport) {
        bypassLog([NSString stringWithFormat:@"[NSURLSession] FIRST REPORT BLOCKED: %@", urlStr]);
        // 返回伪造的失败响应
        if (completionHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(nil, nil, [NSError errorWithDomain:@"NSURLErrorDomain" code:-1001 userInfo:@{NSLocalizedDescriptionKey: @"Request timeout"}]);
            });
        }
        // 创建一个 dummy task 并立即完成
        NSURLSessionDataTask *dummy = ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dataTaskWithRequest)(self, _cmd, request, nil);
        return dummy;
    }

    return ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dataTaskWithRequest)(self, _cmd, request, completionHandler);
}

static void hookNSURLSession(void) {
    Class cls = objc_getClass("NSURLSession");
    if (!cls) { bypassLog(@"[Hook] NSURLSession not found"); return; }
    SEL sel = sel_registerName("dataTaskWithRequest:completionHandler:");
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { bypassLog(@"[Hook] dataTaskWithRequest not found"); return; }
    orig_dataTaskWithRequest = method_getImplementation(m);
    method_setImplementation(m, (IMP)my_dataTaskWithRequest);
    bypassLog(@"[Hook] NSURLSession hooked");
}

// ========== 6. 初始化 ==========
static void initAllHooks(void) {
    bypassLog(@"=== AliSecBypass v4.9 init ===");

    // 先初始化设备指纹（必须在其他 Hook 之前）
    initDeviceProfile();

    // Hook 设备信息
    hookUIDevice();
    hookASIdentifierManager();

    // fishhook 系统函数
    struct rebinding rebinds[] = {
        {"connect", (void *)my_connect, (void **)&orig_connect},
        {"ptrace", (void *)my_ptrace, (void **)&orig_ptrace},
        {"sysctl", (void *)my_sysctl, (void **)&orig_sysctl},
        {"getaddrinfo", (void *)my_getaddrinfo, (void **)&orig_getaddrinfo},
        {"uname", (void *)my_uname, (void **)&orig_uname}
    };
    int ret = rebind_symbols(rebinds, 5);
    bypassLog([NSString stringWithFormat:@"[fishhook] rebind_symbols returned: %d", ret]);

    // NSURLSession Hook
    hookNSURLSession();

    bypassLog(@"=== AliSecBypass v4.9 init complete ===");
}

// ========== 构造函数（延迟 2 秒，后台队列）==========
__attribute__((constructor)) static void constructor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        initAllHooks();
    });
}
