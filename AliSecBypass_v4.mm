// AliSecBypass_v7.mm —— ButterflyLinker 无限试用 (需配合换IP)
// 已验证: IDFV随机化 → 新设备注册 → 服务器发10分钟试用
// 风控: 同一IP短时间多次注册会被拒 → 试用到期后需换IP(飞行模式5秒)再重开App
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "dobby.h"

typedef OSStatus (*SecItemFn)(CFDictionaryRef, CFTypeRef *);
static SecItemFn orig_copy = NULL;
static NSUUID *g_fakeIdfv = nil;
static BOOL g_kcTriggered = NO;
static NSTimeInterval g_start = 0;

static void log_msg(NSString *msg) {
    @try {
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [doc stringByAppendingPathComponent:@"trial_patch.log"];
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) { [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
                  h = [NSFileHandle fileHandleForWritingAtPath:path]; }
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    } @catch (NSException *e) {}
}

static NSString *randomUUID(void) {
    NSMutableString *s = [NSMutableString stringWithString:@"xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"];
    for (NSInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == 'x' || c == 'y') {
            u_int32_t r = arc4random_uniform(16);
            if (c == 'y') r = (r & 0x3) | 0x8;
            [s replaceCharactersInRange:NSMakeRange(i, 1)
                             withString:[NSString stringWithFormat:@"%X", r]];
        }
    }
    return s;
}

static id (*orig_idfv)(UIDevice *, SEL);
static id my_idfv(UIDevice *self, SEL _cmd) {
    if (!g_fakeIdfv) {
        g_fakeIdfv = [[NSUUID alloc] initWithUUIDString:randomUUID()];
        log_msg([NSString stringWithFormat:@"[IDFV] %@", g_fakeIdfv.UUIDString]);
    }
    return g_fakeIdfv;
}

static OSStatus my_copy(CFDictionaryRef query, CFTypeRef *result) {
    if (!g_kcTriggered && [NSDate timeIntervalSinceReferenceDate] - g_start < 10.0) {
        CFStringRef acct = (CFStringRef)CFDictionaryGetValue(query, CFSTR("acct"));
        if (acct && CFGetTypeID(acct) == CFStringGetTypeID()
            && CFStringCompare(acct, CFSTR("abitounid"), 0) == kCFCompareEqualTo) {
            g_kcTriggered = YES;
            log_msg(@"[KC] 旧ID屏蔽");
            return (OSStatus)-25300;
        }
    }
    return orig_copy(query, result);
}

__attribute__((constructor)) static void tp_init(void) {
    g_start = [NSDate timeIntervalSinceReferenceDate];
    Class devCls = objc_getClass("UIDevice");
    if (devCls) {
        Method m = class_getInstanceMethod(devCls, @selector(identifierForVendor));
        if (m) orig_idfv = (id (*)(UIDevice *, SEL))method_setImplementation(m, (IMP)my_idfv);
    }
    void *p = dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
    int e = p ? DobbyHook(p, (void *)my_copy, (void **)&orig_copy) : -1;
    log_msg([NSString stringWithFormat:@"[v7] idfv=%@ kc=%d", g_fakeIdfv ? @"ok" : @"fail", e]);
}
