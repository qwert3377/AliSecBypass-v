// UniversalSecBypass_v10.mm
// 通用脱壳检测绕过插件 v1
// 基于 v9 合并版，根据头文件扩展新增安全/监控/日志/设备信息类 Hook
// 阿里 / 高德 / 字节跳动 / 支付宝 / 阿里云 通用
// 纯库文件（无 Logos 预处理），只用标准 ObjC Runtime
// 日志写入 App Documents 目录

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

// ============================================================
// 1. 日志系统
// ============================================================
static NSString *bypassLogPath(void) {
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        path = [paths.firstObject stringByAppendingPathComponent:@"UniversalBypass.log"];
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

// ============================================================
// 2. Hook 工具
// ============================================================
static inline void safeHook(Class cls, SEL sel, IMP fake, IMP *orig) {
    if (!cls || !sel || !fake) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (orig) *orig = method_getImplementation(m);
    method_setImplementation(m, fake);
    BYPASS_LOG(@"[HOOK] -[%s %s]", class_getName(cls), sel_getName(sel));
}

static inline void safeHookNoOrig(Class cls, SEL sel, IMP fake) {
    safeHook(cls, sel, fake, NULL);
}

static inline void safeHookClass(Class cls, SEL sel, IMP fake, IMP *orig) {
    if (!cls || !sel || !fake) return;
    Method m = class_getClassMethod(cls, sel);
    if (!m) return;
    if (orig) *orig = method_getImplementation(m);
    method_setImplementation(m, fake);
    BYPASS_LOG(@"[HOOK] +[%s %s]", class_getName(cls), sel_getName(sel));
}

static inline void safeHookClassNoOrig(Class cls, SEL sel, IMP fake) {
    safeHookClass(cls, sel, fake, NULL);
}

// ============================================================
// 3. 通用返回值函数（双版本保留）
// ============================================================
static id hook_return_safe(id self, SEL _cmd) { return @"safe"; }
static BOOL hook_return_NO_fixed(id self, SEL _cmd) { return NO; }
static void hook_disable_void_fixed(id self, SEL _cmd) { }
static void hook_disable_id_fixed(id self, SEL _cmd, id arg) { }
static id fake_empty_fixed(id self, SEL _cmd) { return @""; }

static void (*orig_sendLog)(id, SEL, id);
static void hook_sendLog_fixed(id self, SEL _cmd, id log) { }

static id hook_ret_nil(id self, SEL _cmd, ...) { return nil; }
static id hook_ret_empty(id self, SEL _cmd, ...) { return @""; }
static BOOL hook_ret_NO(id self, SEL _cmd, ...) { return NO; }
static BOOL hook_ret_YES(id self, SEL _cmd, ...) { return YES; }
static void hook_ret_void(id self, SEL _cmd, ...) { }
static long hook_ret_0(id self, SEL _cmd, ...) { return 0; }

// ============================================================
// 4. 阿里安全 SDK Hook（v9 完整保留 + 扩展）
// ============================================================
static void hookAliSec(void) {
    const char *safeUtilsVariants[] = {
        "AliSecXSafeUtilsMXXTIY",
        "AliSecXSafeUtilsZZZX",
        nil
    };
    for (int i = 0; safeUtilsVariants[i] != nil; i++) {
        Class cls = objc_getClass(safeUtilsVariants[i]);
        if (!cls) continue;
        BYPASS_LOG(@"[AliSec] found %s", safeUtilsVariants[i]);
        safeHookNoOrig(cls, sel_getUid("descriptor"), (IMP)hook_return_safe);
        safeHookNoOrig(cls, sel_getUid("secStatus"), (IMP)hook_return_safe);
        safeHookNoOrig(cls, sel_getUid("safeDescriptor"), (IMP)hook_return_safe);
        safeHookNoOrig(cls, sel_getUid("securityStatus"), (IMP)hook_return_safe);
        safeHookNoOrig(cls, sel_getUid("checkStatus"), (IMP)hook_return_safe);
        safeHookNoOrig(cls, sel_getUid("isJailbreak"), (IMP)hook_return_NO_fixed);
        safeHookNoOrig(cls, sel_getUid("isJailbroken"), (IMP)hook_return_NO_fixed);
        safeHookNoOrig(cls, sel_getUid("isDebug"), (IMP)hook_return_NO_fixed);
        safeHookNoOrig(cls, sel_getUid("isDebuggerAttached"), (IMP)hook_return_NO_fixed);
        safeHookNoOrig(cls, sel_getUid("startSafeGuard"), (IMP)hook_disable_void_fixed);
        safeHookNoOrig(cls, sel_getUid("initSafeGuard"), (IMP)hook_disable_void_fixed);
    }

    const char *deviceInfoVariants[] = {
        "AliSecXDeviceInfoMXXTIY",
        "AliSecXDeviceInfoZZZX",
        "AliSecXPhoneInfoHolderMXXTIY",
        "AliSecXPhoneInfoHolderZZZX",
        nil
    };
    for (int i = 0; deviceInfoVariants[i] != nil; i++) {
        Class cls = objc_getClass(deviceInfoVariants[i]);
        if (!cls) continue;
        BYPASS_LOG(@"[AliSec] found %s", deviceInfoVariants[i]);
    }

    Class kcQuery = objc_getClass("AliSecXSSKeychainQuery");
    if (kcQuery) {
        BYPASS_LOG(@"[AliSec] found AliSecXSSKeychainQuery");
        safeHookNoOrig(kcQuery, sel_getUid("fetch:"), (IMP)hook_ret_NO);
        safeHookNoOrig(kcQuery, sel_getUid("fetchAll:"), (IMP)hook_ret_nil);
        safeHookNoOrig(kcQuery, sel_getUid("save:"), (IMP)hook_ret_NO);
    }

    // --- v10 新增：AliSecXSSKeychainQueryMXXT ---
    Class kcQueryMXXT = objc_getClass("AliSecXSSKeychainQueryMXXT");
    if (kcQueryMXXT) {
        BYPASS_LOG(@"[AliSec] found AliSecXSSKeychainQueryMXXT");
        safeHookNoOrig(kcQueryMXXT, sel_getUid("fetch:"), (IMP)hook_ret_NO);
        safeHookNoOrig(kcQueryMXXT, sel_getUid("fetchAll:"), (IMP)hook_ret_nil);
        safeHookNoOrig(kcQueryMXXT, sel_getUid("save:"), (IMP)hook_ret_NO);
        safeHookNoOrig(kcQueryMXXT, sel_getUid("deleteItem:"), (IMP)hook_ret_NO);
    }

    // --- v10 新增：AliSecXReachability ---
    const char *reachVariants[] = {
        "AliSecXReachabilityMXXTIY",
        "AliSecXReachabilityZZZX",
        nil
    };
    for (int i = 0; reachVariants[i] != nil; i++) {
        Class cls = objc_getClass(reachVariants[i]);
        if (!cls) continue;
        BYPASS_LOG(@"[AliSec] found %s", reachVariants[i]);
        safeHookNoOrig(cls, sel_getUid("startNotifier"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("stopNotifier"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("currentReachabilityStatus"), (IMP)hook_ret_0);
    }
}

// ============================================================
// 5. 设备标识符 Hook（v9 完整保留）
// ============================================================
static void hookDeviceIdentifiers(void) {
    const char *classes[] = {
        "AidManager",
        "AMapADIUManager",
        "AMapDeviceInfo",
        "UTDevice",
        "UTDID",
        "OpenUDID",
        "AliSecuritySDK",
        "AliSecXDeviceInfoMXXTIY",
        "AliSecXDeviceInfoZZZX",
        "AliSecXPhoneInfoHolderMXXTIY",
        "AliSecXPhoneInfoHolderZZZX",
        nil
    };
    const char *selectors[] = {
        "getAid", "aid",
        "getUtdid", "utdid",
        "getAdiu", "adiu",
        "openUDIDValue",
        "deviceId", "uniqueDeviceIdentifier",
        "getUUID", "uuid",
        "ADIU",
        nil
    };
    for (int i = 0; classes[i] != nil; i++) {
        Class cls = objc_getClass(classes[i]);
        if (!cls) continue;
        for (int j = 0; selectors[j] != nil; j++) {
            SEL sel = sel_getUid(selectors[j]);
            if (class_getInstanceMethod(cls, sel)) {
                safeHookNoOrig(cls, sel, (IMP)fake_empty_fixed);
            }
        }
    }
}

// ============================================================
// 6. 高德监控 Hook（v9 完整保留）
// ============================================================
static void hookAMapMonitors(void) {
    Class cls;

    cls = objc_getClass("AMapMonitorSingal");
    if (cls) {
        BYPASS_LOG(@"[AMap] found AMapMonitorSingal");
        safeHookNoOrig(cls, sel_getUid("startMonitor"), (IMP)hook_disable_void_fixed);
        safeHookNoOrig(cls, sel_getUid("registerMonitor:"), (IMP)hook_disable_id_fixed);
        safeHookNoOrig(cls, sel_getUid("setupMonitor"), (IMP)hook_disable_void_fixed);
        safeHookNoOrig(cls, sel_getUid("start"), (IMP)hook_disable_void_fixed);
        safeHookNoOrig(cls, sel_getUid("installSingalHandle"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("uninstallSingalHandle"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("handleSignal:info:context:withCallStackSymbols:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AMapMonitorNSException");
    if (cls) {
        BYPASS_LOG(@"[AMap] found AMapMonitorNSException");
        safeHookNoOrig(cls, sel_getUid("installNSExceptionHandle"), (IMP)hook_disable_void_fixed);
        safeHookNoOrig(cls, sel_getUid("uninstallNSExceptionHandle"), (IMP)hook_disable_void_fixed);
        safeHookNoOrig(cls, sel_getUid("handleUncaughtException:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AMapCrashReporter");
    if (cls) {
        BYPASS_LOG(@"[AMap] found AMapCrashReporter");
        safeHookNoOrig(cls, sel_getUid("startCrashReporter"), (IMP)hook_disable_void_fixed);
        safeHookNoOrig(cls, sel_getUid("enableCrashReporter"), (IMP)hook_disable_void_fixed);
    }

    cls = objc_getClass("AMapCrashManager");
    if (cls) {
        BYPASS_LOG(@"[AMap] found AMapCrashManager");
        safeHookNoOrig(cls, sel_getUid("installMonitor"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("uninstallMonitor"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("setEnable:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("handleException:crashIndex:backTrace:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("handleExceptionType:code:subcode:signum:crashIndex:crashThreadTrace:backTrace:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AMapMonitorMachException");
    if (cls) {
        BYPASS_LOG(@"[AMap] found AMapMonitorMachException");
    }

    cls = objc_getClass("AMapExceptionHandler");
    if (cls) {
        BYPASS_LOG(@"[AMap] found AMapExceptionHandler");
        safeHookNoOrig(cls, sel_getUid("registerExceptionHandler"), (IMP)hook_disable_void_fixed);
        safeHookNoOrig(cls, sel_getUid("setupExceptionHandler"), (IMP)hook_disable_void_fixed);
    }
}

// ============================================================
// 7. 高德分析/网络 Hook（v9 完整保留）
// ============================================================
static void hookAMapAnalytics(void) {
    Class cls;

    cls = objc_getClass("AMapAnalyticsManager");
    if (cls) {
        BYPASS_LOG(@"[AMap] found AMapAnalyticsManager");
        safeHook(cls, sel_getUid("sendLog:"), (IMP)hook_sendLog_fixed, (IMP *)&orig_sendLog);
        safeHookNoOrig(cls, sel_getUid("sendEvent:"), (IMP)hook_disable_id_fixed);
        safeHookNoOrig(cls, sel_getUid("sendReport:"), (IMP)hook_disable_id_fixed);
        safeHookNoOrig(cls, sel_getUid("trackEvent:"), (IMP)hook_disable_id_fixed);
        safeHookNoOrig(cls, sel_getUid("uploadLog"), (IMP)hook_disable_void_fixed);
        safeHookNoOrig(cls, sel_getUid("flush"), (IMP)hook_disable_void_fixed);
        safeHookNoOrig(cls, sel_getUid("logEvent:params:component:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("logEvent:params:component:customFileName:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("logError:errorInfo:component:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("logCrash:crashInfo:component:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("uploadLogWithType:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("uploadLogWithType:component:complete:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AMapNetworkManager");
    if (cls) {
        BYPASS_LOG(@"[AMap] found AMapNetworkManager");
        safeHookNoOrig(cls, sel_getUid("sendRequest:"), (IMP)hook_disable_id_fixed);
        safeHookNoOrig(cls, sel_getUid("sendReport:"), (IMP)hook_disable_id_fixed);
        safeHookNoOrig(cls, sel_getUid("startOperationWithRequestReformer:completionBlock:"), (IMP)hook_ret_nil);
        safeHookNoOrig(cls, sel_getUid("startOperation:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AMapLogUploader");
    if (cls) {
        BYPASS_LOG(@"[AMap] found AMapLogUploader");
        safeHookNoOrig(cls, sel_getUid("upload"), (IMP)hook_disable_void_fixed);
        safeHookNoOrig(cls, sel_getUid("startUpload"), (IMP)hook_disable_void_fixed);
        safeHookNoOrig(cls, sel_getUid("uploadComponentName:levelStr:complete:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("setUpLoading:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AMapNetFlowManager");
    if (cls) {
        BYPASS_LOG(@"[AMap] found AMapNetFlowManager");
        safeHookNoOrig(cls, sel_getUid("isBlock"), (IMP)hook_return_NO_fixed);
        safeHookNoOrig(cls, sel_getUid("isBlocked"), (IMP)hook_return_NO_fixed);
        safeHookNoOrig(cls, sel_getUid("checkBlock"), (IMP)hook_return_NO_fixed);
        safeHookNoOrig(cls, sel_getUid("checkNetworkBlock"), (IMP)hook_return_NO_fixed);
        safeHookNoOrig(cls, sel_getUid("isBlock:"), (IMP)hook_ret_NO);
        safeHookNoOrig(cls, sel_getUid("checkResponse:withRequest:responseData:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AMapFoundationKeychainManager");
    if (cls) {
        BYPASS_LOG(@"[AMap] found AMapFoundationKeychainManager");
        safeHookNoOrig(cls, sel_getUid("setObject:forKey:"), (IMP)hook_ret_NO);
        safeHookNoOrig(cls, sel_getUid("objectForKey:"), (IMP)hook_ret_nil);
    }

    cls = objc_getClass("AidManager");
    if (cls) {
        BYPASS_LOG(@"[AMap] found AidManager");
        safeHookNoOrig(cls, sel_getUid("value:token:utdid:"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("requestAid:token:utdid:aidDelegate:"), (IMP)hook_ret_void);
    }
}

// ============================================================
// 8. 字节跳动 / 番茄畅听安全 Hook（v9 完整保留）
// ============================================================
static void hookByteDance(void) {
    Class cls;

    cls = objc_getClass("SSSecurityManager");
    if (cls) {
        BYPASS_LOG(@"[BD] found SSSecurityManager");
        safeHookNoOrig(cls, sel_getUid("reportForScene:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("reportForSceneType:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("checkSecurity"), (IMP)hook_ret_NO);
        safeHookNoOrig(cls, sel_getUid("isSecure"), (IMP)hook_ret_YES);
    }

    cls = objc_getClass("TTAppUpdateHelper");
    if (cls) {
        BYPASS_LOG(@"[BD] found TTAppUpdateHelper");
        safeHookNoOrig(cls, sel_getUid("startCheckVersion"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("checkVersion"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("checkAndShowForceUpdateAlert"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AnnieXMonitorTeaReporter");
    if (cls) {
        BYPASS_LOG(@"[BD] found AnnieXMonitorTeaReporter");
        safeHookNoOrig(cls, sel_getUid("reportToTea:params:urlString:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AnnieXMonitor");
    if (cls) {
        BYPASS_LOG(@"[BD] found AnnieXMonitor");
        safeHookNoOrig(cls, sel_getUid("reportPV"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("reportFullTimeWhenFirstScreenWithPlatForm:sampleLevel:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("reportFullTimeWhenLeaveWithPlatForm:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("reportContainerErrorWithSessionId:withErrorCode:withErrorMessage:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("reportUpdateView"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AnnieTraceEventImpl");
    if (cls) {
        BYPASS_LOG(@"[BD] found AnnieTraceEventImpl");
        safeHookNoOrig(cls, sel_getUid("traceBeginSectionWithName:debugInfo:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("traceEndSectionWithName:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("traceInstantWithName:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("SwiftALog4ALog");
    if (cls) {
        BYPASS_LOG(@"[BD] found SwiftALog4ALog");
        safeHookNoOrig(cls, sel_getUid("log:message:level:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("logEvent:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("GeckoManager");
    if (cls) {
        BYPASS_LOG(@"[BD] found GeckoManager");
        safeHookNoOrig(cls, sel_getUid("registerAndPreloadCommerceGecko"), (IMP)hook_ret_void);
    }
}

// ============================================================
// 9. 通用防护（v9 完整保留）
// ============================================================
static void hookGeneral(void) {
    Class exc = objc_getClass("NSException");
    if (exc) {
        safeHookNoOrig(exc, sel_getUid("raise"), (IMP)hook_ret_void);
        safeHookNoOrig(exc, sel_getUid("raise:format:"), (IMP)hook_ret_void);
        safeHookNoOrig(exc, sel_getUid("raise:format:arguments:"), (IMP)hook_ret_void);
    }

    Class uiApp = objc_getClass("UIApplication");
    if (uiApp) {
        safeHookNoOrig(uiApp, sel_getUid("terminateWithSuccess"), (IMP)hook_ret_void);
    }
}

// ============================================================
// 10. v10 新增：高德扩展 - 统计/系统信息/日志/网络
// ============================================================
static void hookAMapExtended(void) {
    Class cls;

    // --- AMapStatistics：设备信息收集 ---
    cls = objc_getClass("AMapStatistics");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapStatistics");
        safeHookNoOrig(cls, sel_getUid("infoStringWithKeys:"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("infoDictionaryWithKeys:"), (IMP)hook_ret_nil);
        safeHookNoOrig(cls, sel_getUid("xinfo"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("xinfo_21"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("platinfoWithProduct:version:"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("platform"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("appname"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("appversion"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("bundleid"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("sysversion"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("diu"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("sim"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("tel"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("pkg"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("manufacture"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("model"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("device"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("mac"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("adiu"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("ext"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("imac"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("ant"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("nt"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("mnc"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("np"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("lon"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("lat"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("wifis"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("wifi"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("wifiname"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("bts"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("bttype"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("gps"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("resolution"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("glrender"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("tid"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("ram"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("storage"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("arch"), (IMP)hook_ret_empty);
    }

    // --- AMapSystemInfo：系统信息 ---
    cls = objc_getClass("AMapSystemInfo");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapSystemInfo");
        safeHookNoOrig(cls, sel_getUid("initialize"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("extractMemoryTotalSize"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("extractMemoryUsedSize"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("extractMemoryFreeSize"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("extractDeviceVersion"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("extractAppUUID"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("extractCPUArch"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("extractDeviceAppHash"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("enterBackground:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("becomeActive:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("resignActive:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("updateLastSwitchActiveTime:"), (IMP)hook_ret_void);
    }

    // --- AMapServices：服务认证/统计 ---
    cls = objc_getClass("AMapServices");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapServices");
        safeHookNoOrig(cls, sel_getUid("validatingAPIKey"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("sendInitInfoWithComponent:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("registerWithComponent:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("registerWithComponent:authKeys:params:handler:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("sendStatisticsWithComponent:handler:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("showKeyAuthorizationInfo:responseHeader:forComponent:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("setUpAnalytics"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("initAnalytics"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("uploadAnalyticsInfo"), (IMP)hook_ret_void);
    }

    // --- AMapMacAddressFinder：MAC地址（设备指纹） ---
    cls = objc_getClass("AMapMacAddressFinder");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapMacAddressFinder");
        safeHookNoOrig(cls, sel_getUid("AMF_macAddress"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("_getMacAddressWithIP:"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("AMF_IPAddress"), (IMP)hook_ret_empty);
    }

    // --- AMapFoundationReachability：网络可达性 ---
    cls = objc_getClass("AMapFoundationReachability");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapFoundationReachability");
        safeHookNoOrig(cls, sel_getUid("startNotifier"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("stopNotifier"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("currentNetworkType"), (IMP)hook_ret_0);
        safeHookNoOrig(cls, sel_getUid("localConnectionChanged"), (IMP)hook_ret_void);
    }

    // --- AMapFoundationRSA：加密 ---
    cls = objc_getClass("AMapFoundationRSA");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapFoundationRSA");
        safeHookNoOrig(cls, sel_getUid("encryptWithData:"), (IMP)hook_ret_nil);
        safeHookNoOrig(cls, sel_getUid("encryptWithString:"), (IMP)hook_ret_nil);
        safeHookNoOrig(cls, sel_getUid("encryptToString:"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("verifyBytesSHA256withRSA:signature:"), (IMP)hook_ret_NO);
    }

    // --- AMapDNSResolver：DNS解析 ---
    cls = objc_getClass("AMapDNSResolver");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapDNSResolver");
        safeHookNoOrig(cls, sel_getUid("asyncLookupComplete:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("stopHostResolution"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("hostResolutionDoneWithAddresses:"), (IMP)hook_ret_void);
    }

    // --- AMapAuthRequestReformer：认证请求 ---
    cls = objc_getClass("AMapAuthRequestReformer");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapAuthRequestReformer");
        safeHookNoOrig(cls, sel_getUid("baseURL"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("v6BaseURL"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("forceUseUserConfigTimeOut"), (IMP)hook_ret_NO);
    }

    // --- AMapRequestLogger / AMapSearchLogger：请求/搜索日志 ---
    cls = objc_getClass("AMapRequestLogger");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapRequestLogger");
        safeHookNoOrig(cls, sel_getUid("onBeginOfOp:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("onEndOfOp:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("onFinalResultOfOp:responseDict:response:responseErr:netErr:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AMapSearchLogger");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapSearchLogger");
        safeHookNoOrig(cls, sel_getUid("onBeginOfOp:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("onEndOfOp:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("onFinalResultOfOp:responseDict:response:responseErr:netErr:"), (IMP)hook_ret_void);
    }

    // --- AMapSearchExecutor：搜索执行器 ---
    cls = objc_getClass("AMapSearchExecutor");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapSearchExecutor");
        safeHookNoOrig(cls, sel_getUid("performSearchTestWithJSONString:completion:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("performSearchServiceWithJSONDic:completion:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("performSearchWithRequest:completionBlock:"), (IMP)hook_ret_void);
    }

    // --- AMapSearchAPI：搜索API ---
    cls = objc_getClass("AMapSearchAPI");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapSearchAPI");
        safeHookNoOrig(cls, sel_getUid("cancelAllRequests"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("performPOISearchWithBaseRequest:"), (IMP)hook_ret_void);
    }

    // --- AMapLogFileHandler / AMapLogHandler / AMapTTYLogHandler：日志处理 ---
    cls = objc_getClass("AMapLogFileHandler");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapLogFileHandler");
        safeHookNoOrig(cls, sel_getUid("uploadLogWithlevelStr:complete:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("logMessage:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AMapLogHandler");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapLogHandler");
        safeHookNoOrig(cls, sel_getUid("logMessage:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("uploadLogWithlevelStr:complete:"), (IMP)hook_ret_void);
    }

    cls = objc_getClass("AMapTTYLogHandler");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapTTYLogHandler");
        safeHookNoOrig(cls, sel_getUid("logMessage:"), (IMP)hook_ret_void);
    }

    // --- AMapNetWorkPerformanceManager：网络性能监控 ---
    cls = objc_getClass("AMapNetWorkPerformanceManager");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapNetWorkPerformanceManager");
        safeHookNoOrig(cls, sel_getUid("addPerformanceModel:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("getPerformanceModel"), (IMP)hook_ret_nil);
        safeHookNoOrig(cls, sel_getUid("getFailModel"), (IMP)hook_ret_nil);
    }

    // --- AMapNetworkStackManager：网络栈 ---
    cls = objc_getClass("AMapNetworkStackManager");
    if (cls) {
        BYPASS_LOG(@"[AMapExt] found AMapNetworkStackManager");
        safeHookNoOrig(cls, sel_getUid("startOperationWithRequestReformer:completionBlock:"), (IMP)hook_ret_nil);
        safeHookNoOrig(cls, sel_getUid("startOperation:"), (IMP)hook_ret_void);
    }
}

// ============================================================
// 11. v10 新增：字节跳动扩展 - 监控/日志/追踪
// ============================================================
static void hookByteDanceExtended(void) {
    Class cls;

    // --- AnnieXMonitorAbilityDelegate：AnnieX 监控代理 ---
    cls = objc_getClass("AnimaXMonitorAbilityDelegate");
    if (cls) {
        BYPASS_LOG(@"[BDExt] found AnimaXMonitorAbilityDelegate");
        safeHookNoOrig(cls, sel_getUid("initWithServiceRegistry:"), (IMP)hook_ret_nil);
        safeHookNoOrig(cls, sel_getUid("setAnimaXPlayer:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("updateUrl:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("setDisplayMode:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("setTag:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("onError:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("onRelease"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("onRepeat:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("onResume"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("onPlaySegment"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("onPlay"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("reportOnPlayAndTryTrigger:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("reportPerformance:"), (IMP)hook_ret_void);
    }

    // --- AnnieLatchMonitorModule：监控模块 ---
    cls = objc_getClass("AnnieLatchMonitorModule");
    if (cls) {
        BYPASS_LOG(@"[BDExt] found AnnieLatchMonitorModule");
        safeHookNoOrig(cls, sel_getUid("result:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("perfMetric:"), (IMP)hook_ret_void);
    }

    // --- AnnieLiveBizMonitor：直播监控 ---
    cls = objc_getClass("AnnieLiveBizMonitor");
    if (cls) {
        BYPASS_LOG(@"[BDExt] found AnnieLiveBizMonitor");
    }

    // --- TempoTrace / TempoDebugRetainCount / TempoMethodAppModule：Tempo 追踪 ---
    cls = objc_getClass("TempoTrace");
    if (cls) {
        BYPASS_LOG(@"[BDExt] found TempoTrace");
        safeHookNoOrig(cls, sel_getUid("init"), (IMP)hook_ret_nil);
    }

    cls = objc_getClass("TempoDebugRetainCount");
    if (cls) {
        BYPASS_LOG(@"[BDExt] found TempoDebugRetainCount");
        safeHookNoOrig(cls, sel_getUid("init"), (IMP)hook_ret_nil);
    }

    cls = objc_getClass("TempoMethodAppModule");
    if (cls) {
        BYPASS_LOG(@"[BDExt] found TempoMethodAppModule");
        safeHookNoOrig(cls, sel_getUid("loadModule"), (IMP)hook_ret_void);
    }

    // --- ComposeLogServiceImpl：Compose 日志服务 ---
    cls = objc_getClass("ComposeLogServiceImpl");
    if (cls) {
        BYPASS_LOG(@"[BDExt] found ComposeLogServiceImpl");
        safeHookNoOrig(cls, sel_getUid("logWithPriority:keyword:message:info:"), (IMP)hook_ret_void);
    }

    // --- ALMOwnPlayerLoggerWrapper：播放器日志 ---
    cls = objc_getClass("ALMOwnPlayerLoggerWrapper");
    if (cls) {
        BYPASS_LOG(@"[BDExt] found ALMOwnPlayerLoggerWrapper");
        safeHookNoOrig(cls, sel_getUid("setApplogCallBlock:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("setNewApplogCallBlock:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("didFinishedOnePlayEvent:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("logPreloaderData:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("eventManagerDidUpdate:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("eventManagerDidUpdateV2:eventName:params:"), (IMP)hook_ret_void);
    }

    // --- YataTrackerEventImpl：Yata 追踪事件 ---
    cls = objc_getClass("TrackerEventImpl");
    if (cls) {
        BYPASS_LOG(@"[BDExt] found TrackerEventImpl");
    }

    // --- Swift 类尝试（通过 mangled name）---
    const char *swiftClasses[] = {
        "_TtC6AnnieX11APMReporter",
        "_TtC6AnnieX13HeimdallrImpl",
        "_TtC6AnnieX7LogImpl",
        "_TtC6AnnieX8Switches",
        "_TtC22SalamanderBDFoundation11SLHeimdallr",
        "_TtC10Salamander16DeviceSystemImpl",
        "_TtC10Salamander8SLDevice",
        nil
    };
    for (int i = 0; swiftClasses[i] != nil; i++) {
        Class cls = objc_getClass(swiftClasses[i]);
        if (cls) {
            BYPASS_LOG(@"[BDExt] found Swift class %s", swiftClasses[i]);
        }
    }
}

// ============================================================
// 12. v10 新增：广告追踪扩展
// ============================================================
static void hookAdExtended(void) {
    Class cls;

    // --- AdInnovationTrackerManager：创新广告追踪 ---
    cls = objc_getClass("AdInnovationTrackerManager");
    if (cls) {
        BYPASS_LOG(@"[AdExt] found AdInnovationTrackerManager");
        safeHookNoOrig(cls, sel_getUid("trackWithContext:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("eventData:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("eventV3:params:isDoubleSending:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("performanceEventV3:params:"), (IMP)hook_ret_void);
    }

    // --- AdInnovationManager：创新广告管理 ---
    cls = objc_getClass("AdInnovationManager");
    if (cls) {
        BYPASS_LOG(@"[AdExt] found AdInnovationManager");
        safeHookNoOrig(cls, sel_getUid("sendEvent:params:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("trackDestroyEvent"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("trackContainerRealDisplay"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("trackContainerAppear"), (IMP)hook_ret_void);
    }

    // --- AdMetaverseTracker：元宇宙广告追踪 ---
    cls = objc_getClass("AdMetaverseTracker");
    if (cls) {
        BYPASS_LOG(@"[AdExt] found AdMetaverseTracker");
    }

    // --- AdWebViewResourceLoader：广告 WebView 资源 ---
    cls = objc_getClass("AdWebViewResourceLoader");
    if (cls) {
        BYPASS_LOG(@"[AdExt] found AdWebViewResourceLoader");
        safeHookNoOrig(cls, sel_getUid("didReceiveMemoryWarningNotification"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("didReceiveApplicationWillTerminalNotification"), (IMP)hook_ret_void);
    }
}

// ============================================================
// 13. v10 新增：支付宝/阿里云扩展
// ============================================================
static void hookAlipayExtended(void) {
    Class cls;

    // --- AlipaySDK：支付宝 ---
    cls = objc_getClass("AlipaySDK");
    if (cls) {
        BYPASS_LOG(@"[Alipay] found AlipaySDK");
        safeHookNoOrig(cls, sel_getUid("processOrderWithPaymentResult:standbyCallback:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("handleOpenUniversalLink:standbyCallback:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("queryTid"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("fetchSdkConfigWithBlock:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("fetchTradeToken"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("isLogined"), (IMP)hook_ret_NO);
    }

    // --- AFServiceCenter：支付宝服务中心 ---
    cls = objc_getClass("AFServiceCenter");
    if (cls) {
        BYPASS_LOG(@"[Alipay] found AFServiceCenter");
        safeHookNoOrig(cls, sel_getUid("callService:withParams:andCompletion:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("handleResponseURL:withCompletion:"), (IMP)hook_ret_void);
    }

    // --- AFServiceTask：支付宝服务任务 ---
    cls = objc_getClass("AFServiceTask");
    if (cls) {
        BYPASS_LOG(@"[Alipay] found AFServiceTask");
        safeHookNoOrig(cls, sel_getUid("performWithBlock:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("callbackWithResult:"), (IMP)hook_ret_void);
    }

    // --- AliyunIdentityManager：阿里云身份管理 ---
    cls = objc_getClass("AliyunIdentityManager");
    if (cls) {
        BYPASS_LOG(@"[Aliyun] found AliyunIdentityManager");
        safeHookNoOrig(cls, sel_getUid("verifyWith:extParams:onCompletion:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("verifyTechWith:extParams:onCompletion:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("sendlog:withSeedID:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("getMetaInfo"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("quit:onCompletion:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("modelFilePathContent"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("appResignActive:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("onVerifyResponse:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("onFinalize:andExtinfo:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("uploadLogChooice"), (IMP)hook_ret_NO);
        safeHookNoOrig(cls, sel_getUid("getlogArray"), (IMP)hook_ret_nil);
        safeHookNoOrig(cls, sel_getUid("finalPathForFile:"), (IMP)hook_ret_empty);
    }

    // --- AliyunFaceAuthRPC：阿里云人脸认证 RPC ---
    cls = objc_getClass("AliyunFaceAuthRPC");
    if (cls) {
        BYPASS_LOG(@"[Aliyun] found AliyunFaceAuthRPC");
        safeHookNoOrig(cls, sel_getUid("zimInit:completionBlock:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("zimValidate:completionBlock:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("zimNFCValidate:completionBlock:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("zimOCRIdentify:completionBlock:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("uploadFileWthParams:completionBlock:"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("zimFileUpload:completionBlock:"), (IMP)hook_ret_void);
    }

    // --- ActionLivenessTC：活体检测 ---
    cls = objc_getClass("ActionLivenessTC");
    if (cls) {
        BYPASS_LOG(@"[Aliyun] found ActionLivenessTC");
        safeHookNoOrig(cls, sel_getUid("initWithVC:"), (IMP)hook_ret_nil);
        safeHookNoOrig(cls, sel_getUid("initData"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("doFaceLive:orient:"), (IMP)hook_ret_nil);
        safeHookNoOrig(cls, sel_getUid("doFaceLive:depthPixelBuffer:orient:"), (IMP)hook_ret_nil);
        safeHookNoOrig(cls, sel_getUid("packSDKDataWithFaceLiveInfo:"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("packLogData"), (IMP)hook_ret_empty);
        safeHookNoOrig(cls, sel_getUid("uploadFaceDetectInfo"), (IMP)hook_ret_void);
        safeHookNoOrig(cls, sel_getUid("trackEvent:withParams:"), (IMP)hook_ret_void);
    }
}

// ============================================================
// 14. Constructor
// ============================================================
__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        BYPASS_LOG(@"==== UniversalSecBypass v10 loaded ====");
        hookAliSec();
        hookDeviceIdentifiers();
        hookAMapMonitors();
        hookAMapAnalytics();
        hookByteDance();
        hookGeneral();
        // v10 新增模块
        hookAMapExtended();
        hookByteDanceExtended();
        hookAdExtended();
        hookAlipayExtended();
        BYPASS_LOG(@"==== UniversalSecBypass v10 init complete ====");
    }
}
