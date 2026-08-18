//
//  AliSecBypass_v4_2_nodobby.mm
//  番茄小说脱壳检测绕过插件 (无 Dobby 版)
//  纯 fishhook，hook __syscall 拦截 syscall(169)
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <sys/syscall.h>
#import <fcntl.h>
#import <stdarg.h>
#import <string.h>
#import <stdint.h>
#import <unistd.h>
#import "fishhook.h"

#pragma mark - Logger

static NSString *bypassLogPath(void) {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        path = [[paths.firstObject stringByAppendingPathComponent:@"AliBypass.log"] copy];
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

#pragma mark - Jailbreak Path Checker

static BOOL isJailbreakPath(const char *path) {
    if (!path) return NO;
    static const char *jbPaths[] = {
        "/Applications/Cydia.app",
        "/Library/MobileSubstrate",
        "/var/lib/cydia",
        "/usr/sbin/frida-server",
        "/etc/apt",
        "/usr/bin/ssh",
        "/var/jb",
        "/private/var/lib/apt",
        "/User/Applications/",
        "/Library/MobileSubstrate/DynamicLibraries/",
        "/Library/MobileSubstrate/CydiaSubstrate.dylib",
        NULL
    };
    for (int i = 0; jbPaths[i]; i++) {
        if (strstr(path, jbPaths[i])) return YES;
    }
    return NO;
}

#pragma mark - C Function Hooks

static int (*orig_csops)(pid_t, unsigned int, void *, size_t);
static int fake_csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize) {
    int ret = orig_csops(pid, ops, useraddr, usersize);
    if (ret != 0) {
        BYPASS_LOG(@"[csops] ops=%u failed, forcing success", ops);
        ret = 0;
    }
    if (ops == 0 && useraddr && usersize >= 4) {
        *(uint32_t *)useraddr = 0x00020001;
        BYPASS_LOG(@"[csops] CS_OPS_STATUS -> forged valid");
    } else if ((ops == 11 || ops == 16) && useraddr) {
        size_t limit = usersize < 64 ? usersize : 64;
        memset(useraddr, 0, limit);
        BYPASS_LOG(@"[csops] ops=%u -> forged pass", ops);
    }
    return ret;
}

static int (*orig_access)(const char *, int);
static int fake_access(const char *path, int mode) {
    if (isJailbreakPath(path)) {
        BYPASS_LOG(@"[access] blocked: %s", path);
        return -1;
    }
    return orig_access(path, mode);
}

static int (*orig_stat)(const char *, void *);
static int fake_stat(const char *path, void *buf) {
    if (isJailbreakPath(path)) {
        BYPASS_LOG(@"[stat] blocked: %s", path);
        return -1;
    }
    return orig_stat(path, buf);
}

static int (*orig_stat64)(const char *, void *);
static int fake_stat64(const char *path, void *buf) {
    if (isJailbreakPath(path)) {
        BYPASS_LOG(@"[stat64] blocked: %s", path);
        return -1;
    }
    return orig_stat64(path, buf);
}

static int (*orig_open)(const char *, int, ...);
static int fake_open(const char *path, int flags, ...) {
    if (isJailbreakPath(path)) {
        BYPASS_LOG(@"[open] blocked: %s", path);
        return -1;
    }
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        int mode = va_arg(ap, int);
        va_end(ap);
        return orig_open(path, flags, mode);
    }
    return orig_open(path, flags);
}

static FILE *(*orig_fopen)(const char *, const char *);
static FILE *fake_fopen(const char *path, const char *mode) {
    if (isJailbreakPath(path)) {
        BYPASS_LOG(@"[fopen] blocked: %s", path);
        return NULL;
    }
    return orig_fopen(path, mode);
}

static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int fake_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (ret == 0 && namelen >= 4 && name[0] == CTL_KERN && name[1] == KERN_PROC && oldp && oldlenp) {
        size_t len = *oldlenp;
        if (len >= 36) {
            uint32_t *p_flag = (uint32_t *)((uint8_t *)oldp + 32);
            if (*p_flag & 0x800) {
                *p_flag &= ~0x800;
                BYPASS_LOG(@"[sysctl] cleared P_TRACED");
            }
        }
    }
    return ret;
}

static int (*orig_ptrace)(int, pid_t, caddr_t, int);
static int fake_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == 0) {
        BYPASS_LOG(@"[ptrace] PT_DENY_ATTACH blocked");
        return 0;
    }
    return orig_ptrace(request, pid, addr, data);
}

static char *(*orig_getenv)(const char *);
static char *fake_getenv(const char *name) {
    if (name && (strcmp(name, "DYLD_INSERT_LIBRARIES") == 0 ||
                 strcmp(name, "DYLD_FRAMEWORK_PATH") == 0 ||
                 strcmp(name, "DYLD_LIBRARY_PATH") == 0)) {
        BYPASS_LOG(@"[getenv] blocked: %s", name);
        return NULL;
    }
    return orig_getenv(name);
}

// ==================== CRITICAL: hook __syscall (libc internal wrapper) ====================
// fishhook can't hook "syscall" directly on iOS (inlined svc), but can hook "__syscall"

static int (*orig___syscall)(int, ...);

static int fake___syscall(int number, ...) {
    va_list ap;
    va_start(ap, number);

    if (number == SYS_csops) {
        pid_t pid = va_arg(ap, pid_t);
        unsigned int ops = va_arg(ap, unsigned int);
        void *useraddr = va_arg(ap, void *);
        size_t usersize = va_arg(ap, size_t);
        va_end(ap);

        BYPASS_LOG(@"[__syscall] SYS_csops(pid=%d, ops=%u) intercepted", pid, ops);

        int ret = orig___syscall(SYS_csops, pid, ops, useraddr, usersize);
        if (ret != 0) {
            BYPASS_LOG(@"[__syscall] csops failed, forcing success");
            ret = 0;
        }
        if (ops == 0 && useraddr && usersize >= 4) {
            *(uint32_t *)useraddr = 0x00020001;
            BYPASS_LOG(@"[__syscall] csops CS_OPS_STATUS -> forged valid");
        } else if ((ops == 11 || ops == 16) && useraddr) {
            size_t limit = usersize < 64 ? usersize : 64;
            memset(useraddr, 0, limit);
            BYPASS_LOG(@"[__syscall] csops ops=%u -> forged pass", ops);
        }
        return ret;
    }

    if (number == SYS_ptrace) {
        int request = va_arg(ap, int);
        va_end(ap);
        if (request == 0) {
            BYPASS_LOG(@"[__syscall] SYS_ptrace(PT_DENY_ATTACH) blocked");
            return 0;
        }
        va_start(ap, number);
        va_arg(ap, int);
        pid_t pid = va_arg(ap, pid_t);
        caddr_t addr = va_arg(ap, caddr_t);
        int data = va_arg(ap, int);
        va_end(ap);
        return orig___syscall(SYS_ptrace, request, pid, addr, data);
    }

    va_end(ap);
    va_start(ap, number);
    long a1 = va_arg(ap, long);
    long a2 = va_arg(ap, long);
    long a3 = va_arg(ap, long);
    long a4 = va_arg(ap, long);
    long a5 = va_arg(ap, long);
    long a6 = va_arg(ap, long);
    va_end(ap);
    return orig___syscall(number, a1, a2, a3, a4, a5, a6);
}

#pragma mark - ObjC Method Hooks

static void hookObjCMethods(void) {
    Class fileMgr = objc_getClass("NSFileManager");
    if (fileMgr) {
        Method m = class_getInstanceMethod(fileMgr, @selector(fileExistsAtPath:));
        if (m) {
            IMP orig = method_getImplementation(m);
            IMP fake = imp_implementationWithBlock(^BOOL(id self, NSString *path) {
                if (path && isJailbreakPath(path.UTF8String)) {
                    BYPASS_LOG(@"[NSFileManager] blocked: %@", path);
                    return NO;
                }
                return ((BOOL (*)(id, SEL, NSString *))orig)(self, @selector(fileExistsAtPath:), path);
            });
            method_setImplementation(m, fake);
            BYPASS_LOG(@"[hook] NSFileManager fileExistsAtPath:");
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
                    BYPASS_LOG(@"[UIApplication] blocked scheme: %@", scheme);
                    return NO;
                }
                return ((BOOL (*)(id, SEL, NSURL *))orig)(self, @selector(canOpenURL:), url);
            });
            method_setImplementation(m, fake);
            BYPASS_LOG(@"[hook] UIApplication canOpenURL:");
        }
    }

    Class bundle = objc_getClass("NSBundle");
    if (bundle) {
        Method m = class_getInstanceMethod(bundle, @selector(bundleIdentifier));
        if (m) {
            IMP orig = method_getImplementation(m);
            IMP fake = imp_implementationWithBlock(^NSString *(id self) {
                NSString *bid = ((NSString * (*)(id, SEL))orig)(self, @selector(bundleIdentifier));
                if ([bid isEqualToString:@"com.dragon.read1"]) {
                    static dispatch_once_t onceToken;
                    dispatch_once(&onceToken, ^{
                        BYPASS_LOG(@"[NSBundle] forged bundleIdentifier");
                    });
                    return @"com.dragon.read";
                }
                return bid;
            });
            method_setImplementation(m, fake);
            BYPASS_LOG(@"[hook] NSBundle bundleIdentifier");
        }
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        BYPASS_LOG(@"=== AliSecBypass v4.2-nodobby (DragonRead) loaded ===");

        struct rebinding rebindings[] = {
            {"csops",      (void *)fake_csops,      (void **)&orig_csops},
            {"access",     (void *)fake_access,     (void **)&orig_access},
            {"stat",       (void *)fake_stat,       (void **)&orig_stat},
            {"stat64",     (void *)fake_stat64,     (void **)&orig_stat64},
            {"open",       (void *)fake_open,       (void **)&orig_open},
            {"fopen",      (void *)fake_fopen,      (void **)&orig_fopen},
            {"sysctl",     (void *)fake_sysctl,     (void **)&orig_sysctl},
            {"ptrace",     (void *)fake_ptrace,     (void **)&orig_ptrace},
            {"getenv",     (void *)fake_getenv,     (void **)&orig_getenv},
            {"__syscall",  (void *)fake___syscall,  (void **)&orig___syscall}
        };
        int count = sizeof(rebindings) / sizeof(rebindings[0]);
        int ret = rebind_symbols(rebindings, count);
        BYPASS_LOG(@"[init] fishhook rebind_symbols returned %d", ret);

        hookObjCMethods();

        BYPASS_LOG(@"=== AliSecBypass v4.2-nodobby init complete ===");
    }
}
