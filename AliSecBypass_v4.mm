// ButterflyTrialPatch.mm v2
// 每次启动: 0.5秒后删Keychain设备ID + 记录 + exit(0)
// 使用: 连点两次App图标 —— 第1次:删ID自杀; 第2次:新ID注册, 全新10分钟试用
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <dispatch/dispatch.h>

static void log_msg(NSString *msg) {
    @try {
        NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [doc stringByAppendingPathComponent:@"trial_patch.log"];
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) { [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
                  h = [NSFileHandle fileHandleForWritingAtPath:path]; }
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    } @catch (NSException *e) {}
}

static void swapAndExit(void) {
    // 1. 删 Keychain 设备ID
    NSDictionary *q = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: @"abitounid",
        (__bridge id)kSecAttrService: @"com.xiongying.ButterflyLinker"
    };
    OSStatus s = SecItemDelete((__bridge CFDictionaryRef)q);
    log_msg([NSString stringWithFormat:@"[Keychain] err=%d", (int)s]);
    // 2. 清服务器响应缓存
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *k in @[@"Dugayon",@"Mansanas",@"Mearind",@"Klase",@"Usuario",
                          @"Sausuario",@"Tandaan",@"Abitcoifugs",@"Session",@"Sesyon",@"Basihanan"]) {
        [ud removeObjectForKey:k];
    }
    [ud synchronize];
    log_msg(@"[缓存] 已清, 1秒后自杀");
    // 3. 给用户看日志的时间后自杀 —— 再次打开即新设备
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        exit(0);
    });
}

__attribute__((constructor)) static void tp_init(void) {
    // 关键修复: 等 App 完全启动、Security 服务就绪后再删
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ swapAndExit(); });
}
