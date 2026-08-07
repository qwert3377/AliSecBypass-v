// AliSecBypass v4.6 - fishhook + Dobby + ObjC Runtime 混合方案
// 纯库文件，无 Logos，TrollStore / 非越狱注入
// 系统函数用 fishhook，静态函数用 Dobby

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

static void bypassLog(NSString *fmt, ...) {
    if (!gLogQueue) {
        gLogQueue = dispatch_queue_create("com.bypass.log", DISPATCH_QUEUE_SERIAL);
    }

    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

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

// ========== Dobby 安全 Hook 封装（用于静态函数）==========
static int safeDobbyHook(const char *name, void *replace, void **orig) {
    void *target = dlsym(RTLD_DEFAULT, name);
    if (!target) {
        bypassLog(@"[Dobby] %s not found, skip", name);
        return -1;
    }
    int ret = DobbyHook(target, replace, orig);
    if (ret != 0) {
        bypassLog(@"[Dobby] %s hook failed: %d", name, ret);
        return ret;
    }
    bypassLog(@"[Dobby] %s hooked", name);
    return 0;
}

// ========== 1. fishhook connect() - Socket 层拦截 ==========
static int (*orig_connect)(int, const struct sockaddr *, socklen_t);
static int my_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (addr && addr->sa_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in *)addr;
        char ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &sin->sin_addr, ip, sizeof(ip));
        bypassLog(@"[connect] %s:%d", [NSString stringWithUTF8String:ip], ntohs(sin->sin_port));
    }
    return orig_connect(sockfd, addr, addrlen);
}

// ========== 2. fishhook ptrace() - 反调试绕过 ==========
static int (*orig_ptrace)(int, pid_t, caddr_t, int);
static int my_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == 0) { // PT_TRACE_ME
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
static int (*orig_getaddrinfo)(const char *, const char *, const struct addrinfo *, struct addrinfo **);
static int my_getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res) {
    if (node) {
        NSString *host = [NSString stringWithUTF8String:node];
        bypassLog(@"[getaddrinfo] %@", host);

        NSArray *blockHosts = @[@"tnc16-alisg.fqnovel.com",
                                 @"tnc16-alisg.byteoversea.com",
                                 @"tnc16-alisc1.fqnovel.com",
                                 @"mon11-misc.fqnovel.com",
                                 @"security-lq.snssdk.com",
                                 @"security-lq.byteoversea.com"];
        for (NSString *bh in blockHosts) {
            if ([host containsString:bh]) {
                bypassLog(@"[getaddrinfo] BLOCKED: %@", host);
                return EAI_NONAME;
            }
        }
    }
    return orig_getaddrinfo(node, service, hints, res);
}

// ========== 5. ObjC Runtime Hook NSURLSession - 应用层拦截 ==========
static IMP orig_dataTaskWithRequest = NULL;

static NSURLSessionDataTask *my_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request, void (^completionHandler)(NSData *, NSURLResponse *, NSError *)) {
    NSURL *url = request.URL;
    bypassLog(@"[NSURLSession] %@", url.absoluteString);

    NSArray *blockHosts = @[@"tnc16-alisg.fqnovel.com",
                             @"tnc16-alisg.byteoversea.com",
                             @"mon11-misc.fqnovel.com",
                             @"security-lq.snssdk.com",
                             @"security-lq.byteoversea.com"];

    for (NSString *bh in blockHosts) {
        if ([url.host containsString:bh]) {
            bypassLog(@"[NSURLSession] BLOCKED: %@", url.host);
            NSURLSessionDataTask *dummy = ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dataTaskWithRequest)(self, _cmd, request, completionHandler);
            [dummy cancel];
            return dummy;
        }
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

// ========== 6. 初始化所有 Hook ==========
static void initAllHooks(void) {
    bypassLog(@"=== AliSecBypass v4.6 init ===");

    // fishhook 系统函数（connect/ptrace/sysctl/getaddrinfo）
    struct rebinding rebinds[] = {
        {"connect", (void *)my_connect, (void **)&orig_connect},
        {"ptrace", (void *)my_ptrace, (void **)&orig_ptrace},
        {"sysctl", (void *)my_sysctl, (void **)&orig_sysctl},
        {"getaddrinfo", (void *)my_getaddrinfo, (void **)&orig_getaddrinfo}
    };
    int ret = rebind_symbols(rebinds, 4);
    bypassLog(@"[fishhook] rebind_symbols returned: %d", ret);

    // ObjC Runtime Hook
    hookNSURLSession();

    // Dobby 备用（用于 Hook 静态函数，当前未使用）
    // safeDobbyHook("some_static_func", (void *)my_func, (void **)&orig_func);

    bypassLog(@"=== AliSecBypass v4.6 init complete ===");
}

// ========== 构造函数（延迟 2 秒执行，避免启动时卡死）==========
__attribute__((constructor)) static void constructor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        initAllHooks();
    });
}
