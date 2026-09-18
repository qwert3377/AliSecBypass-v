// ButterflyTrialPatch.mm
// 原理: hook NSJSONSerialization 类方法, 在 JSON 文本层把服务器响应的
//       dugayon(到期时间)/klase(会员等级)/mansanas(剩余天数) 替换为会员值
// 日志: App Documents/trial_patch.log
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

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

#pragma mark - JSON 篡改
typedef id (*JSON_IMP)(Class, SEL, NSData *, NSUInteger, NSError **);
static JSON_IMP orig_JSON = NULL;

static void rxReplace(NSMutableString *ms, NSString *pattern, NSString *repl) {
    @try {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                    options:0 error:nil];
        [re replaceMatchesInString:ms options:0 range:NSMakeRange(0, ms.length)
                  withTemplate:repl];
    } @catch (NSException *e) {}
}

static id hook_JSON(Class self, SEL _cmd, NSData *data, NSUInteger opt, NSError **err) {
    @autoreleasepool {
        if (data && data.length > 20 && data.length < 2000000) {
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (str && [str containsString:@"dugayon"]) {
                unsigned long long future = (unsigned long long)([[NSDate date] timeIntervalSince1970] + 31536000.0 * 5);
                NSMutableString *ms = [str mutableCopy];
                rxReplace(ms, @"\"dugayon\":\\d+", [NSString stringWithFormat:@"\"dugayon\":%llu", future]);
                rxReplace(ms, @"\"mansanas\":\\d+",  @"\"mansanas\":365");
                rxReplace(ms, @"\"is_today_vip\":\\d+", @"\"is_today_vip\":1");
                rxReplace(ms, @"\"adlaw\":\\d+",     @"\"adlaw\":365");
                rxReplace(ms, @"\"vip_need_watch_ad\":\\d+", @"\"vip_need_watch_ad\":0");
                rxReplace(ms, @"\"klase\":\\d+",    @"\"klase\":2");
                NSData *nd = [ms dataUsingEncoding:NSUTF8StringEncoding];
                if (nd) data = nd;
                log_msg([NSString stringWithFormat:@"[篡改] dugayon→%llu klase→2 (#%@)",
                         future, [NSUserDefaults.standardUserDefaults objectForKey:@"_tp_count"] ?: @"1"]);
            }
        }
        return orig_JSON(self, _cmd, data, opt, err);
    }
}

#pragma mark - 清服务器缓存（强制重拉取被篡改的响应）
static void clearServerCache(void) {
    @try {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud removeObjectForKey:@"Dugayon"];
        [ud removeObjectForKey:@"Mansanas"];
        [ud removeObjectForKey:@"Mearind"];
        [ud removeObjectForKey:@"Klase"];
        [ud removeObjectForKey:@"Usuario"];
        [ud removeObjectForKey:@"Sausuario"];
        [ud removeObjectForKey:@"Tandaan"];
        [ud removeObjectForKey:@"Abitcoifugs"];
        [ud synchronize];
        log_msg(@"[缓存] 已清服务器响应缓存");
    } @catch (NSException *e) {}
}

#pragma mark - 安装（轮询等 Foundation 就绪）
static void tryInstall(void) {
    static int tries = 0;
    if (tries > 100) { log_msg(@"[失败] NSJSONSerialization 100 次未就绪"); return; }
    Class cls = objc_getClass("NSJSONSerialization");
    if (!cls) {
        tries++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ tryInstall(); });
        return;
    }
    Method m = class_getClassMethod(cls, @selector(JSONObjectWithData:options:error:));
    if (!m) {
        tries++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ tryInstall(); });
        return;
    }
    orig_JSON = (JSON_IMP)method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_JSON);
    log_msg(@"[成功] NSJSONSerialization hooked");
    // 清缓存放主线程下一 runloop，等 App 启动读取完成后再清
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ clearServerCache(); });
}

__attribute__((constructor)) static void tp_init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ tryInstall(); });
}
