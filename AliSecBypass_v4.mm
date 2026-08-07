// AliSecBypass v6.1.12 - 针对番茄畅听/红果/番茄小说字节系容器秒检测修复
// 修复点：1)增加HTTP请求日志 2)Hook Keychain防旧IDFV泄露 3)Hook NSBundle隐藏容器特征
//         4)扩充字段覆盖 5)探测BDAutoTrack/RangersAppLog 6)清理NSUserDefaults旧指纹
// fishhook + ObjC Runtime 纯库方案，无 Logos，TrollStore / 非越狱 / LiveContainer 注入

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
#include <mach-o/dyld.h>
#include <Security/Security.h>

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
        NSString *base = paths.firstObject;
        // 日志写到插件自身 Documents，避免被 App 清理
        NSString *logPath = [base stringByAppendingPathComponent:@"AliSecBypass.log"];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
        else { [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
    });
}

// ========== 全局伪装数据 ==========
static NSDictionary *gDeviceProfile = nil;
static NSString *gFakeIDFV = nil;
static NSString *gFakeIDFA = nil;
static NSString *gFakeOpenUDID = nil;
static NSString *gFakeOAID = nil;
static NSString *gFakeUUID = nil;
static NSString *gFakeAID = nil;
static BOOL gLoggedFirstPatch = NO;

static void initDeviceProfile(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDictionary *saved = [ud objectForKey:@"AliSecBypass_DeviceProfile"];
    if (!saved) {
        NSArray *profiles = @[
            @{@"model": @"iPhone14,2", @"systemVersion": @"17.5.1", @"name": @"iPhone", @"machine": @"iPhone14,2",
              @"screenW": @393, @"screenH": @852, @"scale": @3, @"mem": @6, @"disk": @128,
              @"tz": @"Asia/Shanghai", @"lang": @"zh-Hans-CN", @"carrier": @"中国联通"},
            @{@"model": @"iPhone13,2", @"systemVersion": @"16.6.1", @"name": @"iPhone", @"machine": @"iPhone13,2",
              @"screenW": @390, @"screenH": @844, @"scale": @3, @"mem": @4, @"disk": @256,
              @"tz": @"Asia/Shanghai", @"lang": @"zh-Hans-CN", @"carrier": @"中国移动"},
            @{@"model": @"iPhone15,2", @"systemVersion": @"18.0", @"name": @"iPhone", @"machine": @"iPhone15,2",
              @"screenW": @393, @"screenH": @852, @"scale": @3, @"mem": @8, @"disk": @512,
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

    gFakeOpenUDID = [ud stringForKey:@"AliSecBypass_FakeOpenUDID"];
    if (!gFakeOpenUDID) { gFakeOpenUDID = [[NSUUID UUID] UUIDString]; [ud setObject:gFakeOpenUDID forKey:@"AliSecBypass_FakeOpenUDID"]; [ud synchronize]; }

    gFakeOAID = [ud stringForKey:@"AliSecBypass_FakeOAID"];
    if (!gFakeOAID) { gFakeOAID = [[NSUUID UUID] UUIDString]; [ud setObject:gFakeOAID forKey:@"AliSecBypass_FakeOAID"]; [ud synchronize]; }

    gFakeUUID = [ud stringForKey:@"AliSecBypass_FakeUUID"];
    if (!gFakeUUID) { gFakeUUID = [[NSUUID UUID] UUIDString]; [ud setObject:gFakeUUID forKey:@"AliSecBypass_FakeUUID"]; [ud synchronize]; }

    gFakeAID = [ud stringForKey:@"AliSecBypass_FakeAID"];
    if (!gFakeAID) { gFakeAID = [NSString stringWithFormat:@"%u", arc4random_uniform(900000000) + 100000000]; [ud setObject:gFakeAID forKey:@"AliSecBypass_FakeAID"]; [ud synchronize]; }

    // 清理可能残留的旧真实指纹（字节常存 NSUserDefaults）
    NSArray *keysToRemove = @[@"kOpenUDID", @"openUDID", @"BDOpenUDID", @"RangersOpenUDID", @"ttinstall_id", @"tt_device_id", @"device_id_local"];
    for (NSString *k in keysToRemove) {
        if ([ud objectForKey:k]) { [ud removeObjectForKey:k]; }
    }
    [ud synchronize];
}

// ========== 核心：基于原始字典修改，覆盖字节系所有常见字段 ==========
static NSDictionary *patchCommonParams(NSDictionary *original) {
    if (!original) return nil;
    NSMutableDictionary *mut = [original mutableCopy];
    if (!mut) return original;

    // 保留 device_id（服务端生成账号标识），其余全伪装
    NSString *origVid = original[@"vid"];
    NSString *origModel = original[@"device_model"];
    NSString *origRes = original[@"resolution"];
    NSString *origIdfa = original[@"idfa"];
    NSString *origIdfv = original[@"idfv"];
    NSString *origOpenUDID = original[@"openudid"];
    NSString *origOAID = original[@"oaid"];
    NSString *origUUID = original[@"uuid"];
    NSString *origAID = original[@"aid"];
    NSString *origDeviceID = original[@"device_id"];

    mut[@"vid"] = gFakeIDFV;
    mut[@"idfv"] = gFakeIDFV;
    mut[@"idfa"] = gFakeIDFA ?: @"00000000-0000-0000-0000-000000000000";
    mut[@"cdid"] = [[NSUUID UUID] UUIDString];
    mut[@"openudid"] = gFakeOpenUDID;
    mut[@"oaid"] = gFakeOAID;
    mut[@"uuid"] = gFakeUUID;
    mut[@"aid"] = gFakeAID;
    // device_id 如果是服务端下发则保留，否则也伪装
    if (!origDeviceID || origDeviceID.length == 0) {
        mut[@"device_id"] = gFakeAID;
    }

    if (gDeviceProfile) {
        NSString *machine = gDeviceProfile[@"machine"] ?: gDeviceProfile[@"model"];
        NSString *model   = gDeviceProfile[@"model"];
        NSString *sysVer  = gDeviceProfile[@"systemVersion"];
        NSNumber *sw = gDeviceProfile[@"screenW"];
        NSNumber *sh = gDeviceProfile[@"screenH"];
        NSNumber *sc = gDeviceProfile[@"scale"];

        if (machine) mut[@"device_model"] = machine;
        if (model)   mut[@"device_brand"] = [model lowercaseString];
        if (sysVer)  mut[@"os_version"] = sysVer;

        if (sw && sh && sc) {
            int w = [sw intValue] * [sc intValue];
            int h = [sh intValue] * [sc intValue];
            mut[@"resolution"] = [NSString stringWithFormat:@"%d*%d", w, h];
        }

        static NSDictionary *typeMap = nil;
        static dispatch_once_t mapOnce;
        dispatch_once(&mapOnce, ^{
            typeMap = @{
                @"iPhone14,2": @"iPhone 13 Pro",
                @"iPhone13,2": @"iPhone 13",
                @"iPhone15,2": @"iPhone 14 Pro",
                @"iPhone12,5": @"iPhone 11 Pro Max",
                @"iPhone14,5": @"iPhone 13",
                @"iPhone13,1": @"iPhone 13 mini",
                @"iPhone14,4": @"iPhone 13 mini",
                @"iPhone15,3": @"iPhone 14 Pro Max",
            };
        });
        mut[@"device_type"] = typeMap[model] ?: [NSString stringWithFormat:@"iPhone (%@)", model];
    }

    if (!gLoggedFirstPatch) {
        gLoggedFirstPatch = YES;
        bypassLog([NSString stringWithFormat:@"[Patch] vid: %@ -> %@", origVid ?: @"(nil)", mut[@"vid"]]);
        bypassLog([NSString stringWithFormat:@"[Patch] device_model: %@ -> %@", origModel ?: @"(nil)", mut[@"device_model"]]);
        bypassLog([NSString stringWithFormat:@"[Patch] resolution: %@ -> %@", origRes ?: @"(nil)", mut[@"resolution"]]);
        bypassLog([NSString stringWithFormat:@"[Patch] idfa: %@ -> %@", origIdfa ?: @"(nil)", mut[@"idfa"]]);
        bypassLog([NSString stringWithFormat:@"[Patch] idfv: %@ -> %@", origIdfv ?: @"(nil)", mut[@"idfv"]]);
        bypassLog([NSString stringWithFormat:@"[Patch] openudid: %@ -> %@", origOpenUDID ?: @"(nil)", mut[@"openudid"]]);
        bypassLog([NSString stringWithFormat:@"[Patch] oaid: %@ -> %@", origOAID ?: @"(nil)", mut[@"oaid"]]);
        bypassLog([NSString stringWithFormat:@"[Patch] uuid: %@ -> %@", origUUID ?: @"(nil)", mut[@"uuid"]]);
        bypassLog([NSString stringWithFormat:@"[Patch] aid: %@ -> %@", origAID ?: @"(nil)", mut[@"aid"]]);
        bypassLog([NSString stringWithFormat:@"[Patch] device_id: %@ -> %@", origDeviceID ?: @"(nil)", mut[@"device_id"]]);
        bypassLog(@"[Patch] first patch logged, subsequent patches suppressed");
    }

    return mut;
}

// ========== TTNetworkManager Hook（v6.1.2双block + commonParams方法）==========
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

// ========== 探测并 Hook 字节系其他指纹 SDK ==========
static void hookByteDanceSDKs(void) {
    // BDAutoTrack / RangersAppLog / TTInstall 等常见类名
    NSArray *classNames = @[@"BDAutoTrack", @"RangersAppLog", @"TTInstall", @"TTTracker", @"VolcEngineTracker"];
    for (NSString *clsName in classNames) {
        Class cls = objc_getClass([clsName UTF8String]);
        if (!cls) continue;
        bypassLog([NSString stringWithFormat:@"[SDK] Found %@, attempting hook", clsName]);

        // Hook deviceID / installID / ssid 等常见方法
        Method m;
        if ((m = class_getInstanceMethod(cls, @selector(deviceID)))) {
            IMP orig = method_getImplementation(m);
            method_setImplementation(m, imp_implementationWithBlock(^NSString *(id self) {
                NSString *origVal = ((NSString *(*)(id, SEL))orig)(self, @selector(deviceID));
                if (!gLoggedFirstPatch) bypassLog([NSString stringWithFormat:@"[SDK-%@] deviceID: %@ -> %@", clsName, origVal, gFakeAID]);
                return gFakeAID;
            }));
        }
        if ((m = class_getInstanceMethod(cls, @selector(installID)))) {
            IMP orig = method_getImplementation(m);
            method_setImplementation(m, imp_implementationWithBlock(^NSString *(id self) {
                NSString *origVal = ((NSString *(*)(id, SEL))orig)(self, @selector(installID));
                if (!gLoggedFirstPatch) bypassLog([NSString stringWithFormat:@"[SDK-%@] installID: %@ -> %@", clsName, origVal, gFakeIDFV]);
                return gFakeIDFV;
            }));
        }
        if ((m = class_getInstanceMethod(cls, @selector(ssid)))) {
            IMP orig = method_getImplementation(m);
            method_setImplementation(m, imp_implementationWithBlock(^NSString *(id self) {
                return gFakeIDFA;
            }));
        }
    }
}

// ========== 1. UIDevice（完整版）==========
static NSUUID *my_idfv(id self, SEL _cmd) { return [[NSUUID alloc] initWithUUIDString:gFakeIDFV]; }
static NSUUID *my_uniqueVendor(id self, SEL _cmd) { return [[NSUUID alloc] initWithUUIDString:gFakeIDFV]; }
static NSString *my_sysVer(id self, SEL _cmd) { return gDeviceProfile[@"systemVersion"] ?: @"17.0"; }
static NSString *my_model(id self, SEL _cmd) { return gDeviceProfile[@"model"] ?: @"iPhone"; }
static NSString *my_name(id self, SEL _cmd) { return gDeviceProfile[@"name"] ?: @"iPhone"; }
static NSString *my_localizedModel(id self, SEL _cmd) { return gDeviceProfile[@"model"] ?: @"iPhone"; }

static void hookUIDevice(void) {
    Class uid = objc_getClass("UIDevice");
    if (!uid) return;
    Method m;
    if ((m = class_getInstanceMethod(uid, @selector(identifierForVendor)))) method_setImplementation(m, (IMP)my_idfv);
    if ((m = class_getInstanceMethod(uid, NSSelectorFromString(@"_uniqueVendorIdentifier")))) method_setImplementation(m, (IMP)my_uniqueVendor);
    if ((m = class_getInstanceMethod(uid, NSSelectorFromString(@"uniqueIdentifierForVendor")))) method_setImplementation(m, (IMP)my_uniqueVendor);
    if ((m = class_getInstanceMethod(uid, @selector(systemVersion)))) method_setImplementation(m, (IMP)my_sysVer);
    if ((m = class_getInstanceMethod(uid, @selector(model)))) method_setImplementation(m, (IMP)my_model);
    if ((m = class_getInstanceMethod(uid, @selector(name)))) method_setImplementation(m, (IMP)my_name);
    if ((m = class_getInstanceMethod(uid, @selector(localizedModel)))) method_setImplementation(m, (IMP)my_localizedModel);
}

// ========== 2. ASIdentifierManager ==========
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

// ========== 3. UIScreen / NSProcessInfo（完整版）==========
static CGRect my_screenBounds(id self, SEL _cmd) {
    return CGRectMake(0, 0, [gDeviceProfile[@"screenW"] floatValue], [gDeviceProfile[@"screenH"] floatValue]);
}
static CGFloat my_screenScale(id self, SEL _cmd) { return [gDeviceProfile[@"scale"] floatValue] ?: 3.0f; }
static CGRect my_nativeBounds(id self, SEL _cmd) {
    CGFloat s = [gDeviceProfile[@"scale"] floatValue] ?: 3.0f;
    CGFloat w = [gDeviceProfile[@"screenW"] floatValue] ?: 393.0f;
    CGFloat h = [gDeviceProfile[@"screenH"] floatValue] ?: 852.0f;
    return CGRectMake(0, 0, w * s, h * s);
}
static CGFloat my_nativeScale(id self, SEL _cmd) { return [gDeviceProfile[@"scale"] floatValue] ?: 3.0f; }
static unsigned long long my_physicalMemory(id self, SEL _cmd) {
    return ([gDeviceProfile[@"mem"] unsignedLongLongValue] ?: 6ULL) * 1024ULL * 1024ULL * 1024ULL;
}
static NSString *my_osVerString(id self, SEL _cmd) {
    return [NSString stringWithFormat:@"Version %@ (Build 21F79)", gDeviceProfile[@"systemVersion"] ?: @"17.5.1"];
}

static void hookScreenAndProcessInfo(void) {
    Class screen = objc_getClass("UIScreen");
    if (screen) {
        Method m;
        if ((m = class_getInstanceMethod(screen, @selector(bounds)))) method_setImplementation(m, (IMP)my_screenBounds);
        if ((m = class_getInstanceMethod(screen, @selector(scale)))) method_setImplementation(m, (IMP)my_screenScale);
        if ((m = class_getInstanceMethod(screen, @selector(nativeBounds)))) method_setImplementation(m, (IMP)my_nativeBounds);
        if ((m = class_getInstanceMethod(screen, @selector(nativeScale)))) method_setImplementation(m, (IMP)my_nativeScale);
    }
    Class pi = objc_getClass("NSProcessInfo");
    if (pi) {
        Method m;
        if ((m = class_getInstanceMethod(pi, @selector(physicalMemory)))) method_setImplementation(m, (IMP)my_physicalMemory);
        if ((m = class_getInstanceMethod(pi, @selector(operatingSystemVersionString)))) method_setImplementation(m, (IMP)my_osVerString);
    }
}

// ========== 4. uname ==========
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

// ========== 6. 域名拦截（精简版）==========
static BOOL isBlockedHost(NSString *host) {
    if (!host || host.length == 0) return NO;
    NSArray *keywords = @[@"security-lq", @"pitaya.bytedance", @"mon11-misc.fqnovel", @"tnc.bytedance", @"toblog"];
    for (NSString *kw in keywords) { if ([host containsString:kw]) return YES; }
    return NO;
}

// ========== 7. fishhook 系统函数（精简版）==========
static int (*orig_connect)(int, const struct sockaddr *, socklen_t);
static int my_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (addr && addr->sa_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in *)addr;
        NSString *ipStr = [NSString stringWithFormat:@"%s", inet_ntoa(sin->sin_addr)];
        if ([ipStr hasPrefix:@"172.31."]) { errno = ECONNREFUSED; return -1; }
    }
    return orig_connect(sockfd, addr, addrlen);
}

static ssize_t (*orig_sendto)(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
static ssize_t my_sendto(int sockfd, const void *buf, size_t len, int flags, const struct sockaddr *dest_addr, socklen_t addrlen) {
    return orig_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
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
    if (namelen >= 2) {
        if (name[0] == CTL_KERN && name[1] == KERN_PROC) {
            if (oldp && oldlenp) memset(oldp, 0, *oldlenp);
            return 0;
        }
        if (name[0] == CTL_HW && name[1] == HW_MACHINE) {
            if (oldp && oldlenp && gDeviceProfile) {
                NSString *machine = gDeviceProfile[@"machine"] ?: gDeviceProfile[@"model"];
                const char *cstr = [machine UTF8String];
                size_t len = strlen(cstr);
                if (*oldlenp > len) {
                    memcpy(oldp, cstr, len);
                    ((char *)oldp)[len] = '\0';
                    *oldlenp = len;
                } else if (*oldlenp > 0) {
                    size_t copyLen = *oldlenp - 1;
                    if (copyLen > len) copyLen = len;
                    memcpy(oldp, cstr, copyLen);
                    ((char *)oldp)[copyLen] = '\0';
                    *oldlenp = copyLen;
                }
            }
            return 0;
        }
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

// ========== 8. NSURLSession Hook（增加请求/响应日志）==========
static IMP orig_dtwr = NULL;
static NSURLSessionDataTask *my_dtwr(id self, SEL _cmd, NSURLRequest *request, void (^ch)(NSData *, NSURLResponse *, NSError *)) {
    NSURL *url = request.URL;
    NSString *host = url.host ?: @"";
    NSString *path = url.path ?: @"";

    // 记录所有请求（包括Body里的参数）
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

    // 包装 completionHandler 以记录响应
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

// ========== 9. Keychain Hook（防止读取旧真实 IDFV）==========
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus status = orig_SecItemCopyMatching(query, result);
    if (status == errSecSuccess && result && *result) {
        id obj = (__bridge id)*result;
        if ([obj isKindOfClass:[NSData class]]) {
            NSString *str = [[NSString alloc] initWithData:(NSData *)obj encoding:NSUTF8StringEncoding];
            if (str && (str.length == 36 || str.length == 40)) {
                bypassLog([NSString stringWithFormat:@"[Keychain] Read key, value-like UUID: %@", str]);
            }
        }
    }
    return status;
}

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus my_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    id obj = (__bridge id)attributes;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSData *vData = ((NSDictionary *)obj)[(__bridge NSString *)kSecValueData];
        if (vData) {
            NSString *str = [[NSString alloc] initWithData:vData encoding:NSUTF8StringEncoding];
            if (str && str.length > 20) {
                bypassLog([NSString stringWithFormat:@"[Keychain] Add key, value: %@", str]);
            }
        }
    }
    return orig_SecItemAdd(attributes, result);
}

// ========== 10. NSBundle Hook（隐藏容器修改的 Bundle ID / 路径）==========
static NSString *gOriginalBundleID = nil;
static NSString *gOriginalBundlePath = nil;

static NSString *my_bundleIdentifier(id self, SEL _cmd) {
    return gOriginalBundleID ?: @"com.dragon.read";
}
static NSString *my_bundlePath(id self, SEL _cmd) {
    return gOriginalBundlePath ?: @"/var/containers/Bundle/Application/XXXX/番茄畅听.app";
}
static NSDictionary *my_infoDictionary(id self, SEL _cmd) {
    NSDictionary *orig = ((NSDictionary *(*)(id, SEL))objc_msgSend)(self, @selector(infoDictionary));
    NSMutableDictionary *mut = [orig mutableCopy];
    if (gOriginalBundleID) mut[@"CFBundleIdentifier"] = gOriginalBundleID;
    return mut;
}

static void hookNSBundle(void) {
    NSBundle *mainBundle = [NSBundle mainBundle];
    gOriginalBundleID = mainBundle.bundleIdentifier;
    gOriginalBundlePath = mainBundle.bundlePath;

    // 如果 Bundle ID 已经被容器篡改（包含 LiveContainer 等），则伪装回常见值
    if (gOriginalBundleID && ([gOriginalBundleID containsString:@"LiveContainer"] || [gOriginalBundleID containsString:@"esign"] || [gOriginalBundleID containsString:@"troll"])) {
        bypassLog([NSString stringWithFormat:@"[Bundle] Container detected, original ID: %@", gOriginalBundleID]);
        gOriginalBundleID = @"com.dragon.read"; // 番茄畅听原版 Bundle ID，红果/番茄小说请自行改
    }

    Class bundleCls = objc_getClass("NSBundle");
    Method m;
    if ((m = class_getInstanceMethod(bundleCls, @selector(bundleIdentifier)))) method_setImplementation(m, (IMP)my_bundleIdentifier);
    if ((m = class_getInstanceMethod(bundleCls, @selector(bundlePath)))) method_setImplementation(m, (IMP)my_bundlePath);
    if ((m = class_getInstanceMethod(bundleCls, @selector(infoDictionary)))) method_setImplementation(m, (IMP)my_infoDictionary);
    bypassLog(@"[Bundle] NSBundle hooked");
}

// ========== 11. 初始化 ==========
__attribute__((constructor(101))) static void constructor(void) {
    bypassLog(@"=== AliSecBypass v6.1.12 init ===");

    initDeviceProfile();
    hookUIDevice();
    hookASIdentifierManager();
    hookScreenAndProcessInfo();
    hookTTNetworkCommonParams();
    hookByteDanceSDKs();
    hookNSBundle();

    struct rebinding rebinds[] = {
        {"connect", (void *)my_connect, (void **)&orig_connect},
        {"sendto", (void *)my_sendto, (void **)&orig_sendto},
        {"ptrace", (void *)my_ptrace, (void **)&orig_ptrace},
        {"sysctl", (void *)my_sysctl, (void **)&orig_sysctl},
        {"getaddrinfo", (void *)my_getaddrinfo, (void **)&orig_getaddrinfo},
        {"uname", (void *)my_uname, (void **)&orig_uname},
        {"dlopen", (void *)my_dlopen, (void **)&orig_dlopen},
        {"dlsym", (void *)my_dlsym, (void **)&orig_dlsym},
        {"_dyld_get_image_name", (void *)my_dyld_get_image_name, (void **)&orig_dyld_get_image_name},
        {"SecItemCopyMatching", (void *)my_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching},
        {"SecItemAdd", (void *)my_SecItemAdd, (void **)&orig_SecItemAdd}
    };
    rebind_symbols(rebinds, 11);

    Class cls = objc_getClass("NSURLSession");
    if (cls) {
        Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
        if (m1) { orig_dtwr = method_getImplementation(m1); method_setImplementation(m1, (IMP)my_dtwr); }
    }

    bypassLog(@"=== AliSecBypass v6.1.12 init complete ===");
}
