//
// GitHubArtifactDownloader.mm
// 纯 ObjC Runtime，无 Logos，用于 TrollStore 注入
// 功能：在 GitHub App 的 Actions Run 详情页注入 Artifact 下载按钮
//

#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - Global Cache

static NSString *g_runURL     = nil;
static NSString *g_owner        = nil;
static NSString *g_repo         = nil;
static CFAbsoluteTime g_cacheTime = 0;

#pragma mark - Forward Declarations

static void downloadArtifact(id self, SEL _cmd);

#pragma mark - JSON Scanner (called by hook_JSON)

static void extractWorkflowRunInfo(id obj) {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        NSString *typename = dict[@"__typename"];
        if ([typename isEqualToString:@"WorkflowRun"]) {
            NSString *url = dict[@"url"];
            NSDictionary *repo = dict[@"repository"];
            if (url && [url isKindOfClass:[NSString class]] && repo && [repo isKindOfClass:[NSDictionary class]]) {
                NSString *repoName = repo[@"name"];
                NSDictionary *owner = repo[@"owner"];
                NSString *ownerLogin = owner[@"login"];
                if (repoName && ownerLogin) {
                    g_runURL  = [url copy];
                    g_repo    = [repoName copy];
                    g_owner   = [ownerLogin copy];
                    g_cacheTime = CFAbsoluteTimeGetCurrent();
                    NSLog(@"[GHArtifact] Cached: %@/%@ run=%@", ownerLogin, repoName, url);
                    return;
                }
            }
        }
        for (id key in dict) {
            extractWorkflowRunInfo(dict[key]);
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)obj;
        for (id item in arr) {
            extractWorkflowRunInfo(item);
        }
    }
}

#pragma mark - UI Helpers

static void showAlert(id self, NSString *title, NSString *message) {
    UIViewController *vc = (UIViewController *)self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

static void showPATInput(id self) {
    UIViewController *vc = (UIViewController *)self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"GitHub Token"
                                                                   message:@"请输入 Personal Access Token（需 repo 权限）"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"ghp_xxxxxxxxxxxx";
        tf.secureTextEntry = YES;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存并下载"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        NSString *token = alert.textFields.firstObject.text;
        if (token && token.length > 10) {
            [[NSUserDefaults standardUserDefaults] setObject:token forKey:@"GHArtifactPAT"];
            downloadArtifact(self, @selector(gh_downloadArtifact));
        }
    }]];
    [vc presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Network Download

static void downloadZip(id self, NSString *pat, NSNumber *artId, NSString *artName) {
    NSString *api = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/actions/artifacts/%@/zip",
                     g_owner, g_repo, artId];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:api]];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", pat] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDownloadTask *task = [session downloadTaskWithRequest:req
        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !location) {
                showAlert(self, @"下载失败", error ? error.localizedDescription : @"未知错误");
                return;
            }
            NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
            NSString *runId = [g_runURL lastPathComponent];
            NSString *filename = [NSString stringWithFormat:@"%@-%@-%@.zip", g_repo, runId, artName];
            NSString *dest = [docs stringByAppendingPathComponent:filename];
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:dest]) {
                [fm removeItemAtPath:dest error:nil];
            }
            NSError *moveErr = nil;
            [fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:dest] error:&moveErr];
            if (moveErr) {
                showAlert(self, @"保存失败", moveErr.localizedDescription);
                return;
            }

            UIViewController *vc = (UIViewController *)self;
            UIActivityViewController *activity = [[UIActivityViewController alloc]
                initWithActivityItems:@[[NSURL fileURLWithPath:dest]]
                applicationActivities:nil];
            if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                activity.popoverPresentationController.sourceView = vc.view;
                activity.popoverPresentationController.sourceRect =
                    CGRectMake(vc.view.bounds.size.width / 2, vc.view.bounds.size.height / 2, 0, 0);
            }
            [vc presentViewController:activity animated:YES completion:nil];
        });
    }];
    [task resume];
}

static void downloadArtifact(id self, SEL _cmd) {
    NSString *pat = [[NSUserDefaults standardUserDefaults] stringForKey:@"GHArtifactPAT"];
    if (!pat || pat.length < 10) {
        showPATInput(self);
        return;
    }
    if (!g_runURL || !g_owner || !g_repo) {
        showAlert(self, @"未获取到 Run 信息", @"请等待页面加载完成，或重新进入 Actions 详情页");
        return;
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - g_cacheTime > 120) {
        showAlert(self, @"缓存已过期", @"请重新进入 Actions 详情页以刷新数据");
        return;
    }

    NSString *runId = [g_runURL lastPathComponent];
    NSString *api = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/actions/runs/%@/artifacts",
                     g_owner, g_repo, runId];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:api]];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", pat] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                showAlert(self, @"请求失败", error.localizedDescription);
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *artifacts = json[@"artifacts"];
            if (!artifacts || artifacts.count == 0) {
                showAlert(self, @"无 Artifacts", @"该 Run 没有生成 Artifact");
                return;
            }
            NSDictionary *first = artifacts[0];
            NSNumber *artId = first[@"id"];
            NSString *artName = first[@"name"] ?: @"artifact";
            if (!artId) {
                showAlert(self, @"解析失败", @"无法获取 Artifact ID");
                return;
            }
            downloadZip(self, pat, artId, artName);
        });
    }];
    [task resume];
}

#pragma mark - Hooks

static id (*orig_JSON)(id self, SEL _cmd, NSData *data, NSJSONReadingOptions opt, NSError **err);

static id hook_JSON(id self, SEL _cmd, NSData *data, NSJSONReadingOptions opt, NSError **err) {
    id result = orig_JSON(self, _cmd, data, opt, err);
    if (result && data && [data length] > 50 && [data length] < 100000) {
        NSString *preview = [[NSString alloc] initWithData:
            [data subdataWithRange:NSMakeRange(0, MIN(1024, data.length))]
                                                    encoding:NSUTF8StringEncoding];
        if (preview && ([preview containsString:@"WorkflowRun"] || [preview containsString:@"workflowRun"])) {
            extractWorkflowRunInfo(result);
        }
    }
    return result;
}

static void (*orig_vdl)(id self, SEL _cmd);

static void hook_vdl(id self, SEL _cmd) {
    orig_vdl(self, _cmd);
    UIViewController *vc = (UIViewController *)self;
    UIBarButtonItem *dl = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                             target:self
                             action:@selector(gh_downloadArtifact)];
    NSMutableArray *items = [vc.navigationItem.rightBarButtonItems mutableCopy];
    if (!items) items = [NSMutableArray array];
    [items addObject:dl];
    vc.navigationItem.rightBarButtonItems = items;
}

#pragma mark - Constructor

__attribute__((constructor))
static void gh_init() {
    // Hook NSJSONSerialization +JSONObjectWithData:options:error:
    Class jsonCls = objc_getClass("NSJSONSerialization");
    if (jsonCls) {
        Method m = class_getClassMethod(jsonCls, @selector(JSONObjectWithData:options:error:));
        if (m) {
            orig_JSON = (id (*)(id, SEL, NSData *, NSJSONReadingOptions, NSError **))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_JSON);
        }
    }

    // Hook Actions.WorkflowRunViewController -viewDidLoad
    Class vcCls = objc_getClass("Actions.WorkflowRunViewController");
    if (!vcCls) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            Class retryCls = objc_getClass("Actions.WorkflowRunViewController");
            if (retryCls) {
                Method m = class_getInstanceMethod(retryCls, @selector(viewDidLoad));
                if (m) {
                    orig_vdl = (void (*)(id, SEL))method_getImplementation(m);
                    method_setImplementation(m, (IMP)hook_vdl);
                    class_addMethod(retryCls, @selector(gh_downloadArtifact), (IMP)downloadArtifact, "v@:");
                }
            }
        });
        return;
    }
    Method m = class_getInstanceMethod(vcCls, @selector(viewDidLoad));
    if (m) {
        orig_vdl = (void (*)(id, SEL))method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_vdl);
        class_addMethod(vcCls, @selector(gh_downloadArtifact), (IMP)downloadArtifact, "v@:");
    }
}
