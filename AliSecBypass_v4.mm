//
//  BaiduPan_ExperienceTrigger.mm
//  TrollStore inject plugin
//  v7 - 修复函数顺序编译错误
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kLogFile = @"trigger.log";
static NSMutableArray *gInstances = nil;
static UIButton *gFloatBtn = nil;
static id gFloatTarget = nil;
static id (*orig_init)(id self, SEL _cmd);

// ============================================================
// Hook init - 保存实例到全局数组强引用保活
// ============================================================
static id hook_init(id self, SEL _cmd) {
    id result = orig_init(self, _cmd);
    if (!gInstances) {
        gInstances = [[NSMutableArray alloc] init];
    }
    [gInstances addObject:result];
    logMsg([NSString stringWithFormat:@"capture instance, count=%lu", (unsigned long)gInstances.count]);

    return result;
}

// ============================================================
// 触发立即体验
// ============================================================
static void doTrigger(void) {
    id inst = gInstances.lastObject;
    if (inst) {
        logMsg(@"trigger start");
        SEL sel = NSSelectorFromString(@"edtc_flowEnhanceAction");
        if ([inst respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [inst performSelector:sel];
#pragma clang diagnostic pop
            logMsg(@"trigger ok");
        } else {
            logMsg(@"no selector");
        }
    } else {
        logMsg(@"no instance");
    }
}

// ============================================================
// 悬浮球点击目标
// ============================================================
@interface FloatTarget : NSObject
- (void)onTap:(id)sender;
@end

@implementation FloatTarget
- (void)onTap:(id)sender {
    logMsg(@"button tapped");
    doTrigger();
}
@end

// ============================================================
// 创建悬浮球
// ============================================================
static void createFloatButton(void) {
    if (gFloatBtn) return;
    CGFloat size = 55.0;
    CGFloat x = [UIScreen mainScreen].bounds.size.width - size - 15.0;
    CGFloat y = [UIScreen mainScreen].bounds.size.height / 2.0;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(x, y, size, size);
    btn.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.9];
    btn.layer.cornerRadius = size / 2.0;
    btn.layer.masksToBounds = YES;
    [btn setTitle:@"VIP" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    btn.userInteractionEnabled = YES;

    FloatTarget *target = [[FloatTarget alloc] init];
    gFloatTarget = target;
    [btn addTarget:target action:@selector(onTap:) forControlEvents:UIControlEventTouchUpInside];

    UIWindow *kw = getKeyWindow();
    if (kw) {
        [kw addSubview:btn];
        [kw bringSubviewToFront:btn];
        gFloatBtn = btn;
        logMsg(@"button created");
    } else {
        logMsg(@"no key window");
    }
}

// ============================================================
// 注入入口
// ============================================================
__attribute__((constructor))
static void initPlugin(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        logMsg(@"plugin loaded");

        Class ribbonClass = NSClassFromString(@"ElyndorTVCode.EDTCGuildFeatureRibbon");
        if (ribbonClass) {
            IMP origImp = class_replaceMethod(ribbonClass, @selector(init), (IMP)hook_init, "@@:");
            if (origImp) {
                orig_init = (id (*)(id, SEL))origImp;
                logMsg(@"init hooked (replaced)");
            } else {
                Class superClass = class_getSuperclass(ribbonClass);
                orig_init = (id (*)(id, SEL))class_getMethodImplementation(superClass, @selector(init));
                logMsg(@"init hooked (added)");
            }

            // 直接创建实例，hook_init 会自动捕获到 gInstances
            id ribbon = [[ribbonClass alloc] init];
            if (ribbon) {
                logMsg(@"pre-created ribbon instance");
            }
        } else {
            logMsg(@"class not found");
        }

        createFloatButton();
    });
}
