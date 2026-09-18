// ButterflyTrialPatch.mm v3 —— hook SecItemCopyMatching, App 每次启动都"找不到"设备ID → 重新生成 → 新试用
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <dlfcn.h>
#import "dobby.h"

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

// 关键: 启动后 8 秒内的 abitounid 查询一律返回"不存在"
// App 流程: 查→无→generateDeviceID 生成新UUID→写Keychain→注册新设备→新10分钟
// 8 秒后放行(此时 Keychain 里已是新ID, 保持一致性, 避免运行期反复重生成)
static NSTimeInterval g_startTime = 0;
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result);

static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    CFStringRef acct = (CFStringRef)CFDictionaryGetValue(query, kSecAttrAccount);
    if (acct && CFGetTypeID(acct) == CFStringGetTypeID()
        && CFStringCompare(acct, CFSTR("abitounid"), 0) == kCFCompareEqualTo) {
        if ([NSDate timeIntervalSinceReferenceDate] - g_startTime < 8.0) {
            static int n = 0;
            if (++n <= 3) log_msg(@"[hook] abitounid 查询 → 返回不存在(触发重新生成)");
            return errSecItemNotFound;  // -25300
        }
    }
    return orig_SecItemCopyMatching(query, result);
}

__attribute__((constructor)) static void tp_init(void) {
    g_startTime = [NSDate timeIntervalSinceReferenceDate];
    void *sec = dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
    if (!sec) { log_msg(@"[失败] 找不到 SecItemCopyMatching"); return; }
    int err = DobbyHook(sec, (void *)my_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching);
    log_msg([NSString stringWithFormat:@"[Dobby] hook %s", err == 0 ? "成功" : "失败"]);
    // 顺手清掉服务器响应缓存, 防止旧会员状态残留
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        for (NSString *k in @[@"Dugayon",@"Mansanas",@"Mearind",@"Klase",@"Session",@"Sesyon"]) {
            [ud removeObjectForKey:k];
        }
        [ud synchronize];
    });
}
