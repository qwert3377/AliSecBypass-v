// AlohaVPNProbe.mm - TrollStore 注入插件
// 用于探测 Aloha 浏览器的 VPN 配置结构

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <os/log.h>

#define LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[AlohaVPNProbe] " fmt, ##__VA_ARGS__)

// ============ 辅助函数 ============

static void dumpClassMethods(Class cls) {
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    LOG("Class: %s, Methods: %d", class_getName(cls), count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        LOG("  Method: %s", sel_getName(sel));
    }
    free(methods);
    
    // Dump properties
    unsigned int propCount = 0;
    objc_property_t *props = class_copyPropertyList(cls, &propCount);
    LOG("  Properties: %d", propCount);
    for (unsigned int i = 0; i < propCount; i++) {
        LOG("    Property: %s", property_getName(props[i]));
    }
    free(props);
    
    // Dump ivars
    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(cls, &ivarCount);
    LOG("  IVars: %d", ivarCount);
    for (unsigned int i = 0; i < ivarCount; i++) {
        LOG("    IVar: %s", ivar_getName(ivars[i]));
    }
    free(ivars);
}

// ============ Hook ShadowsocksDeviceInfo ============

static Class g_ShadowsocksDeviceInfoClass = nil;

static id (*orig_ShadowsocksDeviceInfo_init)(id self, SEL _cmd);
static id hook_ShadowsocksDeviceInfo_init(id self, SEL _cmd) {
    id result = orig_ShadowsocksDeviceInfo_init(self, _cmd);
    LOG("ShadowsocksDeviceInfo init called, instance: %p", result);
    
    // Dump all properties
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(g_ShadowsocksDeviceInfoClass, &count);
    for (unsigned int i = 0; i < count; i++) {
        const char *name = property_getName(props[i]);
        SEL getter = NSSelectorFromString([NSString stringWithUTF8String:name]);
        if ([result respondsToSelector:getter]) {
            id value = [result performSelector:getter];
            LOG("  %s = %@", name, value);
        }
    }
    free(props);
    
    return result;
}

// ============ Hook VpnUserDefaults ============

static Class g_VpnUserDefaultsClass = nil;

static id (*orig_VpnUserDefaults_init)(id self, SEL _cmd);
static id hook_VpnUserDefaults_init(id self, SEL _cmd) {
    id result = orig_VpnUserDefaults_init(self, _cmd);
    LOG("VpnUserDefaults init called, instance: %p", result);
    
    dumpClassMethods(g_VpnUserDefaultsClass);
    
    return result;
}

// ============ Hook NSUserDefaults 读取 VPN 配置 ============

static id (*orig_objectForKey)(id self, SEL _cmd, NSString *key);
static id hook_objectForKey(id self, SEL _cmd, NSString *key) {
    id result = orig_objectForKey(self, _cmd, key);
    
    // 过滤 VPN 相关 key
    if (key && (
        [key containsString:@"vpn"] ||
        [key containsString:@"VPN"] ||
        [key containsString:@"shadow"] ||
        [key containsString:@"Shadow"] ||
        [key containsString:@"server"] ||
        [key containsString:@"Server"] ||
        [key containsString:@"proxy"] ||
        [key containsString:@"Proxy"]
    )) {
        LOG("NSUserDefaults objectForKey: %@ = %@", key, result);
    }
    
    return result;
}

// ============ Hook AlohaApiOS (网络层) ============

static Class g_AlohaApiOSClass = nil;

static id (*orig_AlohaApiOS_init)(id self, SEL _cmd);
static id hook_AlohaApiOS_init(id self, SEL _cmd) {
    id result = orig_AlohaApiOS_init(self, _cmd);
    LOG("AlohaApiOS init called, instance: %p", result);
    dumpClassMethods(g_AlohaApiOSClass);
    return result;
}

// ============ 构造函数 ============

__attribute__((constructor))
static void init() {
    LOG("AlohaVPNProbe loaded!");
    
    // 查找目标类
    g_ShadowsocksDeviceInfoClass = objc_getClass("_TtC7CoreVPNP33_AC12579CE61CDD2599F6987E0CB79D9821ShadowsocksDeviceInfo");
    g_VpnUserDefaultsClass = objc_getClass("_TtC7CoreVPN15VpnUserDefaults");
    g_AlohaApiOSClass = objc_getClass("_TtC4HTTP10AlohaApiOS");
    
    LOG("ShadowsocksDeviceInfo class: %p", g_ShadowsocksDeviceInfoClass);
    LOG("VpnUserDefaults class: %p", g_VpnUserDefaultsClass);
    LOG("AlohaApiOS class: %p", g_AlohaApiOSClass);
    
    // Hook ShadowsocksDeviceInfo init
    if (g_ShadowsocksDeviceInfoClass) {
        Method m = class_getInstanceMethod(g_ShadowsocksDeviceInfoClass, @selector(init));
        if (m) {
            orig_ShadowsocksDeviceInfo_init = (id (*)(id, SEL))method_setImplementation(m, (IMP)hook_ShadowsocksDeviceInfo_init);
            LOG("Hooked ShadowsocksDeviceInfo init");
        }
        dumpClassMethods(g_ShadowsocksDeviceInfoClass);
    }
    
    // Hook VpnUserDefaults init
    if (g_VpnUserDefaultsClass) {
        Method m = class_getInstanceMethod(g_VpnUserDefaultsClass, @selector(init));
        if (m) {
            orig_VpnUserDefaults_init = (id (*)(id, SEL))method_setImplementation(m, (IMP)hook_VpnUserDefaults_init);
            LOG("Hooked VpnUserDefaults init");
        }
    }
    
    // Hook NSUserDefaults
    Class udClass = [NSUserDefaults class];
    Method udM = class_getInstanceMethod(udClass, @selector(objectForKey:));
    if (udM) {
        orig_objectForKey = (id (*)(id, SEL, NSString *))method_setImplementation(udM, (IMP)hook_objectForKey);
        LOG("Hooked NSUserDefaults objectForKey:");
    }
    
    // Hook AlohaApiOS
    if (g_AlohaApiOSClass) {
        Method m = class_getInstanceMethod(g_AlohaApiOSClass, @selector(init));
        if (m) {
            orig_AlohaApiOS_init = (id (*)(id, SEL))method_setImplementation(m, (IMP)hook_AlohaApiOS_init);
            LOG("Hooked AlohaApiOS init");
        }
    }
    
    LOG("All hooks installed!");
}
