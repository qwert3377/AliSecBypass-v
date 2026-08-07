// AliSecBypass v4.8 - fishhook + ObjC Runtime 混合方案
// 纯库文件，无 Logos，TrollStore / 非越狱注入
// 功能：反调试 + 网络拦截 + 越狱隐藏 + 首次打开换 ID

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

// ========== ID 替换（首次打开换 ID，后续复用）==========
static NSString *gFakeID = nil;

static NSUUID *(*orig_identifierForVendor)(id, SEL);
static NSUUID *my_identifierForVendor(id self, SEL _cmd) {
    if (gFakeID) {
        return [[NSUUID alloc] initWithUUIDString:gFakeID];
    }
    return orig_identifierForVendor(self, _cmd);
}

static NSUUID *(*orig_advertisingIdentifier)(id, SEL);
static NSUUID *my_advertisingIdentifier(id self, SEL _cmd) {
    if (gFakeID) {
        return [[NSUUID alloc] initWithUUIDString:gFakeID];
    }
    return orig_advertisingIdentifier(self, _cmd);
}

static void initIDSwap(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *savedID = [ud stringForKey:@"AliSecBypass_FakeID"];

    if (!savedID) {
        savedID = [[NSUUID UUID] UUIDString];
        [ud setObject:savedID forKey:@"AliSecBypass_FakeID"];
        [ud synchronize];
        bypassLog([NSString stringWithFormat:@"[IDSwap] First launch, new ID: %@", savedID]);
    } else {
        bypassLog([NSString stringWithFormat:@"[IDSwap] Reuse saved ID: %@", savedID]);
    }
    gFakeID = savedID;

    // Hook UIDevice identifierForVendor
    Class uidClass = objc_getClass("UIDevice");
    if (uidClass) {
        SEL sel = sel_registerName("identifierForVendor");
        Method m = class_getInstanceMethod(uidClass, sel);
        if (m) {
            orig_identifierForVendor = (void *)method_getImplementation(m);
            method_setImplementation(m, (IMP)my_identifierForVendor);
            bypassLog(@"[IDSwap] UIDevice identifierForVendor hooked");
        }
    }

    // Hook ASIdentifierManager advertisingIdentifier
    Class asClass = objc_getClass("ASIdentifierManager");
    if (asClass) {
        SEL sel = sel_registerName("advertisingIdentifier");
        Method m = class_getInstanceMethod(asClass, sel);
        if (m) {
            orig_advertisingIdentifier = (void *)method_getImplementation(m);
            method_setImplementation(m, (IMP)my_advertisingIdentifier);
            bypassLog(@"[IDSwap] ASIdentifierManager advertisingIdentifier hooked");
        }
    }
}

// ========== 1. fishhook connect() - Socket 层拦截 ==========
static int (*orig_connect)(int, const struct sockaddr *, socklen_t);
static int my_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (addr && addr->sa_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in *)addr;
        NSString *ipStr = [NSString stringWithFormat:@"%s", inet_ntoa(sin->sin_addr)];
        bypassLog([NSString stringWithFormat:@"[connect] %@:%d", ipStr, ntohs(sin->sin_port)]);
    }
    return orig_connect(sockfd, addr, addrlen);
}

// ========== 2. fishhook ptrace() - 反调试绕过 ==========
static int (*orig_ptrace)(int, pid_t, caddr_t, int);
static int my_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == 0) {
        bypassLog(@"[ptrace] anti-debug blocked");
        return 0;
    }
    return orig_ptrace(request, pid, addr, data);
}

// ========== 3. fishhook sysctl() - 隐藏越狱痕迹 ==========
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

// ========== 4. fishhook getaddrinfo() - DNS 层拦截 ==========
static BOOL isBlockedHost(NSString *host) {
    if (!host || host.length == 0) return NO;

    NSArray *blockKeywords = @[@"tnc16-alisg",
                                @"tnc16-alisc1",
                                @"mon11-misc",
                                @"security-lq",
                                @"pitaya.bytedance",
                                @"mssdk3-normal"];

    for (NSString *kw in blockKeywords) {
        if ([host containsString:kw]) {
            return YES;
        }
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

// ========== 5. ObjC Runtime Hook NSURLSession - 应用层拦截 ==========
static IMP orig_dataTaskWithRequest = NULL;

static NSURLSessionDataTask *my_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request, void (^completionHandler)(NSData *, NSURLResponse *, NSError *)) {
    NSURL *url = request.URL;
    bypassLog([NSString stringWithFormat:@"[NSURLSession] %@", url.absoluteString]);

    if (isBlockedHost(url.host)) {
        bypassLog([NSString stringWithFormat:@"[NSURLSession] BLOCKED: %@", url.host]);
        NSURLSessionDataTask *dummy = ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dataTaskWithRequest)(self, _cmd, request, completionHandler);
        [dummy cancel];
        return dummy;
    }

    return ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dataTaskWithRequest)(self, _cmd, request, completionHandler);
}

static void hookNSURLSession(void) {
    Class cls = objc_getClass("NSURLSession");
    if (!cls) {
        bypassLog(@"[Hook] NSURLSession class not found");
        return;
    }

    SEL sel = sel_registerName("dataTaskWithRequest:completionHandler:");
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        bypassLog(@"[Hook] dataTaskWithRequest:completionHandler: not found");
        return;
    }

    orig_dataTaskWithRequest = method_getImplementation(m);
    method_setImplementation(m, (IMP)my_dataTaskWithRequest);
    bypassLog(@"[Hook] NSURLSession dataTaskWithRequest: hooked");
}

// ========== 6. 初始化 ==========
static void initAllHooks(void) {
    bypassLog(@"=== AliSecBypass v4.8 init ===");

    // 首次打开换 ID
    initIDSwap();

    // fishhook 系统函数
    struct rebinding rebinds[] = {
        {"connect", (void *)my_connect, (void **)&orig_connect},
        {"ptrace", (void *)my_ptrace, (void **)&orig_ptrace},
        {"sysctl", (void *)my_sysctl, (void **)&orig_sysctl},
        {"getaddrinfo", (void *)my_getaddrinfo, (void **)&orig_getaddrinfo}
    };
    int ret = rebind_symbols(rebinds, 4);
    bypassLog([NSString stringWithFormat:@"[fishhook] rebind_symbols returned: %d", ret]);

    // ObjC Runtime Hook
    hookNSURLSession();

    bypassLog(@"=== AliSecBypass v4.8 init complete ===");
}

// ========== 构造函数（延迟 2 秒，后台队列）==========
__attribute__((constructor)) static void constructor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        initAllHooks();
    });
}
