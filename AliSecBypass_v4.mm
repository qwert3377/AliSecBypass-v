//
//  ElyndorTV KeyFinder — Logs ALL UserDefaults reads
//  Find the actual key storing tier/level
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *gLogPath = nil;

static NSString *getLogPath(void) {
    if (gLogPath) return gLogPath;
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (docs.count > 0) {
        gLogPath = [[docs[0] stringByAppendingPathComponent:@"keyfinder.log"] copy];
    } else {
        gLogPath = @"/tmp/keyfinder.log";
    }
    return gLogPath;
}

static void kfLog(NSString *fmt, ...) {
    @try {
        va_list args;
        va_start(args, fmt);
        NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
        va_end(args);
        NSString *line = [NSString stringWithFormat:@"%@ %@\n",
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

// ===== Hook ALL NSUserDefaults accessors, log EVERY key =====

typedef id (*ObjImp)(id, SEL, NSString *);
typedef NSInteger (*IntImp)(id, SEL, NSString *);
typedef BOOL (*BoolImp)(id, SEL, NSString *);
typedef NSString* (*StrImp)(id, SEL, NSString *);
typedef id (*DataImp)(id, SEL, NSString *);
typedef id (*DictImp)(id, SEL, NSString *);
typedef float (*FloatImp)(id, SEL, NSString *);
typedef double (*DoubleImp)(id, SEL, NSString *);

static ObjImp orig_obj = NULL;
static IntImp orig_int = NULL;
static BoolImp orig_bool = NULL;
static StrImp orig_str = NULL;
static DataImp orig_data = NULL;
static DictImp orig_dict = NULL;
static FloatImp orig_float = NULL;
static DoubleImp orig_double = NULL;

static id new_obj(id self, SEL sel, NSString *key) {
    id val = orig_obj(self, sel, key);
    NSString *vstr = val ? [[val description] substringToIndex:MIN(200, [[val description] length])] : @"nil";
    kfLog(@"[ALL] objectForKey:'%@' -> %@", key, vstr);
    return val;
}

static NSInteger new_int(id self, SEL sel, NSString *key) {
    NSInteger val = orig_int(self, sel, key);
    kfLog(@"[ALL] integerForKey:'%@' -> %ld", key, (long)val);
    return val;
}

static BOOL new_bool(id self, SEL sel, NSString *key) {
    BOOL val = orig_bool(self, sel, key);
    kfLog(@"[ALL] boolForKey:'%@' -> %d", key, val);
    return val;
}

static NSString *new_str(id self, SEL sel, NSString *key) {
    NSString *val = orig_str(self, sel, key);
    kfLog(@"[ALL] stringForKey:'%@' -> '%@'", key, val ?: @"nil");
    return val;
}

static id new_data(id self, SEL sel, NSString *key) {
    id val = orig_data(self, sel, key);
    NSString *vstr = val ? [NSString stringWithFormat:@"[NSData %lu bytes]", (unsigned long)[val length]] : @"nil";
    kfLog(@"[ALL] dataForKey:'%@' -> %@", key, vstr);
    return val;
}

static id new_dict(id self, SEL sel, NSString *key) {
    id val = orig_dict(self, sel, key);
    NSString *vstr = val ? [[val description] substringToIndex:MIN(200, [[val description] length])] : @"nil";
    kfLog(@"[ALL] dictionaryForKey:'%@' -> %@", key, vstr);
    return val;
}

static float new_float(id self, SEL sel, NSString *key) {
    float val = orig_float(self, sel, key);
    kfLog(@"[ALL] floatForKey:'%@' -> %f", key, val);
    return val;
}

static double new_double(id self, SEL sel, NSString *key) {
    double val = orig_double(self, sel, key);
    kfLog(@"[ALL] doubleForKey:'%@' -> %f", key, val);
    return val;
}

// ===== Hook NSURLSession to log ALL responses =====

typedef id (*TaskImp)(id, SEL, id, id);
static TaskImp orig_dataTask = NULL;

static id new_dataTask(id self, SEL sel, id arg2, id completion) {
    // Log the URL
    NSString *url = nil;
    if ([arg2 isKindOfClass:[NSURLRequest class]]) {
        url = [[arg2 URL] absoluteString];
    } else if ([arg2 isKindOfClass:[NSURL class]]) {
        url = [arg2 absoluteString];
    }
    if (url) {
        kfLog(@"[NET] URL: %@", url);
    }

    // Wrap completion handler to log response
    if (completion) {
        id origBlock = completion;
        id newBlock = ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data) {
                NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (body) {
                    kfLog(@"[NET] RESP (%lu): %@", (unsigned long)[body length],
                          [body substringToIndex:MIN(2000, [body length])]);
                }
            }
            // Call original
            if ([origBlock isKindOfClass:NSClassFromString(@"NSBlock")]) {
                void (^orig)(NSData*, NSURLResponse*, NSError*) = origBlock;
                orig(data, response, error);
            }
        };
        return orig_dataTask(self, sel, arg2, newBlock);
    }
    return orig_dataTask(self, sel, arg2, completion);
}

// ===== Entry =====

__attribute__((constructor))
static void init(void) {
    kfLog(@"========================================");
    kfLog(@"ElyndorTV KeyFinder v1.0");
    kfLog(@"Build: 2026-08-26");
    kfLog(@"Log: %@", getLogPath());
    kfLog(@"========================================");

    Class UD = objc_getClass("NSUserDefaults");
    if (UD) {
        Method m;
        m = class_getInstanceMethod(UD, @selector(objectForKey:));
        if (m) { orig_obj = (ObjImp)method_getImplementation(m); method_setImplementation(m, (IMP)new_obj); }
        m = class_getInstanceMethod(UD, @selector(integerForKey:));
        if (m) { orig_int = (IntImp)method_getImplementation(m); method_setImplementation(m, (IMP)new_int); }
        m = class_getInstanceMethod(UD, @selector(boolForKey:));
        if (m) { orig_bool = (BoolImp)method_getImplementation(m); method_setImplementation(m, (IMP)new_bool); }
        m = class_getInstanceMethod(UD, @selector(stringForKey:));
        if (m) { orig_str = (StrImp)method_getImplementation(m); method_setImplementation(m, (IMP)new_str); }
        m = class_getInstanceMethod(UD, @selector(dataForKey:));
        if (m) { orig_data = (DataImp)method_getImplementation(m); method_setImplementation(m, (IMP)new_data); }
        m = class_getInstanceMethod(UD, @selector(dictionaryForKey:));
        if (m) { orig_dict = (DictImp)method_getImplementation(m); method_setImplementation(m, (IMP)new_dict); }
        m = class_getInstanceMethod(UD, @selector(floatForKey:));
        if (m) { orig_float = (FloatImp)method_getImplementation(m); method_setImplementation(m, (IMP)new_float); }
        m = class_getInstanceMethod(UD, @selector(doubleForKey:));
        if (m) { orig_double = (DoubleImp)method_getImplementation(m); method_setImplementation(m, (IMP)new_double); }
        kfLog(@"[INIT] NSUserDefaults 8 accessors hooked");
    }

    Class Session = objc_getClass("NSURLSession");
    if (Session) {
        Method m = class_getInstanceMethod(Session, @selector(dataTaskWithRequest:completionHandler:));
        if (m) { orig_dataTask = (TaskImp)method_getImplementation(m); method_setImplementation(m, (IMP)new_dataTask); }
        m = class_getInstanceMethod(Session, @selector(dataTaskWithURL:completionHandler:));
        if (m) { orig_dataTask = (TaskImp)method_getImplementation(m); method_setImplementation(m, (IMP)new_dataTask); }
        kfLog(@"[INIT] NSURLSession hooked");
    }

    kfLog(@"[INIT] KeyFinder active — open member page and check log");
}
