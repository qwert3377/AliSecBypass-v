// EmptyTweak.mm
// 纯注入测试文件，不做任何 hook，仅验证注入本身是否导致崩溃
// 用于 TrollStore 环境注入测试

#import <Foundation/Foundation.h>

__attribute__((constructor))
static void EmptyTweakInit(void) {
    // 什么都不做，仅作为注入入口存在
    // 如果 App 注入后崩溃，说明注入框架/环境有问题，而非代码逻辑导致
}
