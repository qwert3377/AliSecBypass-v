// AliSecBypass_v4.mm
// ButterflyLinker 试用绕过 —— hook SecItemCopyMatching 换设备ID
// 原理: App 查询 Keychain 设备ID(abitounid) 时返回"不存在"
//       → App 生成新 UUID → 写回 Keychain(SecItemAdd, 检测后置位放行)
//       → 注册新设备 → 服务器发新 10 分钟试用
// 依赖: Dobby (CI 已配), 无需 Security.framework (dlsym 取地址)
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "dobby.h"

typedef OSStatus (*SecItemFn)(CFDictionaryRef, CFTypeRef *);           // copy / add
typedef OSStatus (*SecItemUpdateFn)(CFDictionaryRef, CFDictionaryRef); // update

static SecItemFn orig_copy = NULL;
static SecItemFn orig_add = NULL;
static SecItemUpdateFn orig_update = NULL;

static NSTimeInterval g_start = 0;
static BOOL g_newIdWritten = NO;   // 新ID写入后置位, 此后查询一律放行(保证UUID全程一致)

#pragma mark - 日志
static void log_msg(NSString *msg) {
    @try {
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [doc stringByAppendingPathComponent:@"trial_patch.log"];
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
            h = [NSFileHandle fileHandleForWritingAtPath:path];
        }
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    } @catch (NSException *e) {}
}

#pragma mark - 判断查询目标是否为设备ID
static BOOL isAbitQuery(CFDictionaryRef dict) {
    CFStringRef acct = (CFStringRef)CFDictionaryGetValue(dict, CFSTR("acct"));
    return acct && CFGetTypeID(acct) == CFStringGetTypeID()
        && CFStringCompare(acct, CFSTR("abitounid"), 0) == kCFCompareEqualTo;
}

#pragma mark - hook: 读
// 新ID未写入前, 启动8秒内的 abitounid 查询返回 errSecItemNotFound(-25300)
// 触发 App 走"首次安装"路径: generateDeviceID → 新UUID → 注册新设备
static OSStatus my_copy(CFDictionaryRef query, CFTypeRef *result) {
    if (!g_newIdWritten
        && [NSDate timeIntervalSinceReferenceDate] - g_start < 8.0
        && isAbitQuery(query)) {
        static int n = 0;
        if (++n <= 3) log_msg(@"[hook] 查询→不存在(触发重新生成)");
        return (OSStatus)-25300;
    }
    return orig_copy(query, result);
}

#pragma mark - hook: 写
// App 把新生成的 UUID 写回 Keychain → 置位放行
// 关键: 不置位的话 8 秒内每次查询都"不存在", App 会反复生成不同 UUID,
//       导致注册/后续请求身份不一致 → 服务器会话混乱
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

#pragma mark - 入口
__attribute__((constructor)) static void tp_init(void) {
    g_start = [NSDate timeIntervalSinceReferenceDate];

    int e1 = -1, e2 = -1, e3 = -1;
    void *p = dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
    if (p) e1 = DobbyHook(p, (void *)my_copy, (void **)&orig_copy);
    p = dlsym(RTLD_DEFAULT, "SecItemAdd");
    if (p) e2 = DobbyHook(p, (void *)my_add, (void **)&orig_add);
    p = dlsym(RTLD_DEFAULT, "SecItemUpdate");
    if (p) e3 = DobbyHook(p, (void *)my_update, (void **)&orig_update);
    log_msg([NSString stringWithFormat:@"[Dobby] copy=%d add=%d update=%d (全0=成功)", e1, e2, e3]);

    // 1秒后清服务器响应缓存(避免旧会员状态残留), 需等 App 启动读取完成
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @try {
            NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
            for (NSString *k in @[@"Dugayon", @"Mansanas", @"Mearind", @"Klase",
                                  @"Session", @"Sesyon", @"Usuario"]) {
                [ud removeObjectForKey:k];
            }
            [ud synchronize];
        } @catch (NSException *e) {}
    });
}
