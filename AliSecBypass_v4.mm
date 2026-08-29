//
//  KuwoVIPCrack.mm - 极简测试版
//  先确认注入是否生效，再逐步加功能
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ========== 第一步：验证注入 ==========
// 编译注入后，打开App，在macOS控制台或Xcode设备日志中搜索 "KuwoVIPTest"
// 如果看不到这行日志，说明dylib根本没加载

__attribute__((constructor))
static void test_init(void) {
    // 用多种方式输出，确保至少有一种能被捕获
    NSLog(@"[KuwoVIPTest] ========== INJECTED ==========");
    printf("[KuwoVIPTest] printf injected\n");

    // 尝试写文件到多个位置
    NSString *msg = @"[KuwoVIPTest] injected at launch\n";
    NSData *d = [msg dataUsingEncoding:NSUTF8StringEncoding];

    // 尝试 /tmp/
    [@"[KuwoVIPTest] /tmp test\n" writeToFile:@"/tmp/kuwo_test.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // 尝试 Documents
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = paths.firstObject;
    if (doc) {
        NSString *p = [doc stringByAppendingPathComponent:@"kuwo_test.log"];
        [d writeToFile:p atomically:YES];
    }

    // 尝试 Library/Caches
    paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cache = paths.firstObject;
    if (cache) {
        NSString *p = [cache stringByAppendingPathComponent:@"kuwo_test.log"];
        [d writeToFile:p atomically:YES];
    }
}

// ========== 第二步：如果上面能看到日志，取消注释下面的代码 ==========
/*
static NSString *kFake = @"{\"ctime\":2000000000,\"data\":{\"uid\":\"0\",\"vipExpire\":\"2000000000\",\"svipExpire\":\"2000000000\",\"level\":\"10\",\"userType\":\"3\",\"vipTag\":\"SVIP\"},\"meta\":{\"code\":200}}";

static BOOL isVIPKey(NSString *k) {
    return k && ([k rangeOfString:@"VIP_INFO"].location != NSNotFound);
}

typedef id (*ofk_t)(id,SEL,id); static ofk_t o_ofk = NULL;
static id h_ofk(id s, SEL c, id k) {
    id r = o_ofk(s,c,k);
    if (isVIPKey(k)) { NSLog(@"[KuwoVIP] FAKE %@", k); return [kFake copy]; }
    return r;
}

typedef id (*js_t)(Class,SEL,NSData*,NSJSONReadingOptions,NSError**); static js_t o_js = NULL;
static id h_js(Class cls, SEL c, NSData *d, NSJSONReadingOptions opt, NSError **e) {
    id r = o_js(cls,c,d,opt,e);
    if (![r isKindOfClass:[NSDictionary class]]) return r;
    NSDictionary *dict = r;
    id dataObj = dict[@"data"];
    NSDictionary *dd = dataObj && [dataObj isKindOfClass:[NSDictionary class]] ? dataObj : dict;
    if (!dd[@"vipExpire"] && !dd[@"expireTime"]) return r;
    NSLog(@"[KuwoVIP] JSON PATCH");
    NSMutableDictionary *nd = [NSMutableDictionary dictionaryWithDictionary:dict];
    NSMutableDictionary *ndd = dataObj ? [NSMutableDictionary dictionaryWithDictionary:dd] : nd;
    NSArray *keys = @[@"expireTime",@"vipExpire",@"svipExpire",@"level",@"userType"];
    for (NSString *k in keys) {
        id v = ndd[k]; if (!v) continue;
        int n = [v intValue];
        if ([k isEqualToString:@"expireTime"] || [k isEqualToString:@"vipExpire"] || [k isEqualToString:@"svipExpire"]) {
            if (n > 0 && n < 2000000000) { ndd[k] = @2000000000; NSLog(@"[KuwoVIP] %@ patched", k); }
        } else if ([k isEqualToString:@"level"]) {
            if (n < 10) { ndd[k] = @10; NSLog(@"[KuwoVIP] level patched"); }
        } else if ([k isEqualToString:@"userType"]) {
            if (n == 0 || n == 2) { ndd[k] = @3; NSLog(@"[KuwoVIP] userType patched"); }
        }
    }
    NSString *tag = ndd[@"vipTag"];
    if ([tag isKindOfClass:[NSString class]] && [tag rangeOfString:@"VIP"].location != NSNotFound) {
        ndd[@"vipTag"] = @"SVIP"; NSLog(@"[KuwoVIP] vipTag patched");
    }
    if (dataObj) nd[@"data"] = ndd;
    return nd;
}

typedef id (*dt_t)(id,SEL,NSURLRequest*); static dt_t o_dt = NULL;
static id h_dt(id s, SEL c, NSURLRequest *req) {
    NSString *u = req.URL.absoluteString;
    if (u && [u rangeOfString:@"isVip=0" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        NSString *nu = [u stringByReplacingOccurrencesOfString:@"isVip=0" withString:@"isVip=1" options:NSCaseInsensitiveSearch range:NSMakeRange(0,u.length)];
        NSMutableURLRequest *nr = [req mutableCopy]; nr.URL = [NSURL URLWithString:nu];
        NSLog(@"[KuwoVIP] NET patched"); return o_dt(s,c,nr);
    }
    return o_dt(s,c,req);
}

static void hookIM(Class cls, SEL sel, IMP n, IMP *o) {
    Method m = class_getInstanceMethod(cls, sel);
    if (m) *o = method_setImplementation(m, n);
}
static void hookCM(Class cls, SEL sel, IMP n, IMP *o) {
    Method m = class_getClassMethod(cls, sel);
    if (m) *o = method_setImplementation(m, n);
}

__attribute__((constructor))
static void init(void) {
    NSLog(@"[KuwoVIP] === LOAD ===");
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    for (NSString *k in [defs dictionaryRepresentation].allKeys) {
        if (isVIPKey(k)) { [defs setObject:kFake forKey:k]; NSLog(@"[KuwoVIP] INJECT %@", k); }
    }
    [defs synchronize];
    Class ud = [NSUserDefaults class];
    hookIM(ud, @selector(objectForKey:), (IMP)h_ofk, (IMP*)&o_ofk);
    hookCM([NSJSONSerialization class], @selector(JSONObjectWithData:options:error:), (IMP)h_js, (IMP*)&o_js);
    hookIM([NSURLSession class], @selector(dataTaskWithRequest:), (IMP)h_dt, (IMP*)&o_dt);
    NSLog(@"[KuwoVIP] === DONE ===");
}
*/
