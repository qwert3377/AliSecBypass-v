// AliSecBypass_v4.mm —— 抓线路配置/订阅链接响应
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
                if (looksLikeConf(trim)) {
                    g_count++;
                    slog(@"★★★ 线路配置/订阅 ★★★");
                    slog(trim.length > 3000 ? [trim substringToIndex:3000] : trim);
                    slog(@"★★★ 结束 ★★★");
                }
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
