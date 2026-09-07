// YSBrowser Pro Unlock - Probe/Logger (.mm)
// Detects app termination cause and logs to app Documents.
// Run this first to identify which patch triggers kill.

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <signal.h>
#import <libkern/OSCacheControl.h>

static uintptr_t g_base = 0;
static NSString *g_logPath = nil;

static uintptr_t getModuleBase(const char *name) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (strstr(_dyld_get_image_name(i), name))
            return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

static void logMsg(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                  dateStyle:NSDateFormatterNoStyle
                                                  timeStyle:NSDateFormatterMediumStyle];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:g_logPath];
    if (!fh) {
        [@"" writeToFile:g_logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:g_logPath];
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];

    NSLog(@"[YSB-Probe] %@", msg);
}

static int patch4(uintptr_t offset, uint32_t val) {
    uintptr_t addr = g_base + offset;
    kern_return_t kr;
    vm_address_t region = addr & ~0x3FFF;
    vm_size_t size = 0x4000;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    memory_object_name_t obj;

    kr = vm_region_64(mach_task_self(), &region, &size, VM_REGION_BASIC_INFO_64,
                      (vm_region_info_t)&info, &count, &obj);
    if (kr != KERN_SUCCESS) { logMsg(@"vm_region fail offset=0x%llx", (unsigned long long)offset); return -1; }

    kr = vm_protect(mach_task_self(), region, size, false, info.protection | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) { logMsg(@"vm_protect fail offset=0x%llx", (unsigned long long)offset); return -1; }

    uint32_t orig = *(volatile uint32_t *)addr;
    *(volatile uint32_t *)addr = val;

    vm_protect(mach_task_self(), region, size, false, info.protection);
    sys_icache_invalidate((void *)addr, 4);

    logMsg(@"PATCH OK offset=0x%llx orig=0x%x new=0x%x", (unsigned long long)offset, orig, val);
    return 0;
}

static inline void nop(uintptr_t o) { patch4(o, 0xd503201f); }
static inline void ret(uintptr_t o) { patch4(o, 0xd65f03c0); }
static inline void mov_w0_1(uintptr_t o) { patch4(o, 0x52800020); }
static void func_true(uintptr_t o) { mov_w0_1(o); ret(o + 4); }

// Signal handler to detect kills
static void signalHandler(int sig, siginfo_t *info, void *ucontext) {
    logMsg(@"SIGNAL CAUGHT: sig=%d code=%d addr=%p", sig, info->si_code, info->si_addr);
    // Re-raise to get crash report
    signal(sig, SIG_DFL);
    raise(sig);
}

__attribute__((constructor))
static void init() {
    // Setup log path in app Documents
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    g_logPath = [paths[0] stringByAppendingPathComponent:@"ysb_probe.log"];

    logMsg(@"=== Probe started ===");

    // Register signal handlers
    struct sigaction sa;
    sa.sa_sigaction = signalHandler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGILL, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGKILL, &sa, NULL);

    // Wait for module
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        g_base = getModuleBase("YSBrowser");
        if (!g_base) {
            logMsg(@"ERROR: YSBrowser base not found");
            return;
        }
        logMsg(@"Base=0x%llx", (unsigned long long)g_base);

        // === PHASE 1: Settings + Pro page only ===
        logMsg(@"Phase 1: Settings + Pro");
        nop(0x448668);
        func_true(0x448a84);
        nop(0x448644);
        logMsg(@"Phase 1 done");

        // === PHASE 2: Export (5s later) ===
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            logMsg(@"Phase 2: Export");
            patch4(0x3520f8, 0x1400000e);
            nop(0x3509dc);
            nop(0x3509f8);
            nop(0x35f53c);
            func_true(0x35f50c);
            logMsg(@"Phase 2 done");

            // === PHASE 3: Export button paths (3s later) ===
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                logMsg(@"Phase 3: Export button");
                nop(0x1829f4);
                nop(0x182a50);
                logMsg(@"Phase 3 done");

                // === PHASE 4: General Pro check (3s later) ===
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    logMsg(@"Phase 4: General Pro");
                    nop(0x40e0d8);
                    logMsg(@"Phase 4 done - ALL PATCHES APPLIED");
                });
            });
        });
    });
}
