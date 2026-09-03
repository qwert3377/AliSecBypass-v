// Tailscale iOS Chinese Patch
// TrollStore / Theos compatible, pure ObjC Runtime, no Logos syntax
// Compile: just this single .mm file

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <objc/runtime.h>

static NSString *(*orig_NSBundle_localizedStringForKey)(id, SEL, NSString *, NSString *, NSString *);

static void (*orig_UILabel_setText)(id, SEL, NSString *);

static void (*orig_UILabel_setAttributedText)(id, SEL, NSAttributedString *);

static void (*orig_UIButton_setTitle)(id, SEL, NSString *, UIControlState);

static void (*orig_UIButton_setAttributedTitle)(id, SEL, NSAttributedString *, UIControlState);

static void (*orig_UINavigationItem_setTitle)(id, SEL, NSString *);

static void (*orig_UIViewController_setTitle)(id, SEL, NSString *);

static void (*orig_UITabBarItem_setTitle)(id, SEL, NSString *);

static void (*orig_UISegmentedControl_setTitle)(id, SEL, NSString *, NSUInteger);

static void (*orig_UITextField_setPlaceholder)(id, SEL, NSString *);

static void (*orig_UISearchBar_setPlaceholder)(id, SEL, NSString *);

static void (*orig_UIBarButtonItem_setTitle)(id, SEL, NSString *);

static NSString *translateString(NSString *text) {
    if (!text || ![text isKindOfClass:[NSString class]] || [text length] == 0) return text;
    static NSDictionary *dict = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dict = @{
            @"Settings": @"\u8bbe\u7f6e",
            @"Done": @"\u5b8c\u6210",
            @"Accounts": @"\u8d26\u6237",
            @"Connected": @"\u5df2\u8fde\u63a5",
            @"Not Connected": @"\u672a\u8fde\u63a5",
            @"Connect": @"\u8fde\u63a5",
            @"Back": @"\u8fd4\u56de",
            @"You can manage your account from the admin console.": @"\u4f60\u53ef\u4ee5\u5728\u7ba1\u7406\u63a7\u5236\u53f0\u4e2d\u7ba1\u7406\u4f60\u7684\u8d26\u6237\u3002",
            @"View admin console...": @"\u67e5\u770b\u7ba1\u7406\u63a7\u5236\u53f0...",
            @"VPN On Demand": @"VPN \u6309\u9700\u8fde\u63a5",
            @"DNS Settings": @"DNS \u8bbe\u7f6e",
            @"Subnet Routing": @"\u5b50\u7f51\u8def\u7531",
            @"Tailnet Lock": @"Tailnet \u9501\u5b9a",
            @"Not Enabled": @"\u672a\u542f\u7528",
            @"Bug Report": @"\u95ee\u9898\u53cd\u9988",
            @"About Tailscale": @"\u5173\u4e8e Tailscale",
            @"Notifications": @"\u901a\u77e5",
            @"EXIT NODE": @"\u51fa\u53e3\u8282\u70b9",
            @"None": @"\u65e0",
            @"Search...": @"\u641c\u7d22...",
            @"Choose Exit Node": @"\u9009\u62e9\u51fa\u53e3\u8282\u70b9",
            @"Add Account...": @"\u6dfb\u52a0\u8d26\u6237...",
            @"Reauthenticate": @"\u91cd\u65b0\u9a8c\u8bc1",
            @"Log Out": @"\u9000\u51fa\u767b\u5f55",
            @"Routing traffic according to your network's rules.": @"\u6839\u636e\u4f60\u7684\u7f51\u7edc\u89c4\u5219\u8def\u7531\u6d41\u91cf\u3002",
            @"Use Tailscale Subnets": @"\u4f7f\u7528 Tailscale \u5b50\u7f51",
            @"Route traffic according to your network's rules. Some networks require this to access IP addresses that don't start with 100.x.y.z.": @"\u6839\u636e\u4f60\u7684\u7f51\u7edc\u89c4\u5219\u8def\u7531\u6d41\u91cf\u3002\u67d0\u4e9b\u7f51\u7edc\u9700\u8981\u6b64\u529f\u80fd\u6765\u8bbf\u95ee\u4e0d\u4ee5 100.x.y.z \u5f00\u5934\u7684 IP \u5730\u5740\u3002",
            @"Tailnet Lock lets devices in your network verify public keys distributed by the coordination server before trusting them for connectivity.": @"Tailnet \u9501\u5b9a\u5141\u8bb8\u4f60\u7f51\u7edc\u4e2d\u7684\u8bbe\u5907\u5728\u4fe1\u4efb\u534f\u8c03\u670d\u52a1\u5668\u5206\u53d1\u7684\u516c\u94a5\u4e4b\u524d\u5bf9\u5176\u8fdb\u884c\u9a8c\u8bc1\u3002",
            @"Learn more...": @"\u4e86\u89e3\u66f4\u591a...",
            @"Tailnet Lock is currently not enabled.": @"Tailnet \u9501\u5b9a\u5f53\u524d\u672a\u542f\u7528\u3002",
            @"This node has not been signed by another device.": @"\u6b64\u8282\u70b9\u5c1a\u672a\u88ab\u5176\u4ed6\u8bbe\u5907\u7b7e\u540d\u3002",
            @"This node is not trusted to change the Tailnet Lock configuration.": @"\u6b64\u8282\u70b9\u4e0d\u88ab\u4fe1\u4efb\u66f4\u6539 Tailnet \u9501\u5b9a\u914d\u7f6e\u3002",
            @"Node Key": @"\u8282\u70b9\u5bc6\u94a5",
            @"Used to sign this node from another signing device in your tailnet.": @"\u7528\u4e8e\u4ece tailnet \u4e2d\u7684\u53e6\u4e00\u4e2a\u7b7e\u540d\u8bbe\u5907\u5bf9\u6b64\u8282\u70b9\u8fdb\u884c\u7b7e\u540d\u3002",
            @"Tailnet Lock Key": @"Tailnet \u9501\u5b9a\u5bc6\u94a5",
            @"Used to authorize changes to the Tailnet Lock configuration.": @"\u7528\u4e8e\u6388\u6743\u5bf9 Tailnet \u9501\u5b9a\u914d\u7f6e\u7684\u66f4\u6539\u3002",
            @"Using Tailscale DNS": @"\u6b63\u5728\u4f7f\u7528 Tailscale DNS",
            @"This iPhone is using Tailscale to resolve DNS names.": @"\u6b64 iPhone \u6b63\u5728\u4f7f\u7528 Tailscale \u89e3\u6790 DNS \u540d\u79f0\u3002",
            @"Use Tailscale DNS Settings": @"\u4f7f\u7528 Tailscale DNS \u8bbe\u7f6e",
            @"DNS can be configured in the admin console.": @"DNS \u53ef\u4ee5\u5728\u7ba1\u7406\u63a7\u5236\u53f0\u4e2d\u914d\u7f6e\u3002",
            @"SEARCH DOMAIN": @"\u641c\u7d22\u57df",
            @"Allow notifications to receive updates on network connectivity, security, and other major topics where appropriate.": @"\u5141\u8bb8\u901a\u77e5\u4ee5\u63a5\u6536\u7f51\u7edc\u8fde\u63a5\u3001\u5b89\u5168\u6027\u4ee5\u53ca\u5176\u4ed6\u76f8\u5173\u91cd\u8981\u4e3b\u9898\u7684\u66f4\u65b0\u3002",
            @"Allow Notifications": @"\u5141\u8bb8\u901a\u77e5",
            @"Run as Exit Node": @"\u4f5c\u4e3a\u51fa\u53e3\u8282\u70b9\u8fd0\u884c",
            @"Allow Local Network Access": @"\u5141\u8bb8\u672c\u5730\u7f51\u7edc\u8bbf\u95ee",
            @"Reach local network devices even when an exit node is used.": @"\u5373\u4f7f\u5728\u4f7f\u7528\u51fa\u53e3\u8282\u70b9\u65f6\u4e5f\u80fd\u8bbf\u95ee\u672c\u5730\u7f51\u7edc\u8bbe\u5907\u3002",
            @"Enable this to automatically connect Tailscale on this iPhone.": @"\u542f\u7528\u6b64\u529f\u80fd\u4ee5\u5728\u6b64 iPhone \u4e0a\u81ea\u52a8\u8fde\u63a5 Tailscale\u3002",
            @"CONNECT AUTOMATICALLY ON": @"\u81ea\u52a8\u8fde\u63a5",
            @"Always": @"\u59cb\u7ec8",
            @"Cellular": @"\u8702\u7a9d\u7f51\u7edc",
            @"Tailscale will connect automatically when this iPhone joins a Wi-Fi network. It will also connect whenever this iPhone uses cellular data.": @"\u5f53\u6b64 iPhone \u52a0\u5165 Wi-Fi \u7f51\u7edc\u65f6\uff0cTailscale \u5c06\u81ea\u52a8\u8fde\u63a5\u3002\u5f53\u6b64 iPhone \u4f7f\u7528\u8702\u7a9d\u6570\u636e\u65f6\uff0c\u5b83\u4e5f\u4f1a\u8fde\u63a5\u3002",
            @"MAGICDNS": @"MagicDNS",
            @"Detect MagicDNS hostnames": @"\u68c0\u6d4b MagicDNS \u4e3b\u673a\u540d",
            @"Enable to automatically connect Tailscale when any app on this iPhone attempts to reach a host in the ts.net domain. Available when 'Do Nothing' is selected for a network interface. Note that this will not work for all apps nor all types of connections and is not immediate.": @"\u5f53\u6b64 iPhone \u4e0a\u7684\u4efb\u4f55\u5e94\u7528\u5c1d\u8bd5\u8bbf\u95ee ts.net \u57df\u4e2d\u7684\u4e3b\u673a\u65f6\uff0c\u81ea\u52a8\u8fde\u63a5 Tailscale\u3002\u5f53\u4e3a\u7f51\u7edc\u63a5\u53e3\u9009\u62e9\u4e0d\u6267\u884c\u4efb\u4f55\u64cd\u4f5c\u65f6\u53ef\u7528\u3002\u8bf7\u6ce8\u610f\uff0c\u8fd9\u5e76\u975e\u5bf9\u6240\u6709\u5e94\u7528\u6216\u6240\u6709\u7c7b\u578b\u7684\u8fde\u63a5\u90fd\u6709\u6548\uff0c\u5e76\u4e14\u4e0d\u4f1a\u7acb\u5373\u751f\u6548\u3002",
            @"Tailscale debug": @"Tailscale \u8c03\u8bd5",
            @"To report a bug, contact our support team and include the ID above.": @"\u8981\u62a5\u544a\u9519\u8bef\uff0c\u8bf7\u8054\u7cfb\u6211\u4eec\u7684\u652f\u6301\u56e2\u961f\u5e76\u5305\u542b\u4e0a\u65b9\u7684 ID\u3002",
            @"contact our support team": @"\u8054\u7cfb\u6211\u4eec\u7684\u652f\u6301\u56e2\u961f",
            @"This ID helps us find the event in our diagnostic logs.": @"\u6b64 ID \u5e2e\u52a9\u6211\u4eec\u5728\u8bca\u65ad\u65e5\u5fd7\u4e2d\u627e\u5230\u8be5\u4e8b\u4ef6\u3002",
            @"Tailscale Logs": @"Tailscale \u65e5\u5fd7",
            @"Use an auth key": @"\u4f7f\u7528\u6388\u6743\u5bc6\u94a5",
            @"Log in": @"\u767b\u5f55",
            @"Pre-authentication keys let you sign into Tailscale on this iPhone without needing to authenticate from a web browser.": @"\u9884\u8ba4\u8bc1\u5bc6\u94a5\u8ba9\u4f60\u65e0\u9700\u901a\u8fc7\u7f51\u9875\u6d4f\u89c8\u5668\u9a8c\u8bc1\u5373\u53ef\u5728\u6b64 iPhone \u4e0a\u767b\u5f55 Tailscale\u3002",
            @"To continue, enter a valid auth key generated from the Tailscale admin console.": @"\u8981\u7ee7\u7eed\uff0c\u8bf7\u8f93\u5165\u4ece Tailscale \u7ba1\u7406\u63a7\u5236\u53f0\u751f\u6210\u7684\u6709\u6548\u6388\u6743\u5bc6\u94a5\u3002",
            @"Use a custom coordination server": @"\u4f7f\u7528\u81ea\u5b9a\u4e49\u534f\u8c03\u670d\u52a1\u5668",
            @"Advanced Login Options": @"\u9ad8\u7ea7\u767b\u5f55\u9009\u9879",
            @"TAILSCALE ADDRESSES": @"TAILSCALE \u5730\u5740",
            @"OS": @"\u64cd\u4f5c\u7cfb\u7edf",
            @"Key expiry": @"\u5bc6\u94a5\u8fc7\u671f",
            @"Select a file to send it to this device...": @"\u9009\u62e9\u6587\u4ef6\u53d1\u9001\u5230\u6b64\u8bbe\u5907...",
            @"Select a File...": @"\u9009\u62e9\u6587\u4ef6...",
        };
    });
    NSString *trans = [dict objectForKey:text];
    if (trans) return trans;

    if ([text hasPrefix:@"Connect again to talk to the other devices in the "]) {
        return [text stringByReplacingOccurrencesOfString:@"Connect again to talk to the other devices in the " withString:@"\u91cd\u65b0\u8fde\u63a5\u4ee5\u4e0e "];
    }
    if ([text hasPrefix:@"in "] && [text rangeOfString:@" month"].location != NSNotFound) {
        NSString *num = [text substringFromIndex:3];
        num = [num stringByReplacingOccurrencesOfString:@" months" withString:@""];
        num = [num stringByReplacingOccurrencesOfString:@" month" withString:@""];
        return [NSString stringWithFormat:@"%@\u4e2a\u6708\u540e", num];
    }
    return text;
}

static NSString * hooked_NSBundle_localizedStringForKey(id self, SEL _cmd, NSString *key, NSString *value, NSString *table) {
    NSString *result = orig_NSBundle_localizedStringForKey(self, _cmd, key, value, table);
    return translateString(result);
}

static void hooked_UILabel_setText(id self, SEL _cmd, NSString *text) {
    orig_UILabel_setText(self, _cmd, translateString(text));
}

static void hooked_UILabel_setAttributedText(id self, SEL _cmd, NSAttributedString *text) {
    if (text) {
        NSString *orig = [text string];
        NSString *trans = translateString(orig);
        if (![trans isEqualToString:orig]) {
            text = [[NSAttributedString alloc] initWithString:trans];
        }
    }
    orig_UILabel_setAttributedText(self, _cmd, text);
}

static void hooked_UIButton_setTitle(id self, SEL _cmd, NSString *title, UIControlState state) {
    orig_UIButton_setTitle(self, _cmd, translateString(title), state);
}

static void hooked_UIButton_setAttributedTitle(id self, SEL _cmd, NSAttributedString *title, UIControlState state) {
    if (title) {
        NSString *orig = [title string];
        NSString *trans = translateString(orig);
        if (![trans isEqualToString:orig]) {
            title = [[NSAttributedString alloc] initWithString:trans];
        }
    }
    orig_UIButton_setAttributedTitle(self, _cmd, title, state);
}

static void hooked_UINavigationItem_setTitle(id self, SEL _cmd, NSString *title) {
    orig_UINavigationItem_setTitle(self, _cmd, translateString(title));
}

static void hooked_UIViewController_setTitle(id self, SEL _cmd, NSString *title) {
    orig_UIViewController_setTitle(self, _cmd, translateString(title));
}

static void hooked_UITabBarItem_setTitle(id self, SEL _cmd, NSString *title) {
    orig_UITabBarItem_setTitle(self, _cmd, translateString(title));
}

static void hooked_UISegmentedControl_setTitle(id self, SEL _cmd, NSString *title, NSUInteger segment) {
    orig_UISegmentedControl_setTitle(self, _cmd, translateString(title), segment);
}

static void hooked_UITextField_setPlaceholder(id self, SEL _cmd, NSString *placeholder) {
    orig_UITextField_setPlaceholder(self, _cmd, translateString(placeholder));
}

static void hooked_UISearchBar_setPlaceholder(id self, SEL _cmd, NSString *placeholder) {
    orig_UISearchBar_setPlaceholder(self, _cmd, translateString(placeholder));
}

static void hooked_UIBarButtonItem_setTitle(id self, SEL _cmd, NSString *title) {
    orig_UIBarButtonItem_setTitle(self, _cmd, translateString(title));
}

static void swizzle_NSBundle_localizedStringForKey(void) {
    Method m = class_getInstanceMethod([NSBundle class], @selector(localizedStringForKey:value:table:));
    if (m) {
        orig_NSBundle_localizedStringForKey = (NSString *(*)(id, SEL, NSString *, NSString *, NSString *))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_NSBundle_localizedStringForKey);
    }
}

static void swizzle_UILabel_setText(void) {
    Method m = class_getInstanceMethod([UILabel class], @selector(setText:));
    if (m) {
        orig_UILabel_setText = (void (*)(id, SEL, NSString *))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_UILabel_setText);
    }
}

static void swizzle_UILabel_setAttributedText(void) {
    Method m = class_getInstanceMethod([UILabel class], @selector(setAttributedText:));
    if (m) {
        orig_UILabel_setAttributedText = (void (*)(id, SEL, NSAttributedString *))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_UILabel_setAttributedText);
    }
}

static void swizzle_UIButton_setTitle(void) {
    Method m = class_getInstanceMethod([UIButton class], @selector(setTitle:forState:));
    if (m) {
        orig_UIButton_setTitle = (void (*)(id, SEL, NSString *, UIControlState))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_UIButton_setTitle);
    }
}

static void swizzle_UIButton_setAttributedTitle(void) {
    Method m = class_getInstanceMethod([UIButton class], @selector(setAttributedTitle:forState:));
    if (m) {
        orig_UIButton_setAttributedTitle = (void (*)(id, SEL, NSAttributedString *, UIControlState))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_UIButton_setAttributedTitle);
    }
}

static void swizzle_UINavigationItem_setTitle(void) {
    Method m = class_getInstanceMethod([UINavigationItem class], @selector(setTitle:));
    if (m) {
        orig_UINavigationItem_setTitle = (void (*)(id, SEL, NSString *))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_UINavigationItem_setTitle);
    }
}

static void swizzle_UIViewController_setTitle(void) {
    Method m = class_getInstanceMethod([UIViewController class], @selector(setTitle:));
    if (m) {
        orig_UIViewController_setTitle = (void (*)(id, SEL, NSString *))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_UIViewController_setTitle);
    }
}

static void swizzle_UITabBarItem_setTitle(void) {
    Method m = class_getInstanceMethod([UITabBarItem class], @selector(setTitle:));
    if (m) {
        orig_UITabBarItem_setTitle = (void (*)(id, SEL, NSString *))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_UITabBarItem_setTitle);
    }
}

static void swizzle_UISegmentedControl_setTitle(void) {
    Method m = class_getInstanceMethod([UISegmentedControl class], @selector(setTitle:forSegmentAtIndex:));
    if (m) {
        orig_UISegmentedControl_setTitle = (void (*)(id, SEL, NSString *, NSUInteger))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_UISegmentedControl_setTitle);
    }
}

static void swizzle_UITextField_setPlaceholder(void) {
    Method m = class_getInstanceMethod([UITextField class], @selector(setPlaceholder:));
    if (m) {
        orig_UITextField_setPlaceholder = (void (*)(id, SEL, NSString *))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_UITextField_setPlaceholder);
    }
}

static void swizzle_UISearchBar_setPlaceholder(void) {
    Method m = class_getInstanceMethod([UISearchBar class], @selector(setPlaceholder:));
    if (m) {
        orig_UISearchBar_setPlaceholder = (void (*)(id, SEL, NSString *))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_UISearchBar_setPlaceholder);
    }
}

static void swizzle_UIBarButtonItem_setTitle(void) {
    Method m = class_getInstanceMethod([UIBarButtonItem class], @selector(setTitle:));
    if (m) {
        orig_UIBarButtonItem_setTitle = (void (*)(id, SEL, NSString *))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_UIBarButtonItem_setTitle);
    }
}

static void scanView(UIView *view);
static void scanViewController(UIViewController *vc);

static void scanView(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *lbl = (UILabel *)view;
        NSString *trans = translateString(lbl.text);
        if (![trans isEqualToString:lbl.text]) lbl.text = trans;
    } else if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        NSString *orig = [btn titleForState:UIControlStateNormal];
        NSString *trans = translateString(orig);
        if (trans && orig && ![trans isEqualToString:orig]) {
            [btn setTitle:trans forState:UIControlStateNormal];
        }
    } else if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        NSString *trans = translateString(tf.placeholder);
        if (![trans isEqualToString:tf.placeholder]) tf.placeholder = trans;
    } else if ([view isKindOfClass:[UISearchBar class]]) {
        UISearchBar *sb = (UISearchBar *)view;
        NSString *trans = translateString(sb.placeholder);
        if (![trans isEqualToString:sb.placeholder]) sb.placeholder = trans;
    }
    for (UIView *sub in view.subviews) {
        scanView(sub);
    }
}

static void scanViewController(UIViewController *vc) {
    if (!vc) return;
    NSString *t1 = translateString(vc.title);
    if (vc.title && ![t1 isEqualToString:vc.title]) vc.title = t1;
    if (vc.navigationItem) {
        NSString *t2 = translateString(vc.navigationItem.title);
        if (vc.navigationItem.title && ![t2 isEqualToString:vc.navigationItem.title]) vc.navigationItem.title = t2;
        if (vc.navigationItem.backBarButtonItem) {
            NSString *t3 = translateString(vc.navigationItem.backBarButtonItem.title);
            if (t3 && vc.navigationItem.backBarButtonItem.title && ![t3 isEqualToString:vc.navigationItem.backBarButtonItem.title])
                vc.navigationItem.backBarButtonItem.title = t3;
        }
    }
    if (vc.tabBarItem) {
        NSString *t4 = translateString(vc.tabBarItem.title);
        if (vc.tabBarItem.title && ![t4 isEqualToString:vc.tabBarItem.title]) vc.tabBarItem.title = t4;
    }
    scanView(vc.view);
    for (UIViewController *child in vc.childViewControllers) {
        scanViewController(child);
    }
    if (vc.presentedViewController) {
        scanViewController(vc.presentedViewController);
    }
}

static void scanAllViews(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    scanView(window);
                    if (window.rootViewController) scanViewController(window.rootViewController);
                }
            }
        }
    } else {
        for (UIWindow *window in app.windows) {
            scanView(window);
            if (window.rootViewController) scanViewController(window.rootViewController);
        }
    }
}

__attribute__((constructor))
static void tailscale_chinese_init(void) {
    swizzle_NSBundle_localizedStringForKey();
    swizzle_UILabel_setText();
    swizzle_UILabel_setAttributedText();
    swizzle_UIButton_setTitle();
    swizzle_UIButton_setAttributedTitle();
    swizzle_UINavigationItem_setTitle();
    swizzle_UIViewController_setTitle();
    swizzle_UITabBarItem_setTitle();
    swizzle_UISegmentedControl_setTitle();
    swizzle_UITextField_setPlaceholder();
    swizzle_UISearchBar_setPlaceholder();
    swizzle_UIBarButtonItem_setTitle();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        scanAllViews();
    });
}