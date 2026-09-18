// BLSwap.mm —— ButterflyLinker 手动换号插件
// 逻辑: 平时启动身份不变(Keychain保留) → 点悬浮"换"按钮 → 删Keychain旧ID+清凭据 → 自杀
//       → 手动重开App = 全新IDFV注册新设备 (需配合换IP防风控)
// 悬浮按钮: 蓝色圆钮"换", 位于屏幕右上, 单击即执行
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

static NSUUID *g_fakeIdfv = nil;
static UIWindow *g_win = nil;

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

#pragma mark - hook: IDFV 每次启动随机 (注册新设备的关键)
static id (*orig_idfv)(UIDevice *, SEL);
static id my_idfv(UIDevice *self, SEL _cmd) {
    if (!g_fakeIdfv) {
        g_fakeIdfv = [[NSUUID alloc] initWithUUIDString:randomUUID()];
    }
    return g_fakeIdfv;
}

#pragma mark - 换号核心: 删Keychain + 清凭据 + 自杀
static void doSwapAndExit(void) {
    // 1. 删 Keychain 设备ID (dlsym 免链接 Security)
    typedef int (*SecItemDeleteFn)(CFDictionaryRef);
    void *sec = dlsym(RTLD_DEFAULT, "SecItemDelete");
    if (sec) {
        NSDictionary *q = @{@"class": @"genp",
                            @"acct": @"abitounid",
                            @"svce": @"com.xiongying.ButterflyLinker"};
        ((SecItemDeleteFn)sec)((__bridge CFDictionaryRef)q);
    }
    // 2. 清服务器响应缓存 + 登录凭据 (v7验证过的全集, 漏一个换号失败)
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *k in @[@"Sausuario", @"Tandaan", @"Usuario",      // 凭据(核心!)
                          @"Session", @"Sesyon", @"Sessionid",
                          @"Dugayon", @"Mansanas", @"Mearind", @"Klase",
                          @"Abitcoifugs", @"Bitasyon", @"Libutan", @"Adlaw",
                          @"Liyente", @"Tananas", @"Abitproducts",
                          @"Is_today_vip", @"Pay_switch", @"Is_real"]) {
        [ud removeObjectForKey:k];
    }
    [ud synchronize];
    // 3. 0.4秒后自杀 → 用户手动重开App = 新设备+新试用
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        exit(0);
    });
}

@interface BLSwapper : NSObject
@end
@implementation BLSwapper
- (void)swapTapped {
    doSwapAndExit();
}
@end

#pragma mark - 悬浮按钮
static void addFloatingButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect screen = UIScreen.mainScreen.bounds;
        g_win = [[UIWindow alloc] initWithFrame:CGRectMake(screen.size.width - 70, 130, 56, 56)];
        g_win.windowLevel = UIWindowLevelAlert + 1;
        g_win.backgroundColor = [UIColor clearColor];

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = g_win.bounds;
        btn.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.95 alpha:0.88];
        btn.layer.cornerRadius = 28;
        btn.layer.borderWidth = 1.5;
        btn.layer.borderColor = [UIColor whiteColor].CGColor;
        [btn setTitle:@"换" forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:22];
        static BLSwapper *swapper = nil;
        swapper = [[BLSwapper alloc] init];
        [btn addTarget:swapper action:@selector(swapTapped)
      forControlEvents:UIControlEventTouchUpInside];
        [g_win addSubview:btn];
        g_win.hidden = NO;
    });
}

__attribute__((constructor)) static void init(void) {
    // hook IDFV (每次启动新随机身份)
    Class devCls = objc_getClass("UIDevice");
    if (devCls) {
        Method m = class_getInstanceMethod(devCls, @selector(identifierForVendor));
        if (m) orig_idfv = (id (*)(UIDevice *, SEL))method_setImplementation(m, (IMP)my_idfv);
    }
    // 2秒后挂悬浮按钮(等App界面起来)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ addFloatingButton(); });
}
