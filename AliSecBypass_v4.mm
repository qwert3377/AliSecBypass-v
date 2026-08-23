//
// GitHubArtifactDownloader.mm v3
// 修复：Theos -Werror 编译问题
//

#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - File Logger

static NSString *logPath(void) {
    static NSString *path = nil;
    if (!path) {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        path = [docs stringByAppendingPathComponent:@"gh_artifact.log"];
    }
    return path;
}

static void ghLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [[NSDate date] description], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath()];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [line writeToFile:logPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

#pragma mark - Global Cache

static NSString *g_runURL   = nil;
static NSString *g_owner    = nil;
static NSString *g_repo     = nil;
static CFAbsoluteTime g_cacheTime = 0;
static BOOL g_hookedVC = NO;

#pragma mark - Forward Declarations

static void downloadArtifact(id self, SEL _cmd);
static void ensureButton(id self);

#pragma mark - JSON Scanner

static void extractWorkflowRunInfo(id obj, int depth) {
    if (depth > 20) return;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        NSString *typeName = dict[@"__typename"];
        if ([typeName isEqualToString:@"WorkflowRun"]) {
            ghLog(@"[Scan] found WorkflowRun at depth %d", depth);
            NSString *url = dict[@"url"];
            id repoObj = dict[@"repository"];
            if (url && [url isKindOfClass:[NSString class]] && [url containsString:@"/actions/runs/"]) {
                NSString *runId = [url lastPathComponent];
                NSString *repoName = nil;
                NSString *ownerLogin = nil;
                if (repoObj && [repoObj isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *repo = (NSDictionary *)repoObj;
                    repoName = repo[@"name"];
                    id ownerObj = repo[@"owner"];
                    if (ownerObj && [ownerObj isKindOfClass:[NSDictionary class]]) {
                        ownerLogin = ((NSDictionary *)ownerObj)[@"login"];
                    }
                }
                if (!repoName || !ownerLogin) {
                    NSArray *parts = [url pathComponents];
                    if (parts.count >= 4) {
                        ownerLogin = parts[1];
                        repoName = parts[2];
                    }
                }
                if (repoName && ownerLogin && runId) {
                    g_runURL  = [url copy];
                    g_repo    = [repoName copy];
                    g_owner   = [ownerLogin copy];
                    g_cacheTime = CFAbsoluteTimeGetCurrent();
                    ghLog(@"[Cache] SUCCESS: %@/%@ run=%@", ownerLogin, repoName, runId);
                    return;
                }
            }
        }
        for (id key in dict) {
            extractWorkflowRunInfo(dict[key], depth + 1);
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)obj;
        for (id item in arr) {
            extractWorkflowRunInfo(item, depth + 1);
        }
    }
}

#pragma mark - UI Helpers

static void showAlert(id self, NSString *title, NSString *message) {
    UIViewController *vc = (UIViewController *)self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

static void showPATInput(id self) {
    UIViewController *vc = (UIViewController *)self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"GitHub Token" message:@"请输入 Personal Access Token（需 repo 权限）" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"ghp_xxxxxxxxxxxx";
        tf.secureTextEntry = YES;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存并下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *token = alert.textFields.firstObject.text;
        if (token && token.length > 10) {
            [[NSUserDefaults standardUserDefaults] setObject:token forKey:@"GHArtifactPAT"];
            ghLog(@"[Token] saved");
            downloadArtifact(self, @selector(gh_downloadArtifact));
        }
    }]];
    [vc presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Network Download

static void downloadZip(id self, NSString *pat, NSNumber *artId, NSString *artName) {
    NSString *api = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/actions/artifacts/%@/zip", g_owner, g_repo, artId];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:api]];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", pat] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];

    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithRequest:req completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !location) {
                ghLog(@"[DL] error: %@", error ? error.localizedDescription : @"nil");
                showAlert(self, @"下载失败", error ? error.localizedDescription : @"未知错误");
                return;
            }
            NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
            NSString *runId = [g_runURL lastPathComponent];
            NSString *filename = [NSString stringWithFormat:@"%@-%@-%@.zip", g_repo, runId, artName];
            NSString *dest = [docs stringByAppendingPathComponent:filename];
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:dest]) [fm removeItemAtPath:dest error:nil];
            NSError *moveErr = nil;
            [fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:dest] error:&moveErr];
            if (moveErr) {
                showAlert(self, @"保存失败", moveErr.localizedDescription);
                return;
            }
            ghLog(@"[DL] saved: %@", dest);
            UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:dest]] applicationActivities:nil];
            if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                activity.popoverPresentationController.sourceView = ((UIViewController *)self).view;
                activity.popoverPresentationController.sourceRect = CGRectMake(((UIViewController *)self).view.bounds.size.width/2, 100, 0, 0);
            }
            [((UIViewController *)self) presentViewController:activity animated:YES completion:nil];
        });
    }];
    [task resume];
}

static void downloadArtifact(id self, SEL _cmd) {
    ghLog(@"[DL] button tapped");
    NSString *pat = [[NSUserDefaults standardUserDefaults] stringForKey:@"GHArtifactPAT"];
    if (!pat || pat.length < 10) { showPATInput(self); return; }
    if (!g_runURL || !g_owner || !g_repo) {
        ghLog(@"[DL] no cache: url=%@ owner=%@ repo=%@", g_runURL, g_owner, g_repo);
        showAlert(self, @"未获取到 Run 信息", @"请等待页面加载完成");
        return;
    }
    if (CFAbsoluteTimeGetCurrent() - g_cacheTime > 120) {
        showAlert(self, @"缓存已过期", @"请重新进入 Actions 详情页");
        return;
    }
    NSString *runId = [g_runURL lastPathComponent];
    NSString *api = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/actions/runs/%@/artifacts", g_owner, g_repo, runId];
    ghLog(@"[DL] API: %@", api);
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:api]];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", pat] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { showAlert(self, @"请求失败", error.localizedDescription); return; }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *artifacts = json[@"artifacts"];
            ghLog(@"[DL] artifacts: %lu", (unsigned long)artifacts.count);
            if (!artifacts || artifacts.count == 0) { showAlert(self, @"无 Artifacts", @"该 Run 没有 Artifact"); return; }
            NSDictionary *first = artifacts[0];
            NSNumber *artId = first[@"id"];
            NSString *artName = first[@"name"] ?: @"artifact";
            if (!artId) { showAlert(self, @"解析失败", @"无法获取 Artifact ID"); return; }
            downloadZip(self, pat, artId, artName);
        });
    }];
    [task resume];
}

#pragma mark - Button Management

static void ensureButton(id self) {
    UIViewController *vc = (UIViewController *)self;
    UINavigationItem *navItem = vc.navigationItem;
    if (!navItem) { ghLog(@"[Btn] no navigationItem"); return; }
    for (UIBarButtonItem *item in navItem.rightBarButtonItems) {
        if (item.action == @selector(gh_downloadArtifact)) { ghLog(@"[Btn] already exists"); return; }
    }
    UIBarButtonItem *dl = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(gh_downloadArtifact)];
    NSMutableArray *items = [navItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    [items addObject:dl];
    navItem.rightBarButtonItems = items;
    ghLog(@"[Btn] added");
}

#pragma mark - Hooks

static id (*orig_JSON)(id self, SEL _cmd, NSData *data, NSJSONReadingOptions opt, NSError **err);

static id hook_JSON(id self, SEL _cmd, NSData *data, NSJSONReadingOptions opt, NSError **err) {
    id result = orig_JSON(self, _cmd, data, opt, err);
    if (result && data && [data length] > 50 && [data length] < 200000) {
        NSString *preview = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, MIN(512, data.length))] encoding:NSUTF8StringEncoding];
        if (preview && ([preview containsString:@"WorkflowRun"] || [preview containsString:@"workflowRun"])) {
            ghLog(@"[JSON] WorkflowRun detected, scanning...");
            extractWorkflowRunInfo(result, 0);
        }
    }
    return result;
}

static void (*orig_vdl)(id self, SEL _cmd);

static void hook_vdl(id self, SEL _cmd) {
    orig_vdl(self, _cmd);
    ghLog(@"[Hook] viewDidLoad");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ensureButton(self);
    });
}

static void (*orig_vda)(id self, SEL _cmd, BOOL animated);

static void hook_vda(id self, SEL _cmd, BOOL animated) {
    orig_vda(self, _cmd, animated);
    ghLog(@"[Hook] viewDidAppear");
    ensureButton(self);
}

static void (*orig_setRightItems)(id self, SEL _cmd, NSArray *items, BOOL animated);

static void hook_setRightItems(id self, SEL _cmd, NSArray *items, BOOL animated) {
    NSMutableArray *newItems = [items mutableCopy] ?: [NSMutableArray array];
    BOOL hasOurs = NO;
    for (UIBarButtonItem *item in newItems) {
        if (item.action == @selector(gh_downloadArtifact)) { hasOurs = YES; break; }
    }
    if (!hasOurs && g_runURL) {
        UIViewController *vc = nil;
        if ([self respondsToSelector:@selector(topViewController)]) {
            vc = ((UINavigationController *)self).topViewController;
        }
        if (vc) {
            UIBarButtonItem *dl = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:vc action:@selector(gh_downloadArtifact)];
            [newItems addObject:dl];
            ghLog(@"[Hook] injected button via setRightBarButtonItems");
        }
    }
    orig_setRightItems(self, _cmd, newItems, animated);
}

static void (*orig_push)(id self, SEL _cmd, id vc, BOOL animated);

static void hook_push(id self, SEL _cmd, id vc, BOOL animated) {
    orig_push(self, _cmd, vc, animated);
    if (!vc) return;
    NSString *clsName = NSStringFromClass([vc class]);
    if ([clsName isEqualToString:@"Actions.WorkflowRunViewController"]) {
        ghLog(@"[Push] WorkflowRunViewController");
        if (!g_hookedVC) {
            Class targetCls = [vc class];
            Method m1 = class_getInstanceMethod(targetCls, @selector(viewDidLoad));
            if (m1) {
                orig_vdl = (void (*)(id, SEL))method_getImplementation(m1);
                method_setImplementation(m1, (IMP)hook_vdl);
            }
            Method m2 = class_getInstanceMethod(targetCls, @selector(viewDidAppear:));
            if (m2) {
                orig_vda = (void (*)(id, SEL, BOOL))method_getImplementation(m2);
                method_setImplementation(m2, (IMP)hook_vda);
            }
            class_addMethod(targetCls, @selector(gh_downloadArtifact), (IMP)downloadArtifact, "v@:");
            g_hookedVC = YES;
            ghLog(@"[Push] hooked");
        }
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void gh_init() {
    ghLog(@"[Init] loading...");
    Class jsonCls = objc_getClass("NSJSONSerialization");
    if (jsonCls) {
        Method m = class_getClassMethod(jsonCls, @selector(JSONObjectWithData:options:error:));
        if (m) {
            orig_JSON = (id (*)(id, SEL, NSData *, NSJSONReadingOptions, NSError **))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_JSON);
            ghLog(@"[Init] NSJSONSerialization hooked");
        }
    }
    Class navCls = objc_getClass("UINavigationController");
    if (navCls) {
        Method m = class_getInstanceMethod(navCls, @selector(pushViewController:animated:));
        if (m) {
            orig_push = (void (*)(id, SEL, id, BOOL))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_push);
            ghLog(@"[Init] UINavigationController hooked");
        }
        Method m2 = class_getInstanceMethod(navCls, @selector(setRightBarButtonItems:animated:));
        if (m2) {
            orig_setRightItems = (void (*)(id, SEL, NSArray *, BOOL))method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hook_setRightItems);
            ghLog(@"[Init] setRightBarButtonItems hooked");
        }
    }
    Class vcCls = objc_getClass("Actions.WorkflowRunViewController");
    if (vcCls && !g_hookedVC) {
        Method m1 = class_getInstanceMethod(vcCls, @selector(viewDidLoad));
        if (m1) {
            orig_vdl = (void (*)(id, SEL))method_getImplementation(m1);
            method_setImplementation(m1, (IMP)hook_vdl);
        }
        Method m2 = class_getInstanceMethod(vcCls, @selector(viewDidAppear:));
        if (m2) {
            orig_vda = (void (*)(id, SEL, BOOL))method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hook_vda);
        }
        class_addMethod(vcCls, @selector(gh_downloadArtifact), (IMP)downloadArtifact, "v@:");
        g_hookedVC = YES;
        ghLog(@"[Init] WorkflowRunViewController hooked directly");
    }
    ghLog(@"[Init] done");
}
