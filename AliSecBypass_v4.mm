#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "dobby.h"

typedef OSStatus (*SecItemFn)(CFDictionaryRef, CFTypeRef *);
static SecItemFn orig_copy = NULL;
static SecItemFn orig_add = NULL;
static SecItemFn orig_update = NULL;
static NSTimeInterval g_start = 0;
static BOOL g_newIdWritten = NO;   // 关键: 新ID写入后置位, 此后一律放行

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

static BOOL isAbitQuery(CFDictionaryRef dict) {
    CFStringRef acct = (CFStringRef)CFDictionaryGetValue(dict, CFSTR("acct"));
    return acct && CFGetTypeID(acct) == CFStringGetTypeID()
        && CFStringCompare(acct, CFSTR("abitounid"), 0) == kCFCompareEqualTo;
}

// 读: 新ID未写入前, 启动8秒内的查询返回"不存在" → 触发App重新生成
static OSStatus my_copy(CFDictionaryRef query, CFTypeRef *result) {
    if (!g_newIdWritten && [NSDate timeIntervalSinceReferenceDate] - g_start < 8.0
        && isAbitQuery(query)) {
        static int n = 0;
        if (++n <= 3) log_msg(@"[hook] 查询→不存在(触发重新生成)");
        return (OSStatus)-25300;
    }
    return orig_copy(query, result);
}

// 写: App 把新生成的ID写入Keychain → 置位放行, 保证后续读写一致
static OSStatus my_add(CFDictionaryRef attrs, CFTypeRef *result) {
    OSStatus s = orig_add(attrs, result);
    if ((s == 0 || s == -25299) && isAbitQuery(attrs)) {  // 0=成功 -25299=已存在
        if (!g_newIdWritten) log_msg(@"[hook] 新ID已写入, 此后放行");
        g_newIdWritten = YES;
    }
    return s;
}
static OSStatus my_update(CFDictionaryRef query, CFDictionaryRef attrs) {
    OSStatus s = orig_update(query, attrs);
    if (s == 0 && isAbitQuery(query)) g_newIdWritten = YES;
    return s;
}

__attribute__((constructor)) static void tp_init(void) {
    g_start = [NSDate timeIntervalSinceReferenceDate];
    int e1 = 0, e2 = 0, e3 = 0;
    void *p = dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
    if (p) e1 = DobbyHook(p, (void *)my_copy, (void **)&orig_copy);
    p = dlsym(RTLD_DEFAULT, "SecItemAdd");
    if (p) e2 = DobbyHook(p, (void *)my_add, (void **)&orig_add);
    p = dlsym(RTLD_DEFAULT, "SecItemUpdate");
    if (p) e3 = DobbyHook(p, (void *)my_update, (void **)&orig_update);
    log_msg([NSString stringWithFormat:@"[Dobby] copy=%d add=%d update=%d", e1, e2, e3]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        for (NSString *k in @[@"Dugayon",@"Mansanas",@"Mearind",@"Klase",@"Session",@"Sesyon"])
            [ud removeObjectForKey:k];
        [ud synchronize];
    });
}
