//
// GitHub Actions Artifact Downloader v1.4
// 修复：NSLog/printf 双保险日志 + 延迟 UI 初始化
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/log.h>

// ========== 全局状态 ==========
static NSString *g_currentToken = nil;
static NSString *g_currentOwner = nil;
static NSString *g_currentRepo = nil;
static NSString *g_currentRunId = nil;
static UIButton *g_floatingButton = nil;

// ========== 日志：NSLog + printf + 文件 三重保险 ==========
static void gh_log(const char *tag, const char *msg) {
    // 1. NSLog（系统日志，idevicesyslog 可见）
    NSLog(@"[GHAD][%s] %s", tag, msg);

    // 2. printf（stderr，Xcode/idevicesyslog 可见）
    printf("[GHAD][%s] %s\n", tag, msg);

    // 3. 尝试写入 /tmp/（全局可写，不依赖沙盒）
    @try {
        time_t now = time(NULL);
        struct tm *t = localtime(&now);
        char line[1024];
        snprintf(line, sizeof(line), "[%04d-%02d-%02d %02d:%02d:%02d][%s] %s\n",
                 t->tm_year + 1900, t->tm_mon + 1, t->tm_mday,
                 t->tm_hour, t->tm_min, t->tm_sec, tag, msg);

        int fd = open("/tmp/github_artifact.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0) {
            write(fd, line, strlen(line));
            close(fd);
        }
    } @catch (...) {}
}

static void gh_log_ns(NSString *tag, NSString *msg) {
    const char *t = tag ? [tag UTF8String] : "?";
    const char *m = msg ? [msg UTF8String] : "nil";
    gh_log(t, m);
}

// ========== 辅助：获取窗口（兼容 iOS 13+） ==========
static UIWindow *gh_getKeyWindow(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;

    if (@available(iOS 13.0, *)) {
        NSSet *scenes = app.connectedScenes;
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in ws.windows) {
                        if (w.isKeyWindow) return w;
                    }
                    if (ws.windows.count > 0) return ws.windows[0];
                }
            }
        }
    }
    return nil;
}

// ========== 辅助：获取顶层 VC ==========
static UIViewController *gh_topViewController(void) {
    UIWindow *window = gh_getKeyWindow();
    if (!window) return nil;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}

// ========== 辅助：Alert ==========
static void gh_alert(NSString *title, NSString *msg) {
    gh_log_ns(@"ALERT", [NSString stringWithFormat:@"%@ | %@", title, msg]);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:msg
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *top = gh_topViewController();
        if (top) [top presentViewController:alert animated:YES completion:nil];
    });
}

// ========== 解析 Workflow Run URL ==========
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
    gh_log_ns(@"PARSE", [NSString stringWithFormat:@"owner=%@ repo=%@ runId=%@",
               g_currentOwner ?: @"nil", g_currentRepo ?: @"nil", g_currentRunId ?: @"nil"]);
}

// ========== 下载代理 ==========
@interface GHADownloadDelegate : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate>
@property (nonatomic, copy) void (^completionBlock)(NSString *finalUrl, NSError *error);
@property (nonatomic, assign) BOOL completed;
@end

@implementation GHADownloadDelegate
- (instancetype)init {
    self = [super init];
    if (self) _completed = NO;
    return self;
}
- (void)callCompletion:(NSString *)url error:(NSError *)error {
    if (!self.completed && self.completionBlock) {
        self.completed = YES;
        self.completionBlock(url, error);
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    NSString *location = nil;
    for (NSString *key in response.allHeaderFields) {
        if ([key caseInsensitiveCompare:@"Location"] == NSOrderedSame) {
            location = response.allHeaderFields[key];
            break;
        }
    }
    gh_log_ns(@"REDIRECT", location ?: @"nil");
    [self callCompletion:location error:nil];
    completionHandler(nil);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (error) [self callCompletion:nil error:error];
    else if (!self.completed) [self callCompletion:nil error:nil];
}
@end

// ========== 悬浮球 ==========
@interface GHAFloatingButton : UIButton
- (void)handleTap;
- (void)handlePan:(UIPanGestureRecognizer *)pan;
- (void)fetchArtifacts;
- (void)downloadArtifact:(NSString *)downloadUrl name:(NSString *)name;
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

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                                action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        [self addTarget:self action:@selector(handleTap)
       forControlEvents:UIControlEventTouchUpInside];

        gh_log_ns(@"BUTTON", @"FloatingButton created");
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [pan setTranslation:CGPointMake(0, 0) inView:self.superview];
}

- (void)handleTap {
    gh_log_ns(@"BUTTON", @"Tapped");
    [self fetchArtifacts];
}

- (void)fetchArtifacts {
    gh_log_ns(@"FETCH", [NSString stringWithFormat:@"token=%@ owner=%@ repo=%@ runId=%@",
               g_currentToken ? @"YES" : @"NO",
               g_currentOwner ?: @"nil",
               g_currentRepo ?: @"nil",
               g_currentRunId ?: @"nil"]);

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
    gh_log_ns(@"FETCH", urlStr);

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    [req setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                gh_alert(@"请求失败", error.localizedDescription);
                return;
            }
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            gh_log_ns(@"FETCH-RESP", [NSString stringWithFormat:@"HTTP %ld", (long)httpResp.statusCode]);
            if (httpResp.statusCode != 200) {
                gh_alert(@"请求失败", [NSString stringWithFormat:@"HTTP %ld", (long)httpResp.statusCode]);
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (!json || ![json isKindOfClass:[NSDictionary class]]) {
                gh_alert(@"错误", @"解析响应失败");
                return;
            }
            NSArray *artifacts = json[@"artifacts"];
            gh_log_ns(@"FETCH-ARTIFACTS", [NSString stringWithFormat:@"count=%lu", (unsigned long)artifacts.count]);
            if (!artifacts || artifacts.count == 0) {
                gh_alert(@"提示", @"该 Workflow Run 没有 Artifacts");
                return;
            }

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Artifacts"
                                                                           message:@"选择要下载的 Artifact"
                                                                    preferredStyle:UIAlertControllerStyleActionSheet];
            for (NSDictionary *art in artifacts) {
                NSString *name = art[@"name"];
                NSString *downloadUrl = art[@"archive_download_url"];
                if (name && downloadUrl) {
                    UIAlertAction *action = [UIAlertAction actionWithTitle:name
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^(UIAlertAction *action) {
                        [self downloadArtifact:downloadUrl name:name];
                    }];
                    [alert addAction:action];
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

- (void)downloadArtifact:(NSString *)downloadUrl name:(NSString *)name {
    (void)name;
    gh_log_ns(@"DL", downloadUrl);
    if (!downloadUrl || downloadUrl.length == 0) {
        gh_alert(@"错误", @"下载链接为空");
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:downloadUrl]];
    [req setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    req.HTTPMethod = @"GET";

    GHADownloadDelegate *delegate = [[GHADownloadDelegate alloc] init];
    delegate.completionBlock = ^(NSString *finalUrl, NSError *error) {
        if (error) {
            gh_alert(@"下载失败", error.localizedDescription);
            return;
        }
        if (finalUrl && finalUrl.length > 0) {
            NSURL *url = [NSURL URLWithString:finalUrl];
            if (url) {
                [[UIApplication sharedApplication] openURL:url options:@{}
                                         completionHandler:^(BOOL success) {
                    if (!success) gh_alert(@"错误", @"无法打开下载链接");
                }];
            } else {
                gh_alert(@"错误", @"下载链接格式错误");
            }
        } else {
            gh_alert(@"错误", @"无法获取下载链接，可能 Artifact 已过期或没有权限");
        }
    };
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:[NSOperationQueue mainQueue]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req];
    [task resume];
}

@end

// ========== Hook 实现 ==========
static NSURLSessionDataTask *(*orig_dataTaskWithRequest)(id self, SEL _cmd, NSURLRequest *request);

static NSURLSessionDataTask *hooked_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request) {
    NSURL *url = request.URL;
    if (url) {
        NSString *urlString = url.absoluteString;
        if (urlString && [urlString containsString:@"api.github.com"]) {
            NSString *auth = [request valueForHTTPHeaderField:@"Authorization"];
            if (auth && auth.length > 0) {
                g_currentToken = auth;
                gh_log_ns(@"HOOK", [NSString stringWithFormat:@"Token captured: %@",
                           [auth substringToIndex:MIN(20, auth.length)]]);
            }
            NSData *body = request.HTTPBody;
            if (body && body.length > 0) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
                if (json && [json isKindOfClass:[NSDictionary class]]) {
                    NSString *opName = json[@"operationName"];
                    gh_log_ns(@"HOOK", [NSString stringWithFormat:@"GraphQL op=%@", opName ?: @"unknown"]);
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
        gh_log_ns(@"HOOK", [NSString stringWithFormat:@"Hooked %@", NSStringFromClass(cls)]);
    } else {
        gh_log_ns(@"HOOK-ERR", [NSString stringWithFormat:@"Method not found in %@", NSStringFromClass(cls)]);
    }
}

// ========== 添加悬浮球 ==========
static void gh_addFloatingButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_floatingButton) {
            gh_log_ns(@"UI", @"Button already exists");
            return;
        }
        g_floatingButton = (UIButton *)[[GHAFloatingButton alloc] init];
        UIWindow *window = gh_getKeyWindow();
        if (window) {
            [window addSubview:g_floatingButton];
            gh_log_ns(@"UI", [NSString stringWithFormat:@"Button added to %@", NSStringFromClass([window class])]);
        } else {
            gh_log_ns(@"UI-ERR", @"No key window found");
        }
    });
}

// ========== 延迟初始化（等 App 完全启动） ==========
static void gh_delayedInit(void) {
    gh_log_ns(@"INIT", @"Delayed init starting...");
    gh_addFloatingButton();
    gh_log_ns(@"INIT", @"Delayed init completed");
}

// ========== 构造函数 ==========
__attribute__((constructor))
static void gh_init(void) {
    gh_log("INIT", "=== GitHub Actions Artifact Downloader v1.4 ===");
    gh_log("INIT", "Constructor entered");

    // Hook 网络层
    Class sessionClass = NSClassFromString(@"NSURLSession");
    gh_hookSessionClass(sessionClass);

    Class cfSessionClass = NSClassFromString(@"__NSCFURLSession");
    if (cfSessionClass && cfSessionClass != sessionClass) {
        gh_hookSessionClass(cfSessionClass);
    }

    // 延迟 3 秒初始化 UI（等 App 完全启动）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        gh_delayedInit();
    });

    gh_log("INIT", "Constructor completed");
}
