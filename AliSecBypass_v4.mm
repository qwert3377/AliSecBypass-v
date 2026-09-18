// AliSecBypass_v4.mm —— 去掉 Security 框架依赖版
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "dobby.h"

// dlsym 取地址, 不链接 Security.framework
typedef OSStatus (*SecItemCopyMatchingFn)(CFDictionaryRef query, CFTypeRef *result);
static SecItemCopyMatchingFn orig_copy = NULL;
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

// 启动后 8 秒内, abitounid 查询一律返回 errSecItemNotFound(-25300)
// App: 查→无→generateDeviceID 新UUID→写Keychain→注册新设备→新10分钟
static OSStatus my_copy(CFDictionaryRef query, CFTypeRef *result) {
    CFStringRef acct = (CFStringRef)CFDictionaryGetValue(query, CFSTR("acct"));
    if (acct && CFGetTypeID(acct) == CFStringGetTypeID()
        && CFStringCompare(acct, CFSTR("abitounid"), 0) == kCFCompareEqualTo) {
        if ([NSDate timeIntervalSinceReferenceDate] - g_start < 8.0) {
            static int n = 0;
            if (++n <= 3) log_msg(@"[hook] abitounid→不存在(触发重新生成)");
            return (OSStatus)-25300;   // errSecItemNotFound, 硬编码不依赖 Security
        }
    }
    return orig_copy(query, result);
}

__attribute__((constructor)) static void tp_init(void) {
    g_start = [NSDate timeIntervalSinceReferenceDate];
    void *sec = dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
    if (!sec) { log_msg(@"[失败] dlsym SecItemCopyMatching"); return; }
    int err = DobbyHook(sec, (void *)my_copy, (void **)&orig_copy);
    log_msg([NSString stringWithFormat:@"[Dobby] hook %s", err == 0 ? "成功" : "失败"]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        for (NSString *k in @[@"Dugayon",@"Mansanas",@"Mearind",@"Klase",@"Session",@"Sesyon"])
            [ud removeObjectForKey:k];
        [ud synchronize];
    });
}
