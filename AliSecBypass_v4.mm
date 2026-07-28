// FanqieBypass.mm
// 番茄小说/番茄畅听/红果 专用反检测插件 v1.2-fix
// 修复：移除 syscall(opendir/readdir) 避免编译错误，保留核心 C 函数 hook

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <unistd.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <errno.h>

#pragma mark - 日志系统

static NSString *logPath() {
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        path = [paths.firstObject stringByAppendingPathComponent:@"FanqieBypass.log"];
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

#pragma mark - __interpose 宏

#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static struct { \
        const void *replacement; \
        const void *replacee; \
    } _interpose_##_replacee \
    __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(unsigned long)&_replacement, \
        (const void *)(unsigned long)&_replacee \
    };

#pragma mark - 越狱路径检测

static BOOL isJailbreakPath(const char *path) {
    if (!path) return NO;
    return (
        strstr(path, "/Applications/Cydia.app") ||
        strstr(path, "/Library/MobileSubstrate") ||
        strstr(path, "/var/jb") ||
        strstr(path, "/usr/sbin/sshd") ||
        strstr(path, "/etc/apt") ||
        strstr(path, "/var/lib/dpkg") ||
        strstr(path, "/bin/bash") ||
        strstr(path, "/usr/bin/ssh") ||
        strstr(path, "/var/containers/Bundle/tweaks") ||
        strstr(path, "/var/mobile/Library/Preferences/") ||
        strstr(path, ".dylib")
    );
}

static BOOL isInjectedPath(const char *path) {
    if (!path) return NO;
    return (
        strstr(path, "/var/jb") ||
        strstr(path, "tweak") ||
        strstr(path, ".dylib") ||
        strstr(path, "AliSecBypass") ||
        strstr(path, "FanqieBypass") ||
        strstr(path, "substrate") ||
        strstr(path, "dobby") ||
        strstr(path, "ellekit")
    );
}

static BOOL isBlockedEnv(const char *name) {
    if (!name) return NO;
    return (
        strcmp(name, "DYLD_INSERT_LIBRARIES") == 0 ||
        strcmp(name, "DYLD_FRAMEWORK_PATH") == 0 ||
        strcmp(name, "DYLD_LIBRARY_PATH") == 0 ||
        strcmp(name, "MSSafeMode") == 0 ||
        strcmp(name, "_MSSafeMode") == 0 ||
        strcmp(name, "_DYLD_INSERT_LIBRARIES") == 0 ||
        strcmp(name, "DYLD_FORCE_FLAT_NAMESPACE") == 0 ||
        strcmp(name, "DYLD_PRINT_OPTS") == 0 ||
        strcmp(name, "DYLD_PRINT_ENV") == 0
    );
}

#pragma mark - C函数 Hook 实现

static int my_access(const char *path, int mode) {
    if (isJailbreakPath(path)) {
        BYPASS_LOG(@"access blocked: %s", path);
        errno = ENOENT;
        return -1;
    }
    return access(path, mode);
}
DYLD_INTERPOSE(my_access, access);

static int my_stat(const char *path, struct stat *buf) {
    if (isJailbreakPath(path)) {
        BYPASS_LOG(@"stat blocked: %s", path);
        errno = ENOENT;
        return -1;
    }
    return stat(path, buf);
}
DYLD_INTERPOSE(my_stat, stat);

static int my_stat64(const char *path, struct stat64 *buf) {
    if (isJailbreakPath(path)) {
        BYPASS_LOG(@"stat64 blocked: %s", path);
        errno = ENOENT;
        return -1;
    }
    return stat64(path, buf);
}
DYLD_INTERPOSE(my_stat64, stat64);

static int my_lstat(const char *path, struct stat *buf) {
    if (isJailbreakPath(path)) {
        BYPASS_LOG(@"lstat blocked: %s", path);
        errno = ENOENT;
        return -1;
    }
    return lstat(path, buf);
}
DYLD_INTERPOSE(my_lstat, lstat);

static int my_lstat64(const char *path, struct stat64 *buf) {
    if (isJailbreakPath(path)) {
        BYPASS_LOG(@"lstat64 blocked: %s", path);
        errno = ENOENT;
        return -1;
    }
    return lstat64(path, buf);
}
DYLD_INTERPOSE(my_lstat64, lstat64);

static FILE *my_fopen(const char *path, const char *mode) {
    if (isJailbreakPath(path)) {
        BYPASS_LOG(@"fopen blocked: %s", path);
        errno = ENOENT;
        return NULL;
    }
    return fopen(path, mode);
}
DYLD_INTERPOSE(my_fopen, fopen);

static int my_open(const char *path, int oflag, ...) {
    if (isJailbreakPath(path)) {
        BYPASS_LOG(@"open blocked: %s", path);
        errno = ENOENT;
        return -1;
    }
    if (oflag & O_CREAT) {
        va_list ap;
        va_start(ap, oflag);
        mode_t mode = va_arg(ap, int);
        va_end(ap);
        return open(path, oflag, mode);
    }
    return open(path, oflag);
}
DYLD_INTERPOSE(my_open, open);

static void *my_dlopen(const char *path, int mode) {
    if (path && isInjectedPath(path)) {
        BYPASS_LOG(@"dlopen blocked: %s", path);
        return NULL;
    }
    return dlopen(path, mode);
}
DYLD_INTERPOSE(my_dlopen, dlopen);

static BOOL my_dlopen_preflight(const char *path) {
    if (path && isInjectedPath(path)) {
        BYPASS_LOG(@"dlopen_preflight blocked: %s", path);
        return NO;
    }
    return dlopen_preflight(path);
}
DYLD_INTERPOSE(my_dlopen_preflight, dlopen_preflight);

static void *my_dlsym(void *handle, const char *symbol) {
    if (!symbol) return dlsym(handle, symbol);
    if (strstr(symbol, "substrate") || strstr(symbol, "dobby") ||
        strstr(symbol, "ellekit") || strstr(symbol, "MSHook") ||
        strstr(symbol, "DobbyHook")) {
        BYPASS_LOG(@"dlsym blocked: %s", symbol);
        return NULL;
    }
    return dlsym(handle, symbol);
}
DYLD_INTERPOSE(my_dlsym, dlsym);

static char *my_getenv(const char *name) {
    if (isBlockedEnv(name)) {
        BYPASS_LOG(@"getenv blocked: %s", name);
        return NULL;
    }
    return getenv(name);
}
DYLD_INTERPOSE(my_getenv, getenv);

static int my_setenv(const char *name, const char *value, int overwrite) {
    if (isBlockedEnv(name)) {
        BYPASS_LOG(@"setenv blocked: %s", name);
        return 0;
    }
    return setenv(name, value, overwrite);
}
DYLD_INTERPOSE(my_setenv, setenv);

static int my_unsetenv(const char *name) {
    if (isBlockedEnv(name)) {
        BYPASS_LOG(@"unsetenv blocked: %s", name);
        return 0;
    }
    return unsetenv(name);
}
DYLD_INTERPOSE(my_unsetenv, unsetenv);

static int my_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == 0) { // PT_DENY_ATTACH = 0 on iOS
        BYPASS_LOG(@"ptrace PT_DENY_ATTACH blocked");
        return 0;
    }
    return ptrace(request, pid, addr, data);
}
DYLD_INTERPOSE(my_ptrace, ptrace);

static int my_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (namelen >= 4 && name[0] == 1 && name[1] == 14) { // CTL_KERN=1, KERN_PROC=14
        BYPASS_LOG(@"sysctl KERN_PROC blocked");
        if (oldlenp) *oldlenp = 0;
        return 0;
    }
    return sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}
DYLD_INTERPOSE(my_sysctl, sysctl);

static int my_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!name) return sysctlbyname(name, oldp, oldlenp, newp, newlen);
    if (strstr(name, "kern.proc") || strstr(name, "security.mac") ||
        strstr(name, "vm.mmap") || strstr(name, "hw.machine")) {
        BYPASS_LOG(@"sysctlbyname blocked: %s", name);
        if (oldlenp) *oldlenp = 0;
        return 0;
    }
    return sysctlbyname(name, oldp, oldlenp, newp, newlen);
}
DYLD_INTERPOSE(my_sysctlbyname, sysctlbyname);

#pragma mark - ObjC Hook 工具

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

        if (strcmp(selName, "init") == 0 ||
            strcmp(selName, "dealloc") == 0 ||
            strcmp(selName, ".cxx_destruct") == 0 ||
            strncmp(selName, "initWith", 8) == 0 ||
            strcmp(selName, "alloc") == 0 ||
            strcmp(selName, "new") == 0 ||
            strcmp(selName, "copy") == 0 ||
            strcmp(selName, "copyWithZone:") == 0 ||
            strcmp(selName, "mutableCopyWithZone:") == 0 ||
            strcmp(selName, "description") == 0 ||
            strcmp(selName, "debugDescription") == 0 ||
            strcmp(selName, "hash") == 0 ||
            strcmp(selName, "superclass") == 0 ||
            strcmp(selName, "class") == 0 ||
            strcmp(selName, "isEqual:") == 0 ||
            strcmp(selName, "isKindOfClass:") == 0 ||
            strcmp(selName, "isMemberOfClass:") == 0 ||
            strcmp(selName, "respondsToSelector:") == 0 ||
            strcmp(selName, "conformsToProtocol:") == 0 ||
            strcmp(selName, "performSelector:") == 0 ||
            strcmp(selName, "performSelector:withObject:") == 0 ||
            strcmp(selName, "performSelector:withObject:withObject:") == 0 ||
            strcmp(selName, "forwardingTargetForSelector:") == 0 ||
            strcmp(selName, "methodSignatureForSelector:") == 0 ||
            strcmp(selName, "forwardInvocation:") == 0 ||
            strcmp(selName, "doesNotRecognizeSelector:") == 0 ||
            strcmp(selName, "zone") == 0 ||
            strcmp(selName, "autorelease") == 0 ||
            strcmp(selName, "retain") == 0 ||
            strcmp(selName, "release") == 0 ||
            strcmp(selName, "retainCount") == 0) {
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
            } else if (strstr(selName, "String") || strstr(selName, "str") || strstr(selName, "Name") || strstr(selName, "Text") || strstr(selName, "URL") || strstr(selName, "Path") || strstr(selName, "Key")) {
                stub = (IMP)ret_empty_str;
            } else {
                stub = (IMP)ret_nil;
            }
        } else if (retType == '*' || retType == ':' || retType == '^' || retType == '?') {
            stub = (IMP)ret_zero_ll;
        } else {
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

static void batchAutoHook(const char **classNames) {
    for (int i = 0; classNames[i] != nil; i++) {
        autoHookClassMethodsSafe(classNames[i]);
    }
}

#pragma mark - 阿里系

static void hookAliSecXSafeUtilsVariants() {
    const char *variants[] = { "AliSecXSafeUtilsMXXTIY", "AliSecXSafeUtilsZZZX", nil };
    const char *strSels[] = {
        "descriptor", "secStatus", "safeDescriptor", "securityStatus",
        "checkStatus", "deviceFingerprint", "riskToken", "envInfo", nil
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

static void hookAliSecXKeychain() {
    const char *clses[] = {
        "AliSecXSSKeychain", "AliSecXSSKeychainMXXT",
        "AliSecXSSKeychainQuery", "AliSecXSSKeychainQueryMXXT", nil
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
        "AliSecXCryptoGTMBase64", "AliSecXFileOp", "AliSecXFileOpMXXT",
        "AliSecXLocalStorage", "AliSecXLocalStorageMXXT", "AliSecXLocalStorageUtils", nil
    };
    batchAutoHook(clses);
}

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

static void hookDeviceIdentifiers() {
    const char *classes[] = {
        "AidManager", "AMapADIUManager", "AMapDeviceInfo", "UTDevice", "UTDID",
        "OpenUDID", "AliSecuritySDK", "AliSecXDeviceInfoMXXTIY", "AliSecXDeviceInfoZZZX",
        "AliSecXPhoneInfoHolderMXXTIY", "AliSecXPhoneInfoHolderZZZX", nil
    };
    const char *selectors[] = {
        "getAid", "aid", "getUtdid", "utdid", "getAdiu", "adiu",
        "openUDIDValue", "deviceId", "uniqueDeviceIdentifier", "getUUID", "uuid", "ADIU", nil
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

#pragma mark - 百度系

static void hookBaiduCommon() {
    const char *baiduClasses[] = {
        "BaiduMobStat", "BDTuring", "BDTuringConfig", "BDTuringVerify", "BaiduLocation", nil
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

#pragma mark - 字节系 Swift 类全面 autoHook

static void hookByteDanceSwiftClasses() {
    const char *salamander[] = {
        "_TtC10Salamander8SLDevice", "_TtC10Salamander8SLScreen", "_TtC10Salamander8SLThread",
        "_TtC10Salamander13SLApplication", "_TtC10Salamander16DeviceSystemImpl",
        "_TtC10Salamander10ScreenImpl", "_TtC10Salamander11SwiftOCTool",
        "_TtC10Salamander12EventBusImpl", "_TtC10Salamander15ApplicationImpl",
        "_TtC22SalamanderBDFoundation11SLHeimdallr", "_TtC22SalamanderBDFoundation11SLJSONUtils",
        "_TtC22SalamanderBDFoundation15SLBDApplication", nil
    };
    batchAutoHook(salamander);

    const char *annieX[] = {
        "_TtC6AnnieX11APMReporter", "_TtC6AnnieX11NetworkImpl", "_TtC6AnnieX13HeimdallrImpl",
        "_TtC6AnnieX14HybridSettings", "_TtC6AnnieX15AnnieXJSONUtils", "_TtC6AnnieX15AnnieXUUIDUtils",
        "_TtC6AnnieX17AnnieXApplication", "_TtC6AnnieX17AnnieXStringUtils", "_TtC6AnnieX7LogImpl",
        "_TtC6AnnieX8Switches", nil
    };
    batchAutoHook(annieX);

    const char *bdad[] = {
        "_TtC7BDADSDK12GeckoManager", "_TtC7BDADSDK21GeckoEventDelegateImp", nil
    };
    batchAutoHook(bdad);

    const char *bdar[] = {
        "_TtC18BDAResourceKit_iOS14AdResourceUtil", "_TtC18BDAResourceKit_iOS16AdResourceLoader",
        "_TtC18BDAResourceKit_iOS17AdPromiseDeferred", "_TtC18BDAResourceKit_iOS19AdStrategyTrackUtil",
        "_TtC18BDAResourceKit_iOS23AdWebViewResourceLoader",
        "_TtC18BDAResourceKit_iOS35AdResourceLoaderEnvironmentStrategy", nil
    };
    batchAutoHook(bdar);

    const char *tempo[] = {
        "_TtC8TempoiOS10TempoTrace", "_TtC8TempoiOS8TempoApp", "_TtC8TempoiOS15TempoSwiperCell",
        "_TtC8TempoiOS15TempoViewWidget", "_TtC8TempoiOS16TempoBorderLayer",
        "_TtC8TempoiOS16TempoImageWidget", "_TtC8TempoiOS17TempoBuiltInClass",
        "_TtC8TempoiOS17TempoLottieWidget", "_TtC8TempoiOS17TempoPipeLineTask",
        "_TtC8TempoiOS17TempoSwiperWidget", "_TtC8TempoiOS19TempoSwiperItemView",
        "_TtC8TempoiOS20TempoCountDownWidget", "_TtC8TempoiOS20TempoMethodAppModule",
        "_TtC8TempoiOS21TempoBounceViewWidget", "_TtC8TempoiOS21TempoDebugRetainCount",
        "_TtC8TempoiOS21TempoScrollViewWidget", "_TtC8TempoiOS21TempoSwiperItemWidget",
        "_TtC8TempoiOS25TempoTapGestureRecognizer", "_TtC8TempoiOS31TempoLongPressGestureRecognizer", nil
    };
    batchAutoHook(tempo);

    const char *bind[] = { "_TtC4Bind10BindConfig", "_TtC4Bind9BindUtils", nil };
    batchAutoHook(bind);

    const char *bridge[] = {
        "_TtC16SalamanderAnnieX13BridgeHandler", "_TtC16SalamanderAnnieX15BridgeHandlerV2", nil
    };
    batchAutoHook(bridge);

    const char *ies[] = {
        "_TtC14IESIMGroupImpl13GroupInfoUtil", "_TtC14IESIMGroupImpl13GroupMuteUtil",
        "_TtC14IESIMGroupImpl18GroupBasicInfoUtil", "_TtC14IESIMGroupImpl18GroupLinkComponent",
        "_TtC14IESIMGroupImpl24ChatSettingsCheckService", "_TtC14IESIMGroupImpl25GroupAvatarPreviewService",
        "_TtC14IESIMGroupImpl26GroupParticipantController", "_TtC14IESIMGroupImpl29GroupOtherSceneStorageService",
        "_TtC19IESLiveServiceSwift16IESLiveDCEventID", "_TtC19IESLiveServiceSwift21IESLiveDCSharedDataID",
        "_TtC26IESIMConversationSwiftImpl21IMB2CQuestionsService",
        "_TtC33IESIMConversationSettingSwiftImpl20GroupSettingsService", nil
    };
    batchAutoHook(ies);

    const char *yata[] = {
        "_TtC14YataEventChain14ToastEventImpl", "_TtC14YataEventChain16RequestEventImpl",
        "_TtC14YataEventChain16TrackerEventImpl", "_TtC14YataEventChain19OpenSchemaEventImpl", nil
    };
    batchAutoHook(yata);

    const char *iap[] = { "_TtC15CJSwiftIAPStore14CJSwiftIAPTool", "_TtC15CJSwiftIAPStore14CJSwiftIAPUtil", nil };
    batchAutoHook(iap);

    const char *fq[] = {
        "_TtC18FQOriginalSaaSImpl17FQOriginalManager",
        "_TtC18FQOriginalSaaSImpl24SSOriginaUISimpleLoading",
        "_TtC18FQOriginalSaaSImpl29FQOriginalImageCropperManager", nil
    };
    batchAutoHook(fq);

    const char *other[] = {
        "_TtC12FQHybridImpl20FQHybridDefaultTheme",
        "_TtC10rts2native10JsonHelper", "_TtC10rts2native10Uint8Array",
        "_TtC10rts2native4Math", "_TtC10rts2native4Type",
        "_TtC10rts2native6Arrays", "_TtC10rts2native6Object",
        "_TtC10rts2native7console", nil
    };
    batchAutoHook(other);
}

#pragma mark - 字节系关键类精确 hook

static void (*orig_AnnieCheckPermission_call)(id, SEL, id, id);
static void hook_AnnieCheckPermission_call(id self, SEL _cmd, id param, id completion) {
    if (completion) {
        void (^cb)(id) = completion;
        cb(@{@"status": @1});
    }
}

static void (*orig_AnnieRequestPermission_call)(id, SEL, id, id);
static void hook_AnnieRequestPermission_call(id self, SEL _cmd, id param, id completion) {
    if (completion) {
        void (^cb)(id) = completion;
        cb(@{@"status": @1});
    }
}

static void (*orig_AnnieGetUserInfo_call)(id, SEL, id, id);
static void hook_AnnieGetUserInfo_call(id self, SEL _cmd, id param, id completion) {
    if (completion) {
        void (^cb)(id) = completion;
        cb(@{
            @"isLogin": @YES,
            @"userInfo": @{
                @"shortID": @"12345",
                @"userID": @"12345",
                @"secUserID": @"sec12345",
                @"nickName": @"User",
                @"avatarURL": @"",
                @"isBoundPhone": @YES
            }
        });
    }
}

static void (*orig_AnnieTraceEvent_traceBegin)(id, SEL, id, id);
static void hook_AnnieTraceEvent_traceBegin(id self, SEL _cmd, id name, id info) {}

static void (*orig_AnnieTraceEvent_traceEnd)(id, SEL, id);
static void hook_AnnieTraceEvent_traceEnd(id self, SEL _cmd, id name) {}

static void (*orig_AnnieTraceEvent_traceInstant)(id, SEL, id);
static void hook_AnnieTraceEvent_traceInstant(id self, SEL _cmd, id name) {}

static void hookByteDanceKeyClasses() {
    Class cls;

    cls = objc_getClass("_TtC7BDADSDK12GeckoManager");
    if (cls) {
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

    cls = objc_getClass("_TtC18BDAResourceKit_iOS23AdWebViewResourceLoader");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("didReceiveMemoryWarningNotification"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("didReceiveApplicationWillTerminalNotification"), (IMP)ret_void);
    }

    cls = objc_getClass("AnnieCheckPermissionMethodImpl");
    if (cls) safeHook(cls, sel_getUid("callWithParamModel:completionHandler:"), (IMP)hook_AnnieCheckPermission_call, (IMP *)&orig_AnnieCheckPermission_call);

    cls = objc_getClass("AnnieRequestPermissionMethodImpl");
    if (cls) safeHook(cls, sel_getUid("callWithParamModel:completionHandler:"), (IMP)hook_AnnieRequestPermission_call, (IMP *)&orig_AnnieRequestPermission_call);

    cls = objc_getClass("AnnieGetUserInfoMethodImpl");
    if (cls) safeHook(cls, sel_getUid("callWithParamModel:completionHandler:"), (IMP)hook_AnnieGetUserInfo_call, (IMP *)&orig_AnnieGetUserInfo_call);

    cls = objc_getClass("AnnieTraceEventImpl");
    if (cls) {
        safeHook(cls, sel_getUid("traceBeginSectionWithName:debugInfo:"), (IMP)hook_AnnieTraceEvent_traceBegin, (IMP *)&orig_AnnieTraceEvent_traceBegin);
        safeHook(cls, sel_getUid("traceEndSectionWithName:"), (IMP)hook_AnnieTraceEvent_traceEnd, (IMP *)&orig_AnnieTraceEvent_traceEnd);
        safeHook(cls, sel_getUid("traceInstantWithName:"), (IMP)hook_AnnieTraceEvent_traceInstant, (IMP *)&orig_AnnieTraceEvent_traceInstant);
    }

    cls = objc_getClass("AnnieSendLogV3Impl");
    if (cls) safeHookNoOrig(cls, sel_getUid("methodName"), (IMP)ret_empty_str);

    cls = objc_getClass("AnnieLiveReportAggregateALogMethodImpl");
    if (cls) safeHookNoOrig(cls, sel_getUid("callWithParamModel:completionHandler:"), (IMP)ret_void);

    cls = objc_getClass("AnnieWebViewInterceptor");
    if (cls) autoHookClassMethodsSafe("AnnieWebViewInterceptor");

    cls = objc_getClass("AnnieXAccount");
    if (cls) safeHookNoOrig(cls, sel_getUid("accessTokenForAuthPlatform"), (IMP)ret_empty_str);

    cls = objc_getClass("AnnieGlobalProps");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("netType"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("osLanguage"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("resolverWithSchema:context:"), (IMP)ret_nil);
    }

    cls = objc_getClass("AnnieXContainerContextModel");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("collectContainerContext:value:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("annieXIsAsyncCreateData"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("annieXEngineIsFromCache"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("annieXEngineIsWarmup"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("annieXEngineIsReuse"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("annieXCardModelIsReuse"), (IMP)ret_empty_str);
        safeHookNoOrig(cls, sel_getUid("annieXPageIsConcurrentLoad"), (IMP)ret_empty_str);
    }

    cls = objc_getClass("AnnieXContainerTimingModel");
    if (cls) safeHookNoOrig(cls, sel_getUid("collectTiming:timestamp:"), (IMP)ret_void);

    cls = objc_getClass("AnnieLatchMonitorModule");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("result:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("perfMetric:"), (IMP)ret_void);
    }

    cls = objc_getClass("AnnieContainerVCRouterInterceptor");
    if (cls) safeHookNoOrig(cls, sel_getUid("customHandleWithParams:"), (IMP)ret_NO);

    cls = objc_getClass("AnnieDynamicModel");
    if (cls) autoHookClassMethodsSafe("AnnieDynamicModel");

    cls = objc_getClass("AnnieSpeechRecognitionController");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("startRecognitionWithParams:completion:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("stopRecognition:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("onMessageWithType:andData:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("sendAsrStateChangeWithEventType:message:"), (IMP)ret_void);
    }

    cls = objc_getClass("AnnieLLMSpeechRecognitionController");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("startRecognitionWithParams:completion:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("stopRecognition:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("onMessageWithType:andData:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("sendAsrStateChangeWithEventType:message:"), (IMP)ret_void);
    }

    cls = objc_getClass("AnnieAudioRecorder");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("prepareToRecord"), (IMP)ret_NO);
        safeHookNoOrig(cls, sel_getUid("startRecord"), (IMP)ret_NO);
        safeHookNoOrig(cls, sel_getUid("stopRecord"), (IMP)ret_void);
    }

    cls = objc_getClass("AnnieSpeechRecognizer");
    if (cls) {
        safeHookNoOrig(cls, sel_getUid("startRecognitionWithAppKey:token:sosSilenceTimeout:eosSilenceTimeout:sentenceMaxSeconds:listener:"), (IMP)ret_NO);
        safeHookNoOrig(cls, sel_getUid("setupSAMIWithAppKey:token:sosSilenceTimeout:eosSilenceTimeout:sentenceMaxSeconds:listener:"), (IMP)ret_NO);
        safeHookNoOrig(cls, sel_getUid("recognizePCMAudioData:withDataSize:"), (IMP)ret_void);
        safeHookNoOrig(cls, sel_getUid("stopRecognition"), (IMP)ret_void);
    }

    BYPASS_LOG(@"ByteDance key classes hooked");
}

#pragma mark - 系统 API 层 Hook（关键兜底）

static BOOL (*orig_fileExistsAtPath)(id, SEL, NSString*);
static BOOL hook_fileExistsAtPath(id self, SEL _cmd, NSString *path) {
    if (path && isJailbreakPath(path.UTF8String)) {
        BYPASS_LOG(@"NSFileManager blocked: %@", path);
        return NO;
    }
    return orig_fileExistsAtPath(self, _cmd, path);
}

static BOOL (*orig_fileExistsAtPath_isDirectory)(id, SEL, NSString*, BOOL*);
static BOOL hook_fileExistsAtPath_isDirectory(id self, SEL _cmd, NSString *path, BOOL *isDir) {
    if (path && isJailbreakPath(path.UTF8String)) {
        BYPASS_LOG(@"NSFileManager blocked(isDir): %@", path);
        if (isDir) *isDir = NO;
        return NO;
    }
    return orig_fileExistsAtPath_isDirectory(self, _cmd, path, isDir);
}

static NSArray *(*orig_contentsOfDirectoryAtPath_error)(id, SEL, NSString*, NSError**);
static NSArray *hook_contentsOfDirectoryAtPath_error(id self, SEL _cmd, NSString *path, NSError **error) {
    if (path && isJailbreakPath(path.UTF8String)) {
        BYPASS_LOG(@"NSFileManager blocked dir: %@", path);
        return @[];
    }
    return orig_contentsOfDirectoryAtPath_error(self, _cmd, path, error);
}

static NSArray *(*orig_contentsOfDirectoryAtURL_includingPropertiesForKeys_options_error)(id, SEL, NSURL*, NSArray*, NSUInteger, NSError**);
static NSArray *hook_contentsOfDirectoryAtURL_includingPropertiesForKeys_options_error(id self, SEL _cmd, NSURL *url, NSArray *keys, NSUInteger mask, NSError **error) {
    if (url && url.path && isJailbreakPath(url.path.UTF8String)) {
        BYPASS_LOG(@"NSFileManager blocked URL dir: %@", url.path);
        return @[];
    }
    return orig_contentsOfDirectoryAtURL_includingPropertiesForKeys_options_error(self, _cmd, url, keys, mask, error);
}

static void hookNSFileManager() {
    Class cls = objc_getClass("NSFileManager");
    if (!cls) return;
    safeHook(cls, sel_getUid("fileExistsAtPath:"), (IMP)hook_fileExistsAtPath, (IMP *)&orig_fileExistsAtPath);
    safeHook(cls, sel_getUid("fileExistsAtPath:isDirectory:"), (IMP)hook_fileExistsAtPath_isDirectory, (IMP *)&orig_fileExistsAtPath_isDirectory);
    safeHook(cls, sel_getUid("contentsOfDirectoryAtPath:error:"), (IMP)hook_contentsOfDirectoryAtPath_error, (IMP *)&orig_contentsOfDirectoryAtPath_error);
    safeHook(cls, sel_getUid("contentsOfDirectoryAtURL:includingPropertiesForKeys:options:error:"), (IMP)hook_contentsOfDirectoryAtURL_includingPropertiesForKeys_options_error, (IMP *)&orig_contentsOfDirectoryAtURL_includingPropertiesForKeys_options_error);
    BYPASS_LOG(@"NSFileManager hooked");
}

static NSArray *(*orig_allBundles)(Class, SEL);
static NSArray *hook_allBundles(Class self, SEL _cmd) {
    NSArray *orig = orig_allBundles(self, _cmd);
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSBundle *bundle in orig) {
        NSString *path = bundle.bundlePath;
        if (path && isInjectedPath(path.UTF8String)) {
            BYPASS_LOG(@"NSBundle filtered: %@", path);
            continue;
        }
        [filtered addObject:bundle];
    }
    return filtered;
}

static NSArray *(*orig_allFrameworks)(Class, SEL);
static NSArray *hook_allFrameworks(Class self, SEL _cmd) {
    NSArray *orig = orig_allFrameworks(self, _cmd);
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSBundle *bundle in orig) {
        NSString *path = bundle.bundlePath;
        if (path && isInjectedPath(path.UTF8String)) {
            BYPASS_LOG(@"NSFramework filtered: %@", path);
            continue;
        }
        [filtered addObject:bundle];
    }
    return filtered;
}

static NSString *(*orig_bundlePath)(id, SEL);
static NSString *hook_bundlePath(id self, SEL _cmd) {
    NSString *orig = orig_bundlePath(self, _cmd);
    if (orig && isInjectedPath(orig.UTF8String)) {
        return @"/System/Library/Frameworks/Foundation.framework";
    }
    return orig;
}

static NSString *(*orig_executablePath)(id, SEL);
static NSString *hook_executablePath(id self, SEL _cmd) {
    NSString *orig = orig_executablePath(self, _cmd);
    if (orig && [orig containsString:@".dylib"]) {
        return nil;
    }
    return orig;
}

static void hookNSBundle() {
    Class cls = objc_getClass("NSBundle");
    if (!cls) return;
    Method m1 = class_getClassMethod(cls, sel_getUid("allBundles"));
    if (m1) {
        orig_allBundles = (NSArray *(*)(Class, SEL))method_getImplementation(m1);
        method_setImplementation(m1, (IMP)hook_allBundles);
    }
    Method m2 = class_getClassMethod(cls, sel_getUid("allFrameworks"));
    if (m2) {
        orig_allFrameworks = (NSArray *(*)(Class, SEL))method_getImplementation(m2);
        method_setImplementation(m2, (IMP)hook_allFrameworks);
    }
    safeHook(cls, sel_getUid("bundlePath"), (IMP)hook_bundlePath, (IMP *)&orig_bundlePath);
    safeHook(cls, sel_getUid("executablePath"), (IMP)hook_executablePath, (IMP *)&orig_executablePath);
    BYPASS_LOG(@"NSBundle hooked");
}

static NSDictionary *(*orig_environment)(id, SEL);
static NSDictionary *hook_environment(id self, SEL _cmd) {
    NSMutableDictionary *env = [orig_environment(self, _cmd) mutableCopy];
    [env removeObjectForKey:@"DYLD_INSERT_LIBRARIES"];
    [env removeObjectForKey:@"DYLD_FRAMEWORK_PATH"];
    [env removeObjectForKey:@"DYLD_LIBRARY_PATH"];
    [env removeObjectForKey:@"MSSafeMode"];
    [env removeObjectForKey:@"_MSSafeMode"];
    [env removeObjectForKey:@"_DYLD_INSERT_LIBRARIES"];
    return env;
}

static NSArray *(*orig_arguments)(id, SEL);
static NSArray *hook_arguments(id self, SEL _cmd) {
    NSArray *orig = orig_arguments(self, _cmd);
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSString *arg in orig) {
        if ([arg containsString:@"-Tweak"] || [arg containsString:@"-substrate"] || [arg containsString:@"-dobby"]) {
            continue;
        }
        [filtered addObject:arg];
    }
    return filtered;
}

static void hookNSProcessInfo() {
    Class cls = objc_getClass("NSProcessInfo");
    if (!cls) return;
    safeHook(cls, sel_getUid("environment"), (IMP)hook_environment, (IMP *)&orig_environment);
    safeHook(cls, sel_getUid("arguments"), (IMP)hook_arguments, (IMP *)&orig_arguments);
    BYPASS_LOG(@"NSProcessInfo hooked");
}

static NSUUID *hook_identifierForVendor(id self, SEL _cmd) {
    static NSUUID *uuid = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        uuid = [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000000"];
    });
    return uuid;
}

static void hookUIDevice() {
    Class cls = objc_getClass("UIDevice");
    if (!cls) return;
    safeHook(cls, sel_getUid("identifierForVendor"), (IMP)hook_identifierForVendor, NULL);
    BYPASS_LOG(@"UIDevice hooked");
}

static BOOL (*orig_canOpenURL)(id, SEL, NSURL*);
static BOOL hook_canOpenURL(id self, SEL _cmd, NSURL *url) {
    NSString *scheme = url.scheme;
    if ([scheme isEqualToString:@"cydia"] ||
        [scheme isEqualToString:@"sileo"] ||
        [scheme isEqualToString:@"zbra"] ||
        [scheme isEqualToString:@"filza"]) {
        BYPASS_LOG(@"UIApplication canOpenURL blocked: %@", scheme);
        return NO;
    }
    return orig_canOpenURL(self, _cmd, url);
}

static void hookUIApplication() {
    Class cls = objc_getClass("UIApplication");
    if (!cls) return;
    safeHook(cls, sel_getUid("canOpenURL:"), (IMP)hook_canOpenURL, (IMP *)&orig_canOpenURL);
    BYPASS_LOG(@"UIApplication hooked");
}

static BOOL isBlockedHost(NSString *host) {
    if (!host) return NO;
    NSString *low = host.lowercaseString;
    return (
        [low containsString:@"log"] ||
        [low containsString:@"mon"] ||
        [low containsString:@"apm"] ||
        [low containsString:@"security"] ||
        [low containsString:@"risk"] ||
        [low containsString:@"snssdk"] ||
        [low containsString:@"bytedance"] ||
        [low containsString:@"byteoversea"] ||
        [low containsString:@"toutiao"] ||
        [low containsString:@"douyin"] ||
        [low containsString:@"ies"] ||
        [low containsString:@"bdurl"] ||
        [low containsString:@"pangolin"] ||
        [low containsString:@"gromore"] ||
        [low containsString:@"ttapis"] ||
        [low containsString:@"byteimg"] ||
        [low containsString:@"volces"] ||
        [low containsString:@"helo"]
    );
}

static NSURLSessionDataTask *(*orig_dataTaskWithRequest)(id, SEL, NSURLRequest*);
static NSURLSessionDataTask *hook_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request) {
    NSURL *url = request.URL;
    if (url && isBlockedHost(url.host)) {
        BYPASS_LOG(@"NSURLSession blocked: %@", url.absoluteString);
        NSMutableURLRequest *mutReq = [request mutableCopy];
        mutReq.URL = [NSURL URLWithString:@"about:blank"];
        return orig_dataTaskWithRequest(self, _cmd, mutReq);
    }
    return orig_dataTaskWithRequest(self, _cmd, request);
}

static NSURLSessionDataTask *(*orig_dataTaskWithURL)(id, SEL, NSURL*);
static NSURLSessionDataTask *hook_dataTaskWithURL(id self, SEL _cmd, NSURL *url) {
    if (url && isBlockedHost(url.host)) {
        BYPASS_LOG(@"NSURLSession blocked URL: %@", url.absoluteString);
        return orig_dataTaskWithURL(self, _cmd, [NSURL URLWithString:@"about:blank"]);
    }
    return orig_dataTaskWithURL(self, _cmd, url);
}

static void hookNSURLSession() {
    Class cls = objc_getClass("NSURLSession");
    if (!cls) return;
    safeHook(cls, sel_getUid("dataTaskWithRequest:"), (IMP)hook_dataTaskWithRequest, (IMP *)&orig_dataTaskWithRequest);
    safeHook(cls, sel_getUid("dataTaskWithURL:"), (IMP)hook_dataTaskWithURL, (IMP *)&orig_dataTaskWithURL);
    BYPASS_LOG(@"NSURLSession hooked");
}

#pragma mark - Constructor

__attribute__((constructor))
static void init() {
    @autoreleasepool {
        BYPASS_LOG(@"FanqieBypass v1.2-fix loaded (C+ObjC dual layer)");

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

        hookBaiduCommon();

        hookByteDanceSwiftClasses();
        hookByteDanceKeyClasses();

        hookNSFileManager();
        hookNSBundle();
        hookNSProcessInfo();
        hookUIDevice();
        hookUIApplication();
        hookNSURLSession();

        BYPASS_LOG(@"FanqieBypass v1.2-fix init complete");
    }
}
