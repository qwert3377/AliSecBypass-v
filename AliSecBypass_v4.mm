//
//  ElyndorTV_AutoSendVip.mm
//  TrollStore injectable dylib
//  打开 App 10 秒后自动发送体验会员请求，响应写日志
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *gLogPath = nil;

static NSString* GetLogPath(void) {
    if (gLogPath) return gLogPath;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths firstObject] ?: @"/var/mobile/Documents";
    NSString *logDir = [docDir stringByAppendingPathComponent:@"ElyndorTV_Logs"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:logDir]) {
        [fm createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
    NSString *filename = [NSString stringWithFormat:@"vip_send_%@.log", [df stringFromDate:[NSDate date]]];
    gLogPath = [logDir stringByAppendingPathComponent:filename];
    return gLogPath;
}

static void WriteLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *ts = [NSString stringWithFormat:@"[%@] %@\n", [[NSDate date] description], msg];
    NSData *data = [ts dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:GetLogPath()];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    } else {
        [data writeToFile:GetLogPath() atomically:YES];
    }
    NSLog(@"[ElyndorVIP] %@", msg);
}

static void SendVipRequest(void) {
    WriteLog(@"=== 开始发送体验会员请求 ===");

    // 固定参数
    NSString *stateMemoryClient = @"210390710";
    NSString *createInsertFlow = @"ios";
    NSString *historyFavoriteThread = @"1.2.1";
    NSString *jobHistorySearch = @"ios_leo";
    NSString *userAgent = @"ElyndorTVCode/1 CFNetwork/1410.0.3 Darwin/22.6.0";

    // 动态字段（从抓包复制，会过期）
    NSString *authUser = @"dHDdpyuT54ib+W57JrI1TLeMMtbeZ58lNRNkyHyQaYg=";
    NSString *asyncServiceSession = @"57ACB9D2-9710-43DA-A81B-B528962016C4";
    NSString *helperSessionHistory = @"57ACB9D2-9710-43DA-A81B-B528962016C4";
    NSString *messageComponentTask = @"afff7d302d7bfdda476ed4b73ab11c43d4660ccf";
    NSString *cookie = @"HWWAFSESID=5da9a76401fa884f0a; HWWAFSESTIME=1787822905636";

    // 当前毫秒时间戳
    NSString *asyncColumnFeature = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970] * 1000];

    NSString *urlStr = [NSString stringWithFormat:@"https://meticulous.gxzmei.com/event/response/list?stateMemoryClient=%@", stateMemoryClient];

    WriteLog(@"URL: %@", urlStr);
    WriteLog(@"asyncColumnFeature: %@", asyncColumnFeature);

    // 构造请求
    NSURL *url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"GET"];
    [req setValue:@"meticulous.gxzmei.com" forHTTPHeaderField:@"Host"];
    [req setValue:createInsertFlow forHTTPHeaderField:@"createInsertFlow"];
    [req setValue:asyncServiceSession forHTTPHeaderField:@"asyncServiceSession"];
    [req setValue:historyFavoriteThread forHTTPHeaderField:@"historyFavoriteThread"];
    [req setValue:@"zh-CN,zh-Hans;q=0.9" forHTTPHeaderField:@"Accept-Language"];
    [req setValue:authUser forHTTPHeaderField:@"authUser"];
    [req setValue:@"gzip, deflate, br" forHTTPHeaderField:@"Accept-Encoding"];
    [req setValue:asyncColumnFeature forHTTPHeaderField:@"asyncColumnFeature"];
    [req setValue:jobHistorySearch forHTTPHeaderField:@"jobHistorySearch"];
    [req setValue:helperSessionHistory forHTTPHeaderField:@"helperSessionHistory"];
    [req setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
    [req setValue:messageComponentTask forHTTPHeaderField:@"messageComponentTask"];
    [req setValue:@"*/*" forHTTPHeaderField:@"Accept"];
    [req setValue:cookie forHTTPHeaderField:@"Cookie"];

    // 同步发送
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&response error:&error];

    if (error) {
        WriteLog(@"[-] Error: %@", error.localizedDescription);
    } else {
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        WriteLog(@"[+] Status Code: %ld", (long)httpResp.statusCode);

        if (data) {
            NSString *respStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (respStr) {
                WriteLog(@"[+] Response Body: %@", respStr);
            } else {
                NSString *base64 = [data base64EncodedStringWithOptions:0];
                WriteLog(@"[+] Response (base64): %@", base64);
            }
        } else {
            WriteLog(@"[-] No response data");
        }
    }

    WriteLog(@"=== 请求完成 ===");
    WriteLog(@"Log saved to: %@", GetLogPath());
}

// ===================== 初始化 =====================
static __attribute__((constructor)) void AutoSendInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        WriteLog(@"=== ElyndorTV AutoSend Loaded ===");
        WriteLog(@"Log: %@", GetLogPath());
        SendVipRequest();
    });
}
