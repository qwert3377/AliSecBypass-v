// AliSecBypass.mm
// 阿里/高德/字节/百度 SDK 脱壳检测绕过插件 v2.1
// 纯库文件，零外部依赖，适用于 TrollStore / 非越狱注入
// 按头文件增强：AliSecX / AMap / Aliyun / Salamander / AnnieX / BDADSDK / BDAResourceKit / TempoiOS / Bind

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>

#pragma mark - 日志系统

static NSString *logPath() {
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
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath()];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [line writeToFile:logPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

#pragma mark - Hook 工具

static inline void safeHook(Class cls, SEL sel, IMP fake, IMP *orig) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (orig) *orig = method_getImplementation(m);
    method_setImplementation(m, fake);
}

static inline void safeHookNoOrig(Class cls, SEL sel, IMP fake) {
    safeHook(cls, sel, fake, NULL);
}

#pragma mark - 通用返回值 Stub

static id ret_nil(id self, SEL _cmd) { return nil; }
static id ret_empty_str(id self, SEL _cmd) { return @""; }
static id ret_empty_arr(id self, SEL _cmd) { return @[]; }
static id ret_empty_dict(id self, SEL _cmd) { return @{}; }
static id ret_zero_num(id self, SEL _cmd) { return @0; }
static id ret_safe(id self, SEL _cmd) { return @"safe"; }
static BOOL ret_NO(id self, SEL _cmd) { return NO; }
static long long ret_zero_ll(id self, SEL _cmd) { return 0; }
static int ret_zero_int(id self, SEL _cmd) { return 0; }
static double ret_zero_double(id self, SEL _cmd) { return 0.0; }
static void ret_void(id self, SEL _cmd) {}

#pragma mark - 批量 Hook 辅助

static void hookSelectorsOnClass(const char *clsName, const char **sels, IMP imp) {
    Class cls = objc_getClass(clsName);
    if (!cls) return;
    for (int i = 0; sels[i] != nil; i++) {
        SEL sel = sel_getUid(sels[i]);
        if (class_getInstanceMethod(cls, sel)) {
            safeHookNoOrig(cls, sel, imp);
        }
    }
}

// 自动扫描类的方法列表并 hook（仅处理 @objc 暴露的方法）
// 跳过 init/dealloc/struct 返回等高风险方法
static void autoHookClassMethodsSafe(const char *clsName) {
    Class cls = objc_getClass(clsName);
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (!methods) return;

    int hooked = 0;
    for (unsigned int i = 0; i < count; i++) {
        Method m = methods[i];
        SEL sel = method_getName(m);
        const char *selName = sel_getName(sel);

        // 跳过生命周期和初始化方法，避免破坏对象状态
        if (strcmp(selName, "init") == 0 ||
            strcmp(selName, "dealloc") == 0 ||
            strcmp(selName, ".cxx_destruct") == 0 ||
            strncmp(selName, "initWith", 8) == 0 ||
            strcmp(selName, "alloc") == 0 ||
            strcmp(selName, "new") == 0 ||
            strcmp(selName, "copy") == 0 ||
            strcmp(selName, "copyWithZone:") == 0 ||
            strcmp(selName, "mutableCopyWithZone:") == 0) {
            continue;
        }

        const char *type = method_getTypeEncoding(m);
        if (!type || strlen(type) < 1) continue;

        char retType = type[0];
        IMP stub = NULL;

        if (retType == 'v') {
            stub = (IMP)ret_void;
        } else if (retType == 'B') {
            stub = (IMP)ret_NO;
        } else if (retType == 'q' || retType == 'l' || retType == 'i' || retType == 'Q' || retType == 'L' || retType == 'I' || retType == 's' || retType == 'S' || retType == 'c' || retType == 'C') {
            stub = (IMP)ret_zero_ll;
        } else if (retType == 'd' || retType == 'f') {
            stub = (IMP)ret_zero_double;
        } else if (retType == '@' || retType == '#') {
            if (strstr(selName, "Array") || strstr(selName, "List") || strstr(selName, "array")) {
                stub = (IMP)ret_empty_arr;
            } else if (strstr(selName, "Dict") || strstr(selName, "Map") || strstr(selName, "dictionary")) {
                stub = (IMP)ret_empty_dict;
            } else if (strstr(selName, "String") || strstr(selName, "str") || strstr(selName, "Name") || strstr(selName, "Text") || strstr(selName, "URL")) {
                stub = (IMP)ret_empty_str;
            } else {
                stub = (IMP)ret_nil;
            }
        } else if (retType == '*' || retType == ':' || retType == '^') {
            stub = (IMP)ret_zero_ll;
        } else {
            // struct / union / complex，跳过避免崩溃
            continue;
        }

        if (stub) {
            safeHookNoOrig(cls, sel, stub);
            hooked++;
        }
    }
    free(methods);
    if (hooked > 0) {
        BYPASS_LOG(@"autoHook %s: %d methods", clsName, hooked);
    }
}

#pragma mark - 阿里安全 Utils

static void hookAliSecXSafeUtilsVariants() {
    const char *variants[] = {
        "AliSecXSafeUtilsMXXTIY",
        "AliSecXSafeUtilsZZZX",
        nil
    };
    const char *strSels[] = {
        "descriptor", "secStatus", "safeDescriptor", "securityStatus",
        "checkStatus", "deviceFingerprint", "riskToken", "envInfo",
        nil
    };
    const char *boolSels[] = {
        "isJailbreak", "isJailbroken", "isDebug", "isDebuggerAttached",
        "isProxy", "isEmulator", "isVirtualMachine", nil
    };
    for (int i = 0; variants[i] != nil; i++) {
        hookSelectorsOnClass(variants[i], strSels, (IMP)ret_safe);
        hookSelectorsOnClass(variants[i], boolSels, (IMP)ret_NO);
    }
}

#pragma mark - 阿里 Reachability

static void hookAliSecXReachability() {
    const char *clses[] = { "AliSecXReachabilityMXXTIY", "AliSecXReachabilityZZZX", nil };
    for (int i = 0; clses[i] != nil; i++) {
        Class cls = objc_getClass(clses[i]);
        if (!cls) continue;
        safeHookNoOrig(cls, sel_getUid("startNotifier"), (IMP)ret_NO);
        safeHookNoOrig(cls, sel_getUid("stopNotifier"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("currentReachabilityStatus"), (IMP)ret_zero_ll);
        safeHookNoOrig(cls, sel_getUid("localWiFiStatusForFlags:"), (IMP)ret_zero_ll);
        safeHookNoOrig(cls, sel_getUid("networkStatusForFlags:"), (IMP)ret_zero_ll);
    }
}

#pragma mark - 阿里 Keychain & Storage

static void hookAliSecXKeychain() {
    const char *clses[] = {
        "AliSecXSSKeychain", "AliSecXSSKeychainMXXT",
        "AliSecXSSKeychainQuery", "AliSecXSSKeychainQueryMXXT",
        nil
    };
    for (int i = 0; clses[i] != nil; i++) {
        Class cls = objc_getClass(clses[i]);
        if (!cls) continue;
        safeHookNoOrig(cls, sel_getUid("save:"), (IMP)ret_NO);
        safeHookNoOrig(cls, sel_getUid("deleteItem:"), (IMP)ret_NO);
        safeHookNoOrig(cls, sel_getUid("fetchAll:"), (IMP)ret_empty_arr);
        safeHookNoOrig(cls, sel_getUid("fetch:"), (IMP)ret_NO);
        safeHookNoOrig(cls, sel_getUid("setPassword:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("password"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("query"), (IMP)ret_empty_dict);
    }
}

static void hookAliSecXCryptoAndStorage() {
    const char *clses[] = {
        "AliSecXCryptoGTMBase64",
        "AliSecXFileOp", "AliSecXFileOpMXXT",
        "AliSecXLocalStorage", "AliSecXLocalStorageMXXT", "AliSecXLocalStorageUtils",
        nil
    };
    for (int i = 0; clses[i] != nil; i++) {
        autoHookClassMethodsSafe(clses[i]);
    }
}

#pragma mark - 阿里云身份认证

static void (*orig_verifyWith)(id, SEL, id, id, id);
static void hook_verifyWith(id self, SEL _cmd, id arg1, id arg2, id completion) {
    BYPASS_LOG(@"AliyunIdentityManager.verifyWith blocked");
    if (completion) {
        void (^cb)(id) = completion;
        cb(@{@"code": @0, @"msg": @"success", @"certifyId": @""});
    }
}

static void (*orig_verifyTechWith)(id, SEL, id, id, id);
static void hook_verifyTechWith(id self, SEL _cmd, id arg1, id arg2, id completion) {
    if (completion) {
        void (^cb)(id) = completion;
        cb(@{@"code": @0, @"msg": @"success"});
    }
}

static void (*orig_quitAliyun)(id, SEL, id, id);
static void hook_quitAliyun(id self, SEL _cmd, id arg1, id completion) {
    if (completion) { void (^cb)(id) = completion; cb(nil); }
}

static void hookAliyunIdentity() {
    Class cls = objc_getClass("AliyunIdentityManager");
    if (!cls) return;
    BYPASS_LOG(@"hooking AliyunIdentityManager");
    safeHook(cls, sel_getUid("verifyWith:extParams:onCompletion:"), (IMP)hook_verifyWith, (IMP *)&orig_verifyWith);
    safeHook(cls, sel_getUid("verifyTechWith:extParams:onCompletion:"), (IMP)hook_verifyTechWith, (IMP *)&orig_verifyTechWith);
    safeHook(cls, sel_getUid("quit:onCompletion:"), (IMP)hook_quitAliyun, (IMP *)&orig_quitAliyun);
    safeHookNoOrig(cls, sel_getUid("getMetaInfo"), (IMP)ret_empty_str);
    safeHookNoOrig(cls, sel_getUid("sendlog:withSeedID:"), (IMP)ret_void);
    safeHookNoOrig(cls, sel_getUid("modelFilePathContent"), (IMP)ret_empty_str);
    safeHookNoOrig(cls, sel_getUid("uploadLogChooice"), (IMP)ret_NO);
    safeHookNoOrig(cls, sel_getUid("colorParamFail:"), (IMP)ret_NO);
    safeHookNoOrig(cls, sel_getUid("checkMinimumVersion"), (IMP)ret_empty_str);
    safeHookNoOrig(cls, sel_getUid("appResignActive:"), (IMP)ret_void);
    safeHookNoOrig(cls, sel_getUid("onVerifyResponse:"), (IMP)ret_void);
    safeHookNoOrig(cls, sel_getUid("onFinalize:andExtinfo:"), (IMP)ret_void);
    safeHookNoOrig(cls, sel_getUid("getlogArray"), (IMP)ret_empty_arr);
    safeHookNoOrig(cls, sel_getUid("finalPathForFile:"), (IMP)ret_empty_str);
    safeHookNoOrig(cls, sel_getUid("setDataProtocolVersion:"), (IMP)ret_void);
}

#pragma mark - 阿里云人脸认证 RPC

static void (*orig_zimInit)(id, SEL, id, id);
static void hook_zimInit(id self, SEL _cmd, id params, id completion) {
    if (completion) {
        void (^cb)(id) = completion;
        cb(@{@"code": @0, @"msg": @"success"});
    }
}

static void (*orig_zimValidate)(id, SEL, id, id);
static void hook_zimValidate(id self, SEL _cmd, id params, id completion) {
    if (completion) {
        void (^cb)(id) = completion;
        cb(@{@"code": @0, @"msg": @"success"});
    }
}

static void hookAliyunFaceAuth() {
    Class cls = objc_getClass("AliyunFaceAuthRPC");
    if (!cls) return;
    safeHook(cls, sel_getUid("zimInit:completionBlock:"), (IMP)hook_zimInit, (IMP *)&orig_zimInit);
    safeHook(cls, sel_getUid("zimValidate:completionBlock:"), (IMP)hook_zimValidate, (IMP *)&orig_zimValidate);
    safeHookNoOrig(cls, sel_getUid("zimNFCValidate:completionBlock:"), (IMP)hook_zimInit);
    safeHookNoOrig(cls, sel_getUid("zimOCRIdentify:completionBlock:"), (IMP)hook_zimInit);
    safeHookNoOrig(cls, sel_getUid("uploadFileWthParams:completionBlock:"), (IMP)hook_zimInit);
    safeHookNoOrig(cls, sel_getUid("zimFileUpload:completionBlock:"), (IMP)hook_zimInit);
    safeHookNoOrig(cls, sel_getUid("dictionaryIsContainKey:key:"), (IMP)ret_NO);
    safeHookNoOrig(cls, sel_getUid("getValueFromeDict:forKey:defaultStr:"), (IMP)ret_empty_str);

    Class facade = objc_getClass("AliyunFaceAuthFacade");
    if (facade) autoHookClassMethodsSafe("AliyunFaceAuthFacade");
}

#pragma mark - 设备标识符 Hook

static void hookDeviceIdentifiers() {
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
                safeHookNoOrig(cls, sel, (IMP)ret_empty_str);
            }
        }
    }
}

#pragma mark - 高德监控与崩溃

static void hookMonitors() {
    Class cls;

    cls = objc_getClass("AMapMonitorSingal");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("startMonitor"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("registerMonitor:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("setupMonitor"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("start"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("installSingalHandle"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("uninstallSingalHandle"), (IMP)ret_void);
    }

    cls = objc_getClass("AMapMonitorNSException");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("installNSExceptionHandle"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("uninstallNSExceptionHandle"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("handleUncaughtException:"), (IMP)ret_void);
    }

    cls = objc_getClass("AMapMonitorMachException");
    if (cls) autoHookClassMethodsSafe("AMapMonitorMachException");

    cls = objc_getClass("AMapCrashReporter");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("startCrashReporter"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("enableCrashReporter"), (IMP)ret_void);
    }

    cls = objc_getClass("AMapExceptionHandler");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("registerExceptionHandler"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("setupExceptionHandler"), (IMP)ret_void);
    }

    cls = objc_getClass("AMapCrashManager");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("installMonitor"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("uninstallMonitor"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("isInTracedModel"), (IMP)ret_NO);
        safeHookNoOrig(cls, sel_getUid("registerWithComponent:withConfig:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("checkConfigs"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("componentCrashForThread:"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("firstAppCmd"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("firstSymbolCmd"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("parserCrashReason:"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("parserCrashThread:"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("matchComponent:"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("handleExceptionType:code:subcode:signum:crashIndex:crashThreadTrace:backTrace:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("parserCrashException:thread:"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("parserCrashType:"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("handleException:crashIndex:backTrace:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("fillSystemInfo:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("fillComponentInfo:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("exceptionType:signum:"), (IMP)ret_empty_str);
    }
}

#pragma mark - 高德分析与日志

static void (*orig_sendLog)(id, SEL, id);
static void hook_sendLog(id self, SEL _cmd, id log) {}

static void hookAnalytics() {
    Class cls;

    cls = objc_getClass("AMapAnalyticsManager");
    if (cls) {
        safeHook(cls, sel_getUid("sendLog:"), (IMP)hook_sendLog, (IMP *)&orig_sendLog);
        safeHookNoOrig(cls, sel_getUid("sendEvent:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("sendReport:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("trackEvent:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("uploadLog"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("flush"), (IMP)ret_void);
    }

    cls = objc_getClass("AMapNetworkManager");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("sendRequest:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("sendReport:"), (IMP)ret_void);
    }

    cls = objc_getClass("AMapLogUploader");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("upload"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("startUpload"), (IMP)ret_void);
    }

    cls = objc_getClass("AMapNetFlowManager");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("isBlock"), (IMP)ret_NO);
        safeHookNoOrig(cls, sel_getUid("isBlocked"), (IMP)ret_NO);
        safeHookNoOrig(cls, sel_getUid("checkBlock"), (IMP)ret_NO);
        safeHookNoOrig(cls, sel_getUid("checkNetworkBlock"), (IMP)ret_NO);
    }

    cls = objc_getClass("AMapLog");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("_log:message:level:component:file:function:line:session:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("_queueLogMessage:asynchronously:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("_logMessage:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("logEvent:params:component:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("logError:errorInfo:component:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("logCrash:crashInfo:component:"), (IMP)ret_void);
    }

    cls = objc_getClass("AMapLogManager");
    if (cls) autoHookClassMethodsSafe("AMapLogManager");
}

#pragma mark - 高德系统信息与统计

static void hookAMapSystemInfoAndStats() {
    Class cls = objc_getClass("AMapSystemInfo");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("extractMemoryTotalSize"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("extractMemoryUsedSize"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("extractMemoryFreeSize"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("extractDeviceVersion"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("extractAppUUID"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("extractCPUArch"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("extractDeviceAppHash"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("enterBackground:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("becomeActive:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("resignActive:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("updateLastSwitchActiveTime:"), (IMP)ret_void);
    }

    cls = objc_getClass("AMapStatistics");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("xinfo"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("xinfo_21"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("platinfoWithProduct:version:"), (IMP)ret_empty_dict);
        safeHookNoOrig(cls, sel_getUid("infoStringWithKeys:"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("infoDictionaryWithKeys:"), (IMP)ret_empty_dict);
        safeHookNoOrig(cls, sel_getUid("setupCoordinateWithLat:lon:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("fetchSSIDInfo"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("currentDeviceModel"), (IMP)ret_empty_str);
    }
}

#pragma mark - 字节跳动 Swift 类（自动扫描 @objc 方法）

static void hookByteDanceSwiftClasses() {
    const char *swiftClasses[] = {
        // Salamander 基础
        "_TtC10Salamander8SLDevice",
        "_TtC10Salamander8SLScreen",
        "_TtC10Salamander8SLThread",
        "_TtC10Salamander13SLApplication",
        "_TtC10Salamander16DeviceSystemImpl",
        "_TtC10Salamander10ScreenImpl",
        "_TtC10Salamander11SwiftOCTool",
        "_TtC10Salamander12EventBusImpl",
        "_TtC10Salamander15ApplicationImpl",
        // Salamander BD Foundation
        "_TtC22SalamanderBDFoundation11SLHeimdallr",
        "_TtC22SalamanderBDFoundation11SLJSONUtils",
        "_TtC22SalamanderBDFoundation15SLBDApplication",
        // AnnieX
        "_TtC6AnnieX11APMReporter",
        "_TtC6AnnieX11NetworkImpl",
        "_TtC6AnnieX13HeimdallrImpl",
        "_TtC6AnnieX14HybridSettings",
        "_TtC6AnnieX15AnnieXJSONUtils",
        "_TtC6AnnieX15AnnieXUUIDUtils",
        "_TtC6AnnieX17AnnieXApplication",
        "_TtC6AnnieX17AnnieXStringUtils",
        "_TtC6AnnieX7LogImpl",
        "_TtC6AnnieX8Switches",
        // Bind
        "_TtC4Bind10BindConfig",
        "_TtC4Bind9BindUtils",
        // TempoiOS
        "_TtC8TempoiOS10TempoTrace",
        "_TtC8TempoiOS8TempoApp",
        "_TtC8TempoiOS15TempoSwiperCell",
        "_TtC8TempoiOS15TempoViewWidget",
        "_TtC8TempoiOS16TempoBorderLayer",
        "_TtC8TempoiOS16TempoImageWidget",
        "_TtC8TempoiOS17TempoBuiltInClass",
        "_TtC8TempoiOS17TempoLottieWidget",
        "_TtC8TempoiOS17TempoPipeLineTask",
        "_TtC8TempoiOS17TempoSwiperWidget",
        "_TtC8TempoiOS19TempoSwiperItemView",
        "_TtC8TempoiOS20TempoCountDownWidget",
        "_TtC8TempoiOS20TempoMethodAppModule",
        "_TtC8TempoiOS21TempoBounceViewWidget",
        "_TtC8TempoiOS21TempoDebugRetainCount",
        "_TtC8TempoiOS21TempoScrollViewWidget",
        "_TtC8TempoiOS21TempoSwiperItemWidget",
        "_TtC8TempoiOS25TempoTapGestureRecognizer",
        "_TtC8TempoiOS31TempoLongPressGestureRecognizer",
        // BDADSDK
        "_TtC7BDADSDK12GeckoManager",
        "_TtC7BDADSDK21GeckoEventDelegateImp",
        // BDAResourceKit
        "_TtC18BDAResourceKit_iOS14AdResourceUtil",
        "_TtC18BDAResourceKit_iOS16AdResourceLoader",
        "_TtC18BDAResourceKit_iOS17AdPromiseDeferred",
        "_TtC18BDAResourceKit_iOS19AdStrategyTrackUtil",
        "_TtC18BDAResourceKit_iOS23AdWebViewResourceLoader",
        "_TtC18BDAResourceKit_iOS35AdResourceLoaderEnvironmentStrategy",
        // SalamanderAnnieX
        "_TtC16SalamanderAnnieX13BridgeHandler",
        "_TtC16SalamanderAnnieX15BridgeHandlerV2",
        nil
    };

    for (int i = 0; swiftClasses[i] != nil; i++) {
        autoHookClassMethodsSafe(swiftClasses[i]);
    }
}

#pragma mark - 字节跳动精确 Hook（头文件中有明确方法的类）

static void hookByteDanceGeckoManager() {
    Class cls = objc_getClass("_TtC7BDADSDK12GeckoManager");
    if (!cls) return;
    BYPASS_LOG(@"hooking GeckoManager");
    safeHookNoOrig(cls, sel_getUid("registerAndPreloadCommerceGecko"), (IMP)ret_void);
    safeHookNoOrig(cls, sel_getUid("gurdKitDidSetup"), (IMP)ret_void);
    safeHookNoOrig(cls, sel_getUid("updateGurdPollWith:"), (IMP)ret_void);
    safeHookNoOrig(cls, sel_getUid("updateGurdPollWith:completion:"), (IMP)ret_void);
    safeHookNoOrig(cls, sel_getUid("dataFor:channel:"), (IMP)ret_nil);
    safeHookNoOrig(cls, sel_getUid("hasGeckoResourceFor:"), (IMP)ret_NO);
    safeHookNoOrig(cls, sel_getUid("clearGeckoResourceFor:"), (IMP)ret_void);
    safeHookNoOrig(cls, sel_getUid("geckoAccessKey"), (IMP)ret_empty_str);
}

static void hookByteDanceResourceKit() {
    Class cls = objc_getClass("_TtC18BDAResourceKit_iOS23AdWebViewResourceLoader");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("didReceiveMemoryWarningNotification"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("didReceiveApplicationWillTerminalNotification"), (IMP)ret_void);
    }
}

#pragma mark - 百度系通用 Hook

static void hookBaiduCommon() {
    // 百度常见风控/统计类（防御性 hook，类不存在时自动跳过）
    const char *baiduClasses[] = {
        "BaiduMobStat",
        "BDTuring",
        "BDTuringConfig",
        "BDTuringVerify",
        "BaiduLocation",
        nil
    };
    const char *boolSels[] = {
        "isJailbreak", "isJailbroken", "isDebug", "isDebuggerAttached",
        "isProxy", "isEmulator", nil
    };
    const char *strSels[] = {
        "getDeviceId", "deviceId", "getUUID", "uuid",
        "getRiskToken", "riskToken", "getMetaInfo", nil
    };
    for (int i = 0; baiduClasses[i] != nil; i++) {
        hookSelectorsOnClass(baiduClasses[i], boolSels, (IMP)ret_NO);
        hookSelectorsOnClass(baiduClasses[i], strSels, (IMP)ret_empty_str);
        autoHookClassMethodsSafe(baiduClasses[i]);
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void init() {
    @autoreleasepool {
        BYPASS_LOG(@"AliSecBypass v2.1 loaded (headfile-enhanced)");

        // 阿里系
        hookAliSecXSafeUtilsVariants();
        hookAliSecXReachability();
        hookAliSecXKeychain();
        hookAliSecXCryptoAndStorage();
        hookAliyunIdentity();
        hookAliyunFaceAuth();
        hookDeviceIdentifiers();
        hookMonitors();
        hookAnalytics();
        hookAMapSystemInfoAndStats();

        // 字节系
        hookByteDanceGeckoManager();
        hookByteDanceResourceKit();
        hookByteDanceSwiftClasses();

        // 百度系
        hookBaiduCommon();

        BYPASS_LOG(@"AliSecBypass v2.1 init complete");
    }
}
