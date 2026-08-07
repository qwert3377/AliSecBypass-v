
// 在 my_dataTaskWithRequest 函数里，替换为以下内容：

static NSURLSessionDataTask *my_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request, void (^completionHandler)(NSData *, NSURLResponse *, NSError *)) {
    NSURL *url = request.URL;
    NSString *host = url.host ?: @"";

    // 只打印关键域名（避免日志爆炸）
    NSArray *logHosts = @[@"tnc", @"security", @"pitaya", @"mssdk", @"mon11", @"byteoversea", @"fqnovel", @"snssdk"];
    BOOL shouldLog = NO;
    for (NSString *kw in logHosts) {
        if ([host containsString:kw]) { shouldLog = YES; break; }
    }

    if (shouldLog) {
        NSMutableString *log = [NSMutableString stringWithFormat:@"\n========== REQUEST ==========\nURL: %@\nMethod: %@\nHeaders: %@\n", url.absoluteString, request.HTTPMethod, request.allHTTPHeaderFields];

        // 打印 Body（明文，未加密）
        if (request.HTTPBody) {
            // 尝试当 JSON 打印
            id json = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil];
            if (json) {
                [log appendFormat:@"Body(JSON): %@\n", json];
            } else {
                // protobuf 或二进制，打印 base64 和前 200 字节 hex
                NSString *base64 = [request.HTTPBody base64EncodedStringWithOptions:0];
                [log appendFormat:@"Body(Base64): %@\n", base64];

                // 打印前 64 字节 hex，方便分析
                NSUInteger len = MIN(request.HTTPBody.length, 64);
                NSMutableString *hex = [NSMutableString stringWithCapacity:len*3];
                const uint8_t *bytes = request.HTTPBody.bytes;
                for (NSUInteger i = 0; i < len; i++) {
                    [hex appendFormat:@"%02x ", bytes[i]];
                }
                [log appendFormat:@"Body(Hex): %@...\n", hex];
            }
        } else {
            [log appendString:@"Body: (empty)\n"];
        }
        [log appendString:@"==============================\n"];
        bypassLog(log);
    }

    // 拦截 blocked hosts
    if (isBlockedHost(host)) {
        bypassLog([NSString stringWithFormat:@"[NSURLSession] BLOCKED: %@", host]);
        NSURLSessionDataTask *dummy = ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dataTaskWithRequest)(self, _cmd, request, completionHandler);
        [dummy cancel];
        return dummy;
    }

    // 如果要解密返回数据，包装 completionHandler
    void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = nil;
    if (completionHandler && shouldLog) {
        wrappedHandler = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSMutableString *respLog = [NSMutableString stringWithFormat:@"\n========== RESPONSE ==========\nURL: %@\n", url.absoluteString];
            if (error) {
                [respLog appendFormat:@"Error: %@\n", error.localizedDescription];
            } else {
                NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
                [respLog appendFormat:@"Status: %ld\n", (long)httpResp.statusCode];
                if (data) {
                    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if (json) {
                        [respLog appendFormat:@"Data(JSON): %@\n", json];
                    } else {
                        NSString *base64 = [data base64EncodedStringWithOptions:0];
                        [respLog appendFormat:@"Data(Base64): %@\n", base64];
                    }
                }
            }
            [respLog appendString:@"==============================\n"];
            bypassLog(respLog);
            completionHandler(data, response, error);
        };
    }

    return ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *)))orig_dataTaskWithRequest)(self, _cmd, request, wrappedHandler ?: completionHandler);
}
