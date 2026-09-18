// BLDecSniff.mm —— 定位解密函数 + 导出全部线路密文(含VIP)
// 常驻: 任何时候点国家/点连接都能抓到
// 日志: Documents/dec_sniff.log
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static BOOL g_inHook = NO;      // 防递归(log写入不再触发解析)
static int g_btCount = 0;       // 调用栈打印次数限制
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

typedef id (*JSON_IMP)(Class, SEL, NSData *, NSUInteger, NSError **);
static JSON_IMP orig_json = NULL;

static id my_json(Class self, SEL _cmd, NSData *data, NSUInteger opt, NSError **err) {
    id result = orig_json(self, _cmd, data, opt, err);
    if (g_inHook || !data || data.length < 50 || data.length > 300000) return result;
    g_inHook = YES;
    @try {
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!s) { g_inHook = NO; return result; }

        // 1. 明文 vmess 配置出现 → 完整调用栈(解密函数就在里面)
        if ([s containsString:@"\"server\""] && [s containsString:@"\"vmess\""] && g_btCount < 5) {
            g_btCount++;
            slog(@"★★★ 明文出现 调用栈 ★★★");
            for (NSString *f in [NSThread callStackSymbols]) slog(f);
            slog(@"★★★ 栈结束 ★★★");
        }
        // 2. lista lines → 全量密文(含VIP线路)
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
    });
}
