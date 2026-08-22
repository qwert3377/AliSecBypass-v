// WorkingCopy_CN_VIP_v1.mm
// TrollStore 注入用，纯 Runtime Hook
// 功能：VIP 解锁 + 中文汉化
// 日志写入 App Documents/wc_cn_log.txt

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - 文件日志

static NSString *logPath = nil;

static void wcLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[WC-CN] %@", msg);
    if (logPath) {
        NSString *line = [NSString stringWithFormat:@"%@ [WC-CN] %@\n", [NSDate date], msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        } else {
            [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }
}

static void initLog() {
    NSString *home = NSHomeDirectory();
    NSString *docs = [home stringByAppendingPathComponent:@"Documents"];
    logPath = [docs stringByAppendingPathComponent:@"wc_cn_log.txt"];
    [[NSFileManager defaultManager] createDirectoryAtPath:docs
        withIntermediateDirectories:YES attributes:nil error:nil];
    [@"" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    wcLog(@"日志初始化完成: %@", logPath);
}

#pragma mark - 翻译字典

static NSDictionary *cnDict = nil;

static void initTranslations() {
    cnDict = @{
        // === 导航栏 & 标题 ===
        @"Repositories": @"仓库",
        @"Settings": @"设置",
        @"Logs": @"日志",
        @"Unlock": @"解锁",
        @"Commit Log": @"提交日志",
        @"List status": @"列出状态",
        @"Repository status": @"仓库状态",
        @"Detail": @"详情",
        @"Configuration": @"配置",
        @"Popup": @"弹出窗口",

        // === 仓库页 ===
        @"welcome to": @"欢迎使用",
        @"tap to learn more": @"点击了解更多",
        @"Add folder": @"添加文件夹",
        @"Clone repository": @"克隆仓库",
        @"Link external directory": @"链接外部目录",
        @"Initialize new repository": @"初始化新仓库",
        @"No repository selected": @"未选择仓库",
        @"You can create new Git repositories by initializing new ones or by cloning from remote.":
            @"你可以通过初始化新仓库或从远程克隆来创建 Git 仓库。",
        @"Recent": @"最近",

        // === 仓库详情 & 文件列表 ===
        @"Repository": @"仓库",
        @"Status and Configuration": @"状态与配置",
        @"Show only:": @"仅显示：",
        @"Modified": @"已修改",
        @"filename, symbol or text": @"文件名、符号或文本",

        // === Git 操作菜单 ===
        @"Commit": @"提交",
        @"Revert": @"撤销",
        @"Merge": @"合并",
        @"Fetch": @"获取",
        @"Pull": @"拉取",
        @"Push": @"推送",

        // === + 号菜单 ===
        @"Create Text File": @"创建文本文件",
        @"Create Directory": @"创建目录",
        @"File from clipboard": @"从剪贴板导入文件",
        @"Import files": @"导入文件",
        @"Import images": @"导入图片",

        // === 仓库详情 ===
        @"Branch": @"分支",
        @"Tags": @"标签",
        @"Submodules": @"子模块",
        @"Remote": @"远程",
        @"Remotes": @"远程",
        @"Add Remote": @"添加远程",
        @"Clone Submodule": @"克隆子模块",
        @"Delete Repository": @"删除仓库",
        @"Identity not configured": @"身份信息未配置",
        @"Should not be used": @"不应使用",
        @"merge in progress": @"合并进行中",
        @"None": @"无",
        @"Rename": @"重命名",
        @"Current": @"当前",
        @"HEAD": @"HEAD",
        @"Create": @"创建",

        // === 操作按钮 ===
        @"  REVERT  ": @"  撤销  ",
        @"  RESOLVE  ": @"  解决  ",
        @"  COMMIT  ": @"  提交  ",
        @"REVERT": @"撤销",
        @"RESOLVE": @"解决",
        @"COMMIT": @"提交",
        @"Delete from iPhone": @"从 iPhone 删除",
        @"Synchronize": @"同步",
        @"GitHub Page": @"GitHub 页面",
        @"Non-editing": @"非编辑模式",
        @"Editing": @"编辑模式",
        @" Commit": @" 提交",
        @" Resolve Conflicts": @" 解决冲突",
        @" Revert changes": @" 撤销更改",

        // === 状态 & 提示 ===
        @"No changes": @"无更改",
        @"Status": @"状态",
        @"Cancel": @"取消",
        @"Clone": @"克隆",
        @"Done": @"完成",

        // === 克隆/初始化页面 ===
        @"Initialize repository": @"初始化仓库",
        @"Repository Name": @"仓库名称",
        @"Describe your project in the README file.": @"在 README 文件中描述你的项目。",
        @"This can be changed later.": @"以后可以修改。",
        @"git, http, https and ssh supported": @"支持 git、http、https 和 ssh",
        @"Protocol": @"协议",
        @"User": @"用户",
        @"tap to set": @"点击设置",
        @"Host": @"主机",
        @"Port": @"端口",
        @"leave empty for default": @"留空使用默认值",
        @"Path": @"路径",
        @"SSH Key": @"SSH 密钥",
        @"Automatic": @"自动",
        @"Off": @"关闭",

        // === 设置页 ===
        @"Color Scheme": @"配色方案",
        @"Auto": @"自动",
        @"Dark": @"深色",
        @"Light": @"浅色",
        @"AI Completion": @"AI 补全",
        @"GPT code & text completion": @"GPT 代码与文本补全",
        @"App Integrations": @"应用集成",
        @"x-callback-url disabled": @"x-callback-url 已禁用",
        @"Authentication Cookies": @"认证 Cookie",
        @"Alternative way to authorize http transfers": @"授权 HTTP 传输的替代方式",
        @"Hosting Providers": @"托管服务商",
        @"Integration with Git & Cloud providers": @"与 Git 和云服务商集成",
        @"Identities": @"身份信息",
        @"Name & Email addresses for commits": @"提交用的姓名和邮箱",
        @"Screen Lock": @"屏幕锁定",
        @"Protect your repositories": @"保护你的仓库",
        @"SSH Keys": @"SSH 密钥",
        @"Authorizes secure shell transfers": @"授权安全 Shell 传输",
        @"Pro Capabilities Unlocked": @"专业功能已解锁",
        @"All Pro features available": @"所有专业功能可用",
        @"WebDAV Server": @"WebDAV 服务器",
        @"Not currently running": @"当前未运行",
        @"Newsletter": @"新闻通讯",
        @"Occasional announcements": @"不定期公告",
        @"Sign Up": @"订阅",
        @"Rate Working Copy": @"评价 Working Copy",
        @"Review": @"评价",
        @"Source Files": @"源代码",
        @"Git API client from same developer": @"同一开发者的 Git API 客户端",
        @"App Store": @"App Store",
        @"Users Guide": @"用户指南",
        @"Show when updated": @"更新时显示",
        @"Release notes on updates": @"更新时的发布说明",
        @"License": @"许可证",

        // === 解锁页面 ===
        @"All Pro features in Working Copy are available.": @"Working Copy 的所有专业功能已可用。",
        @"Features": @"功能",
        @"One-time trial unlock for 10 days": @"一次性试用解锁 10 天",
        @"Unlock for all your devices": @"为你的所有设备解锁",
        @"unlocked features are permanent": @"解锁的功能是永久的",
        @"Purchased": @"已购买",
        @"Restore previous purchase": @"恢复之前的购买",
        @"Free": @"免费",
        @"Since 2014 Working Copy has pushed the limits of developer tools on iOS which is possible because the Pro Unlock pays my salary.":
            @"自 2014 年以来，Working Copy 不断突破 iOS 开发者工具的极限，这得益于专业版解锁功能支付了我的薪水。",
        @"Thank you for supporting this effort.": @"感谢你支持这项工作。",
        @"Anders Borum": @"Anders Borum",

        // === 库/依赖页面 ===
        @"stunning lib used for Git manipulation": @"用于 Git 操作的优秀库",
        @"SSH protocol support": @"SSH 协议支持",
        @"incremental syntax highlighting": @"增量语法高亮",
        @"syntax highlighting": @"语法高亮",
        @"runs the internal WebDAV server": @"运行内部 WebDAV 服务器",
        @"renders markdown": @"渲染 Markdown",
        @"commit signing": @"提交签名",
        @"used to work with zip files": @"用于处理 zip 文件",
        @"renders AsciiDoc preview": @"渲染 AsciiDoc 预览",
        @"monospace font with high Unicode coverage": @"高 Unicode 覆盖的等宽字体",
        @"monospace font with programming ligatures": @"带编程连字的等宽字体",
        @"beautiful monospace font by Raph Levien": @"Raph Levien 设计的优美等宽字体",
        @"coding font by Paul D. Hunt": @"Paul D. Hunt 设计的编程字体",

        // === 通用 ===
        @"Folder": @"文件夹",
        @"Open": @"打开",
        @"Save": @"保存",
        @"Delete": @"删除",
        @"Edit": @"编辑",
        @"Preview": @"预览",
        @"History": @"历史",
        @"Search": @"搜索",
        @"Replace": @"替换",
        @"Find": @"查找",
        @"Select All": @"全选",
        @"Undo": @"撤销",
        @"Redo": @"重做",
        @"Cut": @"剪切",
        @"Paste": @"粘贴",
        @"Copy": @"复制",
        @"More": @"更多",
        @"Info": @"信息",
        @"Close": @"关闭",
        @"Discard": @"放弃",
        @"Apply": @"应用",
        @"OK": @"确定",
        @"Yes": @"是",
        @"No": @"否",
        @"Continue": @"继续",
        @"Back": @"返回",
        @"Next": @"下一步",
        @"Previous": @"上一步",
        @"Finish": @"完成",
        @"Start": @"开始",
        @"Stop": @"停止",
        @"Refresh": @"刷新",
        @"Reload": @"重新加载",
        @"Clear": @"清除",
        @"Reset": @"重置",
        @"Restore": @"恢复",
        @"Download": @"下载",
        @"Upload": @"上传",
        @"Export": @"导出",
        @"Import": @"导入",
        @"Print": @"打印",
        @"Add": @"添加",
        @"Remove": @"移除",
        @"View": @"查看",
        @"Sort by": @"排序方式",
        @"Name": @"名称",
        @"Date": @"日期",
        @"Size": @"大小",
        @"Type": @"类型",
        @"All": @"全部",
        @"Default": @"默认",
        @"Custom": @"自定义",
        @"General": @"通用",
        @"Advanced": @"高级",
        @"About": @"关于",
        @"Help": @"帮助",
        @"Feedback": @"反馈",
        @"Version": @"版本",
        @"Developer": @"开发者",
        @"Credits": @"致谢",
        @"Libraries": @"库",
        @"Tools": @"工具",
        @"Security": @"安全",
        @"Privacy": @"隐私",
        @"Notifications": @"通知",
        @"Language": @"语言",
        @"Keyboard": @"键盘",
        @"Display": @"显示",
        @"Brightness": @"亮度",
    };
}

static NSString *translateText(NSString *text) {
    if (!text || text.length == 0) return text;
    NSString *cn = [cnDict objectForKey:text];
    if (cn) return cn;
    // 格式化字符串匹配
    if ([text hasPrefix:@"Fetching most recent "] && [text hasSuffix:@" commits."]) {
        NSRange r = [text rangeOfString:@"Fetching most recent "];
        NSRange r2 = [text rangeOfString:@" commits."];
        if (r.location != NSNotFound && r2.location != NSNotFound) {
            NSString *num = [text substringWithRange:NSMakeRange(r.location + r.length, r2.location - (r.location + r.length))];
            return [NSString stringWithFormat:@"正在获取最近的 %@ 条提交...", num];
        }
    }
    if ([text hasPrefix:@"Fetching next "] && [text hasSuffix:@" commits."]) {
        NSRange r = [text rangeOfString:@"Fetching next "];
        NSRange r2 = [text rangeOfString:@" commits."];
        if (r.location != NSNotFound && r2.location != NSNotFound) {
            NSString *num = [text substringWithRange:NSMakeRange(r.location + r.length, r2.location - (r.location + r.length))];
            return [NSString stringWithFormat:@"正在获取接下来的 %@ 条提交...", num];
        }
    }
    if ([text hasPrefix:@"Commits "]) {
        NSString *datePart = [text substringFromIndex:8];
        return [NSString stringWithFormat:@"提交记录 %@", datePart];
    }
    if ([text hasPrefix:@"Delete from "]) {
        NSString *device = [text substringFromIndex:12];
        return [NSString stringWithFormat:@"从 %@ 删除", device];
    }
    return text;
}

#pragma mark - VIP Hooks (原有)

static IMP orig_allowedFeature = NULL;
static IMP orig_runningTrial = NULL;
static IMP orig_trialDaysLeft = NULL;
static IMP orig_unlimitedReposAllowed = NULL;
static IMP orig_latestTrialPurchased = NULL;

static BOOL new_allowedFeature(id self, SEL _cmd, id feature, BOOL missingValue, BOOL allowTrial) { return YES; }
static BOOL new_runningTrial(id self, SEL _cmd) { return YES; }
static NSInteger new_trialDaysLeft(id self, SEL _cmd) { return 999; }
static BOOL new_unlimitedReposAllowed(id self, SEL _cmd) { return YES; }
static BOOL new_latestTrialPurchased(id self, SEL _cmd) { return YES; }

static IMP orig_lockedFeatures = NULL;
static IMP orig_quickAllowed = NULL;
static IMP orig_proFeatureTip = NULL;
static IMP orig_upgradeReason = NULL;

static id new_lockedFeatures(id self, SEL _cmd) { return [NSArray array]; }
static BOOL new_quickAllowed(id self, SEL _cmd, id year) { return YES; }
static id new_proFeatureTip(id self, SEL _cmd) { return nil; }
static id new_upgradeReason(id self, SEL _cmd) { return nil; }

static IMP orig_trialCanBeStarted = NULL;
static IMP orig_canPurchasePush = NULL;
static IMP orig_receiptRead = NULL;
static IMP orig_purchasesBeingMade = NULL;

static BOOL new_trialCanBeStarted(id self, SEL _cmd) { return YES; }
static BOOL new_canPurchasePush(id self, SEL _cmd) { return YES; }
static BOOL new_receiptRead(id self, SEL _cmd) { return YES; }
static BOOL new_purchasesBeingMade(id self, SEL _cmd) { return NO; }

static void hookVIP() {
    Class cls1 = objc_getClass("PaymentStatus");
    if (cls1) {
        Method m;
        m = class_getInstanceMethod(cls1, @selector(allowedFeature:missingValue:allowTrial:));
        if (m && !orig_allowedFeature) { orig_allowedFeature = method_setImplementation(m, (IMP)new_allowedFeature); wcLog(@"✅ PaymentStatus.allowedFeature"); }
        m = class_getInstanceMethod(cls1, @selector(runningTrial));
        if (m && !orig_runningTrial) { orig_runningTrial = method_setImplementation(m, (IMP)new_runningTrial); wcLog(@"✅ PaymentStatus.runningTrial"); }
        m = class_getInstanceMethod(cls1, @selector(trialDaysLeft));
        if (m && !orig_trialDaysLeft) { orig_trialDaysLeft = method_setImplementation(m, (IMP)new_trialDaysLeft); wcLog(@"✅ PaymentStatus.trialDaysLeft"); }
        m = class_getInstanceMethod(cls1, @selector(unlimitedReposAllowedByDownloadDate));
        if (m && !orig_unlimitedReposAllowed) { orig_unlimitedReposAllowed = method_setImplementation(m, (IMP)new_unlimitedReposAllowed); wcLog(@"✅ PaymentStatus.unlimitedReposAllowedByDownloadDate"); }
        m = class_getInstanceMethod(cls1, @selector(latestTrialPurchased));
        if (m && !orig_latestTrialPurchased) { orig_latestTrialPurchased = method_setImplementation(m, (IMP)new_latestTrialPurchased); wcLog(@"✅ PaymentStatus.latestTrialPurchased"); }
    }
    Class cls2 = objc_getClass("AppFeature");
    if (cls2) {
        Method m;
        m = class_getInstanceMethod(cls2, @selector(lockedFeatures));
        if (m && !orig_lockedFeatures) { orig_lockedFeatures = method_setImplementation(m, (IMP)new_lockedFeatures); wcLog(@"✅ AppFeature.lockedFeatures"); }
        m = class_getInstanceMethod(cls2, @selector(quickAllowedForEnterpriseYear:));
        if (m && !orig_quickAllowed) { orig_quickAllowed = method_setImplementation(m, (IMP)new_quickAllowed); wcLog(@"✅ AppFeature.quickAllowedForEnterpriseYear"); }
        m = class_getInstanceMethod(cls2, @selector(proFeatureTip));
        if (m && !orig_proFeatureTip) { orig_proFeatureTip = method_setImplementation(m, (IMP)new_proFeatureTip); wcLog(@"✅ AppFeature.proFeatureTip"); }
        m = class_getInstanceMethod(cls2, @selector(upgradeReasonMessage));
        if (m && !orig_upgradeReason) { orig_upgradeReason = method_setImplementation(m, (IMP)new_upgradeReason); wcLog(@"✅ AppFeature.upgradeReasonMessage"); }
    }
    Class cls3 = objc_getClass("Payment");
    if (cls3) {
        Method m;
        m = class_getInstanceMethod(cls3, @selector(trialCanBeStarted));
        if (m && !orig_trialCanBeStarted) { orig_trialCanBeStarted = method_setImplementation(m, (IMP)new_trialCanBeStarted); wcLog(@"✅ Payment.trialCanBeStarted"); }
        m = class_getInstanceMethod(cls3, @selector(canPurchasePush));
        if (m && !orig_canPurchasePush) { orig_canPurchasePush = method_setImplementation(m, (IMP)new_canPurchasePush); wcLog(@"✅ Payment.canPurchasePush"); }
        m = class_getInstanceMethod(cls3, @selector(receiptRead));
        if (m && !orig_receiptRead) { orig_receiptRead = method_setImplementation(m, (IMP)new_receiptRead); wcLog(@"✅ Payment.receiptRead"); }
        m = class_getInstanceMethod(cls3, @selector(purchasesBeingMade));
        if (m && !orig_purchasesBeingMade) { orig_purchasesBeingMade = method_setImplementation(m, (IMP)new_purchasesBeingMade); wcLog(@"✅ Payment.purchasesBeingMade"); }
    }
}

#pragma mark - 中文汉化 Hooks

static IMP orig_labelSetText = NULL;
static IMP orig_buttonSetTitle = NULL;
static IMP orig_navItemSetTitle = NULL;
static IMP orig_vcSetTitle = NULL;
static IMP orig_bundleLocalizedString = NULL;
static IMP orig_tfSetPlaceholder = NULL;
static IMP orig_searchBarSetPlaceholder = NULL;
static IMP orig_alertActionTitle = NULL;
static IMP orig_alertControllerTitle = NULL;

static void new_labelSetText(id self, SEL _cmd, id text) {
    if (text) {
        NSString *t = translateText(text);
        if (t != text) text = t;
    }
    if (orig_labelSetText) {
        ((void (*)(id, SEL, id))orig_labelSetText)(self, _cmd, text);
    }
}

static void new_buttonSetTitle(id self, SEL _cmd, id title, UIControlState state) {
    if (title) {
        NSString *t = translateText(title);
        if (t != title) title = t;
    }
    if (orig_buttonSetTitle) {
        ((void (*)(id, SEL, id, UIControlState))orig_buttonSetTitle)(self, _cmd, title, state);
    }
}

static void new_navItemSetTitle(id self, SEL _cmd, id title) {
    if (title) {
        NSString *t = translateText(title);
        if (t != title) title = t;
    }
    if (orig_navItemSetTitle) {
        ((void (*)(id, SEL, id))orig_navItemSetTitle)(self, _cmd, title);
    }
}

static void new_vcSetTitle(id self, SEL _cmd, id title) {
    if (title) {
        NSString *t = translateText(title);
        if (t != title) title = t;
    }
    if (orig_vcSetTitle) {
        ((void (*)(id, SEL, id))orig_vcSetTitle)(self, _cmd, title);
    }
}

static id new_bundleLocalizedString(id self, SEL _cmd, id key, id value, id table) {
    id result = nil;
    if (orig_bundleLocalizedString) {
        result = ((id (*)(id, SEL, id, id, id))orig_bundleLocalizedString)(self, _cmd, key, value, table);
    }
    if (result) {
        NSString *t = translateText(result);
        if (t != result) return t;
    }
    return result;
}

static void new_tfSetPlaceholder(id self, SEL _cmd, id text) {
    if (text) {
        NSString *t = translateText(text);
        if (t != text) text = t;
    }
    if (orig_tfSetPlaceholder) {
        ((void (*)(id, SEL, id))orig_tfSetPlaceholder)(self, _cmd, text);
    }
}

static void new_searchBarSetPlaceholder(id self, SEL _cmd, id text) {
    if (text) {
        NSString *t = translateText(text);
        if (t != text) text = t;
    }
    if (orig_searchBarSetPlaceholder) {
        ((void (*)(id, SEL, id))orig_searchBarSetPlaceholder)(self, _cmd, text);
    }
}

// UIAlertAction +actionWithTitle:style:handler: 是类方法
static id new_alertActionWithTitle(id self, SEL _cmd, id title, NSInteger style, id handler) {
    if (title) {
        NSString *t = translateText(title);
        if (t != title) title = t;
    }
    if (orig_alertActionTitle) {
        return ((id (*)(id, SEL, id, NSInteger, id))orig_alertActionTitle)(self, _cmd, title, style, handler);
    }
    return nil;
}

// UIAlertController +alertControllerWithTitle:message:preferredStyle:
static id new_alertControllerWithTitle(id self, SEL _cmd, id title, id message, NSInteger style) {
    if (title) {
        NSString *t = translateText(title);
        if (t != title) title = t;
    }
    if (message) {
        NSString *t = translateText(message);
        if (t != message) message = t;
    }
    if (orig_alertControllerTitle) {
        return ((id (*)(id, SEL, id, id, NSInteger))orig_alertControllerTitle)(self, _cmd, title, message, style);
    }
    return nil;
}

static void hookCN() {
    // UILabel setText:
    Class UILabelCls = objc_getClass("UILabel");
    if (UILabelCls) {
        Method m = class_getInstanceMethod(UILabelCls, @selector(setText:));
        if (m && !orig_labelSetText) {
            orig_labelSetText = method_setImplementation(m, (IMP)new_labelSetText);
            wcLog(@"✅ UILabel.setText:");
        }
    }

    // UIButton setTitle:forState:
    Class UIButtonCls = objc_getClass("UIButton");
    if (UIButtonCls) {
        Method m = class_getInstanceMethod(UIButtonCls, @selector(setTitle:forState:));
        if (m && !orig_buttonSetTitle) {
            orig_buttonSetTitle = method_setImplementation(m, (IMP)new_buttonSetTitle);
            wcLog(@"✅ UIButton.setTitle:forState:");
        }
    }

    // UINavigationItem setTitle:
    Class UINavigationItemCls = objc_getClass("UINavigationItem");
    if (UINavigationItemCls) {
        Method m = class_getInstanceMethod(UINavigationItemCls, @selector(setTitle:));
        if (m && !orig_navItemSetTitle) {
            orig_navItemSetTitle = method_setImplementation(m, (IMP)new_navItemSetTitle);
            wcLog(@"✅ UINavigationItem.setTitle:");
        }
    }

    // UIViewController setTitle:
    Class UIViewControllerCls = objc_getClass("UIViewController");
    if (UIViewControllerCls) {
        Method m = class_getInstanceMethod(UIViewControllerCls, @selector(setTitle:));
        if (m && !orig_vcSetTitle) {
            orig_vcSetTitle = method_setImplementation(m, (IMP)new_vcSetTitle);
            wcLog(@"✅ UIViewController.setTitle:");
        }
    }

    // NSBundle localizedStringForKey:value:table:
    Class NSBundleCls = objc_getClass("NSBundle");
    if (NSBundleCls) {
        Method m = class_getInstanceMethod(NSBundleCls, @selector(localizedStringForKey:value:table:));
        if (m && !orig_bundleLocalizedString) {
            orig_bundleLocalizedString = method_setImplementation(m, (IMP)new_bundleLocalizedString);
            wcLog(@"✅ NSBundle.localizedStringForKey:value:table:");
        }
    }

    // UITextField setPlaceholder:
    Class UITextFieldCls = objc_getClass("UITextField");
    if (UITextFieldCls) {
        Method m = class_getInstanceMethod(UITextFieldCls, @selector(setPlaceholder:));
        if (m && !orig_tfSetPlaceholder) {
            orig_tfSetPlaceholder = method_setImplementation(m, (IMP)new_tfSetPlaceholder);
            wcLog(@"✅ UITextField.setPlaceholder:");
        }
    }

    // UISearchBar setPlaceholder:
    Class UISearchBarCls = objc_getClass("UISearchBar");
    if (UISearchBarCls) {
        Method m = class_getInstanceMethod(UISearchBarCls, @selector(setPlaceholder:));
        if (m && !orig_searchBarSetPlaceholder) {
            orig_searchBarSetPlaceholder = method_setImplementation(m, (IMP)new_searchBarSetPlaceholder);
            wcLog(@"✅ UISearchBar.setPlaceholder:");
        }
    }

    // UIAlertAction +actionWithTitle:style:handler: (类方法)
    Class UIAlertActionCls = objc_getClass("UIAlertAction");
    if (UIAlertActionCls) {
        Method m = class_getClassMethod(UIAlertActionCls, @selector(actionWithTitle:style:handler:));
        if (m && !orig_alertActionTitle) {
            orig_alertActionTitle = method_setImplementation(m, (IMP)new_alertActionWithTitle);
            wcLog(@"✅ UIAlertAction.actionWithTitle:style:handler:");
        }
    }

    // UIAlertController +alertControllerWithTitle:message:preferredStyle: (类方法)
    Class UIAlertControllerCls = objc_getClass("UIAlertController");
    if (UIAlertControllerCls) {
        Method m = class_getClassMethod(UIAlertControllerCls, @selector(alertControllerWithTitle:message:preferredStyle:));
        if (m && !orig_alertControllerTitle) {
            orig_alertControllerTitle = method_setImplementation(m, (IMP)new_alertControllerWithTitle);
            wcLog(@"✅ UIAlertController.alertControllerWithTitle:message:preferredStyle:");
        }
    }
}

#pragma mark - 轮询

static void startPolling() {
    static int attempts = 0;
    const int maxAttempts = 600;

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 0.5 * NSEC_PER_SEC, 0);

    dispatch_source_set_event_handler(timer, ^{
        attempts++;
        hookVIP();
        hookCN();

        BOOL vipDone = orig_allowedFeature != NULL && orig_lockedFeatures != NULL && orig_trialCanBeStarted != NULL;
        BOOL cnDone = orig_labelSetText != NULL && orig_bundleLocalizedString != NULL;

        if ((vipDone && cnDone) || attempts >= maxAttempts) {
            dispatch_source_cancel(timer);
            if (vipDone && cnDone) {
                wcLog(@"🎉 VIP + 汉化 Hook 全部完成");
            } else {
                wcLog(@"⚠️ 轮询结束，VIP=%@ 汉化=%@", vipDone?@"OK":@"FAIL", cnDone?@"OK":@"FAIL");
            }
        }
    });

    dispatch_resume(timer);
}

#pragma mark - 初始化

__attribute__((constructor))
static void wc_cn_vip_init() {
    @autoreleasepool {
        initLog();
        initTranslations();
        wcLog(@"Tweak 已加载 (VIP + 汉化)，开始 Hook...");

        hookVIP();
        hookCN();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            startPolling();
        });
    }
}
