//
//  Kiosker_Premium_Unlock.mm
//  TrollStore Injection Plugin for Kiosker 26.4.2
//  Logs to app Documents directory for debugging
//

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <sys/stat.h>

static id (*orig_init)(id, SEL) = NULL;
static NSString *logPath = nil;

// Write log to file in app Documents directory
static void fileLog(NSString *fmt, ...) {
    if (!logPath) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docDir = [paths firstObject];
        logPath = [docDir stringByAppendingPathComponent:@"kiosker_premium.log"];
    }

    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", 
                      [NSDate date], msg];

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }

    // Also NSLog for console visibility
    NSLog(@"[KioskerPremium] %@", msg);
}

static id kiosker_init(id self, SEL _cmd) {
    fileLog(@"kiosker_init called, self=%p", self);
    self = orig_init(self, _cmd);
    if (self) {
        void *ptr = (__bridge void *)self;
        uint8_t *base = (uint8_t *)ptr;
        uint8_t oldState = base[24];
        base[24] = 1;
        fileLog(@"Patched _state: %d -> 1 at offset +24, self=%p", oldState, self);
    } else {
        fileLog(@"init returned nil");
    }
    return self;
}

static void tryHook() {
    fileLog(@"tryHook called");

    Class cls = NSClassFromString(@"_TtC7Kiosker19SubscriptionHandler");
    if (!cls) {
        fileLog(@"SubscriptionHandler class NOT FOUND yet");
        return;
    }
    fileLog(@"Found class: %@", cls);

    Method m = class_getInstanceMethod(cls, @selector(init));
    if (!m) {
        fileLog(@"init method NOT FOUND");
        return;
    }
    fileLog(@"Found init method");

    IMP current = method_getImplementation(m);
    if (current == (IMP)kiosker_init) {
        fileLog(@"Already hooked, skipping");
        return;
    }

    orig_init = (id (*)(id, SEL))current;
    method_setImplementation(m, (IMP)kiosker_init);
    fileLog(@"HOOKED init: orig=%p, new=%p", orig_init, kiosker_init);
}

__attribute__((constructor))
static void constructor() {
    @autoreleasepool {
        fileLog(@"=== constructor started ===");

        // Try immediately
        tryHook();

        // If class not found, retry every 0.5s for 5 seconds
        // Swift classes may be loaded lazily
        if (!NSClassFromString(@"_TtC7Kiosker19SubscriptionHandler")) {
            fileLog(@"Class not found, starting retry loop");
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                for (int i = 0; i < 10; i++) {
                    [NSThread sleepForTimeInterval:0.5];
                    tryHook();
                    if (NSClassFromString(@"_TtC7Kiosker19SubscriptionHandler")) {
                        break;
                    }
                }
            });
        }
    }
}
