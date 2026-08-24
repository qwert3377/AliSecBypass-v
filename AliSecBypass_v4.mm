//
// GitHub Actions Artifact Downloader v3.6.14
// 修复日志过滤：按步骤分组，只提取失败步骤（红色）的日志
//

#import <UIKit/UIKit.h>
#import <objc/runtime

static NSString *g_currentToken = nil;
static NSString *g_currentOwner = nil;
static NSString *g_currentRepo = nil;
static NSString *g_currentRunId = nil;
static UIView *g_floatingView = nil;
static UIView *g_hudView = nil;
static const char kGHAssocKey = 0;

// ========== 文件日志 ==========
static void gh_log(const char *tag, const char *msg) {
    NSString *docs = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSString *logPath = [docs stringByAppendingPathComponent:@"GHAD_log.txt"];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@][%s] %s\n", [df stringFromDate:[NSDate date]], tag, msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [[NSFileManager defaultManager] createDirectoryAtPath:docs withIntermediateDirectories:YES attributes:nil error:nil];
        [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
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

// ========== HUD ==========
static void gh_showHUD(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_hudView) [g_hudView removeFromSuperview];
        UIWindow *window = gh_getKeyWindow();
        if (!window) return;
        UIView *hud = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 160, 100)];
        hud.center = CGPointMake(window.bounds.size.width / 2, window.bounds.size.height / 2);
        hud.backgroundColor = [UIColor colorWithWhite:0 alpha:0.82];
        hud.layer.cornerRadius = 14;
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        spinner.color = [UIColor whiteColor];
        spinner.center = CGPointMake(80, 40);
        [hud addSubview:spinner];
        [spinner startAnimating];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 65, 140, 25)];
        label.text = text;
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont systemFontOfSize:14];
        [hud addSubview:label];
        [window addSubview:hud];
        g_hudView = hud;
    });
}

static void gh_hideHUD(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_hudView) {
            [g_hudView removeFromSuperview];
            g_hudView = nil;
        }
    });
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

// ========== 读取请求体 ==========
static NSData *gh_readBody(NSURLRequest *request) {
    NSData *body = request.HTTPBody;
    if (body && body.length > 0) return body;
    NSInputStream *stream = request.HTTPBodyStream;
    if (stream) {
        [stream open];
        NSMutableData *data = [NSMutableData data];
        uint8_t buffer[4096];
        while ([stream hasBytesAvailable]) {
            NSInteger read = [stream read:buffer maxLength:sizeof(buffer)];
            if (read > 0) [data appendBytes:buffer length:read];
            else if (read < 0) break;
        }
        [stream close];
        return data.length > 0 ? data : nil;
    }
    return nil;
}

// ========== 解析 URL ==========
static void gh_parseWorkflowRunUrl(NSString *urlStr) {
    if (!urlStr || urlStr.length == 0) return;
    NSString *cleanUrl = [urlStr componentsSeparatedByString:@"?"][0];
    cleanUrl = [cleanUrl componentsSeparatedByString:@"#"][0];
    NSArray *parts = [cleanUrl componentsSeparatedByString:@"/"];
    if (parts.count >= 8) {
        g_currentOwner = parts[3];
        g_currentRepo = parts[4];
        for (NSUInteger i = 5; i < parts.count; i++) {
            if ([parts[i] isEqualToString:@"runs"] && (i + 1) < parts.count) {
                g_currentRunId = parts[i + 1];
                gh_log("PARSE", [[NSString stringWithFormat:@"URL: owner=%@ repo=%@ runId=%@", g_currentOwner, g_currentRepo, g_currentRunId] UTF8String]);
                break;
            }
        }
    }
}

static void gh_parseRestApiUrl(NSString *urlString) {
    if (!urlString || urlString.length == 0) return;
    if (![urlString containsString:@"api.github.com"]) return;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"/repos/([^/]+)/([^/]+)/actions/runs/(\\d+)" options:0 error:nil];
    NSArray *matches = [regex matchesInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    if (matches.count > 0) {
        NSTextCheckingResult *match = matches[0];
        NSString *owner = [urlString substringWithRange:[match rangeAtIndex:1]];
        NSString *repo = [urlString substringWithRange:[match rangeAtIndex:2]];
        NSString *runId = [urlString substringWithRange:[match rangeAtIndex:3]];
        if (owner.length > 0 && repo.length > 0 && runId.length > 0) {
            g_currentOwner = owner;
            g_currentRepo = repo;
            g_currentRunId = runId;
            gh_log("REST", [[NSString stringWithFormat:@"REST API: %@/%@ runId=%@", owner, repo, runId] UTF8String]);
        }
    }
}

static void gh_parseGraphQLBody(NSData *body) {
    if (!body || body.length == 0) return;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    if (!json || ![json isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *vars = json[@"variables"];
    if (!vars) return;

    NSString *opName = json[@"operationName"] ?: @"";
    NSString *owner = nil;
    NSString *name = nil;

    owner = vars[@"owner"];
    name = vars[@"name"];
    if (owner && name && owner.length > 0 && name.length > 0) {
        g_currentOwner = owner;
        g_currentRepo = name;
        gh_log("REPO", [[NSString stringWithFormat:@"direct: %@/%@", owner, name] UTF8String]);
    }

    NSDictionary *repo = vars[@"repo"];
    if (repo && [repo isKindOfClass:[NSDictionary class]]) {
        owner = repo[@"owner"];
        name = repo[@"name"];
        if (owner && name && owner.length > 0 && name.length > 0) {
            g_currentOwner = owner;
            g_currentRepo = name;
            gh_log("REPO", [[NSString stringWithFormat:@"repoObj: %@/%@", owner, name] UTF8String]);
        }
    }

    BOOL isRunPage = [opName isEqualToString:@"WorkflowRun"] ||
                     [opName isEqualToString:@"WorkflowRunDetails"] ||
                     [opName isEqualToString:@"WorkflowRunJobs"] ||
                     [opName isEqualToString:@"WorkflowRunLogs"] ||
                     [opName isEqualToString:@"WorkflowRunArtifacts"] ||
                     [opName isEqualToString:@"CheckRun"];

    if (isRunPage) {
        NSString *runUrl = vars[@"url"];
        if (runUrl) {
            gh_parseWorkflowRunUrl(runUrl);
        } else {
            NSString *runId = vars[@"id"];
            if (runId && runId.length > 0) {
                NSRegularExpression *numRegex = [NSRegularExpression regularExpressionWithPattern:@"\\d+" options:0 error:nil];
                NSTextCheckingResult *numMatch = [numRegex firstMatchInString:runId options:0 range:NSMakeRange(0, runId.length)];
                if (numMatch) {
                    g_currentRunId = [runId substringWithRange:numMatch.range];
                    gh_log("RUN", [[NSString stringWithFormat:@"from id=%@", g_currentRunId] UTF8String]);
                }
            }
        }
    }
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
+ (void)addRecord:(NSString *)name repo:(NSString *)repo filePath:(NSString *)filePath buildNumber:(NSString *)buildNumber;
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
+ (void)addRecord:(NSString *)name repo:(NSString *)repo filePath:(NSString *)filePath buildNumber:(NSString *)buildNumber {
    NSMutableArray *arr = [self loadRecords];
    NSString *displayName = name ?: @"";
    if (buildNumber && buildNumber.length > 0) {
        displayName = [NSString stringWithFormat:@"%@ (#%@)", name, buildNumber];
    }
    NSDictionary *rec = @{
        @"name": displayName,
        @"repo": repo ?: @"",
        @"filePath": filePath ?: @"",
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空历史"
                                                                   message:@"确定要清空所有下载记录吗？"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSArray *records = [GHAHistory records];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSDictionary *rec in records) {
            NSString *path = rec[@"filePath"];
            if (path && path.length > 0) [fm removeItemAtPath:path error:nil];
        }
        [GHAHistory clear];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
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
    NSString *path = rec[@"filePath"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!path || path.length == 0 || ![fm fileExistsAtPath:path]) {
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
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSMutableArray *records = [GHAHistory loadRecords];
        if (indexPath.row < records.count) {
            NSDictionary *rec = records[indexPath.row];
            NSString *path = rec[@"filePath"];
            if (path && path.length > 0) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
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
    UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 40)];
    versionLabel.text = @"GitHub Artifact Downloader v3.6.14";
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.font = [UIFont systemFontOfSize:12];
    versionLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    self.tableView.tableFooterView = versionLabel;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }
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
- (void)toggleUnzip:(UISwitch *)sender { [GHASettings setAutoUnzip:sender.isOn]; }
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
@property (nonatomic, copy) NSString *buildNumber;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSURLSessionDownloadTask *currentTask;
- (void)showHistory;
@end

@implementation GHAArtifactListVC
- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.buildNumber && self.buildNumber.length > 0) {
        self.title = [NSString stringWithFormat:@"Artifacts (#%@)", self.buildNumber];
    } else {
        self.title = @"Artifacts";
    }
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
- (NSString *)localFilePathForArtifactName:(NSString *)name {
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *safeName = [name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *buildNum = self.buildNumber;
    if (!buildNum || buildNum.length == 0) buildNum = @"unknown";
    NSString *buildSuffix = [NSString stringWithFormat:@"_#%@", buildNum];
    NSString *fileName = [NSString stringWithFormat:@"%@%@.zip", safeName, buildSuffix];
    return [tmpDir stringByAppendingPathComponent:fileName];
}
- (void)downloadArtifactAtIndex:(NSInteger)index {
    NSDictionary *art = self.artifacts[index];
    NSString *name = art[@"name"];
    NSString *downloadUrl = art[@"archive_download_url"];
    if (!downloadUrl) { gh_alert(@"错误", @"下载链接为空"); return; }
    NSString *localPath = [self localFilePathForArtifactName:name];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:localPath]) {
        NSURL *fileURL = [NSURL fileURLWithPath:localPath];
        UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                               applicationActivities:nil];
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];
            activity.popoverPresentationController.sourceView = cell;
            activity.popoverPresentationController.sourceRect = cell.bounds;
        }
        [self presentViewController:activity animated:YES completion:nil];
        return;
    }
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
            NSString *buildNum = strongSelf.buildNumber;
            if (!buildNum || buildNum.length == 0) buildNum = @"unknown";
            NSString *buildSuffix = [NSString stringWithFormat:@"_#%@", buildNum];
            NSString *fileName = [NSString stringWithFormat:@"%@%@.zip", safeName, buildSuffix];
            NSString *destPath = [tmpDir stringByAppendingPathComponent:fileName];
            NSFileManager *fm = [NSFileManager defaultManager];
            NSInteger counter = 1;
            NSString *finalPath = destPath;
            while ([fm fileExistsAtPath:finalPath]) {
                NSString *base = [safeName stringByAppendingFormat:@"%@_%ld", buildSuffix, (long)counter];
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
            [GHAHistory addRecord:name repo:repo filePath:destPath buildNumber:strongSelf.buildNumber];
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
        if (self.currentTask.state == NSURLSessionTaskStateCompleted) [t invalidate];
    }];
    objc_setAssociatedObject(self.currentTask, &kGHAssocKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self.currentTask resume];
}
@end

// ========== 日志步骤模型 ==========
@interface GHALogStep : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<NSString *> *lines;
@property (nonatomic, assign) BOOL hasError;
@end

@implementation GHALogStep
- (instancetype)init {
    self = [super init];
    if (self) {
        _lines = [NSMutableArray array];
        _hasError = NO;
    }
    return self;
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
- (void)fetchArtifactsForRunId:(NSString *)runId runNumber:(NSString *)runNumber;
- (void)fetchLatestRun;
- (void)fetchRunLogs:(NSString *)runId;
@end

@implementation GHAFloatingView

- (instancetype)init {
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    self = [super initWithFrame:CGRectMake(screenW - 60, screenH / 2.0 - 24, 48, 48)];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.95 alpha:0.95];
        self.layer.cornerRadius = 24;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 3);
        self.layer.shadowRadius = 6;
        self.layer.shadowOpacity = 0.25;
        self.iconLabel = [[UILabel alloc] initWithFrame:self.bounds];
        self.iconLabel.text = @"📦";
        self.iconLabel.font = [UIFont systemFontOfSize:22];
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
    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 1.0; }];
}

- (void)handleTap {
    if (!g_currentToken || g_currentToken.length == 0) {
        gh_alert(@"错误", @"未获取到 GitHub Token，请先登录 GitHub");
        return;
    }
    if (!g_currentOwner || !g_currentRepo) {
        gh_alert(@"错误", @"未检测到仓库信息，请先进入某个仓库页面");
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Artifact Downloader"
                                                                   message:[NSString stringWithFormat:@"仓库: %@/%@", g_currentOwner, g_currentRepo]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"下载最新 Run"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        gh_log("MENU", "User chose: Latest Run");
        [self fetchLatestRun];
    }]];

    NSString *currentTitle = (g_currentRunId && g_currentRunId.length > 0)
        ? @"下载当前 Run"
        : @"下载当前 Run (未检测到)";
    UIAlertAction *currentAction = [UIAlertAction actionWithTitle:currentTitle
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *action) {
        if (g_currentRunId && g_currentRunId.length > 0) {
            gh_log("MENU", "User chose: Current Run");
            [self fetchArtifactsForRunId:g_currentRunId runNumber:nil];
        } else {
            gh_alert(@"提示", @"未检测到当前 Run 页面。\n\n请先进入某个 Workflow Run 详情页面，或选择「下载最新 Run」");
        }
    }];
    [alert addAction:currentAction];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self;
        alert.popoverPresentationController.sourceRect = self.bounds;
    }

    UIViewController *top = gh_topViewController();
    if (top) [top presentViewController:alert animated:YES completion:nil];
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

- (void)fetchLatestRun {
    gh_showHUD(@"查询最新Run...");

    NSString *runsUrl = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/actions/runs?per_page=1",
                         g_currentOwner, g_currentRepo];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:runsUrl]];
    [req setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    [req setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                gh_hideHUD();
                gh_alert(@"请求失败", error.localizedDescription);
                return;
            }
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (httpResp.statusCode != 200) {
                gh_hideHUD();
                gh_alert(@"请求失败", [NSString stringWithFormat:@"HTTP %ld", (long)httpResp.statusCode]);
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (!json || ![json isKindOfClass:[NSDictionary class]]) {
                gh_hideHUD();
                gh_alert(@"错误", @"解析响应失败");
                return;
            }
            NSArray *runs = json[@"workflow_runs"];
            if (!runs || runs.count == 0) {
                gh_hideHUD();
                gh_alert(@"提示", @"该仓库没有 Workflow Run");
                return;
            }

            NSDictionary *latestRun = runs[0];
            NSString *runId = [NSString stringWithFormat:@"%@", latestRun[@"id"] ?: @""];
            NSString *status = latestRun[@"status"] ?: @"";
            NSString *conclusion = latestRun[@"conclusion"] ?: @"";
            NSString *runNumberStr = [NSString stringWithFormat:@"%@", latestRun[@"run_number"] ?: @""];

            gh_log("RUN", [[NSString stringWithFormat:@"latest id=%@ status=%@ conclusion=%@ number=%@", runId, status, conclusion, runNumberStr] UTF8String]);

            if (![status isEqualToString:@"completed"]) {
                gh_hideHUD();
                NSString *statusText = [status isEqualToString:@"in_progress"] ? @"运行中" : status;
                NSString *msg = [NSString stringWithFormat:@"最新 Run #%@ 状态: %@\n\nArtifact 尚未生成，请等待运行完成后再试", runNumberStr, statusText];
                gh_alert(@"运行中", msg);
                return;
            }

            if (![conclusion isEqualToString:@"success"]) {
                gh_hideHUD();
                NSString *msg = [NSString stringWithFormat:@"最新 Run #%@ 结果: %@\n\n运行未成功，没有 Artifact 可下载", runNumberStr, conclusion];
                UIAlertController *failAlert = [UIAlertController alertControllerWithTitle:@"运行失败"
                                                                                       message:msg
                                                                                preferredStyle:UIAlertControllerStyleAlert];
                [failAlert addAction:[UIAlertAction actionWithTitle:@"查看日志"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction *action) {
                    [self fetchRunLogs:runId];
                }]];
                [failAlert addAction:[UIAlertAction actionWithTitle:@"确定"
                                                               style:UIAlertActionStyleCancel
                                                             handler:nil]];
                UIViewController *top = gh_topViewController();
                if (top) [top presentViewController:failAlert animated:YES completion:nil];
                return;
            }
            [self fetchArtifactsForRunId:runId runNumber:runNumberStr];
        });
    }];
    [task resume];
}

- (void)fetchRunDetailsThenArtifacts:(NSString *)runId {
    gh_showHUD(@"查询Run信息...");
    NSString *urlStr = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/actions/runs/%@",
                        g_currentOwner, g_currentRepo, runId];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    [req setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    [req setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                gh_hideHUD();
                gh_alert(@"请求失败", error.localizedDescription);
                return;
            }
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (httpResp.statusCode != 200) {
                gh_hideHUD();
                gh_alert(@"请求失败", [NSString stringWithFormat:@"HTTP %ld", (long)httpResp.statusCode]);
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (!json || ![json isKindOfClass:[NSDictionary class]]) {
                gh_hideHUD();
                gh_alert(@"错误", @"解析响应失败");
                return;
            }
            NSString *runNumberStr = [NSString stringWithFormat:@"%@", json[@"run_number"] ?: @""];
            gh_log("DETAIL", [[NSString stringWithFormat:@"runId=%@ run_number=%@", runId, runNumberStr] UTF8String]);
            [self fetchArtifactsForRunId:runId runNumber:runNumberStr];
        });
    }];
    [task resume];
}

- (void)fetchArtifactsForRunId:(NSString *)runId runNumber:(NSString *)runNumber {
    if (!runNumber || runNumber.length == 0) {
        [self fetchRunDetailsThenArtifacts:runId];
        return;
    }
    NSString *urlStr = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/actions/runs/%@/artifacts",
                        g_currentOwner, g_currentRepo, runId];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    [req setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    [req setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            gh_hideHUD();
            if (error) {
                gh_alert(@"请求失败", error.localizedDescription);
                return;
            }
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (httpResp.statusCode != 200) {
                gh_alert(@"请求失败", [NSString stringWithFormat:@"HTTP %ld", (long)httpResp.statusCode]);
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (!json || ![json isKindOfClass:[NSDictionary class]]) {
                gh_alert(@"错误", @"解析响应失败");
                return;
            }
            NSNumber *totalCount = json[@"total_count"];
            NSArray *artifacts = json[@"artifacts"];
            gh_log("API", [[NSString stringWithFormat:@"total_count=%@ artifacts=%lu", totalCount, (unsigned long)artifacts.count] UTF8String]);
            if (!artifacts || artifacts.count == 0) {
                gh_alert(@"提示", @"该 Run 成功但未生成 Artifact");
                return;
            }
            GHAArtifactListVC *listVC = [[GHAArtifactListVC alloc] init];
            listVC.artifacts = artifacts;
            listVC.buildNumber = runNumber ?: runId;
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:listVC];
            nav.modalPresentationStyle = UIModalPresentationFormSheet;
            UIViewController *top = gh_topViewController();
            if (top) [top presentViewController:nav animated:YES completion:nil];
        });
    }];
    [task resume];
}

// ========== 日志解析辅助：按步骤分组，只保留失败步骤 ==========
+ (NSString *)filterErrorStepsFromLog:(NSString *)logText jobName:(NSString *)jobName {
    if (!logText || logText.length == 0) return nil;

    NSArray *allLines = [logText componentsSeparatedByString:@"\n"];
    NSMutableArray<GHALogStep *> *steps = [NSMutableArray array];
    GHALogStep *currentStep = nil;

    // 匹配时间戳前缀: 2024-01-01T00:00:00.1234567Z
    NSRegularExpression *tsRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d+Z\\s*" options:0 error:nil];

    for (NSString *rawLine in allLines) {
        NSString *line = rawLine;
        NSTextCheckingResult *tsMatch = [tsRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (tsMatch) {
            line = [line substringFromIndex:tsMatch.range.length];
        }

        if ([line hasPrefix:@"##[group]"]) {
            currentStep = [[GHALogStep alloc] init];
            currentStep.name = [line substringFromIndex:@"##[group]".length];
            [steps addObject:currentStep];
        } else if ([line hasPrefix:@"##[endgroup]"]) {
            currentStep = nil;
        } else if ([line hasPrefix:@"##[error]"]) {
            if (currentStep) {
                currentStep.hasError = YES;
                [currentStep.lines addObject:line];
            }
        } else if (currentStep) {
            [currentStep.lines addObject:line];
            NSString *lower = [line lowercaseString];
            if ([lower containsString:@"error:"] ||
                [lower containsString:@"fatal:"] ||
                [lower containsString:@"failed"] ||
                [lower containsString:@"make:***"] ||
                [lower containsString:@"undefined reference"] ||
                [lower containsString:@"redefinition"] ||
                [lower containsString:@"no such file"] ||
                [lower containsString:@"permission denied"] ||
                [lower containsString:@"command not found"] ||
                [lower containsString:@"exit code"]) {
                currentStep.hasError = YES;
            }
        }
    }

    NSMutableArray<NSString *> *errorStepsText = [NSMutableArray array];
    for (GHALogStep *step in steps) {
        if (step.hasError && step.lines.count > 0) {
            NSString *stepText = [NSString stringWithFormat:@"▶ %@\n%@", step.name, [step.lines componentsJoinedByString:@"\n"]];
            [errorStepsText addObject:stepText];
        }
    }

    if (errorStepsText.count == 0) return nil;

    NSString *header = [NSString stringWithFormat:@"📦 Job: %@\n共 %lu 个失败步骤", jobName, (unsigned long)errorStepsText.count];
    return [NSString stringWithFormat:@"%@\n\n%@", header, [errorStepsText componentsJoinedByString:@"\n\n──────────────\n\n"]];
}

- (void)showLogAlertWithText:(NSString *)text {
    if (!text || text.length == 0) {
        gh_alert(@"提示", @"未找到错误日志");
        return;
    }
    NSString *preview = text.length > 3000 ? [text substringToIndex:3000] : text;
    UIAlertController *logAlert = [UIAlertController alertControllerWithTitle:@"失败步骤日志"
                                                                      message:preview
                                                               preferredStyle:UIAlertControllerStyleAlert];
    [logAlert addAction:[UIAlertAction actionWithTitle:@"复制全部"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
        [[UIPasteboard generalPasteboard] setString:text];
    }]];
    [logAlert addAction:[UIAlertAction actionWithTitle:@"关闭"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    UIViewController *top = gh_topViewController();
    if (top) [top presentViewController:logAlert animated:YES completion:nil];
}

- (void)fetchRunLogs:(NSString *)runId {
    gh_showHUD(@"获取日志...");
    NSString *jobsUrl = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/actions/runs/%@/jobs",
                         g_currentOwner, g_currentRepo, runId];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:jobsUrl]];
    [req setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    GHAFloatingView * __weak weakSelf = self;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            GHAFloatingView *strongSelf = weakSelf;
            if (!strongSelf) { gh_hideHUD(); return; }
            if (error) {
                gh_hideHUD();
                gh_alert(@"错误", @"无法获取日志");
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *jobs = json[@"jobs"];
            if (!jobs || jobs.count == 0) {
                gh_hideHUD();
                gh_alert(@"错误", @"未找到 job 日志");
                return;
            }
            [strongSelf fetchAllJobLogs:jobs];
        });
    }];
    [task resume];
}

- (void)fetchAllJobLogs:(NSArray *)jobs {
    NSMutableArray<NSString *> *allErrorLogs = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();

    for (NSDictionary *job in jobs) {
        NSNumber *jobId = job[@"id"];
        NSString *jobName = job[@"name"] ?: @"Unknown Job";
        dispatch_group_enter(group);
        NSString *logUrl = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/actions/jobs/%@/logs",
                            g_currentOwner, g_currentRepo, jobId];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:logUrl]];
        [req setValue:g_currentToken forHTTPHeaderField:@"Authorization"];
        [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
        NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (!error && data) {
                NSString *logText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (logText) {
                    NSString *filtered = [GHAFloatingView filterErrorStepsFromLog:logText jobName:jobName];
                    if (filtered.length > 0) {
                        @synchronized(allErrorLogs) {
                            [allErrorLogs addObject:filtered];
                        }
                    }
                }
            }
            dispatch_group_leave(group);
        }];
        [task resume];
    }

    GHAFloatingView * __weak weakSelf = self;
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        gh_hideHUD();
        GHAFloatingView *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (allErrorLogs.count == 0) {
            gh_alert(@"提示", @"未找到失败步骤的日志，可能日志已过期或格式不兼容");
            return;
        }
        NSString *finalText = [allErrorLogs componentsJoinedByString:@"\n\n================\n\n"];
        [strongSelf showLogAlertWithText:finalText];
    });
}
@end

// ========== Hook NSURLSession ==========
static NSURLSessionDataTask *(*orig_dataTaskWithRequest)(id self, SEL _cmd, NSURLRequest *request);
static NSURLSessionDataTask *(*orig_dataTaskWithRequestCompletion)(id self, SEL _cmd, NSURLRequest *request, id completionHandler);

static void gh_processRequest(NSURLRequest *request) {
    NSURL *url = request.URL;
    if (!url) return;
    NSString *urlString = url.absoluteString;
    if (!urlString || ![urlString containsString:@"github.com"]) return;

    NSString *auth = [request valueForHTTPHeaderField:@"Authorization"];
    if (auth && auth.length > 0) {
        g_currentToken = auth;
        gh_log("TOKEN", "Captured");
    }

    gh_parseRestApiUrl(urlString);

    NSData *body = gh_readBody(request);
    if (body && body.length > 0) {
        gh_parseGraphQLBody(body);
    }
}

static NSURLSessionDataTask *hooked_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request) {
    gh_processRequest(request);
    return orig_dataTaskWithRequest(self, _cmd, request);
}

static NSURLSessionDataTask *hooked_dataTaskWithRequestCompletion(id self, SEL _cmd, NSURLRequest *request, id completionHandler) {
    gh_processRequest(request);
    return orig_dataTaskWithRequestCompletion(self, _cmd, request, completionHandler);
}

static void gh_hookSessionClass(Class cls) {
    if (!cls) return;
    Method m1 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:));
    if (m1) {
        orig_dataTaskWithRequest = (NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *))method_getImplementation(m1);
        method_setImplementation(m1, (IMP)hooked_dataTaskWithRequest);
        gh_log("HOOK", "dataTaskWithRequest:");
    }
    Method m2 = class_getInstanceMethod(cls, @selector(dataTaskWithRequest:completionHandler:));
    if (m2) {
        orig_dataTaskWithRequestCompletion = (NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, id))method_getImplementation(m2);
        method_setImplementation(m2, (IMP)hooked_dataTaskWithRequestCompletion);
        gh_log("HOOK", "dataTaskWithRequest:completionHandler:");
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
    gh_log("INIT", "GitHub Actions Artifact Downloader v3.6.14");
    gh_hookSessionClass(NSClassFromString(@"NSURLSession"));
    gh_hookSessionClass(NSClassFromString(@"__NSCFURLSession"));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ gh_addFloatingView(); });
}
