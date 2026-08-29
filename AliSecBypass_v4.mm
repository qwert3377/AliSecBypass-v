//
//  KuwoVIPCrack.mm - 弹窗测试版
//  如果注入成功，启动App必定弹Alert
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// 弹窗确认注入是否生效
static void showInjectAlert(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    window = [[UIWindow alloc] initWithWindowScene:scene];
                    break;
                }
            }
        }
        if (!window) {
            window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        }
        window.windowLevel = UIWindowLevelAlert + 1;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"KuwoVIP"
                                                                       message:@"注入成功！\n看到此弹窗说明dylib已加载"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];

        UIViewController *root = [[UIViewController alloc] init];
        window.rootViewController = root;
        [window makeKeyAndVisible];
        [root presentViewController:alert animated:YES completion:nil];
    });
}

// 写文件确认（多路径尝试）
static void writeTestFiles(void) {
    NSString *msg = @"[KuwoVIP] injected\n";
    NSData *d = [msg dataUsingEncoding:NSUTF8StringEncoding];

    // 路径1: /tmp/
    [d writeToFile:@"/tmp/kuwo_vip_injected.txt" atomically:YES];

    // 路径2: App Documents
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (docs.count > 0) {
        NSString *p = [docs[0] stringByAppendingPathComponent:@"kuwo_vip_injected.txt"];
        [d writeToFile:p atomically:YES];
    }

    // 路径3: Library/Caches
    NSArray *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    if (caches.count > 0) {
        NSString *p = [caches[0] stringByAppendingPathComponent:@"kuwo_vip_injected.txt"];
        [d writeToFile:p atomically:YES];
    }

    // 路径4: 用户目录
    NSString *home = NSHomeDirectory();
    if (home) {
        NSString *p = [home stringByAppendingPathComponent:@"kuwo_vip_injected.txt"];
        [d writeToFile:p atomically:YES];
    }
}

__attribute__((constructor))
static void test_init(void) {
    // 1. 写文件（不管有没有UI都能验证）
    writeTestFiles();

    // 2. 弹窗（必须在主线程，延迟确保UI已初始化）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        showInjectAlert();
    });
}
