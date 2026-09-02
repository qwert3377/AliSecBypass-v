//
//  WSCTPlugin.mm
//  WildSafeCareTech (李白浏览器) TrollStore Injection Plugin
//  Pure ObjC Runtime, no Logos / %hook
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <pthread.h>

static NSString *const LOG_TAG = @"[WSCT]";

// ============================================================================
// Recursion Guard (thread-local)
// ============================================================================
static pthread_key_t g_inHook;

static void setupRecursionGuard(void) {
    pthread_key_create(&g_inHook, NULL);
}

static BOOL isInHook(void) {
    return (BOOL)(uintptr_t)pthread_getspecific(g_inHook);
}

static void setInHook(BOOL val) {
    pthread_setspecific(g_inHook, (void *)(uintptr_t)val);
}

// ============================================================================
// Logging
// ============================================================================
static void wsct_log(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"%@ %@", LOG_TAG, msg);
}

// ============================================================================
// JSON Patch Helpers
// ============================================================================
static BOOL shouldPatchJson(NSString *str) {
    if (!str || str.length < 20) return NO;
    return [str containsString:@"\"point\""] ||
           [str containsString:@"\"adFreeEndtime\""] ||
           [str containsString:@"余额不足"] ||
           [str containsString:@"success":false"];
}

static NSString *patchJsonString(NSString *jsonStr, BOOL *outModified) {
    *outModified = NO;
    NSMutableString *result = [jsonStr mutableCopy];

    // 1. Patch point: "point":1 -> "point":999
    NSRegularExpression *pointRe = [NSRegularExpression
        regularExpressionWithPattern:@"\"point\"\s*:\s*([0-9]+)"
        options:0 error:nil];
    NSArray *pointMatches = [pointRe matchesInString:result
        options:0 range:NSMakeRange(0, result.length)];
    for (NSTextCheckingResult *match in [pointMatches reverseObjectEnumerator]) {
        NSRange valRange = [match rangeAtIndex:1];
        NSString *val = [result substringWithRange:valRange];
        if (![val isEqualToString:@"999"]) {
            wsct_log(@"PATCH point: %@ -> 999", val);
            [result replaceCharactersInRange:valRange withString:@"999"];
            *outModified = YES;
        }
    }

    // 2. Patch adFreeEndtime: "adFreeEndtime":0 -> "adFreeEndtime":4102444800
    NSRegularExpression *adFreeRe = [NSRegularExpression
        regularExpressionWithPattern:@"\"adFreeEndtime\"\s*:\s*([0-9]+)"
        options:0 error:nil];
    NSArray *adFreeMatches = [adFreeRe matchesInString:result
        options:0 range:NSMakeRange(0, result.length)];
    for (NSTextCheckingResult *match in [adFreeMatches reverseObjectEnumerator]) {
        NSRange valRange = [match rangeAtIndex:1];
        NSString *val = [result substringWithRange:valRange];
        if (![val isEqualToString:@"4102444800"]) {
            wsct_log(@"PATCH adFreeEndtime: %@ -> 4102444800", val);
            [result replaceCharactersInRange:valRange withString:@"4102444800"];
            *outModified = YES;
        }
    }

    // 3. Patch code != "200"
    NSRegularExpression *codeRe = [NSRegularExpression
        regularExpressionWithPattern:@"\"code\"\s*:\s*\"([^\"]+)\""
        options:0 error:nil];
    NSArray *codeMatches = [codeRe matchesInString:result
        options:0 range:NSMakeRange(0, result.length)];
    for (NSTextCheckingResult *match in [codeMatches reverseObjectEnumerator]) {
        NSRange valRange = [match rangeAtIndex:1];
        NSString *val = [result substringWithRange:valRange];
        if (![val isEqualToString:@"200"]) {
            wsct_log(@"PATCH code: %@ -> \"200\"", val);
            [result replaceCharactersInRange:valRange withString:@"200"];
            *outModified = YES;
        }
    }

    // 4. Patch success:false -> success:true
    NSRange sfRange = [result rangeOfString:@"\"success\":false"];
    if (sfRange.location != NSNotFound) {
        wsct_log(@"PATCH success: false -> true");
        [result replaceCharactersInRange:sfRange withString:@"\"success\":true"];
        *outModified = YES;
    }

    // 5. Patch msg: 余额不足 -> success
    if ([result containsString:@"余额不足"]) {
        NSRegularExpression *msgRe = [NSRegularExpression
            regularExpressionWithPattern:@"\"msg\"\s*:\s*\"[^\"]*\""
            options:0 error:nil];
        NSArray *msgMatches = [msgRe matchesInString:result
            options:0 range:NSMakeRange(0, result.length)];
        for (NSTextCheckingResult *match in [msgMatches reverseObjectEnumerator]) {
            wsct_log(@"PATCH msg -> success");
            [result replaceCharactersInRange:match.range withString:@"\"msg\":\"success\""];
            *outModified = YES;
        }
    }

    return result;
}

// ============================================================================
// 1. Hook NSJSONSerialization +JSONObjectWithData:options:error:
// ============================================================================
static id (*orig_JSONObjectWithData)(Class, SEL, NSData *, NSJSONReadingOptions, NSError **);

static id replaced_JSONObjectWithData(Class self, SEL _cmd, NSData *data,
                                       NSJSONReadingOptions opt, NSError **error) {
    id result = orig_JSONObjectWithData(self, _cmd, data, opt, error);
    if (!result) return result;
    if (isInHook()) return result;

    setInHook(YES);
    @try {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result
                                                           options:0 error:nil];
        if (!jsonData) { setInHook(NO); return result; }

        NSString *jsonStr = [[NSString alloc] initWithData:jsonData
                                                  encoding:NSUTF8StringEncoding];
        if (!jsonStr || jsonStr.length < 20) { setInHook(NO); return result; }

        if (!shouldPatchJson(jsonStr)) { setInHook(NO); return result; }

        wsct_log(@"Intercepted JSON (len=%lu)", (unsigned long)jsonStr.length);
        NSUInteger previewLen = jsonStr.length > 300 ? 300 : jsonStr.length;
        wsct_log(@"RAW: %@", [jsonStr substringToIndex:previewLen]);

        BOOL modified = NO;
        NSString *patchedStr = patchJsonString(jsonStr, &modified);

        if (modified) {
            NSUInteger patchedPreviewLen = patchedStr.length > 300 ? 300 : patchedStr.length;
            wsct_log(@"PATCHED: %@", [patchedStr substringToIndex:patchedPreviewLen]);

            NSData *patchedData = [patchedStr dataUsingEncoding:NSUTF8StringEncoding];
            if (patchedData) {
                id patchedObj = orig_JSONObjectWithData(self, _cmd, patchedData, opt, nil);
                if (patchedObj) {
                    wsct_log(@"Replaced JSON retval");
                    setInHook(NO);
                    return patchedObj;
                }
            }
        }
    } @catch (NSException *e) {
        wsct_log(@"Exception in JSON hook: %@", e);
    }
    setInHook(NO);
    return result;
}

// ============================================================================
// 2. Hook NSString -initWithData:encoding: (fallback)
// ============================================================================
static id (*orig_initWithData)(id, SEL, NSData *, NSStringEncoding);

static id replaced_initWithData(id self, SEL _cmd, NSData *data, NSStringEncoding encoding) {
    id result = orig_initWithData(self, _cmd, data, encoding);
    if (!result || ![result isKindOfClass:[NSString class]]) return result;
    if (isInHook()) return result;

    NSString *str = (NSString *)result;
    if (str.length < 30) return result;
    if (!shouldPatchJson(str)) return result;

    setInHook(YES);
    @try {
        wsct_log(@"Intercepted NSString (len=%lu)", (unsigned long)str.length);
        BOOL modified = NO;
        NSString *patchedStr = patchJsonString(str, &modified);
        if (modified) {
            wsct_log(@"Replaced NSString retval");
            setInHook(NO);
            return [NSString stringWithString:patchedStr];
        }
    } @catch (NSException *e) {
        wsct_log(@"Exception in NSString hook: %@", e);
    }
    setInHook(NO);
    return result;
}

// ============================================================================
// 3. Hook NSURLSession -dataTaskWithRequest: (logging only)
// ============================================================================
static NSURLSessionDataTask *(*orig_dataTaskWithRequest)(id, SEL, NSURLRequest *);

static NSURLSessionDataTask *replaced_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request) {
    @try {
        NSURL *url = request.URL;
        if (!url) return orig_dataTaskWithRequest(self, _cmd, request);

        NSString *urlStr = url.absoluteString;
        NSString *method = request.HTTPMethod ?: @"GET";

        if ([urlStr containsString:@"yiys07.com"] ||
            [urlStr containsString:@"exchange"] ||
            [urlStr containsString:@"convert"] ||
            [urlStr containsString:@"point"] ||
            [urlStr containsString:@"order"]) {
            wsct_log(@"TARGET [%@] %@", method, urlStr);
            if ([method isEqualToString:@"POST"] && request.HTTPBody) {
                NSString *body = [[NSString alloc] initWithData:request.HTTPBody
                                                       encoding:NSUTF8StringEncoding];
                if (body) wsct_log(@"BODY: %@", body);
            }
        }
    } @catch (NSException *e) {}
    return orig_dataTaskWithRequest(self, _cmd, request);
}

// ============================================================================
// Constructor - runs when dylib is loaded
// ============================================================================
__attribute__((constructor))
static void init_plugin(void) {
    setupRecursionGuard();
    wsct_log(@"Plugin loaded");

    // 1. Hook NSJSONSerialization class method
    Class jsonCls = objc_getClass("NSJSONSerialization");
    if (jsonCls) {
        Method m = class_getClassMethod(jsonCls, @selector(JSONObjectWithData:options:error:));
        if (m) {
            orig_JSONObjectWithData = (id (*)(Class, SEL, NSData *, NSJSONReadingOptions, NSError **))
                method_getImplementation(m);
            method_setImplementation(m, (IMP)replaced_JSONObjectWithData);
            wsct_log(@"Hooked NSJSONSerialization.JSONObjectWithData");
        }
    }

    // 2. Hook NSString instance method
    Class strCls = objc_getClass("NSString");
    if (strCls) {
        Method m = class_getInstanceMethod(strCls, @selector(initWithData:encoding:));
        if (m) {
            orig_initWithData = (id (*)(id, SEL, NSData *, NSStringEncoding))
                method_getImplementation(m);
            method_setImplementation(m, (IMP)replaced_initWithData);
            wsct_log(@"Hooked NSString.initWithData:encoding:");
        }
    }

    // 3. Hook NSURLSession instance method
    Class sessionCls = objc_getClass("NSURLSession");
    if (sessionCls) {
        Method m = class_getInstanceMethod(sessionCls, @selector(dataTaskWithRequest:));
        if (m) {
            orig_dataTaskWithRequest = (NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *))
                method_getImplementation(m);
            method_setImplementation(m, (IMP)replaced_dataTaskWithRequest);
            wsct_log(@"Hooked NSURLSession.dataTaskWithRequest:");
        }
    }

    wsct_log(@"All hooks installed");
}
