//
//  ElyndorTV_NetworkHook.mm
//  TrollStore injectable dylib
//  Hook NSURLSession to capture gxzmei.com traffic
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <execinfo.h>

static NSString *const kTargetDomain = @"gxzmei.com";
static NSString *const kLogDirName   = @"ElyndorTV_Logs";
static NSString *gLogPath = nil;

// ===================== 日志工具 =====================
static NSString* GetLogPath(void) {
    if (gLogPath) return gLogPath;

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths firstObject];
    if (!docDir) {
        docDir = @"/var/mobile/Documents";
    }
    NSString *logDir = [docDir stringByAppendingPathComponent:kLogDirName];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:logDir]) {
        [fm createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
    NSString *filename = [NSString stringWithFormat:@"network_%@.log", [df stringFromDate:[NSDate date]]];
    gLogPath = [logDir stringByAppendingPathComponent:filename];
    return gLogPath;
}

static void WriteLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *ts = [NSString stringWithFormat:@"[%@] %@\n",
                    [[NSDate date] description], msg];

    NSData *data = [ts dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:GetLogPath()];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    } else {
        [data writeToFile:GetLogPath() atomically:YES];
    }

    // 同时输出到控制台
    NSLog(@"[ElyndorTV] %@", msg);
}

// ===================== 请求描述 =====================
static NSString* DescribeRequest(NSURLRequest *req) {
    if (!req) return @"<nil request>";
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"\n  URL: %@", req.URL.absoluteString];
    [s appendFormat:@"\n  Method: %@", req.HTTPMethod ?: @"GET"];
    [s appendFormat:@"\n  Headers: %@", req.allHTTPHeaderFields ?: @{}];
    if (req.HTTPBody) {
        NSString *body = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding];
        [s appendFormat:@"\n  Body: %@", body ?: @"<binary>"];
    }
    return s;
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

// ===================== Swizzling 工具 =====================
static void SwizzleMethod(Class cls, SEL origSel, SEL swizSel) {
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method swizMethod = class_getInstanceMethod(cls, swizSel);
    if (!origMethod || !swizMethod) return;

    BOOL didAdd = class_addMethod(cls, origSel,
                                  method_getImplementation(swizMethod),
                                  method_getTypeEncoding(swizMethod));
    if (didAdd) {
        class_replaceMethod(cls, swizSel,
                            method_getImplementation(origMethod),
                            method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, swizMethod);
    }
}

// ===================== NSURLSession Hook =====================
@interface NSURLSession (ElyndorTVHook)
@end

@implementation NSURLSession (ElyndorTVHook)

// Hook: dataTaskWithRequest:completionHandler:
- (NSURLSessionDataTask *)elyndor_dataTaskWithRequest:(NSURLRequest *)request
                                    completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSString *url = request.URL.absoluteString;
    if (IsTargetURL(url)) {
        WriteLog(@"[BLOCK] dataTaskWithRequest:completionHandler:%@%@",
                 DescribeRequest(request), GetStackTrace());
    }

    void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = completionHandler;
    if (IsTargetURL(url) && completionHandler) {
        wrappedHandler = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            NSString *dataStr = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"<nil>";
            WriteLog(@"[RESPONSE] URL: %@ | Status: %ld | Data: %@",
                     url, (long)httpResp.statusCode,
                     dataStr.length > 2000 ? [dataStr substringToIndex:2000] : dataStr);
            completionHandler(data, response, error);
        };
    }

    return [self elyndor_dataTaskWithRequest:request completionHandler:wrappedHandler];
}

// Hook: dataTaskWithRequest: (delegate 版本)
- (NSURLSessionDataTask *)elyndor_dataTaskWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;
    if (IsTargetURL(url)) {
        WriteLog(@"[DELEGATE] dataTaskWithRequest:%@%@",
                 DescribeRequest(request), GetStackTrace());
    }
    return [self elyndor_dataTaskWithRequest:request];
}

// Hook: dataTaskWithURL:completionHandler:
- (NSURLSessionDataTask *)elyndor_dataTaskWithURL:(NSURL *)url
                                completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSString *urlStr = url.absoluteString;
    if (IsTargetURL(urlStr)) {
        WriteLog(@"[BLOCK-URL] dataTaskWithURL: %@%@", urlStr, GetStackTrace());
    }
    return [self elyndor_dataTaskWithURL:url completionHandler:completionHandler];
}

// Hook: downloadTaskWithRequest:completionHandler:
- (NSURLSessionDownloadTask *)elyndor_downloadTaskWithRequest:(NSURLRequest *)request
                                            completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    NSString *url = request.URL.absoluteString;
    if (IsTargetURL(url)) {
        WriteLog(@"[DOWNLOAD-BLOCK] downloadTaskWithRequest:completionHandler:%@%@",
                 DescribeRequest(request), GetStackTrace());
    }
    return [self elyndor_downloadTaskWithRequest:request completionHandler:completionHandler];
}

// Hook: uploadTaskWithRequest:fromData:completionHandler:
- (NSURLSessionUploadTask *)elyndor_uploadTaskWithRequest:(NSURLRequest *)request
                                                 fromData:(NSData *)bodyData
                                        completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSString *url = request.URL.absoluteString;
    if (IsTargetURL(url)) {
        WriteLog(@"[UPLOAD-BLOCK] uploadTaskWithRequest:fromData:completionHandler:%@%@",
                 DescribeRequest(request), GetStackTrace());
    }
    return [self elyndor_uploadTaskWithRequest:request fromData:bodyData completionHandler:completionHandler];
}

@end

// ===================== NSURLConnection Hook (legacy) =====================
@interface NSURLConnection (ElyndorTVHook)
@end

@implementation NSURLConnection (ElyndorTVHook)

+ (NSData *)elyndor_sendSynchronousRequest:(NSURLRequest *)request
                         returningResponse:(NSURLResponse *__autoreleasing *)response
                                     error:(NSError *__autoreleasing *)error {
    NSString *url = request.URL.absoluteString;
    if (IsTargetURL(url)) {
        WriteLog(@"[SYNC] sendSynchronousRequest:%@%@",
                 DescribeRequest(request), GetStackTrace());
    }
    NSData *data = [self elyndor_sendSynchronousRequest:request returningResponse:response error:error];
    if (IsTargetURL(url) && data) {
        NSString *respStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        WriteLog(@"[SYNC-RESPONSE] URL: %@ | Data: %@",
                 url, respStr.length > 2000 ? [respStr substringToIndex:2000] : respStr);
    }
    return data;
}

@end

// ===================== NSURLRequest Hook (追踪创建) =====================
@interface NSURLRequest (ElyndorTVHook)
@end

@implementation NSURLRequest (ElyndorTVHook)

+ (instancetype)elyndor_requestWithURL:(NSURL *)URL {
    NSString *url = URL.absoluteString;
    if (IsTargetURL(url)) {
        WriteLog(@"[REQ-CREATE] +requestWithURL: %@%@", url, GetStackTrace());
    }
    return [self elyndor_requestWithURL:URL];
}

- (instancetype)elyndor_initWithURL:(NSURL *)URL {
    NSString *url = URL.absoluteString;
    if (IsTargetURL(url)) {
        WriteLog(@"[REQ-CREATE] -initWithURL: %@%@", url, GetStackTrace());
    }
    return [self elyndor_initWithURL:URL];
}

@end

// ===================== NSURL Hook (追踪 URL 创建) =====================
@interface NSURL (ElyndorTVHook)
@end

@implementation NSURL (ElyndorTVHook)

+ (instancetype)elyndor_URLWithString:(NSString *)URLString {
    if (IsTargetURL(URLString)) {
        WriteLog(@"[URL-CREATE] +URLWithString: %@%@", URLString, GetStackTrace());
    }
    return [self elyndor_URLWithString:URLString];
}

@end

// ===================== 初始化 =====================
static __attribute__((constructor)) void ElyndorTVInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        WriteLog(@"=== ElyndorTV Network Hook Loaded ===");
        WriteLog(@"Log path: %@", GetLogPath());

        // Swizzle NSURLSession
        Class sessionCls = objc_getClass("NSURLSession");
        if (sessionCls) {
            SwizzleMethod(sessionCls,
                          @selector(dataTaskWithRequest:completionHandler:),
                          @selector(elyndor_dataTaskWithRequest:completionHandler:));
            SwizzleMethod(sessionCls,
                          @selector(dataTaskWithRequest:),
                          @selector(elyndor_dataTaskWithRequest:));
            SwizzleMethod(sessionCls,
                          @selector(dataTaskWithURL:completionHandler:),
                          @selector(elyndor_dataTaskWithURL:completionHandler:));
            SwizzleMethod(sessionCls,
                          @selector(downloadTaskWithRequest:completionHandler:),
                          @selector(elyndor_downloadTaskWithRequest:completionHandler:));
            SwizzleMethod(sessionCls,
                          @selector(uploadTaskWithRequest:fromData:completionHandler:),
                          @selector(elyndor_uploadTaskWithRequest:fromData:completionHandler:));
            WriteLog(@"[+] NSURLSession swizzled");
        }

        // Swizzle NSURLConnection
        Class connCls = objc_getClass("NSURLConnection");
        if (connCls) {
            Method orig = class_getClassMethod(connCls, @selector(sendSynchronousRequest:returningResponse:error:));
            Method swiz = class_getClassMethod(connCls, @selector(elyndor_sendSynchronousRequest:returningResponse:error:));
            if (orig && swiz) method_exchangeImplementations(orig, swiz);
            WriteLog(@"[+] NSURLConnection swizzled");
        }

        // Swizzle NSURLRequest
        Class reqCls = objc_getClass("NSURLRequest");
        if (reqCls) {
            Method orig1 = class_getClassMethod(reqCls, @selector(requestWithURL:));
            Method swiz1 = class_getClassMethod(reqCls, @selector(elyndor_requestWithURL:));
            if (orig1 && swiz1) method_exchangeImplementations(orig1, swiz1);

            Method orig2 = class_getInstanceMethod(reqCls, @selector(initWithURL:));
            Method swiz2 = class_getInstanceMethod(reqCls, @selector(elyndor_initWithURL:));
            if (orig2 && swiz2) method_exchangeImplementations(orig2, swiz2);
            WriteLog(@"[+] NSURLRequest swizzled");
        }

        // Swizzle NSURL
        Class urlCls = objc_getClass("NSURL");
        if (urlCls) {
            Method orig = class_getClassMethod(urlCls, @selector(URLWithString:));
            Method swiz = class_getClassMethod(urlCls, @selector(elyndor_URLWithString:));
            if (orig && swiz) method_exchangeImplementations(orig, swiz);
            WriteLog(@"[+] NSURL swizzled");
        }

        WriteLog(@"=== Hook setup complete, operate App ===");
    });
}
