// ZeroTier One 汉化插件 —— 纯 Runtime 实现，无 %hook 语法
// 编译：theos 单文件 .mm，TrollStore 注入
// 架构：arm64 / arm64e

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSDictionary *gDict = nil;

static NSString *translate(NSString *str) {
    if (!str || ![str isKindOfClass:[NSString class]]) return str;
    NSString *cn = gDict[str];
    if (cn) return cn;
    NSString *trimmed = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    cn = gDict[trimmed];
    if (cn) return cn;
    return str;
}

// ========== 通用 Swizzle 工具 ==========

static void swizzleInstanceMethod(Class cls, SEL origSel, SEL newSel) {
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method newMethod = class_getInstanceMethod(cls, newSel);
    if (!origMethod || !newMethod) return;

    BOOL didAdd = class_addMethod(cls, origSel,
        method_getImplementation(newMethod),
        method_getTypeEncoding(newMethod));

    if (didAdd) {
        class_replaceMethod(cls, newSel,
            method_getImplementation(origMethod),
            method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, newMethod);
    }
}

static void swizzleClassMethod(Class cls, SEL origSel, SEL newSel) {
    Method origMethod = class_getClassMethod(cls, origSel);
    Method newMethod = class_getClassMethod(cls, newSel);
    if (!origMethod || !newMethod) return;
    method_exchangeImplementations(origMethod, newMethod);
}

// ========== 1. UILabel setText: ==========

@interface UILabel (I18N)
- (void)zt_setText:(NSString *)text;
@end

@implementation UILabel (I18N)
- (void)zt_setText:(NSString *)text {
    NSString *cn = translate(text);
    [self zt_setText:cn];
}
@end

// ========== 2. UIButton setTitle:forState: ==========

@interface UIButton (I18N)
- (void)zt_setTitle:(NSString *)title forState:(UIControlState)state;
@end

@implementation UIButton (I18N)
- (void)zt_setTitle:(NSString *)title forState:(UIControlState)state {
    NSString *cn = translate(title);
    [self zt_setTitle:cn forState:state];
}
@end

// ========== 3. UINavigationItem setTitle: ==========

@interface UINavigationItem (I18N)
- (void)zt_setTitle:(NSString *)title;
@end

@implementation UINavigationItem (I18N)
- (void)zt_setTitle:(NSString *)title {
    NSString *cn = translate(title);
    [self zt_setTitle:cn];
}
@end

// ========== 4. UIViewController setTitle: ==========

@interface UIViewController (I18N)
- (void)zt_setTitle:(NSString *)title;
@end

@implementation UIViewController (I18N)
- (void)zt_setTitle:(NSString *)title {
    NSString *cn = translate(title);
    [self zt_setTitle:cn];
}
@end

// ========== 5. NSBundle localizedStringForKey:value:table: ==========

@interface NSBundle (I18N)
- (NSString *)zt_localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)table;
@end

@implementation NSBundle (I18N)
- (NSString *)zt_localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)table {
    NSString *result = [self zt_localizedStringForKey:key value:value table:table];
    return translate(result);
}
@end

// ========== 6. UITextField setPlaceholder: ==========

@interface UITextField (I18N)
- (void)zt_setPlaceholder:(NSString *)placeholder;
@end

@implementation UITextField (I18N)
- (void)zt_setPlaceholder:(NSString *)placeholder {
    NSString *cn = translate(placeholder);
    [self zt_setPlaceholder:cn];
}
@end

// ========== 7. UITableViewCell setText: ==========

@interface UITableViewCell (I18N)
- (void)zt_setText:(NSString *)text;
@end

@implementation UITableViewCell (I18N)
- (void)zt_setText:(NSString *)text {
    NSString *cn = translate(text);
    [self zt_setText:cn];
}
@end

// ========== 8. UIAlertController alertControllerWithTitle:message:preferredStyle: ==========

@interface UIAlertController (I18N)
+ (instancetype)zt_alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style;
@end

@implementation UIAlertController (I18N)
+ (instancetype)zt_alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style {
    NSString *cnTitle = translate(title);
    NSString *cnMsg = translate(message);
    return [self zt_alertControllerWithTitle:cnTitle message:cnMsg preferredStyle:style];
}
@end

// ========== 初始化 ==========

__attribute__((constructor))
static void zt_i18n_init(void) {
    gDict = @{
        @"Add Network": @"添加网络",
        @"Network ID": @"网络ID",
        @"Enable Default Route": @"启用默认路由",
        @"Enable On Demand (beta)": @"启用按需连接（测试版）",
        @"Status": @"状态",
        @"Access Control": @"访问控制",
        @"MAC": @"MAC地址",
        @"MTU": @"MTU",
        @"Broadcast": @"广播",
        @"Bridging": @"桥接",
        @"Managed IPs": @"管理IP",
        @"DNS Search Domain": @"DNS搜索域",
        @"DNS Servers": @"DNS服务器",
        @"None": @"无",
        @"Private": @"私有",
        @"OK": @"正常",
        @"YES": @"是",
        @"NO": @"否",
        @"Share this QR code to add members to this network": @"分享此二维码以添加成员到该网络",
        @"This Network must be restarted for this change to take effect": @"此网络必须重启才能使更改生效",
        @"No DNS Configuration": @"无DNS配置",
        @"DNS Configuration managed by the Network Controller": @"DNS配置由网络控制器管理",
        @"No DNS": @"无DNS",
        @"Network DNS": @"网络DNS",
        @"Custom DNS": @"自定义DNS",
        @"Done": @"完成",
        @"Edit": @"编辑",
        @"Add": @"添加",
        @"ZeroTier One": @"ZeroTier One"
    };

    swizzleInstanceMethod([UILabel class], @selector(setText:), @selector(zt_setText:));
    swizzleInstanceMethod([UIButton class], @selector(setTitle:forState:), @selector(zt_setTitle:forState:));
    swizzleInstanceMethod([UINavigationItem class], @selector(setTitle:), @selector(zt_setTitle:));
    swizzleInstanceMethod([UIViewController class], @selector(setTitle:), @selector(zt_setTitle:));
    swizzleInstanceMethod([NSBundle class], @selector(localizedStringForKey:value:table:), @selector(zt_localizedStringForKey:value:table:));
    swizzleInstanceMethod([UITextField class], @selector(setPlaceholder:), @selector(zt_setPlaceholder:));
    swizzleInstanceMethod([UITableViewCell class], @selector(setText:), @selector(zt_setText:));
    swizzleClassMethod([UIAlertController class], @selector(alertControllerWithTitle:message:preferredStyle:), @selector(zt_alertControllerWithTitle:message:preferredStyle:));
}
