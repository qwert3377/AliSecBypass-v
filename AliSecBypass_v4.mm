//
// GitHub Actions Artifact Downloader v3.3
// 精致版：自定义Cell + 图标 + 空状态 + 美化历史
// 修复：类定义顺序
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *g_currentToken = nil;
static NSString *g_currentOwner = nil;
static NSString *g_currentRepo = nil;
static NSString *g_currentRunId = nil;
static UIView *g_floatingView = nil;
static const char kGHAssocKey = 0;

static void gh_log(const char *tag, const char *msg) {
    NSLog(@"[GHAD][%s] %s", tag, msg);
    printf("[GHAD][%s] %s\n", tag, msg);
}

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

static NSString *gh_formatSize(NSNumber *bytes) {
    if (!bytes) return @"Unknown";
    double b = bytes.doubleValue;
    if (b < 1024) return [NSString stringWithFormat:@"%.0f B", b];
    if (b < 1024 * 1024) return [NSString stringWithFormat:@"%.1f KB", b / 1024.0];
    return [NSString stringWithFormat:@"%.2f MB", b / 1024.0 / 1024.0];
}

static NSString *gh_formatDate(NSTimeInterval ts) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"MM-dd HH:mm";
    return [df stringFromDate:date];
}

// ========== 设置 ==========
@interface GHASettings : NSObject
+ (BOOL)autoUnzip;
+ (void)setAutoUnzip:(BOOL)v;
@end

@implementation GHASettings
+ (NSDictionary *)dict {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"GHAD_Settings"];
}
+ (void)saveDict:(NSDictionary *)d {
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:@"GHAD_Settings"];
}
+ (BOOL)autoUnzip {
    NSDictionary *d = [self dict];
    return d ? [d[@"autoUnzip"] boolValue] : NO;
}
+ (void)setAutoUnzip:(BOOL)v {
    NSMutableDictionary *d = [[self dict] mutableCopy] ?: [NSMutableDictionary dictionary];
    d[@"autoUnzip"] = @(v);
    [self saveDict:d];
}
@end

// ========== 历史记录 ==========
@interface GHAHistory : NSObject
+ (void)addRecord:(NSString *)name repo:(NSString *)repo;
+ (NSArray *)records;
+ (void)clear;
@end

@implementation GHAHistory
+ (NSMutableArray *)loadRecords {
    NSArray *arr = [[NSUserDefaults standardUserDefaults] objectForKey:@"GHAD_History"];
    return arr ? [arr mutableCopy] : [NSMutableArray array];
}
+ (void)saveRecords:(NSArray *)arr {
    [[NSUserDefaults standardUserDefaults] setObject:arr forKey:@"GHAD_History"];
}
+ (void)addRecord:(NSString *)name repo:(NSString *)repo {
    NSMutableArray *arr = [self loadRecords];
    NSDictionary *rec = @{
        @"name": name ?: @"",
        @"repo": repo ?: @"",
        @"date": @([[NSDate date] timeIntervalSince1970])
    };
    [arr insertObject:rec atIndex:0];
    if (arr.count > 30) [arr removeObjectsInRange:NSMakeRange(30, arr.count - 30)];
    [self saveRecords:arr];
}
+ (NSArray *)records { return [self loadRecords]; }
+ (void)clear { [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"GHAD_History"]; }
@end

// ========== S3 重定向 Delegate ==========
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
    NSString *loc = nil;
    for (NSString *k in response.allHeaderFields) {
        if ([k caseInsensitiveCompare:@"Location"] == NSOrderedSame) {
            loc = response.allHeaderFields[k]; break;
        }
    }
    [self finish:loc error:nil];
    completionHandler(nil);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (error) [self finish:nil error:error];
    else if (!_done) [self finish:nil error:nil];
}
@end

// ========== 自定义历史 Cell ==========
@interface GHAHistoryCell : UITableViewCell
@end

@implementation GHAHistoryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        self.imageView.image = [UIImage systemImageNamed:@"arrow.down.circle.fill"];
        self.imageView.tintColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.95 alpha:1];
        self.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        self.detailTextLabel.font = [UIFont systemFontOfSize:12];
        self.detailTextLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    }
    return self;
}

- (void)configureWithRecord:(NSDictionary *)rec {
    self.textLabel.text = rec[@"name"];
    NSString *repo = rec[@"repo"];
    NSNumber *dateNum = rec[@"date"];
    NSString *dateStr = dateNum ? gh_formatDate(dateNum.doubleValue) : @"";
    self.detailTextLabel.text = [NSString stringWithFormat:@"%@  |  %@", repo, dateStr];
}

@end

// ========== 历史记录 VC ==========
@interface GHAHistoryVC : UITableViewController
@end

@implementation GHAHistoryVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"下载历史";
    self.view.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(clear)];
    [self.tableView registerClass:[GHAHistoryCell class] forCellReuseIdentifier:@"hcell"];
    self.tableView.rowHeight = 56;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 56, 0, 0);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)clear {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认清空"
                                                                   message:@"确定要清空所有下载历史吗？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [GHAHistory clear];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = [GHAHistory records].count;
    if (count == 0) {
        UILabel *emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, tableView.bounds.size.width, 40)];
        emptyLabel.text = @"暂无下载记录";
        emptyLabel.textAlignment = NSTextAlignmentCenter;
        emptyLabel.font = [UIFont systemFontOfSize:15];
        emptyLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];
        tableView.backgroundView = emptyLabel;
    } else {
        tableView.backgroundView = nil;
    }
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GHAHistoryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"hcell" forIndexPath:indexPath];
    NSDictionary *rec = [GHAHistory records][indexPath.row];
    [cell configureWithRecord:rec];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *records = [GHAHistory records];
    if (indexPath.row >= records.count) return;
    NSDictionary *rec = records[indexPath.row];
    NSString *name = rec[@"name"];

    // 在临时目录查找该文件
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *safeName = [name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *fileName = [NSString stringWithFormat:@"%@.zip", safeName];
    NSString *path = [tmpDir stringByAppendingPathComponent:fileName];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        // 尝试带序号的
        for (NSInteger i = 1; i < 100; i++) {
            NSString *base = [safeName stringByAppendingFormat:@"_%ld", (long)i];
            fileName = [NSString stringWithFormat:@"%@.zip", base];
            NSString *tryPath = [tmpDir stringByAppendingPathComponent:fileName];
            if ([fm fileExistsAtPath:tryPath]) {
                path = tryPath;
                break;
            }
        }
    }

    if (![fm fileExistsAtPath:path]) {
        gh_alert(@"错误", @"文件已被删除或已过期");
        return;
    }

    NSURL *fileURL = [NSURL fileURLWithPath:path];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                           applicationActivities:nil];
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        activity.popoverPresentationController.sourceView = cell;
        activity.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:activity animated:YES completion:nil];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSMutableArray *records = [GHAHistory loadRecords];
        if (indexPath.row < records.count) {
            [records removeObjectAtIndex:indexPath.row];
            [GHAHistory saveRecords:records];
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        }
    }
}

@end

// ========== 设置 VC ==========
@interface GHASettingsVC : UITableViewController
@end

@implementation GHASettingsVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    self.view.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"scell"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"scell" forIndexPath:indexPath];
    if (indexPath.row == 0) {
        cell.textLabel.text = @"自动解压";
        cell.detailTextLabel.text = @"下载完成后自动解压 zip";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [GHASettings autoUnzip];
        [sw addTarget:self action:@selector(toggleUnzip:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else {
        cell.textLabel.text = @"下载历史";
        cell.detailTextLabel.text = @"查看已下载的 Artifacts";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 1) {
        GHAHistoryVC *vc = [[GHAHistoryVC alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (void)toggleUnzip:(UISwitch *)sender {
    [GHASettings setAutoUnzip:sender.isOn];
}

@end

// ========== 自定义 Artifact Cell ==========
@interface GHAArtifactCell : UITableViewCell
@end

@implementation GHAArtifactCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        self.imageView.image = [UIImage systemImageNamed:@"cube.box.fill"];
        self.imageView.tintColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.95 alpha:1];
        self.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        self.detailTextLabel.font = [UIFont systemFontOfSize:13];
        self.detailTextLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    }
    return self;
}

- (void)configureWithName:(NSString *)name size:(NSString *)size {
    self.textLabel.text = name;
    self.detailTextLabel.text = size;
}

@end

// ========== Artifact 列表 VC ==========
@interface GHAArtifactListVC : UITableViewController
@property (nonatomic, strong) NSArray *artifacts;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSURLSessionDownloadTask *currentTask;
- (void)showHistory;
@end

@implementation GHAArtifactListVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Artifacts";
    self.view.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"历史"
                                                                               style:UIBarButtonItemStylePlain
                                                                              target:self
                                                                              action:@selector(showHistory)];

    [self.tableView registerClass:[GHAArtifactCell class] forCellReuseIdentifier:@"cell"];
    self.tableView.rowHeight = 64;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 56, 0, 0);

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.frame = CGRectMake(0, 0, self.view.bounds.size.width, 3);
    self.progressView.hidden = YES;
    self.progressView.trackTintColor = [UIColor colorWithWhite:0.9 alpha:1];
    self.progressView.progressTintColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.95 alpha:1];
    self.tableView.tableHeaderView = self.progressView;

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 30)];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = [UIColor grayColor];
    self.statusLabel.hidden = YES;
}

- (void)close {
    if (self.currentTask) [self.currentTask cancel];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showHistory {
    GHAHistoryVC *vc = [[GHAHistoryVC alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.artifacts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GHAArtifactCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    NSDictionary *art = self.artifacts[indexPath.row];
    NSString *name = art[@"name"];
    NSNumber *size = art[@"size_in_bytes"];
    [cell configureWithName:name size:gh_formatSize(size)];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self downloadArtifactAtIndex:indexPath.row];
}

- (void)showProgress:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressView.hidden = NO;
        self.progressView.progress = 0;
        self.statusLabel.text = text;
        self.statusLabel.hidden = NO;
        [self.view addSubview:self.statusLabel];
        self.statusLabel.frame = CGRectMake(0, 4, self.view.bounds.size.width, 20);
    });
}

- (void)hideProgress {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressView.hidden = YES;
        self.statusLabel.hidden = YES;
        [self.statusLabel removeFromSuperview];
    });
}

- (void)downloadArtifactAtIndex:(NSInteger)index {
    NSDictionary *art = self.artifacts[index];
    NSString *name = art[@"name"];
    NSString *downloadUrl = art[@"archive_download_url"];
    if (!downloadUrl) { gh_alert(@"错误", @"下载链接为空"); return; }

    [self showProgress:@"获取下载链接..."];

    NSMutableURLRequest *headReq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:downloadUrl]];
    [headReq setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
    headReq.HTTPMethod = @"HEAD";

    GHARedirectDelegate *delegate = [[GHARedirectDelegate alloc] init];
    delegate.completion = ^(NSString *s3Url, NSError *err) {
        if (err || !s3Url || s3Url.length == 0) {
            [self hideProgress];
            gh_alert(@"错误", @"无法获取下载链接，可能已过期");
            return;
        }
        [self downloadFromS3:s3Url name:name];
    };

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg delegate:delegate delegateQueue:[NSOperationQueue mainQueue]];
    [[session dataTaskWithRequest:headReq] resume];
}

- (void)downloadFromS3:(NSString *)s3Url name:(NSString *)name {
    NSURL *url = [NSURL URLWithString:s3Url];
    if (!url) { [self hideProgress]; gh_alert(@"错误", @"链接格式错误"); return; }

    [self showProgress:@"下载中 0%"];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    GHAArtifactListVC * __weak weakSelf = self;
    self.currentTask = [session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        GHAArtifactListVC *strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf hideProgress];
            if (error) { gh_alert(@"下载失败", error.localizedDescription); return; }
            if (!location) { gh_alert(@"错误", @"下载文件为空"); return; }

            NSString *tmpDir = NSTemporaryDirectory();
            NSString *safeName = [name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
            NSString *fileName = [NSString stringWithFormat:@"%@.zip", safeName];
            NSString *destPath = [tmpDir stringByAppendingPathComponent:fileName];

            // 不覆盖：如果存在则加序号
            NSFileManager *fm = [NSFileManager defaultManager];
            NSInteger counter = 1;
            NSString *finalPath = destPath;
            while ([fm fileExistsAtPath:finalPath]) {
                NSString *base = [safeName stringByAppendingFormat:@"_%ld", (long)counter];
                fileName = [NSString stringWithFormat:@"%@.zip", base];
                finalPath = [tmpDir stringByAppendingPathComponent:fileName];
                counter++;
            }

            NSError *copyErr = nil;
            [fm copyItemAtPath:location.path toPath:finalPath error:&copyErr];
            destPath = finalPath;
            if (copyErr) { gh_alert(@"错误", @"保存文件失败"); return; }

            NSURL *fileURL = [NSURL fileURLWithPath:destPath];
            NSString *repo = [NSString stringWithFormat:@"%@/%@", g_currentOwner ?: @"?", g_currentRepo ?: @"?"];
            [GHAHistory addRecord:name repo:repo];

            UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                                   applicationActivities:nil];
            if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                activity.popoverPresentationController.sourceView = strongSelf.view;
                activity.popoverPresentationController.sourceRect = CGRectMake(
                    strongSelf.view.bounds.size.width / 2, strongSelf.view.bounds.size.height / 2, 1, 1);
            }
            [strongSelf presentViewController:activity animated:YES completion:nil];
        });
    }];

    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *t) {
        if (self.currentTask.countOfBytesExpectedToReceive > 0) {
            float p = (float)self.currentTask.countOfBytesReceived / (float)self.currentTask.countOfBytesExpectedToReceive;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.progressView.progress = p;
                self.statusLabel.text = [NSString stringWithFormat:@"下载中 %.0f%%", p * 100];
            });
        }
        if (self.currentTask.state == NSURLSessionTaskStateCompleted) {
            [t invalidate];
        }
    }];
    objc_setAssociatedObject(self.currentTask, &kGHAssocKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [self.currentTask resume];
}

@end

// ========== 自定义悬浮球 ==========
@interface GHAFloatingView : UIView
@property (nonatomic, strong) UILabel *iconLabel;
- (void)startPulse;
- (void)stopPulse;
- (void)handleTap;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)handlePan:(UIPanGestureRecognizer *)pan;
- (void)fetchArtifacts;
@end

@implementation GHAFloatingView

- (instancetype)init {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    self = [super initWithFrame:CGRectMake(screenW - 72, screenH / 2.0 - 32, 64, 64)];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.95 alpha:0.95];
        self.layer.cornerRadius = 32;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 3);
        self.layer.shadowRadius = 6;
        self.layer.shadowOpacity = 0.25;

        self.iconLabel = [[UILabel alloc] initWithFrame:self.bounds];
        self.iconLabel.text = @"📦";
        self.iconLabel.font = [UIFont systemFontOfSize:28];
        self.iconLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:self.iconLabel];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];

        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        [self addGestureRecognizer:longPress];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];

        [self startPulse];
    }
    return self;
}

- (void)startPulse {
    self.alpha = 1.0;
    [UIView animateWithDuration:1.0 delay:0 options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.alpha = 0.6;
    } completion:nil];
}

- (void)stopPulse {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 1.0;
    }];
}

- (void)handleTap {
    [self fetchArtifacts];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        GHASettingsVC *settingsVC = [[GHASettingsVC alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        UIViewController *top = gh_topViewController();
        if (top) [top presentViewController:nav animated:YES completion:nil];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [pan setTranslation:CGPointMake(0, 0) inView:self.superview];

    CGFloat minX = 32, maxX = self.superview.bounds.size.width - 32;
    CGFloat minY = 64, maxY = self.superview.bounds.size.height - 64;
    CGPoint center = self.center;
    center.x = MAX(minX, MIN(maxX, center.x));
    center.y = MAX(minY, MIN(maxY, center.y));
    self.center = center;
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

            GHAArtifactListVC *listVC = [[GHAArtifactListVC alloc] init];
            listVC.artifacts = artifacts;
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:listVC];
            nav.modalPresentationStyle = UIModalPresentationFormSheet;
            UIViewController *top = gh_topViewController();
            if (top) [top presentViewController:nav animated:YES completion:nil];
        });
    }];
    [task resume];
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

static void gh_addFloatingView(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_floatingView) return;
        g_floatingView = [[GHAFloatingView alloc] init];
        UIWindow *window = gh_getKeyWindow();
        if (window) [window addSubview:g_floatingView];
    });
}

__attribute__((constructor))
static void gh_init(void) {
    gh_log("INIT", "GitHub Actions Artifact Downloader v3.3");
    gh_hookSessionClass(NSClassFromString(@"NSURLSession"));
    gh_hookSessionClass(NSClassFromString(@"__NSCFURLSession"));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ gh_addFloatingView(); });
}
