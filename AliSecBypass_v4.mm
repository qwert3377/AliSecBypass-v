// AliSecBypass_v4.mm
// 番茄畅听/番茄小说 通用脱壳检测绕过插件 v4
// 基于头文件精确类名 (字节+百度+阿里) + Dobby inline hook C函数
// 纯库文件，无 Logos，TrollStore / 非越狱注入
// 日志: App Documents/AliBypass.log

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include "dobby.h"
#include <sys/sysctl.h>
#include <unistd.h>

// iOS SDK 没有 sys/ptrace.h，手动定义
#define PT_DENY_ATTACH 0
#define P_TRACED 0x00000800

typedef void *caddr_t;

#pragma mark - Logger

static NSString *bypassLogPath() {
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        path = [paths.firstObject stringByAppendingPathComponent:@"AliBypass.log"];
    });
    return path;
}

static void BYPASS_LOG(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [[NSDate date] descriptionWithLocale:nil], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:bypassLogPath()];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [line writeToFile:bypassLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

#pragma mark - Dobby C Function Hook

static int (*orig_ptrace)(int request, pid_t pid, caddr_t addr, int data);
static int my_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == PT_DENY_ATTACH) {
        BYPASS_LOG(@"[DOBBY] ptrace(PT_DENY_ATTACH) blocked");
        return 0;
    }
    return orig_ptrace(request, pid, addr, data);
}

static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static int my_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (namelen >= 4 && name[0] == CTL_KERN && name[1] == KERN_PROC && name[2] == KERN_PROC_PID) {
        if (oldp) {
            struct kinfo_proc *info = (struct kinfo_proc *)oldp;
            if (info->kp_proc.p_flag & P_TRACED) {
                info->kp_proc.p_flag &= ~P_TRACED;
                BYPASS_LOG(@"[DOBBY] sysctl P_TRACED cleared");
            }
        }
    }
    return ret;
}

static int (*orig_access)(const char *path, int mode);
static int my_access(const char *path, int mode) {
    if (path) {
        NSString *p = [NSString stringWithUTF8String:path];
        if ([p containsString:@"Cydia"] || [p containsString:@"cydia"] ||
            [p containsString:@"MobileSubstrate"] || [p containsString:@"substrate"] ||
            [p containsString:@"apt"] || [p containsString:@"dpkg"] ||
            [p containsString:@"bin/bash"] || [p containsString:@"usr/sbin/sshd"] ||
            [p containsString:@"etc/apt"] || [p containsString:@"Library/MobileSubstrate"] ||
            [p containsString:@"var/lib/dpkg"] || [p containsString:@"var/cache/apt"] ||
            [p containsString:@"var/tmp/cydia"] || [p containsString:@"usr/bin/ssh"] ||
            [p containsString:@"usr/libexec/ssh"] || [p containsString:@"Sileo"] ||
            [p containsString:@"Zebra"] || [p containsString:@"TrollStore"] ||
            [p containsString:@"trollstore"]) {
            BYPASS_LOG(@"[DOBBY] access blocked: %s", path);
            return -1;
        }
    }
    return orig_access(path, mode);
}

#pragma mark - Hook Helpers

static inline void safeHookNoOrig(Class cls, SEL sel, IMP fake) {
    if (!cls || !sel || !fake) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) m = class_getClassMethod(cls, sel);
    if (!m) return;
    method_setImplementation(m, fake);
}

#pragma mark - Universal Fakes

static id   fake_ret_nil(id self, SEL _cmd) { return nil; }
static id   fake_ret_empty(id self, SEL _cmd) { return @""; }
static id   fake_ret_safe(id self, SEL _cmd) { return @"safe"; }
static id   fake_ret_array(id self, SEL _cmd) { return @[]; }
static id   fake_ret_dict(id self, SEL _cmd) { return @{}; }
static id   fake_ret_num0(id self, SEL _cmd) { return @0; }
static BOOL fake_ret_NO(id self, SEL _cmd) { return NO; }
static BOOL fake_ret_YES(id self, SEL _cmd) { return YES; }
static void fake_ret_void(id self, SEL _cmd) {}
static void fake_ret_void_id(id self, SEL _cmd, id arg) {}
static void fake_ret_void_id_id(id self, SEL _cmd, id a, id b) {}
static void fake_ret_void_id_id_id(id self, SEL _cmd, id a, id b, id c) {}
static long long fake_ret_0ll(id self, SEL _cmd) { return 0; }
static int fake_ret_0i(id self, SEL _cmd) { return 0; }
static unsigned long long fake_ret_0ull(id self, SEL _cmd) { return 0; }
static NSUInteger fake_ret_0ul(id self, SEL _cmd) { return 0; }

#pragma mark - Module A: 阿里 SDK (头文件精确类名)

static void hookAliSDK() {
    const char *safeUtils[] = {
        "AliSecXSafeUtilsMXXTIY", "AliSecXSafeUtilsZZZX",
        "AliSecXSafeUtils", nil
    };
    for (int i = 0; safeUtils[i]; i++) {
        Class cls = objc_getClass(safeUtils[i]);
        if (!cls) continue;
        BYPASS_LOG(@"[ALI] found %s", safeUtils[i]);
        safeHookNoOrig(cls, @selector(descriptor), (IMP)fake_ret_safe);
        safeHookNoOrig(cls, @selector(secStatus), (IMP)fake_ret_safe);
        safeHookNoOrig(cls, @selector(safeDescriptor), (IMP)fake_ret_safe);
        safeHookNoOrig(cls, @selector(securityStatus), (IMP)fake_ret_safe);
        safeHookNoOrig(cls, @selector(checkStatus), (IMP)fake_ret_safe);
        safeHookNoOrig(cls, @selector(isJailbreak), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isJailbroken), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isDebug), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isDebuggerAttached), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isProxy), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isEmulator), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isSimulator), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(startSafeGuard), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(initSafeGuard), (IMP)fake_ret_void);
    }

    const char *reachClasses[] = {
        "AliSecXReachabilityMXXTIY", "AliSecXReachabilityZZZX",
        "AliSecXReachability", nil
    };
    for (int i = 0; reachClasses[i]; i++) {
        Class cls = objc_getClass(reachClasses[i]);
        if (!cls) continue;
        safeHookNoOrig(cls, @selector(currentReachabilityStatus), (IMP)fake_ret_0ll);
        safeHookNoOrig(cls, @selector(startNotifier), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(stopNotifier), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(localWiFiStatusForFlags:), (IMP)fake_ret_0ll);
        safeHookNoOrig(cls, @selector(networkStatusForFlags:), (IMP)fake_ret_0ll);
    }

    const char *devInfoClasses[] = {
        "AliSecXDeviceInfoMXXTIY", "AliSecXDeviceInfoZZZX",
        "AliSecXDeviceInfo", "AliDeviceInfo",
        "AliSecXPhoneInfoHolderMXXTIY", "AliSecXPhoneInfoHolderZZZX",
        "AliSecXPhoneInfoHolder", nil
    };
    for (int i = 0; devInfoClasses[i]; i++) {
        Class cls = objc_getClass(devInfoClasses[i]);
        if (!cls) continue;
        safeHookNoOrig(cls, @selector(getAid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(aid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(getUtdid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(utdid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(getAdiu), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(adiu), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(deviceId), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(uniqueDeviceIdentifier), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(getUUID), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(uuid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(getDeviceID), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(getMacAddress), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(macAddress), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(getIPAddress), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(ipAddress), (IMP)fake_ret_empty);
    }

    const char *keychainClasses[] = {
        "AliSecXSSKeychainQuery", "AliSecXSSKeychainQueryMXXT",
        "AliSecXSSKeychain", "AliKeychain", nil
    };
    for (int i = 0; keychainClasses[i]; i++) {
        Class cls = objc_getClass(keychainClasses[i]);
        if (!cls) continue;
        safeHookNoOrig(cls, @selector(save:), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(deleteItem:), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(fetchAll:), (IMP)fake_ret_array);
        safeHookNoOrig(cls, @selector(fetch:), (IMP)fake_ret_NO);
    }

    const char *storageClasses[] = {
        "AliSecXLocalStorage", "AliSecXLocalStorageMXXT",
        "AliSecXLocalStorageUtils", "AliLocalStorage", nil
    };
    for (int i = 0; storageClasses[i]; i++) {
        Class cls = objc_getClass(storageClasses[i]);
        if (!cls) continue;
        safeHookNoOrig(cls, @selector(setObject:forKey:), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(objectForKey:), (IMP)fake_ret_nil);
        safeHookNoOrig(cls, @selector(removeObjectForKey:), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(save:), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(load:), (IMP)fake_ret_nil);
    }

    const char *fileOpClasses[] = {
        "AliSecXFileOp", "AliSecXFileOpMXXT", "AliFileOp", nil
    };
    for (int i = 0; fileOpClasses[i]; i++) {
        Class cls = objc_getClass(fileOpClasses[i]);
        if (!cls) continue;
        safeHookNoOrig(cls, @selector(fileExistsAtPath:), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(readFile:), (IMP)fake_ret_nil);
        safeHookNoOrig(cls, @selector(writeFile:data:), (IMP)fake_ret_YES);
    }

    const char *monitorClasses[] = {
        "AMapMonitorSingal", "AMapMonitorNSException",
        "AMapMonitorMachException", "AMapCrashReporter",
        "AMapExceptionHandler", nil
    };
    for (int i = 0; monitorClasses[i]; i++) {
        Class cls = objc_getClass(monitorClasses[i]);
        if (!cls) continue;
        safeHookNoOrig(cls, @selector(startMonitor), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(registerMonitor:), (IMP)fake_ret_void_id);
        safeHookNoOrig(cls, @selector(setupMonitor), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(start), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(installNSExceptionHandle), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(uninstallNSExceptionHandle), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(installSingalHandle), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(uninstallSingalHandle), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(installMonitor), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(uninstallMonitor), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(startCrashReporter), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(enableCrashReporter), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(registerExceptionHandler), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(setupExceptionHandler), (IMP)fake_ret_void);
    }

    Class crashMgr = objc_getClass("AMapCrashManager");
    if (crashMgr) {
        safeHookNoOrig(crashMgr, @selector(installMonitor), (IMP)fake_ret_void);
        safeHookNoOrig(crashMgr, @selector(uninstallMonitor), (IMP)fake_ret_void);
        safeHookNoOrig(crashMgr, @selector(registerWithComponent:withConfig:), (IMP)fake_ret_void_id_id);
        safeHookNoOrig(crashMgr, @selector(handleException:crashIndex:backTrace:), (IMP)fake_ret_void_id_id_id);
        safeHookNoOrig(crashMgr, @selector(checkConfigs), (IMP)fake_ret_void);
    }

    Class crashCfg = objc_getClass("AMapCrashConfig");
    if (crashCfg) {
        safeHookNoOrig(crashCfg, @selector(isFilter), (IMP)fake_ret_YES);
    }

    Class analytics = objc_getClass("AMapAnalyticsManager");
    if (analytics) {
        BYPASS_LOG(@"[ALI] found AMapAnalyticsManager");
        safeHookNoOrig(analytics, @selector(sendLog:), (IMP)fake_ret_void_id);
        safeHookNoOrig(analytics, @selector(sendEvent:), (IMP)fake_ret_void_id);
        safeHookNoOrig(analytics, @selector(sendReport:), (IMP)fake_ret_void_id);
        safeHookNoOrig(analytics, @selector(trackEvent:), (IMP)fake_ret_void_id);
        safeHookNoOrig(analytics, @selector(uploadLog), (IMP)fake_ret_void);
        safeHookNoOrig(analytics, @selector(flush), (IMP)fake_ret_void);
        safeHookNoOrig(analytics, @selector(logEvent:params:component:), (IMP)fake_ret_void_id_id_id);
        safeHookNoOrig(analytics, @selector(logError:errorInfo:component:), (IMP)fake_ret_void_id_id_id);
        safeHookNoOrig(analytics, @selector(logURLError:forURL:component:), (IMP)fake_ret_void_id_id_id);
        safeHookNoOrig(analytics, @selector(logRESTError:forURL:component:), (IMP)fake_ret_void_id_id_id);
        safeHookNoOrig(analytics, @selector(logCrash:crashInfo:component:), (IMP)fake_ret_void_id_id_id);
        safeHookNoOrig(analytics, @selector(uploadLogWithType:), (IMP)fake_ret_void_id);
        safeHookNoOrig(analytics, @selector(uploadLogWithType:component:complete:), (IMP)fake_ret_void_id_id_id);
    }

    Class netFlow = objc_getClass("AMapNetFlowManager");
    if (netFlow) {
        BYPASS_LOG(@"[ALI] found AMapNetFlowManager");
        safeHookNoOrig(netFlow, @selector(isBlock:), (IMP)fake_ret_NO);
        safeHookNoOrig(netFlow, @selector(isBlocked), (IMP)fake_ret_NO);
        safeHookNoOrig(netFlow, @selector(checkBlock), (IMP)fake_ret_NO);
        safeHookNoOrig(netFlow, @selector(checkNetworkBlock), (IMP)fake_ret_NO);
        safeHookNoOrig(netFlow, @selector(checkResponse:withRequest:responseData:), (IMP)fake_ret_void_id_id_id);
    }

    Class netFlowBlock = objc_getClass("AMapNetFlowBlockStrategy");
    if (netFlowBlock) {
        safeHookNoOrig(netFlowBlock, @selector(isHitStrateg), (IMP)fake_ret_NO);
        safeHookNoOrig(netFlowBlock, @selector(isVaild), (IMP)fake_ret_NO);
    }

    Class errCodeStrategy = objc_getClass("AMapErrorCodeStrategy");
    if (errCodeStrategy) {
        safeHookNoOrig(errCodeStrategy, @selector(isHitStrateg), (IMP)fake_ret_NO);
        safeHookNoOrig(errCodeStrategy, @selector(isVaild), (IMP)fake_ret_NO);
    }

    Class adiuMgr = objc_getClass("AMapADIUManager");
    if (adiuMgr) {
        BYPASS_LOG(@"[ALI] found AMapADIUManager");
        safeHookNoOrig(adiuMgr, @selector(ADIU), (IMP)fake_ret_empty);
        safeHookNoOrig(adiuMgr, @selector(saveWithADIU:), (IMP)fake_ret_void_id);
        safeHookNoOrig(adiuMgr, @selector(processWithResponseData:), (IMP)fake_ret_void_id);
        safeHookNoOrig(adiuMgr, @selector(requestADIU), (IMP)fake_ret_void);
    }

    Class identityMgr = objc_getClass("AliyunIdentityManager");
    if (identityMgr) {
        BYPASS_LOG(@"[ALI] found AliyunIdentityManager");
        safeHookNoOrig(identityMgr, @selector(verifyWith:extParams:onCompletion:), (IMP)fake_ret_void_id_id_id);
        safeHookNoOrig(identityMgr, @selector(verifyTechWith:extParams:onCompletion:), (IMP)fake_ret_void_id_id_id);
        safeHookNoOrig(identityMgr, @selector(sendlog:withSeedID:), (IMP)fake_ret_void_id_id);
        safeHookNoOrig(identityMgr, @selector(getMetaInfo), (IMP)fake_ret_empty);
        safeHookNoOrig(identityMgr, @selector(quit:onCompletion:), (IMP)fake_ret_void_id);
        safeHookNoOrig(identityMgr, @selector(modelFilePathContent), (IMP)fake_ret_empty);
        safeHookNoOrig(identityMgr, @selector(uploadLogChooice), (IMP)fake_ret_NO);
        safeHookNoOrig(identityMgr, @selector(getlogArray), (IMP)fake_ret_array);
    }

    Class faceAuth = objc_getClass("AliyunFaceAuthRPC");
    if (faceAuth) {
        safeHookNoOrig(faceAuth, @selector(zimInit:completionBlock:), (IMP)fake_ret_void_id_id);
        safeHookNoOrig(faceAuth, @selector(zimValidate:completionBlock:), (IMP)fake_ret_void_id_id);
        safeHookNoOrig(faceAuth, @selector(zimNFCValidate:completionBlock:), (IMP)fake_ret_void_id_id);
        safeHookNoOrig(faceAuth, @selector(zimOCRIdentify:completionBlock:), (IMP)fake_ret_void_id_id);
        safeHookNoOrig(faceAuth, @selector(uploadFileWthParams:completionBlock:), (IMP)fake_ret_void_id_id);
        safeHookNoOrig(faceAuth, @selector(zimFileUpload:completionBlock:), (IMP)fake_ret_void_id_id);
    }

    Class encryptor = objc_getClass("AliyunEncryptorforTech");
    if (encryptor) {
        safeHookNoOrig(encryptor, @selector(encrypt:), (IMP)fake_ret_empty);
        safeHookNoOrig(encryptor, @selector(encryptData:), (IMP)fake_ret_nil);
    }

    Class stats = objc_getClass("AMapStatistics");
    if (stats) {
        BYPASS_LOG(@"[ALI] found AMapStatistics");
        SEL idSelectors[] = {
            @selector(diu), @selector(adiu), @selector(imac), @selector(mac),
            @selector(tid), @selector(sim), @selector(tel), @selector(pkg),
            @selector(manufacture), @selector(model), @selector(device),
            @selector(ant), @selector(nt), @selector(mnc), @selector(np),
            @selector(lon), @selector(lat), @selector(wifis),
            @selector(wifi), @selector(wifiname), @selector(bts),
            @selector(bttype), @selector(gps), @selector(resolution),
            @selector(glrender), @selector(ram), @selector(storage),
            @selector(arch), @selector(platform), @selector(appname),
            @selector(appversion), @selector(bundleid), @selector(sysversion),
            (SEL)0
        };
        for (int i = 0; idSelectors[i] != (SEL)0; i++) {
            safeHookNoOrig(stats, idSelectors[i], (IMP)fake_ret_empty);
        }
        safeHookNoOrig(stats, @selector(keyAuthorized), (IMP)fake_ret_YES);
    }

    Class sysInfo = objc_getClass("AMapSystemInfo");
    if (sysInfo) {
        safeHookNoOrig(sysInfo, @selector(extractMemoryTotalSize), (IMP)fake_ret_empty);
        safeHookNoOrig(sysInfo, @selector(extractMemoryUsedSize), (IMP)fake_ret_empty);
        safeHookNoOrig(sysInfo, @selector(extractMemoryFreeSize), (IMP)fake_ret_empty);
        safeHookNoOrig(sysInfo, @selector(extractDeviceVersion), (IMP)fake_ret_empty);
        safeHookNoOrig(sysInfo, @selector(extractAppUUID), (IMP)fake_ret_empty);
        safeHookNoOrig(sysInfo, @selector(extractCPUArch), (IMP)fake_ret_empty);
        safeHookNoOrig(sysInfo, @selector(extractDeviceAppHash), (IMP)fake_ret_empty);
        safeHookNoOrig(sysInfo, @selector(sysctlInt32ForName:), (IMP)fake_ret_0i);
        safeHookNoOrig(sysInfo, @selector(sysctlUint64ForName:), (IMP)fake_ret_0ull);
    }

    Class macFinder = objc_getClass("AMapMacAddressFinder");
    if (macFinder) {
        safeHookNoOrig(macFinder, @selector(AMF_macAddress), (IMP)fake_ret_empty);
        safeHookNoOrig(macFinder, @selector(AMF_IPAddress), (IMP)fake_ret_empty);
        safeHookNoOrig(macFinder, @selector(_getMacAddressWithIP:), (IMP)fake_ret_empty);
    }

    Class services = objc_getClass("AMapServices");
    if (services) {
        safeHookNoOrig(services, @selector(validatingAPIKey), (IMP)fake_ret_void);
        safeHookNoOrig(services, @selector(sendInitInfoWithComponent:), (IMP)fake_ret_void_id);
        safeHookNoOrig(services, @selector(registerWithComponent:), (IMP)fake_ret_void_id);
        safeHookNoOrig(services, @selector(registerWithComponent:authKeys:params:handler:), (IMP)fake_ret_void);
        safeHookNoOrig(services, @selector(sendStatisticsWithComponent:handler:), (IMP)fake_ret_void);
        safeHookNoOrig(services, @selector(showKeyAuthorizationInfo:responseHeader:forComponent:), (IMP)fake_ret_void);
        safeHookNoOrig(services, @selector(setApiKey:), (IMP)fake_ret_void_id);
        safeHookNoOrig(services, @selector(setCrashReportEnabled:), (IMP)fake_ret_void);
        safeHookNoOrig(services, @selector(setUpAnalytics), (IMP)fake_ret_void);
        safeHookNoOrig(services, @selector(initAnalytics), (IMP)fake_ret_void);
        safeHookNoOrig(services, @selector(uploadAnalyticsInfo), (IMP)fake_ret_void);
    }

    const char *reformerClasses[] = {
        "AMapAuthRequestReformer", "AMapAOSRequestReformer",
        "AMapConcreteRequestReformer", "AMapRESTRequestReformer",
        "AMapPostDataRequestReformer", "AMapDownloadRequestReformer",
        "AMapADIURequestReformer", nil
    };
    for (int i = 0; reformerClasses[i]; i++) {
        Class cls = objc_getClass(reformerClasses[i]);
        if (!cls) continue;
        safeHookNoOrig(cls, @selector(reformParameters:result:), (IMP)fake_ret_void_id_id);
        safeHookNoOrig(cls, @selector(signvalue), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(signvalueWithData:), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(parameters), (IMP)fake_ret_nil);
        safeHookNoOrig(cls, @selector(postData), (IMP)fake_ret_nil);
        safeHookNoOrig(cls, @selector(baseURL), (IMP)fake_ret_nil);
        safeHookNoOrig(cls, @selector(v6BaseURL), (IMP)fake_ret_nil);
    }

    Class rsa = objc_getClass("AMapFoundationRSA");
    if (rsa) {
        safeHookNoOrig(rsa, @selector(encryptWithData:), (IMP)fake_ret_nil);
        safeHookNoOrig(rsa, @selector(encryptWithString:), (IMP)fake_ret_empty);
        safeHookNoOrig(rsa, @selector(encryptToString:), (IMP)fake_ret_empty);
        safeHookNoOrig(rsa, @selector(verifyBytesSHA256withRSA:signature:), (IMP)fake_ret_YES);
    }

    Class aes = objc_getClass("AMapFoundationAES");
    if (aes) {
        safeHookNoOrig(aes, @selector(encryptData:key:), (IMP)fake_ret_nil);
        safeHookNoOrig(aes, @selector(decryptData:key:), (IMP)fake_ret_nil);
    }
}

#pragma mark - Module B: 百度 SDK

static void hookBaiduSDK() {
    const char *baiduSecurityClasses[] = {
        "BaiduSecurityManager", "BDProtector", "BDSecurity", "BaiduSafe",
        "BaiduAntiCheat", "BDASecurityManager", "BDASafeUtils",
        "BDAEnvironment", "BDAEnvChecker", "BDADeviceHelper",
        "BDASecurity", "BDDeviceInfo", "BDDeviceManager",
        "BDPanFileDownloadEngine", "BDPanSecurityManager",
        "BaiduSecuritySDK", "BaiduSecurityUtils", nil
    };
    for (int i = 0; baiduSecurityClasses[i]; i++) {
        Class cls = objc_getClass(baiduSecurityClasses[i]);
        if (!cls) continue;
        BYPASS_LOG(@"[BD] found %s", baiduSecurityClasses[i]);
        safeHookNoOrig(cls, @selector(isJailbreak), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isJailbroken), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isDebug), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isDebuggerAttached), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isProxy), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isVPN), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isEmulator), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isSimulator), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isVirtualDevice), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(checkSignature), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(verifySignature), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(checkEnvironment), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(verifyEnvironment), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(checkIntegrity), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(checkStatus), (IMP)fake_ret_safe);
        safeHookNoOrig(cls, @selector(securityStatus), (IMP)fake_ret_safe);
        safeHookNoOrig(cls, @selector(getDeviceID), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(deviceId), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(getUUID), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(uuid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(getUtdid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(utdid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(getAid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(aid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(startSafeGuard), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(initSafeGuard), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(startMonitor), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(setupMonitor), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(sendLog:), (IMP)fake_ret_void_id);
        safeHookNoOrig(cls, @selector(sendReport:), (IMP)fake_ret_void_id);
        safeHookNoOrig(cls, @selector(uploadLog), (IMP)fake_ret_void);
    }

    Class bdKeychain = objc_getClass("BDKeychainManager");
    if (bdKeychain) {
        safeHookNoOrig(bdKeychain, @selector(setObject:forKey:), (IMP)fake_ret_YES);
        safeHookNoOrig(bdKeychain, @selector(objectForKey:), (IMP)fake_ret_nil);
        safeHookNoOrig(bdKeychain, @selector(removeObjectForKey:), (IMP)fake_ret_YES);
    }

    Class bdStorage = objc_getClass("BDLocalStorage");
    if (bdStorage) {
        safeHookNoOrig(bdStorage, @selector(setObject:forKey:), (IMP)fake_ret_YES);
        safeHookNoOrig(bdStorage, @selector(objectForKey:), (IMP)fake_ret_nil);
        safeHookNoOrig(bdStorage, @selector(removeObjectForKey:), (IMP)fake_ret_YES);
    }

    Class bdFileOp = objc_getClass("BDFileOp");
    if (bdFileOp) {
        safeHookNoOrig(bdFileOp, @selector(fileExistsAtPath:), (IMP)fake_ret_NO);
        safeHookNoOrig(bdFileOp, @selector(readFile:), (IMP)fake_ret_nil);
        safeHookNoOrig(bdFileOp, @selector(writeFile:data:), (IMP)fake_ret_YES);
    }
}

#pragma mark - Module C: 字节 SDK (头文件精确类名)

static void hookByteDanceSDK() {
    const char *ttMonitorClasses[] = {
        "AnnieXMonitorModule",
        "AnnieXMonitorAbilityDelegate",
        "AnnieTraceEventImpl",
        "AnnieLiveBizMonitor",
        "AnnieLiveReportAggregateALogMethodImpl",
        "AnnieSendLogV3Impl",
        nil
    };
    for (int i = 0; ttMonitorClasses[i]; i++) {
        Class cls = objc_getClass(ttMonitorClasses[i]);
        if (!cls) continue;
        BYPASS_LOG(@"[TT] found %s", ttMonitorClasses[i]);
        safeHookNoOrig(cls, @selector(sendLog:), (IMP)fake_ret_void_id);
        safeHookNoOrig(cls, @selector(sendEvent:), (IMP)fake_ret_void_id);
        safeHookNoOrig(cls, @selector(sendReport:), (IMP)fake_ret_void_id);
        safeHookNoOrig(cls, @selector(trackEvent:), (IMP)fake_ret_void_id);
        safeHookNoOrig(cls, @selector(upload), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(flush), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(perfMetric:), (IMP)fake_ret_void_id);
        safeHookNoOrig(cls, @selector(result:), (IMP)fake_ret_void_id);
        safeHookNoOrig(cls, @selector(traceBeginSectionWithName:debugInfo:), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(traceEndSectionWithName:), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(traceInstantWithName:), (IMP)fake_ret_void);
    }

    Class geckoMgr = objc_getClass("BDADSDKGeckoManager");
    if (geckoMgr) {
        safeHookNoOrig(geckoMgr, @selector(registerAndPreloadCommerceGecko), (IMP)fake_ret_void);
        safeHookNoOrig(geckoMgr, @selector(gurdKitDidSetup), (IMP)fake_ret_void);
        safeHookNoOrig(geckoMgr, @selector(updateGurdPollWith:), (IMP)fake_ret_void_id);
    }

    Class bdAdStrategy = objc_getClass("BDAResourceKit_iOSAdStrategyTrackUtil");
    if (bdAdStrategy) {
        safeHookNoOrig(bdAdStrategy, @selector(track:), (IMP)fake_ret_void_id);
    }

    Class heimdallr = objc_getClass("SalamanderBDFoundationSLHeimdallr");
    if (heimdallr) {
        safeHookNoOrig(heimdallr, @selector(start), (IMP)fake_ret_void);
        safeHookNoOrig(heimdallr, @selector(stop), (IMP)fake_ret_void);
    }

    const char *ttSecurityClasses[] = {
        "TTSecurity", "TTAppSecurity", "TTDeviceHelper",
        "TTEnvChecker", "TTAntiSpam", "TTSecurityManager",
        "TTSecurityUtils", "TTDeviceInfo", "TTDeviceManager",
        "TTJailbreakDetector", "TTDebugDetector", "TTProxyDetector",
        "TTEnvironment", "TTEnvManager", "TTAppInfo", nil
    };
    for (int i = 0; ttSecurityClasses[i]; i++) {
        Class cls = objc_getClass(ttSecurityClasses[i]);
        if (!cls) continue;
        BYPASS_LOG(@"[TT] found %s", ttSecurityClasses[i]);
        safeHookNoOrig(cls, @selector(isJailbreak), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isJailbroken), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isDebug), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isDebuggerAttached), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isProxy), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isVPN), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isEmulator), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isSimulator), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(isVirtualDevice), (IMP)fake_ret_NO);
        safeHookNoOrig(cls, @selector(checkEnvironment), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(verifyEnvironment), (IMP)fake_ret_YES);
        safeHookNoOrig(cls, @selector(checkStatus), (IMP)fake_ret_safe);
        safeHookNoOrig(cls, @selector(securityStatus), (IMP)fake_ret_safe);
        safeHookNoOrig(cls, @selector(getDeviceID), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(deviceId), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(getUUID), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(uuid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(getUtdid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(utdid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(getAid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(aid), (IMP)fake_ret_empty);
        safeHookNoOrig(cls, @selector(startSafeGuard), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(initSafeGuard), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(startMonitor), (IMP)fake_ret_void);
        safeHookNoOrig(cls, @selector(setupMonitor), (IMP)fake_ret_void);
    }

    Class ttKeychain = objc_getClass("TTKeychainManager");
    if (ttKeychain) {
        safeHookNoOrig(ttKeychain, @selector(setObject:forKey:), (IMP)fake_ret_YES);
        safeHookNoOrig(ttKeychain, @selector(objectForKey:), (IMP)fake_ret_nil);
        safeHookNoOrig(ttKeychain, @selector(removeObjectForKey:), (IMP)fake_ret_YES);
    }

    Class ttStorage = objc_getClass("TTLocalStorage");
    if (ttStorage) {
        safeHookNoOrig(ttStorage, @selector(setObject:forKey:), (IMP)fake_ret_YES);
        safeHookNoOrig(ttStorage, @selector(objectForKey:), (IMP)fake_ret_nil);
        safeHookNoOrig(ttStorage, @selector(removeObjectForKey:), (IMP)fake_ret_YES);
    }

    Class ttFileOp = objc_getClass("TTFileOp");
    if (ttFileOp) {
        safeHookNoOrig(ttFileOp, @selector(fileExistsAtPath:), (IMP)fake_ret_NO);
        safeHookNoOrig(ttFileOp, @selector(readFile:), (IMP)fake_ret_nil);
        safeHookNoOrig(ttFileOp, @selector(writeFile:data:), (IMP)fake_ret_YES);
    }
}

#pragma mark - Module D: 系统类检测绕过

static void hookSystemClasses() {
    Class fileMgr = objc_getClass("NSFileManager");
    if (fileMgr) {
        Method m = class_getInstanceMethod(fileMgr, @selector(fileExistsAtPath:));
        if (m) {
            IMP orig = method_getImplementation(m);
            IMP fake = imp_implementationWithBlock(^BOOL(id self, NSString *path) {
                if ([path containsString:@"Cydia"] ||
                    [path containsString:@"cydia"] ||
                    [path containsString:@"MobileSubstrate"] ||
                    [path containsString:@"substrate"] ||
                    [path containsString:@"apt"] ||
                    [path containsString:@"dpkg"] ||
                    [path containsString:@"bin/bash"] ||
                    [path containsString:@"usr/sbin/sshd"] ||
                    [path containsString:@"etc/apt"] ||
                    [path containsString:@"Library/MobileSubstrate"] ||
                    [path containsString:@"var/lib/dpkg"] ||
                    [path containsString:@"var/cache/apt"] ||
                    [path containsString:@"var/tmp/cydia"] ||
                    [path containsString:@"usr/bin/ssh"] ||
                    [path containsString:@"usr/libexec/ssh"] ||
                    [path containsString:@"Sileo"] ||
                    [path containsString:@"Zebra"] ||
                    [path containsString:@"TrollStore"] ||
                    [path containsString:@"trollstore"]) {
                    BYPASS_LOG(@"[FILE] blocked check: %@", path);
                    return NO;
                }
                return ((BOOL (*)(id, SEL, NSString *))orig)(self, @selector(fileExistsAtPath:), path);
            });
            method_setImplementation(m, fake);
            BYPASS_LOG(@"[SYS] hooked NSFileManager fileExistsAtPath:");
        }
    }

    Class procInfo = objc_getClass("NSProcessInfo");
    if (procInfo) {
        Method m = class_getInstanceMethod(procInfo, @selector(environment));
        if (m) {
            IMP orig = method_getImplementation(m);
            IMP fake = imp_implementationWithBlock(^NSDictionary *(id self) {
                NSMutableDictionary *env = [((NSDictionary * (*)(id, SEL))orig)(self, @selector(environment)) mutableCopy];
                if (env[@"DYLD_INSERT_LIBRARIES"]) {
                    [env removeObjectForKey:@"DYLD_INSERT_LIBRARIES"];
                    BYPASS_LOG(@"[ENV] removed DYLD_INSERT_LIBRARIES");
                }
                return env;
            });
            method_setImplementation(m, fake);
            BYPASS_LOG(@"[SYS] hooked NSProcessInfo environment");
        }
    }

    Class bundle = objc_getClass("NSBundle");
    if (bundle) {
        Method m = class_getInstanceMethod(bundle, @selector(bundleIdentifier));
        if (m) {
            IMP orig = method_getImplementation(m);
            IMP fake = imp_implementationWithBlock(^NSString *(id self) {
                NSString *bid = ((NSString * (*)(id, SEL))orig)(self, @selector(bundleIdentifier));
                if ([bid containsString:@"trollstore"] || [bid containsString:@"TrollStore"]) {
                    BYPASS_LOG(@"[BUNDLE] masked trollstore bundle ID");
                    return @"com.apple.mobilesafari";
                }
                return bid;
            });
            method_setImplementation(m, fake);
            BYPASS_LOG(@"[SYS] hooked NSBundle bundleIdentifier");
        }
    }

    Class app = objc_getClass("UIApplication");
    if (app) {
        Method m = class_getInstanceMethod(app, @selector(canOpenURL:));
        if (m) {
            IMP orig = method_getImplementation(m);
            IMP fake = imp_implementationWithBlock(^BOOL(id self, NSURL *url) {
                NSString *scheme = url.scheme.lowercaseString;
                if ([scheme isEqualToString:@"cydia"] ||
                    [scheme isEqualToString:@"sileo"] ||
                    [scheme isEqualToString:@"zbra"] ||
                    [scheme containsString:@"trollstore"]) {
                    BYPASS_LOG(@"[URL] blocked scheme: %@", scheme);
                    return NO;
                }
                return ((BOOL (*)(id, SEL, NSURL *))orig)(self, @selector(canOpenURL:), url);
            });
            method_setImplementation(m, fake);
            BYPASS_LOG(@"[SYS] hooked UIApplication canOpenURL:");
        }
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void init() {
    @autoreleasepool {
        BYPASS_LOG(@"=== AliSecBypass v4 (Headfile + Dobby) loaded ===");

        DobbyHook((void *)ptrace, (void *)my_ptrace, (void **)&orig_ptrace);
        DobbyHook((void *)sysctl, (void *)my_sysctl, (void **)&orig_sysctl);
        DobbyHook((void *)access, (void *)my_access, (void **)&orig_access);
        BYPASS_LOG(@"[DOBBY] ptrace/sysctl/access hooked");

        hookAliSDK();
        hookBaiduSDK();
        hookByteDanceSDK();
        hookSystemClasses();

        BYPASS_LOG(@"=== AliSecBypass v4 init complete ===");
    }
}
