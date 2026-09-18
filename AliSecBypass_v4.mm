// BLSwap v2 —— 修 Scene 兼容 + 全程日志
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

static NSUUID *g_fakeIdfv = nil;
static UIWindow *g_win = nil;
static NSString *g_logPath = nil;

static void slog(NSString *msg) {
    @try {
        if (!g_logPath) {
            NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            g_logPath = [doc stringByAppendingPathComponent:@"swap.log"];
        }
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:g_logPath];
        if (!h) { [[NSFileManager defaultManager] createFileAtPath:g_logPath contents:nil attributes:nil];
                  h = [NSFileHandle fileHandleForWritingAtPath:g_logPath]; }
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    } @catch (...) {}
}

static NSString *randomUUID(void) {
    NSMutableString *s = [NSMutableString stringWithString:@"xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"];
    for (NSInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == 'x' || c == 'y') {
            u_int32_t r = arc4random_uniform(16);
            if (c == 'y') r = (r & 0x3) | 0x8;
            [s replaceCharactersInRange:NSMakeRange(i, 1)
                             withString:[NSString stringWithFormat:@"%X", r]];
        }
    }
    return s;
}

#pragma mark - hook IDFV
static id (*orig_idfv)(UIDevice *, SEL);
static id my_idfv(UIDevice *self, SEL _cmd) {
    if (!g_fakeIdfv) {
        g_fakeIdfv = [[NSUUID alloc] initWithUUIDString:randomUUID()];
        slog([NSString stringWithFormat:@"[IDFV] %@", g_fakeIdfv.UUIDString]);
    }
    return g_fakeIdfv;
}

#pragma mark - 换号
static void doSwapAndExit(void) {
    slog(@"[点击] 换号开始");
    typedef int (*SecItemDeleteFn)(CFDictionaryRef);
    void *sec = dlsym(RTLD_DEFAULT, "SecItemDelete");
    if (sec) {
        NSDictionary *q = @{@"class": @"genp", @"acct": @"abitounid",
                            @"svce": @"com.xiongying.ButterflyLinker"};
        int err = ((SecItemDeleteFn)sec)((__bridge CFDictionaryRef)q);
        slog([NSString stringWithFormat:@"[KC] 删除 abitounid err=%d", err]);
    } else {
        slog(@"[KC] dlsym SecItemDelete 失败!");
    }
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *k in @[@"Sausuario", @"Tandaan", @"Usuario", @"Session", @"Sesyon",
                          @"Dugayon", @"Mansanas", @"Mearind", @"Klase",
                          @"Abitcoifugs", @"Bitasyon", @"Libutan", @"Adlaw",
                          @"Liyente", @"Tananas", @"Abitproducts"]) {
        [ud removeObjectForKey:k];
    }
    [ud synchronize];
    slog(@"[缓存] 已清 → 0.4秒后自杀");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ exit(0); });
}

@interface BLSwapper : NSObject
@end
@implementation BLSwapper
- (void)swapTapped { doSwapAndExit(); }
@end

#pragma mark - 悬浮按钮 (修 iOS13+ Scene 兼容)
static void addFloatingButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app = UIApplication.sharedApplication;
        // iOS13+ 必须挂 windowScene
        UIWindowScene *targetScene = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *s in app.connectedScenes) {
                if ([s isKindOfClass:UIWindowScene.class] &&
                    s.activationState == UISceneActivationStateForegroundActive) {
                    targetScene = (UIWindowScene *)s;
                    break;
                }
            }
            if (!targetScene) {
                for (UIScene *s in app.connectedScenes) {
                    if ([s isKindOfClass:UIWindowScene.class]) { targetScene = (UIWindowScene *)s; break; }
                }
            }
        }
        slog([NSString stringWithFormat:@"[UI] scene=%@ scenes=%lu",
              targetScene ? @"找到" : @"无!", (unsigned long)app.connectedScenes.count]);

        CGRect screen = UIScreen.mainScreen.bounds;
        g_win = [[UIWindow alloc] initWithFrame:CGRectMake(screen.size.width - 70, 130, 56, 56)];
        if (@available(iOS 13.0, *)) {
            g_win.windowScene = targetScene;   // ← 关键! 不挂 scene 不显示
        }
        g_win.windowLevel = UIWindowLevelAlert + 1;
        g_win.backgroundColor = UIColor.clearColor;

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = g_win.bounds;
        btn.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.95 alpha:0.9];
        btn.layer.cornerRadius = 28;
        btn.layer.borderWidth = 2;
        btn.layer.borderColor = UIColor.whiteColor.CGColor;
        [btn setTitle:@"换" forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:22];
        static BLSwapper *swapper = nil;
        swapper = [[BLSwapper alloc] init];
        [btn addTarget:swapper action:@selector(swapTapped) forControlEvents:UIControlEventTouchUpInside];
        [g_win addSubview:btn];
        g_win.hidden = NO;
        [g_win makeKeyAndVisible];
        slog(@"[UI] 按钮已创建并显示");
    });
}

__attribute__((constructor)) static void init(void) {
    slog(@"[init] 插件加载");
    Class devCls = objc_getClass("UIDevice");
    if (devCls) {
        Method m = class_getInstanceMethod(devCls, @selector(identifierForVendor));
        if (m) {
            orig_idfv = (id (*)(UIDevice *, SEL))method_setImplementation(m, (IMP)my_idfv);
            slog(@"[init] IDFV hooked");
        }
    }
    // 等 App 完全进入前台再挂按钮, 重试3次防 scene 未激活
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ addFloatingButton(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!g_win || g_win.hidden) { slog(@"[UI] 2秒时未成功,5秒重试"); addFloatingButton(); }
    });
}
