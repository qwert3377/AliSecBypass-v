//
//  ElyndorTV VIP Tweak v4.8 — UILabel Full Trace + Member Context Replace
//  Logs ALL setText: calls, replaces "1"/"0" with "8" in member-related views
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#pragma mark - Logger

static NSString *gLogPath = nil;

static NSString *getLogPath(void) {
    if (gLogPath) return gLogPath;
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (docs.count > 0) {
        gLogPath = [[docs[0] stringByAppendingPathComponent:@"vip_v48.log"] copy];
    } else {
        gLogPath = @"/tmp/vip_v48.log";
    }
    return gLogPath;
}

static void vipLog(NSString *fmt, ...) {
    @try {
        va_list args;
        va_start(args, fmt);
        NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
        va_end(args);
        NSString *line = [NSString stringWithFormat:@"%@ [VIP] %@\n",
            [[NSDate date] descriptionWithLocale:nil], msg];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSString *path = getLogPath();
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:data];
            [fh closeFile];
        } else {
            [data writeToFile:path atomically:YES];
        }
    } @catch (NSException *e) {}
}

#pragma mark - Check if view is in member-related hierarchy

static BOOL isMemberViewHierarchy(UIView *view) {
    if (!view) return NO;
    UIView *current = view;
    int depth = 0;
    while (current && depth < 20) {
        NSString *clsName = NSStringFromClass([current class]);
        NSString *lower = [clsName lowercaseString];
        if ([lower containsString:@"member"] || [lower containsString:@"vip"] ||
            [lower containsString:@"profile"] || [lower containsString:@"account"] ||
            [lower containsString:@"subscription"] || [lower containsString:@"premium"]) {
            return YES;
        }
        current = [current superview];
        depth++;
    }
    return NO;
}

#pragma mark - UILabel setText: Hook

typedef void (*LabelSetTextImp_t)(id, SEL, NSString *);
static LabelSetTextImp_t orig_labelSetText = NULL;

static void new_labelSetText(id self, SEL sel, NSString *text) {
    @try {
        if (text && [text length] > 0) {
            // Log all numeric texts
            NSScanner *scanner = [NSScanner scannerWithString:text];
            int num;
            BOOL isNumber = [scanner scanInt:&num] && [scanner isAtEnd];

            if (isNumber) {
                // Check if this label is in member view hierarchy
                if ([self isKindOfClass:[UIView class]]) {
                    UIView *v = (UIView *)self;
                    BOOL inMember = isMemberViewHierarchy(v);
                    vipLog(@"[LABEL] setText:'%@' class=%@ memberCtx=%d", text, NSStringFromClass([v class]), inMember);

                    // If it's "0" or "1" and in member context, replace with "8"
                    if (inMember && (num == 0 || num == 1)) {
                        vipLog(@"[LABEL-REPLACE] '%@' -> '8' in member view", text);
                        orig_labelSetText(self, sel, @"8");
                        return;
                    }
                }
            }

            // Replace Chinese VIP status text
            if ([text containsString:@"立即开通"] || [text containsString:@"尚未开通"] ||
                [text containsString:@"未开通"] || [text containsString:@"非会员"]) {
                orig_labelSetText(self, sel, @"VIP会员已开通");
                return;
            }
        }
    } @catch (NSException *e) {}
    orig_labelSetText(self, sel, text);
}

static void hookUILabel(void) {
    Class cls = objc_getClass("UILabel");
    if (!cls) return;
    SEL sel = @selector(setText:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    orig_labelSetText = (LabelSetTextImp_t)method_getImplementation(m);
    method_setImplementation(m, (IMP)new_labelSetText);
    vipLog(@"[HOOK] UILabel setText:");
}

#pragma mark - UIImage imageNamed: Hook

typedef id (*ImgNamedImp_t)(Class, SEL, NSString *);
static ImgNamedImp_t orig_imgNamed = NULL;

static id new_imgNamed(Class self, SEL sel, NSString *name) {
    @try {
        if (name) {
            NSString *lower = [name lowercaseString];
            if ([lower containsString:@"vip"] || [lower containsString:@"member"] ||
                [lower containsString:@"tier"] || [lower containsString:@"level"] ||
                [lower containsString:@"grade"] || [lower containsString:@"badge"]) {
                vipLog(@"[IMAGE] imageNamed:'%@'", name);
                // Try to replace _1 with _8 in image name
                if ([name hasSuffix:@"_1"] || [name hasSuffix:@"1"]) {
                    NSString *newName = [name stringByReplacingOccurrencesOfString:@"_1" withString:@"_8"];
                    if (![newName isEqualToString:name]) {
                        vipLog(@"[IMAGE-REPLACE] '%@' -> '%@'", name, newName);
                        return orig_imgNamed(self, sel, newName);
                    }
                }
            }
        }
    } @catch (NSException *e) {}
    return orig_imgNamed(self, sel, name);
}

static void hookUIImage(void) {
    Class cls = objc_getClass("UIImage");
    if (!cls) return;
    SEL sel = @selector(imageNamed:);
    Method m = class_getClassMethod(cls, sel);
    if (!m) return;
    orig_imgNamed = (ImgNamedImp_t)method_getImplementation(m);
    method_setImplementation(m, (IMP)new_imgNamed);
    vipLog(@"[HOOK] UIImage imageNamed:");
}

#pragma mark - NSUserDefaults (minimal, from v4.3)

typedef BOOL (*BoolImp_t)(id, SEL, NSString *);
typedef NSInteger (*IntImp_t)(id, SEL, NSString *);
static BoolImp_t orig_boolForKey = NULL;
static IntImp_t orig_integerForKey = NULL;

static BOOL new_boolForKey(id self, SEL sel, NSString *key) {
    const char *k = [key UTF8String];
    if (strcasecmp(k, "kvipStatusStorageKey") == 0 || strcasecmp(k, "kvipstatusstoragekey") == 0) return YES;
    return orig_boolForKey(self, sel, key);
}

static NSInteger new_integerForKey(id self, SEL sel, NSString *key) {
    const char *k = [key UTF8String];
    NSInteger val = orig_integerForKey(self, sel, key);
    if (val >= 0 && val <= 7) {
        NSString *lower = [key lowercaseString];
        if ([lower containsString:@"vip"] || [lower containsString:@"member"] ||
            [lower containsString:@"tier"] || [lower containsString:@"level"] ||
            [lower containsString:@"grade"]) {
            vipLog(@"[UD] integerForKey:'%@' %ld->8", key, (long)val);
            return 8;
        }
    }
    return val;
}

static void hookUserDefaults(void) {
    Class cls = objc_getClass("NSUserDefaults");
    if (!cls) return;
    Method m1 = class_getInstanceMethod(cls, @selector(boolForKey:));
    if (m1) { orig_boolForKey = (BoolImp_t)method_getImplementation(m1); method_setImplementation(m1, (IMP)new_boolForKey); }
    Method m2 = class_getInstanceMethod(cls, @selector(integerForKey:));
    if (m2) { orig_integerForKey = (IntImp_t)method_getImplementation(m2); method_setImplementation(m2, (IMP)new_integerForKey); }
    vipLog(@"[HOOK] NSUserDefaults");
}

#pragma mark - Entry

__attribute__((constructor))
static void init(void) {
    vipLog(@"========================================");
    vipLog(@"ElyndorTV VIP Tweak v4.8");
    vipLog(@"Build: 2026-08-26");
    vipLog(@"Strategy: UILabel trace + member context replace");
    vipLog(@"========================================");

    hookUILabel();
    hookUIImage();
    hookUserDefaults();

    vipLog(@"[INIT] All hooks installed");
}
