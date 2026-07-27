// AliSecBypass_v4.mm
// 番茄畅听/番茄小说 通用脱壳检测绕过插件 v4
// 基于 Dobby inline hook C 函数 + ObjC Runtime hook
// 纯库文件，无 Logos，TrollStore / 非越狱注入
// 日志: App Documents/AliBypass.log

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include "dobby.h"

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

#pragma mark - Dobby C Function Hook Examples

/*
#include <sys/ptrace.h>
#include <sys/sysctl.h>
#include <unistd.h>

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
    if (namelen >= 4 && name[0] == CTL_KERN && name[1] == KERN_PROC && name[2] == KERN_PROC_PID && name[3] == getpid()) {
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
        if ([p containsString:@"Cydia"] ||
            [p containsString:@"MobileSubstrate"] ||
            [p containsString:@"apt"] ||
            [p containsString:@"bin/bash"] ||
            [p containsString:@"usr/sbin/sshd"] ||
            [p containsString:@"var/lib/dpkg"] ||
            [p containsString:@"TrollStore"]) {
            BYPASS_LOG(@"[DOBBY] access blocked: %s", path);
            return -1;
        }
    }
    return orig_access(path, mode);
}
*/

#pragma mark - ObjC Runtime Hook Helpers

static inline void safeHook(Class cls, SEL sel, IMP fake, IMP *orig) {
    if (!cls || !sel || !fake) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (orig) *orig = method_getImplementation(m);
    method_setImplementation(m, fake);
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
}

static inline void safeHookClassNoOrig(Class cls, SEL sel, IMP fake) {
    safeHookClass(cls, sel, fake, NULL);
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

#pragma mark - Module Placeholders

static void hookAliSDK() {
    BYPASS_LOG(@"[ALI] SDK hooks placeholder");
}

static void hookBaiduSDK() {
    BYPASS_LOG(@"[BD] SDK hooks placeholder");
}

static void hookByteDanceSDK() {
    BYPASS_LOG(@"[TT] SDK hooks placeholder");
}

static void hookSystemClasses() {
    BYPASS_LOG(@"[SYS] System hooks placeholder");
}

#pragma mark - Constructor

__attribute__((constructor))
static void init() {
    @autoreleasepool {
        BYPASS_LOG(@"=== AliSecBypass v4 (Dobby + Runtime) loaded ===");
        
        // DobbyHook((void *)ptrace, (void *)my_ptrace, (void **)&orig_ptrace);
        // DobbyHook((void *)sysctl, (void *)my_sysctl, (void **)&orig_sysctl);
        // DobbyHook((void *)access, (void *)my_access, (void **)&orig_access);
        
        hookAliSDK();
        hookBaiduSDK();
        hookByteDanceSDK();
        hookSystemClasses();
        
        BYPASS_LOG(@"=== AliSecBypass v4 init complete ===");
    }
}
