//
// GitHub Actions Artifact Downloader v1.0
// TrollStore / Theos 兼容，纯 ObjC Runtime，无 Logos 语法
//
// 功能：
// 1. Hook NSURLSession 拦截 GraphQL 请求，自动提取 Bearer Token 和 Workflow Run ID
// 2. 在 App 窗口添加可拖拽悬浮球
// 3. 点击悬浮球调用 GitHub REST API 获取 Artifact 列表
// 4. 选择 Artifact 后获取 S3 直链，用 Safari 打开下载
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

// ========== 辅助函数：获取顶层 ViewController ==========
static UIViewController *gh_topViewController(void) {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) {
        NSArray *windows = [UIApplication sharedApplication].windows;
        if (windows.count > 0) {
            window = windows[0];
        }
    }
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}

// ========== 辅助函数：显示 Alert ==========
static void gh_showAlert(NSString *title, NSString *message) {
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

// ========== 辅助函数：解析 Workflow Run URL ==========
static void gh_parseWorkflowRunUrl(NSString *urlStr) {
    if (!urlStr || urlStr.length == 0) {
        return;
    }
    NSArray *parts = [urlStr componentsSeparatedByString:@"/"];
    // https://github.com/owner/repo/actions/runs/123
    if (parts.count >= 8) {
        g_currentOwner = parts[3];
        g_currentRepo = parts[4];
        // 安全查找 runs 后面的 ID
        for (NSUInteger i = 5; i < parts.count; i++) {
            if ([parts[i] isEqualToString:@"runs"] && (i + 1) < parts.count) {
                g_currentRunId = parts[i + 1];
                break;
            }
        }
    }
}

// ========== 下载代理：拦截 302 重定向获取 S3 直链 ==========
@interface GHADownloadDelegate : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate>
@property (nonatomic, copy) void (^completionBlock)(NSString *finalUrl, NSError *error);
@property (nonatomic, assign) BOOL completed;
@end

@implementation GHADownloadDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _completed = NO;
    }
    return self;
}

- (void)callCompletion:(NSString *)url error:(NSError *)error {
    if (!self.completed && self.completionBlock) {
        self.completed = YES;
        self.completionBlock(url, error);
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
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
    [self callCompletion:location error:nil];
    completionHandler(nil); // 不跟随重定向
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
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

        [self addTarget:self
                 action:@selector(handleTap)
       forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x,
                              self.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:self.superview];
}

- (void)handleTap {
    [self fetchArtifacts];
}

- (void)fetchArtifacts {
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
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    [req setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                gh_showAlert(@"请求失败", error.localizedDescription);
                return;
            }

            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
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
    (void)name; // 标记已使用，避免编译警告
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
                [[UIApplication sharedApplication] openURL:url
                                                   options:@{}
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

// ========== Hook NSURLSession 提取 Token 和 Run 信息 ==========
static NSURLSessionDataTask *(*orig_dataTaskWithRequest)(id self, SEL _cmd, NSURLRequest *request);

static NSURLSessionDataTask *hooked_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request) {
    NSURL *url = request.URL;
    if (url) {
        NSString *urlString = url.absoluteString;
        if (urlString && [urlString containsString:@"api.github.com"]) {
            // 提取 Authorization Token
            NSString *auth = [request valueForHTTPHeaderField:@"Authorization"];
            if (auth && auth.length > 0) {
                g_currentToken = auth;
            }

            // 解析 GraphQL 请求体，提取 Workflow Run URL
            NSData *body = request.HTTPBody;
            if (body && body.length > 0) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
                if (json && [json isKindOfClass:[NSDictionary class]]) {
                    NSString *opName = json[@"operationName"];
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

// ========== 添加悬浮球到窗口 ==========
static void gh_addFloatingButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_floatingButton) {
            return;
        }
        g_floatingButton = (UIButton *)[[GHAFloatingButton alloc] init];
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) {
            NSArray *windows = [UIApplication sharedApplication].windows;
            if (windows.count > 0) {
                window = windows[0];
            }
        }
        if (window) {
            [window addSubview:g_floatingButton];
        }
    });
}

// ========== 构造函数 ==========
__attribute__((constructor))
static void gh_init(void) {
    // Hook NSURLSession -dataTaskWithRequest:
    Class sessionClass = NSClassFromString(@"NSURLSession");
    if (sessionClass) {
        Method m = class_getInstanceMethod(sessionClass, @selector(dataTaskWithRequest:));
        if (m) {
            orig_dataTaskWithRequest = (NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *))method_getImplementation(m);
            method_setImplementation(m, (IMP)hooked_dataTaskWithRequest);
        }
    }

    // 监听应用 Active 状态，确保悬浮球始终存在
    g_appActiveObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                            object:nil
                                                                             queue:[NSOperationQueue mainQueue]
                                                                        usingBlock:^(NSNotification *note) {
        gh_addFloatingButton();
    }];

    // 立即尝试添加（如果 App 已启动）
    gh_addFloatingButton();
}
