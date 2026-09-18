// BLConnSniff.mm —— 拦截连接/会员线路相关请求
// 日志: Documents/conn_req.log
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static void clog(NSString *msg) {
    @try {
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [doc stringByAppendingPathComponent:@"conn_req.log"];
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) { [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
                  h = [NSFileHandle fileHandleForWritingAtPath:path]; }
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    } @catch (NSException *e) {}
}

static NSString *bodyOf(NSURLRequest *req, NSData *extraData) {
    NSData *d = req.HTTPBody;
    if ((!d || d.length == 0) && extraData) d = extraData;
    if (!d || d.length == 0) {
        // HTTPBodyStream 尝试读
        NSInputStream *st = req.HTTPBodyStream;
        if (st) {
            [st open];
            NSMutableData *md = [NSMutableData data];
            uint8_t buf[4096]; NSInteger n;
            while ((n = [st read:buf maxLength:sizeof(buf)]) > 0) [md appendBytes:buf length:n];
            [st close];
            d = md;
        }
    }
    if (!d || d.length == 0) return @"(无body)";
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (!s) return [NSString stringWithFormat:@"(二进制 %lu 字节)", (unsigned long)d.length];
    return [s length] > 600 ? [s substringToIndex:600] : s;
}

static void dumpReq(NSURLRequest *req, NSData *extra, NSString *via) {
    @try {
        NSString *url = req.URL.absoluteString ?: @"(nil)";
        // 只记录 API 请求
        if (![url containsString:@"/lukso/"]) return;
        NSString *api = [url componentsSeparatedByString:@"/lukso/"].lastObject;
        clog(@"━━━━━━━━━━━━━━━━━━━━━━");
        clog([NSString stringWithFormat:@"[%@] %@ %@", via, req.HTTPMethod ?: @"?", api]);
        // Header 逐 key(防止被 description 吞 entry)
        NSDictionary *hs = req.allHTTPHeaderFields;
        for (NSString *k in hs) {
            clog([NSString stringWithFormat:@"  H %@ = %@", k, [hs[k] description].length > 80 ?
                  [[hs[k] description] substringToIndex:80] : [hs[k] description]]);
        }
        clog([NSString stringWithFormat:@"  BODY: %@", bodyOf(req, extra)]);
    } @catch (NSException *e) {}
}

// ---- hook 1: dataTaskWithRequest:completionHandler: ----
typedef id (*DT1)(id, SEL, NSURLRequest *, id);
static DT1 orig_dt1 = NULL;
static id my_dt1(id self, SEL _cmd, NSURLRequest *req, id completionHandler) {
    dumpReq(req, nil, @"dt1");
    return orig_dt1(self, _cmd, req, completionHandler);
}

// ---- hook 2: dataTaskWithRequest: (delegate 模式, 之前抓到的是这条) ----
typedef id (*DT2)(id, SEL, NSURLRequest *);
static DT2 orig_dt2 = NULL;
static id my_dt2(id self, SEL _cmd, NSURLRequest *req) {
    dumpReq(req, nil, @"dt2");
    return orig_dt2(self, _cmd, req);
}

// ---- hook 3: uploadTaskWithRequest:fromData: (multipart POST 走这条) ----
typedef id (*DT3)(id, SEL, NSURLRequest *, NSData *);
static DT3 orig_dt3 = NULL;
static id my_dt3(id self, SEL _cmd, NSURLRequest *req, NSData *body) {
    dumpReq(req, body, @"upload");
    return orig_dt3(self, _cmd, req, body);
}

__attribute__((constructor)) static void init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        int n = 0;
        Class cls = objc_getClass("NSURLSession");
        if (cls) {
            Method m;
            m = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
            if (m) { orig_dt1 = (DT1)method_setImplementation(m, (IMP)my_dt1); n++; }
            m = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:));
            if (m) { orig_dt2 = (DT2)method_setImplementation(m, (IMP)my_dt2); n++; }
            m = class_getInstanceMethod(cls, @selector(uploadTaskWithRequest:fromData:));
            if (m) { orig_dt3 = (DT3)method_setImplementation(m, (IMP)my_dt3); n++; }
        }
        clog([NSString stringWithFormat:@"[init] hooked %d 个入口", n]);
    });
}
