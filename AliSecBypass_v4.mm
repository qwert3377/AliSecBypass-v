//
//  BaiduPan_ExperienceTrigger.mm
//  TrollStore inject plugin
//  v8 - 预创建用 initWithFrame:，解决空壳问题
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kLogFile = @"trigger.log";
static NSMutableArray *gInstances = nil;
static UIButton *gFloatBtn = nil;
static id gFloatTarget = nil;
static id (*orig_init)(id self, SEL _cmd);

static void logMsg(NSString *msg) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = paths[0];
    NSString *path = [doc stringByAppendingPathComponent:kLogFile];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"HH:mm:ss"];
    NSString *ts = [fmt stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

static UIWindow* getKeyWindow(void) {
    UIWindow *result = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in ws.windows) {
                        if (w.isKeyWindow) {
                            result = w;
                            break;
                        }
                    }
                    if (result) break;
                }
            }
        }
        if (!result) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    for (UIWindow *w in ws.windows) {
                        if (w.isKeyWindow) {
                            result = w;
                            break;
                        }
                    }
                    if (result) break;
                }
            }
        }
    }
    return result;
}

static id hook_init(id self, SEL _cmd) {
    id result = orig_init(self, _cmd);
    if (!gInstances) {
        gInstances = [[NSMutableArray alloc] init];
    }
    [gInstances addObject:result];
    logMsg([NSString stringWithFormat:@"capture instance, count=%lu", (unsigned long)gInstances.count]);
    return result;
}

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

@interface FloatTarget : NSObject
- (void)onTap:(id)sender;
@end

@implementation FloatTarget
- (void)onTap:(id)sender {
    logMsg(@"button tapped");
    doTrigger();
}
@end

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
// 预创建实例 - 关键修复：用 initWithFrame: 而不是 init
// ============================================================
static void precreateInstance(void) {
    Class ribbonClass = NSClassFromString(@"ElyndorTVCode.EDTCGuildFeatureRibbon");
    if (!ribbonClass) {
        logMsg(@"precreate: class not found");
        return;
    }
    
    if (!gInstances) {
        gInstances = [[NSMutableArray alloc] init];
    }
    
    // 关键：用 initWithFrame: 而不是 init
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGRect frame = CGRectMake(0, 0, screenW, 48.0);
    id inst = [[ribbonClass alloc] initWithFrame:frame];
    
    if (inst) {
        [gInstances addObject:inst];
        logMsg([NSString stringWithFormat:@"precreate: initWithFrame ok, count=%lu", (unsigned long)gInstances.count]);
        
        SEL sel = NSSelectorFromString(@"edtc_flowEnhanceAction");
        if ([inst respondsToSelector:sel]) {
            logMsg(@"precreate: has selector");
        } else {
            logMsg(@"precreate: no selector");
        }
    } else {
        logMsg(@"precreate: initWithFrame failed");
    }
}

__attribute__((constructor))
static void initPlugin(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
        } else {
            logMsg(@"class not found");
        }
        
        // 预创建实例（关键：用 initWithFrame:）
        precreateInstance();
        
        createFloatButton();
    });
}
