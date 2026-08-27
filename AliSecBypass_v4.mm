//
//  ElyndorTV_VIPHook.mm
//  TrollStore injectable dylib
//  专攻 meticulous.gxzmei.com /event/response/list 体验会员接口
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <execinfo.h>

static NSString *const kTargetDomain = @"meticulous.gxzmei.com";
static NSString *const kLogDirName   = @"ElyndorTV_Logs";
static NSString *gLogPath = nil;

// ===================== 日志工具 =====================
static NSString* GetLogPath(void) {
    if (gLogPath) return gLogPath;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths firstObject] ?: @"/var/mobile/Documents";
    NSString *logDir = [docDir stringByAppendingPathComponent:kLogDirName];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:logDir]) {
        [fm createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
    NSString *filename = [NSString stringWithFormat:@"vip_%@.log", [df stringFromDate:[NSDate date]]];
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

static NSString* GetStackTrace(void) {
    void *callstack[32];
    int frames = backtrace(callstack, 32);
    char **strs = backtrace_symbols(callstack, frames);
    NSMutableString *trace = [NSMutableString stringWithString:@"\n--- Stack ---\n"];
    for (int i = 0; i < frames && i < 20; i++) {
        NSString *line = strs[i] ? [NSString stringWithUTF8String:strs[i]] : @"<unknown>";
        [trace appendFormat:@"  %d: %@\n", i, line];
    }
    free(strs);
    return trace;
}

static BOOL IsTargetURL(NSString *url) {
    return url && [url rangeOfString:kTargetDomain options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// ===================== 1. Hook NSURLRequest 初始化 =====================
@interface NSURLRequest (VIPHook)
@end

@implementation NSURLRequest (VIPHook)

+ (instancetype)vip_requestWithURL:(NSURL *)URL {
    NSString *url = URL.absoluteString;
    if (IsTargetURL(url)) {
        WriteLog(@"[REQ-CREATE] +requestWithURL: %@%@", url, GetStackTrace());
    }
    return [self vip_requestWithURL:URL];
}

- (instancetype)vip_initWithURL:(NSURL *)URL {
    NSString *url = URL.absoluteString;
    if (IsTargetURL(url)) {
        WriteLog(@"[REQ-CREATE] -initWithURL: %@%@", url, GetStackTrace());
    }
    return [self vip_initWithURL:URL];
}

@end

// ===================== 2. Hook NSMutableURLRequest (Headers 在这里设置) =====================
@interface NSMutableURLRequest (VIPHook)
@end

@implementation NSMutableURLRequest (VIPHook)

- (void)vip_setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    NSURL *url = self.URL;
    if (url && IsTargetURL(url.absoluteString)) {
        WriteLog(@"[HEADER] %@: %@", field, value);
    }
    [self vip_setValue:value forHTTPHeaderField:field];
}

- (void)vip_addValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    NSURL *url = self.URL;
    if (url && IsTargetURL(url.absoluteString)) {
        WriteLog(@"[HEADER-ADD] %@: %@", field, value);
    }
    [self vip_addValue:value forHTTPHeaderField:field];
}

- (instancetype)vip_initWithURL:(NSURL *)URL {
    NSString *url = URL.absoluteString;
    if (IsTargetURL(url)) {
        WriteLog(@"[REQ-CREATE-MUTABLE] -initWithURL: %@%@", url, GetStackTrace());
    }
    return [self vip_initWithURL:URL];
}

@end

// ===================== 3. Hook NSURLSession (请求发出) =====================
@interface NSURLSession (VIPHook)
@end

@implementation NSURLSession (VIPHook)

- (NSURLSessionDataTask *)vip_dataTaskWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;
    if (IsTargetURL(url)) {
        WriteLog(@"[SESSION-DELEGATE] dataTaskWithRequest:");
        WriteLog(@"  URL: %@", url);
        WriteLog(@"  Method: %@", request.HTTPMethod ?: @"GET");
        WriteLog(@"  Headers: %@", request.allHTTPHeaderFields ?: @{});
        if (request.HTTPBody) {
            NSString *body = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
            WriteLog(@"  Body: %@", body ?: @"<binary>");
        }
        WriteLog(@"%@", GetStackTrace());
    }
    return [self vip_dataTaskWithRequest:request];
}

- (NSURLSessionDataTask *)vip_dataTaskWithRequest:(NSURLRequest *)request
                                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSString *url = request.URL.absoluteString;
    if (IsTargetURL(url)) {
        WriteLog(@"[SESSION-BLOCK] dataTaskWithRequest:completionHandler:");
        WriteLog(@"  URL: %@", url);
        WriteLog(@"  Method: %@", request.HTTPMethod ?: @"GET");
        WriteLog(@"  Headers: %@", request.allHTTPHeaderFields ?: @{});
        if (request.HTTPBody) {
            NSString *body = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
            WriteLog(@"  Body: %@", body ?: @"<binary>");
        }
        WriteLog(@"%@", GetStackTrace());

        void (^wrapped)(NSData *, NSURLResponse *, NSError *) = completionHandler;
        if (completionHandler) {
            wrapped = ^(NSData *data, NSURLResponse *response, NSError *error) {
                NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
                NSString *dataStr = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"<nil>";
                WriteLog(@"[RESPONSE] URL: %@ | Status: %ld | Data: %@",
                         url, (long)httpResp.statusCode,
                         dataStr.length > 2000 ? [dataStr substringToIndex:2000] : dataStr);
                completionHandler(data, response, error);
            };
        }
        return [self vip_dataTaskWithRequest:request completionHandler:wrapped];
    }
    return [self vip_dataTaskWithRequest:request completionHandler:completionHandler];
}

@end

// ===================== 4. Hook WKWebView evaluateJavaScript (注入 fetch 拦截) =====================
@interface WKWebView (VIPHook)
@end

@implementation WKWebView (VIPHook)

- (void)vip_evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id, NSError *))completionHandler {
    // 注入 fetch/XHR 拦截代码
    NSString *injectCode = @""
        @"(function(){"
        @"  if(window.__vip_hooked__)return;"
        @"  window.__vip_hooked__=true;"
        @"  var origFetch=window.fetch;"
        @"  window.fetch=function(url,opts){"
        @"    var u=(typeof url==='string')?url:(url?url.url:'');"
        @"    if(u&&u.indexOf('meticulous.gxzmei.com')!==-1){"
        @"      var m=(opts&&opts.method)?opts.method:'GET';"
        @"      var b=(opts&&opts.body)?String(opts.body):'';"
        @"      var h=(opts&&opts.headers)?JSON.stringify(opts.headers):'';"
        @"      console.log('[VIP_FETCH]'+m+'|'+u+'|'+h+'|'+b);"
        @"    }"
        @"    return origFetch.apply(this,arguments);"
        @"  };"
        @"  var origOpen=XMLHttpRequest.prototype.open;"
        @"  XMLHttpRequest.prototype.open=function(m,u){"
        @"    if(u&&u.indexOf('meticulous.gxzmei.com')!==-1){"
        @"      this._vip_url=u;this._vip_method=m;"
        @"      console.log('[VIP_XHR]'+m+'|'+u);"
        @"    }"
        @"    return origOpen.apply(this,arguments);"
        @"  };"
        @"  var origSend=XMLHttpRequest.prototype.send;"
        @"  XMLHttpRequest.prototype.send=function(b){"
        @"    if(this._vip_url){"
        @"      console.log('[VIP_XHR_SEND]'+this._vip_method+'|'+this._vip_url+'|'+(b||''));"
        @"    }"
        @"    return origSend.apply(this,arguments);"
        @"  };"
        @"})();";

    [self vip_evaluateJavaScript:injectCode completionHandler:nil];
    [self vip_evaluateJavaScript:javaScriptString completionHandler:completionHandler];
}

@end

// ===================== 5. 自动触发体验会员请求模板 =====================
@interface ElyndorTVVIPTrigger : NSObject
+ (void)triggerVipRequest;
@end

@implementation ElyndorTVVIPTrigger

+ (void)triggerVipRequest {
    NSString *stateMemoryClient = @"210390710";
    NSString *createInsertFlow = @"ios";
    NSString *historyFavoriteThread = @"1.2.1";
    NSString *jobHistorySearch = @"ios_leo";
    NSString *userAgent = @"ElyndorTVCode/1 CFNetwork/1410.0.3 Darwin/22.6.0";

    // 动态字段（需要从运行时提取或抓包复制，会过期）
    NSString *authUser = @"dHDdpyuT54ib+W57JrI1TLeMMtbeZ58lNRNkyHyQaYg=";
    NSString *asyncServiceSession = @"57ACB9D2-9710-43DA-A81B-B528962016C4";
    NSString *helperSessionHistory = @"57ACB9D2-9710-43DA-A81B-B528962016C4";
    NSString *messageComponentTask = @"afff7d302d7bfdda476ed4b73ab11c43d4660ccf";
    NSString *asyncColumnFeature = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970] * 1000];

    NSString *cookie = @"HWWAFSESID=5da9a76401fa884f0a; HWWAFSESTIME=1787822905636";

    NSString *urlStr = [NSString stringWithFormat:@"https://meticulous.gxzmei.com/event/response/list?stateMemoryClient=%@", stateMemoryClient];
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

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            WriteLog(@"[TRIGGER-ERROR] %@", error.localizedDescription);
        } else {
            NSString *resp = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            WriteLog(@"[TRIGGER-RESPONSE] %@", resp ?: @"<binary>");
        }
    }];
    [task resume];
    WriteLog(@"[TRIGGER] VIP request sent to %@", urlStr);
}

@end

// ===================== Swizzling 工具 =====================
static void SwizzleInstanceMethod(Class cls, SEL origSel, SEL swizSel) {
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method swizMethod = class_getInstanceMethod(cls, swizSel);
    if (!origMethod || !swizMethod) return;
    if (class_addMethod(cls, origSel, method_getImplementation(swizMethod), method_getTypeEncoding(swizMethod))) {
        class_replaceMethod(cls, swizSel, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, swizMethod);
    }
}

static void SwizzleClassMethod(Class cls, SEL origSel, SEL swizSel) {
    Method origMethod = class_getClassMethod(cls, origSel);
    Method swizMethod = class_getClassMethod(cls, swizSel);
    if (!origMethod || !swizMethod) return;
    method_exchangeImplementations(origMethod, swizMethod);
}

// ===================== 初始化 =====================
static __attribute__((constructor)) void VIPHookInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        WriteLog(@"=== ElyndorTV VIP Hook Loaded ===");
        WriteLog(@"Log: %@", GetLogPath());

        Class reqCls = objc_getClass("NSURLRequest");
        if (reqCls) {
            SwizzleClassMethod(reqCls, @selector(requestWithURL:), @selector(vip_requestWithURL:));
            SwizzleInstanceMethod(reqCls, @selector(initWithURL:), @selector(vip_initWithURL:));
            WriteLog(@"[+] NSURLRequest swizzled");
        }

        Class mReqCls = objc_getClass("NSMutableURLRequest");
        if (mReqCls) {
            SwizzleInstanceMethod(mReqCls, @selector(setValue:forHTTPHeaderField:), @selector(vip_setValue:forHTTPHeaderField:));
            SwizzleInstanceMethod(mReqCls, @selector(addValue:forHTTPHeaderField:), @selector(vip_addValue:forHTTPHeaderField:));
            SwizzleInstanceMethod(mReqCls, @selector(initWithURL:), @selector(vip_initWithURL:));
            WriteLog(@"[+] NSMutableURLRequest swizzled");
        }

        Class sessionCls = objc_getClass("NSURLSession");
        if (sessionCls) {
            SwizzleInstanceMethod(sessionCls, @selector(dataTaskWithRequest:), @selector(vip_dataTaskWithRequest:));
            SwizzleInstanceMethod(sessionCls, @selector(dataTaskWithRequest:completionHandler:), @selector(vip_dataTaskWithRequest:completionHandler:));
            WriteLog(@"[+] NSURLSession swizzled");
        }

        Class wkCls = objc_getClass("WKWebView");
        if (wkCls) {
            SwizzleInstanceMethod(wkCls, @selector(evaluateJavaScript:completionHandler:), @selector(vip_evaluateJavaScript:completionHandler:));
            WriteLog(@"[+] WKWebView swizzled");
        }

        WriteLog(@"=== Setup complete. Click VIP button and check log ===");
    });
}
