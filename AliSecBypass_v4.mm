//
//  KuwoVIPCrack.mm
//  酷我音乐VIP破解 - TrollStore注入版
//  注入已验证生效
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#pragma mark - 配置

static NSString *kFake = @"{\"ctime\":2000000000,\"data\":{\"uid\":\"0\",\"vipExpire\":\"2000000000\",\"svipExpire\":\"2000000000\",\"vipmExpire\":\"2000000000\",\"level\":\"10\",\"curVipValue\":\"99999\",\"starvipLevel\":\"10\",\"starvipType\":\"3\",\"userType\":\"3\",\"isYearUser\":\"1\",\"isNewUser\":\"0\",\"vipTag\":\"SVIP\",\"cloakingStatus\":\"1\",\"status\":\"1\",\"isSign\":\"1\",\"isGift\":\"1\",\"isLook\":\"1\",\"biedAlbum\":\"1\",\"biedSong\":\"1\",\"luxVipDays\":\"9999\",\"cheZaiDays\":\"9999\",\"vipmDays\":\"9999\",\"svipDays\":\"9999\"},\"meta\":{\"code\":200}}";

static BOOL isVIPKey(NSString *k) {
    return k && ([k rangeOfString:@"VIP_INFO"].location != NSNotFound || [k rangeOfString:@"vip_info"].location != NSNotFound);
}

static BOOL isVIPUrl(NSString *u) {
    return u && [u rangeOfString:@"isVip=0" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static id fakeDict() {
    static id d = nil;
    static dispatch_once_t o;
    dispatch_once(&o, ^{
        NSData *data = [kFake dataUsingEncoding:NSUTF8StringEncoding];
        d = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    });
    return d;
}

#pragma mark - Hook

static __thread BOOL gIn = NO;
#define GB if(gIn)return nil;gIn=YES;
#define GBV if(gIn)return;gIn=YES;
#define GE gIn=NO;

// NSUserDefaults objectForKey:
typedef id (*ofk_t)(id,SEL,id); static ofk_t o_ofk = NULL;
static id h_ofk(id s, SEL c, id k) {
    GB id r = o_ofk(s,c,k); if(isVIPKey(k)){GE return [kFake copy];} GE return r;
}

// NSUserDefaults stringForKey:
typedef id (*sfk_t)(id,SEL,NSString*); static sfk_t o_sfk = NULL;
static id h_sfk(id s, SEL c, NSString *k) {
    GB id r = o_sfk(s,c,k); if(isVIPKey(k)){GE return [kFake copy];} GE return r;
}

// NSUserDefaults dictionaryForKey:
typedef id (*dfk_t)(id,SEL,NSString*); static dfk_t o_dfk = NULL;
static id h_dfk(id s, SEL c, NSString *k) {
    GB id r = o_dfk(s,c,k); if(isVIPKey(k)){GE return fakeDict()?:r;} GE return r;
}

// NSUserDefaults setObject:forKey:
typedef void (*sok_t)(id,SEL,id,id); static sok_t o_sok = NULL;
static void h_sok(id s, SEL c, id o, id k) {
    GBV if(isVIPKey(k)){GE return;} o_sok(s,c,o,k); GE
}

// NSJSONSerialization
typedef id (*js_t)(Class,SEL,NSData*,NSJSONReadingOptions,NSError**); static js_t o_js = NULL;
static id h_js(Class cls, SEL c, NSData *d, NSJSONReadingOptions opt, NSError **e) {
    id r = o_js(cls,c,d,opt,e);
    if (![r isKindOfClass:[NSDictionary class]]) return r;
    NSDictionary *dict = r;
    id dataObj = dict[@"data"];
    NSDictionary *dd = dataObj && [dataObj isKindOfClass:[NSDictionary class]] ? dataObj : dict;
    if (!dd[@"vipExpire"] && !dd[@"expireTime"] && !dd[@"level"]) return r;

    NSMutableDictionary *nd = [NSMutableDictionary dictionaryWithDictionary:dict];
    NSMutableDictionary *ndd = dataObj ? [NSMutableDictionary dictionaryWithDictionary:dd] : nd;

    NSArray *tk = @[@"expireTime",@"vipExpire",@"svipExpire",@"vipmExpire",@"chezaiExpire",@"experienceExpire",@"vipWatch1Expire",@"vipAdExpire",@"vipLuxuryExpire",@"vipSpeakerExpire",@"vipOverSeasExpire",@"time"];
    for (NSString *k in tk) { id v=ndd[k]; if(!v)continue; int n=[v intValue]; if(n>0&&n<2000000000){ndd[k]=@2000000000;} }

    NSArray *dk = @[@"luxVipDays",@"cheZaiDays",@"vipmDays",@"svipDays"];
    for (NSString *k in dk) { id v=ndd[k]; if(!v)continue; int n=[v intValue]; if(n<9999){ndd[k]=@9999;} }

    NSArray *lk = @[@"level",@"curVipValue",@"starvipLevel"];
    for (NSString *k in lk) { id v=ndd[k]; if(!v)continue; int n=[v intValue]; if(n<10){ndd[k]=@10;} }

    id st=ndd[@"starvipType"]; if(st&&[st intValue]<3){ndd[@"starvipType"]=@3;}
    id ut=ndd[@"userType"]; if(ut){int n=[ut intValue]; if(n==0||n==2){ndd[@"userType"]=@3;}}

    NSArray *fk = @[@"cloakingStatus",@"status",@"isSign",@"isGift",@"isLook",@"isYearUser",@"isNewUser",@"biedAlbum",@"biedSong"];
    for (NSString *k in fk) { id v=ndd[k]; if(!v)continue; if([v intValue]==0){ndd[k]=@1;} }

    NSString *tag=ndd[@"vipTag"];
    if([tag isKindOfClass:[NSString class]]&&[tag rangeOfString:@"VIP"].location!=NSNotFound&&[tag rangeOfString:@"SVIP"].location==NSNotFound){ndd[@"vipTag"]=@"SVIP";}

    if(dataObj) nd[@"data"]=ndd;
    return nd;
}

// NSURLSession
typedef id (*dt_t)(id,SEL,NSURLRequest*); static dt_t o_dt = NULL;
static id h_dt(id s, SEL c, NSURLRequest *req) {
    NSString *u = req.URL.absoluteString;
    if (isVIPUrl(u)) {
        NSString *nu = [u stringByReplacingOccurrencesOfString:@"isVip=0" withString:@"isVip=1" options:NSCaseInsensitiveSearch range:NSMakeRange(0,u.length)];
        NSMutableURLRequest *nr = [req mutableCopy]; nr.URL = [NSURL URLWithString:nu];
        return o_dt(s,c,nr);
    }
    return o_dt(s,c,req);
}

#pragma mark - 工具

static void hIM(Class c, SEL s, IMP n, IMP *o) {
    Method m = class_getInstanceMethod(c, s);
    if (m) *o = method_setImplementation(m, n);
}
static void hCM(Class c, SEL s, IMP n, IMP *o) {
    Method m = class_getClassMethod(c, s);
    if (m) *o = method_setImplementation(m, n);
}

#pragma mark - 入口

__attribute__((constructor))
static void init(void) {
    // 预注入NSUserDefaults
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    for (NSString *k in [defs dictionaryRepresentation].allKeys) {
        if (isVIPKey(k)) { [defs setObject:kFake forKey:k]; }
    }
    [defs synchronize];

    // Hook
    Class ud = [NSUserDefaults class];
    hIM(ud, @selector(objectForKey:), (IMP)h_ofk, (IMP*)&o_ofk);
    hIM(ud, @selector(stringForKey:), (IMP)h_sfk, (IMP*)&o_sfk);
    hIM(ud, @selector(dictionaryForKey:), (IMP)h_dfk, (IMP*)&o_dfk);
    hIM(ud, @selector(setObject:forKey:), (IMP)h_sok, (IMP*)&o_sok);
    hCM([NSJSONSerialization class], @selector(JSONObjectWithData:options:error:), (IMP)h_js, (IMP*)&o_js);
    hIM([NSURLSession class], @selector(dataTaskWithRequest:), (IMP)h_dt, (IMP*)&o_dt);
}
