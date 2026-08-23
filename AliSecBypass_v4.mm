//
// GitHub Actions Artifact Downloader v1.3
// TrollStore / Theos 兼容，纯 ObjC Runtime
// 修复：类簇 Hook + 日志写入 Documents 目录
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ========== 全局状态 ==========
static NSString *g_currentToken = nil;
static NSString *g_currentOwner = nil;
static NSString *g_currentRepo = nil;
static NSString *g_currentRunId = nil;
static UIButton *g_floatingButton = nil;
static id g_appActiveObserver = nil;

// ========== 日志系统：写入 App Documents 目录 ==========
static void gh_log(NSString *tag, NSString *message) {
    @try {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *ts = [df stringFromDate:[NSDate date]];
        NSString *line = [NSString stringWithFormat:@"[%@][%@] %@\n", ts, tag, message];

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docPath = paths.count > 0 ? paths[0] : nil;
        if (!docPath) {
            NSLog(@"[GHAD] gh_log failed: no Documents path");
            return;
        }

        NSString *logPath = [docPath stringByAppendingPathComponent:@"github_artifact_debug.log"];

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:logPath]) {
            [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
            if (fh) {
                [fh seekToEndOfFile];
                [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [fh closeFile];
            } else {
                [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[GHAD] gh_log exception: %@", e.reason);
    }
}

// ========== 辅助：通过 UIWindowScene 获取窗口 ==========
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

// ========== 辅助：获取顶层 ViewController ==========
static UIViewController *gh_topViewController(void) {
    UIWindow *window = gh_getKeyWindow();
    if (!window) return nil;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}

// ========== 辅助：显示 Alert ==========
static void gh_showAlert(NSString *title, NSString *message) {
    gh_log(@"ALERT", [NSString stringWithFormat:@"%@: %@", title, message]);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        UIViewController *topVC = gh_topViewController();
        if (topVC) {
            [topVC presentViewController:alert animated:YES completion:nil];
        }
    });
}

// ========== 辅助：解析 Workflow Run URL ==========
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
    gh_log(@"PARSE", [NSString stringWithFormat:@"owner=%@ repo=%@ runId=%@", 
          g_currentOwner ?: @"nil", g_currentRepo ?: @"nil", g_currentRunId ?: @"nil"]);
}

// ========== 下载代理：拦截 302 重定向 ==========
@interface GHADownloadDelegate : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate>
@property (nonatomic, copy) void (^completionBlock)(NSString *finalUrl, NSError *error);
@property (nonatomic, assign) BOOL completed;
@end

@implementation GHADownloadDelegate
- (instancetype)init {
    self = [super init];
    if (self) { _completed = NO; }
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
    NSDictionary *headers = response.allHeaderFields;
    for (NSString *key in headers) {
        if ([key caseInsensitiveCompare:@"Location"] == NSOrderedSame) {
            location = headers[key];
            break;
        }
    }
    gh_log(@"REDIRECT", [NSString stringWithFormat:@"Location=%@", location ?: @"nil"]);
    [self callCompletion:location error:nil];
    completionHandler(nil);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (error) {
        [self callCompletion:nil error:error];
    } else if (!self.completed) {
        [self callCompletion:nil error:nil];
    }
}
@end

// ========== 悬浮球按钮 ==========
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

        gh_log(@"BUTTON", @"GHAFloatingButton init completed");
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x,
                              self.center.y + translation.y);
    [pan setTranslation:CGPointMake(0, 0) inView:self.superview];
}

- (void)handleTap {
    gh_log(@"BUTTON", @"Tapped!");
    [self fetchArtifacts];
}

- (void)fetchArtifacts {
    gh_log(@"FETCH", [NSString stringWithFormat:@"token=%@ owner=%@ repo=%@ runId=%@",
          g_currentToken ? @"YES" : @"NO",
          g_currentOwner ?: @"nil",
          g_currentRepo ?: @"nil",
          g_currentRunId ?: @"nil"]);

    if (!g_currentToken || g_currentToken.length == 0) {
        gh_showAlert(@"错误", @"未获取到 GitHub Token，请先进入某个 Workflow Run 详情页");
        return;
    }
    if (!g_currentOwner || !g_currentRepo || !g_currentRunId) {
        gh_showAlert(@"错误", @"未检测到 Workflow Run，请先进入 Actions 页面的某个 Run");
        return;
    }

    NSString *urlStr = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/actions/runs/%@/artifacts",
                        g_currentOwner, g_currentRepo, g_currentRunId];
    gh_log(@"FETCH", [NSString stringWithFormat:@"API URL: %@", urlStr]);

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    [req setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                gh_log(@"FETCH-ERR", error.localizedDescription);
                gh_showAlert(@"请求失败", error.localizedDescription);
                return;
            }
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            gh_log(@"FETCH-RESP", [NSString stringWithFormat:@"HTTP %ld", (long)httpResp.statusCode]);
            if (httpResp.statusCode != 200) {
                NSString *errMsg = [NSString stringWithFormat:@"HTTP %ld", (long)httpResp.statusCode];
                gh_showAlert(@"请求失败", errMsg);
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (!json || ![json isKindOfClass:[NSDictionary class]]) {
                gh_showAlert(@"错误", @"解析响应失败");
                return;
            }
            NSArray *artifacts = json[@"artifacts"];
            gh_log(@"FETCH-ARTIFACTS", [NSString stringWithFormat:@"count=%lu", (unsigned long)artifacts.count]);
            if (!artifacts || artifacts.count == 0) {
                gh_showAlert(@"提示", @"该 Workflow Run 没有 Artifacts");
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
            [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                        style:UIAlertActionStyleCancel
                                                      handler:nil]];
            UIViewController *topVC = gh_topViewController();
            if (topVC) {
                if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                    alert.popoverPresentationController.sourceView = self;
                    alert.popoverPresentationController.sourceRect = self.bounds;
                }
                [topVC presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
    [task resume];
}

- (void)downloadArtifact:(NSString *)downloadUrl name:(NSString *)name {
    (void)name;
    gh_log(@"DL", [NSString stringWithFormat:@"url=%@", downloadUrl]);
    if (!downloadUrl || downloadUrl.length == 0) {
        gh_showAlert(@"错误", @"下载链接为空");
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:downloadUrl]];
    [req setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    req.HTTPMethod = @"GET";

    GHADownloadDelegate *delegate = [[GHADownloadDelegate alloc] init];
    delegate.completionBlock = ^(NSString *finalUrl, NSError *error) {
        if (error) {
            gh_showAlert(@"下载失败", error.localizedDescription);
            return;
        }
        if (finalUrl && finalUrl.length > 0) {
            NSURL *url = [NSURL URLWithString:finalUrl];
            if (url) {
                [[UIApplication sharedApplication] openURL:url options:@{}
                                         completionHandler:^(BOOL success) {
                    if (!success) {
                        gh_showAlert(@"错误", @"无法打开下载链接");
                    }
                }];
            } else {
                gh_showAlert(@"错误", @"下载链接格式错误");
            }
        } else {
            gh_showAlert(@"错误", @"无法获取下载链接，可能 Artifact 已过期或没有权限");
        }
    };
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                          delegate:delegate
                                                     delegateQueue:[NSOperationQueue mainQueue]];
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
                gh_log(@"HOOK", [NSString stringWithFormat:@"Token captured: %@", 
                      [auth substringToIndex:MIN(20, auth.length)]]);
            }
            NSData *body = request.HTTPBody;
            if (body && body.length > 0) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
                if (json && [json isKindOfClass:[NSDictionary class]]) {
                    NSString *opName = json[@"operationName"];
                    gh_log(@"HOOK", [NSString stringWithFormat:@"GraphQL op=%@", opName ?: @"unknown"]);
                    if ([opName isEqualToString:@"WorkflowRun"]) {
                        NSDictionary *vars = json[@"variables"];
                        if (vars) {
                            NSString *runUrl = vars[@"url"];
                            if (runUrl) {
                                gh_parseWorkflowRunUrl(runUrl);
                            }
                        }
                    }
                }
            }
        }
    }
    return orig_dataTaskWithRequest(self, _cmd, request);
}

// ========== 对指定类设置 Hook ==========
static void gh_hookSessionClass(Class cls) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:));
    if (m) {
        orig_dataTaskWithRequest = (NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_dataTaskWithRequest);
        gh_log(@"HOOK", [NSString stringWithFormat:@"Hooked %@", NSStringFromClass(cls)]);
    } else {
        gh_log(@"HOOK", [NSString stringWithFormat:@"Method not found in %@", NSStringFromClass(cls)]);
    }
}

// ========== 添加悬浮球 ==========
static void gh_addFloatingButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_floatingButton) {
            gh_log(@"UI", @"Floating button already exists");
            return;
        }
        g_floatingButton = (UIButton *)[[GHAFloatingButton alloc] init];
        UIWindow *window = gh_getKeyWindow();
        if (window) {
            [window addSubview:g_floatingButton];
            gh_log(@"UI", [NSString stringWithFormat:@"Button added to window %@", NSStringFromClass([window class])]);
        } else {
            gh_log(@"UI-ERR", @"Failed to get key window, button not added");
        }
    });
}

// ========== 构造函数 ==========
__attribute__((constructor))
static void gh_init(void) {
    gh_log(@"INIT", @"=== GitHub Actions Artifact Downloader v1.3 ===");
    gh_log(@"INIT", [NSString stringWithFormat:@"Process: %@", [[NSProcessInfo processInfo] processName]]);
    gh_log(@"INIT", [NSString stringWithFormat:@"Bundle: %@", [[NSBundle mainBundle] bundleIdentifier]]);

    // Hook NSURLSession 主类
    Class sessionClass = NSClassFromString(@"NSURLSession");
    gh_hookSessionClass(sessionClass);

    // Hook 类簇子类 __NSCFURLSession（iOS 实际使用的类）
    Class cfSessionClass = NSClassFromString(@"__NSCFURLSession");
    if (cfSessionClass && cfSessionClass != sessionClass) {
        gh_hookSessionClass(cfSessionClass);
    }

    // 监听应用 Active
    g_appActiveObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                            object:nil
                                                                             queue:[NSOperationQueue mainQueue]
                                                                        usingBlock:^(NSNotification *note) {
        gh_log(@"NOTIFY", @"App became active");
        gh_addFloatingButton();
    }];

    gh_addFloatingButton();
    gh_log(@"INIT", @"Init completed");
}
