// BLDecSniff v2 —— 定位解密函数 + 全线路密文
// v2: hook后1.5秒清线路列表缓存(Tananas等), 迫使App重新请求lista→触发解密
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static BOOL g_inHook = NO;
static int g_btCount = 0;
static int g_linesCount = 0;

static void slog(NSString *msg) {
    if (g_inHook) return;
    @try {
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [doc stringByAppendingPathComponent:@"dec_sniff.log"];
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) { [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
                  h = [NSFileHandle fileHandleForWritingAtPath:path]; }
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    } @catch (...) {}
}

// 清服务器响应缓存 → 强制重新请求
static void clearListCache(void) {
    @try {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        for (NSString *k in @[@"Tananas",        // 线路/国家列表 ★核心
                              @"Abitproducts", @"Dugayon", @"Mansanas", @"Mearind",
                              @"Klase", @"Usuario", @"Sausuario", @"Tandaan",
                              @"Abitcoifugs", @"Bitasyon", @"Libutan", @"Adlaw",
                              @"Liyente", @"Serbisyo"]) {
            [ud removeObjectForKey:k];
        }
        [ud synchronize];
        slog(@"[cache] 列表缓存已清, 请点国家tab");
    } @catch (...) {}
}

typedef id (*JSON_IMP)(Class, SEL, NSData *, NSUInteger, NSError **);
static JSON_IMP orig_json = NULL;

static id my_json(Class self, SEL _cmd, NSData *data, NSUInteger opt, NSError **err) {
    id result = orig_json(self, _cmd, data, opt, err);
    if (g_inHook || !data || data.length < 50 || data.length > 300000) return result;
    g_inHook = YES;
    @try {
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!s) { g_inHook = NO; return result; }

        if ([s containsString:@"\"server\""] && [s containsString:@"\"vmess\""] && g_btCount < 5) {
            g_btCount++;
            slog(@"★★★ 明文出现 调用栈 ★★★");
            for (NSString *f in [NSThread callStackSymbols]) slog(f);
            slog(@"★★★ 栈结束 ★★★");
        }
        if ([s containsString:@"\"lines\""] && [s containsString:@"\"link_url\""] && g_linesCount < 5) {
            g_linesCount++;
            slog(@"★★★ LINES密文 ★★★");
            slog(s.length > 8000 ? [s substringToIndex:8000] : s);
            slog(@"★★★ LINES结束 ★★★");
        }
    } @catch (...) {}
    g_inHook = NO;
    return result;
}

__attribute__((constructor)) static void init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = objc_getClass("NSJSONSerialization");
        if (cls) {
            Method m = class_getClassMethod(cls, @selector(JSONObjectWithData:options:error:));
            if (m) {
                orig_json = (JSON_IMP)method_setImplementation(m, (IMP)my_json);
                slog(@"[init] hooked");
            }
        }
        // 1.5秒后清缓存(等App启动读取完成后)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ clearListCache(); });
    });
}
