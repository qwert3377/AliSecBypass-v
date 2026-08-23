//
// GitHub Actions Artifact Downloader v1.5
// 修复：插件内部下载 + UIActivityViewController 系统分享
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ========== 全局状态 ==========
static NSString *g_currentToken = nil;
static NSString *g_currentOwner = nil;
static NSString *g_currentRepo = nil;
static NSString *g_currentRunId = nil;
static UIButton *g_floatingButton = nil;

// ========== 日志 ==========
static void gh_log(const char *tag, const char *msg) {
    NSLog(@"[GHAD][%s] %s", tag, msg);
    printf("[GHAD][%s] %s\n", tag, msg);
}

static void gh_log_ns(NSString *tag, NSString *msg) {
    gh_log(tag.UTF8String, msg.UTF8String);
}

// ========== 辅助 ==========
static UIWindow *gh_getKeyWindow(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in ws.windows) if (w.isKeyWindow) return w;
                    if (ws.windows.count > 0) return ws.windows[0];
                }
            }
        }
    }
    return nil;
}

static UIViewController *gh_topViewController(void) {
    UIWindow *window = gh_getKeyWindow();
    if (!window) return nil;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static void gh_alert(NSString *title, NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *top = gh_topViewController();
        if (top) [top presentViewController:alert animated:YES completion:nil];
    });
}

static void gh_parseWorkflowRunUrl(NSString *urlStr) {
    if (!urlStr || urlStr.length == 0) return;
    NSArray *parts = [urlStr componentsSeparatedByString:@"/"];
    if (parts.count >= 8) {
        g_currentOwner = parts[3];
        g_currentRepo = parts[4];
        for (NSUInteger i = 5; i < parts.count; i++) {
            if ([parts[i] isEqualToString:@"runs"] && (i + 1) < parts.count) {
                g_currentRunId = parts[i + 1];
                break;
            }
        }
    }
}

// ========== 获取 S3 直链的 Delegate ==========
@interface GHARedirectDelegate : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate>
@property (nonatomic, copy) void (^completion)(NSString *s3Url, NSError *err);
@property (nonatomic, assign) BOOL done;
@end

@implementation GHARedirectDelegate
- (instancetype)init {
    self = [super init]; if (self) _done = NO; return self;
}
- (void)finish:(NSString *)url error:(NSError *)err {
    if (!_done && _completion) { _done = YES; _completion(url, err); }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    NSString *loc = response.allHeaderFields[@"Location"];
    if (!loc) {
        for (NSString *k in response.allHeaderFields) {
            if ([k caseInsensitiveCompare:@"Location"] == NSOrderedSame) {
                loc = response.allHeaderFields[k]; break;
            }
        }
    }
    [self finish:loc error:nil];
    completionHandler(nil); // 不跟随
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (error) [self finish:nil error:error];
    else if (!_done) [self finish:nil error:nil];
}
@end

// ========== 悬浮球 ==========
@interface GHAFloatingButton : UIButton
- (void)handleTap;
- (void)handlePan:(UIPanGestureRecognizer *)pan;
- (void)fetchArtifacts;
- (void)downloadArtifact:(NSString *)downloadUrl name:(NSString *)name;
- (void)showShareSheet:(NSURL *)fileURL name:(NSString *)name;
@end

@implementation GHAFloatingButton

- (instancetype)init {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    self = [super initWithFrame:CGRectMake(screenW - 70, screenH / 2.0 - 30, 60, 60)];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.95 alpha:0.92];
        self.layer.cornerRadius = 30;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowRadius = 4;
        self.layer.shadowOpacity = 0.3;
        [self setTitle:@"📦" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:26];
        self.titleLabel.adjustsFontSizeToFitWidth = YES;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        [self addTarget:self action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [pan setTranslation:CGPointMake(0, 0) inView:self.superview];
}

- (void)handleTap {
    [self fetchArtifacts];
}

- (void)fetchArtifacts {
    if (!g_currentToken || g_currentToken.length == 0) {
        gh_alert(@"错误", @"未获取到 GitHub Token，请先进入某个 Workflow Run 详情页");
        return;
    }
    if (!g_currentOwner || !g_currentRepo || !g_currentRunId) {
        gh_alert(@"错误", @"未检测到 Workflow Run，请先进入 Actions 页面的某个 Run");
        return;
    }

    NSString *urlStr = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/actions/runs/%@/artifacts",
                        g_currentOwner, g_currentRepo, g_currentRunId];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    [req setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { gh_alert(@"请求失败", error.localizedDescription); return; }
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (httpResp.statusCode != 200) {
                gh_alert(@"请求失败", [NSString stringWithFormat:@"HTTP %ld", (long)httpResp.statusCode]);
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (!json || ![json isKindOfClass:[NSDictionary class]]) {
                gh_alert(@"错误", @"解析响应失败"); return;
            }
            NSArray *artifacts = json[@"artifacts"];
            if (!artifacts || artifacts.count == 0) {
                gh_alert(@"提示", @"该 Workflow Run 没有 Artifacts"); return;
            }

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Artifacts"
                                                                           message:@"选择要下载的 Artifact"
                                                                    preferredStyle:UIAlertControllerStyleActionSheet];
            for (NSDictionary *art in artifacts) {
                NSString *name = art[@"name"];
                NSString *downloadUrl = art[@"archive_download_url"];
                if (name && downloadUrl) {
                    [alert addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction *action) {
                        [self downloadArtifact:downloadUrl name:name];
                    }]];
                }
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            UIViewController *top = gh_topViewController();
            if (top) {
                if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                    alert.popoverPresentationController.sourceView = self;
                    alert.popoverPresentationController.sourceRect = self.bounds;
                }
                [top presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
    [task resume];
}

// ========== 核心：插件内部下载 + 系统分享 ==========
- (void)downloadArtifact:(NSString *)downloadUrl name:(NSString *)name {
    if (!downloadUrl || downloadUrl.length == 0) {
        gh_alert(@"错误", @"下载链接为空"); return;
    }

    // Step 1: 获取 S3 直链（GitHub artifact URL 会 302 到 S3）
    NSMutableURLRequest *headReq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:downloadUrl]];
    [headReq setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
    headReq.HTTPMethod = @"HEAD";

    // 先显示 loading
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"下载中..."
                                                                     message:@"正在获取下载链接"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    UIViewController *top = gh_topViewController();
    if (top) [top presentViewController:loading animated:YES completion:nil];

    GHARedirectDelegate *delegate = [[GHARedirectDelegate alloc] init];
    delegate.completion = ^(NSString *s3Url, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [loading dismissViewControllerAnimated:YES completion:nil];
            if (err || !s3Url || s3Url.length == 0) {
                gh_alert(@"错误", @"无法获取下载链接，可能 Artifact 已过期");
                return;
            }
            [self downloadFromS3:s3Url name:name];
        });
    };

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg delegate:delegate delegateQueue:[NSOperationQueue mainQueue]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:headReq];
    [task resume];
}

- (void)downloadFromS3:(NSString *)s3Url name:(NSString *)name {
    NSURL *url = [NSURL URLWithString:s3Url];
    if (!url) { gh_alert(@"错误", @"链接格式错误"); return; }

    // 显示下载进度
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"正在下载 %@", name]
                                                                           message:@"请稍候..."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    UIViewController *top = gh_topViewController();
    if (top) [top presentViewController:progressAlert animated:YES completion:nil];

    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url
                                                                 completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressAlert dismissViewControllerAnimated:YES completion:nil];
            if (error) {
                gh_alert(@"下载失败", error.localizedDescription);
                return;
            }
            if (!location) {
                gh_alert(@"错误", @"下载文件为空");
                return;
            }

            // 复制到临时目录，加上 .zip 后缀（GitHub artifact 是 zip）
            NSString *tmpDir = NSTemporaryDirectory();
            NSString *safeName = [name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
            NSString *fileName = [NSString stringWithFormat:@"%@.zip", safeName];
            NSString *destPath = [tmpDir stringByAppendingPathComponent:fileName];

            NSFileManager *fm = [NSFileManager defaultManager];
            [fm removeItemAtPath:destPath error:nil]; // 删除旧文件
            NSError *copyErr = nil;
            [fm copyItemAtPath:location.path toPath:destPath error:&copyErr];
            if (copyErr) {
                gh_alert(@"错误", [NSString stringWithFormat:@"保存文件失败: %@", copyErr.localizedDescription]);
                return;
            }

            NSURL *fileURL = [NSURL fileURLWithPath:destPath];
            [self showShareSheet:fileURL name:name];
        });
    }];
    [task resume];
}

- (void)showShareSheet:(NSURL *)fileURL name:(NSString *)name {
    (void)name;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                           applicationActivities:nil];

    // iPad 适配
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activity.popoverPresentationController.sourceView = self;
        activity.popoverPresentationController.sourceRect = self.bounds;
    }

    UIViewController *top = gh_topViewController();
    if (top) {
        [top presentViewController:activity animated:YES completion:nil];
    }
}

@end

// ========== Hook NSURLSession ==========
static NSURLSessionDataTask *(*orig_dataTaskWithRequest)(id self, SEL _cmd, NSURLRequest *request);

static NSURLSessionDataTask *hooked_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request) {
    NSURL *url = request.URL;
    if (url) {
        NSString *urlString = url.absoluteString;
        if (urlString && [urlString containsString:@"api.github.com"]) {
            NSString *auth = [request valueForHTTPHeaderField:@"Authorization"];
            if (auth && auth.length > 0) g_currentToken = auth;

            NSData *body = request.HTTPBody;
            if (body && body.length > 0) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
                if (json && [json isKindOfClass:[NSDictionary class]]) {
                    NSString *opName = json[@"operationName"];
                    if ([opName isEqualToString:@"WorkflowRun"]) {
                        NSDictionary *vars = json[@"variables"];
                        if (vars) {
                            NSString *runUrl = vars[@"url"];
                            if (runUrl) gh_parseWorkflowRunUrl(runUrl);
                        }
                    }
                }
            }
        }
    }
    return orig_dataTaskWithRequest(self, _cmd, request);
}

static void gh_hookSessionClass(Class cls) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:));
    if (m) {
        orig_dataTaskWithRequest = (NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_dataTaskWithRequest);
    }
}

static void gh_addFloatingButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_floatingButton) return;
        g_floatingButton = (UIButton *)[[GHAFloatingButton alloc] init];
        UIWindow *window = gh_getKeyWindow();
        if (window) [window addSubview:g_floatingButton];
    });
}

__attribute__((constructor))
static void gh_init(void) {
    gh_log("INIT", "GitHub Actions Artifact Downloader v1.5");
    gh_hookSessionClass(NSClassFromString(@"NSURLSession"));
    gh_hookSessionClass(NSClassFromString(@"__NSCFURLSession"));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ gh_addFloatingButton(); });
}