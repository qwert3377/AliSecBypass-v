// BLConfSniff.mm —— 抓线路配置/订阅链接响应
// 目标: lista/alita/awtomatiko/bitsang/balangkas 响应 + sing-box 配置 + geliunrip 返回值
// 日志: Documents/conf_sniff.log
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static void slog(NSString *msg) {
    @try {
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [doc stringByAppendingPathComponent:@"conf_sniff.log"];
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) { [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
                  h = [NSFileHandle fileHandleForWritingAtPath:path]; }
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    } @catch (NSException *e) {}
}

// 线路配置特征关键字
static BOOL looksLikeConf(NSString *s) {
    if (s.length < 30) return NO;
    if ([s containsString:@"outbounds"] || [s containsString:@"server_port"] ||
        [s containsString:@"vmess://"] || [s containsString:@"trojan://"] ||
        [s containsString:@"vless://"] || [s containsString:@"ss://"] ||
        [s containsString:@"ssr://"] ||
        ([s containsString:@"server"] && [s containsString:@"port"] &&
         ([s containsString:@"uuid"] || [s containsString:@"password"] || [s containsString:@"method"])))
        return YES;
    return NO;
}

typedef id (*JSON_IMP)(Class, SEL, NSData *, NSUInteger, NSError **);
static JSON_IMP orig_json = NULL;
static int g_count = 0;

static id my_json(Class self, SEL _cmd, NSData *data, NSUInteger opt, NSError **err) {
    id result = orig_json(self, _cmd, data, opt, err);
    @try {
        if (data && data.length > 30 && data.length < 200000 && g_count < 40) {
            NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (s) {
                NSString *trim = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                // 1. 线路配置特征
                if (looksLikeConf(trim)) {
                    g_count++;
                    slog(@"★★★ 线路配置/订阅 ★★★");
                    slog(trim.length > 3000 ? [trim substringToIndex:3000] : trim);
                    slog(@"★★★ 结束 ★★★");
                }
                // 2. 节点列表特征 (lista 响应: 数组含国家/节点名)
                else if ([trim hasPrefix:@"["] &&
                         ([trim containsString:@"\"name\""] || [trim containsString:@"\"country\""] || [trim containsString:@"\"city\""])
                         && [trim containsString:@"\"id\""]) {
                    g_count++;
                    slog(@"★★ 节点列表 ★★");
                    slog(trim.length > 2500 ? [trim substringToIndex:2500] : trim);
                }
            }
        }
    } @catch (NSException *e) {}
    return result;
}

// geliunrip 返回值 (配置URL) —— Swift 符号动态找
static void hookGeliunrip(void) {
    uint32_t count = 0;
    const char *img = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "ButterflyLinker.app/ButterflyLinker")) {
            img = nm; break;
        }
    }
    if (!img) return;
    const struct mach_header_64 *hdr = (const struct mach_header_64 *)_dyld_get_image_header(
        (uint32_t)(strstr(img, "ButterflyLinker") - img)); // 简化, 实际用索引
    // 用 nlist 遍历太繁, 简化: 直接 dladdr 找不了 Swift 符号
    // 方案: 遍历符号表找 geliunrip (Mach-O LC_SYMTAB 解析, 略) —— 用另一种方式:
    // hook 整个 App 模块的 URL 返回不现实; 改为 hook -[NSURL absoluteString] 太吵
    // 实用方案: 监听 App Group UD 的 ConfUrl key 变化
    slog(@"[hint] geliunrip 符号hook略, 配置URL会在 UD/AppGroup 出现, 看响应即可");
}

__attribute__((constructor)) static void init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = objc_getClass("NSJSONSerialization");
        if (cls) {
            Method m = class_getClassMethod(cls, @selector(JSONObjectWithData:options:error:));
            if (m) {
                orig_json = (JSON_IMP)method_setImplementation(m, (IMP)my_json);
                slog(@"[init] JSON hooked");
            }
        }
    });
}
